## M01 LightmapGI 烘焙（制作阶段工具，需窗口/GPU 运行）。
## 运行：godot --path . res://tools/run_bake.tscn
## 若 Mobile 渲染器下烘焙失败，可用 --rendering-method forward_plus 重跑。
extends Node


func _ready() -> void:
	await _bake()


func _bake() -> void:
	var ps: PackedScene = load("res://maps/m01_afterglow/map.tscn")
	if ps == null:
		push_error("bake: 地图场景不可加载")
		get_tree().quit(1)
		return
	var inst := ps.instantiate()
	get_tree().root.add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var lm := inst.get_node("BakedWorld") as LightmapGI
	if lm == null:
		push_error("bake: BakedWorld/LightmapGI 不存在")
		get_tree().quit(1)
		return
	# 打印关键属性，确认本机 4.7.2 的实际枚举值
	for p in lm.get_property_list():
		var pn: String = p["name"]
		if pn.contains("light") or pn.contains("environment") or pn.contains("atlas") or pn.contains("bounce") or pn.contains("quality") or pn.contains("denoise") or pn.contains("directional"):
			print("prop ", pn, " = ", lm.get(pn))
	lm.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lm.bounces = 2
	if "generate_probes_subdiv" in lm:
		lm.generate_probes_subdiv = 0  # 无动态物体，不生成光照探针
	print("BAKE_START")
	var t0 := Time.get_ticks_msec()
	var err: Error = lm.bake(false, false)
	var ms := Time.get_ticks_msec() - t0
	print("BAKE_DONE err=", err, " ms=", ms)
	if err != OK:
		get_tree().quit(1)
		return
	# 找到数据属性（不同版本命名可能不同）
	var data: Resource = null
	var data_prop := ""
	for p in lm.get_property_list():
		var pn: String = p["name"]
		var vt: int = p["type"]
		if (pn == "light_data" or pn == "lightmap") and vt == TYPE_OBJECT:
			data_prop = pn
			data = lm.get(pn)
	if data == null:
		push_error("bake: 未找到 LightmapGIData 属性")
		get_tree().quit(1)
		return
	print("data prop = ", data_prop)
	DirAccess.make_dir_recursive_absolute("res://maps/m01_afterglow/baked")
	var out_path := "res://maps/m01_afterglow/baked/lightmap_gi.res"
	var err2 := ResourceSaver.save(data, out_path)
	print("data saved: ", err2, " -> ", out_path)
	# 重新指向已保存资源并回写场景
	var saved: Resource = load(out_path)
	lm.set(data_prop, saved)
	var ps2 := PackedScene.new()
	var pack_err := ps2.pack(inst)
	print("repack: ", pack_err)
	var save_err := ResourceSaver.save(ps2, "res://maps/m01_afterglow/map.tscn")
	print("map.tscn resaved: ", save_err)
	get_tree().quit(0)
