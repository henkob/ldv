import assert from 'node:assert/strict';
import {normalizeGuess,prepareQuizPool,previewRounds,describePool,ROUND_COUNT,QUESTIONS_PER_ROUND,ROUND_DAYS} from './zoo-rounds.mjs';

const makePeople = n => Array.from({length:n},(_,i)=>({
 id: 'synthetic-'+String(i+1).padStart(3,'0'),
 first_name: 'Testnamn'+(i+1),
 photoUrl: 'https://example.invalid/portrait/'+(i+1)
}));
const tests = [];
function test(name,run){run();tests.push(name);}

test('normalizes case, Swedish accents and spaces',()=>{
 assert.equal(normalizeGuess('  ÉMIL   '),'emil');
 assert.equal(normalizeGuess(' ÅSA '),'asa');
 assert.equal(normalizeGuess('  ANNA  MARIA '),'anna maria');
 assert.equal(normalizeGuess(null),'');
});
test('excludes missing photos, names, ids and duplicate ids',()=>{
 const people=makePeople(3);
 const eligible=prepareQuizPool([...people,{...people[0]},{id:'no-photo',first_name:'No'}, {id:'no-name',photoUrl:'url'}]);
 assert.equal(eligible.length,3);
 assert.throws(()=>prepareQuizPool(null),TypeError);
});
test('does not start without any photos',()=>assert.deepEqual(previewRounds([]),[]));
test('shows pool as not ready when fewer than 14 portraits exist',()=>{
 assert.equal(describePool(makePeople(13)).ready,false);
 assert.equal(describePool(makePeople(14)).ready,true);
});
for(const count of [14,15,20,30,70,84,86,103]){
 test('produces six 14-face rounds with '+count+' eligible people',()=>{
  const people=makePeople(count);
  const rounds=previewRounds(people,{seed:2027});
  assert.equal(rounds.length,ROUND_COUNT);
  assert.deepEqual(rounds.map(r=>r.day),ROUND_DAYS);
  const ids=[];
  for(const [i,r] of rounds.entries()){
   assert.equal(r.dayIndex,i);
   assert.equal(r.questions.length,QUESTIONS_PER_ROUND);
   assert.equal(new Set(r.questions.map(q=>q.personId)).size,QUESTIONS_PER_ROUND,'no duplicates within a day');
   ids.push(...r.questions.map(q=>q.personId));
  }
  assert.equal(new Set(ids).size,Math.min(count,84),'maximize unique participants');
  assert.deepEqual(previewRounds(people,{seed:2027}),rounds,'deterministic round assignment');
 });
}
console.log('PASS: '+tests.length+' tests\n'+tests.map(t=>'✓ '+t).join('\n'));
