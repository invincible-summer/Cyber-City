## BuildContract — chapter1-3 §2 构建可信性纯制作辅助层。
## 职责只限：递归解析资源依赖、生成稳定输入签名、计算应烘焙覆盖、只读 JSON、
## 可恢复 JSON 替换、AABB 精确重复检查。不生成场景、不决定 manifest 状态机、
## 不启动 bake、不修改地图场景、不运行测试。
## 签名组成（§2.4）：依赖文件集 hash + LightmapGI 烘焙设置快照 +（按 environment_mode）
## 环境快照；数值统一 5 位小数规范化，杜绝 tscn 往返浮点漂移。
class_name BuildContract
extends RefCounted


## bake 输入依赖的排除规则（§2.3）：烘焙输出/清单/工件/文档/测试/uid/运行脚本。
## 不排除 addons 等未来可能成为真实依赖的目录（R6：宁可重烘不可漏变化）。
const EXCLUDED_PREFIXES: PackedStringArray = [
	"res://artifacts/",
	"res://docs/",
	"res://tests/",
	"res://.godot/",
]
const IMAGE_EXTS: PackedStringArray = ["png", "webp", "jpg", "jpeg", "svg", "bmp", "tga"]
## LightmapGI 4.7.2 实测烘焙相关属性（probe 确认，不得臆造）。
const BAKE_SETTING_PROPS: PackedStringArray = [
	"quality", "directional", "interior", "use_denoiser", "bias", "texel_scale",
	"environment_mode", "environment_custom_energy",
]
## 环境快照覆盖的 Environment 属性（bake 环境光/天空来源）。
const ENV_PROPS: PackedStringArray = [
	"background_mode", "ambient_light_source", "ambient_light_color",
	"ambient_light_energy", "ambient_light_sky_contribution",
]


# ============================ 依赖解析 ============================

static func normalize_dependency_path(raw: String) -> String:
	## ResourceLoader.get_dependencies 可能返回普通 res:// 路径，也可能返回
	## uid://xxx::::res://fallback（实测 4.7.2 四冒号）或文档 UID::空::fallback 形式。
	## 统一取最后一个 res:// 起始的子串。
	var idx := raw.rfind("res://")
	if idx >= 0:
		return raw.substr(idx)
	return raw.strip_edges()


static func collect_dependency_closure(root_paths: PackedStringArray) -> PackedStringArray:
	## 递归收集依赖闭包（排序去重）。源图片返回的是源资产路径，不含 .godot/imported。
	var out: PackedStringArray = []
	var seen := {}
	var queue: Array[String] = []
	for p in root_paths:
		queue.append(String(p))
	while not queue.is_empty():
		var path := queue.pop_front() as String
		if path.is_empty() or seen.has(path):
			continue
		seen[path] = true
		if not FileAccess.file_exists(path):
			continue
		out.append(path)
		for dep in ResourceLoader.get_dependencies(path):
			var n := normalize_dependency_path(String(dep))
			if not n.is_empty() and not seen.has(n):
				queue.append(n)
	out.sort()
	return out


