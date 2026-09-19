## 离线城市生成库：网格构建器（含 lightmap UV2 shelf 打包）、通用建筑构件。
## 仅制作阶段使用；发布程序不引用本文件。
class_name GenLib
extends RefCounted

## Lightmap atlas 假设尺寸（UV2 密度换算用）。
const ATLAS_PX := 6144.0
const FACE_ALL := 63
const FACE_NO_BOTTOM := 63 - 8


## UV2 天际线（skyline）装箱：矩形放到当前轮廓最低可放处，可回填早前余量。
## 配合提交前按高度降序使用。高度按 2 的幂分桶减少碎片。
class ShelfPacker:
	const SNAP := 1.0 / 1024.0
	var segments: Array = []   # [{x, y, w}]，按 x 连续排列
	var used_area := 0.0
	var overflow_count := 0
	var overflow_buckets := {}

	func _init() -> void:
		segments = [{"x": 0.0, "y": 0.0, "w": 1.0}]

	func overflow_stats(key: String) -> void:
		overflow_buckets[key] = int(overflow_buckets.get(key, 0)) + 1

	func overflow_report() -> String:
		var entries: Array = []
		for k in overflow_buckets:
			entries.append({"k": k, "n": overflow_buckets[k]})
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) > int(b["n"]))
		var parts: PackedStringArray = []
		var count := 0
		for e in entries:
			parts.append("%s×%d" % [e["k"], e["n"]])
			count += 1
			if count >= 10:
				break
		return ", ".join(parts)

	func alloc(w: float, h: float) -> Rect2:
		var wq: float = ceili(w / SNAP) * SNAP
		var cells_h := maxi(1, ceili(h / SNAP))
		var bucket := 1
		while bucket < cells_h:
			bucket *= 2
		var hq: float = float(bucket) * SNAP
		if wq <= 0.0 or hq <= 0.0:
			return Rect2()
		if wq > 1.0 + 1e-6 or hq > 1.0 + 1e-6:
			overflow_count += 1
			overflow_stats("%dx%d" % [int(round(wq * 1000)), int(round(hq * 1000))])
			return Rect2(0.5, 0.5, 0.02, 0.02)
		var best := _find_slot(wq)
		if best["y"] + hq > 1.0 + 1e-6:
			overflow_count += 1
			overflow_stats("%dx%d" % [int(round(wq * 1000)), int(round(hq * 1000))])
			return Rect2(0.5, 0.5, 0.02, 0.02)
		var x: float = best["x"]
		var y: float = best["y"]
		_place(x, y, wq, hq, int(best["i"]), int(best["end"]))
		used_area += wq * hq
		return Rect2(x, y, wq, hq)

	func _find_slot(w: float) -> Dictionary:
		## 返回 {x, y, i, end}：从段 i 开始跨到 end-1，底边高度 y 为跨度内最高段。
		var best := {"x": 0.0, "y": 2.0, "i": 0, "end": 0}
		var i := 0
		while i < segments.size():
			var seg: Dictionary = segments[i]
			var x0: float = seg["x"]
			var y: float = seg["y"]
			var covered: float = 0.0
			var j := i
			while j < segments.size() and covered < w - 1e-9:
				var sj: Dictionary = segments[j]
				y = maxf(y, sj["y"])
				covered = sj["x"] + sj["w"] - x0
				j += 1
			if covered >= w - 1e-9 and y < best["y"] - 1e-9:
				best = {"x": x0, "y": y, "i": i, "end": j}
				if y <= 1e-9:
					break  # 已经贴地，不可能更低
			i += 1
		return best

	func _place(x: float, y: float, w: float, h: float, i0: int, end: int) -> void:
		## 用新矩形顶面替换被跨越的天际线段，保留左右残段。
		var new_segs: Array = []
		for k in range(0, i0):
			new_segs.append(segments[k])
		var first: Dictionary = segments[i0]
		var left_w: float = x - float(first["x"])
		if left_w > 1e-9:
			new_segs.append({"x": first["x"], "y": first["y"], "w": left_w})
		new_segs.append({"x": x, "y": y + h, "w": w})
		var last: Dictionary = segments[end - 1]
		var right_x: float = x + w
		var last_end: float = float(last["x"]) + float(last["w"])
		if last_end - right_x > 1e-9:
			new_segs.append({"x": right_x, "y": last["y"], "w": last_end - right_x})
		for k in range(end, segments.size()):
			new_segs.append(segments[k])
		segments = new_segs

	func utilization() -> float:
		return used_area

	func max_y() -> float:
		var m := 0.0
		for s in segments:
			m = maxf(m, s["y"])
		return m


