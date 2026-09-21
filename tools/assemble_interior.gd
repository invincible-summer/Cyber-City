## m01_repair_interior「余晖维修·店内」最终组装（chapter1-2 §6）。
## 运行：godot --headless --path . --script res://tools/assemble_interior.gd
## 职责：展平嵌入 interior_generated → map.tscn（BakedWorld/Backdrop/Environment/
##       CameraAnchors/Ambient/PortalDoors）；写 v2 定义（walk/portals）与构建清单指纹。
## 规则同 assemble_m01：LightmapGI 子树内不放 PackedScene 实例（X2 复制问题），
## owner 不进实例内部；烘焙数据落 baked/map_lightmap.res。
extends SceneTree

const MAP_DEF_SCRIPT := preload("res://scripts/maps/map_definition.gd")

const MAP_DIR := "res://maps/m01_repair_interior"
const GEN_SPEC := MAP_DIR + "/generated/interior_spec.json"
const GEN_SCENE := MAP_DIR + "/generated/interior_generated.tscn"
const MAP_SCENE := MAP_DIR + "/map.tscn"
const MAP_DEF := MAP_DIR + "/map_definition.tres"
const MANIFEST_PATH := MAP_DIR + "/build_manifest.json"
const FONT_SOURCE := "res://assets/fonts/source/NotoSansSC-Regular.otf"

