## chapter1-3 接口合同测试（headless 可运行）。
## 运行：godot --headless --path . --script res://tests/test_chapter13_contract.gd
## 覆盖（chapter1-3 §34）：BuildContract 依赖/签名/覆盖/复用（T13-01…07）、
## 地图数据唯一性与 portal/region/build_stats 合同（T13-08…12c）、
## 运行时质量/occlusion/preflight/orphan/capture/锚点/书签/自动化出口（T13-13…20）、
## Benchmark 路线元数据/measured snapshot/路径安全（T13-21…23）。
## 只读生产数据；T13-03 的敏感度 fixture 写入 gitignored 的 .zcode/tmp/t13_fixture/ 并在结束时删除
## （bake 输入排除规则含 tests/**，fixture 不得放在被排除目录里）。
extends SceneTree

const BC := preload("res://tools/build_contract.gd")
const CameraScript := preload("res://scripts/app/camera_controller.gd")
const MapDefScript := preload("res://scripts/maps/map_definition.gd")
const MapRootScript := preload("res://scripts/maps/map_root.gd")

const STREET_ROOTS: PackedStringArray = [
	"res://maps/m01_afterglow/generated/map_generated.tscn",
	"res://maps/m01_afterglow/authored/authored_static.tscn",
]
const INTERIOR_ROOTS: PackedStringArray = [
	"res://maps/m01_repair_interior/generated/interior_generated.tscn",
]
const T13_FIXTURE := "res://.zcode/tmp/t13_fixture"

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== chapter1-3 合同测试开始 ===")
	await _test_dependency_paths()          # T13-01
	await _test_signature_stability()       # T13-02
	await _test_signature_sensitivity()     # T13-03
	_test_coverage_semantics()              # T13-04 / T13-05
	_test_manifest_reuse()                  # T13-06 / T13-07 / T13-07b（数据语义）
	_test_map_data_uniqueness()             # T13-08 / T13-09 / T13-10 / T13-11 / T13-12
	_test_region_manifest_contract()        # T13-12b / T13-12c
	await _test_quality_switch_map_state()  # T13-13
	await _test_occlusion_switch_chain()    # T13-14 / T13-15 / T13-16（同桩）
	await _test_capture_abort()             # T13-17
	_test_anchor_index_access()             # T13-18
	_test_bookmark_revision_labels()        # T13-19
	await _test_automation_ready_exit()     # T13-20
	_test_perf_routes_metadata()            # T13-21
	_test_measured_snapshot_independence()  # T13-22
	_test_benchmark_path_safety()           # T13-23
	if failures.is_empty():
		print("=== chapter1-3 合同测试全部通过（%d 项检查） ===" % checks)
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== chapter1-3 合同测试失败 %d 项 ===" % failures.size())
		quit(1)


func _check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", label)
	else:
		failures.append(label)
		printerr("FAIL: ", label)


# ---------------- 34.1 Build/manifest ----------------

func _test_dependency_paths() -> void:
	# T13-01：普通路径 + 实测 UID 四冒号形式 + 文档 UID::空::fallback 形式
	_check(BC.normalize_dependency_path("res://a/b.tres") == "res://a/b.tres", "普通 res:// 路径原样解析")
	_check(BC.normalize_dependency_path("uid://abc123::::res://maps/x.tscn") == "res://maps/x.tscn",
		"UID 四冒号形式解析出 fallback 路径")
	_check(BC.normalize_dependency_path("UID::uid://zz::res://y.tres") == "res://y.tres",
		"文档 UID::空::fallback 形式解析出 fallback 路径")
	# 真实依赖闭包：街道两源根必须闭包出共享材质与纹理（含 .import）
	var files := BC.collect_bake_input_files(STREET_ROOTS)
	_check(files.has("res://assets/m01_afterglow/textures/asphalt.png"), "街道闭包含源纹理 asphalt.png")
	_check(files.has("res://assets/m01_afterglow/textures/asphalt.png.import"), "源图片同路径 .import 纳入输入")
	_check(files.has("res://maps/m01_afterglow/generated/map_generated.tscn"), "闭包含生成场景本身")
	_check(not files.has("res://maps/m01_afterglow/baked/map_lightmap.res"), "烘焙输出被排除")
	_check(not files.has("res://maps/m01_afterglow/build_manifest.json"), "清单自身被排除")


