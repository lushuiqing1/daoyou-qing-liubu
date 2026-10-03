'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { create, act, hint, DATA, PRESETS, CARDS } = require('../engine.js');
const copy = s => JSON.parse(JSON.stringify(s));
function commit(s, a) {
  const r = act(s, a);
  assert.equal(r.ok, true, r.error);
  return r.state;
}
function boardFixture(s, row) {
  let id = s.seq + 1;
  s.board = Array.from({ length: 36 }, (_, i) => ({ id: id++, type: DATA.types[(Math.floor(i / 6) * 2 + i % 6) % 5] }));
  row.forEach((type, i) => { s.board[i].type = type; });
  s.board[8].type = row[0]; s.seq = id;
  return s;
}
function fourFixture(s = create()) { return boardFixture(s, ['red', 'red', 'blue', 'red', 'green', 'purple']); }
function purpleFixture(s = create({ preset: 'spirit' })) { return boardFixture(s, ['purple', 'purple', 'blue', 'green', 'yellow', 'red']); }
function boss(s) {
  s.wave = 5;
  s.enemy = { name: '山魈', hp: 231, maxHp: 231, attack: 22, damage: 22, shield: 0,
    type: 'boss', phase: 'calm', round: 1, intentKind: 'attack', intent: 22, intentShield: 0, nextDamage: 0 };
  return s;
}

test('initial role and board are deterministic, playable and independent', () => {
  const a = create({ seed: 630101 }), b = create({ seed: 630101 });
  assert.deepEqual(a, b); assert.notEqual(a, b);
  assert.equal(a.player.maxHp, 170); assert.equal(a.player.attack, 16); assert.equal(a.player.cardPower, 13);
  assert.equal(a.player.armor, 5); assert.equal(a.player.shield, 2); assert.equal(a.mana, 4);
  assert.equal(a.board.length, 36); assert.equal(new Set(a.board.map(t => t.id)).size, 36);
  assert.equal(act(a, { type: 'swap', a: hint(a)[0], b: hint(a)[1] }).ok, true);
  assert.deepEqual(create({ preset: 'guard' }).cards, ['ward', 'ironwall', 'golden']);
  assert.equal(Object.isFrozen(DATA.waves[0]), true);
});

test('invalid and unsuccessful actions preserve the entire transaction including RNG and statistics', () => {
  const s = create(), before = JSON.stringify(s);
  for (const a of [{ type: 'swap', a: 5, b: 6 }, { type: 'swap', a: 0.5, b: 1.5 }, { type: 'cast', cardId: 'flame' }, { type: 'cast', cardId: 'heal' }, { type: 'unknown' }]) {
    const r = act(s, a); assert.equal(r.ok, false); assert.equal(r.state, s); assert.deepEqual(r.events, []);
    assert.equal(JSON.stringify(s), before);
  }
  let missed = false;
  for (let a = 0; a < 30; a++) {
    const r = act(s, { type: 'swap', a, b: a + 6 });
    if (!r.ok) { assert.equal(r.state, s); assert.equal(JSON.stringify(s), before); missed = true; break; }
  }
  assert.equal(missed, true);
  const noSteps = copy(s); noSteps.steps = 0;
  assert.equal(act(noSteps, { type: 'swap', a: hint(noSteps)[0], b: hint(noSteps)[1] }).ok, false);
  const noMana = copy(s); noMana.mana = 0;
  assert.equal(act(noMana, { type: 'cast', cardId: 'sword' }).ok, false);
});

test('four-match refunds at most twice per player turn and refreshes one sword bonus', () => {
  let s = create();
  for (let n = 0; n < 3; n++) {
    s = fourFixture(s); s.enemy.hp = s.enemy.maxHp = 10000;
    const r = act(s, { type: 'swap', a: 2, b: 8 });
    assert.equal(r.ok, true);
    assert.equal(r.events.find(e => e.type === 'match').bonusStep, n < 2 ? 1 : 0);
    s = r.state;
    assert.equal(s.links.swordBoost, true);
  }
  assert.equal(s.stats.fourReturns, 2); assert.equal(s.bonusSteps, 2);
  s.mana = 7;
  const r = act(s, { type: 'cast', cardId: 'sword' });
  assert.equal(r.events.find(e => e.type === 'card').damage, 73);
  assert.equal(r.state.links.swordBoost, false); assert.equal(r.state.stats.links.sword, 1);
  s = commit(r.state, { type: 'endTurn' });
  assert.equal(s.bonusSteps, 0); assert.equal(s.steps, 4); assert.equal(s.links.swordBoost, false);
});

