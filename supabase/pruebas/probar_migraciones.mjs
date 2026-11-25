// Prueba las migraciones de GyGTrack sobre PostgreSQL real (PGlite), simulando
// lo mínimo de Supabase (auth, storage, cron, roles). Uso:
//   cd supabase/pruebas && npm install && npm test
import { PGlite } from "@electric-sql/pglite";
import { uuid_ossp } from "@electric-sql/pglite/contrib/uuid_ossp";
import fs from "node:fs";
import path from "node:path";
import { respaldar } from "../respaldo/respaldar_prototipo.mjs";

// Antes de la migración que borra el prototipo: carga datos de ejemplo con el
// esquema antiguo, los respalda y verifica que el SQL generado los restaure.
async function probarRespaldo() {
  const U = "00000000-0000-0000-0000-0000000000f1";
  await db.exec(`
    insert into auth.users (id, raw_user_meta_data) values ('${U}', '{"full_name":"O''Higgins"}');
    update public.profiles set role = 'admin' where id = '${U}';
    insert into public.cotizaciones (id, titulo, cliente, monto, admin_id, direccion_entrega)
      values ('00000000-0000-0000-0000-0000000000f2', 'Cot. 1', 'Cliente ''A''', 1234567, '${U}', 'Av. 1');
    insert into public.rutas (id, chofer_id, nombre) values ('00000000-0000-0000-0000-0000000000f3', '${U}', 'Ruta 1');
    insert into public.puntos_ruta (ruta_id, direccion, lat, lng, cotizacion_id)
      values ('00000000-0000-0000-0000-0000000000f3', 'Av. 1', -33.4, -70.6, '00000000-0000-0000-0000-0000000000f2');
  `);
  const { datos, sql } = await respaldar(db);
  ok(datos.profiles.length === 1 && datos.cotizaciones.length === 1 && datos.rutas.length === 1 &&
     datos.puntos_ruta.length === 1, "respaldo del prototipo incluye las 4 tablas");

  await db.exec(`delete from public.puntos_ruta; delete from public.rutas; delete from public.cotizaciones;
                 delete from public.profiles;`);
  await db.exec(sql);
  const r = await db.query(`select c.cliente, c.monto, p.full_name from public.cotizaciones c
                            join public.profiles p on p.id = c.admin_id`);
  ok(r.rows.length === 1 && r.rows[0].cliente === "Cliente 'A'" && Number(r.rows[0].monto) === 1234567 &&
     r.rows[0].full_name === "O'Higgins", "el SQL del respaldo restaura los datos (incluidas comillas)");
  ok((await db.query(`select count(*)::int n from public.puntos_ruta`)).rows[0].n === 1,
    "se restauran también rutas y puntos de ruta");

  await db.exec(`delete from public.puntos_ruta; delete from public.rutas; delete from public.cotizaciones;
                 delete from public.profiles; delete from auth.users;`);
}

const dirMigraciones = process.argv[2];
const db = new PGlite({ extensions: { uuid_ossp } });

let fallos = 0;
const ok = (cond, msg) => {
  console.log(`${cond ? "✔" : "✘"} ${msg}`);
  if (!cond) fallos++;
};

await db.exec(`
  create role anon nologin; create role authenticated nologin;
  grant usage on schema public to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant all on functions to anon, authenticated;
  create schema auth;
  create table auth.users (id uuid primary key, raw_user_meta_data jsonb default '{}');
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function auth.role() returns text language sql stable as $$ select 'authenticated' $$;
  grant usage on schema auth to anon, authenticated;
  create schema storage;
  create table storage.buckets (id text primary key, name text, public boolean);
  create table storage.objects (id serial primary key, bucket_id text);
  create schema cron;
  create table cron.job (jobname text primary key, schedule text, command text);
  create function cron.schedule(n text, s text, c text) returns bigint language sql as
    $$ insert into cron.job values (n, s, c) on conflict (jobname) do update set schedule = s, command = c returning 1 $$;
  create schema vault;
  create table vault.decrypted_secrets (name text primary key, decrypted_secret text);
  create schema net;
  create table net.solicitudes (id serial primary key, url text, headers jsonb, body jsonb);
  create function net.http_post(url text, headers jsonb, body jsonb) returns bigint language sql as
    $$ insert into net.solicitudes (url, headers, body) values (url, headers, body) returning id $$;
`);

