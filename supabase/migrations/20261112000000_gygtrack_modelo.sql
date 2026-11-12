-- ============================================================================
-- GyGTrack — Modelo de datos alineado a la especificación (traspaso §5).
--
-- Reemplaza el modelo del prototipo (cotizaciones / rutas / puntos_ruta) por
-- las entidades de la especificación: Usuario, Producto, Orden_compra,
-- Detalle_orden, Despacho, Alerta y Ruta.
--
-- ATENCIÓN: esta migración BORRA las tablas del prototipo y sus datos.
-- Los campos que no figuran en el traspaso están marcados con
-- "-- [IMPL]" y se justifican en docs/DECISIONES_IMPLEMENTACION.md; deben
-- contrastarse con el ER de la Parte 2.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Limpieza del prototipo
-- ----------------------------------------------------------------------------
drop table if exists public.puntos_ruta cascade;
drop table if exists public.rutas cascade;
drop table if exists public.cotizaciones cascade;

-- El bucket "cotizaciones" (PDF/fotos) no forma parte de la especificación.
-- Se quitan sus políticas; el bucket se puede borrar desde el panel.
drop policy if exists "cotizaciones storage: admin manage" on storage.objects;
drop policy if exists "cotizaciones storage: authenticated read" on storage.objects;

-- ----------------------------------------------------------------------------
-- 1. Usuario / Rol  (Módulo Administración y Seguridad — RF-01, RF-02)
-- ----------------------------------------------------------------------------
drop policy if exists "profiles: self select" on public.profiles;
drop policy if exists "profiles: admin select all" on public.profiles;
drop policy if exists "profiles: self update" on public.profiles;
drop policy if exists "profiles: admin update all" on public.profiles;

alter table public.profiles rename to usuario;
alter table public.usuario rename column full_name to nombre;
alter table public.usuario rename column role to rol;
alter table public.usuario drop column if exists phone;
alter table public.usuario drop constraint if exists profiles_role_check;
alter table public.usuario alter column rol drop default;
update public.usuario set rol = 'administrador' where rol = 'admin';
alter table public.usuario
  add constraint usuario_rol_check check (rol in ('administrador', 'chofer')),
  alter column rol set default 'chofer';

drop function if exists public.is_admin() cascade;

create or replace function public.es_administrador()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.usuario where id = auth.uid() and rol = 'administrador'
  );
$$;

-- Toda cuenta nueva (creada por el administrador desde el panel de Supabase)
-- nace como Chofer. El ascenso a Administrador es manual.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.usuario (id, nombre, rol)
  values (new.id, new.raw_user_meta_data ->> 'nombre', 'chofer');
  return new;
end;
$$;

alter table public.usuario enable row level security;

create policy "usuario: ver el propio"
  on public.usuario for select
  using (id = auth.uid());

create policy "usuario: administrador todo"
  on public.usuario for all
  using (public.es_administrador())
  with check (public.es_administrador());

