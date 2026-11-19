export function mountZooGame(client, root) {
  const get = name => root.querySelector('[data-zoo="' + name + '"]');
  const rounds = get('rounds');
  const play = get('play');
  const form = get('form');
  const portrait = get('portrait');
  const guess = get('guess');
  const reveal = get('reveal');
  const next = get('next');
  const status = get('status');
  const loadButton = get('reload');
  const adminControls = get('admin-controls');
  const adminMode = get('admin-mode');
  const schedule = get('schedule');
  const testStart = get('test-start');
  const scheduleStatus = get('schedule-status');
  const date = new Intl.DateTimeFormat('sv-SE', {dateStyle:'medium', timeZone:'Europe/Stockholm'});
  let portraitPreview = false;
  let game, roundIndex, question, name, letters, photoUrl, previewIndex, generation = 0;
  let submitting = false;

  async function load(index, previewPosition = 0) {
    const current = ++generation;
    play.hidden = true;
    if (photoUrl) URL.revokeObjectURL(photoUrl);
    photoUrl = undefined;
    status.textContent = 'Laddar quizet …';
    loadButton.hidden = true;
    const official = await client.rpc('ldv_zoo_my_rounds');
    if (current !== generation) return;
    const admin = official.data?.preview === true;
    const test = admin ? await client.rpc('ldv_zoo_test_week') : null;
    if (current !== generation) return;
    const {data, error} = admin && !portraitPreview ? test : official;
    adminControls.hidden = !admin || Boolean(test?.error);
    if (admin && !test.error) {
      const displayDay = day => date.format(new Date(day + 'T12:00:00Z'));
      get('test-dates').textContent = 'Testvecka ' + displayDay(test.data.startsOn) + ' till ' + displayDay(test.data.endsOn);
      adminMode.textContent = portraitPreview ? 'Tillbaka till testspelet' : 'Förhandsvisa porträtt';
      testStart.value = test.data.startsOn;
      testStart.min = test.data.earliestStart;
    }
    if (error) {
      status.textContent = 'Quizet kunde inte laddas.';
      loadButton.hidden = false;
      return;
    }
    game = data;
    roundIndex = index;
    previewIndex = previewPosition;
    if (!game.available) {
      rounds.replaceChildren();
      get('score').textContent = '';
      status.textContent = 'Quizet öppnar på avresedagen.';
      return;
    }
    get('score').textContent = game.preview ? 'Förhandsvisning för administratörer' :
      (game.testWeekId ? 'Dina testpoäng: ' : 'Din poäng: ') + game.totalPoints;
    rounds.replaceChildren();
    for (const round of game.rounds) {
      const button = document.createElement('button');
      const completed = round.questions.filter(q => q.answered).length;
      button.type = 'button';
      button.disabled = !round.isUnlocked || Boolean(game.testWeekId && game.finished);
      button.textContent = 'Omgång ' + (round.roundIndex + 1) +
        (round.isUnlocked ? (game.preview ? '' : ' · ' + completed + ' av ' + round.questions.length) : ' · öppnar ' + date.format(new Date(round.unlockAt)));
      button.addEventListener('click', () => load(round.roundIndex));
      rounds.append(button);
    }
    status.textContent = game.testWeekId && game.finished ? 'Testspelet är avslutat.' :
      (game.rounds.length ? '' : 'Omgångarna är inte klara ännu.');
    const leaderboard = get('leaderboard');
    leaderboard.hidden = !game.finished;
    const scores = get('scores');
    scores.replaceChildren();
    for (const entry of game.leaderboard ?? []) {
      const item = document.createElement('li');
      item.textContent = entry.name + ' · ' + entry.points + ' poäng';
      scores.append(item);
    }

    const round = game.rounds.find(r => r.roundIndex === index && r.isUnlocked);
    if (!round) return;
    question = game.preview ? round.questions[previewIndex] : round.questions.find(q => !q.answered);
    if (!question || game.finished) {
      status.textContent = game.finished ? 'Tävlingen är avslutad.' : (game.preview ? 'Alla bilder i omgången har visats.' : 'Alla frågor i omgången är besvarade.');
      return;
    }

    const {data: image, error: photoError} = await client.functions.invoke('ldv-zoo-portrait', {
      body: {questionId:question.questionId}
    });
    if (current !== generation) return;
    if (photoError || !(image instanceof Blob) || !image.size) {
      status.textContent = 'Porträttet kunde inte laddas.';
      loadButton.hidden = false;
      return;
    }
    const preload = new Image();
    photoUrl = URL.createObjectURL(new Blob([image], {type:'image/jpeg'}));
    preload.src = photoUrl;
    try {
      await preload.decode();
    } catch {
      if (current !== generation) return;
      status.textContent = 'Porträttet kunde inte visas.';
      loadButton.hidden = false;
      return;
    }
    if (current !== generation) return;
    portrait.src = preload.src;
    guess.value = '';
    get('result').textContent = '';
    get('name').textContent = '';
    get('progress').textContent = 'Fråga ' + (round.questions.findIndex(q => q === question) + 1) + ' av ' + round.questions.length;
    form.hidden = game.preview;
    reveal.hidden = true;
    next.hidden = !game.preview;
    next.textContent = game.preview ? 'Nästa porträtt' : 'Fortsätt';
    play.hidden = false;
  }

  function animateResult(correct) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    portrait.animate(correct
      ? [{transform:'scale(1)'},{transform:'scale(1.08)'},{transform:'scale(1)'}]
      : [{transform:'translateX(0)'},{transform:'translateX(-8px)'},{transform:'translateX(8px)'},{transform:'translateX(0)'}],
      {duration:400});
    if (!correct) return;
    for (let i = 0; i < 32; i++) {
      const piece = document.createElement('span');
      piece.className = 'zoo-confetti';
      piece.style.backgroundColor = ['#ffce47','#db4280','#317fb9','#43a36c'][i % 4];
      get('effects').append(piece);
      const angle = Math.random() * Math.PI * 2;
      const distance = 35 + Math.random() * 115;
      piece.animate([{transform:'translate(0,0)'},{
        transform:'translate(' + Math.cos(angle)*distance + 'px,' + Math.sin(angle)*distance + 'px) rotate(220deg)',
        opacity:0
      }], {duration:550 + Math.random()*350}).finished.then(() => piece.remove());
    }
  }

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (!game || !question || game.preview || submitting || !guess.value.trim()) return;
    submitting = true;
    get('submit').disabled = true;
    const current = generation;
    try {
      const params = {p_question_id:question.questionId, p_guess:guess.value.trim()};
      const {data, error} = game.testWeekId
        ? await client.rpc('ldv_zoo_submit_test_answer', {...params,p_week_id:game.testWeekId})
        : await client.rpc('ldv_zoo_submit_answer', params);
      if (current !== generation) return;
      if (error) {
        status.textContent = game.testWeekId && error.code === '22023'
          ? 'Testomgången är inte längre tillgänglig. Uppdatera quizet.'
          : 'Svaret kunde inte visas. Försök igen för att hämta det sparade resultatet.';
        loadButton.hidden = false;
        return;
      }
      status.textContent = '';
      name = [...data.first_name];
      letters = 0;
      form.hidden = true;
      reveal.textContent = 'Visa första bokstaven';
      reveal.hidden = false;
      reveal.focus();
      get('result').textContent = data.correct ? 'Rätt! +1 poäng' : 'Fel svar. 0 poäng';
      animateResult(data.correct);
      get('score').textContent = (game.testWeekId ? 'Dina testpoäng: ' : 'Din poäng: ') + data.total_points;
    } finally {
      submitting = false;
      get('submit').disabled = false;
    }
  });

  reveal.addEventListener('click', () => {
    get('name').textContent = name.slice(0, ++letters).join('');
    if (letters < name.length) {
      reveal.textContent = 'Visa nästa bokstav';
      return;
    }
    next.hidden = false;
    next.focus();
    reveal.hidden = true;
  });
  next.addEventListener('click', () => load(roundIndex, game.preview ? previewIndex + 1 : 0));
  loadButton.addEventListener('click', () => load(roundIndex, previewIndex));
  adminMode.addEventListener('click', () => {
    portraitPreview = !portraitPreview;
    load();
  });
  schedule.addEventListener('submit', async event => {
    event.preventDefault();
    const save = get('schedule-save');
    if (save.disabled) return;
    save.disabled = true;
    scheduleStatus.textContent = 'Sparar testveckan …';
    try {
      const {error} = await client.rpc('ldv_zoo_schedule_test_week', {p_starts_on:testStart.value});
      if (error) {
        scheduleStatus.textContent = 'Testveckan kunde inte sparas. Välj ett startdatum från idag till 23 januari.';
        return;
      }
      portraitPreview = false;
      await load();
      scheduleStatus.textContent = 'Testveckan är sparad.';
    } finally {
      save.disabled = false;
    }
  });
  return () => load();
}
