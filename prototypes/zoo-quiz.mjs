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
  const dialog = get('dialog');
  const interaction = get('interaction');
  const nameDisplay = get('name');
  const resultDisplay = get('result');
  const progress = get('progress');
  const adminControls = get('admin-controls');
  const adminMode = get('admin-mode');
  const leaderboard = get('leaderboard');
  const dailyResults = get('daily-results');
  const date = new Intl.DateTimeFormat('sv-SE', {dateStyle:'medium', timeZone:'Europe/Stockholm'});
  let portraitPreview = false;
  let game, roundIndex, question, outcome, name, letters, photoUrl, previewIndex, dialogRound, finalTestQuestion, generation = 0;
  let submitting = false;
  const viewport = window.visualViewport;
  let openViewportHeight = 0;

  function fitKeyboard() {
    // iOS can pan the visual viewport while the layout viewport keeps its height.
    const keyboard = dialog.open && document.activeElement === guess && viewport
      && viewport.scale === 1 && Math.max(openViewportHeight, window.innerHeight) - viewport.height > 100;
    dialog.toggleAttribute('data-keyboard', Boolean(keyboard));
    if (keyboard) {
      dialog.style.setProperty('--zoo-keyboard-top', Math.round(viewport.offsetTop + 8) + 'px');
      dialog.style.setProperty('--zoo-keyboard-height', Math.floor(viewport.height - 16) + 'px');
    }
  }

  viewport?.addEventListener('resize', fitKeyboard);
  viewport?.addEventListener('scroll', fitKeyboard);
  guess.addEventListener('focus', fitKeyboard);
  guess.addEventListener('blur', () => dialog.removeAttribute('data-keyboard'));

  async function load(index, previewPosition = 0) {
    const current = ++generation;
    roundIndex = index;
    previewIndex = previewPosition;
    outcome = null;
    question = null;
    finalTestQuestion = false;
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
    adminMode.textContent = portraitPreview ? 'Tillbaka till testspelet' : 'Förhandsvisa porträtt';
    leaderboard.hidden = true;
    if (error) {
      status.textContent = 'Quizet kunde inte laddas.';
      loadButton.hidden = false;
      return;
    }
    game = data;
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
      button.dataset.zooRound = round.roundIndex;
      button.addEventListener('click', () => {
        if (game.testWeekId) {
          dialogRound = round.roundIndex;
          get('dialog-title').textContent = 'Omgång ' + (dialogRound + 1);
          dialog.append(interaction);
          openViewportHeight = viewport?.height ?? 0;
          dialog.showModal();
        }
        return load(round.roundIndex);
      });
      rounds.append(button);
    }
    status.textContent = game.testWeekId && game.finished ? 'Testspelet är avslutat.' :
      (game.rounds.length ? '' : 'Omgångarna är inte klara ännu.');
    leaderboard.hidden = !game.finished;
    dailyResults.replaceChildren();
    if (game.finished) {
      for (const round of game.rounds) {
        const correct = round.questions.filter(question => question.correct).length;
        const total = round.questions.length;
        const item = document.createElement('li');
        const label = document.createElement('span');
        label.textContent = 'Dag ' + (round.roundIndex + 1);
        const bar = document.createElement('span');
        bar.className = 'zoo-bar';
        bar.setAttribute('aria-hidden', 'true');
        const fill = document.createElement('span');
        fill.style.width = (total ? correct / total * 100 : 0) + '%';
        bar.append(fill);
        const value = document.createElement('strong');
        value.textContent = correct + ' av ' + total;
        item.append(label, bar, value);
        dailyResults.append(item);
      }
    }
    const scores = get('scores');
    scores.replaceChildren();
    for (const entry of game.leaderboard ?? []) {
      const item = document.createElement('li');
      item.textContent = entry.name + ' · ' + entry.points + ' poäng';
      scores.append(item);
    }

    const round = game.rounds.find(r => r.roundIndex === index && r.isUnlocked);
    if (!round) {
      if (dialog.open && !game.finished) status.textContent = 'Omgången är inte tillgänglig.';
      return;
    }
    question = game.preview ? round.questions[previewIndex] : round.questions.find(q => !q.answered);
    if (!question || game.finished) {
      status.textContent = game.finished ? 'Tävlingen är avslutad.' : (game.preview ? 'Alla bilder i omgången har visats.' : 'Alla frågor i omgången är besvarade.');
      return;
    }

    finalTestQuestion = Boolean(game.testWeekId) && game.rounds.every(round =>
      round.questions.every(entry => entry.answered || entry.questionId === question.questionId));
    status.textContent = 'Laddar porträttet …';
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
    status.textContent = '';
    resultDisplay.textContent = '';
    nameDisplay.textContent = '';
    progress.textContent = 'Fråga ' + (round.questions.indexOf(question) + 1) + ' av ' + round.questions.length;
    form.hidden = game.preview;
    reveal.hidden = true;
    next.hidden = !game.preview;
    next.textContent = game.preview ? 'Nästa porträtt' : (finalTestQuestion ? 'Visa resultat' : 'Fortsätt');
    play.hidden = false;
    if (dialog.open) {
      progress.focus({preventScroll:true});
      dialog.scrollTop = 0;
    }
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
    if (!game || !question || game.preview || form.hidden || submitting || !guess.value.trim()) return;
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
      loadButton.hidden = true;
      outcome = data;
      const firstName = data.first_name.trim().normalize('NFC');
      name = firstName.match(/\P{L}*\p{L}\p{M}*\P{L}*/gu) ?? [firstName];
      letters = 0;
      form.hidden = true;
      reveal.textContent = name.length === 1 ? 'Visa facit' : 'Visa första bokstaven';
      reveal.hidden = false;
      reveal.focus();
    } finally {
      submitting = false;
      get('submit').disabled = false;
    }
  });

  reveal.addEventListener('click', () => {
    if (!outcome) return;
    nameDisplay.textContent = name.slice(0, ++letters).join('');
    if (letters < name.length) {
      reveal.textContent = letters === name.length - 1 ? 'Visa sista bokstaven' : 'Visa nästa bokstav';
      return;
    }
    const {correct,total_points:totalPoints} = outcome;
    outcome = null;
    resultDisplay.textContent = correct ? 'Rätt! +1 poäng' : 'Fel svar. 0 poäng';
    get('score').textContent = (game.testWeekId ? 'Dina testpoäng: ' : 'Din poäng: ') + totalPoints;
    animateResult(correct);
    reveal.hidden = true;
    next.hidden = false;
    next.focus();
  });
  next.addEventListener('click', () => {
    if (finalTestQuestion && dialog.open) {
      dialog.close();
      return;
    }
    return load(roundIndex, game.preview ? previewIndex + 1 : 0);
  });
  loadButton.addEventListener('click', () => load(roundIndex, previewIndex));
  get('dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', async () => {
    const closedRound = dialogRound;
    dialog.removeAttribute('data-keyboard');
    play.hidden = true;
    get('inline').append(interaction);
    await load();
    if (dialog.open) return;
    if (!leaderboard.hidden) {
      get('results-title').focus();
    } else {
      rounds.querySelector('[data-zoo-round="' + closedRound + '"]')?.focus();
    }
  });
  adminMode.addEventListener('click', () => {
    portraitPreview = !portraitPreview;
    load();
  });
  return () => load();
}
