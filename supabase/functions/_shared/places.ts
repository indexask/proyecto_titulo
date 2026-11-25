// Geocodificación con Google Places API (Text Search). Compartido por las
// funciones geocodificar y optimizar-ruta.
import { HttpError } from "./comun.ts";

export interface LugarGeocodificado {
  direccion: string;
  lat: number;
  lng: number;
}

export async function geocodificarDireccion(apiKey: string, direccion: string): Promise<LugarGeocodificado> {
  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "places.formattedAddress,places.location",
    },
    body: JSON.stringify({
      textQuery: direccion.trim(),
      regionCode: "CL",
      languageCode: "es",
      pageSize: 1,
    }),
  });
  if (!res.ok) throw new HttpError(502, `Places API: ${await res.text()}`);

  const lugar = (await res.json()).places?.[0];
  if (!lugar?.location) throw new HttpError(404, `No se encontró la dirección: ${direccion}`);
  return {
    direccion: lugar.formattedAddress ?? direccion.trim(),
    lat: lugar.location.latitude,
    lng: lugar.location.longitude,
  };
}
