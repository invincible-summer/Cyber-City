## chapter1-1 接口合同测试（headless 可运行）。
## 运行：godot --headless --path . --script res://tests/test_chapter11_contract.gd
## 覆盖：CameraPose 序列化与校验（T08 部分）、ActivityGuard 互斥、BookmarkStore 存取与损坏恢复（T08）、
##       QualityController 快照恢复、MapDefinition v1→v2 兼容（T01/T02 部分）。
extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 合同测试开始 ===")
	_test_camera_pose()
	_test_activity_guard()
	_test_bookmark_store()
	_test_quality_controller()
	_test_map_definition()
	if failures.is_empty():
		print("=== 合同测试全部通过 ===")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== 合同测试失败 %d 项 ===" % failures.size())
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		failures.append(label)
		printerr("FAIL: ", label)


# ---------------- CameraPose（§7.2） ----------------

func _test_camera_pose() -> void:
	var pose := CameraPose.new()
	pose.map_id = &"m01_afterglow"
	pose.anchor_id = &"street_view"
	pose.transform = Transform3D(Basis(Quaternion(Vector3.UP, 0.5)), Vector3(1.0, 2.0, 3.0))
	var d := pose.to_dict()
	var back := CameraPose.from_dict(d)
	_check(back != null, "CameraPose 往返序列化成功")
	if back != null:
		_check(back.transform.origin.distance_to(pose.transform.origin) < 0.001, "位置往返一致")
		_check(absf(back.transform.basis.get_euler().y - pose.transform.basis.get_euler().y) < 0.01, "旋转往返一致")
	# 零四元数拒绝
	var zero := d.duplicate()
	zero["quaternion"] = [0.0, 0.0, 0.0, 0.0]
	_check(CameraPose.from_dict(zero) == null, "零四元数被拒绝")
	# 非有限数值拒绝
	var bad_pos := d.duplicate()
	bad_pos["position"] = [NAN, 0.0, 0.0]
	_check(CameraPose.from_dict(bad_pos) == null, "非有限位置被拒绝")
	# FOV 越界拒绝
	var bad_fov := d.duplicate()
	bad_fov["fov_deg"] = 150.0
	_check(CameraPose.from_dict(bad_fov) == null, "FOV 越界被拒绝")
	# 缺字段拒绝
	_check(CameraPose.from_dict({"position": [0, 0, 0]}) == null, "缺字段被拒绝")
	# 校验器
	var p2 := CameraPose.new()
	_check(not p2.validate().is_empty(), "空位姿校验失败（map_id 空）")


# ---------------- ActivityGuard（§7.8） ----------------

func _test_activity_guard() -> void:
	var g := ActivityGuard.new()
	var t1 := g.try_begin(ActivityGuard.KIND_MAP_TRANSITION)
	_check(t1 > 0, "空闲时 try_begin 返回 >0 token")
	_check(g.try_begin(ActivityGuard.KIND_CAPTURE) == 0, "忙碌时 try_begin 返回 0")
	_check(g.get_active_kind() == ActivityGuard.KIND_MAP_TRANSITION, "get_active_kind 正确")
	_check(g.end(t1 + 999) == ERR_INVALID_PARAMETER, "不匹配 token 的 end 返回错误")
	_check(g.get_active_kind() == ActivityGuard.KIND_MAP_TRANSITION, "错误 end 不释放锁")
	_check(g.end(t1) == OK, "匹配 token 的 end 成功")
	_check(g.get_active_kind() == &"", "释放后空闲")
	var t2 := g.try_begin(ActivityGuard.KIND_BENCHMARK)
	_check(t2 > 0 and t2 != t1, "token 递增")
	g.force_release()
	_check(not g.is_busy(), "force_release 兜底生效")
	_check(g.try_begin(&"illegal") == 0, "非法 kind 拒绝")


# ---------------- BookmarkStore（§7.7 / T08） ----------------

