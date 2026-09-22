## 仅编辑器加载的自动烘焙插件（chapter1-3 §4 BakeCoordinator 状态机）。
## 运行：godot --path . --editor -- --auto-bake [--scene res://path/to/scene.tscn]
## 原因：Godot 4.7.2 未把 LightmapGI.bake() 暴露给脚本，编辑器 UI 按钮是唯一入口；
## 本插件在编辑器内打开地图场景、选中 LightmapGI、程序化触发"烘焙光照贴图"按钮。
## chapter1-3 顺序（C13-02）：先校验 manifest v2 输入签名 → 先落 running 清单 →
## 才允许写空数据（fresh-load 重绑确认 user_count=0）→ 触发烘焙 → 覆盖判定 →
## save_scene 检查 Error → 终检 fresh-load → succeeded 清单 → 报告。
## manifest/report 任一写失败都是 bake 失败（C13-02 §4.4）；报告目录由
## NEON_ARTIFACT_DIR 指定（只允许 res://artifacts 下，§28.4）。
## 无 --auto-bake 参数时完全惰性。--auto-bake 是项目自定义参数（user args），不是引擎开关。
@tool
extends EditorPlugin

signal bake_started(job_id: String, map_id: StringName)
signal bake_finished(job_id: String, success: bool, report_path: String)

const BC := preload("res://tools/build_contract.gd")
const DEFAULT_SCENE := "res://maps/m01_afterglow/map.tscn"
const FALLBACK_REPORT_DIR := "res://artifacts/build"
const BAKE_TIMEOUT_SEC := 900.0  # 默认 15 分钟上限
const POLL_INTERVAL := 0.5

var _jobs: Dictionary = {}  # job_id -> {state, message, started_msec}


func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has("--auto-bake"):
		_run_auto_bake.call_deferred()


func request_bake(map_id: StringName, job_id: String) -> Error:
	## 编辑器内编程入口（编辑器工具/菜单可调用）。
	if _jobs.has(job_id) and str(_jobs[job_id].get("state", "")) == "running":
		return ERR_BUSY
	_jobs[job_id] = {"state": "running", "message": "", "started_msec": Time.get_ticks_msec()}
	bake_started.emit(job_id, map_id)
	_run_auto_bake_job(job_id, _scene_for_map(String(map_id)))
	return OK


func get_status(job_id: String) -> Dictionary:
	return _jobs.get(job_id, {"state": "unknown", "message": "无此任务"})


## 多地图（chapter1-2 §6）：场景统一放在 maps/<map_id>/map.tscn，
## 清单/烘焙数据/报告路径全部从场景路径推导。
func _scene_for_map(map_id: String) -> String:
	return "res://maps/%s/map.tscn" % map_id


func _manifest_for_scene(scene_path: String) -> String:
	return "%s/build_manifest.json" % scene_path.get_base_dir()


func _baked_data_for_scene(scene_path: String) -> String:
	return "%s/baked/map_lightmap.res" % scene_path.get_base_dir()


func _set_job(job_id: String, state: String, message: String) -> void:
	var job: Dictionary = _jobs.get(job_id, {"started_msec": Time.get_ticks_msec()})
	job["state"] = state
	job["message"] = message
	_jobs[job_id] = job


# ============================ 自动烘焙主流程 ============================

func _run_auto_bake() -> void:
	var job_id := "bake-%s" % Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace(" ", "")
	_run_auto_bake_job(job_id, _scene_path_from_args())


func _scene_path_from_args() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--scene" and i + 1 < args.size():
			return args[i + 1]
	return DEFAULT_SCENE


