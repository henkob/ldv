-- LDV 005: resehistorik per person, endast för administratörer.
-- Historik avser tidigare år, aldrig den aktuella eller framtida resan.
create or replace function public.ldv_admin_person_history(p_person_id uuid)
returns table(trip_id bigint,year integer,destination text,participated boolean)
language plpgsql stable security definer set search_path=''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.people p where p.id=p_person_id) then raise exception 'Unknown person'; end if;
 return query select t.id,t.year,t.destination,
 exists(select 1 from public.trip_participation tp where tp.trip_id=t.id and tp.person_id=p_person_id and tp.status <> 'cancelled')
 from public.trips t where t.year < extract(year from current_date)::integer
 order by t.year desc;
end $$;
revoke all on function public.ldv_admin_person_history(uuid) from public;
grant execute on function public.ldv_admin_person_history(uuid) to authenticated;

create or replace function public.ldv_admin_set_person_history(p_person_id uuid,p_trip_id bigint,p_participated boolean)
returns void language plpgsql security definer set search_path=''
as $$
declare v_year integer;
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.people p where p.id=p_person_id) then raise exception 'Unknown person'; end if;
 select t.year into v_year from public.trips t where t.id=p_trip_id;
 if v_year is null or v_year >= extract(year from current_date)::integer then raise exception 'Only previous trips can be edited'; end if;
 if p_participated then
  insert into public.trip_participation(person_id,trip_id,status)
  values(p_person_id,p_trip_id,'confirmed')
  on conflict(person_id,trip_id) do update set status='confirmed';
 else
  delete from public.trip_participation where person_id=p_person_id and trip_id=p_trip_id;
 end if;
end $$;
revoke all on function public.ldv_admin_set_person_history(uuid,bigint,boolean) from public;
grant execute on function public.ldv_admin_set_person_history(uuid,bigint,boolean) to authenticated;
