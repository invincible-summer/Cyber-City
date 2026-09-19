## 截图工具：自动隐藏 UI，等待实际绘制完成后取图，保存到 user://captures/。
extends Node

var capture_count := 0
var _last_time_msec := 0


func take_screenshot(layers_to_hide: Array, map_id: String, view_name: String, quality: String) -> String:
	## layers_to_hide: 需要临时隐藏的 CanvasLayer/Control 列表。返回保存路径或空字符串。
	var now := Time.get_ticks_msec()
	if now - _last_time_msec < 500:
		await get_tree().create_timer(0.5).timeout  # 重复按键节流
	now = Time.get_ticks_msec()
	_last_time_msec = now

	var hidden: Array = []
	for layer in layers_to_hide:
		if layer is CanvasItem and layer.visible:
			layer.visible = false
			hidden.append(layer)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var dir := "user://captures"
	DirAccess.make_dir_recursive_absolute(dir)
	var ts := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "_").replace(" ", "")
	var fname := "%s/%s_%s_%s_%s.png" % [dir, map_id, view_name, quality, ts]
	var err := img.save_png(fname)
	for layer in hidden:
		layer.visible = true
	if err != OK:
		push_error("Screenshot: 保存失败 %s (err=%d)" % [fname, err])
		return ""
	capture_count += 1
	return fname