func _run_auto_bake_job(job_id: String, scene_path: String) -> void:
	_set_job(job_id, "running", "打开场景")
	print("NEON_BAKE[%s]: 编辑器就绪，打开场景 %s …" % [job_id, scene_path])
	await get_tree().create_timer(2.0).timeout
	EditorInterface.open_scene_from_path(scene_path)
	await get_tree().create_timer(1.5).timeout
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _fail(job_id, scene_path, "场景根为空")
	var lm := BC.find_lightmap(root)
	if lm == null:
		return _fail(job_id, scene_path, "LightmapGI 未找到")
	print("NEON_BAKE[%s]: LightmapGI = %s" % [job_id, lm.get_path()])
	# 前置检查：网格 UV2/静态标记/层级
	var pre := _precheck(root, lm)
	if not pre.get("ok", false):
		return _fail(job_id, scene_path, "前置检查失败: %s" % str(pre.get("message", "")))
	var expected := BC.expected_bake_users(root)
	if expected.is_empty():
		return _fail(job_id, scene_path, "应烘焙网格为空（expected=0）")
	# §4.2 步骤 4：manifest v2 输入签名必须与当前场景一致，否则要求重新 assemble
	var manifest_path := _manifest_for_scene(scene_path)
	var manifest := BC.load_json_dict(manifest_path)
	if manifest.is_empty():
		return _fail(job_id, scene_path, "清单缺失或不可解析，先运行 assemble")
	if int(manifest.get("schema_version", 0)) != 2:
		return _fail(job_id, scene_path, "清单 schema_version != 2，先运行 assemble")
	var roots: PackedStringArray = PackedStringArray()
	for r in manifest.get("bake_source_roots", []):
		roots.append(String(r))
	if roots.is_empty():
		return _fail(job_id, scene_path, "清单 bake_source_roots 为空")
	var signature := BC.compute_bake_signature(roots, root)
	if str(signature.get("bake_input_hash", "")) != str(manifest.get("bake_input_hash", "")):
		return _fail(job_id, scene_path, "清单 bake_input_hash 与当前输入不一致——输入已变化，先重新 assemble")
	var manifest_expected: Array = manifest.get("expected_baked_user_paths", [])
	var me_sorted: Array = manifest_expected.duplicate()
	me_sorted.sort()
	var ce_sorted: Array = []
	for p in expected:
		ce_sorted.append(p)
	ce_sorted.sort()
	if me_sorted != ce_sorted:
		return _fail(job_id, scene_path, "清单 expected 与场景结构不一致，先重新 assemble")
	# §4.2 步骤 5：先可恢复替换 manifest=running（actual/missing 清空），成功才允许写空数据
	var pending := _manifest_with_bake_state(manifest, "running", job_id, expected, [], [])
	if BC.write_json_recoverable(manifest_path, pending) != OK:
		return _fail(job_id, scene_path, "manifest=running 写入失败，中止（未触碰烘焙数据）")
	print("NEON_BAKE[%s]: manifest=running 已落盘" % job_id)
	# 预保存空 LightmapGIData（bake() 要求已有保存路径）
	var data_path := _baked_data_for_scene(scene_path)
	DirAccess.make_dir_recursive_absolute(data_path.get_base_dir())
	var data := LightmapGIData.new()
	var save_err := ResourceSaver.save(data, data_path)
	print("NEON_BAKE[%s]: 预保存 light_data -> %s err=%d" % [job_id, data_path, save_err])
	if save_err != OK:
		return _fail(job_id, scene_path, "LightmapGIData 预保存失败")
	# §4.2 步骤 7：fresh-load 重绑，确认 ResourceLoader cache 无旧数据、user_count=0
	var fresh: LightmapGIData = BC.load_resource_fresh(data_path, "LightmapGIData") as LightmapGIData
	if fresh == null:
		return _fail(job_id, scene_path, "空烘焙数据 fresh-load 失败")
	lm.light_data = fresh
	if lm.light_data.get_user_count() != 0:
		return _fail(job_id, scene_path, "重绑后 user_count != 0（cache 未刷新）")
	EditorInterface.edit_node(lm)
	# 定位"烘焙光照贴图"按钮（可解释定位 + 唯一匹配验证，不依赖屏幕坐标）
	var btn: Button = null
	for i in 40:
		await get_tree().create_timer(POLL_INTERVAL).timeout
		btn = _find_bake_button()
		if btn != null:
			break
	if btn == null:
		return _fail(job_id, scene_path, "未找到烘焙按钮")
	print("NEON_BAKE[%s]: 触发按钮 '%s'" % [job_id, btn.text])
	_set_job(job_id, "running", "烘焙中")
	bake_started.emit(job_id, StringName(_map_id_for_scene(scene_path)))
	btn.pressed.emit()
	# 等待烘焙完成：以 LightmapGIData 用户数 > 0 且趋于稳定为准（不依赖固定秒数）
	var waited := 0.0
	var last_count := 0
	var stable_since := -1.0
	while waited < BAKE_TIMEOUT_SEC:
		await get_tree().create_timer(POLL_INTERVAL).timeout
		waited += POLL_INTERVAL
		if not is_instance_valid(lm) or lm.light_data == null:
			return _fail(job_id, scene_path, "LightmapGI 失效")
		var count := lm.light_data.get_user_count()
		if count > 0 and count == last_count:
			if stable_since < 0.0:
				stable_since = waited
			elif waited - stable_since >= 2.0:
				break
		else:
			stable_since = -1.0
		last_count = count
		if int(waited / POLL_INTERVAL) % 20 == 0:
			print("NEON_BAKE[%s]: 等待中 %.0fs users=%d" % [job_id, waited, last_count])
	if last_count == 0:
		return _fail(job_id, scene_path, "烘焙超时（%.0f 秒）或无结果" % waited)
	# 覆盖验证（§4.3）：expected 非空、actual 非空、missing 为空；actual 允许超集
	var actual := BC.actual_bake_users(lm)
	var missing := BC.missing_paths(expected, actual)
	print("NEON_BAKE[%s]: 烘焙 users=%d expected_meshes=%d missing=%d" % [job_id, actual.size(), expected.size(), missing.size()])
	if missing.size() > 0:
		return _fail(job_id, scene_path, "以下网格未被烘焙覆盖: %s" % ", ".join(missing))
	# 保存场景：检查返回 Error（§4.2 步骤 12）
	await get_tree().create_timer(1.5).timeout
	var save_scene_err := EditorInterface.save_scene()
	await get_tree().create_timer(1.5).timeout
	if save_scene_err != OK:
		return _fail(job_id, scene_path, "save_scene 失败 err=%d" % save_scene_err)
	print("NEON_BAKE[%s]: light_data = %s" % [job_id, lm.light_data.resource_path])
	# 终检：磁盘 fresh-load 与场景内数据一致（§4.2 步骤 13）
	var final_data: LightmapGIData = BC.load_resource_fresh(data_path, "LightmapGIData") as LightmapGIData
	if final_data == null or final_data.get_user_count() == 0:
		return _fail(job_id, scene_path, "终检 fresh-load 烘焙数据为空")
	var final_probe := LightmapGI.new()
	final_probe.light_data = final_data
	var final_actual := BC.actual_bake_users(final_probe)
	if BC.missing_paths(expected, final_actual).size() > 0:
		return _fail(job_id, scene_path, "终检覆盖缺失（磁盘数据与场景不一致）")
	# succeeded 清单 + 报告：任一写失败都判失败（§4.4），但 succeeded 语义只表示数据有效
	var finished_utc := Time.get_datetime_string_from_system(true)
	var succeeded := _manifest_with_bake_state(manifest, "succeeded", job_id, expected, actual, [])
	if BC.write_json_recoverable(manifest_path, succeeded) != OK:
		return _fail(job_id, scene_path, "manifest=succeeded 写入失败（数据有效但证据缺失，重跑报告补齐）")
	_set_job(job_id, "succeeded", "users=%d" % actual.size())
	var report := {"users": actual, "expected": expected, "missing": missing, "map_id": _map_id_for_scene(scene_path)}
	if _write_report(job_id, true, "", report) != OK:
		return _fail(job_id, scene_path, "报告写盘失败")
	print("NEON_BAKE_EXIT=0")
	get_tree().quit(0)


