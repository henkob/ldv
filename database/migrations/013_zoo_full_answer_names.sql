-- Return name details only with a recorded guess, in either play mode.
create or replace function public.ldv_zoo_submit_test_answer(
  p_week_id bigint, p_question_id bigint, p_guess text
)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_week ldv_private.zoo_test_weeks%rowtype;
  v_first_name text;
  v_nickname text;
  v_last_name text;
  v_correct boolean;
  v_player uuid := auth.uid();
begin
  perform ldv_private.zoo_require_test_admin();
  if p_guess is null or length(btrim(p_guess)) not between 1 and 100 then
    raise exception 'Invalid answer' using errcode='22023';
  end if;

  select * into strict v_week from ldv_private.zoo_test_weeks order by id desc limit 1;
  if v_week.id is distinct from p_week_id then
    raise exception 'Test session changed' using errcode='22023';
  end if;

  select p.first_name,p.nickname,p.last_name into v_first_name,v_nickname,v_last_name
  from public.ldv_zoo_questions q
  join public.ldv_zoo_rounds r on r.id=q.round_id
  join public.trips t on t.id=r.trip_id and t.is_current and t.year=2027
  join public.people p on p.id=q.person_id
  where q.id=p_question_id;
  if not found then
    raise exception 'Test round not available' using errcode='22023';
  end if;

  insert into ldv_private.zoo_test_answers(week_id,question_id,admin_id,correct)
  values(v_week.id,p_question_id,v_player,ldv_private.zoo_guess_matches(p_guess,v_first_name,v_nickname))
  on conflict (week_id,admin_id,question_id) do nothing;

  select a.correct into strict v_correct from ldv_private.zoo_test_answers a
  where a.week_id=v_week.id and a.question_id=p_question_id and a.admin_id=v_player;

  return jsonb_build_object('correct',v_correct,'first_name',v_first_name,
    'nickname',v_nickname,'last_name',v_last_name,
    'total_points',(select count(*) from ldv_private.zoo_test_answers a
      where a.week_id=v_week.id and a.admin_id=v_player and a.correct));
end
$$;

create or replace function public.ldv_zoo_submit_answer(p_question_id bigint, p_guess text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_player uuid; v_person public.people%rowtype; v_round public.ldv_zoo_rounds%rowtype; v_correct boolean; v_saved public.ldv_zoo_answers%rowtype; v_cutoff timestamptz;
begin
 if not ldv_private.zoo_is_open() then raise exception 'Not an authorized participant' using errcode='42501'; end if;
 v_player:=public.ldv_my_person_id();
 if v_player is null or not public.ldv_is_participant() then
   raise exception 'Not an authorized participant' using errcode='42501';
 end if;
 if p_guess is null or length(btrim(p_guess)) not between 1 and 100 then raise exception 'Invalid answer'; end if;
 select p.* into v_person from public.ldv_zoo_questions q join public.people p on p.id=q.person_id where q.id=p_question_id;
 if not found then raise exception 'Question not found'; end if;
 select r.* into v_round from public.ldv_zoo_questions q join public.ldv_zoo_rounds r on r.id=q.round_id where q.id=p_question_id;
 v_cutoff := ldv_private.zoo_cutoff();
 if v_round.unlock_at is null or v_cutoff is null or now()<v_round.unlock_at or now()>=v_cutoff then raise exception 'Round not available'; end if;
 if not exists(select 1 from public.trip_participation tp join public.trips t on t.id=tp.trip_id where tp.person_id=v_player and tp.trip_id=v_round.trip_id and tp.status='confirmed' and t.is_current and t.year=2027) then raise exception 'Not a participant in this trip' using errcode='42501'; end if;
 v_correct := ldv_private.zoo_guess_matches(p_guess,v_person.first_name,v_person.nickname);
 insert into public.ldv_zoo_answers(question_id,player_id,guess,correct) values(p_question_id,v_player,btrim(p_guess),v_correct) on conflict(question_id,player_id) do nothing returning * into v_saved;
 if v_saved.id is null then select * into v_saved from public.ldv_zoo_answers where question_id=p_question_id and player_id=v_player; end if;
 return jsonb_build_object('question_id',v_saved.question_id,'correct',v_saved.correct,'points',case when v_saved.correct then 1 else 0 end,'first_name',v_person.first_name,
  'nickname',v_person.nickname,'last_name',v_person.last_name,'submitted_at',v_saved.submitted_at,
  'total_points',(select count(*) from public.ldv_zoo_answers a
    join public.ldv_zoo_questions q on q.id=a.question_id
    join public.ldv_zoo_rounds r on r.id=q.round_id
    where a.player_id=v_player and a.correct and r.trip_id=v_round.trip_id));
end $function$;
