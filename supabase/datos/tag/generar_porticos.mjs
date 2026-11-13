// Genera la migración con los pórticos TAG de Santiago (ubicación + tarifas).
//
//   Ubicación y sentido: OpenStreetMap (nodos highway=toll_gantry y la calzada
//   de un sentido donde están), © colaboradores de OpenStreetMap, licencia ODbL.
//   Tarifas y horarios: MOP / Dirección General de Concesiones, "Peajes
//   Tarifas 2026" (tarifas_2026.json, transcritas de los PDF oficiales).
//
// Uso: node supabase/datos/tag/generar_porticos.mjs
// Escribe supabase/migrations/20261113000000_porticos_tag.sql (autopistas
// urbanas) y 20261114000000_peajes_interurbanos.sql (accesos a Santiago, con
// tarifas_interurbanas_2026.json) e imprime un informe de emparejamiento.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));
const osm = JSON.parse(fs.readFileSync(path.join(dir, "osm_porticos_santiago.json"), "utf8"));
const tarifas = JSON.parse(fs.readFileSync(path.join(dir, "tarifas_2026.json"), "utf8"));

// En el sentido poniente-oriente, P8.0 y P8.1 de Costanera Norte (eje Kennedy)
// tienen el mismo precio pero el horario de P8.2/P8.3.
for (const codigo of ["P8.0", "P8.1"]) {
  const po = tarifas.porticos.find((t) => t.concesion === "Costanera Norte" && t.codigo === "P8.2");
  tarifas.porticos.push({ ...po, codigo, tramo: "Costanera Norte - Las Tranqueras" });
}

const sinTilde = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const palabras = (s) => sinTilde(s).replace(/[^a-z0-9 ]/g, " ").split(/\s+/).filter((w) => w.length > 2);

/** Rumbo (0-360°, 0 = norte) del tramo de calzada que pasa por el pórtico. */
function rumbo(a, b) {
  const rad = Math.PI / 180;
  const y = Math.sin((b.lon - a.lon) * rad) * Math.cos(b.lat * rad);
  const x = Math.cos(a.lat * rad) * Math.sin(b.lat * rad) -
    Math.sin(a.lat * rad) * Math.cos(b.lat * rad) * Math.cos((b.lon - a.lon) * rad);
  return (Math.atan2(y, x) / rad + 360) % 360;
}

const nodos = osm.elements.filter((e) => e.type === "node");
const vias = osm.elements.filter((e) => e.type === "way");

function viaDe(n) {
  for (const v of vias) {
    const g = v.geometry ?? [];
    const i = g.findIndex((p) => Math.abs(p.lat - n.lat) < 1e-7 && Math.abs(p.lon - n.lon) < 1e-7);
    if (i >= 0) return { via: v, indice: i };
  }
  return null;
}

/** Concesión según la autopista (o el código si la calzada no tiene nombre). */
function concesionDe(nombreVia, ref) {
  const v = sinTilde(nombreVia ?? "");
  if (v.includes("autopista central") || v.includes("general velasquez")) return "Autopista Central";
  if (v.includes("costanera norte") || v.includes("presidente kennedy")) return "Costanera Norte";
  if (v.includes("vespucio norte")) return "Vespucio Norte";
  if (v.includes("vespucio sur")) return "Vespucio Sur";
  if (v.includes("tunel san cristobal")) return "Túnel San Cristóbal";
  if (v.includes("nororiente")) return "Acceso Nororiente";
  if (v.includes("aeropuerto")) return "Acceso Vial AMB";
  if (v.includes("vespucio oriente")) return "Américo Vespucio Oriente";
  // Calzadas sin nombre: se deduce por el código.
  if (/^P(00|8\.\d|SB|EV|EP)$|^(SB|EV|EP)$/.test(ref ?? "")) return "Costanera Norte";
  if (/^P(1\d\d|2\d\d)$/.test(ref ?? "")) return "Américo Vespucio Oriente";
  if (ref === "P11") return "Vespucio Norte";
  return null;
}

function codigoNormalizado(concesion, ref, nombre) {
  let c = (ref ?? "").split(" ")[0];
  if (concesion === "Costanera Norte") c = c.replace(/^P0(\d)$/, "P$1");
  if (concesion === "Vespucio Sur") c = c.replace(/^P/, "");
  if (concesion === "Túnel San Cristóbal") return sinTilde(nombre).includes("salto - kennedy") ? "El Salto - Kennedy" : "Kennedy - El Salto";
  if (concesion === "Acceso Nororiente") return /Poniente/.test(nombre) ? "Sector Poniente" : "Sector Oriente";
  if (concesion === "Acceso Vial AMB") return "Pórtico AMB";
  if (concesion === "Américo Vespucio Oriente") return c === "P110" ? "P110" : "AVO-I";
  return c;
}

