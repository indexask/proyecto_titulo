// Pruebas de las reglas de costo. Ejecutar con:
//   deno test supabase/functions/optimizar-ruta/costos_test.ts
// o con Node ≥ 23:  node --test supabase/functions/optimizar-ruta/costos_test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  costoRecorrido,
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

test("explica por qué se aceptó o rechazó el TAG", () => {
  const libre = { distanciaMetros: 20_000, duracionSegundos: 50 * 60, peajesClp: 0 };
  assert.match(
    explicarEleccion({ distanciaMetros: 20_000, duracionSegundos: 30 * 60, peajesClp: 900 }, libre),
    /^Se usa TAG: ahorra 20 min por \$900 extra/,
  );
  assert.match(
    explicarEleccion({ distanciaMetros: 20_000, duracionSegundos: 30 * 60, peajesClp: 1_500 }, libre),
    /^Se evita el TAG: ahorraría 20 min pero cuesta \$1\.500 extra/,
  );
  assert.equal(explicarEleccion(libre, libre), "El recorrido óptimo no pasa por autopistas con TAG.");
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