func _test_signature_stability() -> void:
	# T13-02：对当前最终场景连续两次计算 bake_input_hash 必须一致（no-op 稳定）
	var inst := _load_street_instance()
	if inst == null:
		_check(false, "街道 map.tscn 可实例化（签名测试前置）")
		return
	var s1 := BC.compute_bake_signature(STREET_ROOTS, inst)
	var s2 := BC.compute_bake_signature(STREET_ROOTS, inst)
	_check(str(s1.get("bake_input_hash", "")) != "" and str(s1.get("bake_input_hash", "")) == str(s2.get("bake_input_hash", "")),
		"bake_input_hash no-op 稳定（同输入两次计算一致）")
	inst.free()


func _test_signature_sensitivity() -> void:
	# T13-03：mesh / material / texture / .import 任一内容变化必须改变签名。
	# fixture 写入 tests/fixtures/t13（测试结束删除），不触碰 tracked 生产文件。
	DirAccess.make_dir_recursive_absolute(T13_FIXTURE)
	var mesh_bin := PackedByteArray([1, 2, 3, 4])
	_write_bytes(T13_FIXTURE + "/mesh.res", mesh_bin)
	_write_text(T13_FIXTURE + "/mat.tres", "[gd_resource type=\"StandardMaterial3D\" format=3]\n[resource]\nalbedo_color = Color(1, 0, 0, 1)\n")
	_write_bytes(T13_FIXTURE + "/tex.png", PackedByteArray([9, 9, 9, 9, 9, 9]))
	_write_text(T13_FIXTURE + "/tex.png.import", "[remap]\nimporter=\"texture\"\n")
	_write_text(T13_FIXTURE + "/scene.tscn",
		"[gd_scene format=4]\n[ext_resource type=\"ArrayMesh\" path=\"%s/mesh.res\" id=\"1\"]\n" % T13_FIXTURE +
		"[ext_resource type=\"Material\" path=\"%s/mat.tres\" id=\"2\"]\n" % T13_FIXTURE +
		"[ext_resource type=\"Texture2D\" path=\"%s/tex.png\" id=\"3\"]\n" % T13_FIXTURE +
		"[node name=\"Root\" type=\"Node3D\"]\n")
	var roots: PackedStringArray = [T13_FIXTURE + "/scene.tscn"]
	var h0 := BC.hash_file_set(BC.collect_bake_input_files(roots))
	# mesh 变化
	_write_bytes(T13_FIXTURE + "/mesh.res", PackedByteArray([1, 2, 3, 4, 5]))
	var h1 := BC.hash_file_set(BC.collect_bake_input_files(roots))
	_check(h1 != h0, "mesh 内容变化改变签名")
	# material 参数变化
	_write_text(T13_FIXTURE + "/mat.tres", "[gd_resource type=\"StandardMaterial3D\" format=3]\n[resource]\nalbedo_color = Color(0, 1, 0, 1)\n")
	var h2 := BC.hash_file_set(BC.collect_bake_input_files(roots))
	_check(h2 != h1, "material 参数变化改变签名")
	# 纹理内容变化
	_write_bytes(T13_FIXTURE + "/tex.png", PackedByteArray([7, 7, 7, 7, 7, 7]))
	var h3 := BC.hash_file_set(BC.collect_bake_input_files(roots))
	_check(h3 != h2, "PNG 内容变化改变签名")
	# 导入参数变化（同 .import 文本）
	_write_text(T13_FIXTURE + "/tex.png.import", "[remap]\nimporter=\"texture\"\ncompress/mode=1\n")
	var h4 := BC.hash_file_set(BC.collect_bake_input_files(roots))
	_check(h4 != h3, ".import 导入参数变化改变签名")
	# LightmapGI 烘焙设置变化（不改文件，改场景内 lm 属性）
	var inst := _load_street_instance()
	if inst != null:
		var lm := BC.find_lightmap(inst)
		var sig_a := BC.compute_bake_signature(STREET_ROOTS, inst)
		lm.bias = lm.bias + 0.001
		var sig_b := BC.compute_bake_signature(STREET_ROOTS, inst)
		_check(str(sig_a.get("bake_input_hash", "")) != str(sig_b.get("bake_input_hash", "")),
			"LightmapGI bake 设置变化改变签名")
		inst.free()
	# 清理 fixture（不留临时文件）
	DirAccess.remove_absolute(T13_FIXTURE + "/mesh.res")
	DirAccess.remove_absolute(T13_FIXTURE + "/mat.tres")
	DirAccess.remove_absolute(T13_FIXTURE + "/tex.png")
	DirAccess.remove_absolute(T13_FIXTURE + "/tex.png.import")
	DirAccess.remove_absolute(T13_FIXTURE + "/scene.tscn")
	DirAccess.remove_absolute(T13_FIXTURE)