for (const f of fs.readdirSync(dirMigraciones).filter((f) => f.endsWith(".sql")).sort()) {
  if (f.startsWith("20261112000000")) await probarRespaldo();
  let sql = fs.readFileSync(path.join(dirMigraciones, f), "utf8");
  sql = sql
    .replace(/create extension if not exists pg_cron;/i, "-- pg_cron simulado")
    .replace(/create extension if not exists pg_net;/i, "-- pg_net simulado");
  try {
    await db.exec(sql);
    ok(true, `migración ${f}`);
  } catch (e) {
    ok(false, `migración ${f}: ${e.message}`);
    process.exit(1);
  }
}

const A = "00000000-0000-0000-0000-00000000000a";
const C1 = "00000000-0000-0000-0000-0000000000c1";
const C2 = "00000000-0000-0000-0000-0000000000c2";

await db.exec(`
  insert into auth.users (id, raw_user_meta_data) values
    ('${A}', '{"nombre":"Javier Gómez"}'), ('${C1}', '{"nombre":"Chofer Uno"}'), ('${C2}', '{"nombre":"Chofer Dos"}');
  update public.usuario set rol = 'administrador' where id = '${A}';
`);

// Ejecuta como un usuario autenticado (RLS activo).
async function como(uid, sql, params) {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${uid}', false);`);
  try {
    return await db.query(sql, params);
  } finally {
    await db.exec(`reset role;`);
  }
}
async function falla(uid, sql) {
  try {
    await como(uid, sql);
    return null;
  } catch (e) {
    return e.message;
  }
}

const usuarios = await db.query(`select nombre, rol from usuario order by nombre`);
ok(usuarios.rows.length === 3 && usuarios.rows.some((u) => u.rol === "administrador"),
  "trigger crea usuarios (rol Chofer por defecto)");

// --- Gestión comercial ---
const prod = await como(A, `insert into producto (nombre, costo_compra, precio_venta)
  values ('Notebook', 400000, 520000), ('Mouse', 5000, 9000) returning id, nombre`);
const [nb, mouse] = prod.rows;

const hoy = (await db.query(`select (now() at time zone 'America/Santiago')::date as d`)).rows[0].d;
const iso = (offset) => {
  const d = new Date(hoy);
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
};

const o1 = (await como(A, `insert into orden_compra (numero_oc, cliente, direccion_entrega, direccion_lat, direccion_lng, fecha_comprometida, responsable_id)
  values ('1234-56-SE26', 'Municipalidad X', 'Calle 1', -33.4, -70.6, $1, '${C1}') returning id`, [iso(2)])).rows[0].id;
const o2 = (await como(A, `insert into orden_compra (cliente, direccion_entrega, fecha_comprometida, responsable_id)
  values ('Hospital Y', 'Calle 2', $1, '${C1}') returning id`, [iso(0)])).rows[0].id;
const o3 = (await como(A, `insert into orden_compra (cliente, direccion_entrega, fecha_comprometida)
  values ('Liceo Z', 'Calle 3', $1) returning id`, [iso(10)])).rows[0].id;

const desp = await db.query(`select count(*)::int n from despacho where estado = 'pendiente'`);
ok(desp.rows[0].n === 3, "cada orden crea su despacho en estado Pendiente");

await como(A, `insert into detalle_orden (orden_id, producto_id, cantidad, costo_compra, precio_venta)
  values ($1, $2, 10, 400000, 510000)`, [o1, nb.id]);
