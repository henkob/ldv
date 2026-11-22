begin;

create table if not exists public.ldv_profile_view_daily (
  trip_id bigint not null references public.trips(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete cascade,
  view_day date not null,
  views bigint not null check (views > 0),
  primary key (trip_id, person_id, view_day)
);
alter table public.ldv_profile_view_daily enable row level security;
revoke all on public.ldv_profile_view_daily from public, anon, authenticated;

create or replace function public.ldv_record_profile_view(p_person_id uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.ldv_profile_view_daily (trip_id, person_id, view_day, views)
  select distinct tp.trip_id, tp.person_id, (now() at time zone 'Europe/Stockholm')::date, 1
  from public.trip_participation tp
  join public.trips t on t.id = tp.trip_id
  where tp.person_id = p_person_id
    and tp.status = 'confirmed'
    and t.year = public.ldv_current_trip_year()
    and (select auth.uid()) is not null
    and (select public.ldv_is_participant()) is true
  on conflict (trip_id, person_id, view_day) do update
    set views = ldv_profile_view_daily.views + 1;
$$;

create or replace function public.ldv_admin_profile_views(p_trip_id bigint)
returns table (person_id uuid, profile_name text, view_day date, views bigint)
language sql stable security definer set search_path = '' as $$
  select p.id, trim(concat_ws(' ', p.first_name, p.last_name)), v.view_day, coalesce(v.views, 0)
  from public.people p
  left join public.ldv_profile_view_daily v on v.person_id = p.id and v.trip_id = p_trip_id
  where (select auth.uid()) is not null and (select public.ldv_is_admin()) is true
    and (v.person_id is not null or exists (
      select 1 from public.trip_participation tp
      where tp.trip_id = p_trip_id and tp.person_id = p.id and tp.status = 'confirmed'
    ))
  order by v.view_day nulls first, p.id;
$$;

revoke all on function public.ldv_record_profile_view(uuid) from public, anon;
grant execute on function public.ldv_record_profile_view(uuid) to authenticated;
revoke all on function public.ldv_admin_profile_views(bigint) from public, anon;
grant execute on function public.ldv_admin_profile_views(bigint) to authenticated;

commit;