## 网格构建器：按材质键累积表面；UV2 在提交时按高度排序统一打包。
class MeshBuilder:
	var packer := ShelfPacker.new()
	var _surfs := {}
	var _order: Array[String] = []
	var _pending: Array = []

	func reset() -> void:
		_surfs = {}
		_order = []
		_pending = []

	func _surf(key: String) -> Dictionary:
		if not _surfs.has(key):
			_surfs[key] = {
				"verts": PackedVector3Array(), "normals": PackedVector3Array(),
				"uvs": PackedVector2Array(), "uv2": PackedVector2Array(),
			}
			_order.append(key)
		return _surfs[key]

	func _push_tri(s: Dictionary, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2, w0: Vector2, w1: Vector2, w2: Vector2) -> void:
		var vs: PackedVector3Array = s["verts"]
		var ns: PackedVector3Array = s["normals"]
		var uv: PackedVector2Array = s["uvs"]
		var w2a: PackedVector2Array = s["uv2"]
		vs.append(p0); ns.append(n); uv.append(uv0); w2a.append(w0)
		vs.append(p1); ns.append(n); uv.append(uv1); w2a.append(w1)
		vs.append(p2); ns.append(n); uv.append(uv2); w2a.append(w2)

	## 四角按 (左下, 右下, 右上, 左上) 逆时针（从法线一侧看）。
	## uv2_size：lightmap 所需矩形尺寸（UV 单位）；Vector2.ZERO = 不参与烘焙。
	func quad(key: String, c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, normal: Vector3, uv1: Array, uv2_size: Vector2) -> void:
		_pending.append({"key": key, "c0": c0, "c1": c1, "c2": c2, "c3": c3, "n": normal, "uv": uv1, "size": uv2_size})

	func _flush() -> void:
		## 按高度降序打包（shelf 装箱近似最优），再输出三角形。
		_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var sa: Vector2 = a["size"]
			var sb: Vector2 = b["size"]
			if absf(sa.y - sb.y) > 1e-7:
				return sa.y > sb.y
			return sa.x > sb.x)
		for q in _pending:
			var s := _surf(q["key"])
			var size: Vector2 = q["size"]
			var n: Vector3 = q["n"]
			var uv1: Array = q["uv"]
			var q0: Vector3 = q["c0"]
			var q1: Vector3 = q["c1"]
			var q2: Vector3 = q["c2"]
			var q3: Vector3 = q["c3"]
			if size.x <= 0.0 or size.y <= 0.0:
				_push_tri(s, q0, q1, q2, n, uv1[0], uv1[1], uv1[2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				_push_tri(s, q0, q2, q3, n, uv1[0], uv1[2], uv1[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				continue
			var rect := packer.alloc(size.x, size.y)
			var r0 := rect.position
			var r1 := Vector2(rect.position.x + rect.size.x, rect.position.y)
			var r2 := rect.position + rect.size
			var r3 := Vector2(rect.position.x, rect.position.y + rect.size.y)
			_push_tri(s, q0, q1, q2, n, uv1[0], uv1[1], uv1[2], r0, r1, r2)
			_push_tri(s, q0, q2, q3, n, uv1[0], uv1[2], uv1[3], r0, r2, r3)
		_pending = []

	## 轴对齐盒。a=min 角，b=max 角。uv_scale：每米 UV1 重复数；px_per_m：lightmap 密度（0 = 不烘焙）。
	func box(key: String, a: Vector3, b: Vector3, uv_scale: float, px_per_m: float, faces: int = FACE_ALL) -> void:
		var dens := px_per_m / ATLAS_PX
		if faces & 1:   # +X
			_quad_x(key, b.x, a, b, Vector3(1, 0, 0), uv_scale, dens)
		if faces & 2:   # -X
			_quad_x(key, a.x, a, b, Vector3(-1, 0, 0), uv_scale, dens)
		if faces & 4:   # +Y
			_quad_y(key, b.y, a, b, Vector3(0, 1, 0), uv_scale, dens)
		if faces & 8:   # -Y
			_quad_y(key, a.y, a, b, Vector3(0, -1, 0), uv_scale, dens)
		if faces & 16:  # +Z
			_quad_z(key, b.z, a, b, Vector3(0, 0, 1), uv_scale, dens)
		if faces & 32:  # -Z
			_quad_z(key, a.z, a, b, Vector3(0, 0, -1), uv_scale, dens)

	## 由对角两点（任意顺序/旋转 90° 的姿态）构造轴对齐盒。
	func box_between(key: String, p1: Vector3, p2: Vector3, uv_scale: float, px_per_m: float, faces: int = FACE_ALL) -> void:
		box(key, Vector3(minf(p1.x, p2.x), minf(p1.y, p2.y), minf(p1.z, p2.z)), Vector3(maxf(p1.x, p2.x), maxf(p1.y, p2.y), maxf(p1.z, p2.z)), uv_scale, px_per_m, faces)

	func _quad_x(key: String, x: float, a: Vector3, b: Vector3, n: Vector3, uv_scale: float, dens: float) -> void:
		var w := b.z - a.z
		var h := b.y - a.y
		var c0: Vector3
		var c1: Vector3
		var c2: Vector3
		var c3: Vector3
		if n.x > 0:
			# 观察者在 +X：右侧为 -Z，左下角在 z_max
			c0 = Vector3(x, a.y, b.z); c1 = Vector3(x, a.y, a.z)
			c2 = Vector3(x, b.y, a.z); c3 = Vector3(x, b.y, b.z)
		else:
			c0 = Vector3(x, a.y, a.z); c1 = Vector3(x, a.y, b.z)
			c2 = Vector3(x, b.y, b.z); c3 = Vector3(x, b.y, a.z)
		_quad_world_uv(key, c0, c1, c2, c3, n, uv_scale, dens, w, h)

	func _quad_y(key: String, y: float, a: Vector3, b: Vector3, n: Vector3, uv_scale: float, dens: float) -> void:
		var w := b.x - a.x
		var h := b.z - a.z
		var c0: Vector3
		var c1: Vector3
		var c2: Vector3
		var c3: Vector3
		if n.y > 0:
			c0 = Vector3(a.x, y, b.z); c1 = Vector3(b.x, y, b.z)
			c2 = Vector3(b.x, y, a.z); c3 = Vector3(a.x, y, a.z)
		else:
			c0 = Vector3(a.x, y, a.z); c1 = Vector3(b.x, y, a.z)
			c2 = Vector3(b.x, y, b.z); c3 = Vector3(a.x, y, b.z)
		_quad_world_uv(key, c0, c1, c2, c3, n, uv_scale, dens, w, h)

	func _quad_z(key: String, z: float, a: Vector3, b: Vector3, n: Vector3, uv_scale: float, dens: float) -> void:
		var w := b.x - a.x
		var h := b.y - a.y
		var c0: Vector3
		var c1: Vector3
		var c2: Vector3
		var c3: Vector3
		if n.z > 0:
			# 观察者在 +Z：右侧为 +X，左下角在 x_min
			c0 = Vector3(a.x, a.y, z); c1 = Vector3(b.x, a.y, z)
			c2 = Vector3(b.x, b.y, z); c3 = Vector3(a.x, b.y, z)
		else:
			c0 = Vector3(b.x, a.y, z); c1 = Vector3(a.x, a.y, z)
			c2 = Vector3(a.x, b.y, z); c3 = Vector3(b.x, b.y, z)
		_quad_world_uv(key, c0, c1, c2, c3, n, uv_scale, dens, w, h)

	func _quad_world_uv(key: String, c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, n: Vector3, uv_scale: float, dens: float, w: float, h: float) -> void:
		## 竖直面 v 取 -y，使墙脚对应纹理底部（污渍朝下）。
		var uv: Array = []
		var size := Vector2(absf(w) * dens, absf(h) * dens)
		if absf(n.y) > 0.5:
			for p in [c0, c1, c2, c3]:
				uv.append(Vector2(p.x * uv_scale, p.z * uv_scale))
		else:
			for p in [c0, c1, c2, c3]:
				uv.append(Vector2(p.z * uv_scale, -p.y * uv_scale))
		quad(key, c0, c1, c2, c3, n, uv, size)

	## 竖直圆柱（灯杆、管道、水箱）。侧面按段输出，winding 朝外。
	func cylinder(key: String, base: Vector3, radius: float, height: float, segs: int, uv_scale: float, px_per_m: float, caps: bool = true) -> void:
		var dens := px_per_m / ATLAS_PX
		var circ := TAU * radius
		var chord := 2.0 * radius * sin(PI / segs)
		var side_size := Vector2(chord * dens, height * dens)
		var cap_size := Vector2(radius * 2.0 * dens, radius * 2.0 * dens)
		var v0 := -base.y * uv_scale
		var v1 := -(base.y + height) * uv_scale
		for i in segs:
			var a0 := float(i) / segs * TAU
			var a1 := float(i + 1) / segs * TAU
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var p00 := base + d0 * radius
			var p01 := base + d1 * radius
			var p10 := p00 + Vector3.UP * height
			var p11 := p01 + Vector3.UP * height
			var u0 := float(i) / segs * circ * uv_scale
			var u1 := float(i + 1) / segs * circ * uv_scale
			var nrm := ((d0 + d1) * 0.5).normalized()
			# c0 取观察者左侧（角度大的一端）保证逆时针
			quad(key, p01, p00, p10, p11, nrm, [Vector2(u1, v0), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1)], side_size)
		if caps and dens > 0.0:
			var top := base + Vector3.UP * height
			var ring: Array[Vector3] = []
			for k in 8:
				var ang := TAU * k / 8.0
				ring.append(top + Vector3(cos(ang) * radius, 0, sin(ang) * radius))
			for k in 4:
				# 顶面 8 边形：每 90° 一个退化四边形（第一边为零面积）
				var pa := ring[(k * 2) % 8]
				var pb := ring[(k * 2 + 1) % 8]
				var pc := ring[(k * 2 + 2) % 8]
				quad(key, top, pb, pa, pa, Vector3.UP, [Vector2(), Vector2(), Vector2(), Vector2()], cap_size)
				quad(key, top, pc, pb, pb, Vector3.UP, [Vector2(), Vector2(), Vector2(), Vector2()], cap_size)

	## 小灯泡/挂灯（八面体）。
	func bulb(key: String, center: Vector3, r: float) -> void:
		var s := _surf(key)
		var top := center + Vector3(0, r, 0)
		var bot := center - Vector3(0, r, 0)
		var ring: Array[Vector3] = []
		for i in 4:
			var ang := TAU * i / 4.0 + PI / 4.0
			ring.append(center + Vector3(cos(ang) * r, 0, sin(ang) * r))
		for i in 4:
			var p0 := ring[i]
			var p1 := ring[(i + 1) % 4]
			_push_tri(s, top, p0, p1, (top - center + p0 - center).normalized(), Vector2(), Vector2(), Vector2(), Vector2(), Vector2(), Vector2())
			_push_tri(s, bot, p1, p0, (bot - center + p0 - center).normalized(), Vector2(), Vector2(), Vector2(), Vector2(), Vector2(), Vector2())

	func tri_count() -> int:
		_flush()
		var total := 0
		for key in _order:
			var vs: PackedVector3Array = _surfs[key]["verts"]
			total += vs.size() / 3
		return total

	func commit(materials: Dictionary, path: String) -> ArrayMesh:
		_flush()
		var mesh := ArrayMesh.new()
		for key in _order:
			var s: Dictionary = _surfs[key]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = s["verts"]
			arrays[Mesh.ARRAY_NORMAL] = s["normals"]
			arrays[Mesh.ARRAY_TEX_UV] = s["uvs"]
			arrays[Mesh.ARRAY_TEX_UV2] = s["uv2"]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat = materials.get(key)
			if mat != null:
				mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		if not path.is_empty():
			var err := ResourceSaver.save(mesh, path)
			if err != OK:
				push_error("GenLib: 网格保存失败 %s (err=%d)" % [path, err])
		return mesh


## ---------- 通用构件（世界坐标直接构建） ----------

## 窗单元：轴 = 墙所贴的轴向（"x" 表示墙面法线沿 X）。wall_c = 墙面坐标，out_dir = 朝外方向（±1）。
## a_center = 沿墙方向的窗口中心坐标。keys: {frame, glass, lit_warm, lit_cool, sill}
static func window_unit(mb: MeshBuilder, axis: String, wall_c: float, out_dir: int, a_center: float, y_bottom: float, w: float, wh: float, keys: Dictionary, lit_type: int) -> void:
	## lit_type: 0=暗玻璃, 1=暖光, 2=冷光
	var h := wh
	var frame_key: String = keys.get("frame", "metal_dark")
	var glass_key: String = keys.get("glass", "glass_dark")
	if lit_type == 1:
		glass_key = keys.get("lit_warm", "window_lit_warm")
	elif lit_type == 2:
		glass_key = keys.get("lit_cool", "window_lit_cool")
	var out_v := Vector3(out_dir, 0, 0) if axis == "x" else Vector3(0, 0, out_dir)
	# 玻璃（内凹 0.12）
	var glass_off := wall_c + out_dir * -0.12
	var uv01 := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var glass_uv2 := Vector2(w * 24.0 / ATLAS_PX, h * 24.0 / ATLAS_PX)
	if axis == "x":
		if out_dir > 0:
			mb.quad(glass_key, Vector3(glass_off, y_bottom, a_center + w * 0.5), Vector3(glass_off, y_bottom, a_center - w * 0.5), Vector3(glass_off, y_bottom + h, a_center - w * 0.5), Vector3(glass_off, y_bottom + h, a_center + w * 0.5), out_v, uv01, glass_uv2)
		else:
			mb.quad(glass_key, Vector3(glass_off, y_bottom, a_center - w * 0.5), Vector3(glass_off, y_bottom, a_center + w * 0.5), Vector3(glass_off, y_bottom + h, a_center + w * 0.5), Vector3(glass_off, y_bottom + h, a_center - w * 0.5), out_v, uv01, glass_uv2)
	else:
		if out_dir > 0:
			mb.quad(glass_key, Vector3(a_center - w * 0.5, y_bottom, glass_off), Vector3(a_center + w * 0.5, y_bottom, glass_off), Vector3(a_center + w * 0.5, y_bottom + h, glass_off), Vector3(a_center - w * 0.5, y_bottom + h, glass_off), out_v, uv01, glass_uv2)
		else:
			mb.quad(glass_key, Vector3(a_center + w * 0.5, y_bottom, glass_off), Vector3(a_center - w * 0.5, y_bottom, glass_off), Vector3(a_center - w * 0.5, y_bottom + h, glass_off), Vector3(a_center + w * 0.5, y_bottom + h, glass_off), out_v, uv01, glass_uv2)
	# 窗框（凸出 0.06，包边 0.05）
	var t := 0.05
	var protrude := 0.06
	var f_in := wall_c + out_dir * -0.04
	var f_out := wall_c + out_dir * protrude
	if axis == "x":
		mb.box(frame_key, Vector3(minf(f_in, f_out), y_bottom + h, a_center - w * 0.5 - t), Vector3(maxf(f_in, f_out), y_bottom + h + t, a_center + w * 0.5 + t), 0.33, 24.0)
		mb.box(frame_key, Vector3(minf(f_in, f_out), y_bottom - t, a_center - w * 0.5 - t), Vector3(maxf(f_in, f_out), y_bottom, a_center + w * 0.5 + t), 0.33, 24.0)
		mb.box(frame_key, Vector3(minf(f_in, f_out), y_bottom, a_center - w * 0.5 - t), Vector3(maxf(f_in, f_out), y_bottom + h, a_center - w * 0.5), 0.33, 24.0)
		mb.box(frame_key, Vector3(minf(f_in, f_out), y_bottom, a_center + w * 0.5), Vector3(maxf(f_in, f_out), y_bottom + h, a_center + w * 0.5 + t), 0.33, 24.0)
		# 窗台
		if keys.has("sill"):
			mb.box(keys["sill"], Vector3(minf(wall_c, wall_c + out_dir * 0.14), y_bottom - 0.06, a_center - w * 0.5 - 0.07), Vector3(maxf(wall_c, wall_c + out_dir * 0.14), y_bottom - 0.01, a_center + w * 0.5 + 0.07), 0.5, 24.0)
	else:
		mb.box(frame_key, Vector3(a_center - w * 0.5 - t, y_bottom + h, minf(f_in, f_out)), Vector3(a_center + w * 0.5 + t, y_bottom + h + t, maxf(f_in, f_out)), 0.33, 24.0)
		mb.box(frame_key, Vector3(a_center - w * 0.5 - t, y_bottom - t, minf(f_in, f_out)), Vector3(a_center + w * 0.5 + t, y_bottom, maxf(f_in, f_out)), 0.33, 24.0)
		mb.box(frame_key, Vector3(a_center - w * 0.5 - t, y_bottom, minf(f_in, f_out)), Vector3(a_center - w * 0.5, y_bottom + h, maxf(f_in, f_out)), 0.33, 24.0)
		mb.box(frame_key, Vector3(a_center + w * 0.5, y_bottom, minf(f_in, f_out)), Vector3(a_center + w * 0.5 + t, y_bottom + h, maxf(f_in, f_out)), 0.33, 24.0)
		if keys.has("sill"):
			mb.box(keys["sill"], Vector3(a_center - w * 0.5 - 0.07, y_bottom - 0.06, minf(wall_c, wall_c + out_dir * 0.14)), Vector3(a_center + w * 0.5 + 0.07, y_bottom - 0.01, maxf(wall_c, wall_c + out_dir * 0.14)), 0.5, 24.0)


## 阳台：底板 + 三面栏杆。
static func balcony(mb: MeshBuilder, axis: String, wall_c: float, out_dir: int, a0: float, a1: float, y: float, depth: float, keys: Dictionary) -> void:
	var slab_key: String = keys.get("concrete", "concrete_plain")
	var rail_key: String = keys.get("metal", "metal_dark")
	var out0 := wall_c
	var out1 := wall_c + out_dir * depth
	var lo := minf(out0, out1)
	var hi := maxf(out0, out1)
	var a_lo := minf(a0, a1)
	var a_hi := maxf(a0, a1)
	if axis == "x":
		mb.box(slab_key, Vector3(lo, y - 0.12, a_lo), Vector3(hi, y, a_hi), 0.5, 22.0)
		mb.box(rail_key, Vector3(lo, y, a_lo), Vector3(hi, y + 0.95, a_lo + 0.05), 0.8, 20.0)
		mb.box(rail_key, Vector3(lo, y, a_hi - 0.05), Vector3(hi, y + 0.95, a_hi), 0.8, 20.0)
		mb.box(rail_key, Vector3(hi - 0.05 if out_dir > 0 else lo, y, a_lo), Vector3(hi if out_dir > 0 else lo + 0.05, y + 0.95, a_hi), 0.8, 20.0)
	else:
		mb.box(slab_key, Vector3(a_lo, y - 0.12, lo), Vector3(a_hi, y, hi), 0.5, 22.0)
		mb.box(rail_key, Vector3(a_lo, y, lo), Vector3(a_lo + 0.05, y + 0.95, hi), 0.8, 20.0)
		mb.box(rail_key, Vector3(a_hi - 0.05, y, lo), Vector3(a_hi, y + 0.95, hi), 0.8, 20.0)
		mb.box(rail_key, Vector3(a_lo, y, hi - 0.05 if out_dir > 0 else lo), Vector3(a_hi, y + 0.95, hi if out_dir > 0 else lo + 0.05), 0.8, 20.0)


## 女儿墙 + 屋顶设备（水箱/空调/天线）。
static func roof_kit(mb: MeshBuilder, x0: float, z0: float, x1: float, z1: float, y: float, rng: RandomNumberGenerator, keys: Dictionary, tall: bool) -> void:
	var wall_key: String = keys.get("parapet", "concrete_plain")
	var t := 0.24
	mb.box(wall_key, Vector3(x0, y, z0), Vector3(x1, y + 0.55, z0 + t), 0.5, 18.0)
	mb.box(wall_key, Vector3(x0, y, z1 - t), Vector3(x1, y + 0.55, z1), 0.5, 18.0)
	mb.box(wall_key, Vector3(x0, y, z0 + t), Vector3(x0 + t, y + 0.55, z1 - t), 0.5, 18.0)
	mb.box(wall_key, Vector3(x1 - t, y, z0 + t), Vector3(x1, y + 0.55, z1 - t), 0.5, 18.0)
	# 屋面
	if keys.has("roof"):
		mb.box(keys["roof"], Vector3(x0 + t, y - 0.02, z0 + t), Vector3(x1 - t, y + 0.0, z1 - t), 0.25, 14.0)
	# 水箱
	if rng.randf() < 0.6:
		var tx := lerpf(x0 + 3.0, x1 - 3.0, rng.randf())
		var tz := lerpf(z0 + 3.0, z1 - 3.0, rng.randf())
		mb.cylinder(keys.get("metal", "metal_dark"), Vector3(tx, y + 0.7, tz), 1.0, 1.8, 10, 0.4, 16.0)
		for off in [Vector2(0.8, 0.8), Vector2(-0.8, 0.8), Vector2(0.8, -0.8), Vector2(-0.8, -0.8)]:
			mb.box(keys.get("metal", "metal_dark"), Vector3(tx + off.x - 0.06, y, tz + off.y - 0.06), Vector3(tx + off.x + 0.06, y + 0.7, tz + off.y + 0.06), 0.8, 16.0)
	# 屋顶空调外机 ×2
	for i in 2:
		var ax := lerpf(x0 + 2.0, x1 - 2.5, rng.randf())
		var az := lerpf(z0 + 2.0, z1 - 2.5, rng.randf())
		mb.box(keys.get("metal", "metal_dark"), Vector3(ax, y, az), Vector3(ax + 0.9, y + 0.65, az + 0.7), 0.7, 20.0)
	# 天线
	if tall and rng.randf() < 0.7:
		var mx := lerpf(x0 + 2.0, x1 - 2.0, rng.randf())
		var mz := lerpf(z0 + 2.0, z1 - 2.0, rng.randf())
		mb.cylinder(keys.get("metal", "metal_dark"), Vector3(mx, y, mz), 0.05, 4.5, 6, 0.8, 12.0)
		mb.box(keys.get("metal", "metal_dark"), Vector3(mx - 0.5, y + 4.2, mz - 0.03), Vector3(mx + 0.5, y + 4.32, mz + 0.03), 0.8, 12.0)


## 路灯：返回灯头位置（供灯光生成）。
static func streetlight(mb: MeshBuilder, x: float, z: float, dir_x: int, dir_z: int, keys: Dictionary) -> Vector3:
	var pole_key: String = keys.get("metal", "metal_dark")
	var head_key: String = keys.get("lamp", "metal_paint_teal")
	mb.cylinder(pole_key, Vector3(x, 0.15, z), 0.07, 5.4, 8, 0.6, 20.0)
	var hx := x + dir_x * 1.05
	var hz := z + dir_z * 1.05
	mb.box(pole_key, Vector3(minf(x, hx), 5.25, minf(z, hz) - 0.05), Vector3(maxf(x, hx), 5.4, maxf(z, hz) + 0.05), 0.6, 20.0)
	mb.box(head_key, Vector3(hx - 0.28, 5.05, hz - 0.16), Vector3(hx + 0.28, 5.27, hz + 0.16), 0.6, 20.0)
	# 灯罩发光面
	var lens_key: String = keys.get("lens", "light_fixture_warm")
	var lens_uv2 := Vector2(0.5 / ATLAS_PX, 0.3 / ATLAS_PX)
	mb.quad(lens_key, Vector3(hx - 0.24, 5.06, hz - 0.12), Vector3(hx + 0.24, 5.06, hz - 0.12), Vector3(hx + 0.24, 5.06, hz + 0.12), Vector3(hx - 0.24, 5.06, hz + 0.12), Vector3.DOWN, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], lens_uv2)
	return Vector3(hx, 4.95, hz)


## 长椅（rot 仅支持 0 / 90° 的倍数）。
static func bench(mb: MeshBuilder, x: float, z: float, rot_y_rad: float, keys: Dictionary) -> void:
	var wood: String = keys.get("wood", "wood_old")
	var metal: String = keys.get("metal", "metal_dark")
	var cs := cos(rot_y_rad)
	var sn := sin(rot_y_rad)
	var fwd := Vector3(sn, 0, cs)
	var right := Vector3(cs, 0, -sn)
	var c := Vector3(x, 0, z)
	var hw := 0.9
	# 座面 + 靠背
	mb.box_between(wood, c - right * hw + Vector3(0, 0.42, -0.25), c + right * hw + Vector3(0, 0.5, 0.25), 0.5, 24.0)
	mb.box_between(wood, c - right * hw - fwd * 0.32 + Vector3(0, 0.5, 0), c + right * hw - fwd * 0.32 + Vector3(0, 0.95, 0), 0.5, 24.0)
	# 腿
	for s in [-1.0, 1.0]:
		var lp: Vector3 = c + right * hw * s * 0.8
		mb.box_between(metal, lp + Vector3(-0.04, 0.15, -0.2), lp + Vector3(0.04, 0.42, 0.2), 0.7, 20.0)


## 空调外机（墙上）。返回风扇中心（供动画节点）。
static func ac_unit(mb: MeshBuilder, center: Vector3, out_dir: Vector3, keys: Dictionary) -> Vector3:
	var metal: String = keys.get("metal", "metal_dark")
	var right := out_dir.cross(Vector3.UP).normalized()
	mb.box_between(metal, center - right * 0.42 - out_dir * 0.3 + Vector3(0, -0.33, 0), center + right * 0.42 + out_dir * 0.3 + Vector3(0, 0.33, 0), 0.7, 22.0)
	# 支架
	for s in [-1.0, 1.0]:
		var bp: Vector3 = center + right * s * 0.3
		mb.box_between(metal, bp + Vector3(-0.03, -0.55, -0.03), bp + Vector3(0.03, -0.33, 0.03), 0.8, 16.0)
	return center + out_dir * 0.305
