## 仅编辑器加载的自动烘焙插件（chapter1-1 §9.4 BakeCoordinator）。
## 运行：godot --path . --editor -- --auto-bake [--scene res://path/to/scene.tscn]
## 原因：Godot 4.7.2 未把 LightmapGI.bake() 暴露给脚本，编辑器 UI 按钮是唯一入口；
## 本插件在编辑器内打开地图场景、选中 LightmapGI、程序化触发"烘焙光照贴图"按钮，
## 完成后核对 LightmapGIData user 路径、回写 build_manifest.json、写报告并退出。
## 无 --auto-bake 参数时完全惰性。--auto-bake 是项目自定义参数（user args），不是引擎开关。
@tool
extends EditorPlugin

signal bake_started(job_id: String, map_id: StringName)
signal bake_finished(job_id: String, success: bool, report_path: String)

const DEFAULT_SCENE := "res://maps/m01_afterglow/map.tscn"
const REPORT_DIR := "res://artifacts/chapter1_2"
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


func fail_job(job_id: String, reason: String) -> void:
	_set_job(job_id, "failed", reason)
	_write_report(job_id, false, reason, {})


## 多地图（chapter1-2 §6）：场景统一放在 maps/<map_id>/map.tscn，
## 清单/烘焙数据/报告路径全部从场景路径推导。
func _scene_for_map(map_id: String) -> String:
	return "res://maps/%s/map.tscn" % map_id


func _map_id_for_scene(scene_path: String) -> String:
	return scene_path.get_base_dir().get_file()


func _manifest_for_scene(scene_path: String) -> String:
	return "%s/build_manifest.json" % scene_path.get_base_dir()


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
		return _fail(job_id, "场景根为空")
	var lm := _find_lightmap(root)
	if lm == null:
		return _fail(job_id, "LightmapGI 未找到")
	print("NEON_BAKE[%s]: LightmapGI = %s" % [job_id, lm.get_path()])
	# 前置检查：网格 UV2/静态标记/层级
	var pre := _precheck(root, lm)
	if not pre.get("ok", false):
		return _fail(job_id, "前置检查失败: %s" % str(pre.get("message", "")))
	# 预保存空 LightmapGIData（bake() 要求已有保存路径）；统一落 baked/map_lightmap.res
	var data_path := "%s/baked/map_lightmap.res" % scene_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(data_path.get_base_dir())
	var data := LightmapGIData.new()
	var save_err := ResourceSaver.save(data, data_path)
	print("NEON_BAKE[%s]: 预保存 light_data -> %s err=%d" % [job_id, data_path, save_err])
	if save_err != OK:
		return _fail(job_id, "LightmapGIData 预保存失败")
	lm.light_data = load(data_path)
	EditorInterface.edit_node(lm)
	# 定位"烘焙光照贴图"按钮（可解释定位 + 唯一匹配验证，不依赖屏幕坐标）
	var btn: Button = null
	for i in 40:
		await get_tree().create_timer(POLL_INTERVAL).timeout
		btn = _find_bake_button()
		if btn != null:
			break
	if btn == null:
		return _fail(job_id, "未找到烘焙按钮")
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
			return _fail(job_id, "LightmapGI 失效")
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
		return _fail(job_id, "烘焙超时（%.0f 秒）或无结果" % waited)
	# 覆盖验证：user 路径 vs 场景内应烘焙网格
	var expected := _expected_bake_users(root)
	var actual := _actual_bake_users(lm)
	var missing := _diff_paths(expected, actual)
	print("NEON_BAKE[%s]: 烘焙 users=%d expected_meshes=%d" % [job_id, actual.size(), expected.size()])
	if missing.size() > 0:
		print("NEON_BAKE[%s]: 警告——以下网格未被烘焙覆盖: %s" % [job_id, ", ".join(missing)])
	# 保存场景
	await get_tree().create_timer(1.5).timeout
	EditorInterface.save_scene()
	await get_tree().create_timer(1.5).timeout
	print("NEON_BAKE[%s]: light_data = %s" % [job_id, lm.light_data.resource_path])
	# 回写构建清单
	_update_manifest(job_id, actual, _manifest_for_scene(scene_path))
	_set_job(job_id, "succeeded", "users=%d" % actual.size())
	var report := {"users": actual, "expected": expected, "missing": missing}
	_write_report(job_id, missing.is_empty() or actual.size() > 0, "", report)
	print("NEON_BAKE_EXIT=0")
	get_tree().quit(0)


