// Estimación del costo TAG por geocercas de pórticos (RF-24). Sin dependencias,
// para probarlo de forma aislada (peajes_test.ts).
//
// 1. Pórticos: ubicación y sentido de cobro (OpenStreetMap) con tarifas y
//    horarios 2026 del MOP, en la tabla `portico`.
// 2. Ruta: polilínea real de Google Routes.
// 3. Intersección: la ruta "toca" un pórtico si pasa a menos de RADIO_M metros
//    y en el mismo sentido (±TOLERANCIA_RUMBO°), para no cobrar el pórtico de
//    la calzada contraria.
// 4. Cálculo dinámico: hora estimada de paso = hora de salida + tiempo
//    proporcional a la distancia recorrida hasta el pórtico; se aplica la
//    tarifa TBFP / TBP / TS de ese pórtico según el día y la hora.

export interface TarifaCategoria {
  tbfp: number;
  tbp?: number;
  ts?: number;
}

export type Ventanas = { tbp?: [string, string][]; ts?: [string, string][] };

export interface Portico {
  concesion: string;
  codigo: string;
  tramo: string;
  lat: number;
  lng: number;
  rumbo: number | null;
  km: number;
  porKm: boolean;
  tarifas: Record<string, TarifaCategoria>;
  horario: { laboral?: Ventanas; sabado?: Ventanas; domingo?: Ventanas };
}

export interface CrucePortico {
  concesion: string;
  codigo: string;
  tramo: string;
  /** Hora estimada de paso, "HH:MM". */
  hora: string;
  tarifa: "TBFP" | "TBP" | "TS" | "POR KM";
  monto: number;
  /** Distancia desde la salida hasta el pórtico (m). */
  distanciaM: number;
}

export const RADIO_M = 35;
export const TOLERANCIA_RUMBO = 60;

type Punto = [number, number]; // [lat, lng]

/** Decodifica una polilínea de Google (algoritmo estándar, en JS los enteros con signo de 32 bits son correctos). */
export function decodificarPolilinea(codificada: string): Punto[] {
  const puntos: Punto[] = [];
  let indice = 0, lat = 0, lng = 0;
  const siguiente = () => {
    let resultado = 0, desplazamiento = 0, b: number;
    do {
      b = codificada.charCodeAt(indice++) - 63;
      resultado |= (b & 0x1f) << desplazamiento;
      desplazamiento += 5;
    } while (b >= 0x20 && indice < codificada.length);
    return resultado & 1 ? ~(resultado >> 1) : resultado >> 1;
  };
  while (indice < codificada.length) {
    lat += siguiente();
    if (indice >= codificada.length) break;
    lng += siguiente();
    puntos.push([lat / 1e5, lng / 1e5]);
  }
  return puntos;
}

const RAD = Math.PI / 180;

export function distanciaM(a: Punto, b: Punto): number {
  const dLat = (b[0] - a[0]) * RAD, dLng = (b[1] - a[1]) * RAD;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a[0] * RAD) * Math.cos(b[0] * RAD) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

export function rumbo(a: Punto, b: Punto): number {
  const y = Math.sin((b[1] - a[1]) * RAD) * Math.cos(b[0] * RAD);
  const x = Math.cos(a[0] * RAD) * Math.sin(b[0] * RAD) - Math.sin(a[0] * RAD) * Math.cos(b[0] * RAD) * Math.cos((b[1] - a[1]) * RAD);
  return (Math.atan2(y, x) / RAD + 360) % 360;
}

const diferenciaAngular = (a: number, b: number) => {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
};

/** Distancia (m) del punto p al segmento ab y fracción t (0..1) de la proyección. */
function puntoASegmento(p: Punto, a: Punto, b: Punto): { d: number; t: number } {
  // Proyección local equirectangular (suficiente para distancias de metros).
  const kx = Math.cos(p[0] * RAD) * 111320, ky = 110540;
  const ax = (a[1] - p[1]) * kx, ay = (a[0] - p[0]) * ky;
  const bx = (b[1] - p[1]) * kx, by = (b[0] - p[0]) * ky;
  const dx = bx - ax, dy = by - ay;
  const largo2 = dx * dx + dy * dy;
  const t = largo2 === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / largo2));
  const x = ax + t * dx, y = ay + t * dy;
  return { d: Math.hypot(x, y), t };
}

/**
 * Pórticos que la ruta cruza, en orden de recorrido, con la distancia
 * acumulada desde la salida. Un mismo pórtico puede cruzarse más de una vez
 * (por ejemplo, a la ida y a la vuelta) si las pasadas están separadas.
 */
