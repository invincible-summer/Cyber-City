## 最小烘焙探针：一个 GenLib 盒子（带 UV2）+ LightmapGI + 平行光 + 点光。
## 运行：godot --headless --path . --script res://tools/build_bake_probe.gd
extends SceneTree

const GL := preload("res://tools/gen_lib.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "BakeProbe"
	var lm := LightmapGI.new()
	lm.name = "BakedWorld"
	root.add_child(lm)
	var sg := Node3D.new()
	sg.name = "StaticGeometry"
	lm.add_child(sg)
	var mb := GL.MeshBuilder.new()
	var wall: StandardMaterial3D = load("res://assets/m01_afterglow/materials/wall_warm.tres")
	var floor_m: StandardMaterial3D = load("res://assets/m01_afterglow/materials/pavement.tres")
	mb.box("wall", Vector3(-3, 0, -3), Vector3(3, 4, 3), 0.33, 28.0, GL.FACE_NO_BOTTOM)
	var mats := {"wall": wall.duplicate(), "floor": floor_m.duplicate()}
	var mesh := mb.commit(mats, "", Vector2i(512, 512))
	var mi := MeshInstance3D.new()
	mi.name = "ProbeMesh"
	mi.mesh = mesh
	lm.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.0
	sun.light_bake_mode = Light3D.BAKE_STATIC
	sun.rotation_degrees = Vector3(-55, 30, 0)
	root.add_child(sun)
	var omni := OmniLight3D.new()
	omni.position = Vector3(0, 3, 0)
	omni.light_energy = 3.0
	omni.omni_range = 8.0
	omni.light_bake_mode = Light3D.BAKE_STATIC
	root.add_child(omni)
	var cam_anchor := Marker3D.new()
	cam_anchor.name = "CameraAnchors"
	root.add_child(cam_anchor)
	_set_owner(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, "res://tests/fixtures/bake_probe.tscn")
	print("PROBE_DONE uv2_overflow=", mb.packer.overflow_count)
	quit(0)


func _set_owner(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_set_owner(c, root)
