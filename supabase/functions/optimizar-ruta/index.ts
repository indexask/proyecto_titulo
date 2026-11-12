// Edge Function: Módulo Enrutamiento (RF-21 a RF-24).
//
// 1. Compila las direcciones de entrega de los despachos de la jornada (RF-21).
// 2. Consulta Google Routes API (RF-22):
//    a) ruta SIN optimizar: paradas en orden de plazo (fecha_comprometida),
//       que es como se arman hoy los repartos → línea base para el ahorro.
//    b) ruta optimizada permitiendo peajes (TAG).
//    c) ruta optimizada evitando peajes.
// 3. Entre (b) y (c) aplica la regla de negocio: el desvío más rápido solo se
//    acepta si cuesta menos de $500 por cada 10 minutos ahorrados.
// 4. Guarda la ruta, sus paradas en el orden óptimo y el ahorro estimado en
//    combustible y peajes (RF-24). El Chofer solo la visualiza (RF-23).
import {
  clienteAdministrador,
  googleMapsApiKey,
  HttpError,
  json,
  servir,
} from "../_shared/comun.ts";
import { costoRecorrido, elegirRecorrido, Recorrido } from "./costos.ts";

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
  ordenOptimo: number[];
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
    .select("id, estado, orden_compra(cliente, direccion_lat, direccion_lng, fecha_comprometida)")
    .in("id", despachoIds);
  if (error) throw new HttpError(500, error.message);

  const paradas: Parada[] = (filas ?? []).map((f: any) => {
    const o = f.orden_compra;
    if (f.estado === "entregado") {
      throw new HttpError(400, `El despacho de ${o.cliente} ya fue entregado`);
    }
    if (o.direccion_lat == null || o.direccion_lng == null) {
      throw new HttpError(400, `La orden de ${o.cliente} no tiene la dirección geocodificada`);
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

  // Orden por plazo: primero lo que vence antes.
  paradas.sort((a, b) =>
    a.fechaComprometida.localeCompare(b.fechaComprometida) || a.cliente.localeCompare(b.cliente)
  );

  // --- RF-22: Google Routes API --------------------------------------------
  const apiKey = googleMapsApiKey();
  const [sinOptimizar, conPeajes, sinPeajes] = await Promise.all([
    calcularRuta(apiKey, origen, paradas, { optimizar: false, evitarPeajes: false }),
    calcularRuta(apiKey, origen, paradas, { optimizar: true, evitarPeajes: false }),
    calcularRuta(apiKey, origen, paradas, { optimizar: true, evitarPeajes: true }),
  ]);

  const elegida = elegirRecorrido(conPeajes, sinPeajes);

  // --- RF-24: costos y ahorro ----------------------------------------------
  const costoSinOptimizar = costoRecorrido(sinOptimizar);
  const costoOptimizada = costoRecorrido(elegida);

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
    })
    .select("id")
    .single();
  if (errRuta) throw new HttpError(500, errRuta.message);

  const filasParadas = elegida.ordenOptimo.map((indice, posicion) => ({
    ruta_id: ruta.id,
    despacho_id: paradas[indice].despachoId,
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
  });
});

async function calcularRuta(
  apiKey: string,
  origen: Punto,
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
      origin: punto(origen),
      destination: punto(origen), // viaje redondo: vuelve a bodega
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
    .filter((m: any) => m.currencyCode === "CLP")
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
    ordenOptimo: indices,
    usaPeajes: peajesClp > 0,
  };
}