await como(A, `insert into detalle_orden (orden_id, producto_id, cantidad) values ($1, $2, 20)`, [o1, mouse.id]);
let margen = (await como(A, `select margen_neto from orden_compra where id = $1`, [o1])).rows[0].margen_neto;
// 10 × 110.000 + 20 × 4.000 (precio de catálogo por defecto) = 1.180.000
ok(Number(margen) === 1180000, `margen neto calculado automáticamente (${margen})`);

await como(A, `update detalle_orden set cantidad = 5 where orden_id = $1 and producto_id = $2`, [o1, nb.id]);
await como(A, `delete from detalle_orden where orden_id = $1 and producto_id = $2`, [o1, mouse.id]);
margen = (await como(A, `select margen_neto from orden_compra where id = $1`, [o1])).rows[0].margen_neto;
ok(Number(margen) === 550000, `margen se recalcula al editar/eliminar líneas (${margen})`);

// --- Separación de datos (RBAC) ---
ok((await como(C1, `select * from orden_compra`)).rows.length === 0, "Chofer NO lee orden_compra (margen)");
ok((await como(C1, `select * from producto`)).rows.length === 0, "Chofer NO lee producto (costos)");
ok((await como(C1, `select * from detalle_orden`)).rows.length === 0, "Chofer NO lee detalle_orden (precios)");
ok((await como(C1, `select * from usuario`)).rows.length === 1, "Chofer solo ve su propio usuario");
ok((await falla(C1, `insert into producto (nombre, costo_compra, precio_venta) values ('x',1,1)`)) !== null,
  "Chofer NO puede escribir en producto");

const vista = await como(C1, `select * from v_despacho_chofer order by fecha_comprometida`);
ok(vista.rows.length === 2, "Chofer ve sus 2 despachos en v_despacho_chofer");
const columnas = Object.keys(vista.rows[0]);
ok(!columnas.some((c) => /costo|precio|margen|ahorro/.test(c)), `vista sin columnas financieras: ${columnas.join(", ")}`);
ok(!JSON.stringify(vista.rows).match(/costo|precio|margen/), "productos embebidos sin precios");
ok((await como(C2, `select * from v_despacho_chofer`)).rows.length === 0, "otro Chofer no ve despachos ajenos");

// --- Máquina de estados + RPC ---
const d1 = (await db.query(`select id from despacho where orden_id = $1`, [o1])).rows[0].id;
const d2 = (await db.query(`select id from despacho where orden_id = $1`, [o2])).rows[0].id;
const d3 = (await db.query(`select id from despacho where orden_id = $1`, [o3])).rows[0].id;

ok((await falla(C1, `select cambiar_estado_despacho('${d1}', 'entregado')`))?.includes("Transición"),
  "no permite saltar de Pendiente a Entregado");
await como(C1, `select cambiar_estado_despacho('${d1}', 'en_ruta')`);
const rep = await como(C1, `select cambiar_estado_despacho('${d1}', 'en_ruta') r`);
ok(rep.rows[0].r === "en_ruta", "repetir el mismo cambio es idempotente (cola offline)");

const horaOffline = new Date(Date.now() - 45 * 60 * 1000).toISOString();
await como(C1, `select cambiar_estado_despacho('${d1}', 'entregado', $1)`, [horaOffline]);
const ent = (await db.query(`select d.estado, d.fecha_hora_entrega, d.confirmado_en_app, o.fecha_hora_entrega as fo
  from despacho d join orden_compra o on o.id = d.orden_id where d.id = $1`, [d1])).rows[0];
ok(ent.estado === "entregado" && ent.confirmado_en_app === true, "entrega confirmada por el Chofer en la app");
ok(Math.abs(new Date(ent.fecha_hora_entrega) - new Date(horaOffline)) < 1000,
  "se registra la hora REAL del cambio offline, no la de sincronización");
