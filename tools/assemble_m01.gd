## M01「余晖街区」最终组装（chapter1-3 §3 assemble 状态机 + manifest v2）。
## 运行：godot --headless --path . --script res://tools/assemble_m01.gd
## 职责：组合 generated + authored 两层 → map.tscn；写 MapDefinition v2 与 manifest v2。
## 不再无条件清空烘焙数据：先判 can_reuse_bake，不可复用时先持久化 stale/pending
## 清单，之后才允许写空 LightmapGIData（C13-01）。所有必需输出 Error 必须传播（C13-21）。
extends SceneTree

const GL := preload("res://tools/gen_lib.gd")
const MAP_DEF_SCRIPT := preload("res://scripts/maps/map_definition.gd")
const BC := preload("res://tools/build_contract.gd")

const MAP_DIR := "res://maps/m01_afterglow"
const GENERATED_SPEC := MAP_DIR + "/generated/generated_spec.json"
const AUTHORED_SPEC := MAP_DIR + "/authored/authored_spec.json"
const GENERATED_SCENE := MAP_DIR + "/generated/map_generated.tscn"
const AUTHORED_SCENE := MAP_DIR + "/authored/authored_static.tscn"
const MAP_SCENE := MAP_DIR + "/map.tscn"
const MAP_DEF := MAP_DIR + "/map_definition.tres"
const MANIFEST_PATH := MAP_DIR + "/build_manifest.json"
const BAKED_DATA := MAP_DIR + "/baked/map_lightmap.res"
## bake_source_roots（§2.3）：本地图制作层输入根，递归闭包含 mesh/material/texture。
const BAKE_SOURCE_ROOTS: PackedStringArray = [
	"res://maps/m01_afterglow/generated/map_generated.tscn",
	"res://maps/m01_afterglow/authored/authored_static.tscn",
]
const MAT_DIR := "res://assets/m01_afterglow/materials"

const CONTENT_REVISION := "1.2.0"
# chapter1-1 §3.4：外围 bounds（最终以成品收紧）
const BOUNDS := [-78.0, 1.5, -98.0, 156.0, 26.5, 196.0]

var spec: Dictionary = {}
var authored: Dictionary = {}
var mats := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== assemble M01 ===")
	# 硬前置（C13-05 §6.5.2）：两层规格与场景任一缺失/不可解析都不得组出"看似成功"的街景
	spec = BC.load_json_dict(GENERATED_SPEC)
	if spec.is_empty():
		push_error("生成规格缺失或不可解析，先运行 build_m01.gd")
		quit(1)
		return
	authored = BC.load_json_dict(AUTHORED_SPEC)
	if authored.is_empty():
		push_error("精修规格缺失或不可解析，先运行 build_authored.gd")
		quit(1)
		return
	if not ResourceLoader.exists(GENERATED_SCENE):
		push_error("生成场景缺失")
		quit(1)
		return
	if not ResourceLoader.exists(AUTHORED_SCENE):
		push_error("精修场景缺失")
		quit(1)
		return
	_load_materials()

	var root := _build_map()
	var lm: LightmapGI = BC.find_lightmap(root)
	# 当前结构与输入签名（§3.2 步骤 2–4）
	var expected := BC.expected_bake_users(root)
	var signature := BC.compute_bake_signature(BAKE_SOURCE_ROOTS, root)
	if str(signature.get("bake_input_hash", "")) == "":
		push_error("bake 输入签名计算失败：LightmapGI 缺失")
		quit(1)
		return
	# 复用判定：只看磁盘真实数据，不信清单缓存（§3.2 can_reuse_bake）
	var prev := BC.load_json_dict(MANIFEST_PATH)
	var reuse := BC.can_reuse_bake(prev, BAKE_SOURCE_ROOTS, str(signature.get("bake_input_hash", "")), expected, BAKED_DATA)
	var actual: Array[String] = []
	if reuse:
		# 先绑定有效旧数据（无破坏性写入），最终 succeeded 清单在场景/定义保存成功后落盘
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
		# 先持久化 pending/stale（尚未触碰旧烘焙数据），失败立即退出（§3.2 步骤 7）
		var status := "pending" if prev.is_empty() else "stale"
		if not prev.is_empty() and int(prev.get("schema_version", 0)) == 1:
			status = "stale"  # v1 不继承 succeeded，一次性迁移成本（§2.6）
		var m_err := _write_manifest_state(status, signature, expected, [], "", "")
		if m_err != OK:
			push_error("预失效清单写入失败 err=%d，保持旧烘焙数据不动" % m_err)
			quit(1)
			return
		# 清单已非 succeeded，才允许清空烘焙数据（§3.2 步骤 8）
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
	# 最终清单（§3.2 步骤 11）：reuse → succeeded+真实 actual；invalidated → 保持 pending/stale
	if reuse:
		var m_err := _write_manifest_state("succeeded", signature, expected, actual,
			str(prev.get("bake_job_id", "")), str(prev.get("bake_finished_utc", "")))
		if m_err != OK:
			push_error("复用分支清单写入失败 err=%d" % m_err)
			quit(1)
			return
	print("ASSEMBLE_DONE")
	quit(0)


