-- LDV 004: säker redigering av personprofiler i admin.
create or replace function public.ldv_admin_person_profile(p_person_id uuid)
returns table(id uuid,first_name text,last_name text,nickname text,email text,phone text,who_is_who text,helmet_color text,jacket_color text,pants_color text,allergies text)
language plpgsql stable security definer set search_path=''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 return query select p.id,p.first_name,p.last_name,p.nickname,p.email,p.phone,p.who_is_who,p.helmet_color,p.jacket_color,p.pants_color,p.allergies
 from public.people p where p.id=p_person_id;
end $$;
revoke all on function public.ldv_admin_person_profile(uuid) from public;
grant execute on function public.ldv_admin_person_profile(uuid) to authenticated;
create or replace function public.ldv_admin_update_person(
 p_person_id uuid,p_first_name text,p_last_name text,p_nickname text,p_email text,p_phone text,
 p_who_is_who text,p_helmet_color text,p_jacket_color text,p_pants_color text,p_allergies text)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 if nullif(btrim(p_first_name),'') is null or nullif(btrim(p_last_name),'') is null then raise exception 'First and last name required'; end if;
 update public.people set
 first_name=btrim(p_first_name),last_name=btrim(p_last_name),nickname=nullif(btrim(p_nickname),''),
 email=nullif(btrim(p_email),''),phone=nullif(btrim(p_phone),''),who_is_who=nullif(btrim(p_who_is_who),''),
 helmet_color=nullif(btrim(p_helmet_color),''),jacket_color=nullif(btrim(p_jacket_color),''),
 pants_color=nullif(btrim(p_pants_color),''),allergies=nullif(btrim(p_allergies),'')
 where id=p_person_id;
 if not found then raise exception 'Person not found'; end if;
end $$;
revoke all on function public.ldv_admin_update_person(uuid,text,text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.ldv_admin_update_person(uuid,text,text,text,text,text,text,text,text,text,text) to authenticated;
