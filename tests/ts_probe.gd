extends Node
## 验证 Engine.time_scale 是否改变物理步长。
##
## 如果变，那用 time_scale 加速跑出来的测试数据就不代表真实游戏（time_scale=1）；
## 如果不变（每步恒为 1/60），加速测试就是可信的。

var _steps := 0
var _acc := 0.0
var _first := 0.0


func _physics_process(delta: float) -> void:
	_steps += 1
	_acc += delta
	if _steps == 1:
		_first = delta


func _ready() -> void:
	for ts in [1.0, 8.0]:
		Engine.time_scale = ts
		_steps = 0
		_acc = 0.0
		for i in 60:
			await get_tree().physics_frame
		print("time_scale=%.1f  →  物理帧数 %d  累计 delta=%.4f  首帧 delta=%.5f  等效步长=%.5f" % [
			ts, _steps, _acc, _first, _acc / maxf(1.0, float(_steps)),
		])
	Engine.time_scale = 1.0
	get_tree().quit()
