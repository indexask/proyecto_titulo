// Reglas de negocio del Módulo Enrutamiento (traspaso §6). Sin dependencias,
// para poder probarlas de forma aislada (ver costos_test.ts).

/** Parámetros de costo logístico fijos: JAC Sunray 2018 diésel. */
export const RENDIMIENTO_KM_POR_LITRO = 9;
export const PRECIO_DIESEL_CLP_POR_LITRO = 1272;

/** Regla de desvío: se acepta pagar menos de $500 por cada 10 minutos ahorrados. */
export const COSTO_MAXIMO_POR_10_MIN = 500;

export interface Recorrido {
  distanciaMetros: number;
  duracionSegundos: number;
  peajesClp: number;
}

/** Combustible = km / 9 km/L × $1.272/L. */
export function costoCombustible(r: Recorrido): number {
  return Math.round((r.distanciaMetros / 1000 / RENDIMIENTO_KM_POR_LITRO) * PRECIO_DIESEL_CLP_POR_LITRO);
}

/** Costo = combustible + peajes (TAG). */
export function costoRecorrido(r: Recorrido): number {
  return Math.round((r.distanciaMetros / 1000 / RENDIMIENTO_KM_POR_LITRO) * PRECIO_DIESEL_CLP_POR_LITRO + r.peajesClp);
}

/** Resumen de un recorrido para mostrar la comparación (tiempo, km, TAG, combustible). */
export function resumenRecorrido(r: Recorrido) {
  return {
    distanciaKm: Math.round(r.distanciaMetros / 100) / 10,
    duracionMin: Math.round(r.duracionSegundos / 60),
    peajesClp: Math.round(r.peajesClp),
    combustibleClp: costoCombustible(r),
    costoClp: costoRecorrido(r),
  };
}

/**
 * Explica, en palabras, por qué la regla de $500 por cada 10 minutos eligió
 * la ruta con TAG o la ruta sin TAG.
 */
export function explicarEleccion(conTag: Recorrido, sinTag: Recorrido): string {
  const elegida = elegirRecorrido(conTag, sinTag);
  const minutos = Math.round((sinTag.duracionSegundos - conTag.duracionSegundos) / 60);
  const extra = costoRecorrido(conTag) - costoRecorrido(sinTag);
  const limite = Math.round(COSTO_MAXIMO_POR_10_MIN * (minutos / 10));
  const clp = (n: number) => `$${Math.abs(n).toLocaleString("es-CL")}`;

  if (conTag.peajesClp === 0 && sinTag.peajesClp === 0) {
    return "El recorrido óptimo no pasa por autopistas con TAG.";
  }
  if (elegida === conTag) {
    return extra <= 0
      ? `Se usa TAG: es más rápida (${minutos} min menos) y no cuesta más.`
      : `Se usa TAG: ahorra ${minutos} min por ${clp(extra)} extra, menos que el máximo aceptado (${clp(limite)} = $500 por cada 10 min).`;
  }
  return minutos <= 0
    ? "Se evita el TAG: la ruta con TAG no ahorra tiempo."
    : `Se evita el TAG: ahorraría ${minutos} min pero cuesta ${clp(extra)} extra, más que el máximo aceptado (${clp(limite)} = $500 por cada 10 min).`;
}

/**
 * El plazo manda sobre la distancia: separa las paradas cuyo plazo vence en
 * la jornada (o ya venció), que deben visitarse primero, del resto. La
 * optimización por distancia/costo se aplica dentro de cada grupo.
 * Fechas en formato ISO (YYYY-MM-DD), comparables como texto.
 */
export function separarPorPlazo<T extends { fechaComprometida: string }>(
  paradas: T[],
  fechaJornada: string,
): { urgentes: T[]; resto: T[]; vencidas: T[] } {
  return {
    urgentes: paradas.filter((p) => p.fechaComprometida <= fechaJornada),
    resto: paradas.filter((p) => p.fechaComprometida > fechaJornada),
    vencidas: paradas.filter((p) => p.fechaComprometida < fechaJornada),
  };
}

/**
 * Elige entre dos alternativas de recorrido aplicando la regla de negocio:
 * la alternativa más rápida solo se acepta si su costo adicional es menor a
 * $500 por cada 10 minutos ahorrados. Si además es igual o más barata, se
 * elige siempre.
 */
export function elegirRecorrido<T extends Recorrido>(a: T, b: T): T {
  const [rapido, lento] = a.duracionSegundos <= b.duracionSegundos ? [a, b] : [b, a];
  const costoAdicional = costoRecorrido(rapido) - costoRecorrido(lento);
  if (costoAdicional <= 0) return rapido;

  const minutosAhorrados = (lento.duracionSegundos - rapido.duracionSegundos) / 60;
  const limite = COSTO_MAXIMO_POR_10_MIN * (minutosAhorrados / 10);
  return costoAdicional < limite ? rapido : lento;
}
