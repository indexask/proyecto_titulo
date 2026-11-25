// Extrae del PDF los textos (con posición) y las imágenes embebidas (con la
// posición en que se dibujan en la página).
// Las librerías se inyectan (unpdf y pdf-lib) para usar exactamente el mismo
// código en la Edge Function (Deno, `npm:`) y en las pruebas (Node).
import type { ImagenPdf, ItemTexto } from "./lector.ts";

// deno-lint-ignore no-explicit-any
type Lib = any;

export interface LibreriasPdf {
  getDocumentProxy: (datos: Uint8Array) => Promise<Lib>;
  PDFDocument: Lib;
  PDFName: Lib;
  PDFRawStream: Lib;
  PDFArray: Lib;
  decodePDFRawStream: (stream: Lib) => { decode(): Uint8Array };
}

export async function extraerTextos(pdfBytes: Uint8Array, libs: LibreriasPdf): Promise<ItemTexto[]> {
  const pdf = await libs.getDocumentProxy(pdfBytes.slice());
  const items: ItemTexto[] = [];
  for (let pagina = 1; pagina <= pdf.numPages; pagina++) {
    const contenido = await (await pdf.getPage(pagina)).getTextContent();
    for (const it of contenido.items) {
      if (typeof it.str === "string" && it.str.trim()) {
        items.push({ texto: it.str, x: it.transform[4], y: it.transform[5], pagina });
      }
    }
  }
  return items;
}

type Matriz = [number, number, number, number, number, number];

const multiplicar = (m: Matriz, n: Matriz): Matriz => [
  m[0] * n[0] + m[1] * n[2],
  m[0] * n[1] + m[1] * n[3],
  m[2] * n[0] + m[3] * n[2],
  m[2] * n[1] + m[3] * n[3],
  m[4] * n[0] + m[5] * n[2] + n[4],
  m[4] * n[1] + m[5] * n[3] + n[5],
];

/**
 * Recorre el contenido de una página y devuelve, para cada imagen dibujada
 * (operador `Do`), el borde superior de su posición en la página. Solo se
 * interpretan los operadores de transformación (q, Q, cm, Do); el texto y
 * las cadenas se saltan.
 */
export function posicionesDeImagenes(contenido: string): Map<string, { arriba: number; izquierda: number }> {
  const posiciones = new Map<string, { arriba: number; izquierda: number }>();
  const pila: Matriz[] = [];
  let ctm: Matriz = [1, 0, 0, 1, 0, 0];
  let operandos: (number | string)[] = [];
  let i = 0;
  const n = contenido.length;
  const esBlanco = (c: string) => c === " " || c === "\n" || c === "\r" || c === "\t" || c === "\f" || c === "\0";
  const esDelimitador = (c: string) => "()<>[]{}/%".includes(c) || esBlanco(c);

  while (i < n) {
    const c = contenido[i];
    if (esBlanco(c)) { i++; continue; }
    if (c === "%") { while (i < n && contenido[i] !== "\n" && contenido[i] !== "\r") i++; continue; }
    if (c === "(") {
      // Cadena literal: se salta respetando paréntesis anidados y escapes.
      let nivel = 1; i++;
      while (i < n && nivel > 0) {
        if (contenido[i] === "\\") i += 2;
        else { if (contenido[i] === "(") nivel++; else if (contenido[i] === ")") nivel--; i++; }
      }
      operandos.push("(cadena)");
      continue;
    }
    if (c === "<") {
      if (contenido[i + 1] === "<") { i += 2; continue; } // diccionario en línea
      while (i < n && contenido[i] !== ">") i++;
      i++; operandos.push("<hex>"); continue;
    }
    if (c === ">" || c === "[" || c === "]" || c === "{" || c === "}") { i++; continue; }
    if (c === "/") {
      let j = i + 1;
      while (j < n && !esDelimitador(contenido[j])) j++;
      operandos.push(contenido.slice(i, j)); i = j; continue;
    }
    let j = i;
    while (j < n && !esDelimitador(contenido[j])) j++;
    if (j === i) { i++; continue; }
    const token = contenido.slice(i, j);
    i = j;
    const numero = Number(token);
    if (!Number.isNaN(numero) && /^[+-]?(\d+\.?\d*|\.\d+)$/.test(token)) { operandos.push(numero); continue; }

    // Operador
    if (token === "q") pila.push(ctm);
    else if (token === "Q") ctm = pila.pop() ?? [1, 0, 0, 1, 0, 0];
    else if (token === "cm") {
      const m = operandos.slice(-6);
      if (m.length === 6 && m.every((v) => typeof v === "number")) ctm = multiplicar(m as Matriz, ctm);
    } else if (token === "Do") {
      const nombre = operandos[operandos.length - 1];
      if (typeof nombre === "string" && nombre.startsWith("/") && !posiciones.has(nombre)) {
        // La imagen ocupa el cuadrado unitario transformado por la CTM.
        const arriba = Math.max(ctm[5], ctm[5] + ctm[3], ctm[5] + ctm[1], ctm[5] + ctm[1] + ctm[3]);
        const izquierda = Math.min(ctm[4], ctm[4] + ctm[0], ctm[4] + ctm[2]);
        posiciones.set(nombre, { arriba, izquierda });
      }
    } else if (token === "BI") {
      // Imagen en línea: se salta hasta EI.
      const fin = contenido.indexOf("EI", i);
      i = fin < 0 ? n : fin + 2;
    }
    operandos = [];
  }
  return posiciones;
}

