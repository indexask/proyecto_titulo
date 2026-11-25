// node --test supabase/functions/optimizar-ruta/peajes_test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { decodificarPolilinea, detectarCruces, estimarPeajes, tarifaAplicable } from "./peajes.ts";
import type { Portico } from "./peajes.ts";

// PA13 Alameda - Río Mapocho (Autopista Central, sentido sur → norte), tarifas MOP 2026.
const PA13: Portico = {
  concesion: "Autopista Central", codigo: "PA13", tramo: "Alameda - Río Mapocho",
  lat: -33.4400, lng: -70.6600, rumbo: 0, km: 1.75, porKm: false,
  tarifas: { "1": { tbfp: 181.86, tbp: 363.73, ts: 545.60 }, "2": { tbfp: 363.73, tbp: 727.47, ts: 1091.20 } },
  horario: { laboral: { ts: [["08:30", "09:00"]], tbp: [["06:30", "08:30"], ["09:00", "14:00"], ["17:00", "19:00"]] } },
};
// Pórtico de la calzada contraria, a 25 m (sentido norte → sur).
const PA14: Portico = { ...PA13, codigo: "PA14", tramo: "Río Mapocho - Alameda", lng: -70.65973, rumbo: 180,
  horario: {} };

/** Ruta recta norte-sur o sur-norte que pasa por la longitud indicada. */
const rutaNS = (lng: number, haciaNorte: boolean): [number, number][] => {
  const puntos: [number, number][] = [];
  for (let i = 0; i <= 20; i++) puntos.push([-33.45 + i * 0.001, lng]);
  return haciaNorte ? puntos : puntos.reverse();
};

test("decodifica la polilínea de ejemplo de Google", () => {
  assert.deepEqual(decodificarPolilinea("_p~iF~ps|U_ulLnnqC_mqNvxq`@"), [[38.5, -120.2], [40.7, -120.95], [43.252, -126.453]]);
});

test("geocerca: cruza el pórtico de su sentido y no el de la calzada contraria", () => {
  const haciaNorte = detectarCruces(rutaNS(-70.6600, true), [PA13, PA14]);
  assert.deepEqual(haciaNorte.map((c) => c.portico.codigo), ["PA13"]);
  const haciaSur = detectarCruces(rutaNS(-70.65973, false), [PA13, PA14]);
  assert.deepEqual(haciaSur.map((c) => c.portico.codigo), ["PA14"]);
});

test("geocerca: una ruta que pasa a más de 35 m no cruza el pórtico", () => {
  assert.equal(detectarCruces(rutaNS(-70.6610, true), [PA13]).length, 0); // ~93 m al oeste
});

test("tarifa según la hora: TBFP, TBP y TS (día laboral)", () => {
  const a = (h: number, m = 0) => h * 60 + m;
  assert.deepEqual(tarifaAplicable(PA13, 3, a(5), "1"), { tipo: "TBFP", monto: 181.86 });
  assert.deepEqual(tarifaAplicable(PA13, 3, a(7, 15), "1"), { tipo: "TBP", monto: 363.73 });
  assert.deepEqual(tarifaAplicable(PA13, 3, a(8, 45), "1"), { tipo: "TS", monto: 545.60 });
  assert.deepEqual(tarifaAplicable(PA13, 3, a(8, 45), "2"), { tipo: "TS", monto: 1091.20 });
  // Domingo sin ventanas propias: TBFP.
  assert.deepEqual(tarifaAplicable(PA13, 0, a(8, 45), "1"), { tipo: "TBFP", monto: 181.86 });
});

test("cálculo dinámico: la hora de paso depende de la distancia recorrida", () => {
  const ruta = rutaNS(-70.6600, true); // ~2,2 km; el pórtico está a ~1,1 km
  const viaje = { distanciaM: 2224, duracionS: 20 * 60, diaSemana: 2, categoria: "1" };
  // Salida 08:25 + ~10 min (mitad de la ruta) ≈ 08:35 → tarifa saturación.
  const r = estimarPeajes(ruta, [PA13], { ...viaje, salidaMinutos: 8 * 60 + 25 });
  assert.equal(r.cruces.length, 1);
  assert.equal(r.cruces[0].hora, "08:34");
  assert.equal(r.cruces[0].tarifa, "TS");
  assert.equal(r.totalClp, 546);
  // La misma ruta saliendo a las 11:00 paga TBP; a las 22:00, TBFP.
  assert.equal(estimarPeajes(ruta, [PA13], { ...viaje, salidaMinutos: 11 * 60 }).cruces[0].tarifa, "TBP");
  assert.equal(estimarPeajes(ruta, [PA13], { ...viaje, salidaMinutos: 22 * 60 }).totalClp, 182);
});

test("ida y vuelta por la misma autopista cobra ambos sentidos", () => {
  const ida = rutaNS(-70.6600, true);
  const vuelta = rutaNS(-70.65973, false);
  const r = estimarPeajes([...ida, ...vuelta], [PA13, PA14], {
    distanciaM: 4500, duracionS: 30 * 60, diaSemana: 2, salidaMinutos: 11 * 60, categoria: "1",
  });
  assert.deepEqual(r.cruces.map((c) => c.codigo), ["PA13", "PA14"]);
});

test("pórticos con cobro por km (Américo Vespucio Oriente)", () => {
  const avo = (codigo: string, lat: number): Portico => ({
    concesion: "Américo Vespucio Oriente", codigo, tramo: "El Salto - Príncipe de Gales", lat, lng: -70.58,
    rumbo: 0, km: 0, porKm: true, tarifas: { "1": { tbfp: 232, tbp: 464 } }, horario: { laboral: { tbp: [["07:30", "09:30"]] } },
  });
  const ruta: [number, number][] = [];
  for (let i = 0; i <= 60; i++) ruta.push([-33.45 + i * 0.001, -70.58]);
  const r = estimarPeajes(ruta, [avo("AVO-I", -33.448), avo("AVO-I", -33.418)], {
    distanciaM: 6670, duracionS: 600, diaSemana: 2, salidaMinutos: 12 * 60, categoria: "1",
  });
  assert.equal(r.cruces.length, 1); // una pasada
  assert.equal(r.cruces[0].tarifa, "POR KM");
  assert.ok(r.cruces[0].monto > 232 * 3 && r.cruces[0].monto < 232 * 3.6); // ~3,3 km × $232
});
