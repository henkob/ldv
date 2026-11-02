-- LDV personregister. Kör manuellt i ett privat Supabase-projekt.
-- OBS: importera aldrig personuppgifter i det publika GitHub-repot.
create extension if not exists pgcrypto;
create table if not exists public.trips (
 id bigint generated always as identity primary key,
 year integer not null unique,
 destination text not null,
 is_current boolean not null default false
);
create table if not exists public.people (
 id uuid primary key default gen_random_uuid(),
 first_name text not null,
 last_name text not null,
 nickname text,
 email text,
 phone text,
 bio text,
 helmet_color text,
 jacket_color text,
 pants_color text,
 photo_path text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists people_email_unique on public.people (lower(email)) where email is not null;
create table if not exists public.trip_participation (
 person_id uuid not null references public.people(id) on delete cascade,
 trip_id bigint not null references public.trips(id) on delete cascade,
 status text not null check(status in ('confirmed','pending','cancelled')),
 role text,
 -- Antal GENOMFÖRDA resor före detta års resa, om äldre historik inte finns digitalt.
 previous_trips_baseline integer check(previous_trips_baseline >= 0),
 primary key(person_id,trip_id)
);
insert into public.trips(year,destination,is_current) values
 (2026,'Grandvalira',false),(2027,'Sankt Anton',true)
on conflict(year) do update set destination=excluded.destination;
-- Skydda personuppgifter: inga anonyma läsrättigheter.
alter table public.people enable row level security;
alter table public.trip_participation enable row level security;
alter table public.trips enable row level security;
-- Policys för autentiserade användare och administratörer läggs till
-- först när autentisering och rollmodell har implementerats.
-- Service role får aldrig exponeras i frontend.

-- Privat rumsfördelning: ENDAST reseledningen ska få åtkomst.
-- Separat tabell förhindrar att uppgiften oavsiktligt följer med i deltagar-API.
create table if not exists public.room_assignments (
 trip_id bigint not null references public.trips(id) on delete cascade,
 person_id uuid not null,
 roommate_person_id uuid,
 updated_at timestamptz not null default now(),
 primary key(trip_id, person_id),
 foreign key(person_id, trip_id)
   references public.trip_participation(person_id, trip_id) on delete cascade,
 foreign key(roommate_person_id, trip_id)
   references public.trip_participation(person_id, trip_id),
 constraint not_own_roommate check (roommate_person_id is null or roommate_person_id <> person_id)
);
alter table public.room_assignments enable row level security;
-- Inga klientpolicys ännu: även inloggade deltagare nekas åtkomst.
-- Adminåtkomst ska implementeras med en säker serverfunktion och rollkontroll.
-- Deltagare får varken se, välja eller ändra rumskamrat.

-- Behörigheter för övriga tabeller, bildlagring och administratörer
-- måste färdigställas och testas innan registret tas i drift.

-- LDV resehistorik: automatiskt per resa.
-- Kör detta som en separat migration i Supabase SQL Editor på befintlig databas.
-- Skapa en resa i trips i förväg. Resans slutdatum avgör när den är genomförd.
alter table public.trips add column if not exists end_date date;
alter table public.trips add column if not exists trip_status text not null default 'planned';
-- Tillåt framtida planering utan att automatiskt räkna anmälda som veteraner.
-- trip_status: planned, ongoing, completed, cancelled
create or replace view public.ldv_completed_trip_counts
with (security_invoker = true) as
select p.id as person_id,
       count(tp.trip_id) filter (
         where t.trip_status = 'completed'
           and t.end_date < current_date
           and tp.status = 'confirmed'
       )::integer as completed_trips
from public.people p
left join public.trip_participation tp on tp.person_id = p.id
left join public.trips t on t.id = tp.trip_id
group by p.id;
-- OBS: vyn är endast en grund för summering, inte en publik endpoint.
-- RLS/rollkontroll för både personakter och deltagande måste vara klar först.
-- Markera genomförd resa som completed efter hemkomst; anmälda som inte
-- faktiskt reste måste markeras cancelled. Enbart datum räcker inte.