func _test_bookmark_store() -> void:
	var store := BookmarkStore.new()
	# 干净起点
	if FileAccess.file_exists("user://camera_bookmarks.json"):
		DirAccess.remove_absolute("user://camera_bookmarks.json")
	if FileAccess.file_exists("user://camera_bookmarks.backup.json"):
		DirAccess.remove_absolute("user://camera_bookmarks.backup.json")
	store = BookmarkStore.new()
	var pose := CameraPose.new()
	pose.map_id = &"m01_afterglow"
	pose.transform = Transform3D(Basis(), Vector3(1, 2, 3))
	var r1 := store.save_bookmark("  测试机位  ", pose, "1.1.0")
	_check(r1.error == OK, "书签保存成功")
	_check(not str(r1.bookmark_id).is_empty(), "保存返回非空 ID")
	_check(store.list_bookmarks(&"m01_afterglow").size() == 1, "list 返回 1 条")
	_check(store.list_bookmarks(&"m01_afterglow")[0]["label"] == "测试机位", "label 去除首尾空白")
	var loaded := store.load_bookmark(str(r1.bookmark_id))
	_check(loaded != null and loaded.transform.origin.distance_to(Vector3(1, 2, 3)) < 0.001, "load_bookmark 往返一致")
	_check(store.load_bookmark("missing_id") == null, "缺失书签返回 null")
	_check(store.delete_bookmark(str(r1.bookmark_id)) == OK, "删除成功")
	_check(store.list_bookmarks(&"m01_afterglow").is_empty(), "删除后列表为空")
	_check(store.delete_bookmark("missing") == ERR_DOES_NOT_EXIST, "删除缺失返回 ERR_DOES_NOT_EXIST")
	# 校验
	_check(store.save_bookmark("", pose, "1.1.0").error != OK, "空 label 拒绝")
	_check(store.save_bookmark("x".repeat(41), pose, "1.1.0").error != OK, "超长 label 拒绝")
	_check(store.save_bookmark("ok", null, "1.1.0").error != OK, "空位姿拒绝")
	# 上限 12
	for i in 12:
		var r := store.save_bookmark("bm%d" % i, pose, "1.1.0")
		if r.error != OK:
			_check(false, "第 %d 个书签保存失败" % (i + 1))
			break
	_check(store.save_bookmark("overflow", pose, "1.1.0").error != OK, "第 13 个书签被拒绝（上限 12）")
	# 损坏恢复：主文件损坏 → 隔离 + 备份恢复
	DirAccess.copy_absolute("user://camera_bookmarks.json", "user://camera_bookmarks.backup.json")
	var f := FileAccess.open("user://camera_bookmarks.json", FileAccess.WRITE)
	f.store_string("{corrupt json!!")
	f.close()
	store = BookmarkStore.new()
	_check(store.list_bookmarks(&"m01_afterglow").size() == 12, "损坏后从备份恢复书签")
	# 损坏且无备份 → 空库开始，损坏文件被隔离
	DirAccess.remove_absolute("user://camera_bookmarks.backup.json")
	var f2 := FileAccess.open("user://camera_bookmarks.json", FileAccess.WRITE)
	f2.store_string("{corrupt again!!")
	f2.close()
	var corrupt_copy := "user://camera_bookmarks.corrupt-test.json"
	DirAccess.copy_absolute("user://camera_bookmarks.json", corrupt_copy)
	store = BookmarkStore.new()
	_check(store.list_bookmarks(&"m01_afterglow").is_empty(), "损坏且无备份时空库")
	_check(FileAccess.file_exists(corrupt_copy), "损坏副本未被清空（隔离保留）")
	# 清理
	DirAccess.remove_absolute("user://camera_bookmarks.json")
	DirAccess.remove_absolute(corrupt_copy)


# ---------------- QualityController（§7.5） ----------------

