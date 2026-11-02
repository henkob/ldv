-- LDV 006: antal tidigare resor per person, endast administratörer.
create or replace function public.ldv_admin_trip_counts(p_trip_id bigint)
returns table(person_id uuid,previous_trips bigint)
language plpgsql stable security definer set search_path=''
as $$
declare v_year integer;
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 select t.year into v_year from public.trips t where t.id=p_trip_id;
 if v_year is null then raise exception 'Unknown trip'; end if;
 return query select p.id,count(tp.trip_id)::bigint
 from public.people p
 left join public.trip_participation tp on tp.person_id=p.id and tp.status <> 'cancelled'
 left join public.trips t on t.id=tp.trip_id and t.year<v_year
 group by p.id;
end $$;
revoke all on function public.ldv_admin_trip_counts(bigint) from public;
grant execute on function public.ldv_admin_trip_counts(bigint) to authenticated;
