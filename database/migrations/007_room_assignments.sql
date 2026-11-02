-- LDV 007: Privat rumsfördelning, endast reseledningen.
alter table public.room_assignments add column if not exists room_label text;
revoke all on public.room_assignments from anon, authenticated;
alter table public.room_assignments enable row level security;

create or replace function public.ldv_admin_rooms(p_trip_id bigint)
returns table(person_id uuid,roommate_person_id uuid,room_label text)
language plpgsql stable security definer set search_path=''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 return query select r.person_id,r.roommate_person_id,r.room_label
 from public.room_assignments r where r.trip_id=p_trip_id;
end $$;
revoke all on function public.ldv_admin_rooms(bigint) from public;
grant execute on function public.ldv_admin_rooms(bigint) to authenticated;

create or replace function public.ldv_admin_set_room(p_trip_id bigint,p_person_id uuid,p_roommate_id uuid,p_room_label text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_previous uuid;
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.trip_participation tp where tp.trip_id=p_trip_id and tp.person_id=p_person_id and tp.status <> 'cancelled') then
  raise exception 'Person is not on selected trip';
 end if;
 if p_roommate_id=p_person_id then raise exception 'Cannot share room with yourself'; end if;
 if p_roommate_id is not null and not exists(select 1 from public.trip_participation tp where tp.trip_id=p_trip_id and tp.person_id=p_roommate_id and tp.status <> 'cancelled') then
  raise exception 'Roommate is not on selected trip';
 end if;
 -- Ta bort gamla ömsesidiga kopplingar innan ny placering.
 select r.roommate_person_id into v_previous from public.room_assignments r where r.trip_id=p_trip_id and r.person_id=p_person_id;
 update public.room_assignments r set roommate_person_id=null,updated_at=now()
 where r.trip_id=p_trip_id and r.person_id=v_previous and r.roommate_person_id=p_person_id;
 if p_roommate_id is not null then
  -- En rumskamrat kan inte redan vara kopplad till en tredje person.
  if exists(select 1 from public.room_assignments r where r.trip_id=p_trip_id and r.person_id=p_roommate_id and r.roommate_person_id is not null and r.roommate_person_id<>p_person_id) then
   raise exception 'Roommate is already paired with another person';
  end if;
 end if;
 insert into public.room_assignments(trip_id,person_id,roommate_person_id,room_label)
 values(p_trip_id,p_person_id,p_roommate_id,nullif(btrim(p_room_label),''))
 on conflict(trip_id,person_id) do update
 set roommate_person_id=excluded.roommate_person_id,room_label=excluded.room_label,updated_at=now();
 if p_roommate_id is not null then
  insert into public.room_assignments(trip_id,person_id,roommate_person_id,room_label)
  values(p_trip_id,p_roommate_id,p_person_id,nullif(btrim(p_room_label),''))
  on conflict(trip_id,person_id) do update
  set roommate_person_id=excluded.roommate_person_id,room_label=excluded.room_label,updated_at=now();
 end if;
end $$;
revoke all on function public.ldv_admin_set_room(bigint,uuid,uuid,text) from public;
grant execute on function public.ldv_admin_set_room(bigint,uuid,uuid,text) to authenticated;
