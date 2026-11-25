-- ============================================================================
-- GyGTrack — Estado "No entregado" con justificación obligatoria (RF-14, RF-16).
-- Solicitud del equipo (2026-11-23): el Chofer puede marcar un despacho como
-- NO entregado y DEBE justificar por qué no se pudo entregar.
--
-- Amplía la máquina de estados del despacho:
--   pendiente → en_ruta → entregado            (camino normal)
--   en_ruta → no_entregado                     (requiere motivo)
--   no_entregado → en_ruta | entregado         (reintento / entrega posterior)
-- "entregado" sigue siendo terminal.
-- ============================================================================

-- 1. Justificación de la no entrega (solo tiene sentido en estado 'no_entregado').
alter table public.despacho
  add column motivo_no_entrega text;                 -- [IMPL] RF-14/RF-16

-- 2. Nuevo estado permitido en el despacho.
alter table public.despacho drop constraint despacho_estado_check;
alter table public.despacho
  add constraint despacho_estado_check
  check (estado in ('pendiente', 'en_ruta', 'entregado', 'no_entregado'));

-- 3. El motivo es obligatorio (y solo existe) cuando el despacho NO se entregó.
alter table public.despacho
  add constraint despacho_motivo_no_entrega_check
  check (
    (estado = 'no_entregado' and btrim(coalesce(motivo_no_entrega, '')) <> '')
    or (estado <> 'no_entregado' and motivo_no_entrega is null)
  );

-- 4. Transiciones válidas de la máquina de estados (una sola fuente de verdad).
create or replace function public.transicion_despacho_valida(p_desde text, p_hasta text)
returns boolean
language sql
immutable
as $$
  select (p_desde, p_hasta) in (
    ('pendiente', 'en_ruta'),
    ('en_ruta', 'entregado'),
    ('en_ruta', 'no_entregado'),
    ('no_entregado', 'en_ruta'),
    ('no_entregado', 'entregado')
  );
$$;

-- 5. El trigger deja de depender del orden lineal y usa las transiciones válidas.
--    Al salir de 'no_entregado' se limpia el motivo; al entrar, el CHECK exige
--    que venga con motivo.
create or replace function public.despacho_validar_transicion()
returns trigger
language plpgsql
as $$
begin
  if new.estado is distinct from old.estado then
    if not public.transicion_despacho_valida(old.estado, new.estado) then
      raise exception 'Transición de estado no permitida: % → %', old.estado, new.estado
        using errcode = 'P0001';
    end if;
  end if;
  if new.estado <> 'no_entregado' then
    new.motivo_no_entrega := null;
  end if;
  new.actualizado_en := now();
  return new;
end;
$$;

-- 6. RPC de cambio de estado: ahora acepta el motivo. Se reemplaza la versión
--    de 3 argumentos (hay que borrarla porque la firma cambia).
drop function if exists public.cambiar_estado_despacho(uuid, text, timestamptz);

create function public.cambiar_estado_despacho(
  p_despacho_id uuid,
  p_estado text,
  p_ocurrido_en timestamptz default now(),
  p_motivo text default null
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

  if p_estado not in ('pendiente', 'en_ruta', 'entregado', 'no_entregado') then
    raise exception 'Estado inválido: %', p_estado using errcode = '22023';
  end if;

  -- Idempotencia para la cola offline: el mismo estado no hace nada.
  if p_estado = v_actual then
    return v_actual;
  end if;
  -- "Entregado" es terminal: un reintento rezagado de la cola no lo revierte.
  if v_actual = 'entregado' then
    return v_actual;
  end if;

  if not public.transicion_despacho_valida(v_actual, p_estado) then
    raise exception 'Transición de estado no permitida: % → %', v_actual, p_estado
      using errcode = 'P0001';
  end if;

  if p_estado = 'no_entregado' and btrim(coalesce(p_motivo, '')) = '' then
    raise exception 'Debe indicar el motivo de la no entrega' using errcode = '22023';
  end if;

  update public.despacho
     set estado = p_estado,
         motivo_no_entrega = case when p_estado = 'no_entregado' then p_motivo else null end,
         fecha_hora_entrega = case when p_estado = 'entregado' then v_momento
                                   when p_estado = 'no_entregado' then null
                                   else fecha_hora_entrega end,
         confirmado_en_app = case when p_estado = 'entregado' then (v_rol = 'chofer')
                                  when p_estado = 'no_entregado' then false
                                  else confirmado_en_app end
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

-- 7. El Chofer ve su propia justificación (dato operativo, no financiero).
--    Las columnas nuevas de una vista van al final (create or replace).
create or replace view public.v_despacho_chofer
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
       ), '[]'::jsonb)      as productos,
       d.motivo_no_entrega
  from public.despacho d
  join public.orden_compra o on o.id = d.orden_id
 where o.responsable_id = auth.uid()
    or exists (
      select 1 from public.ruta_parada rp
      join public.ruta r on r.id = rp.ruta_id
      where rp.despacho_id = d.id and r.chofer_id = auth.uid()
    );