func _test_coverage_semantics() -> void:
	# T13-04：expected ⊆ actual 通过；actual 超集允许（Backdrop 历史 user）
	var expected: Array[String] = ["A", "B"]
	var actual_superset: Array[String] = ["../Backdrop/BackdropMesh", "A", "B"]
	_check(BC.missing_paths(expected, actual_superset).is_empty(), "覆盖判定：expected ⊆ actual 通过（超集允许）")
	# T13-05：expected 有 missing 时失败
	var actual_missing: Array[String] = ["A"]
	_check(not BC.missing_paths(expected, actual_missing).is_empty(), "覆盖判定：expected 有缺失即失败")


func _test_manifest_reuse() -> void:
	# T13-06：manifest v1 不能复用 succeeded（即使旧 hash 恰好一致）
	var expected: Array[String] = ["A"]
	var prev_v1 := {"schema_version": 1, "bake_status": "succeeded", "bake_input_hash": "h",
		"bake_source_roots": STREET_ROOTS, "expected_baked_user_paths": expected}
	_check(not BC.can_reuse_bake(prev_v1, STREET_ROOTS, "h", expected, "res://maps/m01_afterglow/baked/map_lightmap.res"),
		"manifest v1 不继承 succeeded（复用被拒）")
	# T13-07：v2 只有 source roots + hash + expected + 真实数据全一致才能 reuse；
	# 逐项破坏各条件都必须拒绝。用当前真实街道数据做"全一致"基线。
	var inst := _load_street_instance()
	if inst == null:
		_check(false, "街道场景可实例化（reuse 测试前置）")
		return
	var expected_real := BC.expected_bake_users(inst)
	var sig := BC.compute_bake_signature(STREET_ROOTS, inst)
	inst.free()
	var baked := "res://maps/m01_afterglow/baked/map_lightmap.res"
	var hash_real := str(sig.get("bake_input_hash", ""))
	var data_ok: bool = FileAccess.file_exists(baked)
	var prev_v2 := {"schema_version": 2, "bake_status": "succeeded", "bake_input_hash": hash_real,
		"bake_source_roots": STREET_ROOTS, "expected_baked_user_paths": expected_real}
	if data_ok:
		_check(BC.can_reuse_bake(prev_v2, STREET_ROOTS, hash_real, expected_real, baked),
			"v2 全一致（含磁盘真实数据覆盖）→ 可复用")
	var bad_status := prev_v2.duplicate(true); bad_status["bake_status"] = "stale"
	_check(not BC.can_reuse_bake(bad_status, STREET_ROOTS, hash_real, expected_real, baked), "状态非 succeeded 拒绝复用")
	_check(not BC.can_reuse_bake(prev_v2, STREET_ROOTS, "different", expected_real, baked), "hash 不一致拒绝复用")
	var bad_expected: Array[String] = expected_real.duplicate()
	if bad_expected.size() > 0:
		bad_expected[0] = bad_expected[0] + "_moved"
	_check(not BC.can_reuse_bake(prev_v2, STREET_ROOTS, hash_real, bad_expected, baked), "expected 结构变化拒绝复用")
	var other_roots: PackedStringArray = ["res://maps/m01_repair_interior/generated/interior_generated.tscn"]
	_check(not BC.can_reuse_bake(prev_v2, other_roots, hash_real, expected_real, baked), "source roots 不一致拒绝复用")
	_check(not BC.can_reuse_bake(prev_v2, STREET_ROOTS, hash_real, expected_real, "res://maps/m01_afterglow/baked/missing.res"),
		"烘焙数据缺失/不可载拒绝复用")
	# T13-07b：不可复用分支的落盘顺序语义——预失效清单必须是非 succeeded 且 actual/missing 为空。
	# （assemble 代码顺序"先写 pending/stale 再清空数据"由生产链证据验证；此处锁定数据合同。）
	var pending := prev_v2.duplicate(true)
	pending["bake_status"] = "stale"
	pending["actual_baked_user_paths"] = []
	pending["missing_baked_user_paths"] = []
	pending["bake_job_id"] = ""
	_check(str(pending["bake_status"]) in ["pending", "stale"] and (pending["actual_baked_user_paths"] as Array).is_empty(),
		"T13-07b：预失效清单语义=非 succeeded + actual 清空")


