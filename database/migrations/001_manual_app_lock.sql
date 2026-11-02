-- LDV: manuell låsning av appen, migration 001.
-- Kör i Supabase SQL Editor efter database/schema.sql.
-- Lämnar appen STÄNGD tills admin uttryckligen öppnar den.
create table if not exists public.ldv_admins (
 user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.ldv_admins enable row level security;
revoke all on public.ldv_admins from anon, authenticated;

create table if not exists public.app_access_settings (
 id boolean primary key default true check(id),
 is_open boolean not null default false,
 active_trip_id bigint references public.trips(id),
 changed_at timestamptz not null default now(),
 changed_by uuid references auth.users(id)
);
insert into public.app_access_settings(id,is_open) values (true,false)
on conflict(id) do nothing;
alter table public.app_access_settings enable row level security;
revoke all on public.app_access_settings from anon, authenticated;

create table if not exists public.app_access_audit (
 id bigint generated always as identity primary key,
 is_open boolean not null,
 active_trip_id bigint,
 changed_by uuid not null,
 changed_at timestamptz not null default now()
);
alter table public.app_access_audit enable row level security;
revoke all on public.app_access_audit from anon, authenticated;

-- Inget offentligt direktåtkomst till inställningstabellen.
-- Status kan läsas av alla, utan att personuppgifter exponeras.
create or replace function public.ldv_access_status()
returns table(is_open boolean, active_trip_id bigint)
language sql stable security definer set search_path = ''
as $$
  select s.is_open,s.active_trip_id from public.app_access_settings s where s.id=true
$$;
revoke all on function public.ldv_access_status() from public;
grant execute on function public.ldv_access_status() to anon, authenticated;

create or replace function public.ldv_set_access(p_is_open boolean,p_trip_id bigint default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not exists(select 1 from public.ldv_admins where user_id=v_uid) then
    raise exception 'Not authorized';
  end if;
  if p_is_open and p_trip_id is null then
    raise exception 'An active trip is required when opening the app';
  end if;
  if p_trip_id is not null and not exists(select 1 from public.trips where id=p_trip_id) then
    raise exception 'Unknown trip';
  end if;
  update public.app_access_settings
    set is_open=p_is_open,
        active_trip_id=coalesce(p_trip_id,active_trip_id),
        changed_at=now(),changed_by=v_uid
    where id=true;
  insert into public.app_access_audit(is_open,active_trip_id,changed_by)
    select is_open,active_trip_id,v_uid from public.app_access_settings where id=true;
end
$$;
revoke all on function public.ldv_set_access(boolean,bigint) from public;
grant execute on function public.ldv_set_access(boolean,bigint) to authenticated;

-- Innan drift:
-- 1. Lägg in admin-user_id i ldv_admins via SQL Editor efter Auth-registrering.
-- 2. Skydda ALLA deltagar-API:er och bild-URL:er separat mot låst läge.
-- 3. Aktivera inte öppning innan behörigheter, profiler och storage är testade.
-- GitHub Pages är publik statisk kod; låsning kan inte göra den hemlig.
