-- Clean It — Agenda Comercial / Mini CRM v2
-- Ejecutar completo en Supabase > SQL Editor.
-- Es reejecutable y no borra datos existentes.

create extension if not exists pgcrypto;

-- =========================================================
-- 1) Perfiles y roles
-- =========================================================

create table if not exists public.cleanit_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'operador'
    check (role in ('operador', 'supervisora', 'admin')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.cleanit_profiles add column if not exists email text;
alter table public.cleanit_profiles add column if not exists full_name text;
alter table public.cleanit_profiles add column if not exists role text not null default 'operador';
alter table public.cleanit_profiles add column if not exists active boolean not null default true;
alter table public.cleanit_profiles add column if not exists created_at timestamptz not null default now();
alter table public.cleanit_profiles add column if not exists updated_at timestamptz not null default now();

create index if not exists cleanit_profiles_role_idx on public.cleanit_profiles(role, active);
create index if not exists cleanit_profiles_email_idx on public.cleanit_profiles(email);

-- =========================================================
-- 2) Agenda / seguimientos comerciales
-- =========================================================

create table if not exists public.cleanit_commercial_agenda (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,

  title text not null,
  contact_name text,
  company text,
  phone text,
  email text,

  kommo_link text,
  service_type text,
  description text,

  stage text not null default 'lead'
    check (stage in ('lead', 'contactado', 'presupuestado', 'negociacion', 'ganado', 'perdido')),
  priority text not null default 'media'
    check (priority in ('baja', 'media', 'alta')),
  status text not null default 'pendiente'
    check (status in ('pendiente', 'en_proceso', 'completado', 'cancelado')),

  due_date date,
  due_time time,
  amount numeric(14,2) default 0,
  source text,
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Migración no destructiva para quienes ya instalaron la v1.
alter table public.cleanit_commercial_agenda add column if not exists user_id uuid default auth.uid() references auth.users(id) on delete cascade;
alter table public.cleanit_commercial_agenda add column if not exists kommo_link text;
alter table public.cleanit_commercial_agenda add column if not exists service_type text;
alter table public.cleanit_commercial_agenda add column if not exists description text;
alter table public.cleanit_commercial_agenda add column if not exists amount numeric(14,2) default 0;
alter table public.cleanit_commercial_agenda add column if not exists source text;
alter table public.cleanit_commercial_agenda add column if not exists notes text;

create index if not exists cleanit_agenda_user_due_idx on public.cleanit_commercial_agenda(user_id, due_date, due_time);
create index if not exists cleanit_agenda_user_stage_idx on public.cleanit_commercial_agenda(user_id, stage);
create index if not exists cleanit_agenda_user_status_idx on public.cleanit_commercial_agenda(user_id, status);
create index if not exists cleanit_agenda_kommo_idx on public.cleanit_commercial_agenda(kommo_link);

-- =========================================================
-- 3) Triggers de updated_at
-- =========================================================

create or replace function public.set_cleanit_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_cleanit_profiles_updated_at on public.cleanit_profiles;
create trigger trg_cleanit_profiles_updated_at
before update on public.cleanit_profiles
for each row execute function public.set_cleanit_updated_at();

drop trigger if exists trg_cleanit_agenda_updated_at on public.cleanit_commercial_agenda;
create trigger trg_cleanit_agenda_updated_at
before update on public.cleanit_commercial_agenda
for each row execute function public.set_cleanit_updated_at();

-- Crear perfil automáticamente cuando se crea un usuario en Supabase Auth.
create or replace function public.cleanit_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.cleanit_profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    'operador'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_cleanit_auth_user_created on auth.users;
create trigger on_cleanit_auth_user_created
after insert on auth.users
for each row execute procedure public.cleanit_handle_new_user();

-- Backfill de perfiles para usuarios ya existentes.
insert into public.cleanit_profiles (id, email, full_name, role)
select
  id,
  email,
  coalesce(raw_user_meta_data ->> 'full_name', split_part(email, '@', 1)),
  'operador'
