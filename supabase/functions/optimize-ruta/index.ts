// Edge Function: recibe un origen y una lista de waypoints (puntos de
// entrega) y devuelve el orden optimizado usando Google Directions API
// (viaje redondo: origen -> waypoints optimizados -> origen).
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const GOOGLE_DIRECTIONS_API_KEY = Deno.env.get("GOOGLE_DIRECTIONS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

interface Waypoint {
  lat: number;
  lng: number;
  cotizacionId: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: "No autenticado" }, 401);
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", userData.user.id)
      .single();

    if (profile?.role !== "admin") {
      return json({ error: "Solo administradores pueden usar esta función" }, 403);
    }

    const { origin, waypoints } = (await req.json()) as {
      origin: { lat: number; lng: number };
      waypoints: Waypoint[];
    };

    if (!origin || !waypoints || waypoints.length === 0) {
      return json({ error: "Falta origin o waypoints" }, 400);
    }

    if (waypoints.length === 1) {
      // Un solo punto: no hay nada que optimizar, pero igual pedimos
      // distancia/duración a Directions para el resumen de la ruta.
      const single = waypoints[0];
      const url = new URL("https://maps.googleapis.com/maps/api/directions/json");
      url.searchParams.set("origin", `${origin.lat},${origin.lng}`);
      url.searchParams.set("destination", `${origin.lat},${origin.lng}`);
      url.searchParams.set("waypoints", `${single.lat},${single.lng}`);
      url.searchParams.set("key", GOOGLE_DIRECTIONS_API_KEY);

      const res = await fetch(url);
      const data = await res.json();
      const { distanciaKm, duracionMin } = sumLegs(data);

      return json(
        { order: [single.cotizacionId], distanciaKm, duracionMin },
        200,
      );
    }

    const waypointsParam =
      "optimize:true|" + waypoints.map((w) => `${w.lat},${w.lng}`).join("|");

    const url = new URL("https://maps.googleapis.com/maps/api/directions/json");
    url.searchParams.set("origin", `${origin.lat},${origin.lng}`);
    url.searchParams.set("destination", `${origin.lat},${origin.lng}`);
    url.searchParams.set("waypoints", waypointsParam);
    url.searchParams.set("key", GOOGLE_DIRECTIONS_API_KEY);

    const res = await fetch(url);
    const data = await res.json();

    if (data.status !== "OK") {
      return json({ error: `Directions API: ${data.status} ${data.error_message ?? ""}` }, 502);
    }

    const waypointOrder: number[] = data.routes[0].waypoint_order;
    const order = waypointOrder.map((i) => waypoints[i].cotizacionId);
    const { distanciaKm, duracionMin } = sumLegs(data);

    return json({ order, distanciaKm, duracionMin }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function sumLegs(directionsData: {
  routes?: { legs: { distance: { value: number }; duration: { value: number } }[] }[];
}) {
  const legs = directionsData.routes?.[0]?.legs ?? [];
  const distanciaM = legs.reduce((sum, l) => sum + l.distance.value, 0);
  const duracionS = legs.reduce((sum, l) => sum + l.duration.value, 0);
  return {
    distanciaKm: Math.round((distanciaM / 1000) * 10) / 10,
    duracionMin: Math.round(duracionS / 60),
  };
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
