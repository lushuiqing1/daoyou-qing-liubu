(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.BattleDemo = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // A read-only snapshot of Godot 1.5.0 rules 4. Demo sessions never touch its save.
  const TYPES = ['red', 'green', 'blue', 'yellow', 'purple'];
  const DATA = {
    version: '1.5.0-web-demo', rulesVersion: 4, chapter: '竹林道',
    character: '沈砚', realm: '炼气六层', seed: 630101,
    equipment: ['桃木剑', '粗布衣', '古玉佩'], treasures: ['青冥剑', '灵气丹'],
    maxMana: 7, maxSteps: 4, maxReturns: 2, chainBonus: 0.15, victoryHealRatio: 0.1,
    types: TYPES,
    tiles: {
      red: { name: '赤刃', glyph: '刃', asset: 'sword', effect: '攻击' },
      green: { name: '青木', glyph: '生', asset: 'heart', effect: '恢复' },
      blue: { name: '玄水', glyph: '甲', asset: 'shield', effect: '护盾' },
      yellow: { name: '金铢', glyph: '钱', asset: 'coin', effect: '铜钱' },
      purple: { name: '紫灵', glyph: '术', asset: 'scroll', effect: '灵墨' }
    },
    waves: [
      { id: 'f1', name: '竹林剑傀', type: 'battle', maxHp: 99, attack: 14, pattern: ['attack', 'charge', 'heavy'], description: '先普攻，再蓄力重击；看清预告后准备防护。' },
      { id: 'f2', name: '雾伥斥候', type: 'battle', maxHp: 110, attack: 15, pattern: ['charge', 'heavy', 'attack'], description: '起手蓄力，下一回合重击；先留防护再输出。' },
      { id: 'f3', name: '竹篙妖客', type: 'battle', maxHp: 132, attack: 16, pattern: ['attack', 'attack', 'charge', 'heavy'], description: '连续两次普攻后蓄力，留意气血与重击窗口。' },
      { id: 'elite', name: '青竹傀将', type: 'elite', maxHp: 165, attack: 18, pattern: ['attack', 'guard', 'charge', 'heavy'], description: '普攻后架盾，再蓄力重击；护盾可打破或等待失效。' },
      { id: 'boss', name: '山魈', type: 'boss', maxHp: 231, attack: 22, pattern: ['attack', 'charge', 'heavy', 'guard'], description: '普攻后蓄力重击，重击后守势；半血后新的蓄力更强。' }
    ]
  };
  const CARDS = {
    sword: { id: 'sword', name: '剑气诀', glyph: '斩', type: 'attack', baseCost: 3, cost: 2, damage: 63, scale: true, text: '造成63点伤害，精英战额外+5。直线四连后，下次剑气额外+10。' },
    ward: { id: 'ward', name: '金刚罩', glyph: '守', type: 'defense', baseCost: 2, cost: 1, shieldRatio: 0.3, text: '获得51点护盾；护盾会在敌方行动后消散。' },
    heal: { id: 'heal', name: '回春丹', glyph: '愈', type: 'heal', baseCost: 1, cost: 1, healRatio: 0.25, text: '恢复43点气血，最多恢复到170；满血时不可用。' },
    step: { id: 'step', name: '神行步', glyph: '行', type: 'utility', baseCost: 1, cost: 1, shield: 10, text: '获得10点护盾。' },
    comboOrder: { id: 'comboOrder', name: '连击令', glyph: '令', type: 'utility', baseCost: 3, cost: 2, text: '接下来2次消除，赤刃攻击额外+10。' },
    spiritArray: { id: 'spiritArray', name: '聚灵阵', glyph: '阵', type: 'utility', baseCost: 2, cost: 1, damage: 16, heal: 12, text: '造成16点伤害并恢复12气血；下次包含紫灵的消除额外+1灵墨。' },
    flame: { id: 'flame', name: '焚风诀', glyph: '焚', type: 'attack', baseCost: 2, cost: 1, damage: 65, scale: true, text: '造成65点伤害。' },
    golden: { id: 'golden', name: '金蝉脱壳', glyph: '蝉', type: 'utility', baseCost: 2, cost: 1, heal: 15, shield: 15, text: '恢复15点气血，获得15点护盾。' },
    ironwall: { id: 'ironwall', name: '金刚符', glyph: '刚', type: 'defense', baseCost: 2, cost: 1, shield: 26, text: '获得26点护盾；本次敌方行动击破全部护盾时返还1灵墨，每回合最多一次。' }
  };
  const PRESETS = [
    { id: 'starter', name: '起始', title: '初行三式', deck: ['sword', 'ward', 'heal'], description: '剑气、护盾、恢复兼顾，适合初次历练。' },
    { id: 'sword', name: '御剑', title: '剑气连消', deck: ['sword', 'comboOrder', 'step'], description: '连击令配合四连消，强化下一次剑气；神行步补充防护。' },
    { id: 'guard', name: '守阵', title: '护盾守势', deck: ['ward', 'ironwall', 'golden'], description: '多种护盾交替使用，金刚符护盾被打破时返还灵墨。' },
    { id: 'spirit', name: '灵术', title: '灵墨循环', deck: ['spiritArray', 'flame', 'heal'], description: '聚灵阵配合紫灵消除，积累灵墨后攻守交替。' }
  ];
  const clone = value => JSON.parse(JSON.stringify(value));
  const freeze = value => {
    Object.values(value).forEach(v => { if (v && typeof v === 'object') freeze(v); });
    return Object.freeze(value);
  };
  [DATA, CARDS, PRESETS].forEach(freeze);

  function random(s) {
    let n = s.rng >>> 0;
    n ^= n << 13; n ^= n >>> 17; n ^= n << 5;
    s.rng = n >>> 0;
    return s.rng / 4294967296;
  }
  function tile(s, type) {
    return { id: ++s.seq, type: type || TYPES[Math.floor(random(s) * TYPES.length)] };
  }
  function matches(board) {
    const found = new Set();
    for (let row = 0; row < 6; row++) for (let col = 0; col < 6; col++) {
      const i = row * 6 + col, t = board[i];
      if (!t) continue;
      if (col < 4 && board[i + 1] && board[i + 2] && board[i + 1].type === t.type && board[i + 2].type === t.type) {
        for (let x = col; x < 6 && board[row * 6 + x] && board[row * 6 + x].type === t.type; x++) found.add(row * 6 + x);
      }
      if (row < 4 && board[i + 6] && board[i + 12] && board[i + 6].type === t.type && board[i + 12].type === t.type) {
        for (let y = row; y < 6 && board[y * 6 + col] && board[y * 6 + col].type === t.type; y++) found.add(y * 6 + col);
      }
    }
    return [...found];
  }
  function longMatch(board) {
    for (let i = 0; i < 36; i++) {
      if (!board[i]) continue;
      const same = j => board[j] && board[j].type === board[i].type;
      if (i % 6 <= 2 && [i + 1, i + 2, i + 3].every(same)) return true;
      if (i < 18 && [i + 6, i + 12, i + 18].every(same)) return true;
    }
    return false;
  }
  function adjacent(a, b) {
    return Number.isInteger(a) && Number.isInteger(b) && a >= 0 && b >= 0 && a < 36 && b < 36 &&
      (Math.abs(a - b) === 6 || (Math.floor(a / 6) === Math.floor(b / 6) && Math.abs(a - b) === 1));
  }
  function hint(s) {
    if (!s || s.status !== 'playing') return null;
    const copy = s.board.slice();
    for (let a = 0; a < 36; a++) for (const b of [a % 6 < 5 ? a + 1 : -1, a < 30 ? a + 6 : -1]) {
      if (b < 0) continue;
      [copy[a], copy[b]] = [copy[b], copy[a]];
      const works = matches(copy).length > 0;
      [copy[a], copy[b]] = [copy[b], copy[a]];
      if (works) return [a, b];
    }
    return null;
  }
  function makeBoard(s) {
    for (let attempt = 0; attempt < 100; attempt++) {
      const board = [];
      for (let i = 0; i < 36; i++) {
        const allowed = TYPES.filter(type =>
          !(i % 6 >= 2 && board[i - 1].type === type && board[i - 2].type === type) &&
          !(i >= 12 && board[i - 6].type === type && board[i - 12].type === type));
        board.push(tile(s, allowed[Math.floor(random(s) * allowed.length)]));
      }
      if (hint({ status: 'playing', board })) return board;
    }
    throw new Error('棋盘生成失败');
  }
  function collapse(s) {
    for (let col = 0; col < 6; col++) {
      const values = [];
      for (let row = 5; row >= 0; row--) if (s.board[row * 6 + col]) values.push(s.board[row * 6 + col]);
      for (let row = 5; row >= 0; row--) s.board[row * 6 + col] = values[5 - row] || tile(s);
    }
  }
  function snapshot(s) {
    return clone({ player: s.player, enemy: s.enemy, board: s.board, mana: s.mana, steps: s.steps,
      maxSteps: s.maxSteps, wave: s.wave, round: s.round, links: s.links, status: s.status,
      cards: s.cards, stats: s.stats, coins: s.coins, comboRemain: s.comboRemain, comboAtk: s.comboAtk });
  }
  function emit(events, type, s, details) {
    events.push(Object.assign({ type, state: snapshot(s) }, details));
  }
  function announce(s, events) {
    const e = s.enemy, previous = e.intentKind, locked = e.nextDamage;
    const wave = DATA.waves[s.wave - 1];
    const kind = wave.pattern[(e.round - 1) % wave.pattern.length];
    const heavy = Math.round(e.attack * (e.phase === 'enraged' ? 2.2 : 1.8));
    e.intentKind = kind;
    e.intent = kind === 'attack' ? e.attack : kind === 'heavy' ? (previous === 'charge' ? locked : heavy) : 0;
    e.intentShield = kind === 'guard' ? Math.round(e.maxHp * 0.08) : 0;
    e.nextDamage = kind === 'charge' ? heavy : 0;
    if (events) emit(events, 'intent', s, { kind, damage: e.intent, shield: e.intentShield, nextDamage: e.nextDamage });
  }
  function newEnemy(s) {
    const wave = DATA.waves[s.wave - 1];
    s.enemy = { name: wave.name, hp: wave.maxHp, maxHp: wave.maxHp, attack: wave.attack,
      damage: wave.attack, shield: 0, type: wave.type, phase: 'calm', round: 1,
      intentKind: '', intent: 0, intentShield: 0, nextDamage: 0 };
    announce(s);
  }
  function create(options) {
    options = options || {};
    const preset = PRESETS.find(p => p.id === options.preset) || PRESETS[0];
    const seed = Number.isFinite(options.seed) ? (Math.trunc(options.seed) >>> 0) : DATA.seed;
    const s = { version: DATA.version, seed: seed || DATA.seed, rng: seed || DATA.seed, seq: 1,
      preset: preset.id, cards: preset.deck.slice(), round: 1, wave: 1, status: 'playing',
      player: { hp: 170, maxHp: 170, attack: 16, cardPower: 13, armor: 5, shield: 2 },
      mana: 4, steps: 4, maxSteps: 4, bonusSteps: 0, coins: 0, comboRemain: 0, comboAtk: 0,
      links: { swordBoost: false, talismanRefund: false, spiritBonus: false }, wardRefunded: false,
      stats: { swaps: 0, maxChain: 0, fourReturns: 0, casts: {}, hpLost: 0, damage: 0,
        enemyShieldRemoved: 0, blocked: 0, healed: 0, manaOverflow: 0, shieldExpired: 0,
        armorPrevented: 0, enemiesDefeated: 0, links: { sword: 0, ward: 0, purple: 0 }, fatal: null } };
    s.board = makeBoard(s); newEnemy(s);
    return s;
  }
  function gainMana(s, amount, purple) {
    const actual = Math.min(7 - s.mana, amount);
    s.mana += actual;
    if (purple) s.stats.manaOverflow += amount - actual;
    return actual;
  }
  function heal(s, amount) {
    const actual = Math.min(s.player.maxHp - s.player.hp, amount);
    s.player.hp += actual; s.stats.healed += actual;
    return actual;
  }
  function damageEnemy(s, amount, events) {
    const blocked = Math.min(s.enemy.shield, amount), actual = Math.min(s.enemy.hp, amount - blocked);
    s.enemy.shield -= blocked; s.enemy.hp -= actual;
    s.stats.damage += actual; s.stats.enemyShieldRemoved += blocked;
    if (amount > 0) emit(events, 'damage', s, { target: 'enemy', damage: actual, blocked, raw: amount });
    return { damage: actual, blocked };
  }
  function enrage(s, events) {
    const e = s.enemy;
    if (e.type === 'boss' && e.phase === 'calm' && e.hp > 0 && e.hp * 2 <= e.maxHp) {
      e.phase = 'enraged'; emit(events, 'enrage', s);
    }
  }
  function win(s, events) {
    const oldWave = s.wave;
    s.stats.enemiesDefeated++;
    const recovery = heal(s, Math.round(s.player.maxHp * DATA.victoryHealRatio));
    emit(events, 'win', s, { wave: oldWave, heal: recovery, enemy: s.enemy.name });
    if (s.wave === 5) {
      s.status = 'won'; emit(events, 'result', s, { status: 'won' });
      return;
    }
    // Same-turn engagement preserves board, steps, mana, shields, links and combo.
    s.wave++; newEnemy(s);
    emit(events, 'wave', s, { wave: s.wave, enemy: s.enemy.name });
    emit(events, 'intent', s, { kind: s.enemy.intentKind, damage: s.enemy.intent, nextDamage: s.enemy.nextDamage });
  }
  function resolve(s, events) {
    let found = matches(s.board), chain = 1;
    while (found.length) {
      if (chain > 100) throw new Error('连锁过长，本次操作已撤回');
      const before = clone(s.board), counts = Object.fromEntries(TYPES.map(t => [t, 0]));
      found.forEach(i => counts[s.board[i].type]++);
      const multi = 1 + (chain - 1) * DATA.chainBonus;
      const isLong = longMatch(s.board);
      let returned = 0, bonus = 0;
      if (isLong && s.bonusSteps < DATA.maxReturns) { s.steps++; s.bonusSteps++; s.stats.fourReturns++; returned = 1; }
      s.stats.maxChain = Math.max(s.stats.maxChain, chain);
      if (isLong && s.cards.includes('sword')) s.links.swordBoost = true;
      if (s.comboRemain > 0) {
        bonus = s.comboAtk; s.comboRemain--;
        if (!s.comboRemain) s.comboAtk = 0;
      }
      const dealt = counts.red ? damageEnemy(s, Math.round(counts.red * s.player.attack * multi) + bonus, events) : { damage: 0, blocked: 0 };
      const restored = heal(s, Math.round(counts.green * 2 * multi));
      const shield = Math.round(counts.blue * 2 * multi); s.player.shield += shield;
      const coins = counts.yellow * 4; s.coins += coins;
      const purpleLinked = counts.purple > 0 && s.links.spiritBonus;
      if (purpleLinked) { s.links.spiritBonus = false; s.stats.links.purple++; }
      const mana = gainMana(s, counts.purple + (purpleLinked ? 1 : 0), true);
      emit(events, 'match', s, { indices: found.slice(), board: before, chain, counts, dealt: dealt.damage,
        damage: dealt.damage, blocked: dealt.blocked, heal: restored, shield, coins, mana, bonusStep: returned });
      if (purpleLinked) emit(events, 'link', s, { kind: 'purple' });
      enrage(s, events);
      found.forEach(i => { s.board[i] = null; }); collapse(s);
      emit(events, 'board', s, { board: clone(s.board) });
      if (s.enemy.hp <= 0) { win(s, events); if (s.status !== 'playing') return; }
      found = matches(s.board); chain++;
    }
    if (!hint(s)) { s.board = makeBoard(s); emit(events, 'reshuffle', s, { board: clone(s.board) }); }
  }
  function validate(s, a) {
    if (!s || s.status !== 'playing') return '本次体验已结束，可重新挑战';
    if (!a || !['swap', 'cast', 'endTurn'].includes(a.type)) return '未知操作';
    if (a.type === 'swap') {
      if (s.steps <= 0) return '步数已用尽，可使用术式或结束回合';
      if (!adjacent(a.a, a.b)) return '只能交换相邻灵珠';
    }
    if (a.type === 'cast') {
      if (!s.cards.includes(a.cardId) || !CARDS[a.cardId]) return '此术式未装备';
      if (s.mana < CARDS[a.cardId].cost) return '灵墨不足';
      if (a.cardId === 'heal' && s.player.hp === s.player.maxHp) return '气血已满';
    }
    return '';
  }
  function act(state, action) {
    const error = validate(state, action);
    if (error) return { ok: false, state, events: [], error };
    const s = clone(state), events = [];
    try {
      if (action.type === 'swap') {
        const { a, b } = action;
        [s.board[a], s.board[b]] = [s.board[b], s.board[a]];
        if (!matches(s.board).length) return { ok: false, state, events: [], error: '未形成消除，不扣步数' };
        s.steps--; s.stats.swaps++;
        emit(events, 'swap', s, { a, b, board: clone(s.board) }); resolve(s, events);
      } else if (action.type === 'cast') {
        const card = CARDS[action.cardId];
        const boosted = card.id === 'sword' && s.links.swordBoost;
        s.mana -= card.cost; s.stats.casts[card.id] = (s.stats.casts[card.id] || 0) + 1;
        let dealt = { damage: 0, blocked: 0 }, restored = 0, shield = 0;
        if (card.damage) dealt = damageEnemy(s, card.damage + (card.id === 'sword' && s.enemy.type === 'elite' ? 5 : 0) + (boosted ? 10 : 0), events);
        if (boosted) { s.links.swordBoost = false; s.stats.links.sword++; }
        if (card.id === 'ironwall') s.links.talismanRefund = true;
        if (card.id === 'spiritArray') s.links.spiritBonus = true;
        if (card.shieldRatio) shield += Math.round(s.player.maxHp * card.shieldRatio);
        if (card.shield) shield += card.shield;
        s.player.shield += shield;
        if (card.healRatio) restored += heal(s, Math.round(s.player.maxHp * card.healRatio));
        if (card.heal) restored += heal(s, card.heal);
        if (card.id === 'comboOrder') { s.comboRemain += 2; s.comboAtk += 10; }
        emit(events, 'card', s, { cardId: card.id, dealt: dealt.damage, damage: dealt.damage, blocked: dealt.blocked, heal: restored, shield, swordBoost: boosted });
        if (boosted) emit(events, 'link', s, { kind: 'sword' });
        enrage(s, events); if (s.enemy.hp <= 0) win(s, events);
      } else {
        const e = s.enemy, p = s.player;
        const raw = Math.max(0, e.intent - p.armor), beforeShield = p.shield;
        const blocked = Math.min(raw, beforeShield), damage = Math.min(p.hp, raw - blocked);
        s.stats.hpLost += damage; s.stats.blocked += blocked; s.stats.armorPrevented += Math.min(p.armor, e.intent);
        if (damage >= p.hp) s.stats.fatal = { wave: s.wave, kind: e.intentKind, intent: e.intent,
          mana: s.mana, steps: s.steps, shield: p.shield,
          defense: s.cards.filter(id => (CARDS[id].shield || CARDS[id].shieldRatio) && s.mana >= CARDS[id].cost),
          healing: s.cards.filter(id => p.hp < p.maxHp && (CARDS[id].heal || CARDS[id].healRatio) && s.mana >= CARDS[id].cost) };
        e.shield = e.intentKind === 'guard' ? e.intentShield : 0;
        p.shield -= blocked; p.hp -= damage;
        const refunded = s.links.talismanRefund && !s.wardRefunded && beforeShield > 0 && blocked === beforeShield;
        if (refunded) { s.wardRefunded = true; s.links.talismanRefund = false; gainMana(s, 1, false); s.stats.links.ward++; }
        emit(events, 'enemy', s, { kind: e.intentKind, damage, blocked, guard: e.intentShield, nextDamage: e.nextDamage });
        if (damage) emit(events, 'damage', s, { target: 'player', damage, blocked, raw });
        if (refunded) emit(events, 'link', s, { kind: 'ward' });
        s.stats.shieldExpired += p.shield; p.shield = 0;
        if (p.hp <= 0) { s.status = 'lost'; emit(events, 'result', s, { status: 'lost' }); }
        else {
          s.round++; e.round++; s.steps = s.maxSteps; s.bonusSteps = 0;
          s.links = { swordBoost: false, talismanRefund: false, spiritBonus: false }; s.wardRefunded = false;
          p.shield += 2; gainMana(s, 1, false); announce(s, events);
          if (!hint(s)) { s.board = makeBoard(s); emit(events, 'reshuffle', s, { board: clone(s.board) }); }
        }
      }
      return { ok: true, state: s, events, error: '' };
    } catch (failure) { return { ok: false, state, events: [], error: failure.message || '本次操作已撤回' }; }
  }
  return Object.freeze({ create, act, hint, DATA, PRESETS, CARDS });
});
