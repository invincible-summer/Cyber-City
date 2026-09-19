## 离线纹理生成（制作阶段工具；发布程序不运行本脚本）。
## 运行：godot --headless --path . --script res://tools/gen_textures.gd
## 输出全部为原创程序化纹理，保存到 assets/m01_afterglow/textures/。
extends SceneTree

const OUT_DIR := "res://assets/m01_afterglow/textures"

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_rng.seed = 20260919
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_tex_wall_bluegray()
	_tex_wall_warm()
	_tex_wall_panel()
	_tex_wall_brick()
	_tex_asphalt()
	_tex_pavement()
	_tex_plaza_paving()
	_tex_alley_ground()
	_tex_backdrop_facade()
	_tex_poster()
	_tex_interior_shelf()
	_tex_roof_gravel()
	print("TEXTURES_DONE")
	quit(0)


# ---------- 基础绘制助手 ----------

func _mk_noise(seed_val: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	return n


func _img(size: int, color: Color) -> Image:
	var im := Image.create(size, size, false, Image.FORMAT_RGB8)
	im.fill(color)
	return im


func _jitter(im: Image, noise: FastNoiseLite, amp: float) -> void:
	## 围绕现有颜色做低幅度噪声扰动（保持可平铺的低对比 mottle）。
	var w := im.get_width()
	for y in w:
		for x in w:
			var c := im.get_pixel(x, y)
			var v := (noise.get_noise_2d(x, y) + noise.get_noise_2d(x + 91.7, y + 45.3)) * 0.5
			var d := v * amp
			im.set_pixel(x, y, Color(clampf(c.r + d, 0.0, 1.0), clampf(c.g + d, 0.0, 1.0), clampf(c.b + d, 0.0, 1.0)))


func _hline(im: Image, y: int, thickness: int, color: Color, alpha: float) -> void:
	var w := im.get_width()
	for t in thickness:
		var yy := y + t
		if yy < 0 or yy >= im.get_height():
			continue
		for x in w:
			var c := im.get_pixel(x, yy)
			im.set_pixel(x, yy, c.lerp(color, alpha))


func _vline_safe(im: Image, x: int, thickness: int, color: Color, alpha: float) -> void:
	var h := im.get_height()
	for t in thickness:
		var xx := x + t
		if xx < 0 or xx >= im.get_width():
			continue
		for y in h:
			var c := im.get_pixel(xx, y)
			im.set_pixel(xx, y, c.lerp(color, alpha))


func _bottom_grime(im: Image, strength: float, color: Color) -> void:
	## 底部旧化：向下渐变的污渍。
	var h := im.get_height()
	var w := im.get_width()
	for y in h:
		var t := float(y) / float(h - 1)
		var a := pow(t, 2.2) * strength
		if a < 0.01:
			continue
		for x in w:
			var c := im.get_pixel(x, y)
			im.set_pixel(x, y, c.lerp(color, a))


func _streaks(im: Image, rng: RandomNumberGenerator, count: int, color: Color, max_alpha: float) -> void:
	## 雨水冲刷竖向条纹。
	var w := im.get_width()
	var h := im.get_height()
	for i in count:
		var x0 := rng.randi_range(0, w - 1)
		var width := rng.randi_range(2, 5)
		var y0 := rng.randi_range(0, int(h * 0.4))
		var y1 := rng.randi_range(int(h * 0.6), h - 1)
		var a := rng.randf_range(max_alpha * 0.4, max_alpha)
		for x in range(x0, x0 + width):
			if x < 0 or x >= w:
				continue
			for y in range(y0, y1):
				var fade := 1.0 - float(y - y0) / maxf(1.0, float(y1 - y0))
				var c := im.get_pixel(x, y)
				im.set_pixel(x, y, c.lerp(color, a * fade * 0.6))


func _splats(im: Image, rng: RandomNumberGenerator, count: int, color: Color, max_r: int, max_alpha: float) -> void:
	var w := im.get_width()
	var h := im.get_height()
	for i in count:
		var cx := rng.randi_range(0, w - 1)
		var cy := rng.randi_range(0, h - 1)
		var r := rng.randi_range(max_r / 3, max_r)
		var a := rng.randf_range(max_alpha * 0.5, max_alpha)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				var dist := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
				if dist <= r:
					var c := im.get_pixel(x, y)
					im.set_pixel(x, y, c.lerp(color, a * (1.0 - dist / r) * 0.7))


func _save(im: Image, name: String) -> void:
	var path := "%s/%s.png" % [OUT_DIR, name]
	im.save_png(path)
	print("tex: ", path)


# ---------- 各纹理 ----------

func _tex_wall_bluegray() -> void:
	## 蓝灰抹灰墙：512px = 3m。接缝 + 轻微色差 + 底部污渍。
	var im := _img(512, Color(0.376, 0.467, 0.537))
	_jitter(im, _mk_noise(11, 0.012), 0.035)
	_hline(im, 132, 3, Color(0.3, 0.38, 0.45), 0.5)
	_hline(im, 388, 2, Color(0.3, 0.38, 0.45), 0.4)
	_streaks(im, _rng, 9, Color(0.26, 0.33, 0.4), 0.18)
	_splats(im, _rng, 3, Color(0.3, 0.36, 0.42), 26, 0.1)
	_bottom_grime(im, 0.35, Color(0.24, 0.29, 0.35))
	_save(im, "wall_bluegray")


func _tex_wall_warm() -> void:
	## 暖灰混凝土：512px = 3m。
	var im := _img(512, Color(0.647, 0.616, 0.565))
	_jitter(im, _mk_noise(23, 0.01), 0.04)
	_hline(im, 170, 2, Color(0.5, 0.47, 0.43), 0.45)
	_streaks(im, _rng, 7, Color(0.45, 0.42, 0.38), 0.15)
	_splats(im, _rng, 4, Color(0.48, 0.44, 0.38), 34, 0.12)
	_bottom_grime(im, 0.3, Color(0.4, 0.36, 0.31))
	_save(im, "wall_warm")


func _tex_wall_panel() -> void:
	## 面板立面：512px = 3m，1.5m 大板拼缝 + 螺栓点。
	var im := _img(512, Color(0.62, 0.64, 0.66))
	_jitter(im, _mk_noise(37, 0.02), 0.025)
	var seam := Color(0.42, 0.44, 0.47)
	_hline(im, 0, 3, seam, 0.7)
	_hline(im, 254, 3, seam, 0.7)
	_vline_safe(im, 2, 3, seam, 0.6)
	_vline_safe(im, 256, 3, seam, 0.6)
	for y in [40, 215, 300, 475]:
		for x in [30, 235, 280, 485]:
			_dot(im, x, y, 3, Color(0.35, 0.37, 0.4), 0.8)
	_bottom_grime(im, 0.18, Color(0.42, 0.43, 0.44))
	_save(im, "wall_panel")


func _dot(im: Image, cx: int, cy: int, r: int, color: Color, alpha: float) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or x >= im.get_width() or y < 0 or y >= im.get_height():
				continue
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				var c := im.get_pixel(x, y)
				im.set_pixel(x, y, c.lerp(color, alpha))


func _tex_wall_brick() -> void:
	## 砖墙：512px = 2.4m（砖 240×80mm，行高 42.6px，砖长 128px）。
	var im := _img(512, Color(0.52, 0.35, 0.3))
	_jitter(im, _mk_noise(41, 0.03), 0.03)
	var mortar := Color(0.68, 0.65, 0.6)
	var row_h := 42.6
	var brick_w := 128.0
	var row := 0
	var y := 0.0
	while y < 512.0:
		var offset := 0.0 if row % 2 == 0 else brick_w * 0.5
		var x := -offset
		while x < 512.0:
			var tint := _rng.randf_range(-0.06, 0.06)
			var bc := Color(0.52 + tint, 0.35 + tint * 0.8, 0.3 + tint * 0.8)
			var bx0 := maxi(int(x) + 2, 0)
			var bx1 := mini(int(x + brick_w) - 2, 512)
			var by0 := maxi(int(y) + 2, 0)
			var by1 := mini(int(y + row_h) - 2, 512)
			for yy in range(by0, by1):
				for xx in range(bx0, bx1):
					var j := _rng.randf_range(-0.025, 0.025)
					im.set_pixel(xx, yy, Color(clampf(bc.r + j, 0, 1), clampf(bc.g + j, 0, 1), clampf(bc.b + j, 0, 1)))
			x += brick_w
		for xx in 512:
			var c := im.get_pixel(xx, mini(int(y) + 1, 511))
			im.set_pixel(xx, mini(int(y) + 1, 511), c.lerp(mortar, 0.55))
		y += row_h
		row += 1
	_bottom_grime(im, 0.28, Color(0.32, 0.24, 0.2))
	_save(im, "wall_brick")


func _tex_asphalt() -> void:
	## 沥青路面：1024px = 12m。颗粒 + 裂缝 + 修补痕。
	var im := _img(1024, Color(0.13, 0.14, 0.155))
	_jitter(im, _mk_noise(53, 0.08), 0.05)
	# 碎石亮点
	for i in 900:
		var x := _rng.randi_range(0, 1023)
		var y := _rng.randi_range(0, 1023)
		var c := im.get_pixel(x, y)
		im.set_pixel(x, y, c.lerp(Color(0.32, 0.33, 0.35), _rng.randf_range(0.2, 0.5)))
	# 裂缝
	for crack in 3:
		var cx := _rng.randi_range(100, 924)
		var cy := _rng.randi_range(100, 924)
		var dark := Color(0.07, 0.075, 0.085)
		for step in 140:
			cx += _rng.randi_range(-6, 6)
			cy += _rng.randi_range(-4, 6)
			_dot(im, clampi(cx, 0, 1023), clampi(cy, 0, 1023), _rng.randi_range(1, 2), dark, 0.5)
	# 修补长条
	_splats(im, _rng, 2, Color(0.16, 0.17, 0.18), 60, 0.35)
	_save(im, "asphalt")


func _tex_pavement() -> void:
	## 人行道砖：512px = 2.4m（600×300 砖，128×128px）。
	var im := _img(512, Color(0.55, 0.55, 0.53))
	_jitter(im, _mk_noise(67, 0.025), 0.03)
	var seam := Color(0.4, 0.4, 0.39)
	for y in [0, 128, 256, 384]:
		_hline(im, y, 3, seam, 0.55)
	for x in [0, 128, 256, 384]:
		_vline_safe(im, x, 3, seam, 0.55)
	# 行间半错缝
	for row in 4:
		if row % 2 == 1:
			_vline_safe(im, 64 + row * 7, 3, seam, 0.55)
	_splats(im, _rng, 3, Color(0.42, 0.42, 0.4), 30, 0.1)
	_bottom_grime(im, 0.12, Color(0.42, 0.42, 0.4))
	_save(im, "pavement")


func _tex_plaza_paving() -> void:
	## 广场铺装：1024px = 9.6m（1.2m 石板，128px 网格，暖色）。
	var im := _img(1024, Color(0.51, 0.47, 0.43))
	_jitter(im, _mk_noise(79, 0.015), 0.035)
	var seam := Color(0.36, 0.33, 0.3)
	for i in 9:
		_hline(im, i * 128, 4, seam, 0.6)
		_vline_safe(im, i * 128, 4, seam, 0.6)
	for row in 9:
		for col in 9:
			var tint := _rng.randf_range(-0.04, 0.04)
			for y in range(row * 128 + 6, (row + 1) * 128 - 6, 2):
				for x in range(col * 128 + 6, (col + 1) * 128 - 6, 2):
					var c := im.get_pixel(x, y)
					im.set_pixel(x, y, Color(clampf(c.r + tint, 0, 1), clampf(c.g + tint, 0, 1), clampf(c.b + tint, 0, 1)))
	_splats(im, _rng, 4, Color(0.4, 0.36, 0.32), 60, 0.12)
	_save(im, "plaza_paving")


func _tex_alley_ground() -> void:
	## 侧巷地面：512px = 4m，深色 + 油渍。
	var im := _img(512, Color(0.15, 0.15, 0.16))
	_jitter(im, _mk_noise(97, 0.05), 0.04)
	_splats(im, _rng, 6, Color(0.08, 0.08, 0.09), 40, 0.4)
	_splats(im, _rng, 2, Color(0.2, 0.17, 0.13), 26, 0.2)
	_save(im, "alley_ground")


func _tex_backdrop_facade() -> void:
	## 远景楼立面：512px = 12m 楼宽 × 24m 高。暗底 + 稀疏亮窗（同图供 emission 使用）。
	var im := _img(512, Color(0.055, 0.07, 0.1))
	_jitter(im, _mk_noise(101, 0.02), 0.02)
	var cols := 8
	var rows := 12
	var cw := 512 / cols
	var rh := 512 / rows
	var warm := Color(0.95, 0.72, 0.43)
	var cool := Color(0.5, 0.62, 0.75)
	for row in rows:
		for col in cols:
			var r := _rng.randf()
			if r < 0.12:
				var c := warm if _rng.randf() < 0.75 else cool
				var x0 := col * cw + cw / 4
				var y0 := row * rh + rh / 3
				for y in range(y0, y0 + int(rh / 3)):
					for x in range(x0, x0 + int(cw / 2)):
						var jc := c.lerp(Color(0, 0, 0), _rng.randf_range(0.0, 0.25))
						im.set_pixel(x, y, jc)
			elif r < 0.22:
				var cd := Color(0.09, 0.11, 0.15)
				for y in range(row * rh + rh / 3, row * rh + rh / 3 + int(rh / 3)):
					for x in range(col * cw + cw / 4, col * cw + cw / 4 + int(cw / 2)):
						im.set_pixel(x, y, cd)
	# 竖向楼层分隔暗线
	for row in rows:
		_hline(im, row * rh, 2, Color(0.04, 0.05, 0.07), 0.5)
	_save(im, "backdrop_facade")


func _tex_poster() -> void:
	## 海报：256px。抽象版式 + 撕角，中文语义留待字体阶段。
	var im := _img(256, Color(0.88, 0.86, 0.82))
	_jitter(im, _mk_noise(131, 0.03), 0.02)
	var ink := Color(0.2, 0.22, 0.28)
	var accent := Color(0.86, 0.45, 0.35)
	for row in 5:
		var y := 52 + row * 28
		var w := 180 - row * 12
		for x in range(38, 38 + w):
			for t in 7:
				im.set_pixel(x, y + t, im.get_pixel(x, y + t).lerp(ink, 0.75))
	for t in 26:
		for x in range(38, 110):
			im.set_pixel(x, 22 + t, im.get_pixel(x, 22 + t).lerp(accent, 0.85))
	# 撕角
	for i in 40:
		for j in 40 - i:
			im.set_pixel(216 + i, 216 + j, Color(0.13, 0.14, 0.15, 1.0))
	_save(im, "poster")


func _tex_interior_shelf() -> void:
	## 店内背景墙：256px = 3m。暖渐变 + 货架剪影。
	var im := _img(256, Color(0.55, 0.42, 0.28))
	for y in 256:
		var t := float(y) / 255.0
		var c := Color(0.66, 0.52, 0.34).lerp(Color(0.36, 0.27, 0.18), t)
		for x in 256:
			im.set_pixel(x, y, c)
	_jitter(im, _mk_noise(149, 0.03), 0.02)
	var dark := Color(0.2, 0.15, 0.1)
	for shelf in 3:
		var y := 40 + shelf * 68
		for x in range(18, 238):
			for t in 6:
				im.set_pixel(x, y + t, dark)
		# 货物剪影
		for b in 5:
			var bx := 26 + b * 42
			var bh := _rng.randi_range(18, 34)
			var bw := _rng.randi_range(22, 32)
			for yy in range(y - bh, y):
				for xx in range(bx, bx + bw):
					if xx < 256 and yy >= 0:
						im.set_pixel(xx, yy, Color(0.3 + _rng.randf() * 0.2, 0.24, 0.16))
	_save(im, "interior_shelf")


func _tex_roof_gravel() -> void:
	## 屋面砾石：512px = 4m。
	var im := _img(512, Color(0.24, 0.24, 0.25))
	_jitter(im, _mk_noise(163, 0.09), 0.05)
	for i in 600:
		var x := _rng.randi_range(0, 511)
		var y := _rng.randi_range(0, 511)
		var c := im.get_pixel(x, y)
		im.set_pixel(x, y, c.lerp(Color(0.35, 0.35, 0.36), _rng.randf_range(0.2, 0.45)))
	_splats(im, _rng, 3, Color(0.18, 0.18, 0.19), 40, 0.2)
	_save(im, "roof_gravel")