var spec: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== assemble m01_repair_interior ===")
	spec = _load_json(GEN_SPEC)
	if spec.is_empty():
		push_error("室内规格缺失，先运行 build_interior.gd")
		quit(1)
		return
	if not ResourceLoader.exists(GEN_SCENE):
		push_error("生成场景缺失")
		quit(1)
		return

	var root := _build_map()
	var ps := PackedScene.new()
	_set_all_owners(root, root)
	var err := ps.pack(root)
	if err != OK:
		push_error("pack 失败: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, MAP_SCENE)
	print("map.tscn saved: ", err)
	_save_definition()
	_write_manifest()
	print("ASSEMBLE_INTERIOR_DONE")
	quit(0)


func _build_map() -> Node3D:
	var root := Node3D.new()
	root.name = "M01RepairInterior"
	root.set_script(load("res://scripts/maps/map_root.gd"))

	# BakedWorld = LightmapGI（预存空数据；烘焙有效性由清单指纹判定）
	var lm := LightmapGI.new()
	lm.name = "BakedWorld"
	const BAKED_DATA := "res://maps/m01_repair_interior/baked/map_lightmap.res"
	DirAccess.make_dir_recursive_absolute(BAKED_DATA.get_base_dir())
	var fresh := LightmapGIData.new()
	if ResourceSaver.save(fresh, BAKED_DATA) == OK:
		lm.light_data = load(BAKED_DATA)
	root.add_child(lm)

	# 展平嵌入生成场景：StaticGeometry/Lighting/PortalDoors 入 LightmapGI 子树，
	# Backdrop 独立为 MapRoot 直接子节点（不参与烘焙扫描）。
	var gen_scene := load(GEN_SCENE) as PackedScene
	var gi := gen_scene.instantiate()
	var baked_container := Node3D.new()
	baked_container.name = "Generated"
	lm.add_child(baked_container)
	var backdrop: Node3D = null
	for child in gi.get_children():
		gi.remove_child(child)
		if str(child.name) == "Backdrop":
			backdrop = child
			root.add_child(child)
		else:
			baked_container.add_child(child)
	gi.free()
	baked_container.owner = root

	# CameraAnchors
	var anchors := Node3D.new()
	anchors.name = "CameraAnchors"
	for anchor_id in spec.get("anchors", {}):
		var a: Dictionary = spec["anchors"][anchor_id]
		var m := Marker3D.new()
		m.name = str(anchor_id)
		m.transform = Transform3D(Basis(), _v3(a["pos"])).looking_at(_v3(a["look"]), Vector3.UP)
		anchors.add_child(m)
	root.add_child(anchors)

	# Reserved
	var reserved := Node3D.new()
	reserved.name = "Reserved"
	var actor_root := Node3D.new()
	actor_root.name = "ActorRoot"
	reserved.add_child(actor_root)
	root.add_child(reserved)

	# Ambient（吊扇 ×2 + flicker ×2；粒子 0）
	var ambient := Node3D.new()
	ambient.name = "Ambient"
	for fp in spec.get("fans", []):
		var pivot := Node3D.new()
		pivot.name = "FanPivot"
		pivot.position = _v3(fp["pos"] if fp.has("pos") else fp)
		pivot.rotation_degrees = Vector3(90, 0, 0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.22
		cm.height = 0.035
		cm.radial_segments = 10
		mi.mesh = cm
		mi.material_override = load("res://assets/m01_afterglow/materials/metal_dark.tres")
		mi.set_meta("anim_rotate", true)
		mi.set_meta("anim_axis", "y")
		mi.set_meta("anim_speed", 3.0)
		pivot.add_child(mi)
		ambient.add_child(pivot)
	for fl in spec.get("flickers", []):
		var mat := _flicker_material(str(fl.get("mat_key", "")))
		if mat == null:
			push_warning("assemble_interior: flicker 材质缺失 %s" % str(fl.get("mat_key", "")))
			continue
		var fmi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(float(fl["size"][0]), float(fl["size"][1]))
		fmi.mesh = qm
		fmi.material_override = mat
		fmi.position = _v3(fl["pos"])
		fmi.rotation_degrees.y = float(fl.get("rot_y", 0.0))
		fmi.set_meta("anim_flicker", true)
		ambient.add_child(fmi)
	root.add_child(ambient)

	# Environment（唯一 WorldEnvironment）：室内黄昏基调——环境基底压低，
	# 让烘焙光主导冷暖层次；窗外天空与街区图同源的蓝调。
	root.add_child(_build_environment())
	return root


func _flicker_material(mat_key: String) -> StandardMaterial3D:
	## 共享键走 .tres；室内内联材质在此重建（flicker 面本就独立于网格材质）。
	var path := "res://assets/m01_afterglow/materials/%s.tres" % mat_key
	if ResourceLoader.exists(path):
		return (load(path) as StandardMaterial3D).duplicate()
	var mat := StandardMaterial3D.new()
	match mat_key:
		"terminal_screen":
			mat.albedo_color = Color(0.06, 0.10, 0.12)
			mat.emission_enabled = true
			mat.emission = Color(0.30, 0.92, 0.86)
			mat.emission_energy_multiplier = 1.6
		"vending_panel":
			mat.albedo_color = Color(0.10, 0.18, 0.20)
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.85, 0.80)
			mat.emission_energy_multiplier = 1.4
		_:
			return null
	return mat


func _build_environment() -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.07, 0.11, 0.21)
	sky_mat.sky_horizon_color = Color(0.55, 0.40, 0.35)
	sky_mat.ground_bottom_color = Color(0.04, 0.05, 0.07)
	sky_mat.ground_horizon_color = Color(0.35, 0.29, 0.28)
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35  # 室内环境基底低于街区：烘焙光主导
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.40, 0.44, 0.52)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.4
	env.glow_enabled = true  # 运行时由画质档开关
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	we.environment = env
	return we


# ============================ 定义 ============================