static func collect_bake_input_files(root_paths: PackedStringArray, extra_paths: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	## 闭包 + 显式 extra，过滤排除项后得到真实 bake 输入；源图片同路径 .import 一并纳入。
	var paths := collect_dependency_closure(root_paths)
	for p in extra_paths:
		var n := normalize_dependency_path(String(p))
		if not paths.has(n):
			paths.append(n)
	var out: PackedStringArray = []
	for p in paths:
		if not _is_bake_input(String(p)):
			continue
		out.append(String(p))
		# 压缩/mipmap 等导入参数影响最终资源（§2.3）
		if IMAGE_EXTS.has(String(p).get_extension().to_lower()) and FileAccess.file_exists(String(p) + ".import"):
			out.append(String(p) + ".import")
	out.sort()
	return out


static func _is_bake_input(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	if not FileAccess.file_exists(path):
		return true  # 缺失也入列（stable_file_hash 会写 missing），变化方向安全
	for prefix in EXCLUDED_PREFIXES:
		if path.begins_with(prefix):
			return false
	if path.get_file() == "build_manifest.json":
		return false
	if "/baked/" in path:
		return false
	var ext := path.get_extension().to_lower()
	if ext == "uid" or ext == "gd" or ext == "tmp" or ext == "prev":
		return false
	return true


# ============================ 稳定哈希 ============================

static func stable_file_hash(path: String) -> String:
	## .tscn/.tres 剥离 Godot 4.7 保存时随机生成的 unique_id=NNN 再哈希（1.2 已验证）；
	## 其余按原始字节。
	if path.ends_with(".tscn") or path.ends_with(".tres"):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			return RegEx.create_from_string("unique_id=\\d+").sub(txt, "", true).sha256_text()
	if not FileAccess.file_exists(path):
		return "missing"
	return FileAccess.get_sha256(path)


static func hash_file_set(paths: PackedStringArray) -> String:
	## 路径+hash 串联后再哈希；调用方传入已排序列表或在此重排（双保险）。
	var sorted := PackedStringArray(paths)
	sorted.sort()
	var acc := ""
	for p in sorted:
		acc += String(p).trim_prefix("res://") + ":" + stable_file_hash(String(p)) + ";"
	return acc.sha256_text()


# ============================ 资源新鲜读取 ============================

static func load_resource_fresh(path: String, type_hint: String = "") -> Resource:
	## CACHE_MODE_REPLACE_DEEP：从磁盘刷新主资源及依赖，禁止旧 Resource cache
	## 冒充新 baked data（§2.4.1）。
	return ResourceLoader.load(path, type_hint, ResourceLoader.CACHE_MODE_REPLACE_DEEP)


# ============================ 烘焙覆盖判定 ============================

static func find_lightmap(node: Node) -> LightmapGI:
	if node is LightmapGI:
		return node
	for c in node.get_children():
		var r := find_lightmap(c)
		if r != null:
			return r
	return null


static func expected_bake_users(root: Node) -> Array[String]:
	## LightmapGI 子树内 GI 静态、带 UV2 的 MeshInstance3D 节点路径（相对 LightmapGI）。
	var lm := find_lightmap(root)
	if lm == null:
		return []
	var found: Array[String] = []
	_visit_bake_meshes(lm, lm, found)
	found.sort()
	return found


static func _visit_bake_meshes(node: Node, lm: LightmapGI, found: Array[String]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.gi_mode == GeometryInstance3D.GI_MODE_STATIC and mi.mesh is ArrayMesh:
			var mesh := mi.mesh as ArrayMesh
			var has_uv2 := mesh.get_surface_count() > 0
			for i in mesh.get_surface_count():
				if not (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2):
					has_uv2 = false
			if has_uv2:
				var rel := str(lm.get_path_to(mi))
				if not found.has(rel):
					found.append(rel)
	for c in node.get_children():
		_visit_bake_meshes(c, lm, found)


static func actual_bake_users(lm: LightmapGI) -> Array[String]:
	## LightmapGIData 实际覆盖的 user 路径（get_user_count/get_user_path，4.7.2 实测 API）。
	var out: Array[String] = []
	if lm == null or lm.light_data == null:
		return out
	for i in lm.light_data.get_user_count():
		var p := lm.light_data.get_user_path(i)
		if not out.has(p):
			out.append(p)
	out.sort()
	return out


static func missing_paths(expected: Array[String], actual: Array[String]) -> Array[String]:
	## expected - actual；actual 允许是超集（Backdrop 历史 user，§4.3）。
	var actual_set := {}
	for p in actual:
		actual_set[p] = true
	var out: Array[String] = []
	for p in expected:
		if not actual_set.has(p):
			out.append(p)
	return out


static func can_reuse_bake(prev: Dictionary, source_roots: PackedStringArray,
		current_hash: String, expected: Array[String], baked_path: String) -> bool:
	## §3.2 复用判定（assemble 两图与 bake 前置共用）：
	## prev schema v2 + roots 一致 + succeeded + hash 一致 + expected 一致 +
	## 磁盘真实数据可 fresh-load + actual 覆盖 expected。任一不满足即 false。
	## v1 不继承 succeeded（§2.6）：schema_version != 2 直接 false。
	if prev.is_empty() or int(prev.get("schema_version", 0)) != 2:
		return false
	if str(prev.get("bake_status", "")) != "succeeded":
		return false
	var prev_roots := PackedStringArray()
	for r in prev.get("bake_source_roots", []):
		prev_roots.append(String(r))
	if prev_roots.size() != source_roots.size():
		return false
	var a := PackedStringArray(prev_roots); a.sort()
	var b := PackedStringArray(source_roots); b.sort()
	if a != b:
		return false
	if str(prev.get("bake_input_hash", "")) != current_hash:
		return false
	var prev_expected: Array = prev.get("expected_baked_user_paths", [])
	if prev_expected.size() != expected.size():
		return false
	var prev_sorted: Array = prev_expected.duplicate()
	prev_sorted.sort()
	var cur_sorted: Array = []
	for p in expected:
		cur_sorted.append(p)
	cur_sorted.sort()
	if prev_sorted != cur_sorted:
		return false
	if not ResourceLoader.exists(baked_path):
		return false
	var fresh := load_resource_fresh(baked_path, "LightmapGIData") as LightmapGIData
	if fresh == null:
		return false
	var probe := LightmapGI.new()
	probe.light_data = fresh
	var actual := actual_bake_users(probe)
	return missing_paths(expected, actual).is_empty()


# ============================ 几何重复检查 ============================

static func exact_duplicate_aabbs(boxes: Array) -> Array:
	## 只报告完全相同（position+size 逐分量相等）的 AABB，重复者记 {index, duplicate_of}。
	## 有意的部分重叠不算错误（§2.2）。
	var out: Array = []
	for i in range(boxes.size()):
		var a: AABB = boxes[i]
		for j in range(i):
			var b: AABB = boxes[j]
			if is_equal_approx(a.position.x, b.position.x) and is_equal_approx(a.position.y, b.position.y) \
					and is_equal_approx(a.position.z, b.position.z) and is_equal_approx(a.size.x, b.size.x) \
					and is_equal_approx(a.size.y, b.size.y) and is_equal_approx(a.size.z, b.size.z):
				out.append({"index": i, "duplicate_of": j})
				break
	return out


# ============================ JSON I/O ============================

static func load_json_dict(path: String) -> Dictionary:
	## 只读；非法/不存在返回空字典，失败语义由调用方决定。
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func write_json_recoverable(path: String, data: Dictionary) -> Error:
	## 最低可恢复替换（§2.5.2）：tmp → 回读校验 → prev 备份 → 删旧 → 改名；
	## 失败时尝试 prev 恢复，双败保留 tmp/prev 供人工取证并返回错误。
	## 不宣称操作系统级原子覆盖。
	var tmp := path + ".tmp"
	var prev := path + ".prev"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_string(JSON.stringify(data, "  ", true))
	f.close()
	# 回读校验：JSON 必须可解析且为字典
	var verify_parsed = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	if not verify_parsed is Dictionary:
		DirAccess.remove_absolute(tmp)
		return ERR_PARSE_ERROR
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		DirAccess.remove_absolute(tmp)
		return ERR_CANT_OPEN
	if FileAccess.file_exists(path):
		var cp := DirAccess.copy_absolute(path, prev)
		if cp != OK:
			DirAccess.remove_absolute(tmp)
			return cp
		var rm := DirAccess.remove_absolute(path)
		if rm != OK:
			DirAccess.remove_absolute(tmp)
			return rm
	var rn := dir.rename(tmp.get_file(), path.get_file())
	if rn != OK:
		# 恢复 prev → path
		if FileAccess.file_exists(prev):
			if DirAccess.copy_absolute(prev, path) == OK:
				DirAccess.remove_absolute(prev)
				return rn
		return rn
	if FileAccess.file_exists(prev):
		DirAccess.remove_absolute(prev)
	return OK


# ============================ 烘焙签名 ============================

static func bake_settings_snapshot(lm: LightmapGI) -> Dictionary:
	## 序列化实际 4.7.2 烘焙相关值；数值规范化为字符串保证往返稳定。
	var snap := {}
	for prop in BAKE_SETTING_PROPS:
		var v = lm.get(prop)
		if prop == "environment_custom_color":
			snap[prop] = _canonical_color(v)
		elif v is float:
			snap[prop] = _canonical_float(v)
		else:
			snap[prop] = v
	# CUSTOM_SKY 时天空资源参与 bake（当前两图未用，占位记录资源路径）
	if lm.environment_mode == LightmapGI.ENVIRONMENT_MODE_CUSTOM_SKY and lm.environment_custom_sky != null:
		snap["environment_custom_sky_path"] = lm.environment_custom_sky.resource_path
	return snap


static func environment_snapshot(root: Node, lm: LightmapGI) -> Dictionary:
	## 按 environment_mode 记录 bake 相关环境输入（§2.4）：DISABLED 明确 disabled；
	## SCENE 序列化场景 WorldEnvironment 的环境光/天空来源属性。
	match lm.environment_mode:
		LightmapGI.ENVIRONMENT_MODE_DISABLED:
			return {"mode": "disabled"}
		LightmapGI.ENVIRONMENT_MODE_SCENE:
			var snap: Dictionary = {"mode": "scene"}
			var we: WorldEnvironment = _find_world_environment(root)
			if we == null or we.environment == null:
				snap["environment"] = "missing"
				return snap
			var env := we.environment
			for prop in ENV_PROPS:
				var v = env.get(prop)
				if v is Color:
					snap["env_" + prop] = _canonical_color(v)
				elif v is float:
					snap["env_" + prop] = _canonical_float(v)
				else:
					snap["env_" + prop] = v
			if env.sky != null and env.sky.sky_material != null:
				var sky_mat = env.sky.sky_material
				snap["sky_material_class"] = sky_mat.get_class()
				if sky_mat is ProceduralSkyMaterial:
					var psm := sky_mat as ProceduralSkyMaterial
					for prop in ["sky_top_color", "sky_horizon_color", "ground_bottom_color",
							"ground_horizon_color", "sun_angle_max", "sun_curve", "energy_multiplier"]:
						var v = psm.get(prop)
						if v is Color:
							snap["sky_" + prop] = _canonical_color(v)
						elif v is float:
							snap["sky_" + prop] = _canonical_float(v)
						else:
							snap["sky_" + prop] = v
			return snap
		LightmapGI.ENVIRONMENT_MODE_CUSTOM_SKY:
			var cs: Dictionary = {"mode": "custom_sky"}
			if lm.environment_custom_sky != null:
				cs["sky_resource"] = lm.environment_custom_sky.resource_path
			return cs
		_:
			return {"mode": "custom_color", "color": _canonical_color(lm.environment_custom_color),
				"energy": _canonical_float(lm.environment_custom_energy)}


static func compute_bake_signature(source_roots: PackedStringArray, map_root: Node, extra_paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	## 组装唯一 bake_input_hash（文件集 + 设置快照 + 环境快照）。
	## 返回 {bake_input_hash, bake_input_files, bake_settings, environment_snapshot}；
	## LightmapGI 缺失时 hash 为空串由调用方判失败。
	var lm := find_lightmap(map_root)
	if lm == null:
		return {"bake_input_hash": "", "error": "LightmapGI 未找到"}
	var files := collect_bake_input_files(source_roots, extra_paths)
	var file_entries: Array = []
	for p in files:
		file_entries.append({"path": String(p), "sha256": stable_file_hash(String(p))})
	var settings := bake_settings_snapshot(lm)
	var env_snap := environment_snapshot(map_root, lm)
	var acc := "files:" + hash_file_set(files)
	acc += "|settings:" + JSON.stringify(settings, "", true)
	acc += "|env:" + JSON.stringify(env_snap, "", true)
	return {
		"bake_input_hash": acc.sha256_text(),
		"bake_input_files": file_entries,
		"bake_settings": settings,
		"environment_snapshot": env_snap,
	}


# ============================ 辅助 ============================

static func _find_world_environment(root: Node) -> WorldEnvironment:
	if root is WorldEnvironment:
		return root
	for c in root.get_children():
		var r := _find_world_environment(c)
		if r != null:
			return r
	return null


static func _canonical_float(v: float) -> String:
	## 5 位小数规范化：内存值与 tscn 往返值（文本序列化精度差异）得到同一签名。
	return "%.5f" % v


static func _canonical_color(c: Color) -> String:
	return "%.5f,%.5f,%.5f,%.5f" % [c.r, c.g, c.b, c.a]