/** Entre varias tarifas con el mismo código, la del tramo que mejor calza con el nombre OSM (en orden). */
function elegirTarifa(candidatas, nombreOsm) {
  if (candidatas.length === 1) return candidatas[0];
  const n = palabras(nombreOsm);
  const puntaje = (t) => {
    const [desde, hasta = ""] = t.tramo.split(" - ");
    // Solo las palabras que distinguen cada extremo ("puente" aparece en ambos).
    const pd = palabras(desde), ph = palabras(hasta);
    const propiasDesde = pd.filter((w) => !ph.includes(w));
    const propiasHasta = ph.filter((w) => !pd.includes(w));
    const posicion = (ws) => {
      const i = n.findIndex((w) => ws.includes(w));
      return i < 0 ? Infinity : i;
    };
    // El extremo de origen debe aparecer antes que el de destino en el nombre OSM.
    const ordenCorrecto = posicion(propiasDesde) < posicion(propiasHasta) ? 100 : 0;
    const coincidencias = palabras(t.tramo).filter((w) => n.includes(w)).length;
    return ordenCorrecto + coincidencias;
  };
  return [...candidatas].sort((a, b) => puntaje(b) - puntaje(a))[0];
}

const filas = [];
const sinTarifa = [];
const pendientes = []; // nodos sin tarifa urbana: se revisan como peajes interurbanos
for (const n of nodos) {
  const ref = n.tags.ref ?? "";
  const nombre = n.tags.name ?? ref;
  const ubic = viaDe(n);
  const nombreVia = ubic?.via.tags.name ?? ubic?.via.tags.ref;
  const concesion = concesionDe(nombreVia, ref);
  if (!concesion) {
    sinTarifa.push(`${ref || "(sin ref)"} ${nombre} [${nombreVia ?? "?"}]`);
    pendientes.push(n);
    continue;
  }
  const codigo = codigoNormalizado(concesion, ref, nombre);
  const candidatas = tarifas.porticos.filter((t) => t.concesion === concesion && t.codigo === codigo);
  if (candidatas.length === 0) {
    sinTarifa.push(`${ref} ${nombre} [${concesion}] → código ${codigo} sin tarifa`);
    pendientes.push(n);
    continue;
  }
  const t = elegirTarifa(candidatas, `${ref} ${nombre}`);

  let sentido = null;
  if (ubic) {
    const g = ubic.via.geometry;
    const i = ubic.indice;
    const a = g[Math.max(0, i - 1)], b = g[Math.min(g.length - 1, i + 1)];
    sentido = rumbo(a, b);
    if (ubic.via.tags.oneway === "-1") sentido = (sentido + 180) % 360;
  }
  filas.push({
    osm_id: n.id, concesion, codigo, tramo: t.tramo, lat: n.lat, lng: n.lon,
    rumbo: sentido === null ? null : Math.round(sentido * 10) / 10,
    km: t.km ?? 0, por_km: !!t.porKm, tarifas: t.tarifas, horario: t.horario ?? {},
    nombre_osm: nombre,
  });
}

const sql = (v) => (v === null || v === undefined ? "null" : typeof v === "number" ? String(v) : `'${String(v).replace(/'/g, "''")}'`);
const json = (v) => `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`;

const migracion = `-- ============================================================================
-- GyGTrack — Pórticos TAG de Santiago para estimar el costo de peajes (RF-24).
-- GENERADO por supabase/datos/tag/generar_porticos.mjs — no editar a mano.
--
-- Ubicación y sentido: © colaboradores de OpenStreetMap (ODbL),
--   highway=toll_gantry y la calzada de un sentido donde se ubica cada pórtico.
-- Tarifas y horarios: MOP / Dirección General de Concesiones, Peajes Tarifas
--   2026 (con TAG habilitado). Categoría 1: autos y camionetas; 2: buses y
--   camiones. Ventanas horarias transcritas de los PDF [VALIDAR].
-- ============================================================================

create table public.portico (
  id bigint generated always as identity primary key,
  osm_id bigint unique,
  concesion text not null,
  codigo text not null,
  tramo text not null,
  lat double precision not null,
  lng double precision not null,
  rumbo double precision,              -- sentido de cobro (grados, 0 = norte)
  km numeric(8, 3) not null default 0,
  por_km boolean not null default false, -- tarifa por km recorrido (AVO I)
  tarifas jsonb not null,              -- {"1": {"tbfp":..,"tbp":..,"ts":..}, "2": {...}}
  horario jsonb not null default '{}', -- {"laboral": {"tbp": [["07:00","09:30"]], "ts": [...]}, ...}
  vigencia integer not null default 2026,
  activo boolean not null default true
);

alter table public.portico enable row level security;
create policy "portico: administrador" on public.portico
  for all using (public.es_administrador()) with check (public.es_administrador());

insert into public.portico (osm_id, concesion, codigo, tramo, lat, lng, rumbo, km, por_km, tarifas, horario) values
${filas.map((f) => `  (${[f.osm_id, sql(f.concesion), sql(f.codigo), sql(f.tramo), f.lat, f.lng, sql(f.rumbo), f.km, f.por_km, json(f.tarifas), json(f.horario)].join(", ")})`).join(",\n")};
`;

