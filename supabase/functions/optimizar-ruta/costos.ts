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

/** Costo = combustible (km / 9 km/L × $1.272/L) + peajes (TAG). */
export function costoRecorrido(r: Recorrido): number {
  const litros = r.distanciaMetros / 1000 / RENDIMIENTO_KM_POR_LITRO;
  return Math.round(litros * PRECIO_DIESEL_CLP_POR_LITRO + r.peajesClp);
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
