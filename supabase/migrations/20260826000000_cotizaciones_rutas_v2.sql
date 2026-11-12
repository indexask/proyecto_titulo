-- Fase 2: cotizaciones con datos extraídos del PDF, rutas multi-cotización
-- con punto de partida propio y optimización de recorrido.

drop policy "cotizaciones: chofer select asignadas" on public.cotizaciones;

alter table public.rutas drop column cotizacion_id;

alter table public.cotizaciones
  add column numero_cotizacion text,
  add column fecha_cotizacion date,
  add column direccion_entrega text,
  add column direccion_lat double precision,
  add column direccion_lng double precision,
  add column descripcion text,
  add column unidades numeric,
  add column precio_unidad numeric,
  add column foto_url text;
-- 'cliente' se reutiliza como "Solicitado por"; 'monto' se reutiliza como "Total".

alter table public.puntos_ruta
  add column cotizacion_id uuid references public.cotizaciones (id);

alter table public.rutas
  add column fecha_entrega date not null default current_date,
  add column origen_direccion text,
  add column origen_lat double precision,
  add column origen_lng double precision,
  add column distancia_km numeric,
  add column duracion_min numeric;

create policy "cotizaciones: chofer select asignadas"
  on public.cotizaciones for select
  using (
    exists (
      select 1 from public.puntos_ruta pr
      join public.rutas r on r.id = pr.ruta_id
      where pr.cotizacion_id = cotizaciones.id and r.chofer_id = auth.uid()
    )
  );
