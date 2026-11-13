// Edge Function: Módulo Enrutamiento (RF-21 a RF-24).
//
// 1. Compila las direcciones de los despachos de la jornada (RF-21); las que
//    no estaban validadas se geocodifican con Places.
// 2. Datos del mundo real: Google Route Matrix (Routes API) entrega la matriz
//    de distancia, tiempo y peajes (TAG) por calles entre bodega y paradas,
//    permitiendo TAG y evitándolo (RF-22).
// 3. VRP: reparte los despachos en un lote por chofer (barrido angular desde
//    la bodega, evaluado con el costo real). Con un chofer, un solo lote.
// 4. Motor algorítmico: cada lote se ordena con Vecino Más Cercano + 2-opt.
//    El plazo manda: lo que vence en la jornada se visita primero.
//    Costo minimizado = combustible + peajes + $50 por minuto, que equivale a
//    la regla "aceptar < $500 de costo adicional por cada 10 min ahorrados".
// 5. Por lote se comparan 3 alternativas con el trazado real (Routes API):
//    orden por plazo (línea base), optimizada permitiendo TAG y optimizada
//    evitando TAG. Gana la de menor costo + $50/min.
// 6. Se guarda una ruta por chofer con sus paradas y el ahorro estimado en
//    combustible y peajes (RF-24). El Chofer solo la visualiza (RF-23).
import { clienteAdministrador, googleMapsApiKey, HttpError, json, servir } from "../_shared/comun.ts";
import { geocodificarDireccion } from "../_shared/places.ts";
import {
  CATEGORIA_TAG,
  COSTO_MAXIMO_POR_10_MIN,
  costoRecorrido,
  elegirMejor,
  explicarEleccion,
  HORA_SALIDA_POR_DEFECTO,
  PRECIO_DIESEL_CLP_POR_LITRO,
  RENDIMIENTO_KM_POR_LITRO,
  resumenRecorrido,
  separarPorPlazo,
} from "./costos.ts";
import type { Recorrido } from "./costos.ts";
import { decodificarPolilinea, estimarPeajes } from "./peajes.ts";
import type { CrucePortico, Portico } from "./peajes.ts";
import { asignarLotes, ordenarLote } from "./vrp.ts";
import type { MatrizCostos } from "./vrp.ts";

/** Datos para estimar el TAG por geocercas de pórticos. */
interface ContextoPeajes {
  porticos: Portico[];
  diaSemana: number; // 0 = domingo
  salidaMinutos: number;
  categoria: string;
}

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
  secuencia: Parada[];
  usaPeajes: boolean;
  /** Pórticos TAG que cruza la ruta, con hora estimada y tarifa. */
  cruces: CrucePortico[];
}

// Route Matrix admite 625 elementos: (paradas + bodega)² ≤ 625.
const MAX_PARADAS = 24;