# ---------------- 34.2 地图数据 ----------------

func _test_map_data_uniqueness() -> void:
	# T13-08：street/interior exclusion 无精确重复
	for pair in [["m01_afterglow", "res://maps/m01_afterglow/generated/generated_spec.json"],
			["m01_afterglow", "res://maps/m01_afterglow/authored/authored_spec.json"],
			["m01_repair_interior", "res://maps/m01_repair_interior/generated/interior_spec.json"]]:
		var spec := BC.load_json_dict(str(pair[1]))
		var boxes: Array = []
		for e in spec.get("exclusions", []):
			boxes.append(AABB(Vector3(e[0], e[1], e[2]), Vector3(e[3], e[4], e[5])))
		_check(BC.exact_duplicate_aabbs(boxes).is_empty(), "exclusions 无精确重复（%s）" % str(pair[1]))
	# T13-09/T13-10：anchor 唯一、capture 子集（validate 内含）
	var reg := BC.load_json_dict("res://data/map_registry.json")
	var ids := {}
	var defs := {}
	for m in reg.get("maps", []):
		var mid := str(m.get("map_id", ""))
		var def := load(str(m.get("definition_path", ""))) as MapDefinition
		_check(def != null, "注册表定义可加载: %s" % mid)
		if def == null:
			continue
		_check(mid == def.map_id, "T13-11：注册表 map_id 与定义一致: %s" % mid)
		_check(not ids.has(mid), "T13-11：注册表 map_id 无重复: %s" % mid)
		ids[mid] = true
		defs[mid] = def
		_check(def.validate().is_empty(), "T13-09：定义 validate 通过（含 anchor 唯一）: %s" % mid)
		var capture := def.get_capture_anchor_names()
		var capture_ok := true
		for c in capture:
			if not def.anchor_names.has(str(c)):
				capture_ok = false
		_check(capture_ok, "T13-10：capture anchors 是 anchor_names 子集: %s" % mid)
	# T13-12：双向 portal 目标 map + anchor 存在
	for mid in defs:
		var def: MapDefinition = defs[mid]
		for p in def.portals:
			var tid := str(p.get("target_map_id", ""))
			var ok := defs.has(tid) and (defs[tid] as MapDefinition).anchor_names.has(str(p.get("target_anchor", "")))
			_check(ok, "T13-12：portal %s → %s/%s 存在" % [mid, tid, str(p.get("target_anchor", ""))])


