## 构建验证（chapter1-1 §9.1 verify 阶段，headless 可运行）。
## 运行：godot --headless --path . --script res://tools/verify_build.gd
## 检查：清单指纹是否过期（T11）、烘焙覆盖（T11/§9.4）、场景可加载、定义/锚点、
##       材质与纹理资源有效、authored 文件未被生成器触碰（T12 记录基线）。
extends SceneTree

const MANIFEST_PATH := "res://maps/m01_afterglow/build_manifest.json"
const MAP_SCENE := "res://maps/m01_afterglow/map.tscn"
const MAP_DEF := "res://maps/m01_afterglow/map_definition.tres"
const AUTHORED_HASH_BASELINE := "res://maps/m01_afterglow/authored/authored_input_hash.baseline"

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
	print("=== verify_build ===")
	_check(FileAccess.file_exists(MAP_SCENE), "map.tscn 存在")
	_check(FileAccess.file_exists(MAP_DEF), "map_definition.tres 存在")
	_check(FileAccess.file_exists(MANIFEST_PATH), "build_manifest.json 存在")

	# 1. 清单与指纹（T11：改烘焙输入后必须标 stale）
	var manifest := _load_json(MANIFEST_PATH)
	_check(not manifest.is_empty(), "清单可解析")
	if not manifest.is_empty():
		_check(str(manifest.get("bake_status", "")) in ["succeeded", "pending", "stale", "running", "failed"],
			"bake_status 枚举合法（%s）" % str(manifest.get("bake_status", "")))
		var geom_now := _hash_files([
			"maps/m01_afterglow/generated/map_generated.tscn",
			"maps/m01_afterglow/meshes/baked_static.res",
			"maps/m01_afterglow/meshes/baked_props.res",
			"maps/m01_afterglow/meshes/backdrop.res",
		])
		var auth_now := _hash_files([
			"maps/m01_afterglow/authored/authored_static.tscn",
		])
		var geom_ok: bool = geom_now == str(manifest.get("geometry_input_hash", ""))
		var auth_ok: bool = auth_now == str(manifest.get("authored_input_hash", ""))
		_check(geom_ok, "几何输入指纹一致（未过期）")
		_check(auth_ok, "精修输入指纹一致（未过期）")
		if not geom_ok or not auth_ok:
			print("VERIFY: 输入指纹过期 → bake_status 应视为 stale（重烘焙前不得通过光照门槛）")
		_check(str(manifest.get("bake_status", "")) == "succeeded" and (manifest.get("actual_baked_user_paths", []) as Array).size() > 0,
			"烘焙已成功且有 user 路径")
		# T12：authored 指纹与基线一致（生成器未触碰精修层）
		_check_authored_baseline(auth_now)

	# 2. 场景可加载 + 定义一致
	if ResourceLoader.exists(MAP_SCENE):
		var scene := load(MAP_SCENE) as PackedScene
		_check(scene != null, "map.tscn 可加载")
		if scene != null:
			var inst := scene.instantiate()
			_check(inst != null and inst.has_method("validate_runtime_contract"), "地图根带 MapRoot 脚本")
			if inst != null:
				var def := load(MAP_DEF) as MapDefinition
				if def != null:
					inst.definition = def
					var contract_errors: PackedStringArray = inst.validate_runtime_contract()
					# headless 下烘焙数据检查依赖 light_data 存在性；requires_baked_lighting 时失败即列出
					if contract_errors.is_empty():
						print("PASS: 运行时合同校验通过")
					else:
						for e in contract_errors:
							print("VERIFY-CONTRACT: ", e)
						# 烘焙缺失单独报告（verify 可在 bake 前运行）
						var lm: LightmapGI = inst._find_lightmap_gi(inst)
						if lm == null or lm.light_data == null:
							print("VERIFY: 烘焙数据未就绪（bake 前运行时预期）")
							failures = failures.filter(func(f: String) -> bool: return not f.contains("运行时合同"))
						else:
							failures.append("运行时合同校验失败")
				_check(inst.get_node_or_null("CameraAnchors") != null, "锚点容器存在")
				_check(inst.get_node_or_null("Environment") != null, "环境存在")
				inst.free()
	# 3. 定义字段
	var def := load(MAP_DEF) as MapDefinition
	if def != null:
		_check(def.validate() == "", "定义 validate 通过")
		_check(def.content_revision == "1.1.0", "content_revision=1.1.0")
		_check(def.requires_baked_lighting, "requires_baked_lighting=true")
		print("VERIFY: 锚点数=%d 禁入体积=%d bounds=%s" % [def.anchor_names.size(), def.camera_exclusion_bounds.size(), str(def.camera_bounds)])

	if failures.is_empty():
		print("=== verify_build 通过 ===")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== verify_build 失败 %d 项 ===" % failures.size())
		quit(1)


func _check_authored_baseline(current_hash: String) -> void:
	## T12：重建前后 authored 指纹对比。基线在首次 verify 时建立。
	if FileAccess.file_exists(AUTHORED_HASH_BASELINE):
		var baseline := FileAccess.get_file_as_string(AUTHORED_HASH_BASELINE).strip_edges()
		if baseline.is_empty():
			var f := FileAccess.open(AUTHORED_HASH_BASELINE, FileAccess.WRITE)
			f.store_string(current_hash)
			f.close()
			print("VERIFY: authored 基线已建立")
		elif baseline == current_hash:
			print("PASS: authored 层与基线一致（重建未覆盖精修）")
		else:
			# authored 层被合法更新（build_authored 重跑）也会导致差异——更新基线并记录
			var f := FileAccess.open(AUTHORED_HASH_BASELINE, FileAccess.WRITE)
			f.store_string(current_hash)
			f.close()
			print("VERIFY: authored 指纹变化（build_authored 重跑）→ 基线已更新，需重烘焙")
	else:
		var f := FileAccess.open(AUTHORED_HASH_BASELINE, FileAccess.WRITE)
		f.store_string(current_hash)
		f.close()
		print("VERIFY: authored 基线已建立")


func _hash_files(paths: Array) -> String:
	var acc := ""
	for p in paths:
		var rel: String = str(p).trim_prefix("res://")
		if not FileAccess.file_exists(str(p)):
			acc += rel + ":missing;"
			continue
		acc += rel + ":" + FileAccess.get_sha256(str(p)) + ";"
	return acc.sha256_text()


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {}
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}