test('same-turn kills preserve resources, pending links and board, heal actual missing HP and do not grant extra attacks', () => {
  const s = create({ preset: 'spirit' });
  s.enemy.hp = 1; s.player.hp = 168; s.player.shield = 23; s.steps = 2; s.mana = 7; s.bonusSteps = 1;
  s.links.swordBoost = true; s.links.talismanRefund = true; s.links.spiritBonus = true;
  s.comboRemain = 2; s.comboAtk = 10;
  const r = act(s, { type: 'cast', cardId: 'flame' }), n = r.state;
  assert.equal(n.wave, 2); assert.equal(n.enemy.intentKind, 'charge'); assert.equal(n.enemy.round, 1);
  assert.deepEqual(n.board, s.board); assert.equal(n.player.hp, 170); assert.equal(n.player.shield, 23);
  assert.equal(n.mana, 6); assert.equal(n.steps, 2); assert.equal(n.bonusSteps, 1);
  assert.deepEqual(n.links, s.links); assert.equal(n.comboRemain, 2); assert.equal(n.round, 1);
  assert.equal(n.stats.damage, 1); assert.equal(n.stats.healed, 2); assert.equal(n.stats.hpLost, 0);
  assert.equal(r.events.some(e => e.type === 'enemy'), false);
  for (let wave = 2, state = n; wave <= 5; wave++) {
    state.enemy.hp = 1; state.mana = 7;
    state = commit(state, { type: 'cast', cardId: 'flame' });
    if (wave === 5) { assert.equal(state.status, 'won'); assert.equal(state.stats.enemiesDefeated, 5); }
  }
});

test('each bamboo enemy repeats two complete cycles with heavy immediately after charge', () => {
  for (let wave = 1; wave <= 5; wave++) {
    const spec = DATA.waves[wave - 1]; let s = create(); s.wave = wave;
    s.enemy = { name: spec.name, hp: spec.maxHp, maxHp: spec.maxHp, attack: spec.attack, damage: spec.attack,
      shield: 0, type: spec.type, phase: 'calm', round: 1, intentKind: spec.pattern[0],
      intent: spec.pattern[0] === 'attack' ? spec.attack : 0, intentShield: 0,
      nextDamage: spec.pattern[0] === 'charge' ? Math.round(spec.attack * 1.8) : 0 };
    const kinds = [];
    for (let n = 0; n < spec.pattern.length * 2; n++) {
      s.player.hp = 170; s.player.shield = 100;
      kinds.push(s.enemy.intentKind); s = commit(s, { type: 'endTurn' });
    }
    assert.deepEqual(kinds, [...spec.pattern, ...spec.pattern]);
  }
});

test('enrage preserves a announced charge damage and action position, while a later charge gets 2.2', () => {
  let s = boss(create()); s.enemy.hp = 170;
  s = commit(s, { type: 'endTurn' });
  assert.equal(s.enemy.intentKind, 'charge'); assert.equal(s.enemy.nextDamage, 40);
  s = commit(s, { type: 'cast', cardId: 'sword' });
  assert.equal(s.enemy.phase, 'enraged'); assert.equal(s.enemy.intentKind, 'charge'); assert.equal(s.enemy.nextDamage, 40);
  s = commit(s, { type: 'endTurn' });
  assert.equal(s.enemy.intentKind, 'heavy'); assert.equal(s.enemy.intent, 40);
  s.player.shield = 100;
  s = commit(s, { type: 'endTurn' }); assert.equal(s.enemy.intentKind, 'guard');
  s = commit(s, { type: 'endTurn' }); assert.equal(s.enemy.intentKind, 'attack');
  s = commit(s, { type: 'endTurn' }); assert.equal(s.enemy.intentKind, 'charge'); assert.equal(s.enemy.nextDamage, 48);
  let before = boss(create()); before.enemy.hp = 170;
  before = commit(before, { type: 'cast', cardId: 'sword' });
  before = commit(before, { type: 'endTurn' });
  assert.equal(before.enemy.nextDamage, 48);
  let heavy = boss(create()); heavy.enemy.hp = 170; heavy.enemy.round = 3; heavy.enemy.intentKind = 'heavy'; heavy.enemy.intent = 40;
  heavy = commit(heavy, { type: 'cast', cardId: 'sword' });
  assert.equal(heavy.enemy.intent, 40); assert.equal(heavy.enemy.round, 3);
});

