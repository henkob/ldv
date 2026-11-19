export function mountZooGame(client, root) {
  const get = name => root.querySelector('[data-zoo="' + name + '"]');
  const rounds = get('rounds');
  const play = get('play');
  const form = get('form');
  const submit = get('submit');
  const portrait = get('portrait');
  const rookieBadge = get('rookie-badge');
  const guess = get('guess');
  const hint = get('hint');
  const hintText = get('hint-text');
  const hintDisclosure = get('hint-disclosure');
  const reveal = get('reveal');
  const next = get('next');
  const revealLabel = get('reveal-label');
  const nextLabel = get('next-label');
  const status = get('status');
  const loadButton = get('reload');
  const dialog = get('dialog');
  const dialogTitle = get('dialog-title');
  const dialogProgress = get('dialog-progress');
  const interaction = get('interaction');
  const nameDisplay = get('name');
  const resultDisplay = get('result');
  const feedback = get('feedback');
  const progress = get('progress');
  const adminControls = get('admin-controls');
  const adminMode = get('admin-mode');
  const leaderboard = get('leaderboard');
  const dailyResults = get('daily-results');
  const date = new Intl.DateTimeFormat('sv-SE', {dateStyle:'medium', timeZone:'Europe/Stockholm'});
  const weekday = new Intl.DateTimeFormat('sv-SE', {weekday:'long', timeZone:'Europe/Stockholm'});
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

  function setHintExpanded(expanded) {
    hint.setAttribute('aria-expanded', String(expanded));
    hint.setAttribute('aria-label', expanded ? 'Dölj ledtråd' : 'Visa ledtråd');
    hintDisclosure.toggleAttribute('data-open', expanded);
  }

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
          const scheduled = official.data?.rounds?.find(item => item.roundIndex === dialogRound);
          const day = scheduled?.unlockAt ? weekday.format(new Date(scheduled.unlockAt)) : '';
          dialogTitle.textContent = day ? day[0].toLocaleUpperCase('sv-SE') + day.slice(1) + 'ens bilder'
            : 'Omgång ' + (dialogRound + 1);
          dialogProgress.textContent = '';
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
    rookieBadge.hidden = question.rookie !== true;
    guess.value = '';
    hint.disabled = false;
    setHintExpanded(false);
    hintText.textContent = '';
    status.textContent = '';
    resultDisplay.textContent = '';
    nameDisplay.textContent = '';
    progress.textContent = (round.questions.indexOf(question) + 1) + '/' + round.questions.length;
    dialogProgress.textContent = progress.textContent;
    form.hidden = Boolean(game.preview);
    submit.hidden = form.hidden;
    feedback.hidden = !game.preview;
    reveal.hidden = true;
    next.hidden = !game.preview;
    nextLabel.textContent = game.preview ? 'Nästa porträtt' : (finalTestQuestion ? 'Visa resultat' : 'Fortsätt');
    play.hidden = false;
    if (dialog.open) {
      dialogTitle.focus({preventScroll:true});
      dialog.scrollTop = 0;
    }
  }

  function animateResult(correct) {
    if (!correct || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    portrait.animate(
      [{transform:'scale(1)'},{transform:'scale(1.025)'},{transform:'scale(1)'}],
      {duration:450,easing:'ease-in-out'}
    );
    for (let i = 0; i < 16; i++) {
      const piece = document.createElement('span');
      piece.className = 'zoo-confetti';
      piece.style.backgroundColor = ['#ffce47','#db4280','#317fb9','#43a36c'][i % 4];
      get('effects').append(piece);
      const angle = Math.random() * Math.PI * 2;
      const distance = 24 + Math.random() * 70;
      piece.animate([{transform:'translate(0,0)',opacity:.8},{
        transform:'translate(' + Math.cos(angle)*distance + 'px,' + Math.sin(angle)*distance + 'px) rotate(120deg)',
        opacity:0
      }], {duration:600 + Math.random()*240,easing:'ease-out'}).finished.then(() => piece.remove());
    }
  }

  hint.addEventListener('click', async () => {
    if (!question || form.hidden || hint.disabled || submitting) return;
    if (hintText.textContent) {
      setHintExpanded(hint.getAttribute('aria-expanded') !== 'true');
      return;
    }
    const current = generation;
    hint.disabled = true;
    const {data, error} = await client.rpc('ldv_zoo_first_letter_hint', {
      p_question_id:question.questionId
    });
    if (current !== generation || form.hidden) return;
    hint.disabled = false;
    if (error || !data) {
      status.textContent = 'Ledtråden kunde inte visas. Försök igen.';
      return;
    }
    status.textContent = '';
    setHintExpanded(true);
    hintText.textContent = 'Förnamnet börjar på ' + data + '.';
  });

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (!game || !question || game.preview || form.hidden || submitting || !guess.value.trim()) return;
    submitting = true;
    submit.disabled = true;
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
      submit.hidden = true;
      feedback.hidden = false;
      revealLabel.textContent = name.length === 1 ? 'Visa facit' : 'Visa första bokstaven';
      reveal.hidden = false;
      reveal.focus({preventScroll:true});
    } finally {
      submitting = false;
      submit.disabled = false;
    }
  });

  reveal.addEventListener('click', () => {
    if (!outcome) return;
    const piece = document.createElement('span');
    piece.className = 'zoo-letter';
    piece.textContent = name[letters++];
    if (letters < name.length) {
      nameDisplay.append(piece);
      revealLabel.textContent = letters === name.length - 1 ? 'Visa sista bokstaven' : 'Visa nästa bokstav';
      return;
    }
    const {correct, nickname, last_name:lastName, total_points:totalPoints} = outcome;
    const alias = nickname?.trim();
    piece.textContent = [piece.textContent, alias ? '”' + alias + '”' : '', lastName?.trim()]
      .filter(Boolean).join(' ');
    nameDisplay.append(piece);
    outcome = null;
    resultDisplay.textContent = correct ? 'Poäng! ' : '';
    if (!correct) {
      const description = document.createElement('span');
      description.className = 'ldv-visually-hidden';
      description.textContent = 'Fel svar.';
      resultDisplay.append(description);
    }
    const symbol = document.createElement('span');
    symbol.setAttribute('aria-hidden', 'true');
    symbol.textContent = correct ? '✅' : '❌';
    resultDisplay.append(symbol);
    get('score').textContent = (game.testWeekId ? 'Dina testpoäng: ' : 'Din poäng: ') + totalPoints;
    animateResult(correct);
    reveal.hidden = true;
    next.hidden = false;
    next.focus({preventScroll:true});
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
