// Edge Function: Módulo Enrutamiento (RF-21 a RF-24).
//
// 1. Compila las direcciones de entrega de los despachos de la jornada (RF-21).
// 2. "Cumplir el plazo primero, optimizar después": las paradas cuyo plazo
//    vence en la jornada (o ya venció) se visitan ANTES que el resto. Dentro de
//    cada grupo, Google Routes API ordena las paradas para minimizar el
//    recorrido (RF-22).
// 3. Se calcula esa ruta priorizada permitiendo peajes (TAG) y evitándolos, y
//    se aplica la regla de negocio: el desvío más rápido solo se acepta si
//    cuesta menos de $500 por cada 10 minutos ahorrados.
// 4. Línea base para el ahorro: las mismas paradas en orden de plazo, sin
//    optimizar (como se arman hoy los repartos).
// 5. Guarda la ruta, sus paradas y el ahorro estimado en combustible y
//    peajes (RF-24). El Chofer solo la visualiza (RF-23).
import {
  clienteAdministrador,
  googleMapsApiKey,
  HttpError,
  json,
  servir,
} from "../_shared/comun.ts";
import { geocodificarDireccion } from "../_shared/places.ts";
import {
  costoRecorrido,
  elegirRecorrido,
  explicarEleccion,
  resumenRecorrido,
  separarPorPlazo,
} from "./costos.ts";
import type { Recorrido } from "./costos.ts";

interface Punto {
  lat: number;
  lng: number;
}

interface Parada extends Punto {
  despachoId: string;
  fechaComprometida: string;
  cliente: string;
}

interface ResultadoRuta extends Recorrido {
  polilinea: string;
  /** Paradas en el orden de visita. */
  secuencia: Parada[];
  usaPeajes: boolean;
}

const MAX_PARADAS = 25; // límite de puntos intermedios de Routes API

servir(async (req) => {
  const supabase = await clienteAdministrador(req);

  const body = (await req.json()) as {
    fecha?: string;
    choferId?: string | null;
    origen?: Punto & { direccion: string };
    despachoIds?: string[];
  };

  const { fecha, choferId, origen, despachoIds } = body;
  if (!fecha || !origen || !despachoIds?.length) {
    throw new HttpError(400, "Faltan fecha, origen o despachos");
  }
  if (despachoIds.length > MAX_PARADAS) {
    throw new HttpError(400, `Máximo ${MAX_PARADAS} paradas por ruta`);
  }

  // --- RF-21: compilar direcciones de la jornada ---------------------------
  const { data: filas, error } = await supabase
    .from("despacho")
    .select("id, estado, orden_compra(id, cliente, direccion_entrega, direccion_lat, direccion_lng, fecha_comprometida)")
    .in("id", despachoIds);
  if (error) throw new HttpError(500, error.message);

  const apiKey = googleMapsApiKey();

  // Las direcciones aún sin validar se geocodifican ahora (Places) y se
  // guardan en la orden.
  // deno-lint-ignore no-explicit-any
  for (const f of (filas ?? []) as any[]) {
    const o = f.orden_compra;
    if (o.direccion_lat != null && o.direccion_lng != null) continue;
    const lugar = await geocodificarDireccion(apiKey, o.direccion_entrega);
    o.direccion_lat = lugar.lat;
    o.direccion_lng = lugar.lng;
    await supabase
      .from("orden_compra")
      .update({ direccion_entrega: lugar.direccion, direccion_lat: lugar.lat, direccion_lng: lugar.lng })
      .eq("id", o.id);
  }

  // deno-lint-ignore no-explicit-any
  const paradas: Parada[] = (filas ?? []).map((f: any) => {
    const o = f.orden_compra;
    if (f.estado === "entregado") {
      throw new HttpError(400, `El despacho de ${o.cliente} ya fue entregado`);
    }
    return {
      despachoId: f.id,
      lat: o.direccion_lat,
      lng: o.direccion_lng,
      fechaComprometida: o.fecha_comprometida,
      cliente: o.cliente,
    };
  });
  if (paradas.length !== despachoIds.length) {
    throw new HttpError(404, "Algún despacho no existe");
  }

  paradas.sort((a, b) =>
    a.fechaComprometida.localeCompare(b.fechaComprometida) || a.cliente.localeCompare(b.cliente)
  );

  // --- Plazo primero --------------------------------------------------------
  const { urgentes, resto, vencidas } = separarPorPlazo(paradas, fecha);

  // --- RF-22: Google Routes API --------------------------------------------
  const [sinOptimizar, conPeajes, sinPeajes] = await Promise.all([
    calcularRuta(apiKey, origen, origen, paradas, { optimizar: false, evitarPeajes: false }),
    rutaPriorizada(apiKey, origen, urgentes, resto, false),
    rutaPriorizada(apiKey, origen, urgentes, resto, true),
  ]);

  // Ambas alternativas respetan el plazo; entre ellas manda la regla de costo.
  const elegida = elegirRecorrido(conPeajes, sinPeajes);

  // --- RF-24: costos y ahorro ----------------------------------------------
  const costoSinOptimizar = costoRecorrido(sinOptimizar);
  const costoOptimizada = costoRecorrido(elegida);

  // Comparación completa para el Administrador: tiempo, km, TAG y combustible
  // de cada alternativa, y por qué se eligió la ruta final.
  const detalleOptimizacion = {
    sinOptimizar: resumenRecorrido(sinOptimizar),
    conTag: resumenRecorrido(conPeajes),
    sinTag: resumenRecorrido(sinPeajes),
    elegida: elegida === conPeajes ? "con_tag" : "sin_tag",
    motivo: explicarEleccion(conPeajes, sinPeajes),
    paradasPrioritarias: urgentes.length,
  };

  const { data: ruta, error: errRuta } = await supabase
    .from("ruta")
    .insert({
      fecha,
      chofer_id: choferId ?? null,
      origen_direccion: origen.direccion,
      origen_lat: origen.lat,
      origen_lng: origen.lng,
      distancia_km: Math.round(elegida.distanciaMetros / 100) / 10,
      duracion_min: Math.round(elegida.duracionSegundos / 60),
      polilinea: elegida.polilinea,
      usa_peajes: elegida.usaPeajes,
      costo_ruta_sin_optimizar: costoSinOptimizar,
      costo_ruta_optimizada: costoOptimizada,
      detalle_optimizacion: detalleOptimizacion,
    })
    .select("id")
    .single();
  if (errRuta) throw new HttpError(500, errRuta.message);

  const filasParadas = elegida.secuencia.map((p, posicion) => ({
    ruta_id: ruta.id,
    despacho_id: p.despachoId,
    orden: posicion,
  }));
  const { error: errParadas } = await supabase.from("ruta_parada").insert(filasParadas);
  if (errParadas) {
    await supabase.from("ruta").delete().eq("id", ruta.id);
    throw new HttpError(500, errParadas.message);
  }

  return json({
    rutaId: ruta.id,
    usaPeajes: elegida.usaPeajes,
    costoSinOptimizar,
    costoOptimizada,
    ahorro: costoSinOptimizar - costoOptimizada,
    paradasPrioritarias: urgentes.length,
    advertencias: vencidas.map((p) =>
      `${p.cliente}: el plazo venció el ${p.fechaComprometida}; se visita primero`
    ),
  });
});

