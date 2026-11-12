// Edge Function: envío de alertas como notificaciones push (RF-19).
//
// La invoca el CRON (public.disparar_envio_push) justo después de
// generar_alertas(). Envía cada alerta aún no notificada al responsable de la
// orden y a los Administradores, por Firebase Cloud Messaging (FCM se usa
// únicamente como canal de envío). Marca la alerta como enviada si llegó al
// menos a un dispositivo y elimina los tokens que FCM reporta como inválidos.
//
// Solo acepta la service_role key (desplegar con --no-verify-jwt).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { HttpError, json, servir } from "../_shared/comun.ts";
import { CuentaServicio, enviarPush, tokenDeAcceso } from "./fcm.ts";
import { AlertaParaEnviar, destinatarios, mensajeAlerta } from "./mensajes.ts";

// Alertas más antiguas que esto ya no se notifican (evita avisos atrasados
// si un teléfono se registra días después).
const ANTIGUEDAD_MAXIMA_HORAS = 36;

servir(async (req) => {
  const claveServicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!claveServicio || req.headers.get("Authorization") !== `Bearer ${claveServicio}`) {
    throw new HttpError(401, "No autorizado");
  }

  const cuentaJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!cuentaJson) throw new HttpError(500, "Falta el secreto FIREBASE_SERVICE_ACCOUNT");
  const cuenta = JSON.parse(cuentaJson) as CuentaServicio;

  const db = createClient(Deno.env.get("SUPABASE_URL")!, claveServicio);

  const desde = new Date(Date.now() - ANTIGUEDAD_MAXIMA_HORAS * 3600 * 1000).toISOString();
  const { data: alertas, error } = await db
    .from("alerta")
    .select("id, orden_id, tipo, orden_compra(cliente, numero_oc, fecha_comprometida, responsable_id)")
    .eq("push_enviada", false)
    .gte("fecha_emision", desde);
  if (error) throw new HttpError(500, error.message);
  if (!alertas?.length) return json({ alertas: 0, enviadas: 0 });

  const { data: admins } = await db.from("usuario").select("id").eq("rol", "administrador");
  const idsAdmin = (admins ?? []).map((u) => u.id as string);

  const { data: dispositivos } = await db.from("dispositivo_push").select("token, usuario_id");
  const tokensPorUsuario = new Map<string, string[]>();
  for (const d of dispositivos ?? []) {
    tokensPorUsuario.set(d.usuario_id, [...(tokensPorUsuario.get(d.usuario_id) ?? []), d.token]);
  }

  const accessToken = await tokenDeAcceso(cuenta);
  const enviadas: string[] = [];
  const tokensInvalidos = new Set<string>();

  for (const a of alertas) {
    // deno-lint-ignore no-explicit-any
    const orden = a.orden_compra as any;
    const datosAlerta: AlertaParaEnviar = {
      tipo: a.tipo,
      cliente: orden.cliente,
      numeroOc: orden.numero_oc,
      fechaComprometida: orden.fecha_comprometida,
    };
    const { titulo, cuerpo } = mensajeAlerta(datosAlerta);
    const tokens = destinatarios(orden.responsable_id, idsAdmin)
      .flatMap((id) => tokensPorUsuario.get(id) ?? [])
      .filter((t) => !tokensInvalidos.has(t));

    let exitos = 0;
    for (const token of tokens) {
      const r = await enviarPush(accessToken, cuenta.project_id, token, {
        titulo,
        cuerpo,
        datos: { alerta_id: a.id, orden_id: a.orden_id, tipo: a.tipo },
      });
      if (r === "ok") exitos++;
      if (r === "token_invalido") tokensInvalidos.add(token);
    }
    if (exitos > 0) enviadas.push(a.id);
  }

  if (enviadas.length) {
    await db.from("alerta").update({ push_enviada: true }).in("id", enviadas);
  }
  if (tokensInvalidos.size) {
    await db.from("dispositivo_push").delete().in("token", [...tokensInvalidos]);
  }

  return json({
    alertas: alertas.length,
    enviadas: enviadas.length,
    tokensEliminados: tokensInvalidos.size,
  });
});