func _build_map() -> Node3D:
	var root := Node3D.new()
	root.name = "M01Afterglow"
	root.set_script(load("res://scripts/maps/map_root.gd"))

	# BakedWorld：LightmapGI 下双实例（生成层 + 精修层）。
	# 不在此处写烘焙数据：can_reuse_bake 判定后才决定绑定有效旧数据或（清单预失效后）
	# 写空数据（C13-01：assemble 不得"清空 bake 但保留 succeeded"）。
	var lm := LightmapGI.new()
	lm.name = "BakedWorld"
	root.add_child(lm)
	var gen_inst := Node3D.new()
	gen_inst.name = "GeneratedStatic"
	gen_inst.set_scene_instance_load_placeholder(false)
	var gen_scene := load(GENERATED_SCENE) as PackedScene
	if gen_scene != null:
		# 展平嵌入：不用 PackedScene 实例引用。Godot 4.7 的 LightmapGI 烘焙会对
		# "LightmapGI 子树内的实例"复制出 X2 副本网格并写回场景（上一轮遗留 bug）。
		# 展平后节点路径与原实例结构一致（Generated/BakedWorld/…），烘焙行为与首版相同。
		var gen_container := Node3D.new()
		gen_container.name = "Generated"
		gen_inst.add_child(gen_container)
		var gi := gen_scene.instantiate()
		gen_container.add_child(gi)
		while gi.get_child_count() > 0:
			var c := gi.get_child(0)
			gi.remove_child(c)
			gen_container.add_child(c)
		gi.free()
		gen_container.owner = root
		gen_inst.owner = root
	lm.add_child(gen_inst)
	if ResourceLoader.exists(AUTHORED_SCENE):
		var auth_inst := Node3D.new()
		auth_inst.name = "AuthoredStatic"
		var auth_container := Node3D.new()
		auth_container.name = "Authored"
		auth_inst.add_child(auth_container)
		var auth_scene := load(AUTHORED_SCENE) as PackedScene
		var ai := auth_scene.instantiate()
		auth_container.add_child(ai)
		while ai.get_child_count() > 0:
			var c := ai.get_child(0)
			ai.remove_child(c)
			auth_container.add_child(c)
		ai.free()
		auth_container.owner = root
		auth_inst.owner = root
		lm.add_child(auth_inst)
	else:
		print("注意：authored 场景不存在（WP2 前为空）——仅组合生成层")

	# Backdrop（不烘焙）
	var backdrop := Node3D.new()
	backdrop.name = "Backdrop"
	var backdrop_mesh_path := str(spec.get("backdrop_mesh", ""))
	if backdrop_mesh_path != "" and ResourceLoader.exists(backdrop_mesh_path):
		var mi := MeshInstance3D.new()
		mi.name = "BackdropMesh"
		mi.mesh = load(backdrop_mesh_path)
		backdrop.add_child(mi)
	root.add_child(backdrop)

	# Environment（唯一 WorldEnvironment）
	root.add_child(_build_environment())

	# CameraAnchors：generated + authored 锚点合并（ID 唯一）
	var anchors := Node3D.new()
	anchors.name = "CameraAnchors"
	var anchor_defs: Dictionary = {}
	for k in spec.get("anchors", {}):
		anchor_defs[k] = spec["anchors"][k]
	for k in authored.get("anchors", {}):
		if anchor_defs.has(k):
			push_error("锚点重复: %s" % k)
			quit(1)
			return root
		anchor_defs[k] = authored["anchors"][k]
	for anchor_id in anchor_defs:
		var a: Dictionary = anchor_defs[anchor_id]
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

	# Ambient：少量可关闭环境动画/粒子（≤6 动画节点、≤2 粒子）
	root.add_child(_build_ambient())
	return root


