## 烘焙收尾：headless 读取真实 LightmapGIData，核对覆盖并回写 build_manifest.json。
## 场景：编辑器烘焙已完成并产出 baked/map_lightmap.res，但插件在保存阶段中断时，
## 由此脚本完成与插件相同的清单回写（读取实际烘焙数据，不伪造成功）。
## 运行：godot --headless --path . --script res://tools/finalize_bake_manifest.gd
extends SceneTree

const MANIFEST_PATH := "res://maps/m01_afterglow/build_manifest.json"
const MAP_SCENE := "res://maps/m01_afterglow/map.tscn"
const BAKED_DATA := "res://maps/m01_afterglow/baked/map_lightmap.res"
const REPORT_DIR := "res://artifacts/chapter1_1"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := load(BAKED_DATA) as LightmapGIData
	if data == null:
		printerr("FINALIZE: 烘焙数据不可加载")
		quit(1)
		return
	var actual: Array[String] = []
	for i in data.get_user_count():
		var p := data.get_user_path(i)
		if not actual.has(p):
			actual.append(p)
	actual.sort()
	# 期望：map.tscn 中 LightmapGI 子树内 GI 静态 + UV2 的网格节点路径
	var scene := load(MAP_SCENE) as PackedScene
	if scene == null:
		printerr("FINALIZE: map.tscn 不可加载")
		quit(1)
		return
	var inst := scene.instantiate()
	var lm := _find_lightmap(inst)
	if lm == null:
		printerr("FINALIZE: 未找到 LightmapGI")
		quit(1)
		return
	var expected: Array[String] = []
	_visit(lm, lm, expected)
	expected.sort()
	var missing: Array[String] = []
	for p in expected:
		if not actual.has(p):
			missing.append(p)
	print("FINALIZE: users=%d expected=%d missing=%d" % [actual.size(), expected.size(), missing.size()])
	for m in missing:
		print("FINALIZE-MISSING: ", m)
	# 回写清单
	if not FileAccess.file_exists(MANIFEST_PATH):
		printerr("FINALIZE: 清单不存在")
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	manifest["bake_status"] = "succeeded" if missing.is_empty() else "failed"
	manifest["bake_job_id"] = str(manifest.get("bake_job_id", "")) if str(manifest.get("bake_job_id", "")) != "" else "headless-finalize"
	var arr: Array = []
	for p in actual:
		arr.append(p)
	manifest["actual_baked_user_paths"] = arr
	manifest["bake_finished_utc"] = Time.get_datetime_string_from_system(true)
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("FINALIZE: bake_status=", manifest["bake_status"], " -> 清单已回写")
	inst.free()
	quit(0 if missing.is_empty() else 1)


func _find_lightmap(node: Node) -> LightmapGI:
	if node is LightmapGI:
		return node
	for c in node.get_children():
		var r := _find_lightmap(c)
		if r != null:
			return r
	return null


func _visit(node: Node, lm: LightmapGI, found: Array[String]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.gi_mode == GeometryInstance3D.GI_MODE_STATIC and mi.mesh != null:
			var has_uv2 := false
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_surface_count() > 0:
				has_uv2 = true
				for i in (mi.mesh as ArrayMesh).get_surface_count():
					if not ((mi.mesh as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2):
						has_uv2 = false
			if has_uv2:
				var rel := str(lm.get_path_to(mi))
				if not found.has(rel):
					found.append(rel)
	for c in node.get_children():
		_visit(c, lm, found)
