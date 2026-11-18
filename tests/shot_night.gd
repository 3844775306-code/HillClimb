extends Node
## 黑夜图截图：跑真实渲染，沿路连拍，用来肉眼检查车灯画得对不对。
##
## 用法（需要真实渲染，会短暂弹出窗口）：
##   godot --path . res://tests/shot_night.tscn
##
## 纯函数的断言在 tests/shapes.gd 的 `_section_night`（光池多亮、锥形多长、八辆车的
## 灯珠落不落在车壳多边形里），但**看不出好不好看**：光池会不会太亮、锥形边缘是不是
## 一条硬边、两颗灯珠看着像不像车灯 —— 只有截图能回答。这个特性是纯 `draw_polygon`
## 的逐顶点渐变（没有着色器），数值全对了也可能很难看。
##
## **第一张是关着灯的。** 用户的原话是「未被车灯照到的地方亮度改为白天的 0.05」，
## 关灯那一张整屏都该是那个 5%（车也几乎看不见）—— 这张图不对，后面几张都不用看。
##
## **腾空时必须松油门**（和 [tests/shot_rooftop.gd] 同一条规矩）：car.gd 里「空中按前进」
## 不是油门而是空中姿态，一直按着不放，车一被弹到空中就后空翻、拿车顶落地。

const OUT_DIR := "res://.shots"

## 第几秒截图。第 1 张关灯，之后开灯 —— 同一个位置看不出来，所以错开时间拍。
const SHOT_TIMES: Array[float] = [0.9, 2.0, 3.4, 4.8, 6.2, 7.6]
## 从第几张开始开灯（0 起算）：第一张专拍「关灯长什么样」。
const LAMPS_FROM := 1

var _main: HillGame
var _elapsed := 0.0
## 下一张要拍的是 [constant SHOT_TIMES] 的第几个。
var _next := 0
## 死因（`""` = 还活着）。见 [signal HillCar.crashed]。
var _death := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveData.persist = false
	SaveData.reset_progress()
	SaveData.selected_map = Maps.NIGHT
	_main = load("res://scenes/main.tscn").instantiate() as HillGame
	add_child(_main)
	_main.car.crashed.connect(func(reason: String) -> void: _death = reason)


func _process(delta: float) -> void:
	_elapsed += delta
	# 见文件头：腾空时必须松油门。
	if _main.car.grounded:
		Input.action_press("drive_forward")
	else:
		Input.action_release("drive_forward")
	while _next < SHOT_TIMES.size() and _elapsed >= SHOT_TIMES[_next]:
		var index := _next
		# **先自增再 await**：`_capture` 里会让出控制权，那时 `_process` 还会被
		# 再进来一次，不自增的话同一张图会被拍两遍、而且永远走不到最后一张。
		_next += 1
		# 开灯这件事只在这里做一次（[constant LAMPS_FROM]），不在每帧里按着 ——
		# `toggle_headlights()` 是「按一下换一次」，每帧调等于每帧开关一次。
		if index == LAMPS_FROM:
			_main.car.toggle_headlights()
			print("开灯：headlights_on = %s，油 %s" % [_main.car.headlights_on, _main.car.fuel])
		await _capture("night_%02d" % (index + 1))
		if _next >= SHOT_TIMES.size():
			get_tree().quit()


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("截图失败 %s：%s" % [path, error_string(err)])
		return
	print("已保存 %s（x=%.0f%s%s）" % [
			ProjectSettings.globalize_path(path), _main.car.chassis.global_position.x,
			"，灯开着" if _main.car.headlights_on else "，灯关着",
			("，死了：" + _death) if _death != "" else ""])
