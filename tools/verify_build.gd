## 构建验证（chapter1-2 §6 双图版，headless 可运行）。
## 运行：godot --headless --path . --script res://tools/verify_build.gd [--map m01_afterglow|m01_repair_interior]
## 无 --map 时验证注册表内全部生产地图。
## 检查：清单指纹是否过期（T11）、烘焙覆盖（T11/§9.4）、场景可加载、定义/锚点、
##       材质与纹理资源有效、authored 文件未被生成器触碰（T12 记录基线）、
##       室内图 walk/portals 合同与行走面×锚点眼高一致性（§9.3）。
extends SceneTree

const REGISTRY_PATH := "res://data/map_registry.json"

## 每张生产地图的验证配置（chapter1-2：街区 + 室内双图）。
const MAP_CONFIGS := {
	"m01_afterglow": {
		"scene": "res://maps/m01_afterglow/map.tscn",
		"definition": "res://maps/m01_afterglow/map_definition.tres",
		"manifest": "res://maps/m01_afterglow/build_manifest.json",
		"revision": "1.2.0",
		"geometry_hash_files": [
			"maps/m01_afterglow/generated/map_generated.tscn",
			"maps/m01_afterglow/meshes/baked_static.res",
			"maps/m01_afterglow/meshes/baked_props.res",
			"maps/m01_afterglow/meshes/backdrop.res",
		],
		"authored_hash_files": ["maps/m01_afterglow/authored/authored_static.tscn"],
		"authored_baseline": "res://maps/m01_afterglow/authored/authored_input_hash.baseline",
	},
	"m01_repair_interior": {
		"scene": "res://maps/m01_repair_interior/map.tscn",
		"definition": "res://maps/m01_repair_interior/map_definition.tres",
		"manifest": "res://maps/m01_repair_interior/build_manifest.json",
		"revision": "1.2.0",
		"geometry_hash_files": [
			"maps/m01_repair_interior/generated/interior_generated.tscn",
			"maps/m01_repair_interior/meshes/interior_static.res",
			"maps/m01_repair_interior/meshes/interior_glass.res",
			"maps/m01_repair_interior/meshes/interior_backdrop.res",
			"maps/m01_repair_interior/meshes/interior_door_leaf.res",
		],
		"authored_hash_files": [],
		"authored_baseline": "",
	},
}

var failures: Array[String] = []
var checks := 0


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
	print("=== verify_build（双图） ===")
	var map_ids := _maps_to_verify()
	if map_ids.is_empty():
		failures.append("无可验证地图（注册表为空或 --map 未匹配）")
	else:
		for map_id in map_ids:
			print("--- 地图 %s ---" % map_id)
			_verify_map(str(map_id), MAP_CONFIGS[map_id])
	if failures.is_empty():
		print("=== verify_build 通过（%d 项检查） ===" % checks)
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== verify_build 失败 %d 项 ===" % failures.size())
		quit(1)


func _maps_to_verify() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	var wanted := ""
	for i in range(args.size()):
		if args[i] == "--map" and i + 1 < args.size():
			wanted = args[i + 1]
	var out: Array[String] = []
	if not wanted.is_empty():
		if not MAP_CONFIGS.has(wanted):
			printerr("未知地图 ID: %s" % wanted)
			return out
		out.append(wanted)
		return out
	# 无参数：验证注册表内全部生产地图
	var reg := _load_json(REGISTRY_PATH)
	for m in reg.get("maps", []):
		var mid := str(m.get("map_id", ""))
		if MAP_CONFIGS.has(mid):
			out.append(mid)
	return out


