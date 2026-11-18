extends Node
## 屋顶图截图：跑真实渲染，沿路连拍八张，用来肉眼检查画得对不对。
##
## 用法（需要真实渲染，会短暂弹出窗口）：
##   godot --path . res://tests/shot_rooftop.tscn
##
## 纯函数的断言在 tests/shapes.gd（瓦铺到哪儿、窗户摆几列、横档多密），但**看不出
## 好不好看** —— 瓦像不像瓦、窗户像不像窗户、钢梯像不像梯子，只有截图能回答。
##
## **为什么是「沿路连拍」而不是「一张房子、一张缝、一张梯子」。** 想把镜头对准某个
## 特征，就得把车摆到那儿去，而这辆车的**刚体不能事后摆位置**：两个 [PinJoint2D]
## 的锚点是进树那一刻按两边刚体的位置算好、交给物理服务器的（见 scripts/game.gd
## 的 `_enter_tree`），事后再挪等于给车装了个偏心的轴，拍出来是一辆抖着的车。
## 所以这里只顺路拍：按固定间隔连拍，八张里总有房子、有缝、有钢梯脚。
## 想凑近看某一处就改 [constant SHOT_TIMES] 里的秒数（着地全油门时均速 500 上下，
## 一秒走五百来像素，第三张之后每张比前一张往前约 550）。
##
## **腾空时必须松油门。** 在 car.gd 里「空中按前进」不是油门而是空中姿态
## （[member HillCar.air_spin] 14 rad/s ≈ 800°/s）：一直按着不放，车一被弹到空中
## 就后空翻、拿车顶落地 —— 这个脚本最早正是这样，后几张全停在 x=1628 的
## 「翻车了！」画面上（见 tests/shapes.gd 的 [method _drive_until]，那里是同一套
## 规矩）。真人腾空时要么松开、要么反着拧。

const OUT_DIR := "res://.shots"

## 每张图的时刻（秒）。第一栋房子从 x = 800 起步（[constant Maps.SHAPE_START_CELL]），
## 所以第一张定在 1.6 s —— 正好把它拍进画面里，再早就是出生直道，什么都没有。
const SHOT_TIMES: Array[float] = [1.6, 2.7, 3.8, 4.9, 6.0, 7.1, 8.2, 9.3]

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
	SaveData.selected_map = Maps.ROOFTOP
	_main = load("res://scenes/main.tscn").instantiate() as HillGame
	add_child(_main)
	# 死因也打出来：「车停在半路」在日志里和「车开得慢」长得一模一样，
	# 不连这个信号就得去翻 png 才知道是翻了车。
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
		await _capture("rooftop_%02d" % (index + 1))
		if _next >= SHOT_TIMES.size():
			get_tree().quit()


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("截图失败 %s：%s" % [path, error_string(err)])
	else:
		print("已保存 %s（x=%.0f%s）" % [
				ProjectSettings.globalize_path(path), _main.car.chassis.global_position.x,
				("，死了：" + _death) if _death != "" else ""])
