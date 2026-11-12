// Extrae del PDF los textos (con posición) y las imágenes embebidas.
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

export async function extraerImagenes(pdfBytes: Uint8Array, libs: LibreriasPdf): Promise<ImagenPdf[]> {
  const { PDFDocument, PDFName, PDFRawStream } = libs;
  const doc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
  const imagenes: ImagenPdf[] = [];

  doc.getPages().forEach((pagina: Lib, indice: number) => {
    const xobjects = pagina.node.Resources()?.lookup(PDFName.of("XObject"));
    if (!xobjects) return;
    for (const [, ref] of xobjects.entries()) {
      const obj = doc.context.lookup(ref);
      if (!(obj instanceof PDFRawStream)) continue;
      const dict = obj.dict;
      if (dict.get(PDFName.of("Subtype"))?.toString() !== "/Image") continue;
      imagenes.push({
        pagina: indice + 1,
        ancho: Number(dict.get(PDFName.of("Width"))?.toString() ?? 0),
        alto: Number(dict.get(PDFName.of("Height"))?.toString() ?? 0),
        filtro: dict.get(PDFName.of("Filter"))?.toString() ?? "",
        bytes: obj.contents,
      });
    }
  });
  return imagenes;
}
