-- LDV admin dashboard helper functions.
-- Run in Supabase SQL Editor after 001_manual_app_lock.sql.
create or replace function public.ldv_is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists(select 1 from public.ldv_admins a where a.user_id=(select auth.uid()))
$$;
revoke all on function public.ldv_is_admin() from public;
grant execute on function public.ldv_is_admin() to authenticated;

create or replace function public.ldv_admin_trips()
returns table(id bigint,year integer,destination text)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if (select auth.uid()) is null or not public.ldv_is_admin() then
  raise exception 'Not authorized';
 end if;
 return query select t.id,t.year,t.destination from public.trips t order by t.year desc;
end
$$;
revoke all on function public.ldv_admin_trips() from public;
grant execute on function public.ldv_admin_trips() to authenticated;
