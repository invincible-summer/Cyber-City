## 构建验证（chapter1-3 §6.4 verify v2，完全只读）。
## 运行：godot --headless --path . --script res://tools/verify_build.gd [--map <id>]
## 无 --map 时验证注册表内全部生产地图。
## verify 从 registry 枚举（不按 map_id 硬编码 MAP_CONFIGS）；manifest 路径由
## def.scene_path 推导；按 bake_source_roots 重算 bake_input_hash；从真实
## LightmapGIData fresh-load 读 actual；校验 portal 目标图/锚点（§16.3）。
## 本脚本绝不写 res://：不建基线、不修数据、不顺手更新任何被测对象（C13-04/H3）。
extends SceneTree

const BC := preload("res://tools/build_contract.gd")
const REGISTRY_PATH := "res://data/map_registry.json"

var failures: Array[String] = []
var checks := 0
var _defs: Dictionary = {}  # map_id -> MapDefinition（portal 完整性需要）


func _check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", label)
	else:
		failures.append(label)
		printerr("FAIL: ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== verify_build v2（registry 枚举，只读） ===")
	var map_ids := _maps_to_verify()
	if map_ids.is_empty():
		failures.append("无可验证地图（注册表为空/非法或 --map 未匹配）")
	else:
		# 先加载全部生产定义：portal 完整性需要跨图查询（§16.3），
		# --map 只缩小"全量校验"范围，不缩小跨图引用检查范围。
		for map_id in _all_registry_ids():
			var def_path := _definition_path(map_id)
			if def_path.is_empty():
				failures.append("[%s] 注册表 definition_path 缺失" % map_id)
				continue
			var def := load(def_path) as MapDefinition
			if def == null:
				failures.append("[%s] 定义不可加载: %s" % [map_id, def_path])
				continue
			_defs[map_id] = def
		for map_id in map_ids:
			if _defs.has(str(map_id)):
				print("--- 地图 %s ---" % map_id)
				_verify_map(str(map_id), _defs[str(map_id)])
	if failures.is_empty():
		print("=== verify_build 通过（%d 项检查） ===" % checks)
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== verify_build 失败 %d 项 ===" % failures.size())
		quit(1)


func _all_registry_ids() -> Array[String]:
	var reg := BC.load_json_dict(REGISTRY_PATH)
	var out: Array[String] = []
	var seen := {}
	for m in reg.get("maps", []):
		var mid := str(m.get("map_id", ""))
		if not mid.is_empty() and not seen.has(mid):
			seen[mid] = true
			out.append(mid)
	return out


func _maps_to_verify() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	var wanted := ""
	for i in range(args.size()):
		if args[i] == "--map" and i + 1 < args.size():
			wanted = args[i + 1]
	var reg := BC.load_json_dict(REGISTRY_PATH)
	var out: Array[String] = []
	var seen := {}
	for m in reg.get("maps", []):
		var mid := str(m.get("map_id", ""))
		if mid.is_empty() or seen.has(mid):
			continue
		seen[mid] = true
		if wanted.is_empty() or mid == wanted:
			out.append(mid)
	if not wanted.is_empty() and out.is_empty():
		printerr("未知地图 ID（不在注册表内）: %s" % wanted)
	return out


func _definition_path(map_id: String) -> String:
	var reg := BC.load_json_dict(REGISTRY_PATH)
	for m in reg.get("maps", []):
		if str(m.get("map_id", "")) == map_id:
			return str(m.get("definition_path", ""))
	return ""


