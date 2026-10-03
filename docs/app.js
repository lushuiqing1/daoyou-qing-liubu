(function () {
  'use strict';
  const E = window.BattleDemo;
  const $ = id => document.getElementById(id);
  const KEY = 'daoyou.battle-demo.v1';
  const RELEASE = 'https://github.com/lushuiqing1/daoyou-qing-liubu/releases/tag/godot-v1.5.0';
  const esc = x => String(x).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const clone = x => JSON.parse(JSON.stringify(x));
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const ACTIONS = { attack: '普攻', charge: '蓄力', heavy: '重击', guard: '守势' };
  const SKILL_ART = { sword: 'sword', ward: 'ward', heal: 'heal', step: 'step', comboOrder: 'comboOrder', spiritArray: 'spiritArray', flame: 'flame', golden: 'golden', ironwall: 'ironwall' };
  let state, busy = false, selectedTile = null, selectedCard = null, cursor = 0, hinted = [], pointer = null, suppressClick = false;
  let settings = { reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches, sound: false };
  let guide = {}, feedbackTimer, hintTimer, storageAvailable = true, soundContext, resultShown = false;

  function validState(s) {
    const preset = E.PRESETS.find(p => p.id === s?.preset);
    const finite = (x, lo, hi) => Number.isFinite(x) && x >= lo && x <= hi;
    return s?.version === E.DATA.version && preset && Array.isArray(s.cards) && s.cards.join() === preset.deck.join() &&
      Array.isArray(s.board) && s.board.length === 36 && s.board.every(t => t && E.DATA.types.includes(t.type) && Number.isInteger(t.id)) &&
      ['playing', 'won', 'lost'].includes(s.status) && Number.isInteger(s.wave) && finite(s.wave, 1, 5) &&
      finite(s.player?.hp, 0, 170) && s.player.maxHp === 170 && finite(s.player.shield, 0, 100000) &&
      finite(s.enemy?.hp, 0, E.DATA.waves[s.wave - 1].maxHp) && s.enemy.maxHp === E.DATA.waves[s.wave - 1].maxHp &&
      ACTIONS[s.enemy.intentKind] && finite(s.mana, 0, 7) && finite(s.steps, 0, 6) &&
      Number.isInteger(s.rng) && finite(s.rng, 0, 4294967295) && Number.isInteger(s.seq) && s.seq >= 1 &&
      Number.isInteger(s.round) && finite(s.round, 1, 100000) && s.links && s.stats?.casts && s.stats?.links &&
      finite(s.stats.swaps, 0, 100000) && finite(s.stats.hpLost, 0, 1000000) && Number.isFinite(s.bonusSteps);
  }
  function restore() {
    let saved;
    try {
      const raw = localStorage.getItem(KEY);
      try { saved = JSON.parse(raw || 'null'); } catch (_) { saved = null; }
      if (saved?.schema === 1 && validState(saved.state)) {
        state = saved.state;
        guide = saved.guide && typeof saved.guide === 'object' ? saved.guide : {};
        settings.sound = saved.settings?.sound === true;
        settings.reducedMotion = saved.settings?.reducedMotion === true;
        return true;
      }
    } catch (_) { storageAvailable = false; }
    state = E.create({ seed: E.DATA.seed, preset: 'starter' });
    return false;
  }
  function save() {
    try { localStorage.setItem(KEY, JSON.stringify({ schema: 1, state, settings, guide })); }
    catch (_) { storageAvailable = false; }
  }
  function notify(text, duration = 5000) {
    clearTimeout(feedbackTimer);
    $('feedback').textContent = text;
    if (duration) feedbackTimer = setTimeout(() => {
      $('feedback').textContent = state.status === 'playing' ? (state.steps ? '交换相邻灵珠，消除三枚同色。' : '步数用尽，仍可施法；结束回合后补满。') : '竹林体验已结束，可以换一组搭配再试。';
    }, duration);
  }
  function lesson(id, text) {
    if (guide.skip || guide[id]) return false;
    guide[id] = true; save(); notify(text, 7000); return true;
  }
  function tone(kind) {
    if (!settings.sound) return;
    try {
      soundContext ||= new (window.AudioContext || window.webkitAudioContext)();
      soundContext.resume();
      const oscillator = soundContext.createOscillator(), gain = soundContext.createGain();
      oscillator.connect(gain); gain.connect(soundContext.destination);
      const t = soundContext.currentTime;
      oscillator.type = 'sine'; oscillator.frequency.setValueAtTime(kind === 'hit' ? 240 : 620, t);
      oscillator.frequency.exponentialRampToValueAtTime(kind === 'hit' ? 100 : 880, t + 0.12);
      gain.gain.setValueAtTime(0.08, t); gain.gain.exponentialRampToValueAtTime(0.001, t + 0.18);
      oscillator.start(t); oscillator.stop(t + 0.18);
    } catch (_) { /* Sound is optional; combat remains usable. */ }
  }
  function intentText(s) {
    if (s.status !== 'playing') return s.status === 'won' ? '竹林已清 · 五战告捷' : '本次历练止步';
    const e = s.enemy;
    if (e.intentKind === 'charge') return `蓄力 · 下次重击 ${e.nextDamage}`;
    if (e.intentKind === 'guard') return `守势 · 获得 ${e.intentShield} 盾`;
    return `${ACTIONS[e.intentKind]} · ${e.intent} 伤害`;
  }
  function cardReason(s, id) {
    if (s.status !== 'playing') return '本次体验已结束';
    if (s.mana < E.CARDS[id].cost) return '灵墨不足';
    if (id === 'heal' && s.player.hp >= s.player.maxHp) return '气血已满';
    return '';
  }
  function render(s = state) {
    document.body.classList.toggle('reduced-motion', settings.reducedMotion);
    document.body.classList.toggle('is-busy', busy);
    document.body.dataset.status = s.status;
    $('chapter').textContent = E.DATA.chapter;
    $('wave').textContent = `${s.wave} / 5`;
    $('turn').textContent = s.round;
    $('steps').textContent = s.steps;
    $('mana').textContent = s.mana;
    $('intent').textContent = intentText(s);
    $('intent-detail').dataset.kind = s.enemy.intentKind;
    $('player-attack').textContent = s.player.attack;
    $('enemy-attack').textContent = s.enemy.attack;
    $('player-shield').textContent = s.player.shield;
    $('enemy-shield').textContent = s.enemy.shield;
    for (const target of ['player', 'enemy']) {
      const p = s[target], ratio = Math.max(0, Math.min(1, p.hp / p.maxHp));
      $(`${target}-health-fill`).style.width = `${ratio * 100}%`;
      $(`${target}-health`).setAttribute('aria-label', `${target === 'player' ? '我方' : '敌方'}气血 ${p.hp} / ${p.maxHp}`);
      $(`${target}-health`).setAttribute('aria-valuenow', p.hp);
      $(`${target}-health`).setAttribute('aria-valuemax', p.maxHp);
      $(`${target}-health`).textContent = `${target === 'player' ? '我方' : '敌方'}气血 ${p.hp} / ${p.maxHp}`;
    }
    $('enemy-portrait').src = s.wave === 5 ? 'assets/boss.webp' : 'assets/enemy.webp';
    $('enemy-portrait').alt = s.wave === 5 ? '竹林首领山魈' : '竹林剑傀';
    $('enemy-detail').classList.toggle('enraged', s.enemy.phase === 'enraged');
    $('enemy-detail').setAttribute('aria-label', `查看敌方状态，第 ${s.wave} 战${s.enemy.phase === 'enraged' ? '，已激怒' : ''}`);
    if ($('preset-name')) $('preset-name').textContent = E.PRESETS.find(p => p.id === state.preset).name;
    if ($('link-status')) {
      const labels = [];
      if (s.links.swordBoost) labels.push('剑气 +10');
      if (s.links.talismanRefund) labels.push('破盾可返墨');
      if (s.links.spiritBonus) labels.push('下次紫消 +1墨');
      if (s.comboRemain) labels.push(`连击 ${s.comboRemain} 次`);
      $('link-status').textContent = labels.join(' · ');
      $('link-status').hidden = !labels.length;
    }
    $('board').setAttribute('aria-busy', String(busy));
    $('board').classList.toggle('out-of-steps', s.steps === 0);
    if (!$('board').children.length) {
      const fragment = document.createDocumentFragment();
      for (let i = 0; i < 36; i++) {
        const button = document.createElement('button');
        button.className = 'tile'; button.type = 'button'; button.dataset.index = i;
        button.setAttribute('role', 'gridcell');
        const art = document.createElement('img'); art.className = 'tile-art'; art.alt = ''; art.draggable = false;
        button.append(art); fragment.append(button);
      }
      $('board').append(fragment);
    }
    [...$('board').children].forEach((button, i) => {
      const tile = s.board[i], data = E.DATA.tiles[tile.type];
      button.dataset.kind = tile.type; button.dataset.tileId = tile.id;
      button.querySelector('img').src = `assets/tile-${data.asset}.webp`;
      button.setAttribute('aria-label', `第${Math.floor(i / 6) + 1}行第${i % 6 + 1}列，${data.name}，${data.effect}`);
      button.setAttribute('aria-selected', String(selectedTile === i));
      button.tabIndex = i === cursor ? 0 : -1;
      button.classList.toggle('selected', selectedTile === i);
      button.classList.toggle('hinted', hinted.includes(i));
      button.disabled = busy || s.status !== 'playing';
    });
    if ($('cards').dataset.deck !== s.cards.join()) {
      $('cards').dataset.deck = s.cards.join();
      $('cards').innerHTML = s.cards.map((id, i) => {
        const c = E.CARDS[id];
        const short = { sword: '剑气 63', ward: '护盾 51', heal: '恢复 43', step: '护盾 10', comboOrder: '连消增伤', spiritArray: '伤害 16\n回复 12', flame: '焚风 65', golden: '回复＋护盾', ironwall: '护盾 26' }[id];
        return `<button type="button" class="skill-card" data-card="${id}" aria-label="选择${esc(c.name)}，耗${c.cost}灵墨"><img class="skill-art" src="assets/skill-${SKILL_ART[id]}.webp" alt="" draggable="false"><span class="skill-name">${esc(c.name)}</span><span class="skill-cost">${c.cost}</span><span class="skill-description">${esc(short).replace(/\n/g, '<br>')}<small class="skill-status"></small></span><span class="skill-key">${i + 1}</span></button>`;
      }).join('');
    }
    for (const button of $('cards').children) {
      const reason = cardReason(s, button.dataset.card);
      button.classList.toggle('unavailable', !!reason);
      button.classList.toggle('selected', selectedCard === button.dataset.card);
      button.setAttribute('aria-pressed', String(selectedCard === button.dataset.card));
      button.disabled = busy || s.status !== 'playing';
      button.title = reason || E.CARDS[button.dataset.card].text;
      button.querySelector('.skill-status').textContent = reason || '可施放';
    }
    const chosen = E.CARDS[selectedCard];
    $('card-detail').textContent = chosen ? chosen.text : '选中一式，再按「施放术式」。';
    const reason = chosen ? cardReason(s, selectedCard) : '先选择术式';
    $('confirm-cast').disabled = busy || !!reason;
    $('confirm-cast').textContent = chosen ? `施放${chosen.name}` : '施放术式';
    $('end-turn').disabled = busy || s.status !== 'playing';
    $('end-turn').classList.toggle('attention', s.steps === 0 && s.status === 'playing');
    $('hint').disabled = busy || s.status !== 'playing' || s.steps === 0;
    for (const id of ['restart', 'settings', 'help', 'stage-progress', 'player-detail', 'enemy-detail', 'intent-detail']) {
      if ($(id)) $(id).disabled = busy;
    }
  }
  function floatText(target, text, kind = '') {
    const rect = $(target === 'player' ? 'player-detail' : 'enemy-detail').getBoundingClientRect();
    const parent = $('effects').getBoundingClientRect();
    const span = document.createElement('span'); span.className = `combat-number ${kind}`;
    span.textContent = text;
    span.style.left = `${rect.left + rect.width / 2 - parent.left}px`;
    span.style.top = `${rect.top + rect.height / 2 - parent.top}px`;
    $('effects').append(span);
    setTimeout(() => span.remove(), settings.reducedMotion ? 850 : 1150);
  }
  function pulse(id, kind) {
    const node = $(id); if (!node) return;
    node.classList.remove(kind); void node.offsetWidth; node.classList.add(kind);
    setTimeout(() => node.classList.remove(kind), 500);
  }
  async function animate(events) {
    for (const event of events) {
      if (event.state) render(event.state);
      if (event.type === 'match') {
        event.indices.forEach(i => $('board').children[i]?.classList.add('clearing'));
        tone('match');
        const rewards = [];
        if (event.damage) rewards.push(`攻击 ${event.damage}`);
        if (event.heal) rewards.push(`恢复 ${event.heal}`);
        if (event.shield) rewards.push(`护盾 +${event.shield}`);
        if (event.mana) rewards.push(`灵墨 +${event.mana}`);
        if (event.bonusStep) rewards.push('四连返步 +1');
        notify(`${event.chain > 1 ? `${event.chain}层连锁 · ` : ''}${rewards.join(' · ') || '铜钱入囊'}`, 0);
        await wait(settings.reducedMotion ? 70 : 220);
        [...$('board').children].forEach(e => e.classList.remove('clearing'));
      } else if (event.type === 'damage' && event.damage) {
        floatText(event.target, `−${event.damage}`, 'damage'); pulse(`${event.target}-detail`, 'hit'); tone('hit');
        await wait(settings.reducedMotion ? 40 : 120);
      } else if (event.type === 'card') {
        if (event.heal) floatText('player', `+${event.heal}`, 'heal');
        if (event.shield) floatText('player', `+${event.shield}盾`, 'shield');
        pulse('cards', 'cast-flash'); notify(`施放${E.CARDS[event.cardId].name}`, 0);
        await wait(settings.reducedMotion ? 70 : 200);
      } else if (event.type === 'wave') {
        pulse('enemy-detail', 'entering');
        notify(event.wave === 5 ? '第五战 · 首领入场' : `第${event.wave}战 · 继续接战`, 0);
        await wait(settings.reducedMotion ? 180 : 500);
      } else if (event.type === 'win') {
        pulse('enemy-detail', 'defeated');
        if (event.heal) floatText('player', `+${event.heal}`, 'heal');
        await wait(settings.reducedMotion ? 100 : 280);
      } else if (event.type === 'enrage') {
        notify('首领震怒 · 下一次新蓄力更强，已预告的重击保持不变。', 0);
        pulse('enemy-detail', 'enraged-flash'); await wait(settings.reducedMotion ? 100 : 250);
      } else if (event.type === 'link') {
        notify({ sword: '四连剑气 · 强化 +10 已生效', ward: '护盾被击破 · 返还 1 灵墨', purple: '聚灵回环 · 紫消额外 1 灵墨' }[event.kind], 0);
        await wait(settings.reducedMotion ? 90 : 250);
      } else if (event.type === 'enemy') {
        notify(event.kind === 'charge' ? `敌方蓄力 · 下次重击 ${event.nextDamage}` : event.kind === 'guard' ? `敌方守势 · 获得 ${event.guard} 盾` : `${ACTIONS[event.kind]} · 失血 ${event.damage}，格挡 ${event.blocked}`, 0);
        await wait(settings.reducedMotion ? 90 : 200);
      } else if (event.type === 'reshuffle') {
        notify('棋盘无解 · 已自动重新布置', 0); await wait(120);
      } else if (event.type === 'swap' || event.type === 'board') await wait(settings.reducedMotion ? 20 : 100);
    }
  }
  async function perform(action) {
    if (busy || document.querySelector('dialog[open]')) return;
    const before = state, result = E.act(state, action);
    if (!result.ok) { notify(result.error); return; }
    busy = true; selectedTile = null; hinted = []; clearTimeout(hintTimer);
    state = result.state; save(); // Commit once before visual playback; refresh resumes this exact state.
    render(before);
    try { await animate(result.events); }
    finally { busy = false; render(); }
    if (state.status !== 'playing') { showResult(); return; }
    let coached = false;
    if (result.events.some(e => e.type === 'wave')) coached = lesson('wave', '接战保留棋盘、灵墨、护盾和剩余步数，新怪从自己的首次行动开始。');
    else if (result.events.some(e => e.type === 'link')) coached = lesson('links', '联动不叠加，结束回合后清除；同回合接战可以保留。');
    else if (result.events.some(e => e.type === 'match' && e.bonusStep)) coached = lesson('four', '直线四连及以上返还 1 步，每个回合最多返还 2 步。');
    else if (action.type === 'swap') coached = lesson('swap', '交换成功。每回合可交换 4 次，紫灵消除可攒灵墨施法。');
    else if (action.type === 'cast') coached = lesson('cast', '施法不消耗交换步数，灵墨足够可以继续施放。');
    else if (action.type === 'endTurn') coached = lesson('turn', '结束回合时敌方行动，随后步数补满。蓄力回合可先积攒防护。');
    if (!coached) notify(state.steps ? '可以继续交换，或选择术式施放。' : '步数用尽，仍可施法；准备好后结束回合。');
  }
  function selectTile(index) {
    if (busy || state.status !== 'playing') return;
    if (!state.steps) { notify('步数已用尽，可施法或结束回合。'); return; }
    cursor = index;
    if (selectedTile === index) selectedTile = null;
    else if (selectedTile === null) selectedTile = index;
    else {
      const a = selectedTile;
      const adjacent = Math.abs(a - index) === 6 || (Math.floor(a / 6) === Math.floor(index / 6) && Math.abs(a - index) === 1);
      if (adjacent) { selectedTile = null; perform({ type: 'swap', a, b: index }); return; }
      selectedTile = index;
    }
    render();
  }
  function selectCard(id) {
    if (busy || state.status !== 'playing') return;
    selectedCard = id; render();
    const reason = cardReason(state, id);
    if (reason) notify(`${E.CARDS[id].name}：${reason}`);
  }
  function showHint() {
    if (busy || state.status !== 'playing' || !state.steps) return;
    hinted = E.hint(state) || []; selectedTile = null; render();
    notify('发光的两枚可以交换。提示不消耗步数。');
    clearTimeout(hintTimer); hintTimer = setTimeout(() => { hinted = []; render(); }, 4500);
  }
  const dialog = document.createElement('dialog'); dialog.className = 'demo-dialog'; dialog.setAttribute('aria-labelledby', 'dialog-title'); document.body.append(dialog);
  let dialogOrigin;
  function modal(title, body, actions = '') {
    if (busy) return;
    if (dialog.open) dialog.close();
    dialogOrigin = document.activeElement;
    dialog.innerHTML = `<header class="modal-head"><h2 id="dialog-title">${esc(title)}</h2><button type="button" class="dialog-close" data-close aria-label="关闭">×</button></header><div class="dialog-body">${body}</div>${actions ? `<div class="dialog-actions">${actions}</div>` : ''}`;
    dialog.showModal();
    dialog.querySelector('.dialog-close').focus({ preventScroll: true });
    dialog.scrollTop = 0;
    requestAnimationFrame(() => { dialog.scrollTop = 0; });
  }
  dialog.addEventListener('click', e => { if (e.target === dialog || e.target.closest('[data-close]')) dialog.close(); });
  dialog.addEventListener('close', () => { if (dialogOrigin?.isConnected) dialogOrigin.focus(); });
  dialog.addEventListener('keydown', e => {
    if (e.key !== 'Tab') return;
    const targets = [...dialog.querySelectorAll('button:not(:disabled),a[href],input:not(:disabled),summary,[tabindex="0"]')].filter(node => node.getClientRects().length);
    const first = targets[0], last = targets[targets.length - 1];
    if (!first) return;
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  });
  function showHelp() {
    modal('三消成式 · 竹林轻体验', `<p class="dialog-lead">交换相邻灵珠，让三枚同色连成一线。击败五只敌人，清出一条竹林道。</p><div class="legend-list">${E.DATA.types.map(t => {
      const d = E.DATA.tiles[t];
      return `<div><img src="assets/tile-${d.asset}.webp" alt=""><strong>${d.name}</strong><span>${esc({ red: '攻击敌方', green: '恢复气血', blue: '积累护盾', yellow: '收集铜钱', purple: '增加灵墨' }[t])}</span></div>`;
    }).join('')}</div><ol class="rules-list"><li>每回合 4 步。无效交换不扣步，直线四连及以上返 1 步，每回合最多返 2 步。</li><li>选中术式，再确认施放。灵墨上限 7，施法不扣交换步。</li><li>结束回合时敌方按预告行动，我方剩余护盾随后消散。敌方先蓄力，再重击。</li><li>击败敌人恢复最多 17 气血，棋盘和本回合资源继续用于下一战。</li></ol><p class="fine-print">键盘：方向键移动棋盘焦点，空格或 Enter 选择；1–3 选式、Enter 施放、H 提示、E 结束回合、Esc 暂停。手机可点选两枚相邻灵珠或滑动交换。</p><p class="fine-print">固定${E.DATA.realm}角色，${E.DATA.equipment.join('／')}，配${E.DATA.treasures.join('／')}。本页展示一章战斗，体验铜钱只作本局记录。完整游戏另有四境、修炼、收藏与通关试炼。</p>`, '<button type="button" class="primary-button" data-close autofocus>开始消除</button><button type="button" class="secondary-button" id="skip-guide">跳过短提示</button>');
    $('skip-guide').onclick = () => { guide.skip = true; save(); dialog.close(); notify('短提示已跳过，可随时从「规则」重看。'); };
  }
  function showSettings() {
    modal('体验设置', `<label class="setting-row"><span><strong>减少动态效果</strong><small>保留血条和结算，减少闪动与位移。</small></span><input id="motion-setting" type="checkbox" ${settings.reducedMotion ? 'checked' : ''}></label><label class="setting-row"><span><strong>战斗音效</strong><small>短音效默认关闭。</small></span><input id="sound-setting" type="checkbox" ${settings.sound ? 'checked' : ''}></label><p class="fine-print">${storageAvailable ? '本局会自动保存在当前浏览器，刷新后可继续。' : '浏览器限制了本地保存，本局仍可继续游玩。'}试玩进度使用独立存储。</p>`, '<button type="button" class="primary-button" data-close>完成</button><button type="button" class="secondary-button" id="review-guide">重看短提示</button>');
    $('motion-setting').onchange = e => { settings.reducedMotion = e.target.checked; save(); render(); };
    $('sound-setting').onchange = e => { settings.sound = e.target.checked; save(); tone('match'); };
    $('review-guide').onclick = () => { guide = {}; save(); showHelp(); };
  }
  function showRestart() {
    let preset = state.preset;
    modal('换一组搭配 · 再入竹林', `<p class="dialog-lead">从满血、第一战开始。四组共用固定角色，自由体验不同打法。</p><div class="preset-list">${E.PRESETS.map(p => `<button type="button" class="preset-option ${p.id === preset ? 'selected' : ''}" data-preset="${p.id}" aria-pressed="${p.id === preset}"><strong>${esc(p.name)}</strong><span>${p.deck.map(id => E.CARDS[id].name).join('／')}</span><small>${esc(p.description)}</small></button>`).join('')}</div><label class="same-seed"><input id="same-seed" type="checkbox" checked>同一棋盘重试</label>`, '<button type="button" class="primary-button" id="start-again">重新挑战</button><button type="button" class="secondary-button" data-close>留在本局</button>');
    dialog.querySelectorAll('[data-preset]').forEach(button => { button.onclick = () => {
      preset = button.dataset.preset;
      dialog.querySelectorAll('[data-preset]').forEach(b => { const on = b.dataset.preset === preset; b.classList.toggle('selected', on); b.setAttribute('aria-pressed', String(on)); });
    }; });
    $('start-again').onclick = () => {
      let seed = state.seed;
      if (!$('same-seed').checked) { const a = new Uint32Array(1); crypto.getRandomValues(a); seed = a[0] || E.DATA.seed; }
      state = E.create({ preset, seed }); selectedCard = null; selectedTile = null; cursor = 0; hinted = []; resultShown = false;
      save(); dialog.close(); render(); notify(`${E.PRESETS.find(p => p.id === preset).name}三式 · 第一战开始`);
    };
  }
  function showProgress() {
    const next = E.DATA.waves[state.wave];
    modal('竹林连续五战', `<div class="wave-list">${E.DATA.waves.map((w, i) => `<div class="wave-row ${state.wave === i + 1 ? 'current' : ''}"><strong>${i + 1}${i === 4 ? ' · 首领' : ''}</strong><span>${esc(w.description)}</span><small>${state.wave > i + 1 || state.status === 'won' ? '已过' : state.wave === i + 1 ? '当前' : `首次${ACTIONS[w.pattern[0]]}`}</small></div>`).join('')}</div><p class="dialog-lead">${next ? `下一战：${esc(next.description)}首次${ACTIONS[next.pattern[0]]}。` : '当前为第五战，击败首领后完成体验。'}</p><p class="fine-print">接战保留棋盘、灵墨、护盾、剩余步数及本回合联动；新怪不会立即额外攻击。</p>`);
  }
  function showDetail(target) {
    if (target === 'player') modal('我方状态', `<dl class="detail-list"><div><dt>气血</dt><dd>${state.player.hp} / ${state.player.maxHp}</dd></div><div><dt>基础攻击</dt><dd>${state.player.attack}</dd></div><div><dt>减伤</dt><dd>${state.player.armor}</dd></div><div><dt>护盾</dt><dd>${state.player.shield}</dd></div><div><dt>灵墨</dt><dd>${state.mana} / 7</dd></div><div><dt>境界</dt><dd>${E.DATA.realm}</dd></div></dl><p class="fine-print">${E.DATA.equipment.join('／')}；法宝：${E.DATA.treasures.join('／')}。粗布衣每回合开始 +2 盾；古玉佩每回合开始 +1 墨；灵气丹降低术式墨耗，最低 1 墨。</p><p>护盾用于本次敌方行动，剩余量随后消散。</p>`);
    else modal('敌方状态', `<dl class="detail-list"><div><dt>气血</dt><dd>${state.enemy.hp} / ${state.enemy.maxHp}</dd></div><div><dt>基础攻击</dt><dd>${state.enemy.attack}</dd></div><div><dt>护盾</dt><dd>${state.enemy.shield}</dd></div><div><dt>行动</dt><dd>${esc(intentText(state))}</dd></div><div><dt>状态</dt><dd>${state.enemy.phase === 'enraged' ? '首领已激怒' : '冷静'}</dd></div></dl><p>${esc(E.DATA.waves[state.wave - 1].description)}</p><p class="fine-print">首领半血后的新蓄力按 2.2 倍攻击锁定重击；已预告的重击不会因激怒而改动。先扣减伤，再用护盾格挡。</p>`);
  }
  function advice(s) {
    if (s.status === 'lost' && s.stats.fatal) {
      const f = s.stats.fatal;
      const available = [...f.defense, ...f.healing].map(id => E.CARDS[id].name);
      return `最后一回合面对${ACTIONS[f.kind]}，行动前有 ${f.mana} 灵墨${available.length ? `，可用术式：${[...new Set(available)].join('、')}` : ''}。`;
    }
    if (s.stats.manaOverflow) return `紫灵消除有 ${s.stats.manaOverflow} 点灵墨超过上限，未计入资源。`;
    if (s.stats.shieldExpired) return `本局共有 ${s.stats.shieldExpired} 点剩余护盾在敌方行动后消散。`;
    const unused = s.cards.filter(id => !s.stats.casts[id]);
    if (unused.length) return `本局尚未使用${unused.map(id => E.CARDS[id].name).join('、')}。`;
    return '';
  }
  function showResult() {
    if (busy || resultShown) return;
    resultShown = true;
    const st = state.stats, casts = Object.values(st.casts).reduce((n, x) => n + x, 0), fact = advice(state);
    modal(state.status === 'won' ? '竹林已清 · 道友留步' : '本次止步 · 再修一回', `<p class="dialog-lead">${state.status === 'won' ? '五战告捷，已体验三消与三式的配合。换一组搭配，还能走出另一条竹林道。' : `止步于第 ${state.wave} 战。可以用同一棋盘调整打法，再次挑战。`}</p><div class="result-grid"><div><strong>${st.swaps}</strong><span>有效交换</span></div><div><strong>${st.maxChain}</strong><span>最高连锁</span></div><div><strong>${st.fourReturns}</strong><span>四连返步</span></div><div><strong>${casts}</strong><span>术式使用</span></div><div><strong>${st.hpLost}</strong><span>实际失血</span></div><div><strong>${st.enemiesDefeated} / 5</strong><span>击败敌人</span></div></div>${fact ? `<p class="recap-fact">${esc(fact)}</p>` : ''}<details class="recap-details"><summary>展开战斗复盘</summary><dl class="detail-list"><div><dt>有效输出</dt><dd>${st.damage}</dd></div><div><dt>移除敌盾</dt><dd>${st.enemyShieldRemoved}</dd></div><div><dt>护盾格挡</dt><dd>${st.blocked}</dd></div><div><dt>实际回复</dt><dd>${st.healed}</dd></div><div><dt>紫灵溢出</dt><dd>${st.manaOverflow}</dd></div><div><dt>护盾消散</dt><dd>${st.shieldExpired}</dd></div></dl><p>${state.cards.map(id => `${E.CARDS[id].name} ${st.casts[id] || 0} 次`).join(' · ')}</p><p>强化剑气 ${st.links.sword} 次 · 破盾返墨 ${st.links.ward} 次 · 聚灵紫消 ${st.links.purple} 次</p></details>`, `<button type="button" class="primary-button" id="result-retry" autofocus>换搭配再试</button><a class="secondary-button" href="${RELEASE}" target="_blank" rel="noopener">下载完整游戏</a><button type="button" class="text-button" data-close>查看棋盘</button>`);
    $('result-retry').onclick = showRestart;
  }
  function pause() {
    modal('暂歇竹林', '<p class="dialog-lead">战斗按回合进行，等待时不会受到攻击。</p><p class="fine-print">本局已自动保存，可以继续或选择重新挑战。</p>', '<button type="button" class="primary-button" data-close autofocus>继续战斗</button><button type="button" class="secondary-button" id="pause-restart">重新挑战</button>');
    $('pause-restart').onclick = showRestart;
  }
  $('board').addEventListener('click', e => { const tile = e.target.closest('.tile'); if (!tile) return; if (suppressClick) { suppressClick = false; return; } selectTile(Number(tile.dataset.index)); });
  $('board').addEventListener('focusin', e => {
    const tile = e.target.closest('.tile');
    if (!tile || cursor === Number(tile.dataset.index)) return;
    cursor = Number(tile.dataset.index); render();
  });
  $('board').addEventListener('pointerdown', e => {
    const tile = e.target.closest('.tile');
    if (!tile || busy || !e.isPrimary) return;
    pointer = { index: Number(tile.dataset.index), x: e.clientX, y: e.clientY, id: e.pointerId };
    tile.setPointerCapture(e.pointerId);
  });
  $('board').addEventListener('pointerup', e => {
    if (!pointer || e.pointerId !== pointer.id) return;
    const from = pointer; pointer = null;
    if (Math.hypot(e.clientX - from.x, e.clientY - from.y) < 14) return;
    suppressClick = true; setTimeout(() => { suppressClick = false; }, 100);
    const target = document.elementFromPoint(e.clientX, e.clientY)?.closest('.tile');
    if (target && target.closest('#board')) { selectedTile = null; perform({ type: 'swap', a: from.index, b: Number(target.dataset.index) }); }
  });
  $('board').addEventListener('pointercancel', () => { pointer = null; });
  $('cards').addEventListener('click', e => { const card = e.target.closest('[data-card]'); if (card) selectCard(card.dataset.card); });
  $('confirm-cast').onclick = () => { if (selectedCard) perform({ type: 'cast', cardId: selectedCard }); };
  $('end-turn').onclick = () => perform({ type: 'endTurn' });
  $('hint').onclick = showHint; $('help').onclick = showHelp; $('settings').onclick = showSettings; $('restart').onclick = showRestart;
  $('stage-progress').onclick = showProgress; $('player-detail').onclick = () => showDetail('player'); $('enemy-detail').onclick = () => showDetail('enemy'); $('intent-detail').onclick = () => showDetail('enemy');
  document.addEventListener('keydown', e => {
    if (e.ctrlKey || e.metaKey || e.altKey || dialog.open || busy || /INPUT|TEXTAREA|SELECT/.test(e.target.tagName)) return;
    const inBoard = e.target.closest?.('#board');
    if (inBoard && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
      e.preventDefault(); const row = Math.floor(cursor / 6), col = cursor % 6;
      if (e.key === 'ArrowUp' && row > 0) cursor -= 6;
      if (e.key === 'ArrowDown' && row < 5) cursor += 6;
      if (e.key === 'ArrowLeft' && col > 0) cursor--;
      if (e.key === 'ArrowRight' && col < 5) cursor++;
      render(); $('board').children[cursor].focus(); return;
    }
    if (inBoard && [' ', 'Enter'].includes(e.key)) { e.preventDefault(); selectTile(cursor); return; }
    if (e.key >= '1' && e.key <= '3') {
      e.preventDefault(); selectCard(state.cards[Number(e.key) - 1]);
      if (!$('confirm-cast').disabled) $('confirm-cast').focus();
      else $('cards').children[Number(e.key) - 1].focus();
    }
    else if (e.key.toLowerCase() === 'h') { e.preventDefault(); showHint(); }
    else if (e.key.toLowerCase() === 'e') { e.preventDefault(); perform({ type: 'endTurn' }); }
    else if (e.key === 'Enter' && selectedCard && !e.target.closest('button,a')) { e.preventDefault(); perform({ type: 'cast', cardId: selectedCard }); }
    else if (e.key === 'Escape') { e.preventDefault(); pause(); }
  });
  window.addEventListener('pagehide', save);
  const resumed = restore(); save(); render();
  window.DaoyouDemo = Object.freeze({ version: E.DATA.version, getState: () => clone(state), getBusy: () => busy });
  notify(resumed ? '已续上次竹林体验，按「规则」可查看操作。' : '交换相邻灵珠凑三枚；紫灵攒墨，三式可施放。', 0);
  if (state.status !== 'playing') setTimeout(showResult, 200);
})();