test('spirit bonus refreshes instead of stacking, is consumed at cap, and disappears at end-turn', () => {
  let s = create({ preset: 'spirit' }); s.mana = 7;
  s = commit(s, { type: 'cast', cardId: 'spiritArray' });
  s = commit(s, { type: 'cast', cardId: 'spiritArray' });
  assert.equal(s.links.spiritBonus, true);
  s = purpleFixture(s); s.mana = 6; s.enemy.hp = s.enemy.maxHp = 10000;
  const r = act(s, { type: 'swap', a: 2, b: 8 });
  assert.equal(r.ok, true); assert.equal(r.state.mana, 7); assert.equal(r.state.links.spiritBonus, false);
  assert.equal(r.state.stats.links.purple, 1); assert.ok(r.state.stats.manaOverflow >= 3);
  const first = r.events.find(e => e.type === 'match'); assert.equal(first.counts.purple, 3); assert.equal(first.mana, 1);
  s = r.state; s.mana = 7; s = commit(s, { type: 'cast', cardId: 'spiritArray' });
  s = commit(s, { type: 'endTurn' }); assert.equal(s.links.spiritBonus, false);
});

test('talisman refund uses actual full shield break; natural expiry and a partial block do not trigger', () => {
  let s = create({ preset: 'guard' }); s = commit(s, { type: 'cast', cardId: 'ironwall' });
  s.enemy.intentKind = 'heavy'; s.enemy.intent = 40;
  const r = act(s, { type: 'endTurn' });
  assert.equal(r.state.stats.links.ward, 1); assert.equal(r.state.stats.blocked, 28); assert.equal(r.state.stats.hpLost, 7);
  assert.equal(r.state.mana, 5); assert.equal(r.state.links.talismanRefund, false);
  assert.equal(r.state.stats.shieldExpired, 0);
  let partial = create({ preset: 'guard' }); partial = commit(partial, { type: 'cast', cardId: 'ironwall' });
  partial = commit(partial, { type: 'endTurn' });
  assert.equal(partial.stats.links.ward, 0); assert.equal(partial.stats.shieldExpired, 19);
  let natural = create({ preset: 'guard' }); natural = commit(natural, { type: 'cast', cardId: 'ironwall' });
  natural.enemy.intent = 0; natural.enemy.intentKind = 'charge'; natural = commit(natural, { type: 'endTurn' });
  assert.equal(natural.stats.links.ward, 0); assert.equal(natural.stats.shieldExpired, 28);
  let exact = create({ preset: 'guard' }); exact = commit(exact, { type: 'cast', cardId: 'ironwall' });
  exact.enemy.intentKind = 'heavy'; exact.enemy.intent = 33;
  exact = commit(exact, { type: 'endTurn' });
  assert.equal(exact.stats.links.ward, 1); assert.equal(exact.stats.hpLost, 0);
});

