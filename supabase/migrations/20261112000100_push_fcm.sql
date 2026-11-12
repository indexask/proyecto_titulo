-- ============================================================================
-- GyGTrack — Envío de alertas por notificación push (RF-19).
--
-- Firebase Cloud Messaging (FCM) se usa ÚNICAMENTE como canal de envío de
-- notificaciones push. La lógica de cuándo alertar sigue en Supabase
-- (generar_alertas + pg_cron). Base de datos y backend: Supabase.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Dispositivos registrados para recibir push
-- ----------------------------------------------------------------------------
create table public.dispositivo_push (
  token text primary key,                       -- token FCM del dispositivo
  usuario_id uuid not null references public.usuario (id) on delete cascade,
  plataforma text not null check (plataforma in ('android', 'ios')),
  actualizado_en timestamptz not null default now()
);

create index dispositivo_push_usuario_idx on public.dispositivo_push (usuario_id);

alter table public.dispositivo_push enable row level security;

create policy "dispositivo_push: ver los propios" on public.dispositivo_push
  for select using (usuario_id = auth.uid());
create policy "dispositivo_push: borrar los propios" on public.dispositivo_push
  for delete using (usuario_id = auth.uid());

-- Registra (o reasigna, si el teléfono cambió de usuario) el token del
-- dispositivo de quien llama.
create function public.registrar_dispositivo_push(p_token text, p_plataforma text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;
  insert into public.dispositivo_push (token, usuario_id, plataforma)
  values (p_token, auth.uid(), p_plataforma)
  on conflict (token) do update
    set usuario_id = excluded.usuario_id,
        plataforma = excluded.plataforma,
        actualizado_en = now();
end;
$$;

revoke execute on function public.registrar_dispositivo_push(text, text) from public, anon;
grant execute on function public.registrar_dispositivo_push(text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Disparo del envío desde el CRON
-- Llama a la Edge Function `enviar-alertas` con pg_net. La URL del proyecto
-- y la service_role key se guardan en Supabase Vault (ver README):
--   gygtrack_url_proyecto, gygtrack_service_role_key
-- Si no están configuradas, no hace nada (las alertas igual quedan
-- registradas y visibles en la app).
-- ----------------------------------------------------------------------------
create extension if not exists pg_net;

create function public.disparar_envio_push()
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_url text;
  v_clave text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'gygtrack_url_proyecto';
  select decrypted_secret into v_clave
    from vault.decrypted_secrets where name = 'gygtrack_service_role_key';

  if v_url is null or v_clave is null then
    return false;
  end if;

  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/enviar-alertas',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_clave
    ),
    body := '{}'::jsonb
  );
  return true;
end;
$$;

revoke execute on function public.disparar_envio_push() from public, anon, authenticated;

-- El CRON ahora genera las alertas y, a continuación, dispara su envío push.
select cron.schedule(
  'gygtrack-generar-alertas',
  '0 * * * *',
  $$select public.generar_alertas(); select public.disparar_envio_push();$$
);