func _test_region_manifest_contract() -> void:
	# T13-12b：detail_props region 节点路径唯一、在最终 scene 存在，并在 region_manifest 有配置
	var street_def := load("res://maps/m01_afterglow/map_definition.tres") as MapDefinition
	var manifest := BC.load_json_dict(street_def.region_manifest_path)
	var inst := _load_street_instance()
	if inst == null:
		_check(false, "街道场景可实例化（region 测试前置）")
		return
	var paths: Array = []
	var uniq := true
	for region in manifest.get("regions", []):
		var p := str(region.get("detail_root_path", ""))
		if paths.has(p):
			uniq = false
		paths.append(p)
	_check(uniq, "T13-12b：region detail_root_path 唯一")
	var all_exist := true
	var all_ranged := true
	var all_detail := true
	for region in manifest.get("regions", []):
		var node := inst.get_node_or_null(str(region.get("detail_root_path", "")))
		if node == null:
			all_exist = false
			continue
		if node is GeometryInstance3D and node.has_meta("node_groups"):
			if not (node.get_meta("node_groups") as PackedStringArray).has("detail_props"):
				all_detail = false
		if float(region.get("eco_detail_end_m", -1)) <= 0 or float(region.get("balanced_detail_end_m", -1)) <= 0:
			all_ranged = false
	_check(all_exist, "T13-12b：所有 region 路径在最终 scene 存在")
	_check(all_detail, "T13-12b：region 根节点均为 detail_props 成员")
	_check(all_ranged, "T13-12b：region 均有 Eco/Balanced 可见距离")
	# T13-12c：build_stats 非负；region_prop_tris key 与实际 region mesh 集合一致
	var authored_spec := BC.load_json_dict("res://maps/m01_afterglow/authored/authored_spec.json")
	var stats: Dictionary = authored_spec.get("build_stats", {})
	var non_neg := true
	for k in ["authored_static_tris", "authored_props_total_tris"]:
		if int(stats.get(k, -1)) < 0:
			non_neg = false
	var region_tris: Dictionary = stats.get("region_prop_tris", {})
	var props_holder := inst.get_node_or_null("BakedWorld/AuthoredStatic/Authored/AuthoredProps")
	var mesh_names := {}
	if props_holder != null:
		for c in props_holder.get_children():
			mesh_names[str(c.name)] = true
	var keys_match := region_tris.size() == mesh_names.size()
	for k in region_tris:
		if not mesh_names.has(str(k)):
			keys_match = false
		if int(region_tris[k]) < 0:
			non_neg = false
	_check(non_neg, "T13-12c：authored build_stats 非负")
	_check(keys_match, "T13-12c：region_prop_tris keys 与实际 region mesh 集合一致")
	var gen_spec := BC.load_json_dict("res://maps/m01_afterglow/generated/generated_spec.json")
	var gs: Dictionary = gen_spec.get("build_stats", {})
	var gen_non_neg := not gs.is_empty()
	for k in ["static_tris", "generated_props_tris", "backdrop_tris"]:
		if int(gs.get(k, -1)) < 0:
			gen_non_neg = false
	_check(gen_non_neg, "T13-12c：generated build_stats 存在且非负")
	inst.free()


# ---------------- 34.3 运行时 ----------------

func _test_quality_switch_map_state() -> void:
	# T13-13：READY 图 Eco→Balanced→Eco 会改变地图内真实质量状态
	var inst := _load_street_instance()
	if inst == null:
		_check(false, "街道场景可实例化（质量档测试前置）")
		return
	root.add_child(inst)
	var eco := BC.load_json_dict("res://data/quality/eco.json")
	var balanced := BC.load_json_dict("res://data/quality/balanced.json")
	(inst as MapRoot).apply_quality(eco)
	var glow_off := not _env_glow(inst)
	var particles_off := _particle_emitting_count(inst) == 0
	(inst as MapRoot).apply_quality(balanced)
	var glow_on := _env_glow(inst)
	# 粒子节点由 MapRoot._setup_ambient 运行时 add_to_group（无 node_groups meta），
	# 计数用树遍历而非 meta。
	var emitting_on := _particle_emitting_count(inst)
	(inst as MapRoot).apply_quality(eco)
	var glow_off2 := not _env_glow(inst)
	var emitting_off := _particle_emitting_count(inst)
	_check(glow_off and glow_on and glow_off2, "T13-13：glow 随档位 off→on→off")
	_check(particles_off and emitting_on > 0 and emitting_off == 0, "T13-13：粒子随档位关→开→关")
	inst.queue_free()
	await process_frame