func _save_definition() -> void:
	var def := MAP_DEF_SCRIPT.new()
	def.schema_version = 2
	def.map_id = "m01_repair_interior"
	def.display_name = str(spec.get("display_name", "余晖维修·店内"))
	def.scene_path = MAP_SCENE
	def.preview_path = ""
	def.default_anchor = str(spec.get("default_anchor", "entry_view"))
	var b: Array = spec.get("bounds", [0.45, 1.5, -5.6, 13.15, 4.5, 11.2])
	def.camera_bounds = AABB(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]))
	var exclusions: Array[AABB] = []
	for e in spec.get("exclusions", []):
		exclusions.append(AABB(Vector3(e[0], e[1], e[2]), Vector3(e[3], e[4], e[5])))
	def.camera_exclusion_bounds = exclusions
	var anchor_ids := PackedStringArray()
	for k in spec.get("anchors", {}):
		anchor_ids.append(String(k))
	def.anchor_names = anchor_ids
	def.lighting_profile_id = str(spec.get("lighting_profile_id", "m01_interior_dusk_v12"))
	def.available = true
	def.content_revision = str(spec.get("content_revision", "1.2.0"))
	def.region_manifest_path = ""
	def.occlusion_enabled = false  # 单个小室内，遮挡剔除无收益
	def.bookmark_schema_version = 1
	def.requires_baked_lighting = true
	# chapter1-2 §4
	def.camera_mode = str(spec.get("camera_mode", "walk"))
	var walks: Array[AABB] = []
	for w in spec.get("walk_surfaces", []):
		walks.append(AABB(Vector3(w[0], w[1], w[2]), Vector3(w[3], w[4], w[5])))
	def.walk_surfaces = walks
	var portals: Array[Dictionary] = []
	for p in spec.get("portals", []):
		portals.append({
			"pos": Vector3(p["pos"][0], p["pos"][1], p["pos"][2]),
			"radius": float(p["radius"]),
			"target_map_id": str(p["target_map_id"]),
			"target_anchor": str(p["target_anchor"]),
			"label": str(p["label"]),
		})
	def.portals = portals
	var err := ResourceSaver.save(def, MAP_DEF)
	print("definition saved: ", err, " anchors=", anchor_ids.size(),
		" exclusions=", exclusions.size(), " walk=", walks.size(), " portals=", portals.size())


# ============================ 构建清单 ============================

func _write_manifest() -> void:
	var files := [
		"maps/m01_repair_interior/generated/interior_generated.tscn",
		"maps/m01_repair_interior/meshes/interior_static.res",
		"maps/m01_repair_interior/meshes/interior_glass.res",
		"maps/m01_repair_interior/meshes/interior_backdrop.res",
		"maps/m01_repair_interior/meshes/interior_door_leaf.res",
	]
	var combined := _hash_files(files)
	var font_hash := ""
	if FileAccess.file_exists(FONT_SOURCE):
		font_hash = FileAccess.get_sha256(FONT_SOURCE)
	var prev := _load_json(MANIFEST_PATH)
	var bake_status := "pending"
	var bake_job_id := ""
	var actual: Array = prev.get("actual_baked_user_paths", []) if str(prev.get("geometry_input_hash", "")) == combined else []
	if str(prev.get("geometry_input_hash", "")) == combined and str(prev.get("bake_status", "")) == "succeeded":
		bake_status = "succeeded"
		bake_job_id = str(prev.get("bake_job_id", ""))
	elif not prev.is_empty():
		bake_status = "stale"
	var manifest := {
		"schema_version": 1,
		"map_id": "m01_repair_interior",
		"content_revision": str(spec.get("content_revision", "1.2.0")),
		"engine_version": str(Engine.get_version_info().get("string", "")),
		"build_id": _build_id(),
		"geometry_input_hash": combined,
		"lighting_input_hash": combined,
		"authored_input_hash": "",
		"font_source_hash": font_hash,
		"bake_job_id": bake_job_id,
		"bake_status": bake_status,
		"expected_baked_user_paths": [],
		"actual_baked_user_paths": actual,
		"outputs": [],
	}
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("manifest saved: ", MANIFEST_PATH)


func _hash_files(paths: Array) -> String:
	## 文件清单指纹：路径 + 内容哈希串联后再哈希。清单自身与烘焙输出不入列（避免循环依赖）。
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


func _build_id() -> String:
	var env := OS.get_environment("NEON_BUILD_ID")
	if not env.is_empty():
		return env
	return "local-%s" % Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")


# ============================ 辅助 ============================

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _v3(arr: Variant) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


func _set_all_owners(node: Node, root: Node, inside_instance: bool = false) -> void:
	for child in node.get_children():
		if child == root:
			continue
		if not inside_instance:
			child.owner = root
		_set_all_owners(child, root, inside_instance or not str(child.scene_file_path).is_empty())
