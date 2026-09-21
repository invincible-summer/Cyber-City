## 截图 → data URL 转换（chapter1-2 验收辅助，制作阶段工具）。
## 运行：godot --headless --path . --script res://tools/shot_to_dataurl.gd -- <输入.png> <输出.txt> [宽度]
## 用途：把本地截图缩放并编码为 data:image/jpeg;base64,... 单行文本，
##       供不支持本地文件读取的视觉验收工具消费。不做任何外发。
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("用法: shot_to_dataurl.gd -- <输入.png> <输出.txt> [宽度]")
		quit(1)
		return
	var in_path := ProjectSettings.globalize_path(args[0])
	var out_path := args[1]
	var width := 768
	if args.size() >= 3:
		width = int(args[2])
	var img := Image.load_from_file(in_path)
	if img == null:
		printerr("加载失败: %s" % in_path)
		quit(1)
		return
	var height := int(float(img.get_height()) * float(width) / float(img.get_width()))
	img.resize(width, height, Image.INTERPOLATE_LANCZOS)
	var err := img.save_jpg("user://shot_tmp.jpg", 0.82)
	if err != OK:
		printerr("JPEG 编码失败: %d" % err)
		quit(1)
		return
	var jpg := FileAccess.get_file_as_bytes("user://shot_tmp.jpg")
	var b64 := Marshalls.raw_to_base64(jpg)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("data:image/jpeg;base64," + b64)
	f.close()
	DirAccess.remove_absolute("user://shot_tmp.jpg")
	print("DATAURL_DONE %s -> %s (%d chars)" % [in_path, out_path, b64.length()])
	quit(0)
