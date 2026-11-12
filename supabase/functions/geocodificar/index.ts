// Edge Function: geocodifica una dirección con Google Places API (Text Search)
// y devuelve la dirección normalizada y sus coordenadas.
// Usada al registrar la dirección de entrega de una orden y el origen de una
// ruta (Módulo Enrutamiento, RF-22). Solo para el Administrador.
import {
  clienteAdministrador,
  googleMapsApiKey,
  HttpError,
  json,
  servir,
} from "../_shared/comun.ts";

servir(async (req) => {
  await clienteAdministrador(req);

  const { direccion } = (await req.json()) as { direccion?: string };
  if (!direccion || direccion.trim().length < 3) {
    throw new HttpError(400, "Falta la dirección");
  }

  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": googleMapsApiKey(),
      "X-Goog-FieldMask": "places.formattedAddress,places.location",
    },
    body: JSON.stringify({
      textQuery: direccion.trim(),
      regionCode: "CL",
      languageCode: "es",
      pageSize: 1,
    }),
  });

  if (!res.ok) {
    throw new HttpError(502, `Places API: ${await res.text()}`);
  }

  const data = await res.json();
  const lugar = data.places?.[0];
  if (!lugar?.location) {
    throw new HttpError(404, "No se encontró la dirección");
  }

  return json({
    direccion: lugar.formattedAddress ?? direccion.trim(),
    lat: lugar.location.latitude,
    lng: lugar.location.longitude,
  });
});
