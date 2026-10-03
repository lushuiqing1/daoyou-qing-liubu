class_name TrialSession
extends RefCounted
## Owns the independent trial model and recoverable stamp receipt journal.
const Model = preload("res://scripts/ink_engine.gd")
const Store = preload("res://scripts/trial_store.gd")
const Progress = preload("res://scripts/progress_store.gd")
var engine: InkEngine = null
var persistence: bool = true
var receipt_committed: bool = false
var last_error: String = ""
var writes_blocked: bool = false
var save_path: String = Store.SAVE
var normal_save_path: String = Progress.SAVE

func has_session() -> bool:
	return engine != null and engine.state.has("trial")

func load() -> bool:
	last_error = ""; writes_blocked = false
	if not persistence: return has_session()
	var reader = Model.new()
	var loaded = Store.read_result(reader,save_path)
	last_error = loaded.error; writes_blocked = loaded.blocked
	if loaded.envelope.is_empty(): engine = null; receipt_committed = false; return false
	reader.state = loaded.envelope.engineState
	engine = reader; receipt_committed = loaded.envelope.receiptCommitted
	return true

func start_reason(normal: InkEngine) -> String:
	if writes_blocked: return last_error if not last_error.is_empty() else "试炼保存受保护，暂不可开始"
	if normal == null: return "未读取普通进度"
	if normal.state.profile.records.clears <= 0: return "普通四境通关后开启试炼"
	if normal.state.run != null: return "请先完成或结束普通历练"
	if persistence and normal_save_path == Progress.SAVE and Progress.writes_blocked: return Progress.last_error
	return ""

func can_start(normal: InkEngine) -> bool:
	return start_reason(normal).is_empty()

func start(id: String, normal: InkEngine) -> bool:
	last_error = start_reason(normal)
	if not last_error.is_empty(): return false
	if not reconcile(normal): return false
	var next_engine = Model.new()
	var session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var result = next_engine.start_trial(id,session_id)
	if not result.ok: last_error = result.notice; return false
	next_engine.state.settings.sound = normal.state.settings.sound
	next_engine.state.settings.reducedMotion = normal.state.settings.reducedMotion
	var previous = engine; var previous_receipt = receipt_committed
	engine = next_engine; receipt_committed = false
	if not save(): engine = previous; receipt_committed = previous_receipt; return false
	return true

func envelope() -> Dictionary:
	return {"schema":Store.FORMAT,"engineState":engine.state.duplicate(true),"receiptCommitted":receipt_committed} if has_session() else {}

func save() -> bool:
	if not has_session(): return true
	if writes_blocked: return false
	if not Store.validate(envelope(),engine): last_error = "试炼进度校验失败，未覆盖存档"; return false
	if not persistence: last_error = ""; return true
	var error = Store.save_state(envelope(),engine,save_path)
	if error != OK: last_error = "试炼保存失败（%d）：%s"%[error,ProjectSettings.globalize_path(save_path)]; return false
	last_error = ""; return true

func reconcile(normal: InkEngine) -> bool:
	if not has_session(): return true
	var receipt = engine.trial_result_info()
	if receipt.is_empty() or not receipt.qualified: return true
	# The completed result must exist in the independent journal before touching normal progress.
	if not save(): return false
	if normal == null: last_error = "普通进度不可用，获章结果已保留待补记"; return false
	var has_token = normal.state.profile.records.get("trialReceipts",{}).get(receipt.sessionId,false)
	if not has_token:
		if persistence and normal_save_path == Progress.SAVE and Progress.writes_blocked:
			last_error = "普通进度保存受保护，获章结果已保留待补记："+Progress.last_error; return false
		var before = normal.state.duplicate(true)
		var accepted = normal.dispatch({"type":"awardTrial","receipt":receipt})
		if not accepted.ok: last_error = accepted.notice; return false
		if not Progress.validate(normal.state,normal):
			normal.state = before; last_error = "印章补记校验失败，普通进度已撤回"; return false
		if persistence:
			var error = Progress.save_state(normal.state,normal_save_path)
			if error != OK:
				normal.state = before; last_error = "普通进度保存失败（%d），获章结果已保留待补记"%error; return false
	var previous_receipt = receipt_committed
	receipt_committed = true
	if not save(): receipt_committed = previous_receipt; return false
	return true
