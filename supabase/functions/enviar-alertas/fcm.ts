// Cliente mínimo de Firebase Cloud Messaging (API HTTP v1). FCM se usa
// únicamente como canal de envío de notificaciones push.

export interface CuentaServicio {
  project_id: string;
  client_email: string;
  private_key: string;
}

export type ResultadoEnvio = "ok" | "token_invalido" | "error";

function base64url(datos: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof datos === "string"
    ? new TextEncoder().encode(datos)
    : datos instanceof Uint8Array
    ? datos
    : new Uint8Array(datos);
  let binario = "";
  for (const b of bytes) binario += String.fromCharCode(b);
  return btoa(binario).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Obtiene un token OAuth2 firmando un JWT con la cuenta de servicio. */
export async function tokenDeAcceso(cuenta: CuentaServicio): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  const encabezado = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const reclamos = base64url(JSON.stringify({
    iss: cuenta.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: ahora,
    exp: ahora + 3600,
  }));

  const pem = cuenta.private_key
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const clave = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const firma = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    clave,
    new TextEncoder().encode(`${encabezado}.${reclamos}`),
  );
  const jwt = `${encabezado}.${reclamos}.${base64url(firma)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth de Google: ${await res.text()}`);
  return (await res.json()).access_token;
}

export async function enviarPush(
  accessToken: string,
  projectId: string,
  token: string,
  mensaje: { titulo: string; cuerpo: string; datos: Record<string, string> },
): Promise<ResultadoEnvio> {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: mensaje.titulo, body: mensaje.cuerpo },
        data: mensaje.datos,
        android: { priority: "HIGH" },
        apns: { payload: { aps: { sound: "default" } } },
      },
    }),
  });
  if (res.ok) return "ok";

  const texto = await res.text();
  // Token desinstalado o inválido: se elimina del registro.
  if (res.status === 404 || /UNREGISTERED|registration-token-not-registered/.test(texto)) {
    return "token_invalido";
  }
  console.error(`FCM ${res.status}: ${texto}`);
  return "error";
}