servir(async (req) => {
  const supabase = await clienteAdministrador(req);

  const body = (await req.json()) as {
    fecha?: string;
    choferId?: string | null; // compatibilidad: un solo chofer
    choferIds?: string[];
    origen?: Punto & { direccion: string };
    despachoIds?: string[];
    horaSalida?: string; // HH:MM
  };

  const { fecha, origen, despachoIds } = body;
  const horaSalida = /^\d{2}:\d{2}$/.test(body.horaSalida ?? "") ? body.horaSalida! : HORA_SALIDA_POR_DEFECTO;
  const choferIds: (string | null)[] = body.choferIds?.length
    ? body.choferIds
    : [body.choferId ?? null];
  if (!fecha || !origen || !despachoIds?.length) {
    throw new HttpError(400, "Faltan fecha, origen o despachos");
  }
  if (despachoIds.length > MAX_PARADAS) {
    throw new HttpError(400, `Máximo ${MAX_PARADAS} paradas por cálculo`);
  }

  // --- RF-21: compilar direcciones de la jornada ---------------------------
  const { data: filas, error } = await supabase
    .from("despacho")
    .select("id, estado, orden_compra(id, cliente, direccion_entrega, direccion_lat, direccion_lng, fecha_comprometida)")
    .in("id", despachoIds);
  if (error) throw new HttpError(500, error.message);

  const apiKey = googleMapsApiKey();

  // Pórticos TAG (ubicación OSM + tarifas MOP) para estimar los peajes.
  const { data: filasPorticos, error: errPorticos } = await supabase
    .from("portico")
    .select("concesion, codigo, tramo, lat, lng, rumbo, km, por_km, tarifas, horario")
    .eq("activo", true);
  if (errPorticos) throw new HttpError(500, errPorticos.message);
  const [hh, mm] = horaSalida.split(":").map(Number);
  const peajes: ContextoPeajes = {
    // deno-lint-ignore no-explicit-any
    porticos: (filasPorticos ?? []).map((p: any) => ({
      concesion: p.concesion, codigo: p.codigo, tramo: p.tramo, lat: p.lat, lng: p.lng,
      rumbo: p.rumbo, km: Number(p.km), porKm: p.por_km, tarifas: p.tarifas, horario: p.horario,
    })),
    diaSemana: new Date(`${fecha}T12:00:00Z`).getUTCDay(),
    salidaMinutos: hh * 60 + mm,
    categoria: CATEGORIA_TAG,
  };

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
    if (f.estado === "entregado") throw new HttpError(400, `El despacho de ${o.cliente} ya fue entregado`);
    return {
      despachoId: f.id,
      lat: o.direccion_lat,
      lng: o.direccion_lng,
      fechaComprometida: o.fecha_comprometida,
      cliente: o.cliente,
    };
  });
  if (paradas.length !== despachoIds.length) throw new HttpError(404, "Algún despacho no existe");

  // Orden por plazo (línea base): primero lo que vence antes.
  paradas.sort((a, b) =>
    a.fechaComprometida.localeCompare(b.fechaComprometida) || a.cliente.localeCompare(b.cliente)
  );
  const { urgentes, vencidas } = separarPorPlazo(paradas, fecha);
  const esUrgente = new Set(urgentes.map((p) => p.despachoId));

  // --- Datos del mundo real: Route Matrix (nodo 0 = bodega) -----------------
  const puntos: Punto[] = [origen, ...paradas];
  const [matrizConTag, matrizSinTag] = await Promise.all([
    calcularMatriz(apiKey, puntos, false),
    calcularMatriz(apiKey, puntos, true),
  ]);

  // --- VRP: un lote por chofer ------------------------------------------------
  const paradasVrp = paradas.map((p, i) => ({
    nodo: i + 1,
    lat: p.lat,
    lng: p.lng,
    urgente: esUrgente.has(p.despachoId),
  }));
  const { lotes } = asignarLotes(matrizConTag, origen, paradasVrp, choferIds.length);

  const rutasCreadas = [];
  for (const [indiceLote, lote] of lotes.entries()) {
    const choferId = choferIds[indiceLote] ?? null;
    const nodosLote = lote.nodos;
    const paradasLote = nodosLote.map((n) => paradas[n - 1]);
    const urgentesLote = nodosLote.filter((n) => paradasVrp[n - 1].urgente);
    const restoLote = nodosLote.filter((n) => !paradasVrp[n - 1].urgente);

    // Motor: Vecino Más Cercano + 2-opt, con cada matriz (con y sin TAG).
    const conTag = ordenarLote(matrizConTag, urgentesLote, restoLote);
    const sinTag = ordenarLote(matrizSinTag, urgentesLote, restoLote);
    const secuencia = (orden: number[]) => orden.map((n) => paradas[n - 1]);
    const ordenPorPlazo = [...paradasLote].sort((a, b) =>
      a.fechaComprometida.localeCompare(b.fechaComprometida) || a.cliente.localeCompare(b.cliente)
    );

    // Trazado real por calles de cada alternativa (orden fijo).
    const [sinOptimizar, optConTag, optSinTag] = await Promise.all([
      calcularRuta(apiKey, origen, ordenPorPlazo, false, peajes),
      calcularRuta(apiKey, origen, secuencia(conTag.orden), false, peajes),
      calcularRuta(apiKey, origen, secuencia(sinTag.orden), true, peajes),
    ]);

    const candidatas = [
      { clave: "sin_optimizar", etiqueta: "Orden por plazo", ...sinOptimizar },
      { clave: "con_tag", etiqueta: "Optimizada · permite TAG", ...optConTag },
      { clave: "sin_tag", etiqueta: "Optimizada · evita TAG", ...optSinTag },
    ];
    const elegida = elegirMejor(candidatas);

    // --- RF-24: costos y ahorro --------------------------------------------
    const costoSinOptimizar = costoRecorrido(sinOptimizar);
    const costoOptimizada = costoRecorrido(elegida);
    const motor = elegida.clave === "sin_tag" ? sinTag : conTag;

    const detalleOptimizacion = {
      sinOptimizar: resumenRecorrido(sinOptimizar),
      conTag: resumenRecorrido(optConTag),
      sinTag: resumenRecorrido(optSinTag),
      elegida: elegida.clave,
      motivo: explicarEleccion(candidatas, elegida),
      paradasPrioritarias: urgentesLote.length,
      algoritmo: {
        nombre: "Vecino Más Cercano + 2-opt sobre Route Matrix",
        // Costo del modelo (combustible + peajes + $50/min) antes y después de 2-opt.
        costoVecino: Math.round(motor.costoVecino),
        costo2opt: Math.round(motor.costo2opt),
        mejoras2opt: motor.mejoras2opt,
      },
      vrp: { choferes: choferIds.length, rutas: lotes.length, lote: indiceLote + 1 },
      // Detalle TAG de la ruta elegida (geocercas de pórticos, tarifas MOP 2026).
      peajes: {
        categoria: peajes.categoria,
        horaSalida,
        totalClp: Math.round(elegida.peajesClp),
        cruces: elegida.cruces,
        fuente: "Pórticos: OpenStreetMap. Tarifas: MOP Peajes Tarifas 2026.",
      },
    };

    const { data: ruta, error: errRuta } = await supabase
      .from("ruta")
      .insert({
        fecha,
        chofer_id: choferId,
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

    const { error: errParadas } = await supabase.from("ruta_parada").insert(
      elegida.secuencia.map((p, posicion) => ({ ruta_id: ruta.id, despacho_id: p.despachoId, orden: posicion })),
    );
    if (errParadas) {
      await supabase.from("ruta").delete().eq("id", ruta.id);
      throw new HttpError(500, errParadas.message);
    }

    rutasCreadas.push({
      rutaId: ruta.id,
      choferId,
      paradas: elegida.secuencia.length,
      ahorro: costoSinOptimizar - costoOptimizada,
    });
  }

  return json({
    rutaId: rutasCreadas[0]?.rutaId, // compatibilidad: una sola ruta
    rutas: rutasCreadas,
    advertencias: vencidas.map((p) => `${p.cliente}: el plazo venció el ${p.fechaComprometida}; se visita primero`),
  });
});

