extends RefCounted
## A separate native trial journal. No import of ordinary progress.
const Progress = preload("res://scripts/progress_store.gd")
const SAVE = "user://trial-v1.json"
const BACKUP = "user://trial-v1.backup.json"
const FORMAT = "daoyou-trial-v1"
static var last_error: String = ""
static var writes_blocked: bool = false
static var _blocked_paths: Dictionary = {}
static var _recovered_backups: Dictionary = {}

static func read_result(engine: InkEngine, save_path: String = SAVE) -> Dictionary:
	var found = false
	for path in [save_path,save_path.get_basename()+".backup.json"]:
		if not FileAccess.file_exists(path): continue
		found = true
		var parser = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var envelope = InkEngine.normalize_numbers(parser.data)
		if not validate(envelope,engine): continue
		_blocked_paths.erase(save_path)
		if path != save_path: _recovered_backups[save_path] = true
		if save_path == SAVE: last_error = ""; writes_blocked = false
		return {"envelope":envelope,"error":"","blocked":false}
	var message = ""
	if found:
		_blocked_paths[save_path] = true
		message = "试炼进度与备份均无法读取，已停止试炼保存。请保留文件并从有效备份恢复："+ProjectSettings.globalize_path(save_path)
	else: _blocked_paths.erase(save_path)
	if save_path == SAVE: last_error = message; writes_blocked = found
	return {"envelope":{},"error":message,"blocked":found}

static func read_state(engine: InkEngine, save_path: String = SAVE) -> Dictionary:
	return read_result(engine,save_path).envelope

static func save_state(envelope: Dictionary, engine: InkEngine, save_path: String = SAVE) -> Error:
	if _blocked_paths.has(save_path): return ERR_FILE_CORRUPT
	if not validate(envelope,engine): return ERR_INVALID_DATA
	var file = FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(envelope)); file.flush()
	var write_error = file.get_error(); file.close()
	if write_error != OK: return write_error
	if FileAccess.file_exists(save_path) and not _recovered_backups.has(save_path):
		var backup_error = DirAccess.copy_absolute(save_path,save_path.get_basename()+".backup.json")
		if backup_error != OK: return backup_error
	var error = DirAccess.rename_absolute(save_path+".tmp",save_path)
	if error == OK: _recovered_backups.erase(save_path)
	if save_path == SAVE: last_error = "" if error == OK else "试炼保存失败（%d）：%s"%[error,ProjectSettings.globalize_path(save_path)]
	return error

static func validate(envelope: Variant, engine: InkEngine) -> bool:
	if not envelope is Dictionary or not envelope.get("schema") is String or envelope.schema != FORMAT or not envelope.get("receiptCommitted") is bool: return false
	var s = envelope.get("engineState")
	if not Progress.validate(s,engine,true): return false
	if not s.get("trial") is Dictionary: return false
	var metadata = s.trial
	if not metadata.get("id") is String: return false
	var definition = engine.trial_definition(metadata.id)
	if definition.is_empty() or not metadata.get("seed") is int or metadata.seed != definition.seed: return false
	if not metadata.get("sessionId") is String or metadata.sessionId.strip_edges().is_empty() or metadata.sessionId.length() > 128: return false
	if not metadata.get("result") is Dictionary: return false
	var p = s.profile
	if p.realm != definition.realm or p.deck != definition.deck or p.get("cultivationPath") != "none": return false
	if p.equipment != {"weapon":"wood_sword","armor":"cloth","accessory":"jade"} or p.legacy != {"hp":0,"attack":0,"armor":0}: return false
	for id in p.inventory:
		if not engine.items.has(id) or p.inventory[id] != (1 if id in ["wood_sword","cloth","jade"] else 0): return false
	for id in engine.cards:
		if p.collection[id] != 1: return false
	if s.settings.get("guide",{}).get("enabled",true): return false
	if s.run != null:
		if s.run.chapter != definition.chapter or s.run.get("rulesVersion") != 4 or s.run.get("cultivationPath") != "none": return false
		if s.run.deck != definition.deck or s.run.treasures != definition.treasures or s.run.pendingReward != null: return false
		if s.battle == null or s.lastResult != null or not metadata.result.is_empty() or envelope.receiptCommitted: return false
		if not Progress.cultivation_valid(s.battle.get("cultivation"),"none",definition.realm): return false
		if s.run.summary.coverage != "full" or s.run.summary.startChapter != definition.chapter or s.run.summary.startWave != 1: return false
	else:
		if s.lastResult == null or s.lastResult.chapter != definition.chapter or metadata.result.is_empty(): return false
		var result = engine.trial_result_info(s)
		if result.is_empty() or result != metadata.result: return false
		if s.lastResult.summary.coverage != "full" or s.lastResult.summary.startChapter != definition.chapter or s.lastResult.summary.startWave != 1 or s.lastResult.summary.deck != definition.deck: return false
		if s.lastResult.summary != p.records.lastSummary: return false
		if envelope.receiptCommitted and not result.qualified: return false
	return true
