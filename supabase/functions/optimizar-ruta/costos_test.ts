// Pruebas de las reglas de costo. Ejecutar con:
//   deno test supabase/functions/optimizar-ruta/costos_test.ts
// o con Node ≥ 23:  node --test supabase/functions/optimizar-ruta/costos_test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  costoRecorrido,
  elegirMejor,
  elegirRecorrido,
  explicarEleccion,
  resumenRecorrido,
  separarPorPlazo,
} from "./costos.ts";

test("resumen de recorrido: km, minutos, TAG y combustible", () => {
  assert.deepEqual(resumenRecorrido({ distanciaMetros: 45_300, duracionSegundos: 4_250, peajesClp: 1_830.4 }), {
    distanciaKm: 45.3,
    duracionMin: 71,
    peajesClp: 1_830,
    combustibleClp: 6_402, // 45,3 / 9 × 1.272
    costoClp: 8_233,
  });
});

// Caso real de la jornada 12-11-2026 (Maipú → Providencia → La Reina):
// Google optimizó por tiempo y la ruta "optimizada" salía más cara.
const ordenPorPlazo = { etiqueta: "Orden por plazo", distanciaMetros: 56_200, duracionSegundos: 82 * 60, peajesClp: 0 };
const optConTag = { etiqueta: "Optimizada · permite TAG", distanciaMetros: 61_600, duracionSegundos: 77 * 60, peajesClp: 0 };
const optSinTag = { etiqueta: "Optimizada · evita TAG", distanciaMetros: 60_900, duracionSegundos: 95 * 60, peajesClp: 0 };

test("caso real: 5 min menos no justifican $764 más → se queda el orden por plazo", () => {
  // Ahorrar 5 min permite pagar hasta $250 extra; la optimizada cuesta ~$763 más (con km redondeados).
  assert.equal(elegirMejor([ordenPorPlazo, optConTag, optSinTag]), ordenPorPlazo);
});

test("elegirMejor coincide con la regla de a pares", () => {
  const casos = [
    [{ distanciaMetros: 20_000, duracionSegundos: 30 * 60, peajesClp: 900 }, { distanciaMetros: 20_000, duracionSegundos: 50 * 60, peajesClp: 0 }],
    [{ distanciaMetros: 20_000, duracionSegundos: 30 * 60, peajesClp: 1_000 }, { distanciaMetros: 20_000, duracionSegundos: 50 * 60, peajesClp: 0 }],
    [{ distanciaMetros: 10_000, duracionSegundos: 600, peajesClp: 0 }, { distanciaMetros: 15_000, duracionSegundos: 900, peajesClp: 0 }],
  ];
  for (const [a, b] of casos) assert.equal(elegirMejor([a, b]), elegirRecorrido(a, b));
});

test("explica la elección frente a la más rápida y la más barata", () => {
  assert.match(
    explicarEleccion([ordenPorPlazo, optConTag, optSinTag], ordenPorPlazo),
    /^Se eligió "Orden por plazo"\. "Optimizada · permite TAG" ahorraría 5 min pero cuesta \$763 más, sobre el máximo aceptado \(\$250/,
  );
  const tagRapido = { etiqueta: "Optimizada · permite TAG", distanciaMetros: 20_000, duracionSegundos: 30 * 60, peajesClp: 900 };
  const libre = { etiqueta: "Optimizada · evita TAG", distanciaMetros: 20_000, duracionSegundos: 50 * 60, peajesClp: 0 };
  assert.match(explicarEleccion([tagRapido, libre], tagRapido), /ahorra 20 min frente a "Optimizada · evita TAG" por \$900 más, bajo el máximo aceptado \(\$1\.000/);
  assert.match(explicarEleccion([libre, { ...libre, etiqueta: "x" }], libre), /Ninguna alternativa pasa por autopistas con TAG/);
});

test("plazo: lo que vence en la jornada (o ya venció) va primero", () => {
  const paradas = [
    { id: "manana", fechaComprometida: "2026-11-13" },
    { id: "hoy", fechaComprometida: "2026-11-12" },
    { id: "atrasada", fechaComprometida: "2026-11-10" },
  ];
  const r = separarPorPlazo(paradas, "2026-11-12");
  assert.deepEqual(r.urgentes.map((p) => p.id), ["hoy", "atrasada"]);
  assert.deepEqual(r.resto.map((p) => p.id), ["manana"]);
  assert.deepEqual(r.vencidas.map((p) => p.id), ["atrasada"]);
});

test("costo: 90 km sin peajes = 10 L × $1.272", () => {
  assert.equal(costoRecorrido({ distanciaMetros: 90_000, duracionSegundos: 0, peajesClp: 0 }), 12_720);
});

test("costo: suma peajes", () => {
  assert.equal(costoRecorrido({ distanciaMetros: 9_000, duracionSegundos: 0, peajesClp: 1_500 }), 2_772);
});

test("regla: acepta desvío con peaje si cuesta < $500 por cada 10 min ahorrados", () => {
  const conPeaje = { id: "peaje", distanciaMetros: 20_000, duracionSegundos: 30 * 60, peajesClp: 900 };
  const sinPeaje = { id: "libre", distanciaMetros: 20_000, duracionSegundos: 50 * 60, peajesClp: 0 };
  // Ahorra 20 min → límite $1.000; costo adicional $900 → se acepta.
  assert.equal(elegirRecorrido(conPeaje, sinPeaje).id, "peaje");
});

test("regla: rechaza desvío si el costo adicional alcanza el límite", () => {
  const conPeaje = { id: "peaje", distanciaMetros: 20_000, duracionSegundos: 30 * 60, peajesClp: 1_000 };
  const sinPeaje = { id: "libre", distanciaMetros: 20_000, duracionSegundos: 50 * 60, peajesClp: 0 };
  assert.equal(elegirRecorrido(conPeaje, sinPeaje).id, "libre");
});

test("regla: si la alternativa rápida también es más barata, se elige", () => {
  const a = { id: "a", distanciaMetros: 10_000, duracionSegundos: 600, peajesClp: 0 };
  const b = { id: "b", distanciaMetros: 15_000, duracionSegundos: 900, peajesClp: 0 };
  assert.equal(elegirRecorrido(b, a).id, "a");
});
