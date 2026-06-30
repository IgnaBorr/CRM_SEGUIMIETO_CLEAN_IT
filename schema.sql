-- =========================================================
-- Clean It - Recontactador Kommo
-- Supabase schema + RLS
-- Ejecutar completo en Supabase > SQL Editor
-- =========================================================

create extension if not exists pgcrypto;

-- Perfiles de usuarios internos
create table if not exists public.cleanit_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique,
  full_name text,
  role text not null default 'operador' check (role in ('operador', 'supervisora', 'admin')),
  franquicias text[] default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Base histórica de turnos/leads cancelados o perdidos para recontacto
create table if not exists public.cleanit_recontacts (
  id uuid primary key default gen_random_uuid(),
  external_key text not null unique,

  -- Trazabilidad Kommo / origen
  source text default 'kommo_sheet',
  kommo_id text,
  kommo_link text,
  estado_original text, -- Cancelado / Lead perdido / Perdido / otro valor original
  raw_data jsonb default '{}'::jsonb,

  -- Datos comerciales
  fecha_turno date,
  cliente text,
  telefono text,
  email text,
  franquicia text,
  servicio text,
  monto numeric(14,2) default 0,

  -- Gestión de recontacto
  estado_contacto text not null default 'Sin contactar'
    check (estado_contacto in ('Sin contactar', 'Recontactado', 'Cerrado')),
  observaciones text default '',
  servicio_realizado boolean not null default false,

  -- Asignación y auditoría
  assigned_to uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null,
  imported_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_cleanit_recontacts_franquicia on public.cleanit_recontacts(franquicia);
create index if not exists idx_cleanit_recontacts_servicio on public.cleanit_recontacts(servicio);
create index if not exists idx_cleanit_recontacts_monto on public.cleanit_recontacts(monto desc);
create index if not exists idx_cleanit_recontacts_estado_contacto on public.cleanit_recontacts(estado_contacto);
create index if not exists idx_cleanit_recontacts_servicio_realizado on public.cleanit_recontacts(servicio_realizado);
create index if not exists idx_cleanit_recontacts_assigned_to on public.cleanit_recontacts(assigned_to);
create index if not exists idx_cleanit_recontacts_fecha_turno on public.cleanit_recontacts(fecha_turno desc);

-- Timestamp automático
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_cleanit_profiles_updated_at on public.cleanit_profiles;
create trigger trg_cleanit_profiles_updated_at
before update on public.cleanit_profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_cleanit_recontacts_updated_at on public.cleanit_recontacts;
create trigger trg_cleanit_recontacts_updated_at
before update on public.cleanit_recontacts
for each row execute function public.set_updated_at();

-- Crear perfil automáticamente al crear usuario Auth
create or replace function public.handle_new_cleanit_user()
returns trigger as $$
begin
  insert into public.cleanit_profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'role', 'operador')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_cleanit_user_created on auth.users;
create trigger on_auth_cleanit_user_created
after insert on auth.users
for each row execute function public.handle_new_cleanit_user();

-- Helper de rol
create or replace function public.current_cleanit_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.cleanit_profiles where id = auth.uid()), 'operador')
$$;

-- Helper de franquicias del usuario
create or replace function public.current_cleanit_franquicias()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select franquicias from public.cleanit_profiles where id = auth.uid()), '{}')
$$;

-- RLS
alter table public.cleanit_profiles enable row level security;
alter table public.cleanit_recontacts enable row level security;

-- Limpieza de políticas previas
DROP POLICY IF EXISTS "profiles_select" ON public.cleanit_profiles;
DROP POLICY IF EXISTS "profiles_update_self" ON public.cleanit_profiles;
DROP POLICY IF EXISTS "profiles_admin_update" ON public.cleanit_profiles;
DROP POLICY IF EXISTS "recontacts_select" ON public.cleanit_recontacts;
DROP POLICY IF EXISTS "recontacts_insert" ON public.cleanit_recontacts;
DROP POLICY IF EXISTS "recontacts_update" ON public.cleanit_recontacts;
DROP POLICY IF EXISTS "recontacts_delete" ON public.cleanit_recontacts;

-- Perfiles: todos los usuarios internos pueden ver nombres/roles para filtros.
-- Si querés máxima restricción, cambiá esta política por una más cerrada.
create policy "profiles_select"
on public.cleanit_profiles
for select
to authenticated
using (true);

create policy "profiles_update_self"
on public.cleanit_profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "profiles_admin_update"
on public.cleanit_profiles
for update
to authenticated
using (public.current_cleanit_role() = 'admin')
with check (public.current_cleanit_role() = 'admin');

-- Recontactos:
-- admin y supervisora ven todo.
-- operador ve lo asignado a su usuario. Si no trabajás con asignaciones, dejá a la supervisora/admin como usuarios principales.
create policy "recontacts_select"
on public.cleanit_recontacts
for select
to authenticated
using (
  public.current_cleanit_role() in ('admin', 'supervisora')
  or assigned_to = auth.uid()
);

-- Carga/importación: admin y supervisora pueden cargar base histórica.
-- operador puede crear registros propios.
create policy "recontacts_insert"
on public.cleanit_recontacts
for insert
to authenticated
with check (
  public.current_cleanit_role() in ('admin', 'supervisora')
  or assigned_to = auth.uid()
  or assigned_to is null
);