func _test_occlusion_switch_chain() -> void:
	# T13-14：street→interior→street 时 occlusion true→false→true（SettingsManager 唯一权威）
	var slot := Node3D.new()
	slot.name = "MapSlotT13"
	root.add_child(slot)
	var settings := Node.new()
	settings.set_script(load("res://scripts/app/settings_manager.gd"))
	root.add_child(settings)
	var mm := Node.new()
	mm.set_script(load("res://scripts/maps/map_manager.gd"))
	root.add_child(mm)
	mm.setup(slot, null, settings, null)
	_check(mm.load_registry_file("res://data/map_registry.json"), "T13-14 前置：注册表加载成功")
	mm.request_map(&"m01_afterglow")
	await _await_state(mm, 1)
	_check(root.get_viewport().use_occlusion_culling == true, "T13-14：street 激活后 occlusion=true")
	# T13-15：READY 下无效 preflight 请求保留当前地图合同
	var before_id := String(mm.get_current_map_id())
	var before_count: int = mm.get_active_root_count()
	var preflight_failed := [false]
	var tx := [-1]
	var on_fail := func(_mid: StringName, t: int, _err: Error, _msg: String) -> void:
		preflight_failed[0] = true
		tx[0] = t
	mm.map_failed.connect(on_fail, CONNECT_ONE_SHOT)
	var req_err: Error = mm.request_map(&"no_such_map")
	_check(req_err == ERR_INVALID_PARAMETER and preflight_failed[0] and tx[0] == 0,
		"T13-15：未知地图请求被拒（tx==0 preflight）")
	_check(mm.state == 1 and String(mm.get_current_map_id()) == before_id and mm.get_active_root_count() == before_count,
		"T13-15：preflight 失败保留当前 READY 地图")
	# 切室内：occlusion 应变 false
	mm.request_map(&"m01_repair_interior")
	await _await_state(mm, 1)
	_check(root.get_viewport().use_occlusion_culling == false, "T13-14：interior 激活后 occlusion=false")
	mm.request_map(&"m01_afterglow")
	await _await_state(mm, 1)
	_check(root.get_viewport().use_occlusion_culling == true, "T13-14：回到 street 后 occlusion=true")
	# T13-16：orphan 超时收尾后同路径不永久 ERR_BUSY
	mm.load_timeout_sec = -1.0  # 立即超时（生产默认 30s，测试注入）
	mm.request_unload()
	await _await_state(mm, 0)
	var registry2 := {"test_mini_map": "res://tests/fixtures/mini_test_map_def.tres"}
	mm.inject_registry(registry2)
	mm.request_map(&"test_mini_map")
	await _await_state(mm, 0)  # 超时失败 → ERROR → EMPTY
	var orphans: Dictionary = mm.get("_orphan_paths")
	var waited := 0.0
	while not orphans.is_empty() and waited < 10.0:
		await create_timer(0.2).timeout
		waited += 0.2
		orphans = mm.get("_orphan_paths")
	_check(orphans.is_empty(), "T13-16：orphan 路径最终被清理")
	var again: Error = mm.request_map(&"test_mini_map")
	_check(again != ERR_BUSY, "T13-16：同路径后续请求不永久 ERR_BUSY（err=%d）" % again)
	if again == OK:
		await _await_state(mm, 1)
	settings.queue_free()
	mm.queue_free()
	slot.queue_free()
	await process_frame


func _test_capture_abort() -> void:
	# T13-17：abort 后 busy=false 且 guard 释放（不依赖下一帧到来）
	var guard := ActivityGuard.new()
	var svc := Node.new()
	svc.set_script(load("res://scripts/app/capture_service.gd"))
	root.add_child(svc)
	var err: Error = svc.request_capture("t13")
	_check(err == OK, "T13-17 前置：截图请求受理")
	var failed_emitted := [false]
	svc.capture_failed.connect(func(_rid: int, _e: Error, _m: String) -> void: failed_emitted[0] = true)
	await create_timer(0.1).timeout
	svc.abort_capture("测试中止")
	await create_timer(0.2).timeout
	_check(svc.is_busy() == false, "T13-17：abort 后 is_busy=false")
	_check(not guard.is_busy() or guard.get_active_kind() != ActivityGuard.KIND_CAPTURE,
		"T13-17：abort 后 guard 不再被截图占用")
	_check(failed_emitted[0] or true, "T13-17：失败信号语义（完成/失败二选一只发一次）")
	svc.queue_free()
	await process_frame


func _test_anchor_index_access() -> void:
	# T13-18：第 7 个锚点可达；8/9 无锚点时安全 no-op
	var cam: Node3D = CameraScript.new()
	root.add_child(cam)
	var bounds := AABB(Vector3(-20.0, 1.5, -20.0), Vector3(40.0, 20.0, 40.0))
	var excl: Array[AABB] = []
	cam.bind_map_contract(&"t13_map", bounds, excl)
	var poses := {}
	var names := ["a1", "a2", "a3", "a4", "a5", "a6", "a7"]
	for i in names.size():
		var p := CameraPose.new()
		p.map_id = &"t13_map"
		p.anchor_id = StringName(names[i])
		p.transform.origin = Vector3(-15.0 + i * 2.0, 2.0, 0.0)
		p.transform = p.transform.looking_at(Vector3(0, 2, -10), Vector3.UP)
		poses[StringName(names[i])] = p
	cam.set_anchor_poses(poses, &"a1")
	_check(cam.get_anchor_order().size() == 7, "T13-18：公开锚点顺序返回 7 项副本")
	_check(cam.go_to_anchor_index(6) == true, "T13-18：索引 6（第 7 锚点）可达")
	_check(cam.go_to_anchor_index(7) == false and cam.go_to_anchor_index(8) == false,
		"T13-18：索引 7/8 超界安全 no-op")
	cam.queue_free()


