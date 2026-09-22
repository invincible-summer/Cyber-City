## m01_repair_interior「余晖维修·店内」最终组装（chapter1-3 §3 + manifest v2）。
## 运行：godot --headless --path . --script res://tools/assemble_interior.gd
## 职责：展平嵌入 interior_generated → map.tscn（BakedWorld/Backdrop/Environment/
##       CameraAnchors/Ambient/PortalDoors）；写 v2 定义（walk/portals）与 manifest v2。
## 规则同 assemble_m01：assemble 不再无条件清空烘焙数据（C13-01）；
## 必需输出 Error 必须传播（C13-21）；owner 不进实例内部。
extends SceneTree

const MAP_DEF_SCRIPT := preload("res://scripts/maps/map_definition.gd")
const BC := preload("res://tools/build_contract.gd")

const MAP_DIR := "res://maps/m01_repair_interior"
const GEN_SPEC := MAP_DIR + "/generated/interior_spec.json"
const GEN_SCENE := MAP_DIR + "/generated/interior_generated.tscn"
const MAP_SCENE := MAP_DIR + "/map.tscn"
const MAP_DEF := MAP_DIR + "/map_definition.tres"
const MANIFEST_PATH := MAP_DIR + "/build_manifest.json"
const BAKED_DATA := MAP_DIR + "/baked/map_lightmap.res"
## bake_source_roots（§2.3）
const BAKE_SOURCE_ROOTS: PackedStringArray = [
	"res://maps/m01_repair_interior/generated/interior_generated.tscn",
]

var spec: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== assemble m01_repair_interior ===")
	spec = BC.load_json_dict(GEN_SPEC)
	if spec.is_empty():
		push_error("室内规格缺失或不可解析，先运行 build_interior.gd")
		quit(1)
		return
	if not ResourceLoader.exists(GEN_SCENE):
		push_error("生成场景缺失")
		quit(1)
		return

	var root := _build_map()
	var lm: LightmapGI = BC.find_lightmap(root)
	var expected := BC.expected_bake_users(root)
	var signature := BC.compute_bake_signature(BAKE_SOURCE_ROOTS, root)
	if str(signature.get("bake_input_hash", "")) == "":
		push_error("bake 输入签名计算失败：LightmapGI 缺失")
		quit(1)
		return
	var prev := BC.load_json_dict(MANIFEST_PATH)
	var reuse := BC.can_reuse_bake(prev, BAKE_SOURCE_ROOTS, str(signature.get("bake_input_hash", "")), expected, BAKED_DATA)
	var actual: Array[String] = []
	if reuse:
		var fresh := BC.load_resource_fresh(BAKED_DATA, "LightmapGIData") as LightmapGIData
		if fresh == null:
			push_error("可复用分支 fresh-load 烘焙数据失败")
			quit(1)
			return
		lm.light_data = fresh
		var probe := LightmapGI.new()
		probe.light_data = fresh
		actual = BC.actual_bake_users(probe)
		print("ASSEMBLE: 复用有效烘焙数据 users=%d" % actual.size())
	else:
		# 先持久化 pending/stale，成功后才允许清空烘焙数据（§3.2）
		var status := "pending" if prev.is_empty() else "stale"
		if not prev.is_empty() and int(prev.get("schema_version", 0)) == 1:
			status = "stale"
		var m_err := _write_manifest_state(status, signature, expected, [], "", "")
		if m_err != OK:
			push_error("预失效清单写入失败 err=%d，保持旧烘焙数据不动" % m_err)
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(BAKED_DATA.get_base_dir())
		var empty := LightmapGIData.new()
		if ResourceSaver.save(empty, BAKED_DATA) != OK:
			push_error("空 LightmapGIData 保存失败")
			quit(1)
			return
		var fresh := BC.load_resource_fresh(BAKED_DATA, "LightmapGIData") as LightmapGIData
		if fresh == null:
			push_error("空烘焙数据 fresh-load 失败")
			quit(1)
			return
		lm.light_data = fresh
		print("ASSEMBLE: 烘焙数据已失效（%s），等待重烘" % status)

	var ps := PackedScene.new()
	_set_all_owners(root, root)
	var err := ps.pack(root)
	if err != OK:
		push_error("pack 失败: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, MAP_SCENE)
	if err != OK:
		push_error("map.tscn 保存失败: %d" % err)
		quit(1)
		return
	print("map.tscn saved: ", err)
	if _save_definition() != OK:
		quit(1)
		return
	if reuse:
		var m_err := _write_manifest_state("succeeded", signature, expected, actual,
			str(prev.get("bake_job_id", "")), str(prev.get("bake_finished_utc", "")))
		if m_err != OK:
			push_error("复用分支清单写入失败 err=%d" % m_err)
			quit(1)
			return
	print("ASSEMBLE_INTERIOR_DONE")
	quit(0)


func _build_map() -> Node3D:
	var root := Node3D.new()
	root.name = "M01RepairInterior"
	root.set_script(load("res://scripts/maps/map_root.gd"))

	# BakedWorld = LightmapGI（不在此写烘焙数据；由 can_reuse_bake 分支决定，C13-01）
	var lm := LightmapGI.new()
	lm.name = "BakedWorld"
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

func _save_definition() -> Error:
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
	if err != OK:
		push_error("map_definition.tres 保存失败: %d" % err)
		return err
	print("definition saved: ", err, " anchors=", anchor_ids.size(),
		" exclusions=", exclusions.size(), " walk=", walks.size(), " portals=", portals.size())
	return OK


# ============================ manifest v2（§2.5） ============================

func _write_manifest_state(status: String, signature: Dictionary, expected: Array[String],
		actual: Array[String], job_id: String, finished_utc: String) -> Error:
	## 唯一的 v2 清单写入口：可恢复替换（write_json_recoverable），调用方必须检查 Error。
	var actual_arr: Array = []
	for p in actual:
		actual_arr.append(p)
	var manifest := {
		"schema_version": 2,
		"map_id": "m01_repair_interior",
		"content_revision": str(spec.get("content_revision", "1.2.0")),
		"engine_version": str(Engine.get_version_info().get("string", "")),
		"build_id": _build_id(),
		"bake_source_roots": BAKE_SOURCE_ROOTS,
		"bake_input_hash": str(signature.get("bake_input_hash", "")),
		"bake_input_files": signature.get("bake_input_files", []),
		"bake_settings": signature.get("bake_settings", {}),
		"environment_snapshot": signature.get("environment_snapshot", {}),
		"bake_job_id": job_id,
		"bake_status": status,
		"expected_baked_user_paths": expected,
		"actual_baked_user_paths": actual_arr,
		"missing_baked_user_paths": [],
		"bake_finished_utc": finished_utc,
		"outputs": [],
	}
	var err := BC.write_json_recoverable(MANIFEST_PATH, manifest)
	if err == OK:
		print("manifest saved: ", MANIFEST_PATH, " status=", status)
	else:
		push_error("manifest 可恢复替换失败 err=%d" % err)
	return err


func _build_id() -> String:
	var env := OS.get_environment("NEON_BUILD_ID")
	if not env.is_empty():
		return env
	return "local-%s" % Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")


# ============================ 辅助 ============================

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
