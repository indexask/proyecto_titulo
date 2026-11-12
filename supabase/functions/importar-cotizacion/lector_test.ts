// node --test supabase/functions/importar-cotizacion/lector_test.ts
// Fixture: posiciones reales de la cotización 5609-132-COT26 (plantilla de
// GyG); los datos bancarios se reemplazaron por valores ficticios.
import { test } from "node:test";
import assert from "node:assert/strict";
import { elegirFotoProducto, leerCotizacion, parsearMonto } from "./lector.ts";
import type { ItemTexto } from "./lector.ts";

const p1 = (x: number, y: number, texto: string): ItemTexto => ({ texto, x, y, pagina: 1 });

const COTIZACION_REAL: ItemTexto[] = [
  p1(177, 734, "G&G Comercial SpA."),
  p1(105, 686, "Cotización"), p1(272, 687, "NºFG-RM-9022"), p1(406, 686, "12-08-2026"),
  p1(55, 661, "RUT:"), p1(156, 661, "77.817.781-1"),
  p1(55, 647, "Dirección:"), p1(156, 647, "Morandé 835 of 518, Santiago Centro."),
  p1(55, 632, "Email:"), p1(156, 632, "CORREO@EJEMPLO.CL"),
  p1(55, 609, "Solicitado por:"), p1(156, 608, "UNIVERSIDAD DE CHILE"),
  p1(55, 594, "Dirección:"), p1(156, 594, "Arturo Bürhle 50, Providencia, Región Metropolitana de Santiago"),
  p1(55, 580, "Cotización"), p1(156, 580, "5609-132-COT26"),
  p1(55, 557, "Condición:"), p1(156, 557, "Credito a 30 días"),
  p1(162, 535, "Descripción"), p1(333, 535, "Unidades"), p1(399, 542, "Precio"), p1(398, 528, "Unidad"),
  p1(478, 535, "Precio"),
  p1(55, 514, "Aspiradora Industrial Polvo / Agua - 80 Lts. 3 Motores -3.000W - Glanz BF585-3"),
  p1(372, 513, "1"), p1(404, 514, "$259.697"), p1(496, 514, "$259.697"),
  p1(174, 252, "Envió Gratis 2 a 5 días hábiles luego de aceptada la OC"),
  p1(383, 237, "Subtotal"), p1(496, 237, "$259.697"),
  p1(383, 221, "IVA 19%"), p1(501, 221, "$49.342"),
  p1(383, 206, "Total"), p1(496, 206, "$309.039"),
  p1(251, 174, "Datos Bancarios"), p1(63, 154, "BANCO: BANCO EJEMPLO"), p1(63, 138, "CUENTA: 0000000"),
  { texto: "Detalles", x: 280, y: 760, pagina: 2 },
];

test("lee todos los campos de la cotización real", () => {
  const d = leerCotizacion(COTIZACION_REAL);
  assert.equal(d.fechaCotizacion, "2026-08-12");
  assert.equal(d.solicitadoPor, "UNIVERSIDAD DE CHILE");
  assert.equal(d.direccion, "Arturo Bürhle 50, Providencia, Región Metropolitana de Santiago");
  assert.equal(d.numeroCotizacion, "5609-132-COT26");
  assert.deepEqual(d.lineas, [{
    descripcion: "Aspiradora Industrial Polvo / Agua - 80 Lts. 3 Motores -3.000W - Glanz BF585-3",
    unidades: 1,
    precioUnidad: 259697,
    total: 259697,
  }]);
  assert.equal(d.subtotal, 259697);
  assert.equal(d.iva, 49342);
  assert.equal(d.totalConIva, 309039);
  assert.deepEqual(d.plazoDiasHabiles, { min: 2, max: 5 });
  assert.deepEqual(d.advertencias, []);
});

test("toma la dirección del cliente, no la de GyG (que va antes)", () => {
  assert.notEqual(leerCotizacion(COTIZACION_REAL).direccion, "Morandé 835 of 518, Santiago Centro.");
});

test("varios productos y descripción en dos líneas", () => {
  const sinTabla = COTIZACION_REAL.filter((i) => i.y > 520 || i.y < 260);
  const d = leerCotizacion([
    ...sinTabla,
    p1(55, 514, "Notebook 14 pulgadas"), p1(372, 513, "3"), p1(404, 514, "$400.000"), p1(496, 514, "$1.200.000"),
    p1(55, 503, "Intel Core i5, 16 GB RAM"),
    p1(55, 492, "Mouse inalámbrico"), p1(372, 491, "10"), p1(404, 492, "$9.000"), p1(496, 492, "$90.000"),
  ].map((i) => (i.texto === "$259.697" && i.y === 237 ? { ...i, texto: "$1.290.000" } : i)));

  assert.deepEqual(d.lineas.map((l) => [l.descripcion, l.unidades, l.precioUnidad, l.total]), [
    ["Notebook 14 pulgadas Intel Core i5, 16 GB RAM", 3, 400000, 1200000],
    ["Mouse inalámbrico", 10, 9000, 90000],
  ]);
  assert.deepEqual(d.advertencias, []);
});

test("advierte si la suma de productos no cuadra con el subtotal", () => {
  const alterada = COTIZACION_REAL.map((i) => (i.y === 237 && i.texto.startsWith("$") ? { ...i, texto: "$999" } : i));
  assert.match(leerCotizacion(alterada).advertencias.join(), /no coincide con el subtotal/);
});

test("un PDF que no es cotización devuelve campos vacíos con advertencias", () => {
  const d = leerCotizacion([p1(50, 700, "Informe mensual"), p1(50, 680, "Texto cualquiera")]);
  assert.equal(d.solicitadoPor, null);
  assert.equal(d.lineas.length, 0);
  assert.ok(d.advertencias.length >= 4);
});

test("número de cotización con distinto largo (1147293-222-COT26)", () => {
  const otra = COTIZACION_REAL.map((i) => (i.texto === "5609-132-COT26" ? { ...i, texto: "1147293-222-COT26" } : i));
  assert.equal(leerCotizacion(otra).numeroCotizacion, "1147293-222-COT26");
});

test("no confunde el N° interno, la fecha ni el RUT con el número de cotización", () => {
  const sinId = COTIZACION_REAL.filter((i) => i.texto !== "5609-132-COT26");
  assert.equal(leerCotizacion(sinId).numeroCotizacion, null); // quedan NºFG-RM-9022, 12-08-2026, 77.817.781-1
});

test("montos en formato chileno", () => {
  assert.equal(parsearMonto("$259.697"), 259697);
  assert.equal(parsearMonto("$1.234.567"), 1234567);
  assert.equal(parsearMonto("1"), 1);
  assert.equal(parsearMonto("IVA 19%"), null);
  assert.equal(parsearMonto("77.817.781-1"), null);
});

test("la foto es la imagen de la página de detalles, no el timbre ni el encabezado", () => {
  const img = (pagina: number, ancho: number, alto: number, filtro = "/DCTDecode") =>
    ({ pagina, ancho, alto, filtro, bytes: new Uint8Array() });
  const foto = elegirFotoProducto([img(1, 844, 163), img(1, 521, 228), img(2, 360, 534)]);
  assert.deepEqual([foto?.pagina, foto?.ancho], [2, 360]);
  assert.equal(elegirFotoProducto([img(1, 844, 163)]), null);
});
