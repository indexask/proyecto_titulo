-- ============================================================================
-- GyGTrack — Detalle de la optimización de rutas (RF-22, RF-24).
-- Guarda la comparación completa que calcula optimizar-ruta: tiempo, km, TAG
-- y combustible de la ruta sin optimizar, con TAG y sin TAG, más el motivo de
-- la elección (regla de $500 por cada 10 minutos).
-- ============================================================================

alter table public.ruta add column detalle_optimizacion jsonb;   -- [IMPL] solo Administrador

-- El Chofer ve si su ruta usa autopistas con TAG (dato operativo, no
-- financiero). Las columnas nuevas de una vista van al final.
create or replace view public.v_ruta_chofer
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
       ), '[]'::jsonb) as paradas,
       r.usa_peajes
  from public.ruta r
 where r.chofer_id = auth.uid();
