-- Test only: creates rounds only after 84 synthetic full-size portraits exist.
-- No execution until Saturday trip dates and browser image uploads are verified.
CREATE OR REPLACE FUNCTION public.ldv_zoo_prepare_test_rounds(p_first_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count int; v_round bigint; v_i int; v_inserted int:=0;
begin
 if auth.uid() is null or not public.ldv_is_admin() then raise exception 'Admin required' using errcode='42501'; end if;
 if current_setting('app.settings.project_ref',true) is distinct from 'wtrrdxurgxyvfahhgbsh' then
   -- Environment safety is checked by test-only synthetic data too, since project_ref may not be configured.
   if not exists(select 1 from public.people where email='ldv-zoo-test-001@example.invalid') then
     raise exception 'Test dataset missing; refusing to prepare quiz';
   end if;
 end if;
 if extract(isodow from p_first_day)<>6 then raise exception 'First quiz day must be Saturday'; end if;
 if exists(select 1 from public.ldv_zoo_rounds where trip_id=2) then raise exception 'Rounds already prepared'; end if;
 select count(*) into v_count from public.people p
 join public.trip_participation tp on tp.person_id=p.id and tp.trip_id=2 and tp.status='confirmed'
 where p.email ~ '^ldv-zoo-test-[0-9]{3}@example[.]invalid$'
 and exists(select 1 from storage.objects o where o.bucket_id='ldv-avatars' and o.name=p.id::text||'/avatar-full');
 if v_count<>84 then raise exception 'Expected 84 uploaded synthetic full-size portraits, found %',v_count; end if;
 for v_i in 0..5 loop
  insert into public.ldv_zoo_rounds(trip_id,round_index,unlock_at)
  values(2,v_i,(p_first_day+v_i)::timestamp at time zone 'Europe/Stockholm')
  returning id into v_round;
  insert into public.ldv_zoo_questions(round_id,position,person_id)
  select v_round,row_number() over(order by p.email)::smallint - (v_i*14),p.id
  from public.people p join public.trip_participation tp on tp.person_id=p.id and tp.trip_id=2 and tp.status='confirmed'
  where p.email ~ '^ldv-zoo-test-[0-9]{3}@example[.]invalid$'
  order by p.email offset (v_i*14) limit 14;
  get diagnostics v_inserted=row_count;
  if v_inserted<>14 then raise exception 'Expected 14 questions, got %',v_inserted; end if;
 end loop;
 return jsonb_build_object('rounds',6,'questions',84,'firstDay',p_first_day);
end $function$

revoke all on function public.ldv_zoo_prepare_test_rounds(date) from public,anon;
grant execute on function public.ldv_zoo_prepare_test_rounds(date) to authenticated;
