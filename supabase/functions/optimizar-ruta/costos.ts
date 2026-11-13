// Reglas de negocio del Módulo Enrutamiento (traspaso §6). Sin dependencias,
// para poder probarlas de forma aislada (ver costos_test.ts).

/** Parámetros de costo logístico fijos: JAC Sunray 2018 diésel. */
export const RENDIMIENTO_KM_POR_LITRO = 9;
export const PRECIO_DIESEL_CLP_POR_LITRO = 1272;

/** Regla de desvío: se acepta pagar menos de $500 por cada 10 minutos ahorrados. */
export const COSTO_MAXIMO_POR_10_MIN = 500;

/**
 * Categoría TAG del vehículo (MOP): "1" autos y camionetas, "2" buses y
 * camiones. JAC Sunray 2018 (furgón) [VALIDAR: confirmar la categoría con la
 * que lo clasifican las concesionarias].
 */
export const CATEGORIA_TAG = "1";

/** Hora de salida de la bodega si no se indica (HH:MM). */
export const HORA_SALIDA_POR_DEFECTO = "09:00";

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
 * La regla "aceptar un costo adicional < $500 por cada 10 minutos ahorrados"
 * equivale a elegir la alternativa con menor costo + $50 por minuto. Así se
 * puede aplicar a cualquier número de alternativas (orden por plazo,
 * optimizada con TAG, optimizada sin TAG). En empate gana la más lenta, igual
 * que en la regla de a pares (el costo adicional debe ser MENOR al límite).
 */
export function costoConTiempo(r: Recorrido): number {
  return costoRecorrido(r) + (COSTO_MAXIMO_POR_10_MIN / 10) * (r.duracionSegundos / 60);
}

export function elegirMejor<T extends Recorrido>(candidatas: T[]): T {
  return candidatas.reduce((mejor, c) => {
    const dc = costoConTiempo(c), dm = costoConTiempo(mejor);
    if (dc < dm - 1e-9) return c;
    if (Math.abs(dc - dm) <= 1e-9 && c.duracionSegundos > mejor.duracionSegundos) return c;
    return mejor;
  });
}

const clp = (n: number) => `$${Math.round(Math.abs(n)).toLocaleString("es-CL")}`;

/**
 * Explica, en palabras, por qué se eligió la ruta final frente a la
 * alternativa más rápida y la más barata.
 */
export function explicarEleccion<T extends Recorrido & { etiqueta: string }>(candidatas: T[], elegida: T): string {
  const sinTag = candidatas.every((c) => c.peajesClp === 0) ? " Ninguna alternativa pasa por autopistas con TAG." : "";
  const masRapida = candidatas.reduce((a, b) => (b.duracionSegundos < a.duracionSegundos ? b : a));
  const masBarata = candidatas.reduce((a, b) => (costoRecorrido(b) < costoRecorrido(a) ? b : a));

  if (elegida === masRapida && elegida === masBarata) {
    return `Se eligió "${elegida.etiqueta}": es la más rápida y la más barata.${sinTag}`;
  }
  if (elegida !== masRapida) {
    const minutos = Math.round((elegida.duracionSegundos - masRapida.duracionSegundos) / 60);
    const extra = costoRecorrido(masRapida) - costoRecorrido(elegida);
    const limite = COSTO_MAXIMO_POR_10_MIN * (minutos / 10);
    return `Se eligió "${elegida.etiqueta}". "${masRapida.etiqueta}" ahorraría ${minutos} min pero cuesta ${clp(extra)} más, ` +
      `sobre el máximo aceptado (${clp(limite)} = $500 por cada 10 min).${sinTag}`;
  }
  const minutos = Math.round((masBarata.duracionSegundos - elegida.duracionSegundos) / 60);
  const extra = costoRecorrido(elegida) - costoRecorrido(masBarata);
  const limite = COSTO_MAXIMO_POR_10_MIN * (minutos / 10);
  return `Se eligió "${elegida.etiqueta}": ahorra ${minutos} min frente a "${masBarata.etiqueta}" por ${clp(extra)} más, ` +
    `bajo el máximo aceptado (${clp(limite)} = $500 por cada 10 min).${sinTag}`;
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
