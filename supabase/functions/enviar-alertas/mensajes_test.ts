// node --test supabase/functions/enviar-alertas/mensajes_test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { destinatarios, mensajeAlerta } from "./mensajes.ts";

test("mensaje Día Cero", () => {
  const m = mensajeAlerta({
    tipo: "dia_cero",
    cliente: "Hospital Y",
    numeroOc: "1234-56-SE26",
    fechaComprometida: "2026-11-12",
  });
  assert.equal(m.titulo, "Día Cero: entrega vence HOY");
  assert.equal(m.cuerpo, "Hospital Y (OC 1234-56-SE26): el plazo de entrega vence hoy (12-11-2026).");
});

test("mensaje preventivo sin número de OC", () => {
  const m = mensajeAlerta({
    tipo: "preventiva",
    cliente: "Liceo Z",
    numeroOc: null,
    fechaComprometida: "2026-11-15",
  });
  assert.equal(m.cuerpo, "Liceo Z: el plazo de entrega vence el 15-11-2026.");
});

test("destinatarios: responsable + administradores sin duplicar", () => {
  assert.deepEqual(destinatarios("c1", ["a1", "c1"]), ["c1", "a1"]);
  assert.deepEqual(destinatarios(null, ["a1"]), ["a1"]);
});
