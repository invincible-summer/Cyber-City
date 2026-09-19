## 地图生命周期测试（headless 可运行）。
## 运行：godot --headless --path . --script res://tests/test_map_lifecycle.gd
## 覆盖：单活动地图、A→B→A ×10、弱引用失效、重复请求、无效 ID、缺失路径、缺锚点、失败恢复。
extends SceneTree

const MM_SCRIPT := preload("res://scripts/maps/map_manager.gd")
const MAP_DEF_SCRIPT := preload("res://scripts/maps/map_definition.gd")

var mm: Node
var slot: Node3D
var failures: Array[String] = []
var _last_event := ""
var _failed_ids: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 生命周期测试开始 ===")
	slot = Node3D.new()
	slot.name = "MapSlot"
	root.add_child(slot)
	mm = Node.new()
	mm.name = "MapManager"
	mm.set_script(MM_SCRIPT)
	root.add_child(mm)
	mm.setup(slot)
	mm.map_loaded.connect(func(id: String) -> void: _last_event = "loaded:" + id; print("[%.1fs] loaded %s" % [Time.get_ticks_msec() / 1000.0, id]))
	mm.map_failed.connect(func(id: String, reason: String) -> void: _last_event = "failed:" + id + ":" + reason; _failed_ids.append(id); print("[%.1fs] FAILED %s: %s" % [Time.get_ticks_msec() / 1000.0, id, reason]))
	mm.state_changed.connect(func(s: int) -> void: _last_event = "state:%d" % s)

	# 负面用例的破损定义（写入 user://，不进生产注册表）
	var broken_scene_def := MAP_DEF_SCRIPT.new()
	broken_scene_def.map_id = "broken_scene"
	broken_scene_def.display_name = "坏路径"
	broken_scene_def.scene_path = "res://tests/fixtures/does_not_exist.tscn"
	broken_scene_def.anchor_names = PackedStringArray(["test_anchor"])
	broken_scene_def.default_anchor = "test_anchor"
	ResourceSaver.save(broken_scene_def, "user://broken_scene_def.tres")
	var broken_anchor_def := MAP_DEF_SCRIPT.new()
	broken_anchor_def.map_id = "broken_anchor"
	broken_anchor_def.display_name = "缺锚点"
	broken_anchor_def.scene_path = "res://tests/fixtures/mini_test_map.tscn"
	broken_anchor_def.anchor_names = PackedStringArray(["wrong_anchor"])
	broken_anchor_def.default_anchor = "wrong_anchor"
	ResourceSaver.save(broken_anchor_def, "user://broken_anchor_def.tres")

	mm.inject_registry({
		"m01_afterglow": "res://maps/m01_afterglow/map_definition.tres",
		"test_mini_map": "res://tests/fixtures/mini_test_map_definition.tres",
		"broken_scene": "user://broken_scene_def.tres",
		"broken_anchor": "user://broken_anchor_def.tres",
	})

	_check(mm.state == 0, "初始状态为 EMPTY")

	# 1. 无效 ID：卸载前拒绝，状态不变
	_last_event = ""
	mm.request_map("no_such_map")
	_check(_last_event.begins_with("failed:no_such_map"), "无效 ID 发出 map_failed")
	_check(mm.state == 0, "无效 ID 后状态保持 EMPTY")

	# 2. 加载正式地图
	_check(mm.request_map("m01_afterglow"), "请求 m01 被接受")
	_check(await _await_loaded("m01_afterglow", 30.0), "m01 加载完成")
	_check(mm.state == 1, "加载后 READY")
	_check(mm.get_active_root_count() == 1, "稳态活动地图数为 1")

	# 3. 已是当前地图时重复请求被拒绝
	_check(not mm.request_map("m01_afterglow"), "相同地图重复请求被拒绝")

	# 4. 缺失路径：卸载前拒绝，当前地图不变
	_last_event = ""
	mm.request_map("broken_scene")
	_check(_last_event.begins_with("failed:broken_scene"), "缺失路径发出 map_failed")
	_check(mm.state == 1 and mm.current_map_id == "m01_afterglow", "缺失路径后仍为 m01 READY")

	# 5. A→B→A ×5（共 10 次切换）
	for i in 5:
		var weak_a := _root_weak()
		mm.request_map("test_mini_map")
		_check(await _await_loaded("test_mini_map", 30.0), "第 %d 轮 B 加载完成" % (i + 1))
		_check(mm.get_active_root_count() <= 1, "切换中任意时刻活动地图 ≤1")
		_check(await _weak_dead(weak_a), "A 卸载后弱引用失效 (轮 %d)" % (i + 1))
		var weak_b := _root_weak()
		mm.request_map("m01_afterglow")
		_check(await _await_loaded("m01_afterglow", 30.0), "第 %d 轮 A 加载完成" % (i + 1))
		_check(mm.get_active_root_count() <= 1, "切回后活动地图 ≤1")
		_check(await _weak_dead(weak_b), "B 卸载后弱引用失效 (轮 %d)" % (i + 1))

	# 6. 单独卸载 → 空外壳
	mm.unload_current_map()
	_check(await _await_state(0, 10.0), "卸载后回到 EMPTY")
	_check(mm.get_active_root_count() == 0, "卸载后活动地图数为 0")
	_check(slot.get_child_count() == 0, "MapSlot 无残留子节点")

	# 7. 重新加载恢复
	mm.request_map("m01_afterglow")
	_check(await _await_loaded("m01_afterglow", 30.0), "重新加载 m01 成功")
	_check(mm.get_active_root_count() == 1, "恢复后活动地图数为 1")

	# 8. 缺锚点：卸载后失败 → 清理 → EMPTY → 可重试
	_last_event = ""
	_failed_ids.clear()
	mm.request_map("broken_anchor")
	_check(await _await_cond(func() -> bool: return _failed_ids.has("broken_anchor"), 30.0), "缺锚点发出 map_failed")
	_check(await _await_state(0, 5.0), "失败清理后回到 EMPTY")
	_check(mm.get_active_root_count() == 0, "失败后无残留地图")

	# 9. 失败后重试成功
	mm.request_map("m01_afterglow")
	_check(await _await_loaded("m01_afterglow", 30.0), "失败后重试 m01 成功")

	# 结果
	if failures.is_empty():
		print("=== 生命周期测试全部通过 ===")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== 生命周期测试失败 %d 项 ===" % failures.size())
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		failures.append(label)
		printerr("FAIL: ", label)


func _await_loaded(map_id: String, timeout: float) -> bool:
	var target := "loaded:" + map_id
	return await _await_cond(func() -> bool: return _last_event == target, timeout)


func _await_state(s: int, timeout: float) -> bool:
	return await _await_cond(func() -> bool: return mm.state == s, timeout)


func _await_cond(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.03).timeout
		t += 0.03
	return cond.call()


func _root_weak() -> WeakRef:
	var roots := get_nodes_in_group("active_map_root")
	return weakref(roots[0]) if roots.size() > 0 else weakref(null)


func _weak_dead(ref: WeakRef) -> bool:
	## 释放可能延迟若干帧；轮询确认。
	var t := 0.0
	while t < 2.0:
		if ref.get_ref() == null:
			return true
		await create_timer(0.05).timeout
		t += 0.05
	return ref.get_ref() == null