func _build_environment() -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.075, 0.12, 0.23)
	sky_mat.sky_horizon_color = Color(0.62, 0.45, 0.38)
	sky_mat.ground_bottom_color = Color(0.05, 0.06, 0.08)
	sky_mat.ground_horizon_color = Color(0.4, 0.33, 0.31)
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.4  # 1.1 目检后提升环境基底，消除大面积死黑
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.18
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.47, 0.56)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.5
	env.glow_enabled = true  # 运行时由画质档开关
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.05
	we.environment = env
	return we


func _build_ambient() -> Node3D:
	var ambient := Node3D.new()
	ambient.name = "Ambient"
	for fp in spec.get("fan_positions", []):
		var pivot := Node3D.new()
		pivot.name = "FanPivot"
		pivot.position = _v3(fp)
		pivot.rotation_degrees = Vector3(90, 0, 0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 0.035
		cm.radial_segments = 10
		mi.mesh = cm
		mi.material_override = mats["metal_dark"]
		mi.set_meta("anim_rotate", true)
		mi.set_meta("anim_axis", "y")
		mi.set_meta("anim_speed", 3.2)
		pivot.add_child(mi)
		ambient.add_child(pivot)
	for fl in authored.get("flickers", []):
		_add_flicker(ambient, str(fl.get("mat_key", "")), _v3(fl["pos"]), Vector2(fl["size"][0], fl["size"][1]), float(fl.get("rot_y", 0.0)))
	for fl in spec.get("flickers", []):
		_add_flicker(ambient, str(fl.get("mat_key", "")), _v3(fl["pos"]), Vector2(fl["size"][0], fl["size"][1]), float(fl.get("rot_y", 0.0)))
	var particle_count := 0
	for pp in spec.get("particles", []):
		if particle_count < 2:
			_add_particles(ambient, _v3(pp))
			particle_count += 1
	for pp in authored.get("particles", []):
		if particle_count < 2:
			_add_particles(ambient, _v3(pp))
			particle_count += 1
	return ambient


func _add_flicker(parent: Node3D, mat_key: String, pos: Vector3, size: Vector2, rot_y: float) -> void:
	if not mats.has(mat_key):
		push_warning("assemble: flicker 材质缺失 %s" % mat_key)
		return
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = (mats[mat_key] as StandardMaterial3D).duplicate()
	mi.position = pos
	mi.rotation_degrees.y = rot_y
	mi.set_meta("anim_flicker", true)
	parent.add_child(mi)


func _add_particles(parent: Node3D, pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 8
	p.lifetime = 3.2
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.04, 1, 0.03)
	pm.spread = 9.0
	pm.initial_velocity_min = 0.22
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0, 0.1, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.color = Color(0.8, 0.83, 0.87, 0.15)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.8, 0.84, 0.88, 0.12)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = sm
	p.draw_pass_1 = quad
	p.emitting = false
	p.add_to_group("optional_particle")
	parent.add_child(p)