func _fail(job_id: String, scene_path: String, reason: String) -> void:
	printerr("NEON_BAKE[%s]: %s" % [job_id, reason])
	_set_job(job_id, "failed", reason)
	# 尽最大可能把失败写入清单（best-effort，写失败不掩盖原始错误）
	var manifest_path := _manifest_for_scene(scene_path)
	var manifest := BC.load_json_dict(manifest_path)
	if not manifest.is_empty() and int(manifest.get("schema_version", 0)) == 2:
		var expected: Array = manifest.get("expected_baked_user_paths", [])
		var failed := _manifest_with_bake_state(manifest, "failed", job_id, expected, [], [reason])
		BC.write_json_recoverable(manifest_path, failed)
	_write_report(job_id, false, reason, {})
	print("NEON_BAKE_EXIT=1")
	get_tree().quit(1)


func _manifest_with_bake_state(manifest: Dictionary, status: String, job_id: String,
		expected: Array, actual: Array, missing: Array) -> Dictionary:
	## 唯一的清单字段更新入口：保留 assemble 写入的输入签名，只改烘焙状态字段。
	var out: Dictionary = manifest.duplicate(true)
	out["bake_job_id"] = job_id
	out["bake_status"] = status
	out["expected_baked_user_paths"] = expected
	out["actual_baked_user_paths"] = actual
	out["missing_baked_user_paths"] = missing
	if status == "succeeded" or status == "failed":
		out["bake_finished_utc"] = Time.get_datetime_string_from_system(true)
	return out


