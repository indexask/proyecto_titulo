// Edge Function: importa una cotización de GyG Comercial desde su PDF
// (registro de adjudicación, RF-05/RF-06). Lee los campos de la plantilla
// propia de GyG sin intervención manual y extrae la foto de cada producto.
// No usa IA ni servicios externos: el PDF se procesa dentro de Supabase.
// Solo para el Administrador. No guarda nada: la app muestra los datos para
// confirmarlos y los guarda junto con la orden.
import { getDocumentProxy } from "npm:unpdf@2.1.0";
import { decodePDFRawStream, PDFArray, PDFDocument, PDFName, PDFRawStream } from "npm:pdf-lib@1.17.1";
import { decodeBase64, encodeBase64 } from "jsr:@std/encoding@1/base64";
import { clienteAdministrador, HttpError, json, servir } from "../_shared/comun.ts";
import { extraerImagenes, extraerTextos } from "./extraer.ts";
import type { LibreriasPdf } from "./extraer.ts";
import { elegirFotosProductos, leerCotizacion } from "./lector.ts";

const LIBRERIAS: LibreriasPdf = {
  getDocumentProxy,
  PDFDocument,
  PDFName,
  PDFRawStream,
  PDFArray,
  decodePDFRawStream,
};
const TAMANO_MAXIMO = 10 * 1024 * 1024; // 10 MB

servir(async (req) => {
  await clienteAdministrador(req);

  const { pdfBase64 } = (await req.json()) as { pdfBase64?: string };
  if (!pdfBase64) throw new HttpError(400, "Falta el PDF");

  const bytes = decodeBase64(pdfBase64);
  if (bytes.length > TAMANO_MAXIMO) throw new HttpError(413, "El PDF supera los 10 MB");
  if (new TextDecoder().decode(bytes.slice(0, 5)) !== "%PDF-") {
    throw new HttpError(400, "El archivo no es un PDF");
  }

  const textos = await extraerTextos(bytes, LIBRERIAS);
  if (textos.length === 0) {
    throw new HttpError(422, "El PDF no tiene texto (¿es un escaneo?). Ingresa la orden manualmente.");
  }
  const datos = leerCotizacion(textos);

  // Una foto por producto, en el mismo orden que la tabla.
  let fotos: { base64: string; tipo: string }[] = [];
  try {
    fotos = elegirFotosProductos(await extraerImagenes(bytes, LIBRERIAS))
      .map((i) => ({ base64: encodeBase64(i.bytes), tipo: "image/jpeg" }));
  } catch (e) {
    datos.advertencias.push(`No se pudieron extraer las fotos de los productos (${e})`);
  }
  if (fotos.length === 0) {
    datos.advertencias.push("No se encontraron fotos de los productos");
  } else if (fotos.length !== datos.lineas.length) {
    datos.advertencias.push(
      `La cotización tiene ${datos.lineas.length} producto(s) y ${fotos.length} foto(s): ` +
        "se asignaron en orden; revisa que cada foto corresponda a su producto",
    );
  }

  // `foto` se mantiene por compatibilidad con versiones anteriores de la app.
  return json({ ...datos, fotos, foto: fotos[0] ?? null });
});
