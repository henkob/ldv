-- Applied to LDV test only. Review before any production migration.
create extension if not exists fuzzystrmatch with schema extensions;

create or replace function public.ldv_zoo_normalize(p_guess text)
returns text language sql immutable strict set search_path to ''
as $$
  select regexp_replace(
    regexp_replace(lower(normalize(p_guess, NFKD)), U&'[\0300-\036F]', '', 'g'),
    '[[:space:]‐‑-]+', '', 'g')
$$;

CREATE OR REPLACE FUNCTION public.ldv_zoo_submit_answer(p_question_id bigint, p_guess text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_player uuid; v_person public.people%rowtype; v_round public.ldv_zoo_rounds%rowtype; v_correct boolean; v_saved public.ldv_zoo_answers%rowtype; v_cutoff timestamptz; v_guess text;
begin
 if auth.uid() is null or not public.ldv_is_participant() then raise exception 'Not an authorized participant' using errcode='42501'; end if;
 v_player:=public.ldv_my_person_id();
 if v_player is null then raise exception 'Participant profile missing' using errcode='42501'; end if;
 if p_guess is null or length(btrim(p_guess)) not between 1 and 100 then raise exception 'Invalid answer'; end if;
 select p.* into v_person from public.ldv_zoo_questions q join public.people p on p.id=q.person_id where q.id=p_question_id;
 if not found then raise exception 'Question not found'; end if;
 select r.* into v_round from public.ldv_zoo_questions q join public.ldv_zoo_rounds r on r.id=q.round_id where q.id=p_question_id;
 select ((max(unlock_at) at time zone 'Europe/Stockholm')+interval '1 day') at time zone 'Europe/Stockholm' into v_cutoff from public.ldv_zoo_rounds where trip_id=v_round.trip_id;
 if v_round.unlock_at is null or v_cutoff is null or now()<v_round.unlock_at or now()>=v_cutoff then raise exception 'Round not available'; end if;
 if not exists(select 1 from public.trip_participation tp join public.trips t on t.id=tp.trip_id where tp.person_id=v_player and tp.trip_id=v_round.trip_id and tp.status='confirmed' and t.is_current=true) then raise exception 'Not a participant in this trip' using errcode='42501'; end if;
 v_guess:=public.ldv_zoo_normalize(p_guess);
 select exists (
   select from (values (public.ldv_zoo_normalize(v_person.first_name)),
                       (public.ldv_zoo_normalize(v_person.nickname))) aliases(name)
   where name<>'' and (name=v_guess or (
     length(name) between 5 and 100 and abs(length(name)-length(v_guess))<=1
     and extensions.levenshtein_less_equal(left(name,100),left(v_guess,100),1)<=1))
 ) into v_correct;
 insert into public.ldv_zoo_answers(question_id,player_id,guess,correct) values(p_question_id,v_player,btrim(p_guess),v_correct) on conflict(question_id,player_id) do nothing returning * into v_saved;
 if v_saved.id is null then select * into v_saved from public.ldv_zoo_answers where question_id=p_question_id and player_id=v_player; end if;
 return jsonb_build_object('question_id',v_saved.question_id,'correct',v_saved.correct,'points',case when v_saved.correct then 1 else 0 end,'first_name',v_person.first_name,'submitted_at',v_saved.submitted_at,
  'total_points',(select count(*) from public.ldv_zoo_answers a
    join public.ldv_zoo_questions q on q.id=a.question_id
    join public.ldv_zoo_rounds r on r.id=q.round_id
    where a.player_id=v_player and a.correct and r.trip_id=v_round.trip_id));
end $function$;

revoke all on function public.ldv_zoo_submit_answer(bigint,text) from public,anon;
grant execute on function public.ldv_zoo_submit_answer(bigint,text) to authenticated;