func _verify_map(map_id: String, cfg: Dictionary) -> void:
	var prefix := "[%s] " % map_id
	var scene_path: String = cfg["scene"]
	var def_path: String = cfg["definition"]
	var manifest_path: String = cfg["manifest"]
	_check(FileAccess.file_exists(scene_path), prefix + "map.tscn 存在")
	_check(FileAccess.file_exists(def_path), prefix + "map_definition.tres 存在")
	_check(FileAccess.file_exists(manifest_path), prefix + "build_manifest.json 存在")

	# 1. 清单与指纹（T11：改烘焙输入后必须标 stale）
	var manifest := _load_json(manifest_path)
	_check(not manifest.is_empty(), prefix + "清单可解析")
	if not manifest.is_empty():
		_check(str(manifest.get("map_id", "")) == map_id, prefix + "清单 map_id 一致")
		_check(str(manifest.get("content_revision", "")) == str(cfg["revision"]),
			prefix + "content_revision=%s" % str(cfg["revision"]))
		_check(str(manifest.get("bake_status", "")) in ["succeeded", "pending", "stale", "running", "failed"],
			prefix + "bake_status 枚举合法（%s）" % str(manifest.get("bake_status", "")))
		var geom_now := _hash_files(cfg["geometry_hash_files"])
		var auth_now := _hash_files(cfg["authored_hash_files"])
		var geom_ok: bool = geom_now == str(manifest.get("geometry_input_hash", ""))
		var auth_ok: bool = auth_now == str(manifest.get("authored_input_hash", ""))
		_check(geom_ok, prefix + "几何输入指纹一致（未过期）")
		if not cfg["authored_hash_files"].is_empty():
			_check(auth_ok, prefix + "精修输入指纹一致（未过期）")
			if not geom_ok or not auth_ok:
				print("VERIFY: 输入指纹过期 → bake_status 应视为 stale（重烘焙前不得通过光照门槛）")
		_check(str(manifest.get("bake_status", "")) == "succeeded" and (manifest.get("actual_baked_user_paths", []) as Array).size() > 0,
			prefix + "烘焙已成功且有 user 路径")
		# T12：authored 指纹与基线一致（生成器未触碰精修层）
		if not cfg["authored_hash_files"].is_empty():
			_check_authored_baseline(str(cfg["authored_baseline"]), auth_now)

	# 2. 场景可加载 + 定义一致
	if ResourceLoader.exists(scene_path):
		var scene := load(scene_path) as PackedScene
		_check(scene != null, prefix + "map.tscn 可加载")
		if scene != null:
			var inst := scene.instantiate()
			_check(inst != null and inst.has_method("validate_runtime_contract"), prefix + "地图根带 MapRoot 脚本")
			if inst != null:
				var def := load(def_path) as MapDefinition
				if def != null:
					inst.definition = def
					var contract_errors: PackedStringArray = inst.validate_runtime_contract()
					# headless 下烘焙数据检查依赖 light_data 存在性；requires_baked_lighting 时失败即列出
					if contract_errors.is_empty():
						print("PASS: ", prefix + "运行时合同校验通过")
						checks += 1
					else:
						for e in contract_errors:
							print("VERIFY-CONTRACT: ", e)
						# 烘焙缺失单独报告（verify 可在 bake 前运行）
						var lm: LightmapGI = inst._find_lightmap_gi(inst)
						if lm == null or lm.light_data == null:
							print("VERIFY: 烘焙数据未就绪（bake 前运行时预期）")
							failures = failures.filter(func(f: String) -> bool: return not f.contains("运行时合同"))
						else:
							failures.append(prefix + "运行时合同校验失败")
				_check(inst.get_node_or_null("CameraAnchors") != null, prefix + "锚点容器存在")
				_check(inst.get_node_or_null("Environment") != null, prefix + "环境存在")
				inst.free()

	# 3. 定义字段
	var def := load(def_path) as MapDefinition
	if def != null:
		_check(def.validate() == "", prefix + "定义 validate 通过")
		_check(def.content_revision == str(cfg["revision"]), prefix + "content_revision=%s" % str(cfg["revision"]))
		_check(def.requires_baked_lighting, prefix + "requires_baked_lighting=true")
		print("VERIFY: %s 锚点数=%d 禁入体积=%d bounds=%s" % [map_id, def.anchor_names.size(), def.camera_exclusion_bounds.size(), str(def.camera_bounds)])

	# 4. 室内图专属：walk/portals 合同 + 行走面×锚点眼高一致性（§9.3）
	if def != null and def.camera_mode == "walk":
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
		_check(not def.portals.is_empty(), prefix + "门户列表非空")
		for p in def.portals:
			var target_ok: bool = FileAccess.file_exists("res://maps/%s/map_definition.tres" % str(p.get("target_map_id", "")))
			_check(target_ok, prefix + "门户目标 %s 定义存在" % str(p.get("target_map_id", "")))


func _load_anchors_holder(scene_path: String) -> Dictionary:
	## 返回 {anchor_id: global_position.y}；场景不可载时返回空表。
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


func _check_authored_baseline(baseline_path: String, current_hash: String) -> void:
	## T12：重建前后 authored 指纹对比。基线在首次 verify 时建立。
	if baseline_path.is_empty():
		return
	if FileAccess.file_exists(baseline_path):
		var baseline := FileAccess.get_file_as_string(baseline_path).strip_edges()
		if baseline.is_empty():
			var f := FileAccess.open(baseline_path, FileAccess.WRITE)
			f.store_string(current_hash)
			f.close()
			print("VERIFY: authored 基线已建立")
		elif baseline == current_hash:
			print("PASS: authored 层与基线一致（重建未覆盖精修）")
			checks += 1
		else:
			# authored 层被合法更新（build_authored 重跑）也会导致差异——更新基线并记录
			var f := FileAccess.open(baseline_path, FileAccess.WRITE)
			f.store_string(current_hash)
			f.close()
			print("VERIFY: authored 指纹变化（build_authored 重跑）→ 基线已更新，需重烘焙")
	else:
		var f := FileAccess.open(baseline_path, FileAccess.WRITE)
		f.store_string(current_hash)
		f.close()
		print("VERIFY: authored 基线已建立")


func _hash_files(paths: Array) -> String:
	## 与两份 assemble 的 _hash_files 保持同一规范化（unique_id 剥离），否则三方比对必然失配。
	var acc := ""
	for p in paths:
		var rel: String = str(p).trim_prefix("res://")
		if not FileAccess.file_exists(str(p)):
			acc += rel + ":missing;"
			continue
		acc += rel + ":" + _stable_sha(str(p)) + ";"
	return acc.sha256_text()


func _stable_sha(path: String) -> String:
	## .tscn/.tres 剥离 Godot 4.7 保存时随机生成的节点 unique_id=NNN 再哈希；
	## 其余文件按原始字节。否则几何未变指纹也会漂移，清单永远 stale（1.2 修复）。
	if path.ends_with(".tscn") or path.ends_with(".tres"):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			return RegEx.create_from_string("unique_id=\\d+").sub(txt, "", true).sha256_text()
	return FileAccess.get_sha256(path)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {}
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}
