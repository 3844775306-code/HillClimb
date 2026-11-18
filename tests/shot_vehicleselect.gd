extends Node
## 选车界面截图：四辆车各存一张 png，用来肉眼检查卡片和预览。
##
## 用法（需要真实渲染，会短暂弹出窗口）：
##   godot --path . res://tests/shot_vehicleselect.tscn
##
## 无头模式也能跑，但**不要**拿无头下的图判断版面 —— 无头视口是 1280×1280，
## 卡片会被拉伸（见 README 的坑 #7）。
##
## 那张卡片上的车是**从各车的 `.tscn` 里读出来现画的**（[method Vehicles.silhouette]），
## 所以这组图也是「四辆车的形状对不对」最直观的一次检查 —— 摩托是不是摩托、
## 巴士是不是个方盒子，一眼就能看出来。

const OUT_DIR := "res://.shots"
const SELECT := preload("res://scenes/vehicleselect.tscn")

var _s: HillVehicleSelect


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveData.persist = false
	SaveData.reset_progress()

	_s = SELECT.instantiate()
	add_child(_s)
	for i in range(3):
		await get_tree().process_frame

	var view := get_viewport().get_visible_rect().size
	print("视口 %s   界面 size %s   能选 %d 辆" % [
		str(view), str(_s.size), _s._ids.size()])

	# 每辆车各存一张：光标停在它上面（高亮边框），鼠标悬停也放在它身上。
	for i in range(_s._ids.size()):
		var id: String = _s._ids[i]
		var v: Dictionary = Vehicles.get_vehicle(id)
		var st: Dictionary = Vehicles.stats(id)
		await _shot("%02d_%s" % [i + 1, id], i)
		print("  %-6s 质量 %.0f  车壳 %.0f  极速 %.0f  满油 %.1fs  推重比 %.2f%s" % [
			v["zh"], st["mass"], st["chassis_len"], st["top_speed"], st["fuel_seconds"],
			st["ratio"], "（被限幅）" if st["torque_clamped"] else "",
		])

	# 一张「悬停在别的卡上」的：边框高亮跟着鼠标走，但选中框还在原处。
	if _s._ids.size() > 1:
		_s._sel = 0
		_s._hover = 1
		_s.queue_redraw()
		for i in range(3):
			await get_tree().process_frame
		await _save("99_hover")

	get_tree().quit()


func _shot(shot_name: String, sel: int) -> void:
	_s._sel = sel
	_s._hover = sel
	_s.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await _save(shot_name)


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("截图失败 %s：%s" % [path, error_string(err)])
	else:
		print("已保存 %s" % shot_name)
