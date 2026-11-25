// Motor algorítmico de enrutamiento (RF-21, RF-22). Sin dependencias, para
// probarlo de forma aislada (vrp_test.ts).
//
// 1. VRP (Vehicle Routing Problem): reparte los despachos de la jornada en un
//    lote por chofer con un barrido angular desde la bodega ("sweep"),
//    evaluando cada partición con el costo real de sus rutas.
// 2. Cada lote se ordena con Vecino Más Cercano (heurística constructiva) y se
//    mejora con 2-opt (búsqueda local que elimina cruces).
// 3. El plazo manda: lo que vence en la jornada va primero; 2-opt solo
//    reordena dentro de cada grupo, nunca mueve una parada urgente detrás de
//    una no urgente.
//
// Las distancias/tiempos/peajes vienen de una matriz real por calles
// (Google Route Matrix). Nodo 0 = bodega; nodos 1..n = paradas.

/** Matriz de costos: costo[i][j] de ir del nodo i al j (puede ser asimétrica). */
export type MatrizCostos = number[][];

/** Costo de bodega → paradas en orden → bodega. */
export function costoCircuito(m: MatrizCostos, orden: number[], bodega = 0): number {
  let total = 0;
  let actual = bodega;
  for (const n of orden) {
    total += m[actual][n];
    actual = n;
  }
  return total + m[actual][bodega];
}

/**
 * Vecino Más Cercano: desde [desde], visita siempre la parada pendiente más
 * barata de alcanzar.
 */
export function vecinoMasCercano(m: MatrizCostos, desde: number, nodos: number[]): number[] {
  const pendientes = new Set(nodos);
  const orden: number[] = [];
  let actual = desde;
  while (pendientes.size > 0) {
    let mejor = -1;
    let costoMejor = Infinity;
    for (const n of pendientes) {
      if (m[actual][n] < costoMejor || (m[actual][n] === costoMejor && n < mejor)) {
        costoMejor = m[actual][n];
        mejor = n;
      }
    }
    orden.push(mejor);
    pendientes.delete(mejor);
    actual = mejor;
  }
  return orden;
}

/**
 * 2-opt: invierte tramos del recorrido mientras eso reduzca el costo total
 * (circuito desde y hacia la bodega). Con [grupos] solo se invierten tramos
 * contenidos en un mismo grupo (para respetar la prioridad por plazo).
 * Se recalcula el costo completo de cada candidato, válido también para
 * matrices asimétricas (calles de un sentido).
 */
export function dosOpt(
  m: MatrizCostos,
  orden: number[],
  opciones: { bodega?: number; grupos?: number[]; maxIteraciones?: number } = {},
): { orden: number[]; mejoras: number } {
  const bodega = opciones.bodega ?? 0;
  const grupos = opciones.grupos ?? orden.map(() => 0);
  let mejor = [...orden];
  let costoMejor = costoCircuito(m, mejor, bodega);
  let mejoras = 0;
  const maxIteraciones = opciones.maxIteraciones ?? 1000;

  let huboMejora = true;
  while (huboMejora && mejoras < maxIteraciones) {
    huboMejora = false;
    for (let i = 0; i < mejor.length - 1; i++) {
      for (let j = i + 1; j < mejor.length; j++) {
        if (grupos[i] !== grupos[j]) continue; // no cruzar la prioridad por plazo
        const candidato = [...mejor.slice(0, i), ...mejor.slice(i, j + 1).reverse(), ...mejor.slice(j + 1)];
        const costo = costoCircuito(m, candidato, bodega);
        if (costo < costoMejor - 1e-9) {
          mejor = candidato;
          costoMejor = costo;
          mejoras++;
          huboMejora = true;
        }
      }
    }
  }
  return { orden: mejor, mejoras };
}

export interface ResultadoOrden {
  orden: number[];
  costoVecino: number;
  costo2opt: number;
  mejoras2opt: number;
}

/**
 * Ordena un lote: Vecino Más Cercano + 2-opt, con lo urgente primero.
 * Las urgentes se ordenan desde la bodega; el resto, desde la última urgente.
 */
export function ordenarLote(m: MatrizCostos, urgentes: number[], resto: number[], bodega = 0): ResultadoOrden {
  const ordenUrgentes = vecinoMasCercano(m, bodega, urgentes);
  const desde = ordenUrgentes.length ? ordenUrgentes[ordenUrgentes.length - 1] : bodega;
  const ordenVecino = [...ordenUrgentes, ...vecinoMasCercano(m, desde, resto)];
  const grupos = ordenVecino.map((n) => (urgentes.includes(n) ? 0 : 1));
  const { orden, mejoras } = dosOpt(m, ordenVecino, { bodega, grupos });
  return {
    orden,
    costoVecino: costoCircuito(m, ordenVecino, bodega),
    costo2opt: costoCircuito(m, orden, bodega),
    mejoras2opt: mejoras,
  };
}

export interface ParadaVrp {
  nodo: number; // índice en la matriz (1..n)
  lat: number;
  lng: number;
  urgente: boolean;
}

/**
 * VRP por barrido angular: ordena las paradas por ángulo alrededor de la
 * bodega y prueba todas las formas de cortar ese círculo en [k] lotes
 * contiguos de tamaño equilibrado. Se queda con la partición de menor costo
 * total (cada lote ordenado con Vecino Más Cercano + 2-opt). Con k = 1
 * equivale a una sola ruta.
 */
export function asignarLotes(
  m: MatrizCostos,
  bodega: { lat: number; lng: number },
  paradas: ParadaVrp[],
  k: number,
): { lotes: (ResultadoOrden & { nodos: number[] })[]; costoTotal: number } {
  const lotesEfectivos = Math.max(1, Math.min(k, paradas.length));
  const ordenar = (nodos: number[]) => {
    const urgentes = nodos.filter((n) => paradas.find((p) => p.nodo === n)!.urgente);
    const resto = nodos.filter((n) => !urgentes.includes(n));
    return { nodos, ...ordenarLote(m, urgentes, resto) };
  };

  if (lotesEfectivos === 1) {
    const unico = ordenar(paradas.map((p) => p.nodo));
    return { lotes: [unico], costoTotal: unico.costo2opt };
  }

  const angulo = (p: ParadaVrp) => Math.atan2(p.lat - bodega.lat, p.lng - bodega.lng);
  const circulo = [...paradas].sort((a, b) => angulo(a) - angulo(b)).map((p) => p.nodo);
  const n = circulo.length;

  // Tamaños equilibrados (difieren a lo más en 1).
  const base = Math.floor(n / lotesEfectivos);
  const extra = n % lotesEfectivos;
  const tamanos = Array.from({ length: lotesEfectivos }, (_, i) => base + (i < extra ? 1 : 0));

  let mejor: { lotes: (ResultadoOrden & { nodos: number[] })[]; costoTotal: number } | null = null;
  for (let inicio = 0; inicio < n; inicio++) {
    const rotado = [...circulo.slice(inicio), ...circulo.slice(0, inicio)];
    let cursor = 0;
    const lotes = tamanos.map((t) => {
      const nodos = rotado.slice(cursor, cursor + t);
      cursor += t;
      return ordenar(nodos);
    });
    const costoTotal = lotes.reduce((s, l) => s + l.costo2opt, 0);
    if (!mejor || costoTotal < mejor.costoTotal - 1e-9) mejor = { lotes, costoTotal };
  }
  return mejor!;
}
