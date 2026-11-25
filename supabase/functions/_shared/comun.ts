// Utilidades compartidas por las Edge Functions de GyGTrack.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/**
 * Crea un cliente Supabase con el JWT del usuario que llama (respeta RLS) y
 * verifica que tenga rol Administrador. Lanza HttpError si no corresponde.
 */
export async function clienteAdministrador(req: Request): Promise<SupabaseClient> {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: userData, error } = await supabase.auth.getUser();
  if (error || !userData.user) throw new HttpError(401, "No autenticado");

  const { data: usuario } = await supabase
    .from("usuario")
    .select("rol")
    .eq("id", userData.user.id)
    .single();

  if (usuario?.rol !== "administrador") {
    throw new HttpError(403, "Solo el Administrador puede usar esta función");
  }
  return supabase;
}

export function googleMapsApiKey(): string {
  const key = Deno.env.get("GOOGLE_MAPS_API_KEY");
  if (!key) throw new HttpError(500, "Falta el secreto GOOGLE_MAPS_API_KEY");
  return key;
}

/** Envuelve un handler con CORS y manejo uniforme de errores. */
export function servir(handler: (req: Request) => Promise<Response>) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    try {
      return await handler(req);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      return json({ error: String(e) }, 500);
    }
  });
}
