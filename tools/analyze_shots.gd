## 截图像素统计（制作阶段工具）：检测全黑/过曝/暖光池/天地图对比。
## 运行：godot --headless --path . --script res://tools/analyze_shots.gd
extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dir := "res://artifacts/screenshots"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".png"):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(dir + "/" + f))
		if img == null:
			print(f, " LOAD_FAIL")
			continue
		var w := img.get_width()
		var h := img.get_height()
		var n := 0
		var lum_sum := 0.0
		var black := 0
		var blown := 0
		var warm := 0
		var sky_lum := 0.0
		var sky_n := 0
		var gnd_lum := 0.0
		var gnd_n := 0
		for y in range(0, h, 3):
			for x in range(0, w, 3):
				var c := img.get_pixel(x, y)
				var l: float = c.get_luminance()
				n += 1
				lum_sum += l
				if l < 0.04:
					black += 1
				if l > 0.92 and c.s > 0.1:
					blown += 1
				if c.r - c.b > 0.08 and l > 0.15:
					warm += 1
				if y < h * 0.18:
					sky_lum += l
					sky_n += 1
				if y > h * 0.6:
					gnd_lum += l
					gnd_n += 1
		print("SHOT %s %dx%d mean_lum=%.3f black=%.2f blown=%.3f warm=%.3f sky=%.3f ground=%.3f" % [
			f.trim_prefix("m01_afterglow_").trim_suffix(".png"), w, h,
			lum_sum / n, float(black) / n, float(blown) / n, float(warm) / n,
			sky_lum / sky_n, gnd_lum / gnd_n])
	quit(0)
