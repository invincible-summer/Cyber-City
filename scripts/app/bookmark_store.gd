## 摄影书签存储（chapter1-1 §7.7）。每地图最多 12 个；原子写 + 最近可读备份。
## 存储位置 user://camera_bookmarks.json，顶层 schema_version=1。
class_name BookmarkStore
extends RefCounted

const STORE_PATH := "user://camera_bookmarks.json"
const BACKUP_PATH := "user://camera_bookmarks.backup.json"
const SCHEMA_VERSION := 1
const MAX_PER_MAP := 12
const LABEL_MIN := 1
const LABEL_MAX := 40

var _cache: Dictionary = {}     # 解析后的库：{"schema_version":1, "bookmarks":[…]}
var _loaded := false


func list_bookmarks(map_id: StringName) -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for entry in _db().get("bookmarks", []):
		if entry is Dictionary and str(entry.get("map_id", "")) == String(map_id):
			out.append(_public_view(entry))
	return out


## 返回 {error: int, bookmark_id: String, message: String}；失败时 ID 为空。
func save_bookmark(label: String, pose: CameraPose, content_revision: String) -> Dictionary:
	if pose == null:
		return {"error": ERR_INVALID_PARAMETER, "bookmark_id": "", "message": "位姿为空（未绑定地图？）"}
	var errors := pose.validate()
	if not errors.is_empty():
		return {"error": ERR_INVALID_PARAMETER, "bookmark_id": "", "message": "位姿非法: %s" % "; ".join(errors)}
	var clean_label := label.strip_edges()
	if clean_label.length() < LABEL_MIN or clean_label.length() > LABEL_MAX:
		return {"error": ERR_INVALID_PARAMETER, "bookmark_id": "", "message": "名称需 1–40 个字符"}
	_ensure_loaded()
	var db := _db()
	var bookmarks: Array = db.get("bookmarks", [])
	var map_key := String(pose.map_id)
	var count := 0
	for entry in bookmarks:
		if entry is Dictionary and str(entry.get("map_id", "")) == map_key:
			count += 1
	if count >= MAX_PER_MAP:
		return {"error": ERR_OUT_OF_MEMORY, "bookmark_id": "", "message": "该地图书签已满（%d 个），请先删除" % MAX_PER_MAP}
	var bookmark_id := _new_id()
	bookmarks.append({
		"id": bookmark_id,
		"label": clean_label,
		"map_id": map_key,
		"content_revision": content_revision,
		"created_utc": Time.get_datetime_string_from_system(true).replace("T", " "),
		"pose": pose.to_dict(),
	})
	db["bookmarks"] = bookmarks
	var err := _atomic_write()
	if err != OK:
		return {"error": err, "bookmark_id": "", "message": "写入失败（err=%d）" % err}
	return {"error": OK, "bookmark_id": bookmark_id, "message": ""}


## 缺失或解析失败返回 null；UI 显示"书签不存在或数据无效"，保留当前相机。
func load_bookmark(bookmark_id: String) -> CameraPose:
	_ensure_loaded()
	for entry in _db().get("bookmarks", []):
		if entry is Dictionary and str(entry.get("id", "")) == bookmark_id:
			return CameraPose.from_dict(entry.get("pose"))
	return null


func delete_bookmark(bookmark_id: String) -> Error:
	_ensure_loaded()
	var db := _db()
	var bookmarks: Array = db.get("bookmarks", [])
	for i in bookmarks.size():
		var entry = bookmarks[i]
		if entry is Dictionary and str(entry.get("id", "")) == bookmark_id:
			bookmarks.remove_at(i)
			db["bookmarks"] = bookmarks
			return _atomic_write()
	return ERR_DOES_NOT_EXIST


# ============================ 内部 ============================

func _db() -> Dictionary:
	if _cache.is_empty():
		_cache = {"schema_version": SCHEMA_VERSION, "bookmarks": []}
	return _cache


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(STORE_PATH):
		return
	var txt := FileAccess.get_file_as_string(STORE_PATH)
	var parsed = JSON.parse_string(txt)
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != SCHEMA_VERSION or not parsed.get("bookmarks", []) is Array:
		# 损坏文件不覆盖为空：隔离副本，从备份恢复或以空库开始
		_quarantine_corrupt()
		return
	_cache = parsed


func _quarantine_corrupt() -> void:
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace(" ", "")
	var quarantine := "user://camera_bookmarks.corrupt-%s.json" % stamp
	DirAccess.copy_absolute(STORE_PATH, quarantine)
	push_warning("BookmarkStore: 书签文件损坏，已隔离到 %s" % quarantine)
	# 尝试备份恢复
	if FileAccess.file_exists(BACKUP_PATH):
		var backup_txt := FileAccess.get_file_as_string(BACKUP_PATH)
		var parsed = JSON.parse_string(backup_txt)
		if parsed is Dictionary and int(parsed.get("schema_version", 0)) == SCHEMA_VERSION:
			_cache = parsed
			_atomic_write()
			push_warning("BookmarkStore: 已从备份恢复 %d 条书签" % (_cache.get("bookmarks", []) as Array).size())
			return
	_cache = {"schema_version": SCHEMA_VERSION, "bookmarks": []}


func _atomic_write() -> Error:
	## 写临时文件，成功后替换；保留上一份最近可读备份。
	var tmp := STORE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_string(JSON.stringify(_db(), "  "))
	f.close()
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.copy_absolute(STORE_PATH, BACKUP_PATH)
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(STORE_PATH))
	return err


func _new_id() -> String:
	## 独立随机唯一标识，不以 label 作为文件路径。
	return "%08x%08x" % [randi(), randi()]


func _public_view(entry: Dictionary) -> Dictionary:
	return {
		"id": str(entry.get("id", "")),
		"label": str(entry.get("label", "")),
		"map_id": str(entry.get("map_id", "")),
		"content_revision": str(entry.get("content_revision", "")),
		"created_utc": str(entry.get("created_utc", "")),
	}