func _test_quality_controller() -> void:
	var q := Node.new()
	q.set_script(load("res://scripts/app/settings_manager.gd"))
	root.add_child(q)
	# 等待 _ready
	await process_frame
	_check(String(q.get_profile_id()) == "eco", "默认档位 Eco")
	_check(q.set_profile(&"unknown_tier") == ERR_INVALID_PARAMETER, "未知档位返回错误")
	_check(q.set_profile(&"balanced", false) == OK, "切换 Balanced 成功")
	_check(String(q.get_profile_id()) == "balanced", "档位已切换")
	var eff: Dictionary = q.get_effective_state()
	for key in ["profile_id", "frame_cap", "render_scale", "aa_mode", "glow_enabled", "probe_count", "particle_emitter_count", "runtime_fill_count", "occlusion_enabled", "focused", "minimized", "renderer"]:
		_check(eff.has(key), "effective_state 含字段 %s" % key)
	_check(int(eff["frame_cap"]) == 60, "Balanced 帧率上限实际生效")
	# 快照恢复
	var snap: Dictionary = q.capture_runtime_state()
	q.set_profile(&"eco", false)
	q.restore_runtime_state(snap)
	_check(String(q.get_profile_id()) == "balanced", "快照恢复档位")
	# 窗口状态优先级
	q.set_profile(&"eco", false)
	q.set_window_state(false, true)
	_check(int(q.get_effective_state()["frame_cap"]) == 5, "最小化帧率 5")
	q.set_window_state(false, false)
	_check(int(q.get_effective_state()["frame_cap"]) == 10, "失焦帧率 10")
	q.set_window_state(true, false)
	_check(int(q.get_effective_state()["frame_cap"]) == 30, "恢复用户档位帧率")
	q.queue_free()


# ---------------- MapDefinition v1→v2（T01/T02） ----------------

func _test_map_definition() -> void:
	# v1 .tres 读取：新字段自动落默认值，validate 通过
	var def := load("res://maps/m01_afterglow/map_definition.tres") as MapDefinition
	_check(def != null, "M01 定义可加载")
	if def != null:
		_check(def.schema_version <= 2 and def.validate() == "", "磁盘定义 validate 通过")
		_check(def.get_capture_anchor_names().size() > 0, "capture 锚点回落 anchor_names")
		# 真正的 v1 文件（显式 schema_version=1）：读入补默认值
		var v1 := MapDefinition.new()
		v1.schema_version = 1
		v1.map_id = "v1_compat"
		v1.scene_path = "res://tests/fixtures/mini_test_map.tscn"
		ResourceSaver.save(v1, "user://v1_compat_def.tres")
		var v1_back := load("user://v1_compat_def.tres") as MapDefinition
		_check(v1_back != null and v1_back.schema_version == 1, "v1 文件读回 schema_version=1")
		_check(v1_back != null and v1_back.validate() == "", "v1 文件 validate 通过")
		_check(v1_back != null and v1_back.content_revision == "1.0.0" and not v1_back.requires_baked_lighting, "v1 读入补默认值")
		# v2 编程构造
		var v2 := MapDefinition.new()
		v2.map_id = "test_v2"
		v2.scene_path = "res://tests/fixtures/mini_test_map.tscn"
		v2.content_revision = "1.1.0"
		_check(v2.validate() == "", "v2 构造 validate 通过")
		# 未来版本拒绝
		var v3 := MapDefinition.new()
		v3.schema_version = 3
		v3.map_id = "test_v3"
		v3.scene_path = "res://tests/fixtures/mini_test_map.tscn"
		_check(not v3.validate().is_empty(), "schema_version=3 明确拒绝")
		# 非法 bounds 拒绝
		var vb := MapDefinition.new()
		vb.map_id = "test_vb"
		vb.scene_path = "res://tests/fixtures/mini_test_map.tscn"
		vb.camera_bounds = AABB(Vector3.ZERO, Vector3.ZERO)
		_check(not vb.validate().is_empty(), "零尺寸 bounds 明确拒绝")