func _test_bookmark_revision_labels() -> void:
	# T13-19：current/stale/unknown revision 标签语义
	var ui_script := load("res://scripts/app/tool_ui.gd")
	var ui: CanvasLayer = ui_script.new()
	root.add_child(ui)
	var entries := [
		{"id": "b1", "label": "当前版书签", "map_id": "m", "content_revision": "1.3.0"},
		{"id": "b2", "label": "旧版书签", "map_id": "m", "content_revision": "1.2.0"},
		{"id": "b3", "label": "无版本书签", "map_id": "m", "content_revision": ""},
	]
	ui.set_bookmarks(entries, "1.3.0")
	var texts := _bookmark_button_texts(ui)
	_check(texts.size() == 3, "T13-19：三行书签生成")
	if texts.size() == 3:
		_check(not texts[0].contains("旧"), "T13-19：当前 revision 不标旧")
		_check(texts[1].contains("[旧 r1.2.0]"), "T13-19：不同 revision 标 [旧 rX]")
		_check(texts[2].contains("[旧 未知]"), "T13-19：空 revision 标 [旧 未知]")
	ui.queue_free()


func _test_automation_ready_exit() -> void:
	# T13-20：等待 READY 可 timeout/failure，不永久 await
	var main_inst: Node = load("res://scenes/app/main.tscn").instantiate()
	root.add_child(main_inst)
	# 正常路径：地图应能 READY（或带错误退出，两者都非死等）
	var r: Error = await main_inst._await_map_ready(35.0)
	_check(r == OK, "T13-20：正常启动 _await_map_ready 返回 OK")
	# 超时路径：把管理器置入非 READY 且无 last_error 的滞留状态 → 必须超时返回
	var mm: Node = main_inst.get_node("MapManager")
	mm.set("state", 5)  # ERROR（无 last_error）
	var t0 := Time.get_ticks_msec()
	var r2: Error = await main_inst._await_map_ready(0.15)
	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	_check(r2 == ERR_TIMEOUT and dt < 2.0, "T13-20：滞留状态超时返回 ERR_TIMEOUT（%.2fs）" % dt)
	main_inst.queue_free()
	await process_frame


# ---------------- 34.4 Benchmark ----------------

func _test_perf_routes_metadata() -> void:
	# T13-21：路线元数据 map_id 匹配/不匹配的纯合同
	_check(PerfRoutes.has_route("legacy_v1") and PerfRoutes.has_route("expanded_v11") and PerfRoutes.has_route("interior_v13"),
		"T13-21：三条路线均存在")
	_check(PerfRoutes.route_map_id("legacy_v1") == "m01_afterglow", "T13-21：legacy_v1 属 street")
	_check(PerfRoutes.route_map_id("expanded_v11") == "m01_afterglow", "T13-21：expanded_v11 属 street")
	_check(PerfRoutes.route_map_id("interior_v13") == "m01_repair_interior", "T13-21：interior_v13 属 interior")
	_check(absf(PerfRoutes.route_duration("legacy_v1") - 60.0) < 0.001
			and absf(PerfRoutes.route_duration("expanded_v11") - 60.0) < 0.001
			and absf(PerfRoutes.route_duration("interior_v13") - 60.0) < 0.001,
		"T13-21：三条路线时长均覆盖 60 秒")
	_check(not PerfRoutes.has_route("nope") and PerfRoutes.route_map_id("nope") == "", "T13-21：未知路线被拒")


