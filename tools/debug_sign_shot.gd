extends SceneTree
## 一次性诊断：窗口化直拍两张对照图，裁决"店招字图是否真的渲染"。
## A: 相机正对店招近景（x 轴正对墙面）
## B: v6 gallery_view 原机位复现

var _frames := 0
var _stage := 0
var _cam: Camera3D

func _initialize() -> void:
	var ps: PackedScene = load("res://maps/m01_repair_interior/map.tscn")
	var map := ps.instantiate()
	root.add_child(map)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 60.0
	_cam.current = true
	_pose(Vector3(6.5, 3.29, -0.4), Vector3(0.11, 3.29, -0.4))

func _pose(p: Vector3, look: Vector3) -> void:
	_cam.look_at_from_position(p, look, Vector3.UP)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 50:
		_save("debug_sign_closeup.png")
		_stage = 1
	elif _stage == 1 and _frames == 100:
		# v6 gallery_view 原机位：pos [4.1, 3.62, -0.93] look [1.1, 1.66, -0.93]
		_pose(Vector3(4.1, 3.62, -0.93), Vector3(1.1, 1.66, -0.93))
		_stage = 2
	elif _stage == 2 and _frames == 150:
		_save("debug_gallery_repro.png")
		return true
	return false

func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("res://artifacts/chapter1_2/" + name)
	print("SAVED ", name, " ", img.get_size())
