## 裁剪 PNG 区域并放大保存（视觉验收辅助：把画面局部放大给独立视觉模型判读）。
## 运行：godot --headless --path . --script res://tools/crop_png.gd -- <src.png> <x> <y> <w> <h> <scale> <out.png>
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 7:
		push_error("crop_png: 需要 <src> <x> <y> <w> <h> <scale> <out>")
		quit(1)
		return
	var img := Image.load_from_file(args[0])
	if img == null:
		push_error("crop_png: 无法读取 %s" % args[0])
		quit(1)
		return
	var rect := Rect2i(int(args[1]), int(args[2]), int(args[3]), int(args[4]))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		push_error("crop_png: 裁剪区域为空")
		quit(1)
		return
	var c := img.get_region(rect)
	var s := maxi(1, int(args[5]))
	c.resize(rect.size.x * s, rect.size.y * s, Image.INTERPOLATE_NEAREST)
	c.save_png(args[6])
	print("crop: %s -> %s (%dx%d x%d)" % [args[0], args[6], rect.size.x, rect.size.y, s])
	quit()