function contenidoDePagina(pagina: Lib, libs: LibreriasPdf): string {
  const { PDFArray, PDFRawStream, decodePDFRawStream } = libs;
  const contexto = pagina.doc.context;
  const contents = pagina.node.Contents?.();
  if (!contents) return "";
  const streams = contents instanceof PDFArray
    ? contents.asArray().map((r: Lib) => contexto.lookup(r))
    : [contents];
  let texto = "";
  for (const s of streams) {
    if (!(s instanceof PDFRawStream)) continue;
    const bytes = decodePDFRawStream(s).decode();
    let parte = "";
    for (let k = 0; k < bytes.length; k++) parte += String.fromCharCode(bytes[k]);
    texto += parte + "\n";
  }
  return texto;
}

export async function extraerImagenes(pdfBytes: Uint8Array, libs: LibreriasPdf): Promise<ImagenPdf[]> {
  const { PDFDocument, PDFName, PDFRawStream } = libs;
  const doc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
  const imagenes: ImagenPdf[] = [];

  doc.getPages().forEach((pagina: Lib, indice: number) => {
    const xobjects = pagina.node.Resources()?.lookup(PDFName.of("XObject"));
    if (!xobjects) return;

    let posiciones = new Map<string, { arriba: number; izquierda: number }>();
    try {
      posiciones = posicionesDeImagenes(contenidoDePagina(pagina, libs));
    } catch {
      // Sin posiciones: se usará el orden de los recursos.
    }

    let orden = 0;
    for (const [clave, ref] of xobjects.entries()) {
      const obj = doc.context.lookup(ref);
      orden++;
      if (!(obj instanceof PDFRawStream)) continue;
      const dict = obj.dict;
      if (dict.get(PDFName.of("Subtype"))?.toString() !== "/Image") continue;
      const pos = posiciones.get(clave.toString());
      imagenes.push({
        pagina: indice + 1,
        ancho: Number(dict.get(PDFName.of("Width"))?.toString() ?? 0),
        alto: Number(dict.get(PDFName.of("Height"))?.toString() ?? 0),
        filtro: dict.get(PDFName.of("Filter"))?.toString() ?? "",
        bytes: obj.contents,
        arriba: pos?.arriba,
        izquierda: pos?.izquierda,
        ordenRecurso: orden,
      });
    }
  });
  return imagenes;
}