const salida = path.join(dir, "..", "..", "migrations", "20261113000000_porticos_tag.sql");
fs.writeFileSync(salida, migracion);

const porConcesion = {};
filas.forEach((f) => (porConcesion[f.concesion] = (porConcesion[f.concesion] || 0) + 1));
console.log(`Pórticos con tarifa: ${filas.length} de ${nodos.length}`);
console.log(porConcesion);
console.log(`Sin rumbo: ${filas.filter((f) => f.rumbo === null).length}`);
console.log(`\nSin tarifa (${sinTarifa.length}):\n  ` + sinTarifa.join("\n  "));
console.log(`\nVerificación de sentido (código → tramo elegido ← nombre OSM):`);
for (const f of filas.filter((x) => x.concesion === "Costanera Norte")) {
  console.log(`  ${f.codigo.padEnd(5)} ${f.tramo.padEnd(42)} ← ${f.nombre_osm}`);
}
console.log(`\nMigración: ${path.relative(process.cwd(), salida)}`);

// ============================================================================
// Peajes interurbanos (accesos a Santiago): plazas troncales y pórticos de
// Ruta 5 Norte/Sur, Ruta 68, Ruta 78 y Autopista Los Libertadores.
// Ubicación: nodos del extracto urbano que no tuvieron tarifa urbana +
// osm_peajes_interurbanos.json (toll_booth/toll_gantry con su calzada).
// ============================================================================
const inter = JSON.parse(fs.readFileSync(path.join(dir, "osm_peajes_interurbanos.json"), "utf8"));
const tarifasInter = JSON.parse(fs.readFileSync(path.join(dir, "tarifas_interurbanas_2026.json"), "utf8"));
const viasInter = [...vias, ...inter.elements.filter((e) => e.type === "way" && e.tags.highway !== "footway")];

const R5S = "Ruta 5 Sur (Santiago - Talca)";
const R5N = "Ruta 5 Norte (Santiago - Los Vilos)";
const REGLAS = [
  [/chacabuco/, "Autopista Los Libertadores", "Chacabuco"],
  [/las canteras/, "Autopista Los Libertadores", "Las Canteras"],
  [/peaje san jose/, "Autopista Los Libertadores", "San José"],
  [/troncal lo prado/, "Ruta 68", "Lo Prado"],
  [/zapata/, "Ruta 68", "Zapata"],
  [/troncal sur rutas del pacifico/, "Ruta 68", "Troncal Sur"],
  [/pomaire/, "Ruta 78", "T8"],
  [/puangue/, "Ruta 78", "T10"],
  [/^t(1|2|3|4|6|7)\b/, "Ruta 78", null], // código = ref (T1 … T7)
  [/angostura/, R5S, "Angostura"],
  [/rio maipo/, R5S, "Río Maipo"],
  [/gabriela/, R5S, "Gabriela"],
  [/tocornal/, R5S, "Tocornal"],
  [/lo marcoleta/, R5N, "Lo Marcoleta"],
  [/buenaventura/, R5N, "Buenaventura"],
  [/la montana/, R5N, "La Montaña"],
  [/lo pinto/, R5N, "Lo Pinto"],
  [/peaje lampa/, R5N, "Lampa"],
  [/pichidangui/, R5N, "Pichidangui"],
  [/tunel el melon/, R5N, "Túnel El Melón"],
];

const vistos = new Set(filas.map((f) => f.osm_id));
const candidatosInter = [];
for (const n of [...pendientes, ...inter.elements.filter((e) => e.type === "node")]) {
  if (vistos.has(n.id)) continue;
  vistos.add(n.id);
  candidatosInter.push(n);
}

