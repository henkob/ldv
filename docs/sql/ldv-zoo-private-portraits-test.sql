-- Apply only to wtrrdxurgxyvfahhgbsh.
create table if not exists public.ldv_zoo_portraits (
  person_id uuid primary key references public.people(id),
  photo_path text not null unique,
  portrait_key uuid not null
);
alter table public.ldv_zoo_portraits enable row level security;
revoke all on public.ldv_zoo_portraits from anon, authenticated;

create or replace function public.ldv_zoo_register_portrait(
  p_slot uuid, p_photo_path text, p_portrait_key uuid, p_first_name text, p_nickname text
) returns void
language plpgsql security definer set search_path to ''
as $$
begin
  if auth.uid() is null or not public.ldv_is_admin() then
    raise exception 'Admin required' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(8272027);
  if exists(select from public.ldv_zoo_rounds where trip_id=2) then
    raise exception 'Rounds already prepared';
  end if;
  if p_photo_path !~ '^zoo/[0-9a-f-]{36}$' or nullif(btrim(p_first_name),'') is null
    or not exists(select from storage.objects where bucket_id='ldv-avatars' and name=p_photo_path) then
    raise exception 'Portrait and name required';
  end if;
  update public.people set first_name=p_first_name, nickname=nullif(btrim(p_nickname),'')
  where id=p_slot and email ~ '^ldv-zoo-test-[0-9]{3}@example[.]invalid$';
  if not found then raise exception 'Invalid test slot'; end if;
  insert into public.ldv_zoo_portraits values(p_slot,p_photo_path,p_portrait_key)
  on conflict(person_id) do update set
    photo_path=excluded.photo_path, portrait_key=excluded.portrait_key;
end $$;
revoke all on function public.ldv_zoo_register_portrait(uuid,text,uuid,text,text) from public,anon;
grant execute on function public.ldv_zoo_register_portrait(uuid,text,uuid,text,text) to authenticated;

create or replace function public.ldv_zoo_can_read_portrait(p_path text)
returns boolean language sql stable security definer set search_path to ''
as $$
  select auth.uid() is not null and public.ldv_is_participant() and exists (
    select from public.ldv_zoo_portraits p
    join public.ldv_zoo_questions q using (person_id)
    join public.ldv_zoo_rounds r on r.id=q.round_id
    join public.trips t on t.id=r.trip_id and t.is_current
    join public.trip_participation tp on tp.trip_id=t.id
    where p.photo_path=p_path and r.unlock_at<=now()
      and tp.person_id=public.ldv_my_person_id() and tp.status='confirmed'
  )
$$;
revoke all on function public.ldv_zoo_can_read_portrait(text) from public,anon;
grant execute on function public.ldv_zoo_can_read_portrait(text) to authenticated;

drop policy if exists ldv_zoo_read_portrait on storage.objects;
create policy ldv_zoo_read_portrait on storage.objects for select to authenticated
using (bucket_id='ldv-avatars' and name like 'zoo/%' and public.ldv_zoo_can_read_portrait(name));