/**
 * Ruta que visita primero las paradas urgentes y después el resto, cada
 * grupo en su orden óptimo:
 *   a) urgentes: bodega → urgentes (orden óptimo) → bodega
 *   b) resto:    última urgente → resto (orden óptimo) → bodega
 *   c) recorrido final con ese orden fijo (distancia, peajes y trazado reales)
 */
async function rutaPriorizada(
  apiKey: string,
  origen: Punto,
  urgentes: Parada[],
  resto: Parada[],
  evitarPeajes: boolean,
): Promise<ResultadoRuta> {
  if (urgentes.length === 0 || resto.length === 0) {
    const todas = urgentes.length ? urgentes : resto;
    return calcularRuta(apiKey, origen, origen, todas, { optimizar: true, evitarPeajes });
  }

  const tramoUrgente = await calcularRuta(apiKey, origen, origen, urgentes, {
    optimizar: true,
    evitarPeajes,
  });
  const ultimaUrgente = tramoUrgente.secuencia[tramoUrgente.secuencia.length - 1];
  const tramoResto = await calcularRuta(apiKey, ultimaUrgente, origen, resto, {
    optimizar: true,
    evitarPeajes,
  });

  return calcularRuta(apiKey, origen, origen, [...tramoUrgente.secuencia, ...tramoResto.secuencia], {
    optimizar: false,
    evitarPeajes,
  });
}

async function calcularRuta(
  apiKey: string,
  desde: Punto,
  hasta: Punto,
  paradas: Parada[],
  opciones: { optimizar: boolean; evitarPeajes: boolean },
): Promise<ResultadoRuta> {
  const punto = (p: Punto) => ({ location: { latLng: { latitude: p.lat, longitude: p.lng } } });

  const res = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": [
        "routes.distanceMeters",
        "routes.duration",
        "routes.polyline.encodedPolyline",
        "routes.optimizedIntermediateWaypointIndex",
        "routes.travelAdvisory.tollInfo",
      ].join(","),
    },
    body: JSON.stringify({
      origin: punto(desde),
      destination: punto(hasta),
      intermediates: paradas.map(punto),
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_UNAWARE",
      optimizeWaypointOrder: opciones.optimizar && paradas.length > 1,
      routeModifiers: {
        avoidTolls: opciones.evitarPeajes,
        vehicleInfo: { emissionType: "DIESEL" },
      },
      extraComputations: ["TOLLS"],
      languageCode: "es-CL",
      units: "METRIC",
    }),
  });

  if (!res.ok) throw new HttpError(502, `Routes API: ${await res.text()}`);
  const data = await res.json();
  const r = data.routes?.[0];
  if (!r) throw new HttpError(502, "Routes API no devolvió rutas");

  const peajesClp = (r.travelAdvisory?.tollInfo?.estimatedPrice ?? [])
    // deno-lint-ignore no-explicit-any
    .filter((m: any) => m.currencyCode === "CLP")
    // deno-lint-ignore no-explicit-any
    .reduce((s: number, m: any) => s + Number(m.units ?? 0) + (m.nanos ?? 0) / 1e9, 0);

  const indices: number[] =
    opciones.optimizar && Array.isArray(r.optimizedIntermediateWaypointIndex) &&
      r.optimizedIntermediateWaypointIndex.length === paradas.length
      ? r.optimizedIntermediateWaypointIndex
      : paradas.map((_, i) => i);

  return {
    distanciaMetros: r.distanceMeters ?? 0,
    duracionSegundos: parseInt(String(r.duration ?? "0s").replace("s", ""), 10),
    peajesClp,
    polilinea: r.polyline?.encodedPolyline ?? "",
    secuencia: indices.map((i) => paradas[i]),
    usaPeajes: peajesClp > 0,
  };
}