ok(+new Date(ent.fo) === +new Date(ent.fecha_hora_entrega), "fecha_hora_entrega se copia a la orden");

const retro = await como(C1, `select cambiar_estado_despacho('${d1}', 'en_ruta') r`);
ok(retro.rows[0].r === "entregado", "un cambio atrasado no retrocede el estado");

ok((await falla(C2, `select cambiar_estado_despacho('${d2}', 'en_ruta')`))?.includes("sin permiso"),
  "un Chofer no puede cambiar despachos ajenos");
ok((await falla(C1, `update despacho set estado = 'en_ruta' where id = '${d2}'`)) !== null ||
   (await db.query(`select estado from despacho where id = $1`, [d2])).rows[0].estado === "pendiente",
  "Chofer no puede actualizar la tabla despacho directamente");

// --- No entregado con justificación obligatoria (RF-14/RF-16) ---
const oNE = (await como(A, `insert into orden_compra (cliente, direccion_entrega, fecha_comprometida, responsable_id)
  values ('Cliente NE', 'Calle NE', $1, '${C1}') returning id`, [iso(5)])).rows[0].id;
const dNE = (await db.query(`select id from despacho where orden_id = $1`, [oNE])).rows[0].id;
await como(C1, `select cambiar_estado_despacho('${dNE}', 'en_ruta')`);
ok((await falla(C1, `select cambiar_estado_despacho('${dNE}', 'no_entregado')`))?.includes("motivo"),
  "No entregado exige motivo");
ok((await falla(C1, `select cambiar_estado_despacho('${dNE}', 'no_entregado', now(), '   ')`))?.includes("motivo"),
  "No entregado rechaza un motivo en blanco");
await como(C1, `select cambiar_estado_despacho('${dNE}', 'no_entregado', now(), 'Cliente ausente')`);
const ne = (await db.query(`select estado, motivo_no_entrega, confirmado_en_app, fecha_hora_entrega
  from despacho where id = $1`, [dNE])).rows[0];
ok(ne.estado === "no_entregado" && ne.motivo_no_entrega === "Cliente ausente"
   && ne.confirmado_en_app === false && ne.fecha_hora_entrega === null,
  "No entregado guarda el motivo y no marca entrega");
ok((await como(C1, `select motivo_no_entrega from v_despacho_chofer where despacho_id = $1`, [dNE]))
     .rows[0].motivo_no_entrega === "Cliente ausente",
  "el Chofer ve su justificación en la vista v_despacho_chofer");
await como(C1, `select cambiar_estado_despacho('${dNE}', 'en_ruta')`);
ok((await db.query(`select motivo_no_entrega from despacho where id = $1`, [dNE])).rows[0].motivo_no_entrega === null,
  "al reintentar (volver a En Ruta) se limpia el motivo");
await como(C1, `select cambiar_estado_despacho('${dNE}', 'entregado')`);
ok((await db.query(`select estado from despacho where id = $1`, [dNE])).rows[0].estado === "entregado",
  "un despacho no entregado puede entregarse en un reintento");
await como(A, `update despacho set motivo_no_entrega = 'x' where id = '${dNE}'`);
ok((await db.query(`select motivo_no_entrega from despacho where id = $1`, [dNE])).rows[0].motivo_no_entrega === null,
  "el motivo solo persiste en estado No entregado (el trigger lo limpia)");
await como(A, `delete from orden_compra where id = '${oNE}'`);

// --- Bultos (Administrador) ---
await como(A, `update despacho set cantidad_bultos = 4 where id = $1`, [d2]);
ok((await como(C1, `select cantidad_bultos from v_despacho_chofer where despacho_id = $1`, [d2])).rows[0].cantidad_bultos === 4,
  "Chofer ve los bultos registrados por el Administrador");

