-- LDV 008: permanent borttagning av person, enbart administratör.
-- Tar bort personens deltaganden, rumsplaceringar och historik.
-- Alla åtgärder sker i samma transaktion. Anropet misslyckas om andra referenser blockerar.
create or replace function public.ldv_admin_delete_person(p_person_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.ldv_is_admin() then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.people p where p.id=p_person_id) then raise exception 'Person not found'; end if;
 -- Ta bort referenser från andras rumskamratfält.
 update public.room_assignments r set roommate_person_id=null,updated_at=now()
 where r.roommate_person_id=p_person_id;
 delete from public.room_assignments r where r.person_id=p_person_id;
 delete from public.trip_participation tp where tp.person_id=p_person_id;
 delete from public.people p where p.id=p_person_id;
end $$;
revoke all on function public.ldv_admin_delete_person(uuid) from public;
grant execute on function public.ldv_admin_delete_person(uuid) to authenticated;