func _verify_map(map_id: String, def: MapDefinition) -> void:
	var prefix := "[%s] " % map_id
	var scene_path: String = def.scene_path
	var scene_dir := scene_path.get_base_dir()
	var manifest_path := scene_dir.path_join("build_manifest.json")
	var baked_path := scene_dir.path_join("baked/map_lightmap.res")
	_check(def.validate() == "", prefix + "定义 validate 通过")
	_check(FileAccess.file_exists(scene_path), prefix + "map.tscn 存在")
	_check(FileAccess.file_exists(manifest_path), prefix + "build_manifest.json 存在")

	# 1. manifest v2 与输入签名（§6.4）
	var manifest := BC.load_json_dict(manifest_path)
	_check(not manifest.is_empty(), prefix + "清单可解析")
	var inst: Node = null
	if not manifest.is_empty():
		_check(int(manifest.get("schema_version", 0)) == 2, prefix + "清单 schema_version=2")
		_check(str(manifest.get("map_id", "")) == map_id, prefix + "清单 map_id 一致")
		_check(str(manifest.get("content_revision", "")) == str(def.content_revision),
			prefix + "清单与定义 content_revision 一致（%s）" % str(def.content_revision))
		_check(str(manifest.get("bake_status", "")) == "succeeded", prefix + "bake_status=succeeded")
		var roots: PackedStringArray = PackedStringArray()
		for r in manifest.get("bake_source_roots", []):
			roots.append(String(r))
		_check(roots.size() > 0, prefix + "bake_source_roots 非空")
		var roots_ok := roots.size() > 0
		for r in roots:
			if not String(r).begins_with("res://") or not FileAccess.file_exists(String(r)):
				roots_ok = false
		_check(roots_ok, prefix + "bake_source_roots 均存在且位于 res://")
		if roots_ok and ResourceLoader.exists(scene_path):
			var scene := load(scene_path) as PackedScene
			_check(scene != null, prefix + "map.tscn 可加载")
			if scene != null:
				inst = scene.instantiate()
				# 从最终场景重算当前签名/期望（与 assemble 同一 BuildContract 实现）
				var signature := BC.compute_bake_signature(roots, inst)
				_check(str(signature.get("bake_input_hash", "")) == str(manifest.get("bake_input_hash", "")),
					prefix + "bake_input_hash 与当前输入一致（未过期）")
				var cur_expected := BC.expected_bake_users(inst)
				var manifest_expected: Array = manifest.get("expected_baked_user_paths", [])
				var me_sorted: Array = manifest_expected.duplicate()
				me_sorted.sort()
				var ce_sorted: Array = []
				for p in cur_expected:
					ce_sorted.append(p)
				ce_sorted.sort()
				_check(me_sorted == ce_sorted and not ce_sorted.is_empty(),
					prefix + "expected_baked_user_paths 与当前场景结构一致（%d 项）" % ce_sorted.size())
				# 从磁盘真实数据读 actual（fresh-load，不信缓存也不信清单）
				var fresh := BC.load_resource_fresh(baked_path, "LightmapGIData") as LightmapGIData
				_check(fresh != null, prefix + "烘焙数据可 fresh-load")
				var actual: Array[String] = []
				if fresh != null:
					var probe := LightmapGI.new()
					probe.light_data = fresh
					actual = BC.actual_bake_users(probe)
				var missing := BC.missing_paths(cur_expected, actual)
				_check(missing.is_empty(), prefix + "烘焙覆盖无缺失（missing=%d）" % missing.size())
				var manifest_actual: Array = manifest.get("actual_baked_user_paths", [])
				var ma_sorted: Array = manifest_actual.duplicate()
				ma_sorted.sort()
				var ac_sorted: Array = []
				for p in actual:
					ac_sorted.append(p)
				ac_sorted.sort()
				_check(ma_sorted == ac_sorted, prefix + "清单 actual 与磁盘真实 actual 集合一致")
				_check((manifest.get("missing_baked_user_paths", []) as Array).is_empty(),
					prefix + "清单 missing 为空")

	# 2. 运行时合同 + 锚点容器（沿既有口径）
	if inst != null:
		inst.definition = def
		var contract_errors: PackedStringArray = inst.validate_runtime_contract()
		if contract_errors.is_empty():
			print("PASS: ", prefix + "运行时合同校验通过")
			checks += 1
		else:
			for e in contract_errors:
				printerr("VERIFY-CONTRACT[%s]: %s" % [map_id, e])
			failures.append(prefix + "运行时合同校验失败")
		_check(inst.get_node_or_null("CameraAnchors") != null, prefix + "锚点容器存在")
		_check(inst.get_node_or_null("Environment") != null, prefix + "环境存在")
		inst.free()

	# 3. 门户完整性（§16.3：目标在注册表、定义合法、锚点存在；不加载目标 3D 场景）
	for p in def.portals:
		var tid := str(p.get("target_map_id", ""))
		var tanchor := str(p.get("target_anchor", ""))
		_check(_defs.has(tid), prefix + "门户目标 %s 在注册表" % tid)
		if _defs.has(tid):
			var tdef: MapDefinition = _defs[tid]
			_check(tdef.validate() == "", prefix + "门户目标 %s 定义合法" % tid)
			_check(tdef.anchor_names.has(tanchor), prefix + "门户目标锚点 %s/%s 存在" % [tid, tanchor])

	# 4. walk 图合同（沿 chapter1-2 §9.3）
	if def.camera_mode == "walk":
		_check(not def.walk_surfaces.is_empty(), prefix + "walk_surfaces 非空")
		var anchors_holder := _load_anchors_holder(scene_path)
		for anchor_id in def.anchor_names:
			if not anchors_holder.has(str(anchor_id)):
				failures.append(prefix + "锚点 %s 场景内缺失" % anchor_id)
				checks += 1
				continue
			var eye_y: float = anchors_holder[str(anchor_id)]
			var matched := false
			for w in def.walk_surfaces:
				if absf(w.position.y + w.size.y + 1.62 - eye_y) <= 0.02:
					matched = true
					break
			checks += 1
			if matched:
				print("PASS: ", prefix + "锚点 %s 眼高贴合行走面（y=%.3f）" % [anchor_id, eye_y])
			else:
				failures.append(prefix + "锚点 %s 眼高无行走面对应（y=%.3f）" % [anchor_id, eye_y])

	print("VERIFY: %s 锚点数=%d 禁入体积=%d bounds=%s" % [map_id, def.anchor_names.size(), def.camera_exclusion_bounds.size(), str(def.camera_bounds)])


func _load_anchors_holder(scene_path: String) -> Dictionary:
	## 返回 {anchor_id: position.y}；场景不可载时返回空表（只读实例，检完即释放）。
	if not ResourceLoader.exists(scene_path):
		return {}
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return {}
	var inst := scene.instantiate()
	var out := {}
	var holder := inst.get_node_or_null("CameraAnchors")
	if holder != null:
		for c in holder.get_children():
			if c is Node3D:
				out[str(c.name)] = (c as Node3D).position.y
	inst.free()
	return out