// --- Motor de alertas ---
let n = (await db.query(`select generar_alertas() n`)).rows[0].n;
const alertas = (await db.query(`select o.cliente, a.tipo from alerta a join orden_compra o on o.id = a.orden_id order by 1`)).rows;
ok(alertas.length === 1 && alertas[0].cliente === "Hospital Y" && alertas[0].tipo === "dia_cero",
  `Día Cero para la orden que vence hoy; la entregada no genera alerta (${JSON.stringify(alertas)})`);
await como(A, `insert into orden_compra (cliente, direccion_entrega, fecha_comprometida) values ('Escuela W', 'Calle 4', $1)`, [iso(3)]);
n = (await db.query(`select generar_alertas() n`)).rows[0].n;
ok(n === 1, "alerta preventiva a 3 días del plazo");
n = (await db.query(`select generar_alertas() n`)).rows[0].n;
ok(n === 0, "el motor es idempotente (no duplica alertas)");
ok((await falla(C1, `select generar_alertas()`)) !== null, "un usuario no puede ejecutar el motor de alertas");
ok((await como(C1, `select * from v_alerta_chofer`)).rows.length === 1, "Chofer ve las alertas de sus órdenes");
ok((await db.query(`select count(*)::int n from cron.job where jobname = 'gygtrack-generar-alertas'`)).rows[0].n === 1,
  "CRON programado");

// --- Enrutamiento ---
const r = (await como(A, `insert into ruta (fecha, chofer_id, origen_direccion, origen_lat, origen_lng, distancia_km, duracion_min, costo_ruta_sin_optimizar, costo_ruta_optimizada)
  values ($1, '${C1}', 'Bodega', -33.45, -70.66, 42.5, 75, 9800, 7200) returning id, ahorro`, [iso(0)])).rows[0];
ok(Number(r.ahorro) === 2600, "ahorro = costo sin optimizar − costo optimizado");
await como(A, `insert into ruta_parada (ruta_id, despacho_id, orden) values ($1, $2, 0), ($1, $3, 1)`, [r.id, d2, d3]);
const rc = await como(C1, `select * from v_ruta_chofer`);
// usa_peajes (sí/no) es operativo: avisa que la ruta pasa por autopistas.
// Montos de peaje, costos, ahorro y el detalle de optimización NO se exponen.
const colsRuta = Object.keys(rc.rows[0]).filter((c) => c !== "usa_peajes");
ok(rc.rows.length === 1 && !colsRuta.some((c) => /costo|ahorro|peaje|detalle|combustible/.test(c)),
  `Chofer ve su ruta sin costos: ${Object.keys(rc.rows[0]).join(", ")}`);
await como(A, `update ruta set detalle_optimizacion = '{"conTag":{"peajesClp":1830}}' where id = $1`, [r.id]);
ok(!JSON.stringify((await como(C1, `select * from v_ruta_chofer`)).rows).includes("1830"),
  "el detalle de optimización (montos de TAG) no llega al Chofer");
ok((await como(C1, `select * from ruta`)).rows.length === 0, "Chofer NO lee la tabla ruta (costos)");
ok((await como(C1, `select * from v_despacho_chofer where despacho_id = $1`, [d3])).rows.length === 1,
  "Chofer ve despachos de su ruta aunque no sea responsable");
ok((await como(C2, `select * from v_ruta_chofer`)).rows.length === 0, "otro Chofer no ve la ruta");

// --- Cambiar la alternativa de la ruta (menos tiempo / plata / km) ---
const nuevaOrden = async (cliente) => {
  const id = (await como(A, `insert into orden_compra (cliente, direccion_entrega, fecha_comprometida) values ($1, 'Calle', $2) returning id`,
    [cliente, iso(5)])).rows[0].id;
  return (await db.query(`select id from despacho where orden_id = $1`, [id])).rows[0].id;
};
const [da, db_] = [await nuevaOrden("Alt A"), await nuevaOrden("Alt B")];
const alt = (ids, km, min, costo, pol) => ({ polilinea: pol, despachoIds: ids, usaPeajes: costo > 20000, distanciaKm: km,
  duracionMin: min, costoClp: costo, peajes: { totalClp: costo > 20000 ? 5000 : 0, cruces: [] } });