/**
 * Matriz de costos con Google Route Matrix. Costo de cada tramo =
 * combustible + peajes + $50 por minuto (regla de $500 por cada 10 min).
 */
async function calcularMatriz(apiKey: string, puntos: Punto[], evitarPeajes: boolean): Promise<MatrizCostos> {
  const waypoint = (p: Punto) => ({ waypoint: { location: { latLng: { latitude: p.lat, longitude: p.lng } } } });
  // En Route Matrix las opciones de ruta (evitar TAG, vehículo) van en cada
  // origen (RouteMatrixOrigin.routeModifiers), no en la raíz como en Routes.
  const origen = (p: Punto) => ({
    ...waypoint(p),
    routeModifiers: { avoidTolls: evitarPeajes, vehicleInfo: { emissionType: "DIESEL" } },
  });
  const res = await fetch("https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "originIndex,destinationIndex,distanceMeters,duration,condition,travelAdvisory.tollInfo",
    },
    body: JSON.stringify({
      origins: puntos.map(origen),
      destinations: puntos.map(waypoint),
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_UNAWARE",
      extraComputations: ["TOLLS"],
      languageCode: "es-CL",
      units: "METRIC",
    }),
  });
  if (!res.ok) throw new HttpError(502, `Route Matrix: ${await res.text()}`);
  const elementos = await res.json();

  const n = puntos.length;
  const m: MatrizCostos = Array.from({ length: n }, (_, i) => Array.from({ length: n }, (_, j) => (i === j ? 0 : 1e12)));
  // deno-lint-ignore no-explicit-any
  for (const e of elementos as any[]) {
    const i = e.originIndex ?? 0;
    const j = e.destinationIndex ?? 0;
    if (i === j || (e.condition && e.condition !== "ROUTE_EXISTS")) continue;
    const km = (e.distanceMeters ?? 0) / 1000;
    const minutos = parseInt(String(e.duration ?? "0s").replace("s", ""), 10) / 60;
    const peajes = (e.travelAdvisory?.tollInfo?.estimatedPrice ?? [])
      // deno-lint-ignore no-explicit-any
      .filter((p: any) => p.currencyCode === "CLP")
      // deno-lint-ignore no-explicit-any
      .reduce((s: number, p: any) => s + Number(p.units ?? 0) + (p.nanos ?? 0) / 1e9, 0);
    m[i][j] = (km / RENDIMIENTO_KM_POR_LITRO) * PRECIO_DIESEL_CLP_POR_LITRO + peajes +
      (COSTO_MAXIMO_POR_10_MIN / 10) * minutos;
  }
  return m;
}