func _fail(job_id: String, reason: String) -> void:
	printerr("NEON_BAKE[%s]: %s" % [job_id, reason])
	_set_job(job_id, "failed", reason)
	_write_report(job_id, false, reason, {})
	print("NEON_BAKE_EXIT=1")
	get_tree().quit(1)


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


func _expected_bake_users(root: Node) -> Array[String]:
	## 应烘焙的网格：LightmapGI 子树内 GI 静态、带 UV2 的 MeshInstance3D 的**节点路径**
	## （LightmapGIData.get_user_path() 返回相对 LightmapGI 的节点路径）。
	var lm := _find_lightmap(root)
	if lm == null:
		return []
	var found: Array[String] = []
	_visit_bake_meshes(lm, lm, found)
	found.sort()
	return found


func _visit_bake_meshes(node: Node, lm: LightmapGI, found: Array[String]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.gi_mode == GeometryInstance3D.GI_MODE_STATIC and mi.mesh != null:
			var has_uv2 := false
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_surface_count() > 0:
				has_uv2 = true
				for i in (mi.mesh as ArrayMesh).get_surface_count():
					if not ((mi.mesh as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2):
						has_uv2 = false
			if has_uv2:
				var rel := str(lm.get_path_to(mi))
				if not found.has(rel):
					found.append(rel)
	for c in node.get_children():
		_visit_bake_meshes(c, lm, found)


func _actual_bake_users(lm: LightmapGI) -> Array[String]:
	## LightmapGIData 实际覆盖的 user 路径（按本机 4.7.2 API：get_user_count/get_user_path）。
	var out: Array[String] = []
	if lm.light_data == null:
		return out
	for i in lm.light_data.get_user_count():
		var p := lm.light_data.get_user_path(i)
		if not out.has(p):
			out.append(p)
	out.sort()
	return out


func _diff_paths(expected: Array[String], actual: Array[String]) -> Array[String]:
	## 节点路径口径直接对比。
	var actual_set := {}
	for p in actual:
		actual_set[p] = true
	var missing: Array[String] = []
	for p in expected:
		if not actual_set.has(p):
			missing.append(p)
	return missing


# ============================ 清单与报告 ============================

func _update_manifest(job_id: String, actual: Array[String], manifest_path: String) -> void:
	if not FileAccess.file_exists(manifest_path):
		print("NEON_BAKE: 清单不存在，跳过回写")
		return
	var txt := FileAccess.get_file_as_string(manifest_path)
	var manifest = JSON.parse_string(txt)
	if not manifest is Dictionary:
		print("NEON_BAKE: 清单 JSON 非法，跳过回写")
		return
	manifest["bake_job_id"] = job_id
	manifest["bake_status"] = "succeeded"
	var arr: Array = []
	for p in actual:
		arr.append(p)
	manifest["actual_baked_user_paths"] = arr
	manifest["bake_finished_utc"] = Time.get_datetime_string_from_system(true)
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("NEON_BAKE: 清单已回写 bake_status=succeeded")


func _write_report(job_id: String, success: bool, reason: String, detail: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace(" ", "")
	var path := "%s/bake_report_%s.json" % [REPORT_DIR, stamp]
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
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		print("NEON_BAKE: 报告 %s" % path)
		bake_finished.emit(job_id, success, path)


# ============================ 编辑器控件定位（沿用已验证路线） ============================

func _find_lightmap(node: Node) -> LightmapGI:
	if node is LightmapGI:
		return node
	for c in node.get_children():
		var r := _find_lightmap(c)
		if r != null:
			return r
	return null


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