-- Actualización: admin/supervisora pueden actualizar todo.
-- operador solo los propios.
create policy "recontacts_update"
on public.cleanit_recontacts
for update
to authenticated
using (
  public.current_cleanit_role() in ('admin', 'supervisora')
  or assigned_to = auth.uid()
)
with check (
  public.current_cleanit_role() in ('admin', 'supervisora')
  or assigned_to = auth.uid()
);

-- Eliminación solo admin.
create policy "recontacts_delete"
on public.cleanit_recontacts
for delete
to authenticated
using (public.current_cleanit_role() = 'admin');

-- =========================================================
-- Asignación de roles - ejemplos
-- =========================================================
-- update public.cleanit_profiles
-- set full_name = 'Nombre Supervisora', role = 'supervisora'
-- where email = 'supervisora@cleanit.com.ar';
--
-- update public.cleanit_profiles
-- set full_name = 'Nombre Operador', role = 'operador'
-- where email = 'operador@cleanit.com.ar';
--
-- update public.cleanit_profiles
-- set role = 'admin'
-- where email = 'admin@cleanit.com.ar';

-- =========================================================
-- V2 Realtime / Sync desde Google Sheets
-- Ejecutar también si ya instalaste la versión anterior.
-- =========================================================

alter table public.cleanit_recontacts
  add column if not exists source_hash text,
  add column if not exists source_last_seen_at timestamptz,
  add column if not exists active_in_source boolean not null default true;

create index if not exists idx_cleanit_recontacts_source_seen on public.cleanit_recontacts(source_last_seen_at desc);
create index if not exists idx_cleanit_recontacts_source_hash on public.cleanit_recontacts(source_hash);

-- Necesario para que Supabase Realtime pueda emitir updates/deletes completos.
alter table public.cleanit_recontacts replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'cleanit_recontacts'
    ) then
      alter publication supabase_realtime add table public.cleanit_recontacts;
    end if;
  end if;
exception
  when others then
    -- En algunos proyectos Supabase gestiona la publicación desde el panel Realtime.
    -- Si esto falla, activar Realtime manualmente para public.cleanit_recontacts.
    null;
end $$;

-- Sincronización segura desde el frontend autenticado.
-- Importante: actualiza solo datos base provenientes del Sheet.
-- NO pisa estado_contacto, observaciones, servicio_realizado ni assigned_to.
create or replace function public.sync_cleanit_recontacts_from_sheet(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  v_count integer := 0;
  v_role text;
  v_external_key text;
  v_monto numeric(14,2);
  v_fecha date;
begin
  if auth.uid() is null then
    raise exception 'Usuario no autenticado';
  end if;

  select role into v_role
  from public.cleanit_profiles
  where id = auth.uid();

  if coalesce(v_role, 'operador') not in ('admin', 'supervisora') then
    raise exception 'No tenés permisos para sincronizar la base';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows debe ser un array JSON';
  end if;

  for item in select * from jsonb_array_elements(p_rows)
  loop
    v_external_key := nullif(item->>'external_key', '');
    if v_external_key is null then
      v_external_key := left(encode(digest(item::text, 'sha256'), 'hex'), 48);
    end if;

    begin
      v_monto := coalesce(nullif(item->>'monto', '')::numeric, 0);
    exception when others then
      v_monto := 0;
    end;

    begin
      v_fecha := nullif(item->>'fecha_turno', '')::date;
    exception when others then
      v_fecha := null;
    end;

    insert into public.cleanit_recontacts (
      external_key,
      source,
      kommo_id,
      kommo_link,
      estado_original,
      raw_data,
      fecha_turno,
      cliente,
      telefono,
      email,
      franquicia,
      servicio,
      monto,
      estado_contacto,
      observaciones,
      servicio_realizado,
      created_by,
      updated_by,
      imported_at,
      source_last_seen_at,
      source_hash,
      active_in_source
    ) values (
      v_external_key,
      coalesce(nullif(item->>'source', ''), 'kommo_sheet'),
      nullif(item->>'kommo_id', ''),
      nullif(item->>'kommo_link', ''),
      coalesce(nullif(item->>'estado_original', ''), 'Histórico'),
      coalesce(item->'raw_data', '{}'::jsonb),
      v_fecha,
      nullif(item->>'cliente', ''),
      nullif(item->>'telefono', ''),
      nullif(item->>'email', ''),
      nullif(item->>'franquicia', ''),
      nullif(item->>'servicio', ''),
      v_monto,
      coalesce(nullif(item->>'estado_contacto', ''), 'Sin contactar'),
      coalesce(item->>'observaciones', ''),
      coalesce((item->>'servicio_realizado')::boolean, false),
      auth.uid(),
      auth.uid(),
      now(),
      now(),
      left(encode(digest(item::text, 'sha256'), 'hex'), 64),
      true
    )
    on conflict (external_key) do update set
      source = excluded.source,
      kommo_id = excluded.kommo_id,
      kommo_link = excluded.kommo_link,
      estado_original = excluded.estado_original,
      raw_data = excluded.raw_data,
      fecha_turno = excluded.fecha_turno,
      cliente = excluded.cliente,
      telefono = excluded.telefono,
      email = excluded.email,
      franquicia = excluded.franquicia,
      servicio = excluded.servicio,
      monto = excluded.monto,
      imported_at = now(),
      source_last_seen_at = now(),
      source_hash = excluded.source_hash,
      active_in_source = true,
      updated_by = auth.uid();

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.sync_cleanit_recontacts_from_sheet(jsonb) to authenticated;
