-- ============================================================================
-- GyGTrack — Cambiar la alternativa de una ruta (RF-22, RF-24).
-- optimizar-ruta guarda en detalle_optimizacion.alternativas las 3
-- alternativas calculadas (orden por plazo, optimizada con TAG, optimizada
-- sin TAG) con su trazado, orden de paradas y TAG. El Administrador puede
-- aplicar otra según su criterio (menos tiempo, menos plata, menos km); la
-- recomendada por el sistema es la equilibrada (costo + $50/min).
-- ============================================================================

create or replace function public.elegir_alternativa_ruta(
  p_ruta_id uuid,
  p_alternativa text,
  p_criterio text,
  p_motivo text default null
) returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_detalle jsonb;
  v_alt jsonb;
begin
  if not public.es_administrador() then
    raise exception 'Solo el Administrador puede cambiar la ruta' using errcode = '42501';
  end if;
  if p_alternativa not in ('sin_optimizar', 'con_tag', 'sin_tag') then
    raise exception 'Alternativa no válida: %', p_alternativa using errcode = '22023';
  end if;
  if p_criterio not in ('equilibrada', 'menos_tiempo', 'menos_plata', 'menos_km') then
    raise exception 'Criterio no válido: %', p_criterio using errcode = '22023';
  end if;

  select detalle_optimizacion into v_detalle from public.ruta where id = p_ruta_id for update;
  if not found then
    raise exception 'Ruta no encontrada' using errcode = 'P0002';
  end if;
  v_alt := v_detalle -> 'alternativas' -> p_alternativa;
  if v_alt is null then
    raise exception 'Esta ruta se calculó antes de guardar las alternativas; vuelve a calcularla' using errcode = '22023';
  end if;

  -- Si el Chofer ya salió, el orden de las paradas no se cambia.
  if exists (
    select 1 from public.ruta_parada rp
      join public.despacho d on d.id = rp.despacho_id
     where rp.ruta_id = p_ruta_id and d.estado <> 'pendiente'
  ) then
    raise exception 'La ruta ya comenzó: no se puede cambiar la alternativa' using errcode = '55000';
  end if;

  update public.ruta
     set polilinea = v_alt ->> 'polilinea',
         distancia_km = (v_alt ->> 'distanciaKm')::numeric,
         duracion_min = (v_alt ->> 'duracionMin')::integer,
         usa_peajes = coalesce((v_alt ->> 'usaPeajes')::boolean, false),
         costo_ruta_optimizada = (v_alt ->> 'costoClp')::numeric,
         detalle_optimizacion = v_detalle || jsonb_build_object(
           'elegida', p_alternativa,
           'criterio', p_criterio,
           'peajes', v_alt -> 'peajes',
           'motivo', coalesce(p_motivo, v_detalle ->> 'motivo')
         )
   where id = p_ruta_id;

  -- Nuevo orden de paradas (se borra y se vuelve a insertar por unique(ruta_id, orden)).
  delete from public.ruta_parada where ruta_id = p_ruta_id;
  insert into public.ruta_parada (ruta_id, despacho_id, orden)
  select p_ruta_id, (x.despacho_id)::uuid, x.posicion - 1
    from jsonb_array_elements_text(v_alt -> 'despachoIds') with ordinality as x(despacho_id, posicion);
end;
$$;

revoke all on function public.elegir_alternativa_ruta(uuid, text, text, text) from public, anon;
grant execute on function public.elegir_alternativa_ruta(uuid, text, text, text) to authenticated;
