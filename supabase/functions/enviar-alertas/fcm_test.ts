// node --test supabase/functions/enviar-alertas/fcm_test.ts
// Verifica la firma RS256 del JWT de la cuenta de servicio y la clasificación
// de respuestas de FCM, sin llamar a Google (fetch simulado).
import { test } from "node:test";
import assert from "node:assert/strict";
import { createVerify, generateKeyPairSync } from "node:crypto";
import { enviarPush, tokenDeAcceso } from "./fcm.ts";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const cuenta = {
  project_id: "gygtrack-prueba",
  client_email: "push@gygtrack-prueba.iam.gserviceaccount.com",
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
};

test("tokenDeAcceso firma un JWT RS256 válido para el scope de FCM", async () => {
  let jwt = "";
  globalThis.fetch = (async (_url: string, init: RequestInit) => {
    jwt = new URLSearchParams(init.body as URLSearchParams).get("assertion")!;
    return new Response(JSON.stringify({ access_token: "ya29.prueba" }));
  }) as typeof fetch;

  assert.equal(await tokenDeAcceso(cuenta), "ya29.prueba");

  const [h, c, firma] = jwt.split(".");
  const verificador = createVerify("RSA-SHA256");
  verificador.update(`${h}.${c}`);
  assert.ok(verificador.verify(publicKey, Buffer.from(firma, "base64url")), "firma válida");

  const reclamos = JSON.parse(Buffer.from(c, "base64url").toString());
  assert.equal(reclamos.iss, cuenta.client_email);
  assert.equal(reclamos.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assert.equal(reclamos.exp - reclamos.iat, 3600);
});

test("enviarPush clasifica las respuestas de FCM", async () => {
  const responder = (status: number, cuerpo = "{}") =>
    (globalThis.fetch = (async () => new Response(cuerpo, { status })) as typeof fetch);
  const msg = { titulo: "t", cuerpo: "c", datos: {} };

  responder(200);
  assert.equal(await enviarPush("x", "p", "tok", msg), "ok");
  responder(404, '{"error":{"status":"NOT_FOUND"}}');
  assert.equal(await enviarPush("x", "p", "tok", msg), "token_invalido");
  responder(400, '{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}');
  assert.equal(await enviarPush("x", "p", "tok", msg), "token_invalido");
  responder(500);
  assert.equal(await enviarPush("x", "p", "tok", msg), "error");
});