export function detectarCruces(
  ruta: Punto[],
  porticos: Portico[],
  opciones: { radioM?: number; toleranciaRumbo?: number } = {},
): { portico: Portico; distanciaM: number }[] {
  const radio = opciones.radioM ?? RADIO_M;
  const tolerancia = opciones.toleranciaRumbo ?? TOLERANCIA_RUMBO;
  const cruces: { portico: Portico; distanciaM: number }[] = [];

  // Distancia acumulada en cada vértice.
  const acumulada = [0];
  for (let i = 1; i < ruta.length; i++) acumulada.push(acumulada[i - 1] + distanciaM(ruta[i - 1], ruta[i]));

  for (const portico of porticos) {
    const p: Punto = [portico.lat, portico.lng];
    let ultimaPasada = -Infinity;
    for (let i = 1; i < ruta.length; i++) {
      const a = ruta[i - 1], b = ruta[i];
      // Descarte rápido: el pórtico debe estar cerca del segmento.
      if (Math.min(distanciaM(a, p), distanciaM(b, p)) > distanciaM(a, b) + radio) continue;
      const { d, t } = puntoASegmento(p, a, b);
      if (d > radio) continue;
      if (portico.rumbo !== null && diferenciaAngular(rumbo(a, b), portico.rumbo) > tolerancia) continue;
      const dist = acumulada[i - 1] + t * (acumulada[i] - acumulada[i - 1]);
      if (dist - ultimaPasada < 500) continue; // misma pasada
      ultimaPasada = dist;
      cruces.push({ portico, distanciaM: dist });
    }
  }
  return cruces.sort((x, y) => x.distanciaM - y.distanciaM);
}

const aMinutos = (hhmm: string) => {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
};
const enVentana = (min: number, ventanas?: [string, string][]) =>
  (ventanas ?? []).some(([desde, hasta]) => min >= aMinutos(desde) && min < aMinutos(hasta));

/**
 * Tarifa aplicable según el día (0 = domingo … 6 = sábado) y la hora en
 * minutos desde medianoche. TS tiene prioridad sobre TBP; si la categoría no
 * tiene ese monto, se usa el siguiente disponible.
 */
export function tarifaAplicable(
  portico: Portico,
  diaSemana: number,
  minutos: number,
  categoria: string,
): { tipo: "TBFP" | "TBP" | "TS"; monto: number } {
  const t = portico.tarifas[categoria] ?? portico.tarifas["1"];
  const ventanas = diaSemana === 0 ? portico.horario.domingo
    : diaSemana === 6 ? portico.horario.sabado
    : portico.horario.laboral;
  minutos = ((minutos % 1440) + 1440) % 1440;
  if (t.ts !== undefined && enVentana(minutos, ventanas?.ts)) return { tipo: "TS", monto: t.ts };
  if (t.tbp !== undefined && (enVentana(minutos, ventanas?.tbp) || enVentana(minutos, ventanas?.ts))) {
    return { tipo: "TBP", monto: t.tbp };
  }
  return { tipo: "TBFP", monto: t.tbfp };
}

const hhmm = (minutos: number) => {
  // Se trunca al minuto (como un reloj): 08:29:59 se muestra 08:29, coherente con la tarifa aplicada.
  const m = ((Math.floor(minutos) % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
};

/**
 * Costo TAG estimado de una ruta. La hora de paso por cada pórtico se estima
 * en proporción a la distancia recorrida (no incluye el tiempo detenido en
 * cada entrega). Los pórticos de cobro por km (Américo Vespucio Oriente) se
 * cobran por la distancia entre el primer y el último pórtico de cada pasada.
 */
export function estimarPeajes(
  ruta: Punto[],
  porticos: Portico[],
  viaje: { distanciaM: number; duracionS: number; diaSemana: number; salidaMinutos: number; categoria: string },
): { totalClp: number; cruces: CrucePortico[] } {
  const crucesRuta = detectarCruces(ruta, porticos);
  const minutosEn = (dist: number) =>
    viaje.salidaMinutos + (viaje.distanciaM > 0 ? (viaje.duracionS / 60) * (dist / viaje.distanciaM) : 0);

  const cruces: CrucePortico[] = [];
  for (let i = 0; i < crucesRuta.length; i++) {
    const { portico, distanciaM: dist } = crucesRuta[i];
    const minutos = minutosEn(dist);

    if (portico.porKm) {
      // Agrupa los pórticos por km consecutivos de la misma concesión (una pasada).
      let j = i;
      while (j + 1 < crucesRuta.length && crucesRuta[j + 1].portico.porKm &&
        crucesRuta[j + 1].portico.concesion === portico.concesion &&
        crucesRuta[j + 1].distanciaM - crucesRuta[j].distanciaM < 5000) j++;
      const km = Math.max(1, (crucesRuta[j].distanciaM - dist) / 1000);
      const { monto } = tarifaAplicable(portico, viaje.diaSemana, minutos, viaje.categoria);
      cruces.push({
        concesion: portico.concesion, codigo: portico.codigo, tramo: `${portico.tramo} (${km.toFixed(1)} km)`,
        hora: hhmm(minutos), tarifa: "POR KM", monto: Math.round(monto * km), distanciaM: Math.round(dist),
      });
      i = j;
      continue;
    }

    const { tipo, monto } = tarifaAplicable(portico, viaje.diaSemana, minutos, viaje.categoria);
    cruces.push({
      concesion: portico.concesion, codigo: portico.codigo, tramo: portico.tramo,
      hora: hhmm(minutos), tarifa: tipo, monto: Math.round(monto), distanciaM: Math.round(dist),
    });
  }
  return { totalClp: cruces.reduce((s, c) => s + c.monto, 0), cruces };
}