-- ----------------------------------------------------------------------------
-- 2. Producto  (Gestión Comercial — RF-11)
-- ----------------------------------------------------------------------------
create table public.producto (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  costo_compra numeric(14, 2) not null check (costo_compra >= 0),
  precio_venta numeric(14, 2) not null check (precio_venta >= 0),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 3. Orden_compra  (Gestión Comercial — RF-05, RF-07, RF-09, RF-10)
-- ----------------------------------------------------------------------------
create table public.orden_compra (
  id uuid primary key default gen_random_uuid(),
  numero_oc text,                                  -- [IMPL] N° OC Mercado Público
  cliente text not null,
  direccion_entrega text not null,                 -- [IMPL] requerido por RF-21
  direccion_lat double precision,                  -- [IMPL] requerido por RF-22
  direccion_lng double precision,                  -- [IMPL] requerido por RF-22
  fecha_comprometida date not null,
  fecha_hora_entrega timestamptz,
  margen_neto numeric(14, 2) not null default 0,   -- calculado (RF-07)
  responsable_id uuid references public.usuario (id) on delete set null,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 4. Detalle_orden  (Gestión Comercial — RF-05, RF-06)
-- Guarda el costo y el precio adjudicado de cada línea: el precio adjudicado
-- depende de cada licitación y no siempre coincide con el del catálogo.
-- ----------------------------------------------------------------------------
create table public.detalle_orden (
  id uuid primary key default gen_random_uuid(),
  orden_id uuid not null references public.orden_compra (id) on delete cascade,
  producto_id uuid not null references public.producto (id) on delete restrict,
  cantidad integer not null check (cantidad > 0),
  costo_compra numeric(14, 2) not null check (costo_compra >= 0),
  precio_venta numeric(14, 2) not null check (precio_venta >= 0),
  created_at timestamptz not null default now()
);

create index detalle_orden_orden_idx on public.detalle_orden (orden_id);

-- Si no se informa costo/precio en la línea, se toma el del catálogo.
create function public.detalle_orden_valores_por_defecto()
returns trigger
language plpgsql
as $$
begin
  if new.costo_compra is null or new.precio_venta is null then
    select coalesce(new.costo_compra, p.costo_compra),
           coalesce(new.precio_venta, p.precio_venta)
      into new.costo_compra, new.precio_venta
      from public.producto p
     where p.id = new.producto_id;
  end if;
  return new;
end;
$$;

create trigger detalle_orden_defaults
  before insert or update on public.detalle_orden
  for each row execute function public.detalle_orden_valores_por_defecto();

-- Motor de rentabilidad (RF-07):
--   margen_neto(orden) = Σ ((precio_venta − costo_compra) × cantidad)
create function public.recalcular_margen_neto(p_orden_id uuid)
returns void
language sql
security definer set search_path = public
as $$
  update public.orden_compra o
     set margen_neto = coalesce((
           select sum((d.precio_venta - d.costo_compra) * d.cantidad)
             from public.detalle_orden d
            where d.orden_id = p_orden_id
         ), 0)
   where o.id = p_orden_id;
$$;

create function public.detalle_orden_recalcular_margen()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.recalcular_margen_neto(old.orden_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public.recalcular_margen_neto(new.orden_id);
  end if;
  return null;
end;
$$;

create trigger detalle_orden_margen
  after insert or update or delete on public.detalle_orden
  for each row execute function public.detalle_orden_recalcular_margen();

-- ----------------------------------------------------------------------------
-- 5. Despacho  (Logístico — RF-12, RF-14, RF-15, RF-16)
-- Un despacho por orden; se crea automáticamente en estado Pendiente.
-- ----------------------------------------------------------------------------
create table public.despacho (
  id uuid primary key default gen_random_uuid(),
  orden_id uuid not null unique references public.orden_compra (id) on delete cascade,
  cantidad_bultos integer check (cantidad_bultos is null or cantidad_bultos > 0),
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'en_ruta', 'entregado')),
  fecha_hora_entrega timestamptz,
  confirmado_en_app boolean not null default false,  -- [IMPL] medición KPI-07
  actualizado_en timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create function public.orden_compra_crear_despacho()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.despacho (orden_id) values (new.id);
  return new;
end;
$$;

create trigger orden_compra_despacho
  after insert on public.orden_compra
  for each row execute function public.orden_compra_crear_despacho();

-- Máquina de estados (RF-14): solo se avanza un paso a la vez,
-- Pendiente → En Ruta → Entregado. Aplica a cualquier UPDATE.
create function public.rango_estado_despacho(p_estado text)
returns integer
language sql
immutable
as $$
  select case p_estado
           when 'pendiente' then 0
           when 'en_ruta' then 1
           when 'entregado' then 2
         end;
$$;

create function public.despacho_validar_transicion()
returns trigger
language plpgsql
as $$
begin
  if new.estado is distinct from old.estado then
    if public.rango_estado_despacho(new.estado)
       <> public.rango_estado_despacho(old.estado) + 1 then
      raise exception 'Transición de estado no permitida: % → %', old.estado, new.estado
        using errcode = 'P0001';
    end if;
  end if;
  new.actualizado_en := now();
  return new;
end;
$$;

create trigger despacho_transicion
  before update on public.despacho
  for each row execute function public.despacho_validar_transicion();

-- Cambio de estado usado por la app (también desde la cola offline, RF-15).
--  * p_ocurrido_en: hora real en que el chofer hizo el cambio, aunque se
--    sincronice después (RF-16). No se aceptan horas futuras.
--  * Idempotente: si el despacho ya está en ese estado o más adelante, no
--    hace nada (permite reintentar la cola sin duplicar efectos).
create function public.cambiar_estado_despacho(
  p_despacho_id uuid,
  p_estado text,
  p_ocurrido_en timestamptz default now()
)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_actual text;
  v_rol text;
  v_momento timestamptz := least(coalesce(p_ocurrido_en, now()), now());
begin
  select rol into v_rol from public.usuario where id = auth.uid();
  if v_rol is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  select d.estado into v_actual
    from public.despacho d
    join public.orden_compra o on o.id = d.orden_id
   where d.id = p_despacho_id
     and (
       v_rol = 'administrador'
       or o.responsable_id = auth.uid()
       or exists (
         select 1 from public.ruta_parada rp
         join public.ruta r on r.id = rp.ruta_id
         where rp.despacho_id = d.id and r.chofer_id = auth.uid()
       )
     )
   for update of d;

  if v_actual is null then
    raise exception 'Despacho no encontrado o sin permiso' using errcode = '42501';
  end if;

  if public.rango_estado_despacho(p_estado) is null then
    raise exception 'Estado inválido: %', p_estado using errcode = '22023';
  end if;

  if public.rango_estado_despacho(p_estado) <= public.rango_estado_despacho(v_actual) then
    return v_actual;  -- ya aplicado (idempotencia)
  end if;

  update public.despacho
     set estado = p_estado,
         fecha_hora_entrega = case when p_estado = 'entregado' then v_momento else fecha_hora_entrega end,
         confirmado_en_app = case when p_estado = 'entregado' then (v_rol = 'chofer') else confirmado_en_app end
   where id = p_despacho_id;

  if p_estado = 'entregado' then
    update public.orden_compra o
       set fecha_hora_entrega = v_momento
      from public.despacho d
     where d.id = p_despacho_id and o.id = d.orden_id;
  end if;

  return p_estado;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. Alerta  (Notificaciones — RF-17, RF-18, RF-19, RF-20)
-- ----------------------------------------------------------------------------
create table public.alerta (
  id uuid primary key default gen_random_uuid(),
  orden_id uuid not null references public.orden_compra (id) on delete cascade,
  tipo text not null check (tipo in ('preventiva', 'dia_cero')),
  fecha_emision timestamptz not null default now(),
  push_enviada boolean not null default false,       -- [IMPL] seguimiento RF-19
  unique (orden_id, tipo)
);

-- Motor de alertas. Se ejecuta cada hora vía pg_cron y es idempotente
-- (una alerta de cada tipo por orden).
--  * Preventiva: faltan 3 días para fecha_comprometida. Si la orden se
--    registró con menos de 3 días de plazo (o el CRON no corrió), se emite
--    en cuanto se detecta, para no dejar órdenes sin alerta (KPI-06).
--  * Día Cero: fecha_comprometida = hoy.
-- Las órdenes ya entregadas no generan alertas. "Hoy" = hora de Chile.
create function public.generar_alertas()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_hoy date := (now() at time zone 'America/Santiago')::date;
  v_total integer := 0;
  v_n integer;
begin
  insert into public.alerta (orden_id, tipo)
  select o.id, 'preventiva'
    from public.orden_compra o
    join public.despacho d on d.orden_id = o.id
   where d.estado <> 'entregado'
     and o.fecha_comprometida - v_hoy between 1 and 3
  on conflict (orden_id, tipo) do nothing;
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  insert into public.alerta (orden_id, tipo)
  select o.id, 'dia_cero'
    from public.orden_compra o
    join public.despacho d on d.orden_id = o.id
   where d.estado <> 'entregado'
     and o.fecha_comprometida = v_hoy
  on conflict (orden_id, tipo) do nothing;
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  return v_total;
end;
$$;

revoke execute on function public.generar_alertas() from public, anon, authenticated;

create extension if not exists pg_cron;

select cron.schedule(
  'gygtrack-generar-alertas',
  '0 * * * *',
  $$select public.generar_alertas();$$
);

-- ----------------------------------------------------------------------------
-- 7. Ruta  (Enrutamiento — RF-21 a RF-24)
-- ----------------------------------------------------------------------------
create table public.ruta (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,                                -- [IMPL] jornada (RF-21)
  chofer_id uuid references public.usuario (id) on delete set null,
  origen_direccion text not null,                     -- [IMPL] bodega de salida
  origen_lat double precision not null,
  origen_lng double precision not null,
  distancia_km numeric(10, 1),                        -- [IMPL]
  duracion_min integer,                               -- [IMPL]
  polilinea text,                                     -- [IMPL] trazado para RF-23
  usa_peajes boolean not null default false,          -- [IMPL] regla $500/10 min
  costo_ruta_sin_optimizar numeric(14, 0),
  costo_ruta_optimizada numeric(14, 0),
  ahorro numeric(14, 0)
    generated always as (costo_ruta_sin_optimizar - costo_ruta_optimizada) stored,
  created_at timestamptz not null default now()
);

-- [IMPL] Paradas de la ruta en el orden optimizado (relación Ruta–Despacho).
create table public.ruta_parada (
  ruta_id uuid not null references public.ruta (id) on delete cascade,
  despacho_id uuid not null references public.despacho (id) on delete cascade,
  orden integer not null,
  primary key (ruta_id, despacho_id),
  unique (ruta_id, orden)
);

-- ----------------------------------------------------------------------------
-- 8. RLS de tablas base: SOLO el Administrador accede a ellas.
-- El Chofer lee únicamente las vistas de la sección 9 (sin datos financieros).
-- ----------------------------------------------------------------------------
alter table public.producto enable row level security;
alter table public.orden_compra enable row level security;
alter table public.detalle_orden enable row level security;
alter table public.despacho enable row level security;
alter table public.alerta enable row level security;
alter table public.ruta enable row level security;
alter table public.ruta_parada enable row level security;

create policy "producto: administrador" on public.producto
  for all using (public.es_administrador()) with check (public.es_administrador());
create policy "orden_compra: administrador" on public.orden_compra
  for all using (public.es_administrador()) with check (public.es_administrador());
create policy "detalle_orden: administrador" on public.detalle_orden
  for all using (public.es_administrador()) with check (public.es_administrador());
create policy "despacho: administrador" on public.despacho
  for all using (public.es_administrador()) with check (public.es_administrador());
create policy "alerta: administrador" on public.alerta
  for all using (public.es_administrador()) with check (public.es_administrador());
create policy "ruta: administrador" on public.ruta
  for all using (public.es_administrador()) with check (public.es_administrador());
create policy "ruta_parada: administrador" on public.ruta_parada
  for all using (public.es_administrador()) with check (public.es_administrador());

-- ----------------------------------------------------------------------------
-- 9. Vistas del Chofer (RF-03 / RF-13): separación de datos a nivel de BD.
-- Ninguna expone costo_compra, precio_venta, margen_neto, costos ni ahorro.
-- ----------------------------------------------------------------------------
create view public.v_despacho_chofer
with (security_barrier = true) as
select d.id                 as despacho_id,
       d.estado,
       d.cantidad_bultos,
       d.fecha_hora_entrega,
       d.actualizado_en,
       o.id                 as orden_id,
       o.numero_oc,
       o.cliente,
       o.direccion_entrega,
       o.direccion_lat,
       o.direccion_lng,
       o.fecha_comprometida,
       coalesce((
         select jsonb_agg(jsonb_build_object('producto', p.nombre, 'cantidad', det.cantidad)
                          order by p.nombre)
           from public.detalle_orden det
           join public.producto p on p.id = det.producto_id
          where det.orden_id = o.id
       ), '[]'::jsonb)      as productos
  from public.despacho d
  join public.orden_compra o on o.id = d.orden_id
 where o.responsable_id = auth.uid()
    or exists (
      select 1 from public.ruta_parada rp
      join public.ruta r on r.id = rp.ruta_id
      where rp.despacho_id = d.id and r.chofer_id = auth.uid()
    );

create view public.v_ruta_chofer
with (security_barrier = true) as
select r.id,
       r.fecha,
       r.origen_direccion,
       r.origen_lat,
       r.origen_lng,
       r.distancia_km,
       r.duracion_min,
       r.polilinea,
       coalesce((
         select jsonb_agg(jsonb_build_object('despacho_id', rp.despacho_id, 'orden', rp.orden)
                          order by rp.orden)
           from public.ruta_parada rp
          where rp.ruta_id = r.id
       ), '[]'::jsonb) as paradas
  from public.ruta r
 where r.chofer_id = auth.uid();

create view public.v_alerta_chofer
with (security_barrier = true) as
select a.id, a.orden_id, a.tipo, a.fecha_emision, o.cliente, o.numero_oc, o.fecha_comprometida
  from public.alerta a
  join public.orden_compra o on o.id = a.orden_id
 where o.responsable_id = auth.uid();

revoke all on public.v_despacho_chofer, public.v_ruta_chofer, public.v_alerta_chofer from anon;
grant select on public.v_despacho_chofer, public.v_ruta_chofer, public.v_alerta_chofer to authenticated;

revoke execute on function public.cambiar_estado_despacho(uuid, text, timestamptz) from public, anon;
grant execute on function public.cambiar_estado_despacho(uuid, text, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 10. Indicadores (KPI) para el Administrador — fórmulas del informe.
-- KPI-03 (tiempo de obtención del margen) se mide en la app, no aquí.
-- ----------------------------------------------------------------------------
create view public.v_kpi
with (security_barrier = true) as
select k.* from (
with base as (
  select o.*, d.estado, d.cantidad_bultos, d.confirmado_en_app,
         d.fecha_hora_entrega as entrega_despacho
    from public.orden_compra o
    join public.despacho d on d.orden_id = o.id
),
hoy as (select (now() at time zone 'America/Santiago')::date as d)
select
  round(100.0 * count(*) filter (where estado = 'entregado'
          and (entrega_despacho at time zone 'America/Santiago')::date <= fecha_comprometida)
        / nullif(count(*) filter (where estado = 'entregado'), 0), 1)          as kpi01_entrega_en_plazo,
  round(100.0 * count(*) filter (where exists (select 1 from public.detalle_orden x where x.orden_id = base.id))
        / nullif(count(*), 0), 1)                                              as kpi02_cobertura_margen,
  round(100.0 * count(*) filter (where responsable_id is not null)
        / nullif(count(*), 0), 1)                                              as kpi04_con_responsable,
  round(100.0 * count(*) filter (where cantidad_bultos is not null)
        / nullif(count(*), 0), 1)                                              as kpi05_con_bultos,
  round(100.0 * count(*) filter (where fecha_comprometida <= (select d from hoy) + 3
          and exists (select 1 from public.alerta a where a.orden_id = base.id and a.tipo = 'preventiva'))
        / nullif(count(*) filter (where fecha_comprometida <= (select d from hoy) + 3
          and fecha_comprometida - (created_at at time zone 'America/Santiago')::date >= 1), 0), 1)
                                                                               as kpi06_alertas_preventivas,
  round(100.0 * count(*) filter (where estado = 'entregado' and confirmado_en_app)
        / nullif(count(*) filter (where estado = 'entregado'), 0), 1)          as kpi07_confirmadas_en_app,
  (select coalesce(sum(r.ahorro), 0) from public.ruta r
    where date_trunc('month', r.fecha) = date_trunc('month', (select d from hoy)))
                                                                               as kpi08_ahorro_mes
  from base
) k
-- El filtro va sobre el resultado completo: el Chofer no obtiene ninguna fila.
where public.es_administrador();

revoke all on public.v_kpi from anon;
grant select on public.v_kpi to authenticated;