const detalleAlt = { elegida: "sin_tag", recomendada: "sin_tag", motivo: "recomendada", alternativas: {
  sin_optimizar: alt([da, db_], 65.9, 97, 18580, "plazo"), con_tag: alt([db_, da], 68.6, 88, 21479, "contag"),
  sin_tag: alt([da, db_], 63.1, 106, 14946, "sintag") } };
const ra = (await como(A, `insert into ruta (fecha, chofer_id, origen_direccion, origen_lat, origen_lng, costo_ruta_sin_optimizar, costo_ruta_optimizada, detalle_optimizacion)
  values ($1, '${C1}', 'Bodega', -33.45, -70.66, 18580, 14946, $2) returning id`, [iso(0), JSON.stringify(detalleAlt)])).rows[0].id;
await como(A, `insert into ruta_parada (ruta_id, despacho_id, orden) values ($1, $2, 0), ($1, $3, 1)`, [ra, da, db_]);
await como(A, `select elegir_alternativa_ruta($1, 'con_tag', 'menos_tiempo', 'por tiempo')`, [ra]);
const rAlt = (await como(A, `select polilinea, duracion_min, usa_peajes, ahorro, detalle_optimizacion d from ruta where id = $1`, [ra])).rows[0];
const ordenAlt = (await como(A, `select despacho_id from ruta_parada where ruta_id = $1 order by orden`, [ra])).rows.map((x) => x.despacho_id);
ok(rAlt.polilinea === "contag" && rAlt.duracion_min === 88 && rAlt.usa_peajes && Number(rAlt.ahorro) === 18580 - 21479 &&
  rAlt.d.elegida === "con_tag" && rAlt.d.criterio === "menos_tiempo" && rAlt.d.recomendada === "sin_tag" &&
  ordenAlt[0] === db_ && ordenAlt[1] === da, "cambiar a 'menos tiempo' aplica trazado, orden, TAG y costo");
ok((await falla(C1, `select elegir_alternativa_ruta('${ra}', 'sin_tag', 'equilibrada')`)) !== null,
  "el Chofer no puede cambiar la alternativa");
await db.query(`update despacho set estado = 'en_ruta' where id = $1`, [da]);
ok(((await falla(A, `select elegir_alternativa_ruta('${ra}', 'sin_tag', 'equilibrada')`)) ?? "").includes("ya comenzó"),
  "no se cambia la alternativa si la ruta ya comenzó");
await como(A, `delete from ruta where id = $1`, [ra]);
// Limpieza: se borran las órdenes de prueba (el despacho no puede volver a "pendiente").
await como(A, `delete from orden_compra where id in (select orden_id from despacho where id in ($1, $2))`, [da, db_]);

// --- KPI ---
const kpi = (await como(A, `select * from v_kpi`)).rows[0];
console.log("  KPI:", JSON.stringify(kpi));
ok(Number(kpi.kpi07_confirmadas_en_app) === 100 && Number(kpi.kpi08_ahorro_mes) === 2600, "v_kpi calcula indicadores");
const kpiChofer = (await como(C1, `select * from v_kpi`)).rows;
ok(kpiChofer.length === 0, `Chofer no obtiene KPI (${JSON.stringify(kpiChofer)})`);

// --- Push (RF-19): registro de dispositivos y disparo del envío ---
await como(C1, `select registrar_dispositivo_push('token-c1', 'android')`);
await como(A, `select registrar_dispositivo_push('token-a', 'ios')`);
ok((await como(C1, `select * from dispositivo_push`)).rows.length === 1,
  "cada usuario ve solo sus propios dispositivos");
await como(C2, `select registrar_dispositivo_push('token-c1', 'android')`);
ok((await db.query(`select usuario_id from dispositivo_push where token = 'token-c1'`)).rows[0].usuario_id === C2,
  "si el teléfono cambia de usuario, el token se reasigna");
