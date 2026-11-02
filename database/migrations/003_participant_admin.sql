-- LDV 003: adminhantering av deltagare och tidigare resor.
-- Kör efter 001 och 002. Alla skrivfunktioner kontrollerar adminrollen.
-- Ingen publik direktåtkomst till personregister eller deltagande.
revoke all on public.people, public.trip_participation, public.room_assignments from anon, authenticated;
alter table public.people enable row level security;
alter table public.trip_participation enable row level security;
alter table public.room_assignments enable row level security;

-- Historiska resor. 2007 och 2008 saknar ort, 2021 var pandemi.
insert into public.trips(year,destination,is_current) values
(2003,'St. Anton',false),(2004,'Gressoney',false),(2005,'Alpe d''Huez',false),
(2006,'Les Menuires',false),(2007,'Okänd ort',false),(2008,'Okänd ort',false),
(2009,'Engelberg',false),(2010,'Gressoney',false),(2011,'Sestriere',false),
(2012,'Ischgl',false),(2013,'Gressoney',false),(2014,'Cervinia',false),
(2015,'Ponte di Legno',false),(2016,'Canazei',false),(2017,'Mayrhofen',false),
(2018,'Chamonix',false),(2019,'La Thuile',false),(2020,'Serre Chevalier',false),
(2022,'Obertauern',false),(2023,'Sauze d''Oulx',false),
(2024,'Gressoney',false),(2025,'Les Arcs',false)
on conflict(year) do nothing;

create or replace function public.ldv_admin_people()
returns table(id uuid,first_name text,last_name text,nickname text,email text,phone text)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 return query select p.id,p.first_name,p.last_name,p.nickname,p.email,p.phone
 from public.people p order by p.first_name,p.last_name;
end $$;
revoke all on function public.ldv_admin_people() from public;
grant execute on function public.ldv_admin_people() to authenticated;

create or replace function public.ldv_admin_participants(p_trip_id bigint)
returns table(person_id uuid,status text)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 return query select tp.person_id,tp.status from public.trip_participation tp
 where tp.trip_id=p_trip_id;
end $$;
revoke all on function public.ldv_admin_participants(bigint) from public;
grant execute on function public.ldv_admin_participants(bigint) to authenticated;

create or replace function public.ldv_admin_add_person(p_first_name text,p_last_name text,p_email text default null,p_phone text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 if nullif(btrim(p_first_name),'') is null or nullif(btrim(p_last_name),'') is null then
  raise exception 'First and last name required';
 end if;
 insert into public.people(first_name,last_name,email,phone)
 values(btrim(p_first_name),btrim(p_last_name),nullif(btrim(p_email),''),nullif(btrim(p_phone),''))
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.ldv_admin_add_person(text,text,text,text) from public;
grant execute on function public.ldv_admin_add_person(text,text,text,text) to authenticated;

create or replace function public.ldv_admin_set_participation(p_person_id uuid,p_trip_id bigint,p_selected boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.people where id=p_person_id) or
    not exists(select 1 from public.trips where id=p_trip_id) then
  raise exception 'Unknown person or trip';
 end if;
 if p_selected then
  insert into public.trip_participation(person_id,trip_id,status)
  values(p_person_id,p_trip_id,'pending')
  on conflict(person_id,trip_id) do update
  set status=case when trip_participation.status='cancelled' then 'pending'
                  else trip_participation.status end;
 else
  -- Historiken bevaras; tidigare genomförda resor kan inte avmarkeras här.
  if exists(select 1 from public.trips where id=p_trip_id and trip_status='completed') then
   raise exception 'Completed trips cannot be edited here';
  end if;
  delete from public.trip_participation where person_id=p_person_id and trip_id=p_trip_id;
 end if;
end $$;
revoke all on function public.ldv_admin_set_participation(uuid,bigint,boolean) from public;
grant execute on function public.ldv_admin_set_participation(uuid,bigint,boolean) to authenticated;