test('stats record actual HP, healing and shield removal, exclude overkill and overflow healing, and capture a factual fatal snapshot', () => {
  const s = create(); s.enemy.hp = 10; s.enemy.shield = 20;
  let r = act(s, { type: 'cast', cardId: 'sword' });
  assert.equal(r.state.stats.damage, 10); assert.equal(r.state.stats.enemyShieldRemoved, 20);
  assert.equal(r.events.find(e => e.type === 'card').damage, 10);
  const injured = create(); injured.player.hp = 165;
  r = act(injured, { type: 'cast', cardId: 'heal' }); assert.equal(r.state.stats.healed, 5);
  const doomed = create(); doomed.player.hp = 3; doomed.player.shield = 0; doomed.enemy.intent = 99;
  r = act(doomed, { type: 'endTurn' });
  assert.equal(r.state.status, 'lost'); assert.equal(r.state.stats.hpLost, 3); assert.equal(r.state.player.hp, 0);
  assert.deepEqual(r.state.stats.fatal.defense, ['ward']); assert.deepEqual(r.state.stats.fatal.healing, ['heal']);
  assert.equal(act(r.state, { type: 'endTurn' }).state, r.state);
});

// A deterministic legal-operation bot. It never edits a session and its complete
// actions can be replayed from seed; used to demonstrate each offered deck wins.
function simulate(preset, seed) {
  let s = create({ preset, seed }); const actions = [];
  const execute = a => { s = commit(s, a); actions.push(a); };
  for (let count = 0; count < 1000 && s.status === 'playing'; count++) {
    const healCard = s.cards.find(id => (CARDS[id].heal || CARDS[id].healRatio) && s.mana >= CARDS[id].cost);
    if (s.player.hp < 95 && healCard) { execute({ type: 'cast', cardId: healCard }); continue; }
    const attack = s.cards.find(id => CARDS[id].damage && s.mana >= CARDS[id].cost &&
      (s.enemy.hp <= CARDS[id].damage || s.mana >= 6));
    if (attack) { execute({ type: 'cast', cardId: attack }); continue; }
    if (s.steps > 0) {
      let best = null;
      for (let a = 0; a < 36; a++) for (const b of [a % 6 < 5 ? a + 1 : -1, a < 30 ? a + 6 : -1]) {
        if (b < 0) continue;
        const action = { type: 'swap', a, b }, result = act(s, action);
        if (!result.ok) continue;
        const n = result.state;
        const threat = Math.max(0, s.enemy.intent - s.player.armor - s.player.shield);
        const value = (n.stats.damage - s.stats.damage) * 2 + (n.wave - s.wave) * 160 +
          (n.status === 'won' ? 1000 : 0) + (n.player.hp - s.player.hp) +
          Math.min(threat, Math.max(0, n.player.shield - s.player.shield)) * 0.7 +
          (n.mana - s.mana) * 7 + (n.stats.fourReturns - s.stats.fourReturns) * 18;
        if (!best || value > best.value) best = { action, value };
      }
      assert.ok(best, 'playable board must provide an effective exchange');
      execute(best.action); continue;
    }
    const need = Math.max(0, s.enemy.intent - s.player.armor - s.player.shield);
    const defense = s.cards.find(id => (CARDS[id].shield || CARDS[id].shieldRatio) && s.mana >= CARDS[id].cost);
    if (need > 0 && defense) { execute({ type: 'cast', cardId: defense }); continue; }
    execute({ type: 'endTurn' });
  }
  return { state: s, actions, preset, seed };
}
const records = [];
test('all four offered presets clear five bamboo fights using replayable fixed-seed actions', () => {
  for (const preset of PRESETS) {
    const record = simulate(preset.id, 630101);
    assert.equal(record.state.status, 'won', preset.id);
    assert.equal(record.state.stats.enemiesDefeated, 5);
    let replay = create({ seed: record.seed, preset: record.preset });
    record.actions.forEach(a => { replay = commit(replay, a); });
    assert.deepEqual(replay, record.state);
    records.push({ preset: record.preset, seed: record.seed, swaps: replay.stats.swaps,
      rounds: replay.round, hp: replay.player.hp, maxChain: replay.stats.maxChain,
      actions: record.actions });
    console.log(`${preset.id}: ${replay.stats.swaps} swaps, ${replay.round} turns, ${replay.player.hp}/170 HP, ${record.actions.length} replay operations`);
  }
});

module.exports = { simulate, records };
