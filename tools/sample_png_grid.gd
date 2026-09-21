## 一次性诊断：对截图做 12x8 网格取色（判定画面区域内容，无图像输入环境下的目检替代）。
## 用法：--script res://tools/sample_png_grid.gd -- <png绝对路径> [列数 行数]
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("用法: sample_png_grid.gd -- <png> [cols rows]")
		quit(1)
		return
	var path := args[0]
	var cols := 12
	var rows := 8
	if args.size() >= 3:
		cols = int(args[1])
		rows = int(args[2])
	var img := Image.load_from_file(path)
	if img == null:
		push_error("无法读取图片: " + path)
		quit(1)
		return
	print("size=", img.get_size())
	for r in rows:
		var line := ""
		for c in cols:
			var x0 := int(float(c) / float(cols) * float(img.get_width()))
			var y0 := int(float(r) / float(rows) * float(img.get_height()))
			var x1 := int(float(c + 1) / float(cols) * float(img.get_width()))
			var y1 := int(float(r + 1) / float(rows) * float(img.get_height()))
			var acc := Vector3.ZERO
			var n := 0
			var sx := maxf(1.0, float(x1 - x0) / 8.0)
			var sy := maxf(1.0, float(y1 - y0) / 8.0)
			var yy := float(y0)
			while yy < float(y1):
				var xx := float(x0)
				while xx < float(x1):
					var px: Color = img.get_pixel(int(xx), int(yy))
					acc += Vector3(px.r, px.g, px.b)
					n += 1
					xx += sx
				yy += sy
			var avg := acc / float(maxi(n, 1))
			line += "%02X%02X%02X " % [int(avg.x * 255.0), int(avg.y * 255.0), int(avg.z * 255.0)]
		print("row%d %s" % [r, line])
	quit(0)
