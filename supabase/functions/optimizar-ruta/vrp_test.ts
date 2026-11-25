// node --test supabase/functions/optimizar-ruta/vrp_test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { asignarLotes, costoCircuito, dosOpt, ordenarLote, vecinoMasCercano } from "./vrp.ts";
import type { MatrizCostos } from "./vrp.ts";

/** Matriz euclidiana a partir de coordenadas (nodo 0 = bodega). */
function matriz(puntos: [number, number][]): MatrizCostos {
  return puntos.map(([x1, y1]) => puntos.map(([x2, y2]) => Math.hypot(x1 - x2, y1 - y2)));
}

test("vecino más cercano visita siempre la parada más cercana", () => {
  //            bodega   A      B      C
  const m = matriz([[0, 0], [1, 0], [5, 0], [2, 0]]);
  assert.deepEqual(vecinoMasCercano(m, 0, [1, 2, 3]), [1, 3, 2]);
});

test("2-opt elimina un cruce y nunca empeora el recorrido", () => {
  // Cuadrado: el orden 1-3-2-4 se cruza; el óptimo es recorrer el borde.
  const m = matriz([[0, 0], [0, 1], [1, 1], [1, 0], [0.5, -0.1]]);
  const cruzado = [1, 3, 2, 4];
  const { orden, mejoras } = dosOpt(m, cruzado);
  assert.ok(mejoras >= 1);
  assert.ok(costoCircuito(m, orden) < costoCircuito(m, cruzado));
  assert.ok(costoCircuito(m, orden) <= costoCircuito(m, [1, 2, 3, 4]) + 1e-9);
});

test("2-opt mejora o iguala al vecino más cercano en casos aleatorios", () => {
  let semilla = 7;
  const azar = () => ((semilla = (semilla * 16807) % 2147483647) / 2147483647);
  for (let caso = 0; caso < 30; caso++) {
    const puntos: [number, number][] = Array.from({ length: 12 }, () => [azar() * 10, azar() * 10]);
    const m = matriz(puntos);
    const r = ordenarLote(m, [], puntos.slice(1).map((_, i) => i + 1));
    assert.ok(r.costo2opt <= r.costoVecino + 1e-9, `caso ${caso}`);
    assert.equal(new Set(r.orden).size, 11);
  }
});

test("el plazo manda: las urgentes van primero aunque estén más lejos", () => {
  // Urgente (3) está lejos; las cercanas (1, 2) deben ir después.
  const m = matriz([[0, 0], [1, 0], [2, 0], [9, 9]]);
  const r = ordenarLote(m, [3], [1, 2]);
  assert.equal(r.orden[0], 3);
  assert.deepEqual([...r.orden.slice(1)].sort(), [1, 2]);
});

test("VRP: reparte en lotes equilibrados por zona y cubre todas las paradas", () => {
  // Bodega al centro; 3 paradas al norte y 3 al sur.
  const coords: [number, number][] = [[0, 0], [-1, 5], [0, 6], [1, 5], [-1, -5], [0, -6], [1, -5]];
  const m = matriz(coords);
  const paradas = coords.slice(1).map(([x, y], i) => ({ nodo: i + 1, lng: x, lat: y, urgente: false }));
  const { lotes } = asignarLotes(m, { lng: 0, lat: 0 }, paradas, 2);
  assert.equal(lotes.length, 2);
  assert.deepEqual(lotes.map((l) => l.orden.length).sort(), [3, 3]);
  const norte = lotes.find((l) => l.orden.includes(2))!;
  assert.deepEqual([...norte.orden].sort(), [1, 2, 3]); // no mezcla norte con sur
  assert.deepEqual(lotes.flatMap((l) => l.orden).sort(), [1, 2, 3, 4, 5, 6]);
});

test("VRP con un solo chofer equivale a una ruta", () => {
  const coords: [number, number][] = [[0, 0], [1, 1], [2, 0], [1, -1]];
  const m = matriz(coords);
  const paradas = coords.slice(1).map(([x, y], i) => ({ nodo: i + 1, lng: x, lat: y, urgente: false }));
  const { lotes } = asignarLotes(m, { lng: 0, lat: 0 }, paradas, 1);
  assert.equal(lotes.length, 1);
  assert.equal(lotes[0].orden.length, 3);
});

test("VRP con más choferes que paradas no crea rutas vacías", () => {
  const m = matriz([[0, 0], [1, 0], [0, 1]]);
  const paradas = [{ nodo: 1, lng: 1, lat: 0, urgente: false }, { nodo: 2, lng: 0, lat: 1, urgente: false }];
  const { lotes } = asignarLotes(m, { lng: 0, lat: 0 }, paradas, 5);
  assert.equal(lotes.length, 2);
  assert.ok(lotes.every((l) => l.orden.length === 1));
});
