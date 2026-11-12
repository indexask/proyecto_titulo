-- ============================================================================
-- GyGTrack — Importación automática de cotizaciones (extensión de RF-05/RF-06).
-- El Administrador sube el PDF de la cotización de GyG y el sistema completa
-- la orden: fecha, cliente ("Solicitado por"), dirección, ID de cotización,
-- productos (descripción, unidades, precio unidad, total) y foto del producto.
-- ============================================================================

-- Datos de la cotización que originó la orden.  [IMPL] [VALIDAR]
alter table public.orden_compra
  add column numero_cotizacion text,          -- ID Mercado Público, ej. 5609-132-COT26
  add column fecha_cotizacion date;

create unique index orden_compra_numero_cotizacion_uidx
  on public.orden_compra (numero_cotizacion)
  where numero_cotizacion is not null;        -- evita importar dos veces la misma

-- Foto del producto (ruta en Storage, bucket "productos").  [IMPL] [VALIDAR]
alter table public.producto add column foto_path text;

-- Bucket privado: solo el Administrador sube y ve las fotos.
insert into storage.buckets (id, name, public)
values ('productos', 'productos', false)
on conflict (id) do nothing;

create policy "productos storage: administrador"
  on storage.objects for all
  using (bucket_id = 'productos' and public.es_administrador())
  with check (bucket_id = 'productos' and public.es_administrador());
