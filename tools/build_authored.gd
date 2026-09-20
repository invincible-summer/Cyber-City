## M01「余晖街区」精修层构建（chapter1-1 §6.1 authored 层）。
## 运行：godot --headless --path . --script res://tools/build_authored.gd
## 职责：三处新空间（生活广场/站前空间/屋顶露台）+ 精修附加几何与灯光。
## 本脚本是 authored 层的唯一来源；build_m01.gd 与 assemble_m01.gd 不得覆盖其输出。
## 输出：authored/authored_static.tscn + authored_spec.json（锚点/禁入体积/环境件规格）
extends SceneTree

const GL := preload("res://tools/gen_lib.gd")
const TEX := "res://assets/m01_afterglow/textures"
const MAT_DIR := "res://assets/m01_afterglow/materials"
const AUTHORED_DIR := "res://maps/m01_afterglow/authored"
const AUTHORED_SCENE := "res://maps/m01_afterglow/authored/authored_static.tscn"
const AUTHORED_SPEC := "res://maps/m01_afterglow/authored/authored_spec.json"
const AUTHORED_MESH_DIR := "res://maps/m01_afterglow/meshes"

var mats := {}
var lights_spec: Array = []
var exclusions: Array[AABB] = []
var anchors: Dictionary = {}
var flickers: Array = []
var particles: Array = []
var region_manifest_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== build_authored ===")
	DirAccess.make_dir_recursive_absolute(AUTHORED_DIR)
	_load_materials()

	var root := Node3D.new()
	root.name = "M01Authored"

	# 三处扩展区域的静态几何与道具（WP2 灰盒 → WP4 成品化）
	var geom := Node3D.new()
	geom.name = "AuthoredGeometry"
	var mb_static := GL.MeshBuilder.new()
	_service_court_static(mb_static)
	_station_forecourt_static(mb_static)
	_roof_terrace_static(mb_static)
	var mesh_static := mb_static.commit(mats, "%s/authored_static_mesh.res" % AUTHORED_MESH_DIR, Vector2i(2048, 2048))
	print("authored static: tris=", mb_static.tri_count(), " surf=", mesh_static.get_surface_count(), " uv2_max_y=%.3f overflow=%d" % [mb_static.packer.max_y(), mb_static.packer.overflow_count])
	var mi_static := MeshInstance3D.new()
	mi_static.name = "AuthoredStaticMesh"
	mi_static.mesh = mesh_static
	geom.add_child(mi_static)
	_add_occluders(geom)
	root.add_child(geom)

	var props := Node3D.new()
	props.name = "AuthoredProps"
	var mb_props := GL.MeshBuilder.new()
	_service_court_props(mb_props)
	_station_forecourt_props(mb_props)
	_roof_terrace_props(mb_props)
	var mesh_props := mb_props.commit(mats, "%s/authored_props_mesh.res" % AUTHORED_MESH_DIR, Vector2i(512, 512))
	print("authored props: tris=", mb_props.tri_count())
	var mi_props := MeshInstance3D.new()
	mi_props.name = "AuthoredPropsMesh"
	mi_props.mesh = mesh_props
	mi_props.add_to_group("detail_props")
	props.add_child(mi_props)
	root.add_child(props)

	var lighting := Node3D.new()
	lighting.name = "AuthoredLighting"
	for L in lights_spec:
		var o := OmniLight3D.new()
		o.position = L["pos"]
		o.light_color = L["color"]
		o.light_energy = L["energy"]
		o.omni_range = L["range"]
		o.light_bake_mode = Light3D.BAKE_STATIC
		o.shadow_enabled = false
		o.add_to_group("bake_only_light")
		lighting.add_child(o)
	root.add_child(lighting)

	_set_all_owners(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack 失败: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, AUTHORED_SCENE)
	print("authored scene saved: ", err)
	_save_spec()
	print("AUTHORED_DONE")
	quit(0)


# ============================ 三个新区域（内容在 WP2/WP4 填充） ============================

func _service_court_static(_mb: GL.MeshBuilder) -> void:
	pass  # WP2 灰盒 → WP4 成品


func _service_court_props(_mb: GL.MeshBuilder) -> void:
	pass


func _station_forecourt_static(_mb: GL.MeshBuilder) -> void:
	pass


func _station_forecourt_props(_mb: GL.MeshBuilder) -> void:
	pass


func _roof_terrace_static(_mb: GL.MeshBuilder) -> void:
	pass


func _roof_terrace_props(_mb: GL.MeshBuilder) -> void:
	pass


# ============================ 规格输出 ============================

func _save_spec() -> void:
	var excl: Array = []
	for b in exclusions:
		excl.append([b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	var spec := {
		"schema_version": 1,
		"authored_scene": AUTHORED_SCENE,
		"anchors": anchors,
		"exclusions": excl,
		"flickers": flickers,
		"particles": particles,
		"region_manifest_path": region_manifest_path,
		"total_exclusions": excl.size(),
	}
	var f := FileAccess.open(AUTHORED_SPEC, FileAccess.WRITE)
	if f == null:
		push_error("authored spec 写入失败")
		return
	f.store_string(JSON.stringify(spec, "  "))
	f.close()
	print("authored spec saved: anchors=", anchors.size(), " exclusions=", excl.size())


# ============================ 辅助 ============================

func _load_materials() -> void:
	## 复用生成层材质（共享资产）；只按需添加 authored 专属材质。
	var keys := [
		"wall_bluegray", "wall_warm", "wall_panel", "wall_brick", "concrete_plain",
		"metal_dark", "metal_teal", "metal_orange", "glass_dark", "lit_warm", "lit_cool",
		"glass_shop", "interior_back", "asphalt", "pavement", "plaza", "alley", "roof",
		"wood", "rubber", "marking", "steel_station", "bulb_warm", "wire", "poster",
		"door_dark", "lamp_lens", "asphalt_wet",
		"sign_repair", "sign_station", "sign_convenience", "sign_cafe", "sign_noodle",
		"sign_pharmacy", "sign_electronics", "sign_hotel_v", "sign_soda", "sign_bar_v",
	]
	for k in keys:
		var path := "%s/%s.tres" % [MAT_DIR, k]
		if ResourceLoader.exists(path):
			mats[k] = load(path)
		else:
			push_warning("authored: 共享材质缺失 %s" % path)


func _add_occluders(parent: Node3D) -> void:
	if not ClassDB.class_exists("BoxOccluder"):
		return
	# 各区域主体遮挡体在填充内容时按几何登记
	for occ_spec in get_meta("occluders", []):
		var occ := OccluderInstance3D.new()
		occ.name = str(occ_spec.get("name", "Occ"))
		var box = ClassDB.instantiate("BoxOccluder")
		box.size = occ_spec["size"]
		occ.occluder = box
		occ.position = occ_spec["pos"]
		parent.add_child(occ)


func _omni(pos: Vector3, color: Color, energy: float, range_m: float) -> Dictionary:
	return {"pos": pos, "color": color, "energy": energy, "range": range_m}


func _set_all_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child != root:
			child.owner = root
			_set_all_owners(child, root)
