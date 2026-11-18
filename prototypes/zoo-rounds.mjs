/* Who is Who in the Zoo – client-side round preparation.
 * Input must be authorized trip participants with photo URLs resolved by the app.
 * Never use this module to validate answers or award points: server owns scoring.
 */
export const QUESTIONS_PER_ROUND = 14;
export const ROUND_COUNT = 6;
export const ROUND_DAYS = Object.freeze(['lördag','söndag','måndag','tisdag','onsdag','torsdag']);
export function normalizeGuess(value) {
  return String(value ?? '').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').trim().replace(/\s+/g,' ').toLocaleLowerCase('sv-SE');
}
export function hasPhoto(person) {
  return Boolean(person && person.id && person.photoUrl && typeof person.photoUrl === 'string');
}
export function prepareQuizPool(participants) {
  if (!Array.isArray(participants)) throw new TypeError('participants must be an array');
  const seen = new Set();
  return participants.filter(person => {
    if (!hasPhoto(person) || !person.first_name || seen.has(person.id)) return false;
    seen.add(person.id); return true;
  });
}
// Seeded, deterministic order so every participant receives the same round composition.
// The server must generate and persist official round assignments.
function random(seed) {
  let state = seed >>> 0;
  return () => {state += 0x6D2B79F5; let t=state;t=Math.imul(t^(t>>>15),t|1);t^=t+Math.imul(t^(t>>>7),t|61);return ((t^(t>>>14))>>>0)/4294967296;};
}
function shuffle(list, rng) {
  const copy=[...list];
  for(let i=copy.length-1;i>0;i--){const j=Math.floor(rng()*(i+1));[copy[i],copy[j]]=[copy[j],copy[i]];}
  return copy;
}
export function previewRounds(participants,{seed=2027}={}) {
  const pool=prepareQuizPool(participants);
  if(!pool.length) return [];
  const rng=random(seed),slots=QUESTIONS_PER_ROUND*ROUND_COUNT;
  const selected=shuffle(pool,rng).slice(0,slots);
  // Avoid a duplicate person within a round when at least 14 distinct photos exist.
  while(selected.length<slots){
    const roundStart=Math.floor(selected.length/QUESTIONS_PER_ROUND)*QUESTIONS_PER_ROUND;
    const inRound=new Set(selected.slice(roundStart).map(p=>p.id));
    const eligible=pool.filter(p=>!inRound.has(p.id));
    if(!eligible.length) break;
    selected.push(eligible[Math.floor(rng()*eligible.length)]);
  }
  return Array.from({length:ROUND_COUNT},(_,day)=>{
    const people=selected.slice(day*QUESTIONS_PER_ROUND,(day+1)*QUESTIONS_PER_ROUND);
    return {day:ROUND_DAYS[day],dayIndex:day,questions:people.map(p=>({personId:p.id,photoUrl:p.photoUrl}))};
  });
}
export function describePool(participants){
  const pool=prepareQuizPool(participants);
  return {eligible:pool.length,requiredDistinctForFullRounds:QUESTIONS_PER_ROUND,slots:QUESTIONS_PER_ROUND*ROUND_COUNT,ready:pool.length>=QUESTIONS_PER_ROUND};
}
