// Edge Function: geocodifica una dirección con Google Places API (Text Search)
// y devuelve la dirección normalizada y sus coordenadas.
// Usada al registrar la dirección de entrega de una orden y el origen de una
// ruta (Módulo Enrutamiento, RF-22). Solo para el Administrador.
import { clienteAdministrador, googleMapsApiKey, HttpError, json, servir } from "../_shared/comun.ts";
import { geocodificarDireccion } from "../_shared/places.ts";

servir(async (req) => {
  await clienteAdministrador(req);

  const { direccion } = (await req.json()) as { direccion?: string };
  if (!direccion || direccion.trim().length < 3) {
    throw new HttpError(400, "Falta la dirección");
  }

  return json(await geocodificarDireccion(googleMapsApiKey(), direccion));
});
