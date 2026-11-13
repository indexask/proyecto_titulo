// Lector de la cotización de GyG Comercial (plantilla propia, PDF con texto).
// Sin dependencias: recibe los textos con su posición en la página y las
// imágenes embebidas, y devuelve los campos de la cotización. Ver lector_test.ts.
//
// Plantilla esperada (página 1):
//   Cotización  Nº...  DD-MM-AAAA
//   Solicitado por: <cliente>
//   Dirección:      <dirección del cliente>      (la de GyG va ANTES, en el encabezado)
//   Cotización      <ID Mercado Público, ej. 5609-132-COT26>
//   Descripción | Unidades | Precio Unidad | Precio
//   <filas de productos>
//   Subtotal / IVA 19% / Total
// La foto del producto es la imagen JPEG de la página de "Detalles".

export interface ItemTexto {
  texto: string;
  x: number;
  y: number; // coordenada PDF: crece hacia arriba
  pagina: number;
}

export interface ImagenPdf {
  pagina: number;
  ancho: number;
  alto: number;
  filtro: string; // "/DCTDecode" = JPEG
  bytes: Uint8Array;
  /** Borde superior donde se dibuja en la página (coordenada PDF), si se pudo leer. */
  arriba?: number;
  izquierda?: number;
  /** Orden en la lista de recursos de la página (respaldo si no hay posición). */
  ordenRecurso?: number;
}

export interface LineaCotizacion {
  descripcion: string;
  unidades: number;
  precioUnidad: number;
  total: number;
}

export interface DatosCotizacion {
  fechaCotizacion: string | null; // YYYY-MM-DD
  solicitadoPor: string | null;
  direccion: string | null;
  numeroCotizacion: string | null;
  lineas: LineaCotizacion[];
  subtotal: number | null; // neto (sin IVA)
  iva: number | null;
  totalConIva: number | null;
  plazoDiasHabiles: { min: number; max: number } | null;
  advertencias: string[];
}

type Fila = { y: number; pagina: number; items: ItemTexto[] };

const TOLERANCIA_Y = 4;

function agruparFilas(items: ItemTexto[]): Fila[] {
  const filas: Fila[] = [];
  const ordenados = items
    .filter((i) => i.texto.trim() !== "")
    .sort((a, b) => a.pagina - b.pagina || b.y - a.y || a.x - b.x);
  for (const item of ordenados) {
    const fila = filas.find((f) => f.pagina === item.pagina && Math.abs(f.y - item.y) <= TOLERANCIA_Y);
    if (fila) fila.items.push(item);
    else filas.push({ y: item.y, pagina: item.pagina, items: [item] });
  }
  for (const f of filas) f.items.sort((a, b) => a.x - b.x);
  return filas;
}

const textoFila = (items: ItemTexto[]) => items.map((i) => i.texto.trim()).join(" ").replace(/\s+/g, " ").trim();

/** "$259.697" → 259697 ; "1.234,5" → 1234.5 ; devuelve null si no es monto. */
export function parsearMonto(texto: string): number | null {
  const limpio = texto.replace(/[\s$]/g, "");
  if (!/^\d{1,3}(\.\d{3})*(,\d+)?$|^\d+(,\d+)?$/.test(limpio)) return null;
  return Number(limpio.replace(/\./g, "").replace(",", "."));
}

/** Busca la fila cuya primera celda coincide con la etiqueta y devuelve el resto. */
function valorDeEtiqueta(filas: Fila[], etiqueta: RegExp): { fila: Fila; valor: string } | null {
  for (const fila of filas) {
    const i = fila.items.findIndex((it) => etiqueta.test(it.texto.trim()));
    if (i >= 0) {
      const valor = textoFila(fila.items.slice(i + 1));
      if (valor) return { fila, valor };
    }
  }
  return null;
}

