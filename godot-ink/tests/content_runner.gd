extends SceneTree
const Model = preload("res://scripts/ink_engine.gd")
const Overflow = preload("res://tests/content_overflow_engine.gd")
const Store = preload("res://scripts/progress_store.gd")
const PATTERNS = [["ACH","CHA","AACH","AGCH","ACHG"],["GACH","AGCH","GAGACH","GAGCH","GCHGA"],["AACH","CHAA","AAACH","AAGCH","AACHG"],["AGCH","GAACH","GCHA","AGACH","GACH"]]
const ACTIONS = {"A":"attack","G":"guard","C":"charge","H":"heavy"}
var checks = 0
var failures: Array = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func apply(model, action: Dictionary) -> Dictionary:
	var result = model.dispatch(action)
	check(result.ok, "Accepted "+JSON.stringify(action))
	check(Store.validate(model.state, model), "Valid state after "+str(action.type))
	return result
func model_with(deck: Array):
	var model = Model.new(321)
	for id in model.cards: model.state.profile.collection[id] = 1
	model.state.profile.deck = deck.duplicate()
	apply(model,{"type":"newRun"})
	return model
func uid(model, id: String) -> int:
	for card in model.state.battle.hand:
		if card.cardId == id: return card.uid
	return -1
func set_wave(model, chapter: int, wave: int):
	model.state.run.chapter = chapter; model.state.run.nodes = model.node_states()
	for node in model.d.nodes:
		if node.level < wave-1: model.state.run.nodes[node.id] = "passed"
	model.start_battle(model.state,model.d.nodes[wave-1])
func match_board(model, kind: String, length: int = 3) -> Array:
	var board = []
	for i in range(36): board.append({"id":i+1,"type":model.d.types[(i/6+2*(i%6))%5]})
	for i in range(length): board[i].type = kind
	model.state.seq = maxi(model.state.seq,100)
	return board
func resolve_match(model, kind: String, length: int = 3):
	model.state.battle.board = match_board(model,kind,length)
	check(model.resolve(model.state), "Resolve controlled "+kind+" match")
	check(Store.validate(model.state,model), "Valid after controlled match")
func exhaust_chapter(model):
	for wave in range(5):
		model.state.battle.enemy.hp = 1; model.state.battle.mana = 7
		apply(model,{"type":"card","uid":uid(model,"sword")})