from auth.users
on conflict (id) do nothing;

-- =========================================================
-- 4) Helpers seguros para RLS
-- =========================================================

create or replace function public.cleanit_current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.cleanit_profiles where id = auth.uid() and active = true limit 1), 'operador');
$$;

create or replace function public.cleanit_is_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.cleanit_current_role() in ('supervisora', 'admin');
$$;

create or replace function public.cleanit_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.cleanit_current_role() = 'admin';
$$;

-- =========================================================
-- 5) Row Level Security
-- =========================================================

alter table public.cleanit_profiles enable row level security;
alter table public.cleanit_commercial_agenda enable row level security;

-- Perfiles

drop policy if exists "cleanit_profiles_select_scope" on public.cleanit_profiles;
drop policy if exists "cleanit_profiles_insert_self" on public.cleanit_profiles;
drop policy if exists "cleanit_profiles_update_admin" on public.cleanit_profiles;
drop policy if exists "cleanit_profiles_delete_admin" on public.cleanit_profiles;

create policy "cleanit_profiles_select_scope"
on public.cleanit_profiles
for select
to authenticated
using (id = auth.uid() or public.cleanit_is_manager());

create policy "cleanit_profiles_insert_self"
on public.cleanit_profiles
for insert
to authenticated
with check (id = auth.uid() and role = 'operador');

create policy "cleanit_profiles_update_admin"
on public.cleanit_profiles
for update
to authenticated
using (public.cleanit_is_admin())
with check (public.cleanit_is_admin());

create policy "cleanit_profiles_delete_admin"
on public.cleanit_profiles
for delete
to authenticated
using (public.cleanit_is_admin());

-- Agenda

drop policy if exists "cleanit_agenda_select_own" on public.cleanit_commercial_agenda;
drop policy if exists "cleanit_agenda_insert_own" on public.cleanit_commercial_agenda;
drop policy if exists "cleanit_agenda_update_own" on public.cleanit_commercial_agenda;
drop policy if exists "cleanit_agenda_delete_own" on public.cleanit_commercial_agenda;
drop policy if exists "cleanit_agenda_select_scope_v2" on public.cleanit_commercial_agenda;
drop policy if exists "cleanit_agenda_insert_own_v2" on public.cleanit_commercial_agenda;
drop policy if exists "cleanit_agenda_update_own_or_admin_v2" on public.cleanit_commercial_agenda;
drop policy if exists "cleanit_agenda_delete_own_or_admin_v2" on public.cleanit_commercial_agenda;

create policy "cleanit_agenda_select_scope_v2"
on public.cleanit_commercial_agenda
for select
to authenticated
using (user_id = auth.uid() or public.cleanit_is_manager());

create policy "cleanit_agenda_insert_own_v2"
on public.cleanit_commercial_agenda
for insert
to authenticated
with check (user_id = auth.uid());

create policy "cleanit_agenda_update_own_or_admin_v2"
on public.cleanit_commercial_agenda
for update
to authenticated
using (user_id = auth.uid() or public.cleanit_is_admin())
with check (user_id = auth.uid() or public.cleanit_is_admin());

create policy "cleanit_agenda_delete_own_or_admin_v2"
on public.cleanit_commercial_agenda
for delete
to authenticated
using (user_id = auth.uid() or public.cleanit_is_admin());

-- =========================================================
-- 6) Cómo asignar roles
-- =========================================================
-- Luego de crear los usuarios en Supabase Auth, ejecutar algo así:
--
-- update public.cleanit_profiles
-- set full_name = 'Nombre Operador', role = 'operador'
-- where email = 'operador@cleanit.com.ar';
--
-- update public.cleanit_profiles
-- set full_name = 'Nombre Supervisora', role = 'supervisora'
-- where email = 'supervisora@cleanit.com.ar';
--
-- update public.cleanit_profiles
-- set full_name = 'Administrador', role = 'admin'
-- where email = 'admin@cleanit.com.ar';
