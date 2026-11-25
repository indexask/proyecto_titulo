-- Esquema inicial: perfiles, cotizaciones, rutas y puntos de ruta.

-- gen_random_uuid() es nativa de PostgreSQL (no requiere la extensión uuid-ossp,
-- que en Supabase vive en el esquema "extensions" y falla en `db push`).

-- ============================================================
-- profiles
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'chofer' check (role in ('chofer', 'admin')),
  created_at timestamptz not null default now()
);

-- Crea automáticamente el perfil (rol chofer por defecto) al registrarse.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, new.raw_user_meta_data ->> 'full_name', 'chofer');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- helper: es admin el usuario actual
create function public.is_admin()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ============================================================
-- cotizaciones
-- ============================================================
create table public.cotizaciones (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  cliente text,
  monto numeric,
  archivo_url text,
  admin_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

-- ============================================================
-- rutas
-- ============================================================
create table public.rutas (
  id uuid primary key default gen_random_uuid(),
  cotizacion_id uuid not null references public.cotizaciones (id) on delete cascade,
  chofer_id uuid references public.profiles (id),
  nombre text not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'en_curso', 'completada')),
  created_at timestamptz not null default now()
);

-- ============================================================
-- puntos_ruta
-- ============================================================
create table public.puntos_ruta (
  id uuid primary key default gen_random_uuid(),
  ruta_id uuid not null references public.rutas (id) on delete cascade,
  orden int not null default 0,
  direccion text not null,
  lat double precision not null,
  lng double precision not null,
  notas text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Row Level Security (todas las tablas ya existen a esta altura,
-- así que las policies cruzadas entre tablas pueden resolverse).
-- ============================================================

alter table public.profiles enable row level security;

create policy "profiles: self select"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles: admin select all"
  on public.profiles for select
  using (public.is_admin());

create policy "profiles: self update"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and role = (select role from public.profiles where id = auth.uid()));

create policy "profiles: admin update all"
  on public.profiles for update
  using (public.is_admin());

alter table public.cotizaciones enable row level security;

create policy "cotizaciones: admin all"
  on public.cotizaciones for all
  using (public.is_admin())
  with check (public.is_admin());

create policy "cotizaciones: chofer select asignadas"
  on public.cotizaciones for select
  using (
    exists (
      select 1 from public.rutas r
      where r.cotizacion_id = cotizaciones.id and r.chofer_id = auth.uid()
    )
  );

alter table public.rutas enable row level security;

create policy "rutas: admin all"
  on public.rutas for all
  using (public.is_admin())
  with check (public.is_admin());

create policy "rutas: chofer select propias"
  on public.rutas for select
  using (chofer_id = auth.uid());

create policy "rutas: chofer update estado propias"
  on public.rutas for update
  using (chofer_id = auth.uid())
  with check (chofer_id = auth.uid());

alter table public.puntos_ruta enable row level security;

create policy "puntos_ruta: admin all"
  on public.puntos_ruta for all
  using (public.is_admin())
  with check (public.is_admin());

create policy "puntos_ruta: chofer select de sus rutas"
  on public.puntos_ruta for select
  using (
    exists (
      select 1 from public.rutas r
      where r.id = puntos_ruta.ruta_id and r.chofer_id = auth.uid()
    )
  );

-- ============================================================
-- storage: bucket de archivos de cotizaciones
-- ============================================================
insert into storage.buckets (id, name, public)
values ('cotizaciones', 'cotizaciones', false)
on conflict (id) do nothing;

create policy "cotizaciones storage: admin manage"
  on storage.objects for all
  using (bucket_id = 'cotizaciones' and public.is_admin())
  with check (bucket_id = 'cotizaciones' and public.is_admin());

create policy "cotizaciones storage: authenticated read"
  on storage.objects for select
  using (bucket_id = 'cotizaciones' and auth.role() = 'authenticated');
