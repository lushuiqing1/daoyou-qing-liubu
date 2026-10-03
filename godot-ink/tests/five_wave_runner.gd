extends SceneTree
const Model = preload("res://scripts/ink_engine.gd")
const Legacy = preload("res://tests/migration_v1_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
var checks = 0
var failures: Array = []
var balance: Array = []
func _init(): call_deferred("run")
func check(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message); printerr("FAIL: "+message)
func apply(model, action: Dictionary) -> Dictionary:
	var result = model.dispatch(action)
	if result.ok and action.type == "newRun": force_rule2(model)
	check(result.ok,"Action accepted: "+JSON.stringify(action))
	check(Store.validate(model.state,model),"Valid state after "+str(action.type))
	return result
func force_rule2(model):
	model.state.run.rulesVersion = 2
	model.state.battle.rulesVersion = 2
	model.state.battle.enemy.intentKind = ""; model.state.battle.enemy.nextDamage = 0
	model.announce_intent(model.state.battle)
func start_rule2(model):
	model.dispatch({"type":"newRun"}); force_rule2(model)
func retained_profile(old: Dictionary, upgraded: Dictionary) -> bool:
	for key in old:
		if key == "records":
			for record in old.records:
				if upgraded.records.get(record) != old.records[record]: return false
		elif upgraded.get(key) != old[key]: return false
	return true
func kill_one(model):
	model.state.battle.enemy.hp = 1; model.state.battle.mana = 7
	apply(model,{"type":"card","uid":model.state.battle.hand[0].uid})
func match_board(model, count: int) -> Array:
	var board = []
	for i in range(36): board.append({"id":i+1,"type":model.d.types[(i/6+2*(i%6))%5]})
	for i in range(count): board[i].type = "red"
	return board
func run():
	for seed_value in range(40):
		var model = Model.new(seed_value+1); apply(model,{"type":"newRun"})
		check(model.state.battle.enemy.hp == 99 and model.state.battle.enemy.damage == 14,"Beginner first enemy tuning")
		check(model.matches(model.state.battle.board).is_empty() and not model.possible_move(model.state.battle.board).is_empty(),"Playable board")
		var before = model.state.duplicate(true)
		check(not model.dispatch({"type":"enterNode","id":"boss"}).ok and model.state == before,"Cannot skip monsters")
		check(not model.dispatch({"type":"swap","a":5,"b":6}).ok and model.state == before,"No row wrap")
		var pair = model.possible_move(model.state.battle.board); apply(model,{"type":"swap","a":pair[0],"b":pair[1]})
		check(model.state.run.moves == 1,"One swap counted once")
	var m = Model.new(88); apply(m,{"type":"newRun"}); var equipped = m.state.run.deck.duplicate()
	for chapter in range(4):
		var previous_hp = 0; var previous_damage = 0
		for wave in range(1,6):
			var s = m.state; var enemy = s.battle.enemy
			check(s.run.chapter == chapter and s.run.wave == wave,"Five ordered enemies")
			check(enemy.maxHp > previous_hp and enemy.damage > previous_damage,"Each enemy stronger than previous")
			check((enemy.type == "boss") == (wave == 5),"Only fifth is Boss")
			previous_hp = enemy.maxHp; previous_damage = enemy.damage; s.profile.hp = 50
			s.battle.steps = 2; s.battle.shield = 4; s.battle.bonusSteps = 1
			var board = s.battle.board.duplicate(true); var hand = s.battle.hand.duplicate(true); kill_one(m)
			check(m.state.profile.hp == mini(m.stats().maxHp,50+roundi(m.stats().maxHp*0.1)),"10 percent victory heal")
			if wave < 5:
				check(m.state.battle != null and m.state.run.pendingReward == null,"No normal-enemy reward modal")
				check(m.state.battle.board == board and m.state.battle.hand == hand,"Board and skills retained")
				check(m.state.battle.mana == 4 and m.state.battle.steps == 2 and m.state.battle.shield == 4 and m.state.battle.bonusSteps == 1,"All turn resources retained")
			else:
				check(m.state.battle == null and m.state.run.pendingReward.chapterComplete,"Boss ends chapter")
				check(m.state.profile.collection[m.d.chapters[chapter].fixedUnlock] == 1,"Fixed skill unlocked")
				var before = m.state.duplicate(true)
				check(not m.dispatch({"type":"reward","id":"sword"}).ok and m.state == before,"Invalid reward transactional")
				apply(m,{"type":"reward","id":""})
				if chapter < 3:
					check(m.state.battle == null and m.state.run.chapter == chapter+1,"Preparation between chapters")
					m.state.profile.coins += 200; apply(m,{"type":"cultivate"}); apply(m,{"type":"buyItem","id":"spring_pill"})
					check(m.state.run.deck == equipped,"Three skills stay locked"); apply(m,{"type":"enterNode","id":"f1"})
	check(m.state.run == null and m.state.profile.records.wins == 20 and m.state.profile.records.clears == 1,"Exactly 20 victories per complete run")
	for chapter in range(4):
		var pm = Model.new(100+chapter); start_rule2(pm); pm.state.run.chapter = chapter
		for n in pm.d.nodes:
			pm.state.run.nodes = pm.node_states()
			for previous in pm.d.nodes:
				if previous.level < n.level: pm.state.run.nodes[previous.id] = "passed"
			pm.start_battle(pm.state,n); var pattern = pm.intent_pattern()
			for round_number in range(1,pattern.size()*2+1):
				check(pm.state.battle.enemy.intentKind == pattern[(round_number-1)%pattern.size()],"Chapter-specific pattern")
				pm.state.battle.shield = 10000; apply(pm,{"type":"endTurn"})
			if n.id == "boss":
				var b = pm.state.battle; b.round = pattern.find("charge")+1; b.enemyRound = b.round; pm.announce_intent(b)
				var locked = b.enemy.nextDamage; b.enemy.hp = b.enemy.maxHp/2; pm.check_enrage(pm.state)
				apply(pm,{"type":"endTurn"})
				check(pm.state.battle.enemy.phase == "enraged" and pm.state.battle.enemy.intent == locked,"Enrage preserves heavy telegraph")
	var sm = Model.new(909); start_rule2(sm)
	sm.state.battle.enemy.hp = 100000; sm.state.battle.enemy.maxHp = 100000; sm.state.seq = maxi(sm.state.seq,100)
	var base_steps = sm.state.battle.steps
	for attempt in range(3):
		sm.state.battle.board = match_board(sm,4); check(sm.resolve(sm.state),"Four-match resolves")
		check(sm.state.battle.bonusSteps <= 2,"Two-step refund cap")
	check(sm.state.battle.steps == base_steps+2,"Refund total is two")
	apply(sm,{"type":"endTurn"}); check(sm.state.battle.bonusSteps == 0,"Refund budget resets")
	check(not sm.has_long_match(match_board(sm,3)),"Three-match no refund")
	var cascade = Model.new(555); start_rule2(cascade)
	cascade.state.battle.board = match_board(cascade,4); cascade.state.battle.enemy.hp = 1
	check(cascade.resolve(cascade.state),"Winning cascade continues")
	check(cascade.state.run.wave >= 2 and Store.validate(cascade.state,cascade),"Cascades finish before save")
	var defeat = Model.new(777); start_rule2(defeat); defeat.state.profile.hp = 1; defeat.state.battle.shield = 0
	apply(defeat,{"type":"endTurn"})
	check(defeat.state.run == null and defeat.state.lastResult.kind == "defeat","Defeat ends all remaining waves")
	var revive = Model.new(778); start_rule2(revive); revive.state.run.treasures.append("revive")
	revive.state.profile.hp = 1; revive.state.battle.shield = 0; apply(revive,{"type":"endTurn"})
	check(revive.state.run.reviveUsed and revive.state.profile.hp == 50 and revive.state.run.wave == 1,"Revive preserves current enemy")
	revive.state.profile.hp = 1; revive.state.battle.shield = 0; revive.state.battle.enemyRound = 1; revive.announce_intent(revive.state.battle)
	apply(revive,{"type":"endTurn"}); check(revive.state.run == null and revive.state.lastResult.kind == "defeat","Revive can only trigger once")
	for card in m.d.cards:
		var cm = Model.new(77)
		for c in cm.d.cards: cm.state.profile.collection[c.id] = 1
		var deck = [card.id]
		for c in cm.d.cards:
			if c.id not in deck and deck.size() < 3: deck.append(c.id)
		cm.state.profile.deck = deck; start_rule2(cm)
		cm.state.battle.enemy.maxHp = 10000; cm.state.battle.enemy.hp = 10000; cm.state.profile.hp = 30; cm.state.battle.mana = 7
		var uid = cm.state.battle.hand[0].uid; apply(cm,{"type":"card","uid":uid})
		check(cm.state.battle.mana == 7-card.cost,"All skill costs correct")
		if cm.state.battle.mana >= card.cost: apply(cm,{"type":"card","uid":uid})
		check(cm.state.battle.hand.size() == 3,"All skills reusable")
	var legacy_cases = []
	for node in ["f1","f2","f3","elite","boss"]:
		var old = Legacy.new(222); old.dispatch({"type":"newRun"}); old.state.run.nodes[node] = "available"
		old.dispatch({"type":"enterNode","id":node}); legacy_cases.append(old.state.duplicate(true))
	var old_reward = Legacy.new(444); old_reward.dispatch({"type":"newRun"}); old_reward.dispatch({"type":"enterNode","id":"f1"})
	old_reward.state.battle.enemy.hp = 1; old_reward.dispatch({"type":"card","uid":old_reward.state.battle.hand[0].uid}); legacy_cases.append(old_reward.state.duplicate(true))
	for value in legacy_cases:
		var current = Model.new(); check(Store.validate(value,current),"Old native save recognized")
		var upgraded = current.upgrade_state(value); check(Store.validate(upgraded,current),"Old native save upgrades")
		check(retained_profile(value.profile,upgraded.profile),"All historical profile progress preserved")
		var legacy_path = "res://verification/test-old-five-wave.json"
		check(Store.save_state(value,legacy_path) == OK,"Write isolated old native fixture")
		check(Store.read_state(current,legacy_path) == upgraded,"Read and upgrade actual old native file")
		if upgraded.run.pendingReward != null:
			current.state = upgraded; apply(current,{"type":"reward","id":""})
			check(current.state.run.wave == 2 and current.state.battle != null,"Old reward resumes second enemy")
	DirAccess.remove_absolute("res://verification/test-old-five-wave.json")
	DirAccess.remove_absolute("res://verification/test-old-five-wave.backup.json")
	var new_save = Model.new(12); start_rule2(new_save); kill_one(new_save)
	var save_path = "res://verification/test-five-wave-progress.json"
	check(Store.save_state(new_save.state,save_path) == OK,"Save second enemy")
	check(Store.read_state(new_save,save_path) == new_save.state,"Resume exact second enemy"); DirAccess.remove_absolute(save_path)
	for key in ["wave","flowVersion","chapterCoins"]:
		var broken = new_save.state.duplicate(true); broken.run[key] = "bad"; check(not Store.validate(broken,new_save),"Reject invalid "+key)
	var broken_battle = new_save.state.duplicate(true); broken_battle.battle = "bad"
	check(not Store.validate(broken_battle,new_save),"Reject bad battle without crash")
	var broken_reward = new_save.state.duplicate(true); broken_reward.run.pendingReward = "bad"
	check(not Store.validate(broken_reward,new_save),"Reject bad reward without crash")
	for seed_value in range(24):
		balance.append(play_run(91001+seed_value*97))
		if seed_value%8 == 7: print("Balance simulation: ",seed_value+1," / 24")
	var file = FileAccess.open("res://verification/engine.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"rulesVersion":2,"suite":"historical-rules2","checks":checks,"failures":failures,"balance":balance,"method":"Frozen rules2 regression; current rules3 acceptance is content_runner. Heuristic simulations are not human playtests"},"\t")); file.close()
	print("Historical rules2 five-wave engine: ",checks," checks; failures: ",failures.size()); quit(1 if not failures.is_empty() else 0)
func best_swap(model) -> Array:
	var board = model.state.battle.board; var b = model.state.battle; var stats = model.stats(); var best = []; var best_score = -INF
	for left in range(36):
		for right in [left+1 if left%6 < 5 else -1,left+6 if left < 30 else -1]:
			if right < 0: continue
			var copy = board.duplicate(); var temp = copy[left]; copy[left] = copy[right]; copy[right] = temp
			var indices = model.matches(copy)
			if indices.is_empty(): continue
			var score = 0.0
			for index in indices:
				match copy[index].type:
					"red": score += stats.attack*(0.6 if b.enemy.shield > 0 else 1.2)
					"green": score += stats.heal*(1.5 if model.state.profile.hp < stats.maxHp*0.65 else 0.05)
					"blue": score += stats.shield*(0.9 if b.enemy.intent > b.shield else 0.05)
					"yellow": score += 1.7
					"purple": score += model.card_value("sword")/3.0*(1.0 if b.mana < 5 else 0.02)
			if model.has_long_match(copy): score += 12
			if score > best_score: best_score = score; best = [left,right]
	return best
func play_run(seed_value: int) -> Dictionary:
	var model = Model.new(seed_value); start_rule2(model); var actions = 0; var turns = 0; var chapters = []; var chapter_start = 0
	while model.state.run != null and actions < 2500:
		actions += 1
		if model.state.run.pendingReward != null:
			chapters.append({"chapter":model.state.run.chapter+1,"turns":turns-chapter_start,"hp":model.state.profile.hp,"realm":model.state.profile.realm}); chapter_start = turns
			model.dispatch({"type":"reward","id":""}); continue
		if model.state.battle == null:
			while model.state.profile.realm < 9 and model.state.profile.coins >= model.d.realms[model.state.profile.realm].cost: model.dispatch({"type":"cultivate"})
			for id in ["aura","jade","qingming","robe","swordArt","ice","revive","incense"]:
				if not model.has(model.state,id) and model.state.profile.coins >= model.treasures[id].price: model.dispatch({"type":"buyTreasure","id":id})
			model.dispatch({"type":"enterNode","id":"f1"}); continue
		var b = model.state.battle; var stats = model.stats(); var hp = model.state.profile.hp
		if hp < stats.maxHp*0.7 and b.mana >= model.card_cost("heal"):
			model.dispatch({"type":"card","uid":b.hand[2].uid}); continue
		var sword_cost = model.card_cost("sword")
		if b.mana >= sword_cost and (b.enemy.hp <= model.card_value("sword") or b.mana >= 6 or (b.steps == 0 and hp > stats.maxHp*0.55 and b.enemy.intent <= b.shield+stats.armor+hp*0.4)):
			model.dispatch({"type":"card","uid":b.hand[0].uid}); continue
		if b.steps > 0:
			var pair = best_swap(model)
			if pair.is_empty(): break
			model.dispatch({"type":"swap","a":pair[0],"b":pair[1]}); continue
		if b.enemy.intent > b.shield+stats.armor and b.mana >= model.card_cost("ward"):
			model.dispatch({"type":"card","uid":b.hand[1].uid}); continue
		model.dispatch({"type":"endTurn"}); turns += 1
	var result = model.state.lastResult.get("kind","timeout") if model.state.lastResult != null else "timeout"
	check(result != "timeout","Simulation terminates"); check(Store.validate(model.state,model),"Simulation final state valid")
	return {"seed":seed_value,"result":result,"actions":actions,"enemyTurns":turns,"chapters":chapters,"wins":model.state.profile.records.wins,"realm":model.state.profile.realm}
