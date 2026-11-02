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

-- Rumskamrat är knuten till en viss resa, inte personens permanenta profil.
-- Värdet kan vara null när rumskamrat ännu inte är bestämd.
alter table public.trip_participation
 add column if not exists roommate_person_id uuid references public.people(id);
alter table public.trip_participation
 add constraint roommate_not_self check (roommate_person_id is null or roommate_person_id <> person_id);
-- Säkerställ i applikationslogiken att rumskamraten deltar i samma resa.
-- Låt reseledningen bekräfta rumsfördelningen; deltagarens val är ett önskemål.

-- Integritetsregel: roommate_person_id är en privat uppgift.
-- Exponera aldrig denna kolumn i publika deltagarvyer eller allmänna API-svar.
-- Endast den berörda deltagaren och behörig reseledning ska få läsa/ändra.
-- OBS: RLS är radbaserad, inte kolumnbaserad. En generell SELECT-policy
-- för deltagare på trip_participation skulle även exponera roommate_person_id.
-- Använd därför separata behörighetskontrollerade vyer/RPC:er eller
-- en privat tabell med strikt RLS innan någon SELECT-policy aktiveras.
