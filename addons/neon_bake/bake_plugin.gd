## 仅编辑器加载的自动烘焙插件。
## 运行：godot --path . --editor -- --auto-bake
## 原因：Godot 4.7.2 未把 LightmapGI.bake() 暴露给脚本，编辑器 UI 按钮是唯一入口；
## 本插件在编辑器内打开地图场景、选中 LightmapGI、程序化触发"烘焙光照贴图"按钮，
## 完成后保存场景并退出。无 --auto-bake 参数时完全惰性。
@tool
extends EditorPlugin

const MAP_SCENE := "res://maps/m01_afterglow/map.tscn"


func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has("--auto-bake"):
		_run_auto_bake.call_deferred()


func _bake_scene_path() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--scene" and i + 1 < args.size():
			return args[i + 1]
	return MAP_SCENE


func _run_auto_bake() -> void:
	print("NEON_BAKE: 编辑器就绪，打开场景…")
	await get_tree().create_timer(2.0).timeout
	EditorInterface.open_scene_from_path(_bake_scene_path())
	await get_tree().create_timer(1.5).timeout
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		print("NEON_BAKE: 场景根为空")
		_finish(1)
		return
	var lm := _find_lightmap(root)
	if lm == null:
		print("NEON_BAKE: LightmapGI 未找到")
		_finish(1)
		return
	print("NEON_BAKE: LightmapGI = ", lm.get_path())
	_diag_meshes(root)
	# bake() 要求已有 light_data（提供保存路径）或调用方传入路径；
	# 预先保存一个空 LightmapGIData 作为输出位置。
	var data_path := _bake_scene_path().get_basename() + "_lightmap.res"
	var data := LightmapGIData.new()
	var save_err := ResourceSaver.save(data, data_path)
	print("NEON_BAKE: 预保存 light_data -> ", data_path, " err=", save_err)
	lm.light_data = load(data_path)
	EditorInterface.edit_node(lm)
	var btn: Button = null
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		btn = _find_bake_button(EditorInterface.get_inspector())
		if btn == null:
			btn = _find_bake_button(EditorInterface.get_base_control())
		if btn != null:
			break
	if btn == null:
		print("NEON_BAKE: 未找到烘焙按钮")
		_finish(1)
		return
	print("NEON_BAKE: 触发按钮 '", btn.text, "'")
	btn.pressed.emit()
	await get_tree().create_timer(2.0).timeout
	_dump_visible_dialogs(EditorInterface.get_base_control())
	for i in 120:  # 最长等待 60 秒
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(lm):
			print("NEON_BAKE: LightmapGI 失效")
			_finish(1)
			return
		if lm.light_data != null:
			break
	if lm.light_data == null:
		print("NEON_BAKE: 烘焙未完成——保持编辑器打开供外部检查（手动关闭）")
		return
	print("NEON_BAKE: 烘焙完成，保存场景…")
	await get_tree().create_timer(1.5).timeout
	EditorInterface.save_scene()
	await get_tree().create_timer(1.5).timeout
	print("NEON_BAKE: light_data = ", lm.light_data.resource_path)
	_finish(0)


func _finish(code: int) -> void:
	print("NEON_BAKE_EXIT=", code)
	get_tree().quit(code)


func _find_lightmap(node: Node) -> LightmapGI:
	if node is LightmapGI:
		return node
	for c in node.get_children():
		var r := _find_lightmap(c)
		if r != null:
			return r
	return null


func _diag_meshes(node: Node) -> void:
	var acc := {"total": 0, "static": 0, "uv2": 0, "tris": 0}
	_diag_visit(node, acc)
	print("NEON_BAKE diag: mesh_instances=", acc["total"], " gi_static=", acc["static"], " 带UV2网格=", acc["uv2"], " 面数=", acc["tris"])


func _diag_visit(node: Node, acc: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		acc["total"] = int(acc["total"]) + 1
		if mi.gi_mode == GeometryInstance3D.GI_MODE_STATIC:
			acc["static"] = int(acc["static"]) + 1
		var mesh := mi.mesh
		if mesh is ArrayMesh and mesh.get_surface_count() > 0:
			var has_uv2 := true
			for i in mesh.get_surface_count():
				if not (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2):
					has_uv2 = false
			if has_uv2:
				acc["uv2"] = int(acc["uv2"]) + 1
			acc["tris"] = int(acc["tris"]) + mesh.get_faces_count()
	for c in node.get_children():
		_diag_visit(c, acc)


func _find_bake_button(node: Node) -> Button:
	var all := []
	_collect_bake_buttons(EditorInterface.get_inspector(), all, "inspector")
	_collect_bake_buttons(EditorInterface.get_base_control(), all, "base")
	for entry in all:
		print("NEON_BAKE candidate[", entry["where"], "]: ", entry["path"], " visible=", entry["visible"])
	if all.is_empty():
		return null
	# 优先检查器中的可见按钮
	for entry in all:
		if entry["where"] == "inspector" and entry["visible"]:
			return entry["btn"]
	for entry in all:
		if entry["visible"]:
			return entry["btn"]
	return null


func _collect_bake_buttons(node: Node, out: Array, where: String, path: String = "") -> void:
	if node is Button:
		var t: String = node.text
		if t.contains("烘焙光照贴图") or t.contains("Bake Lightmaps") or (t.contains("烘焙") and t.contains("贴图")):
			out.append({"btn": node, "where": where, "path": path + "/" + node.name, "visible": node.is_visible_in_tree()})
	for c in node.get_children():
		_collect_bake_buttons(c, out, where, path + "/" + String(node.name))


func _dump_visible_dialogs(node: Node, depth: int = 0) -> void:
	if node is AcceptDialog and node.visible:
		var d := node as AcceptDialog
		print("NEON_BAKE dialog: '", d.title, "' text=", d.dialog_text)
		for c in d.get_children():
			if c is Button and c.visible:
				print("NEON_BAKE dialog btn: ", (c as Button).text)
	if depth < 12:
		for c in node.get_children():
			_dump_visible_dialogs(c, depth + 1)
