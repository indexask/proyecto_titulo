// Edge Function: recibe un PDF de cotización en base64 y usa Google Gemini
// (nivel gratuito) para extraer los campos estructurados. Solo admins
// pueden invocarla.
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const EXTRACTION_PROMPT = `Eres un asistente que extrae datos de documentos de cotizaciones comerciales chilenas. Lee el PDF adjunto y devuelve los siguientes campos:

- numero_cotizacion: el número de la cotización.
- fecha_cotizacion: la fecha en formato ISO YYYY-MM-DD.
- solicitado_por: el nombre del cliente/empresa que solicita la cotización.
- direccion_entrega: la dirección donde se debe entregar (normalmente la del "Solicitado por" o "Entregar en").
- descripcion: descripción del producto o servicio principal cotizado.
- unidades: cantidad de unidades del ítem principal.
- precio_unidad: precio unitario, sin símbolo de moneda ni puntos de miles.
- total: monto total de la cotización, sin símbolo de moneda ni puntos de miles.

Si un campo no aparece en el documento, usa null.`;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    numero_cotizacion: { type: "STRING", nullable: true },
    fecha_cotizacion: { type: "STRING", nullable: true },
    solicitado_por: { type: "STRING", nullable: true },
    direccion_entrega: { type: "STRING", nullable: true },
    descripcion: { type: "STRING", nullable: true },
    unidades: { type: "NUMBER", nullable: true },
    precio_unidad: { type: "NUMBER", nullable: true },
    total: { type: "NUMBER", nullable: true },
  },
};

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

    const { pdfBase64 } = await req.json();
    if (!pdfBase64) {
      return json({ error: "Falta pdfBase64" }, 400);
    }

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: EXTRACTION_PROMPT },
                {
                  inline_data: {
                    mime_type: "application/pdf",
                    data: pdfBase64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: RESPONSE_SCHEMA,
          },
        }),
      },
    );

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      return json({ error: `Error de Gemini: ${errText}` }, 502);
    }

    const geminiData = await geminiRes.json();
    const rawText: string =
      geminiData.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
    const extracted = JSON.parse(rawText);

    return json(extracted, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