/** Recorrido real por calles en un orden fijo: bodega → paradas → bodega. */
async function calcularRuta(
  apiKey: string,
  origen: Punto,
  paradas: Parada[],
  evitarPeajes: boolean,
  peajes: ContextoPeajes,
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
        "routes.travelAdvisory.tollInfo",
      ].join(","),
    },
    body: JSON.stringify({
      origin: punto(origen),
      destination: punto(origen), // viaje redondo: vuelve a bodega
      intermediates: paradas.map(punto),
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_UNAWARE",
      routeModifiers: { avoidTolls: evitarPeajes, vehicleInfo: { emissionType: "DIESEL" } },
      extraComputations: ["TOLLS"],
      languageCode: "es-CL",
      units: "METRIC",
    }),
  });
  if (!res.ok) throw new HttpError(502, `Routes API: ${await res.text()}`);
  const r = (await res.json()).routes?.[0];
  if (!r) throw new HttpError(502, "Routes API no devolvió rutas");

  const distanciaMetros = r.distanceMeters ?? 0;
  const duracionSegundos = parseInt(String(r.duration ?? "0s").replace("s", ""), 10);
  const polilinea = r.polyline?.encodedPolyline ?? "";

  // TAG: Google no tiene tarifas de autopistas chilenas (devuelve $0), así que
  // se estima con las geocercas de los pórticos y las tarifas MOP 2026.
  const { totalClp, cruces } = estimarPeajes(decodificarPolilinea(polilinea), peajes.porticos, {
    distanciaM: distanciaMetros,
    duracionS: duracionSegundos,
    diaSemana: peajes.diaSemana,
    salidaMinutos: peajes.salidaMinutos,
    categoria: peajes.categoria,
  });

  return {
    distanciaMetros,
    duracionSegundos,
    peajesClp: totalClp,
    polilinea,
    secuencia: paradas,
    usaPeajes: cruces.length > 0,
    cruces,
  };
}