# ============================ 定义 ============================

func _save_definition() -> Error:
	var def := MAP_DEF_SCRIPT.new()
	def.schema_version = 2
	def.map_id = "m01_afterglow"
	def.display_name = "余晖街区"
	def.scene_path = MAP_SCENE
	def.preview_path = ""
	def.default_anchor = str(authored.get("default_anchor", "street_view"))
	def.camera_bounds = AABB(Vector3(BOUNDS[0], BOUNDS[1], BOUNDS[2]), Vector3(BOUNDS[3], BOUNDS[4], BOUNDS[5]))
	var exclusions: Array[AABB] = []
	for e in spec.get("exclusions", []):
		exclusions.append(AABB(Vector3(e[0], e[1], e[2]), Vector3(e[3], e[4], e[5])))
	for e in authored.get("exclusions", []):
		exclusions.append(AABB(Vector3(e[0], e[1], e[2]), Vector3(e[3], e[4], e[5])))
	def.camera_exclusion_bounds = exclusions
	var anchor_ids := PackedStringArray()
	for k in spec.get("anchors", {}):
		anchor_ids.append(String(k))
	for k in authored.get("anchors", {}):
		anchor_ids.append(String(k))
	def.anchor_names = anchor_ids
	def.lighting_profile_id = "m01_dusk_v11"
	def.available = true
	def.content_revision = CONTENT_REVISION
	def.region_manifest_path = authored.get("region_manifest_path", "")
	def.occlusion_enabled = true
	def.bookmark_schema_version = 1
	def.requires_baked_lighting = true
	# chapter1-2 §4.4：门户（门外 → 店内）
	var portal_list: Array[Dictionary] = []
	for p in authored.get("portals", []):
		portal_list.append({
			"pos": Vector3(p["pos"][0], p["pos"][1], p["pos"][2]),
			"radius": float(p["radius"]),
			"target_map_id": str(p["target_map_id"]),
			"target_anchor": str(p["target_anchor"]),
			"label": str(p["label"]),
		})
	def.portals = portal_list
	var err := ResourceSaver.save(def, MAP_DEF)
	if err != OK:
		push_error("map_definition.tres 保存失败: %d" % err)
		return err
	print("definition saved: ", err, " anchors=", anchor_ids.size(), " exclusions=", exclusions.size(), " portals=", portal_list.size())
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
		"map_id": "m01_afterglow",
		"content_revision": CONTENT_REVISION,
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

func _load_materials() -> void:
	## 组装需要的材质（ambient 用）。从已生成的 .tres 加载，不重复生成。
	var keys := ["metal_dark", "sign_bar_v", "sign_electronics"]
	for k in keys:
		var path := "%s/%s.tres" % [MAT_DIR, k]
		if ResourceLoader.exists(path):
			mats[k] = load(path)
	for mat_file in ["sign_bar_v", "sign_electronics"]:
		var path := "%s/%s.tres" % [MAT_DIR, mat_file]
		if not ResourceLoader.exists(path):
			push_warning("assemble: 材质缺失 %s" % path)


func _v3(arr: Variant) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


func _set_all_owners(node: Node, root: Node, inside_instance: bool = false) -> void:
	## 实例根设 owner（属于外层场景），实例内部节点保持 owner=实例根（属于子场景）。
	## 若把 owner 设到实例内部节点，pack 会把它们写成"实例覆盖子节点"，
	## 编辑器加载时与子场景自身节点叠加复制（X2 网格来源）。
	for child in node.get_children():
		if child == root:
			continue
		if not inside_instance:
			child.owner = root
		_set_all_owners(child, root, inside_instance or not str(child.scene_file_path).is_empty())