const filasInter = [];
const sinTarifaInter = [];
for (const n of candidatosInter) {
  const ref = n.tags.ref ?? "";
  const nombre = n.tags.name ?? "";
  const texto = sinTilde(`${ref} ${nombre}`.trim());
  const regla = REGLAS.find(([re]) => re.test(texto));
  if (!regla) {
    sinTarifaInter.push(`${n.id} ${ref} ${nombre}`.trim());
    continue;
  }
  const [, concesion, codigoFijo] = regla;
  const codigo = codigoFijo ?? ref.split(" ")[0].toUpperCase();
  const t = tarifasInter.porticos.find((p) => p.concesion === concesion && p.codigo === codigo);
  if (!t) {
    sinTarifaInter.push(`${n.id} ${ref} ${nombre} → ${concesion} ${codigo} sin tarifa`);
    continue;
  }
  // Sentido: solo si la calzada es de un sentido. En una calzada de doble
  // sentido la plaza cobra en ambos sentidos (rumbo null).
  let sentido = null;
  for (const v of viasInter) {
    const g = v.geometry ?? [];
    const i = g.findIndex((p) => Math.abs(p.lat - n.lat) < 1e-7 && Math.abs(p.lon - n.lon) < 1e-7);
    if (i < 0) continue;
    if (v.tags.oneway === "yes" || v.tags.oneway === "-1" || v.tags.highway === "motorway") {
      const a = g[Math.max(0, i - 1)], b = g[Math.min(g.length - 1, i + 1)];
      sentido = rumbo(a, b);
      if (v.tags.oneway === "-1") sentido = (sentido + 180) % 360;
    }
    break;
  }
  filasInter.push({
    osm_id: n.id, concesion, codigo, tramo: t.tramo, lat: n.lat, lng: n.lon,
    rumbo: sentido === null ? null : Math.round(sentido * 10) / 10,
    km: 0, por_km: false, tarifas: t.tarifas, horario: t.horario ?? {}, nombre_osm: `${ref} ${nombre}`.trim(),
  });
}

// Una plaza suele tener varios nodos en el mismo sentido (casetas + pórtico
// free flow): se deja uno por sentido para no cobrar dos veces la pasada.
const metros = (a, b) => {
  const rad = Math.PI / 180;
  const x = (b.lng - a.lng) * rad * Math.cos(((a.lat + b.lat) / 2) * rad), y = (b.lat - a.lat) * rad;
  return Math.sqrt(x * x + y * y) * 6371000;
};
const mismoSentido = (a, b) =>
  a.rumbo === null || b.rumbo === null || Math.abs(((a.rumbo - b.rumbo + 540) % 360) - 180) <= 60;
const filasPlaza = [];
for (const f of filasInter.sort((a, b) => a.osm_id - b.osm_id)) {
  const dup = filasPlaza.find((g) => g.concesion === f.concesion && g.codigo === f.codigo &&
    metros(g, f) < 300 && mismoSentido(g, f));
  if (!dup) filasPlaza.push(f);
}

const migracionInter = `-- ============================================================================
-- GyGTrack — Peajes interurbanos de los accesos a Santiago (RF-24).
-- GENERADO por supabase/datos/tag/generar_porticos.mjs — no editar a mano.
--
-- Ubicación y sentido: © colaboradores de OpenStreetMap (ODbL), nodos
--   toll_booth/toll_gantry y su calzada (rumbo null = cobra en ambos sentidos).
-- Tarifas: MOP / Dirección General de Concesiones, Peajes Tarifas 2026 (con
--   TAG): Autopista Los Libertadores, Ruta 68, Ruta 78, Ruta 5 Sur
--   (Santiago - Talca) y Ruta 5 Norte (Santiago - Los Vilos). Los horarios
--   punta que los PDF no definen se estiman con la tarifa normal [VALIDAR].
-- ============================================================================

insert into public.portico (osm_id, concesion, codigo, tramo, lat, lng, rumbo, km, por_km, tarifas, horario) values
${filasPlaza.map((f) => `  (${[f.osm_id, sql(f.concesion), sql(f.codigo), sql(f.tramo), f.lat, f.lng, sql(f.rumbo), f.km, f.por_km, json(f.tarifas), json(f.horario)].join(", ")})`).join(",\n")}
on conflict (osm_id) do nothing;
`;
const salidaInter = path.join(dir, "..", "..", "migrations", "20261114000000_peajes_interurbanos.sql");
fs.writeFileSync(salidaInter, migracionInter);

console.log(`\n--- Peajes interurbanos ---`);
console.log(`Nodos con tarifa: ${filasInter.length}; tras unir nodos de la misma plaza y sentido: ${filasPlaza.length}`);
for (const f of filasPlaza) {
  console.log(`  ${f.concesion.padEnd(36)} ${f.codigo.padEnd(15)} rumbo ${String(f.rumbo ?? "ambos").padEnd(6)} ← ${f.nombre_osm}`);
}
console.log(`Sin regla o sin tarifa (${sinTarifaInter.length}):\n  ` + sinTarifaInter.join("\n  "));
console.log(`Migración: ${path.relative(process.cwd(), salidaInter)}`);