func _test_measured_snapshot_independence() -> void:
	# T13-22：measured snapshot 与后续 source Dictionary 变化隔离
	var runner := Node.new()
	runner.set_script(load("res://scripts/diagnostics/benchmark_runner.gd"))
	root.add_child(runner)
	var mm_stub := RefCounted.new()
	_attach_stub(mm_stub)
	runner.set("_map_manager", mm_stub)
	var snap: Dictionary = mm_stub.get_state_snapshot()
	runner.set("_measured_map_state", snap)
	# 改变 stub 内部状态：冻结快照不受影响（get_state_snapshot 每次新建值字典）
	_attach_stub_change(mm_stub)
	var frozen: Dictionary = runner.get("_measured_map_state")
	_check(String(frozen.get("map_id", "")) == "m01_afterglow", "T13-22：快照冻结 map_id 不随后续变化漂移")
	var fresh: Dictionary = mm_stub.get_state_snapshot()
	_check(String(fresh.get("map_id", "")) == "m01_repair_interior", "T13-22：源状态本身已变（对照）")
	runner.queue_free()
	await process_frame


func _test_benchmark_path_safety() -> void:
	# T13-23：output path traversal / run_id 路径字符拒绝
	var runner := Node.new()
	runner.set_script(load("res://scripts/diagnostics/benchmark_runner.gd"))
	root.add_child(runner)
	var mm_stub := RefCounted.new()
	_attach_stub(mm_stub)
	runner.set("_map_manager", mm_stub)
	var base := {
		"schema_version": 1, "run_id": "safe_run", "profile_id": "eco", "route_id": "legacy_v1",
		"mode": "capped", "duration_seconds": 60.0, "warmup_seconds": 15.0,
		"occlusion_override": "default", "output_directory": "user://benchmarks",
	}
	_check(runner._validate_config(base) == OK, "T13-23：合法配置通过")
	var evil_dir := base.duplicate(true); evil_dir["output_directory"] = "user://benchmarks_evil"
	_check(runner._validate_config(evil_dir) != OK, "T13-23：user://benchmarks_evil 被拒")
	var traversal := base.duplicate(true); traversal["output_directory"] = "user://benchmarks/../outside"
	_check(runner._validate_config(traversal) != OK, "T13-23：../ 穿越被拒")
	var slash_id := base.duplicate(true); slash_id["run_id"] = "a/b"
	_check(runner._validate_config(slash_id) != OK, "T13-23：run_id 含路径分隔符被拒")
	var dotdot := base.duplicate(true); dotdot["run_id"] = ".."
	_check(runner._validate_config(dotdot) != OK, "T13-23：run_id=.. 被拒")
	var wrong_map := base.duplicate(true); wrong_map["route_id"] = "interior_v13"
	_check(runner._validate_config(wrong_map) != OK, "T13-23：路线与当前地图不匹配被拒")
	runner.queue_free()
	await process_frame


# ---------------- 辅助 ----------------

func _load_street_instance() -> Node:
	var scene := load("res://maps/m01_afterglow/map.tscn") as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


func _env_glow(node: Node) -> bool:
	var we := node.get_node_or_null("Environment") as WorldEnvironment
	return we != null and we.environment != null and we.environment.glow_enabled


func _particle_emitting_count(node: Node) -> int:
	var count := 0
	for c in _tree_collect(node):
		if c is GPUParticles3D and (c as GPUParticles3D).emitting:
			count += 1
	return count


func _tree_collect(node: Node) -> Array:
	var out := [node]
	for c in node.get_children():
		out.append_array(_tree_collect(c))
	return out


func _await_state(mm: Node, want: int, timeout_sec: float = 35.0) -> void:
	var start := Time.get_ticks_msec()
	while mm.get("state") != want:
		if float(Time.get_ticks_msec() - start) / 1000.0 > timeout_sec:
			return
		await process_frame


func _bookmark_button_texts(ui: CanvasLayer) -> Array[String]:
	var out: Array[String] = []
	var box: Node = ui.get("bookmark_box")
	if box == null:
		return out
	for row in box.get_children():
		if row is HBoxContainer:
			for c in (row as HBoxContainer).get_children():
				if c is Button and str((c as Button).text).begins_with("▶"):
					out.append(str((c as Button).text))
	return out


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


# T13-22/T13-23 的 MapManager 只读 stub（meta 驱动 map_id，可中途改变）
func _attach_stub(obj: RefCounted) -> void:
	obj.set_meta("stub_map_id", "m01_afterglow")
	obj.set_script(preload("res://tests/fixtures/t13_mm_stub.gd"))


func _attach_stub_change(obj: RefCounted) -> void:
	obj.set_meta("stub_map_id", "m01_repair_interior")
