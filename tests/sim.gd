extends Node
## 无头冒烟测试：加载主场景，按住油门跑一段时间，打印地形与车辆状态。
##
## 用法：
##   godot --headless --path . res://tests/sim.tscn
## 目的是在没有画面的情况下验证物理跑得通 —— 车真的能被轮子推着往前走。

@export var duration := 15.0
## 每多少秒打一行状态。
@export var report_interval := 2.0

var _main: HillGame
var _elapsed := 0.0
var _next_report := 0.0


func _ready() -> void:
	SaveData.persist = false   # 别让测试的里程和金币写进玩家存档
	SaveData.reset_progress()  # 也别让玩家练出来的升级影响冒烟测试的车
	_main = load("res://scenes/main.tscn").instantiate() as HillGame
	add_child(_main)
	_probe_terrain()
	# 模拟一直按住油门。Input.action_press 不会产生事件，所以不会触发重开。
	Input.action_press("drive_forward")
	print("t=0.0  x=%.0f  油=100%%" % _main.car.chassis.global_position.x)
	_next_report = report_interval


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		_finish()
		return
	if _elapsed >= _next_report:
		_next_report += report_interval
		_report()


func _probe_terrain() -> void:
	var terrain := _main.terrain
	var min_y := INF
	var max_y := -INF
	var max_slope := 0.0
	var prev := terrain.height_at(0.0)
	var x := 0.0
	while x <= 30000.0:
		var y := terrain.height_at(x)
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
		if x > 0.0:
			max_slope = maxf(max_slope, absf(y - prev) / 20.0)
		prev = y
		x += 20.0
	print(
		"[地形] 30km 内地面 y ∈ [%.0f, %.0f]，最陡坡度 %.1f°"
		% [min_y, max_y, rad_to_deg(atan(max_slope))]
	)


func _report() -> void:
	var car := _main.car
	print(
		"t=%.1f  x=%.0f  y=%.0f  速度=%.0f  轮速=%.0f  油=%.0f%%  存活=%s"
		% [
			_elapsed,
			car.chassis.global_position.x,
			car.chassis.global_position.y,
			car.chassis.linear_velocity.length(),
			car.rear_wheel.angular_velocity,
			car.fuel / car.fuel_max * 100.0,
			car.alive,
		]
	)


func _finish() -> void:
	var car := _main.car
	print(
		"[结果] 里程=%d m  金币=%d  存活=%s  最终 x=%.0f"
		% [_main.distance_meters(), _main.coins, car.alive, car.chassis.global_position.x]
	)
	get_tree().quit()