func run():
	test_patterns()
	test_presets_and_guide()
	test_links()
	test_summary_and_rollback()
	test_old_current_upgrade()
	var version = str(ProjectSettings.get_setting("application/config/version")).replace("godot-", "")
	var report = {"suite":"current-content","rulesVersion":Model.CURRENT_RULES,"checks":checks,"failures":failures,"playerProgressUntouched":true,"historicalSuite":"five_wave_runner rules2 and migration_v1_runner"}
	var file = FileAccess.open("res://verification/content-"+version+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("Current content rules",Model.CURRENT_RULES,": ",checks," checks; failures: ",failures.size())
	quit(1 if not failures.is_empty() else 0)
func test_patterns():
	for chapter in range(4):
		for wave in range(1,6):
			var model = model_with(["sword","ward","heal"]); set_wave(model,chapter,wave)
			var expected = []
			for letter in PATTERNS[chapter][wave-1]: expected.append(ACTIONS[letter])
			check(model.intent_pattern() == expected,"Exact pattern chapter %d wave %d"%[chapter,wave])
			var before = model.state.duplicate(true); model.next_enemy_preview(); check(model.state == before,"Preview is pure reading")
			check(model.next_enemy_preview().available == (wave < 5),"Preview availability")
			for turn in range(expected.size()*2):
				check(model.state.battle.enemy.intentKind == expected[turn%expected.size()],"Two cycles: chapter %d wave %d turn %d"%[chapter,wave,turn])
				if model.state.battle.enemy.intentKind == "guard":
					var ratio = 0.12 if chapter == 1 and wave == 3 else model.d.combat.chapters[chapter].guardRatio
					check(model.state.battle.enemy.intentShield == roundi(model.state.battle.enemy.maxHp*ratio),"Wave guard ratio")
				model.state.battle.shield = 10000; apply(model,{"type":"endTurn"})
			if wave == 5:
				var b = model.state.battle; b.enemyRound = expected.find("charge")+1; b.round = b.enemyRound
				b.enemy.intentKind = ""; b.enemy.nextDamage = 0; model.announce_intent(b)
				var locked = b.enemy.nextDamage; b.enemy.hp = b.enemy.maxHp/2; model.check_enrage(model.state)
				b.shield = 10000; apply(model,{"type":"endTurn"})
				check(model.state.battle.enemy.intentKind == "heavy" and model.state.battle.enemy.intent == locked,"Enrage preserves charged heavy in each chapter")
func test_presets_and_guide():
	var model = Model.new(444)
	var before = model.state.duplicate(true)
	check(not model.dispatch({"type":"deckPreset","id":"guard"}).ok and model.state == before,"Locked preset is atomic")
	check(not model.dispatch({"type":"deckPreset","id":"unknown"}).ok and model.state == before,"Unknown preset is atomic")
	for id in model.cards: model.state.profile.collection[id] = 1
	for preset in model.preset_list():
		apply(model,{"type":"deckPreset","id":preset.id}); check(model.state.profile.deck == preset.deck,"Atomic three-card preset "+preset.id)
	apply(model,{"type":"guideProgress","id":"swap"})
	apply(model,{"type":"guideProgress","id":"swap"}); check(model.state.settings.guide.seen.count("swap") == 1,"Guide checkpoint deduplicates")
	apply(model,{"type":"guideSkip"}); check(not model.state.settings.guide.enabled,"Guide skip persists")
	apply(model,{"type":"newRun"}); before = model.state.duplicate(true)
	check(not model.dispatch({"type":"deckPreset","id":"starter"}).ok and model.state == before,"Preset locked during entire run")
	check(model.state.run.rulesVersion == Model.CURRENT_RULES and model.state.battle.rulesVersion == Model.CURRENT_RULES,"New run chooses current rules")
func test_links():
	var sword = model_with(["sword","ward","heal"])
	var base_damage = sword.card_value("sword")
	resolve_match(sword,"blue",4)
	check(sword.state.battle.links.swordReady,"Any-color four match arms sword")
	resolve_match(sword,"blue",4); sword.state.battle.enemy.maxHp = 1000; sword.state.battle.enemy.hp = 1000; sword.state.battle.mana = 7
	var damage = sword.card_value("sword"); var hp = sword.state.battle.enemy.hp
	check(damage == base_damage+10,"Repeated four matches refresh exactly +10 without stacking")
	apply(sword,{"type":"card","uid":uid(sword,"sword")})
	check(hp-sword.state.battle.enemy.hp == damage,"Sword consumes one refreshable +10")
	check(not sword.state.battle.links.swordReady and sword.state.run.summary.links.sword == 1,"Sword bonus consumption recorded")
	var no_sword = model_with(["ward","ironwall","golden"]); resolve_match(no_sword,"blue",4)
	check(not no_sword.state.battle.links.swordReady,"Four match needs equipped sword")
	var inheritance = model_with(["sword","ironwall","spiritArray"])
	inheritance.state.battle.mana = 7; apply(inheritance,{"type":"card","uid":uid(inheritance,"ironwall")}); apply(inheritance,{"type":"card","uid":uid(inheritance,"spiritArray")})
	resolve_match(inheritance,"blue",4)
	var links = inheritance.state.battle.links.duplicate(true); inheritance.state.battle.enemy.hp = 0; inheritance.win(inheritance.state)
	check(inheritance.state.run.wave == 2 and inheritance.state.battle.links == links,"Three link states carry within same player turn")
	apply(inheritance,{"type":"endTurn"}); check(inheritance.state.battle.links == inheritance.empty_links(),"Every turn clears three link states")
	var ward = model_with(["ironwall","ward","heal"])
	ward.state.battle.mana = 7; apply(ward,{"type":"card","uid":uid(ward,"ironwall")}); ward.state.battle.shield = 10
	apply(ward,{"type":"endTurn"}); check(ward.state.run.summary.links.ward == 1 and ward.state.battle.mana == 6,"Broken positive shield refunds one mana")
	var expiration = model_with(["ironwall","ward","heal"])
	expiration.state.battle.mana = 7; apply(expiration,{"type":"card","uid":uid(expiration,"ironwall")}); expiration.state.battle.shield = 100
	apply(expiration,{"type":"endTurn"}); check(expiration.state.run.summary.links.ward == 0 and expiration.state.battle.mana == 5,"Natural shield expiration never refunds")
	var unshielded = model_with(["ironwall","ward","heal"])
	unshielded.state.battle.mana = 7; apply(unshielded,{"type":"card","uid":uid(unshielded,"ironwall")}); unshielded.state.battle.shield = 0
	apply(unshielded,{"type":"endTurn"}); check(unshielded.state.run.summary.links.ward == 0,"No refund from zero shield")
	var capped = model_with(["ironwall","ward","heal"])
	capped.state.battle.mana = 7; apply(capped,{"type":"card","uid":uid(capped,"ironwall")}); capped.state.battle.mana = 7; capped.state.battle.shield = 10
	apply(capped,{"type":"endTurn"}); check(capped.state.battle.mana == 7 and capped.state.run.summary.links.ward == 1 and capped.state.run.summary.manaOverflow == 1,"Ward refund obeys mana cap and records overflow")
	var already_refunded = model_with(["ironwall","ward","heal"])
	already_refunded.state.battle.mana = 7; apply(already_refunded,{"type":"card","uid":uid(already_refunded,"ironwall")}); already_refunded.state.battle.links.wardRefunded = true; already_refunded.state.battle.shield = 10
	apply(already_refunded,{"type":"endTurn"}); check(already_refunded.state.battle.mana == 5 and already_refunded.state.run.summary.links.ward == 0,"Ward cannot refund a second time in one turn")
	var purple = model_with(["spiritArray","flame","heal"])
	purple.state.battle.mana = 7; apply(purple,{"type":"card","uid":uid(purple,"spiritArray")}); apply(purple,{"type":"card","uid":uid(purple,"spiritArray")})
	resolve_match(purple,"purple")
	check(purple.state.run.summary.links.purple == 1 and not purple.state.battle.links.purpleReady,"Purple refresh does not stack")
	purple.state.battle.mana = 7; apply(purple,{"type":"card","uid":uid(purple,"spiritArray")}); purple.state.battle.mana = 7
	var overflow = purple.state.run.summary.manaOverflow; resolve_match(purple,"purple")
	check(purple.state.battle.mana == 7 and not purple.state.battle.links.purpleReady and purple.state.run.summary.manaOverflow >= overflow+4,"Capped purple consumes bonus and records overflow")
	var chapter = model_with(["sword","ward","heal"]); exhaust_chapter(chapter)
	apply(chapter,{"type":"reward","id":""}); apply(chapter,{"type":"enterNode","id":"f1"})
	check(chapter.state.battle.links == chapter.empty_links(),"New chapter clears link states")
func test_summary_and_rollback():
	var model = model_with(["sword","ward","heal"])
	model.state.profile.hp = 99; model.state.battle.mana = 7
	apply(model,{"type":"card","uid":uid(model,"heal")}); check(model.state.run.summary.healed == 1,"Healing records actual gain")
	model.state.battle.enemy.hp = 2; model.state.battle.mana = 7
	apply(model,{"type":"card","uid":uid(model,"sword")}); check(model.state.run.summary.damage == 2,"Damage excludes overkill")
	check(model.state.run.summary.casts.heal == 1 and model.state.run.summary.casts.sword == 1,"Casts counted by card")
	var defense = model_with(["sword","ward","heal"]); defense.state.battle.shield = 100
	apply(defense,{"type":"endTurn"}); check(defense.state.run.summary.blocked == 14 and defense.state.run.summary.shieldExpired == 86 and defense.state.run.summary.hpLost == 0,"Block and expiration record actual amounts")
	var fatal = model_with(["sword","ward","heal"]); fatal.state.profile.hp = 1; fatal.state.battle.shield = 0; fatal.state.battle.mana = 2
	apply(fatal,{"type":"endTurn"}); var summary = fatal.state.lastResult.summary
	check(summary.hpLost == 1 and summary.fatal.loss == 1 and summary.fatal.mana == 2,"Fatal records actual HP lost and pre-action mana")
	check(summary.fatal.defensiveCard == "ward" and summary.fatal.healCard == "heal","Fatal hints only genuinely usable cards")
	check(summary == fatal.state.profile.records.lastSummary and not fatal.summary_text(summary).is_empty(),"Final and recent summary match")
	var unavailable = model_with(["sword","ward","heal"]); unavailable.state.profile.hp = 1; unavailable.state.battle.shield = 0; unavailable.state.battle.mana = 0
	apply(unavailable,{"type":"endTurn"}); check(unavailable.state.lastResult.summary.fatal.defensiveCard == null and unavailable.state.lastResult.summary.fatal.healCard == null,"No invented affordable-card advice")
	var rollback = Overflow.new(42); apply(rollback,{"type":"newRun"})
	rollback.state.battle.enemy.maxHp = 1000000; rollback.state.battle.enemy.hp = 1000000
	var pair = rollback.possible_move(rollback.state.battle.board); var before = rollback.state.duplicate(true)
	check(not rollback.dispatch({"type":"swap","a":pair[0],"b":pair[1]}).ok,"Excessive cascade rejects action")
	check(rollback.state == before,"Rollback preserves RNG, profile and complete summary")
	for field in ["healed","hpLost","casts","links","deck"]:
		var bad = model.state.duplicate(true)
		bad.run.summary[field] = "invalid"
		check(not Store.validate(bad,model),"Reject malformed summary "+field)
func test_old_current_upgrade():
	var current = model_with(["sword","ward","heal"]); set_wave(current,3,5)
	current.state.run.rulesVersion = 2; current.state.battle.rulesVersion = 2
	var b = current.state.battle; b.enemyRound = 3; b.round = 3; b.enemy.intentKind = ""; b.enemy.nextDamage = 0; current.announce_intent(b)
	var old = current.state.duplicate(true)
	old.settings.erase("guide"); old.profile.records.erase("lastSummary"); old.run.erase("summary"); old.run.erase("rulesVersion"); old.battle.erase("links")
	check(Store.validate(old,current),"Original flow2 save with absent optional fields validates")
	var original_battle = old.battle.duplicate(true); var upgraded = current.upgrade_state(old)
	var upgraded_battle = upgraded.battle.duplicate(true); upgraded_battle.erase("links")
	check(original_battle == upgraded_battle,"Old current battle, RNG and locked telegraph preserved exactly")
	check(upgraded.run.rulesVersion == 2 and upgraded.run.summary.coverage == "partial" and not upgraded.settings.guide.enabled,"Migrated current run keeps rule2, partial recap and guide disabled")
	check(Store.validate(upgraded,current),"Upgraded current run validates")
	current.state = upgraded; apply(current,{"type":"abandon"}); apply(current,{"type":"newRun"})
	check(current.state.run.rulesVersion == Model.CURRENT_RULES,"Next run after old save uses new rules")