# ============================ 前置/覆盖检查 ============================

func _precheck(root: Node, lm: LightmapGI) -> Dictionary:
	## GDScript lambda 按值捕获局部变量——计数必须走引用类型（字典）。
	var acc := {"mesh_count": 0, "uv2_count": 0}
	_visit_meshes(root, acc)
	if int(acc["mesh_count"]) == 0:
		return {"ok": false, "message": "场景内无网格"}
	if int(acc["uv2_count"]) == 0:
		return {"ok": false, "message": "无网格带 UV2"}
	print("NEON_BAKE: 前置检查 mesh_instances=%d 带UV2=%d" % [int(acc["mesh_count"]), int(acc["uv2_count"])])
	return {"ok": true, "message": ""}


func _visit_meshes(node: Node, acc: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		acc["mesh_count"] = int(acc["mesh_count"]) + 1
		var mesh := mi.mesh
		if mesh is ArrayMesh and (mesh as ArrayMesh).get_surface_count() > 0:
			var has_uv2 := true
			for i in (mesh as ArrayMesh).get_surface_count():
				if not ((mesh as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2):
					has_uv2 = false
			if has_uv2:
				acc["uv2_count"] = int(acc["uv2_count"]) + 1
	for c in node.get_children():
		_visit_meshes(c, acc)


# ============================ 报告 ============================

func _report_dir() -> String:
	## §28.4：NEON_ARTIFACT_DIR 只允许 res://artifacts 下；未设置回退 res://artifacts/build。
	var env := OS.get_environment("NEON_ARTIFACT_DIR")
	if env.begins_with("res://artifacts") and (env.length() == len("res://artifacts") or env[len("res://artifacts")] == "/"):
		return env
	if not env.is_empty():
		push_warning("NEON_BAKE: NEON_ARTIFACT_DIR 非法（%s），回退 %s" % [env, FALLBACK_REPORT_DIR])
	return FALLBACK_REPORT_DIR


func _write_report(job_id: String, success: bool, reason: String, detail: Dictionary) -> Error:
	var dir := _report_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace(" ", "")
	var path := "%s/bake_report_%s.json" % [dir, stamp]
	var report := {
		"schema_version": 1,
		"job_id": job_id,
		"success": success,
		"reason": reason,
		"detail": detail,
		"utc": Time.get_datetime_string_from_system(true),
		"engine_version": str(Engine.get_version_info().get("string", "")),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("NEON_BAKE: 报告不可写 %s" % path)
		return ERR_CANT_OPEN
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("NEON_BAKE: 报告 %s" % path)
	bake_finished.emit(job_id, success, path)
	return OK


# ============================ 编辑器控件定位（沿用已验证路线） ============================

func _map_id_for_scene(scene_path: String) -> String:
	return scene_path.get_base_dir().get_file()


func _find_bake_button() -> Button:
	var all := []
	_collect_bake_buttons(EditorInterface.get_inspector(), all, "inspector")
	_collect_bake_buttons(EditorInterface.get_base_control(), all, "base")
	if all.is_empty():
		return null
	for entry in all:
		if entry["where"] == "inspector" and entry["visible"]:
			return entry["btn"]
	for entry in all:
		if entry["visible"]:
			return entry["btn"]
	return null


func _collect_bake_buttons(node: Node, out: Array, where: String, path: String = "") -> void:
	if node is Button:
		var t: String = node.text
		if t.contains("烘焙光照贴图") or t.contains("Bake Lightmaps") or (t.contains("烘焙") and t.contains("贴图")):
			out.append({"btn": node, "where": where, "path": path + "/" + node.name, "visible": node.is_visible_in_tree()})
	for c in node.get_children():
		_collect_bake_buttons(c, out, where, path + "/" + String(node.name))