export function leerCotizacion(items: ItemTexto[]): DatosCotizacion {
  const advertencias: string[] = [];
  const filas = agruparFilas(items);
  const filasP1 = filas.filter((f) => f.pagina === 1);
  const todoElTexto = filas.map((f) => textoFila(f.items)).join("\n");

  // --- Fecha (DD-MM-AAAA del encabezado) -----------------------------------
  const mFecha = filasP1.map((f) => textoFila(f.items)).join("\n").match(/\b(\d{2})[-/](\d{2})[-/](\d{4})\b/);
  const fechaCotizacion = mFecha ? `${mFecha[3]}-${mFecha[2]}-${mFecha[1]}` : null;

  // --- Solicitado por / Dirección del cliente ------------------------------
  const solicitado = valorDeEtiqueta(filasP1, /^solicitado\s+por:?$/i);
  const direcciones = filasP1
    .map((f) => ({ f, i: f.items.findIndex((it) => /^direcci[oó]n:?$/i.test(it.texto.trim())) }))
    .filter(({ i }) => i >= 0)
    .map(({ f, i }) => ({ y: f.y, valor: textoFila(f.items.slice(i + 1)) }))
    .filter((d) => d.valor);
  // La dirección del cliente es la que aparece debajo de "Solicitado por".
  const direccionCliente = solicitado
    ? direcciones.filter((d) => d.y < solicitado.fila.y).sort((a, b) => b.y - a.y)[0]
    : direcciones[direcciones.length - 1];

  // --- ID de la cotización (formato Mercado Público: <números>-<números>-<letras><año>,
  // ej. 5609-132-COT26 o 1147293-222-COT26; el largo de cada parte varía) ------
  const mId = todoElTexto.match(/\b\d+-\d+-[A-Z]{2,6}\d{0,4}\b/);
  const numeroCotizacion = mId ? mId[0] : null;

  // --- Tabla de productos ---------------------------------------------------
  const encabezado = filasP1.find((f) => f.items.some((it) => /^descripci[oó]n$/i.test(it.texto.trim())));
  const filaSubtotal = filasP1.find((f) => f.items.some((it) => /^subtotal$/i.test(it.texto.trim())));
  const colUnidades = encabezado?.items.find((it) => /^unidades$/i.test(it.texto.trim()))?.x;

  const lineas: LineaCotizacion[] = [];
  if (encabezado && colUnidades !== undefined) {
    let ultimaY: number | null = null;
    const cuerpo = filasP1.filter(
      (f) => f.y < encabezado.y - TOLERANCIA_Y && (!filaSubtotal || f.y > filaSubtotal.y + TOLERANCIA_Y),
    );
    for (const fila of cuerpo) {
      const desc = textoFila(fila.items.filter((it) => it.x < colUnidades - 15));
      const numeros = fila.items.filter((it) => it.x >= colUnidades - 15);
      const conPeso = numeros.filter((it) => it.texto.includes("$")).map((it) => parsearMonto(it.texto));
      const unidades = numeros.find((it) => !it.texto.includes("$") && parsearMonto(it.texto) !== null);

      if (conPeso.length >= 1 && unidades && desc) {
        const precioUnidad = conPeso[0]!;
        const cantidad = parsearMonto(unidades.texto)!;
        lineas.push({
          descripcion: desc,
          unidades: cantidad,
          precioUnidad,
          total: conPeso.length >= 2 ? conPeso[conPeso.length - 1]! : precioUnidad * cantidad,
        });
        ultimaY = fila.y;
      } else if (desc && numeros.length === 0 && ultimaY !== null && ultimaY - fila.y < 14) {
        // Descripción que continúa en la línea siguiente.
        lineas[lineas.length - 1].descripcion += ` ${desc}`;
        ultimaY = fila.y;
      }
    }
  }

  // --- Totales ----------------------------------------------------------------
  const montoDeFila = (etiqueta: RegExp) => {
    const fila = filasP1.find((f) => f.items.some((it) => etiqueta.test(it.texto.trim())));
    const m = fila?.items.map((it) => parsearMonto(it.texto)).filter((v) => v !== null);
    return m?.length ? m[m.length - 1]! : null;
  };
  const subtotal = montoDeFila(/^subtotal$/i);
  const iva = montoDeFila(/^iva/i);
  const totalConIva = montoDeFila(/^total$/i);

  // --- Plazo de entrega indicado ("2 a 5 días hábiles") -----------------------
  const mPlazo = todoElTexto.match(/(\d+)\s*(?:a\s*(\d+)\s*)?d[ií]as\s*h[aá]biles/i);
  const plazoDiasHabiles = mPlazo
    ? { min: Number(mPlazo[1]), max: Number(mPlazo[2] ?? mPlazo[1]) }
    : null;

  // --- Advertencias -----------------------------------------------------------
  if (!fechaCotizacion) advertencias.push("No se encontró la fecha de la cotización");
  if (!solicitado) advertencias.push('No se encontró "Solicitado por"');
  if (!direccionCliente) advertencias.push("No se encontró la dirección del cliente");
  if (!numeroCotizacion) advertencias.push("No se encontró el número de cotización");
  if (lineas.length === 0) advertencias.push("No se encontraron productos en la tabla");
  const sumaLineas = lineas.reduce((s, l) => s + l.total, 0);
  if (subtotal !== null && lineas.length && Math.abs(sumaLineas - subtotal) > 1) {
    advertencias.push(`La suma de los productos (${sumaLineas}) no coincide con el subtotal (${subtotal})`);
  }

  return {
    fechaCotizacion,
    solicitadoPor: solicitado?.valor ?? null,
    direccion: direccionCliente?.valor ?? null,
    numeroCotizacion,
    lineas,
    subtotal,
    iva,
    totalConIva,
    plazoDiasHabiles,
    advertencias,
  };
}

/**
 * Fotos de los productos, en el mismo orden que la tabla de la cotización:
 * las imágenes JPEG de las páginas de "Detalles" (desde la página 2; la
 * primera tiene el encabezado y el timbre), de arriba hacia abajo y de
 * izquierda a derecha. Se descartan imágenes muy pequeñas (íconos).
 */
export function elegirFotosProductos(imagenes: ImagenPdf[]): ImagenPdf[] {
  return imagenes
    .filter((i) => i.pagina > 1 && i.filtro === "/DCTDecode" && i.ancho >= 80 && i.alto >= 80)
    .sort((a, b) =>
      a.pagina - b.pagina ||
      // Más arriba primero (en PDF, y mayor = más arriba). Tolerancia de 20 pt
      // para imágenes en la misma fila.
      (Math.abs((b.arriba ?? 0) - (a.arriba ?? 0)) > 20 ? (b.arriba ?? 0) - (a.arriba ?? 0) : 0) ||
      (a.izquierda ?? 0) - (b.izquierda ?? 0) ||
      (a.ordenRecurso ?? 0) - (b.ordenRecurso ?? 0)
    );
}

/** Compatibilidad: la primera foto de producto. */
export function elegirFotoProducto(imagenes: ImagenPdf[]): ImagenPdf | null {
  return elegirFotosProductos(imagenes)[0] ?? null;
}
