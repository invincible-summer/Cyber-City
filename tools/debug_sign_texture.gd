extends SceneTree
## 一次性诊断：headless 加载 repair_main.png 的导入产物，decompress 后
## 网格采样，验证引擎侧纹理是否真的含字（左中右/亮度分布）。

func _init() -> void:
	var tex: Texture2D = load("res://assets/m01_afterglow/textures/signs/repair_main.png")
	if tex == null:
		print("TEXTURE LOAD FAILED")
		quit(1)
		return
	var img := tex.get_image()
	print("size=", img.get_size(), " format=", img.get_format())
	if img.is_compressed():
		img.decompress()
		print("decompressed -> ", img.get_format())
	# 6×4 网格采样亮度
	var lum_min := 10.0
	var lum_max := -1.0
	for gy in 4:
		var row := ""
		for gx in 6:
			var px := img.get_pixel(int((gx + 0.5) * img.get_width() / 6.0), int((gy + 0.5) * img.get_height() / 4.0))
			var l := px.get_luminance()
			lum_min = minf(lum_min, l)
			lum_max = maxf(lum_max, l)
			row += "%4.2f " % l
		print(row)
	print("contrast_min=%.2f contrast_max=%.2f" % [lum_min, lum_max])
	quit(0)
