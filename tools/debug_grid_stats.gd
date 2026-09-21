extends SceneTree
## 一次性诊断：对截图做 N×M 网格统计（均值亮度 + 高亮像素占比），
## 客观探测自发光字迹（炸亮笔画）的位置与有无，不依赖视觉模型。
## 用法：--script res://tools/debug_grid_stats.gd -- <png绝对路径> [cols rows]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("用法: debug_grid_stats.gd -- <png> [cols rows]")
		quit(1)
		return
	var img := Image.load_from_file(args[0])
	if img == null:
		push_error("无法读取图片")
		quit(1)
		return
	var cols := 24 if args.size() < 2 else int(args[1])
	var rows := 14 if args.size() < 3 else int(args[2])
	print("size=", img.get_size(), " grid=", cols, "x", rows)
	for r in rows:
		var line := ""
		for c in cols:
			var x0 := int(float(c) / cols * img.get_width())
			var y0 := int(float(r) / rows * img.get_height())
			var x1 := int(float(c + 1) / cols * img.get_width())
			var y1 := int(float(r + 1) / rows * img.get_height())
			var sum := 0.0
			var bright := 0
			var n := 0
			for y in range(y0, y1, 3):
				for x in range(x0, x1, 3):
					var l := img.get_pixel(x, y).get_luminance()
					sum += l
					if l > 0.85:
						bright += 1
					n += 1
			var mean := sum / maxf(1.0, float(n))
			var pct := 100.0 * bright / maxf(1.0, float(n))
			line += "%4.2f/%4.1f " % [mean, pct]
		print("r%02d %s" % [r, line])
	quit(0)
