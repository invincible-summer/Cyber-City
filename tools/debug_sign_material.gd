extends SceneTree
## 一次性诊断（v6 终验"店招无字"根因定位）：
## 加载室内图与街区图的生成场景，找到 sign_repair / poster surface，
## 打印运行时材质状态、引擎侧纹理像素与 mesh UV1 数据。

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_check_scene(args[0])
	else:
		_check_scene("res://maps/m01_repair_interior/generated/interior_generated.tscn")
	quit(0)

func _check_scene(path: String) -> void:
	print("=== ", path)
	if not ResourceLoader.exists(path):
		print("  NOT EXISTS")
		return
	var ps: PackedScene = load(path)
	if ps == null:
		print("  LOAD FAILED")
		return
	var root := ps.instantiate()
	_walk(root)
	root.free()

func _walk(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat == null:
					continue
				var sm := mat as StandardMaterial3D
				var textured: bool = sm != null and sm.albedo_texture != null
				var named: bool = mat.resource_path.contains("sign") or mat.resource_path.contains("poster")
				if not (textured or named):
					continue
				print("  MI=%s surf=%d mat=%s class=%s" % [mi.name, s, mat.resource_path, mat.get_class()])
				if sm == null:
					continue
				print("    albedo_tex=%s emission=%s emission_tex=%s energy=%.1f" % [
					_tex_desc(sm.albedo_texture), sm.emission_enabled,
					_tex_desc(sm.emission_texture), sm.emission_energy_multiplier])
				if sm.albedo_texture != null:
					var img := sm.albedo_texture.get_image()
					if img.is_compressed():
						print("    img=%s (compressed, skip px)" % img.get_size())
					else:
						var mid := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
						print("    img=%s px(0,0)=%s px(mid)=%s" % [img.get_size(), img.get_pixel(0, 0), mid])
				var arrays := mi.mesh.surface_get_arrays(s)
				var uv = arrays[Mesh.ARRAY_TEX_UV]
				if uv == null:
					print("    UV1=NULL !")
				else:
					print("    uv_n=%d first4=%s" % [uv.size(), str([uv[0], uv[1], uv[2], uv[3]])])
	for c in n.get_children():
		_walk(c)

func _tex_desc(t: Texture2D) -> String:
	if t == null:
		return "null"
	return "%s(%s)" % [t.get_class(), t.resource_path.get_file()]
