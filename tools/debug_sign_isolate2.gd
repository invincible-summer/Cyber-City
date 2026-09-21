extends SceneTree
## 隔离诊断 v2：sign surface 抽出后保持地图坐标（仅对顶点数据做 z 偏移），
## 三块对照：A 原样+tres / B z+2+tres / C z+4+动态材质。全部同屏可判。

var _frames := 0
var _src_mat: Material
var _src_arrays: Array

func _find(n: Node) -> void:
	if n is MeshInstance3D and n.name == "InteriorStaticMesh":
		var mi := n as MeshInstance3D
		print("MI transform=", mi.transform)
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m != null and m.resource_path.contains("sign_repair"):
				_src_mat = m
				_src_arrays = mi.mesh.surface_get_arrays(s)
				return
	for c in n.get_children():
		_find(c)

func _shifted(off: float) -> Array:
	var a := _src_arrays.duplicate()
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in vs.size():
		vs[i] += Vector3(0.0, 0.0, off)
	a[Mesh.ARRAY_VERTEX] = vs
	return a

func _initialize() -> void:
	var ps: PackedScene = load("res://maps/m01_repair_interior/map.tscn")
	var map := ps.instantiate()
	root.add_child(map)
	_find(map)
	print("verts=", (_src_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		" idx_null=", _src_arrays[Mesh.ARRAY_INDEX] == null,
		" src_mat=", _src_mat.resource_path)
	map.visible = false

	var m2 := StandardMaterial3D.new()
	m2.albedo_texture = load("res://assets/m01_afterglow/textures/signs/repair_main.png")
	m2.roughness = 0.6
	m2.emission_enabled = true
	m2.emission_texture = m2.albedo_texture
	m2.emission_energy_multiplier = 4.2

	_mk(_shifted(0.0), _src_mat)   # A 原位
	_mk(_shifted(2.0), _src_mat)   # B
	_mk(_shifted(4.0), m2)         # C

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 40.0
	cam.current = true
	cam.look_at_from_position(Vector3(8.5, 3.29, -0.4), Vector3(0.11, 3.29, -0.4), Vector3.UP)

func _mk(arrays: Array, mat: Material) -> void:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	if mat != null:
		mi.material_override = mat
	root.add_child(mi)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 50:
		var img := root.get_texture().get_image()
		img.save_png("res://artifacts/chapter1_2/debug_isolate_sign2.png")
		print("SAVED debug_isolate_sign2.png ", img.get_size())
		return true
	return false