ok((await falla(C1, `insert into dispositivo_push (token, usuario_id, plataforma) values ('x', '${C2}', 'android')`)) !== null,
  "no se pueden registrar tokens a nombre de otro usuario");
ok((await falla(C1, `select disparar_envio_push()`)) !== null, "un usuario no puede disparar el envío push");
ok((await db.query(`select disparar_envio_push() r`)).rows[0].r === false,
  "sin secretos en Vault no se llama a la Edge Function");
await db.exec(`insert into vault.decrypted_secrets values
  ('gygtrack_url_proyecto', 'https://abc.supabase.co/'), ('gygtrack_service_role_key', 'clave-servicio')`);
ok((await db.query(`select disparar_envio_push() r`)).rows[0].r === true, "con secretos se dispara el envío");
const sol = (await db.query(`select url, headers from net.solicitudes`)).rows[0];
ok(sol.url === "https://abc.supabase.co/functions/v1/enviar-alertas" &&
   sol.headers.Authorization === "Bearer clave-servicio", `llama a enviar-alertas con la service key (${sol.url})`);
const cmd = (await db.query(`select command from cron.job where jobname = 'gygtrack-generar-alertas'`)).rows[0].command;
ok(cmd.includes("generar_alertas()") && cmd.includes("disparar_envio_push()"),
  "el CRON genera las alertas y luego dispara el push");

// --- Importación de cotizaciones ---
await como(A, `update orden_compra set numero_cotizacion = '5609-132-COT26', fecha_cotizacion = '2026-08-12' where id = $1`, [o2]);
ok((await falla(A, `insert into orden_compra (cliente, direccion_entrega, fecha_comprometida, numero_cotizacion) values ('X', 'Y', current_date, '5609-132-COT26')`))?.includes("duplicate") ?? false,
  "no se puede importar dos veces la misma cotización");
ok((await como(C1, `select * from v_despacho_chofer where despacho_id = $1`, [d2])).rows.length === 1, "la vista del Chofer sigue funcionando con los campos nuevos");
ok((await db.query(`select count(*)::int n from storage.buckets where id = 'productos'`)).rows[0].n === 1, "bucket privado de fotos de productos");

// --- Pórticos TAG ---
const nPort = (await db.query(`select count(*)::int n, count(distinct concesion)::int c from portico`)).rows[0];
ok(nPort.n === 161 && nPort.c === 13, `pórticos TAG cargados (${nPort.n} de ${nPort.c} concesiones: 114 urbanos + 47 interurbanos)`);
const ang = (await db.query(`select tarifas, rumbo from portico where codigo = 'Angostura'`)).rows;
ok(ang.length === 2 && ang[0].tarifas["1"].tbfp === 3800, "Angostura: un punto por sentido, $3.800 categoría 1");
const chac = (await db.query(`select rumbo from portico where codigo = 'Chacabuco'`)).rows;
ok(chac.length === 1 && chac[0].rumbo === null, "Chacabuco cobra en ambos sentidos (rumbo null)");
const pa13 = (await db.query(`select tarifas from portico where codigo = 'PA13'`)).rows[0];
ok(Number(pa13.tarifas["1"].ts) === 545.6, "tarifa TS de PA13 (MOP 2026) cargada");
ok((await como(C1, `select * from portico`)).rows.length === 0, "el Chofer no lee la tabla de pórticos (tarifas)");

// --- Eliminación en cascada ---
await como(A, `delete from orden_compra where id = $1`, [o1]);
ok((await db.query(`select count(*)::int n from despacho where orden_id = $1`, [o1])).rows[0].n === 0,
  "eliminar una orden borra su despacho (CRUD, RF-09)");

console.log(fallos === 0 ? "\nTODO OK" : `\n${fallos} FALLO(S)`);
process.exit(fallos ? 1 : 0);
