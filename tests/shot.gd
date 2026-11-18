extends Node
## 截图测试：跑一遍真实渲染流程，把画面存成 png，用来肉眼检查视觉效果。
##
## 用法（需要真实渲染，会短暂弹出窗口）：
##   godot --path . res://tests/shot.tscn

const OUT_DIR := "res://.shots"

var _main: HillGame
var _elapsed := 0.0
var _shots_taken := 0

## 第几秒截图，以及截图前要做的动作。
var _schedule := []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# 别让这次演示写进玩家存档；同时预置一份「历史战绩」，
	# 前几张图里顶栏的最远记录/金币总数才是非零的，看得出这两列接上了存档。
	SaveData.persist = false
	# 先清干净（含升级等级）：车库里攒的升级会让截图里的车和默认参数对不上，
	# 之后要对比 HUD 数字时也容易被干扰。
	SaveData.reset_progress()
	SaveData.best_distance = 1234
	SaveData.total_coins = 88
	_main = load("res://scenes/main.tscn").instantiate() as HillGame
	add_child(_main)
	Input.action_press("drive_forward")
	_schedule = [
		{"t": 1.0, "name": "01_start"},
		{"t": 5.0, "name": "02_hills"},
		{"t": 9.0, "name": "03_far"},
		# 把纪录压到 0，让这一局必定破纪录，好把「新纪录！」那条也截出来
		{"t": 9.5, "name": "", "set_best": 0},
		{"t": 10.0, "name": "04_gameover", "kill": true},
	]


func _process(delta: float) -> void:
	_elapsed += delta
	while _shots_taken < _schedule.size() and _elapsed >= float(_schedule[_shots_taken]["t"]):
		var entry: Dictionary = _schedule[_shots_taken]
		_shots_taken += 1
		if entry.has("set_best"):
			SaveData.best_distance = int(entry["set_best"])
		var name := String(entry["name"])
		if name.is_empty():
			continue
		if entry.get("kill", false):
			# 强制触发「没油了」的结束面板。
			#
			# 抽干油之后必须等够帧数才能截图：车要到下一个物理帧才在
			# _burn_fuel 里判定死亡，HUD 的 queue_redraw() 还要再等一帧才画。
			# 直接 await frame_post_draw 会拿到面板出现**之前**的那一帧 ——
			# 截出来是一张普通游戏画面，而地形和云的颜色又足够像文字，
			# 会让「面板画对了没有」的检查给出错误的通过。
			_main.car.fuel = 0.0
			for i in range(3):
				await get_tree().physics_frame
			for i in range(2):
				await get_tree().process_frame
			_report_hud_rect()
			print("  game_over = %s" % str(_main.game_over))
		await _capture(name)
		if _shots_taken >= _schedule.size():
			get_tree().quit()


## HUD 是按自己的 size 来铺遮罩、定中心的，而截图是 1280x720 —— 把两者都打出来，
## 免得面板排版和画面尺寸对不上时靠猜。
func _report_hud_rect() -> void:
	var hud: HillHud = _main.hud
	var view := get_viewport().get_visible_rect().size
	print("  视口 %s   HUD size %s   HUD pos %s" % [str(view), str(hud.size), str(hud.position)])
	var c := hud.size * 0.5
	print("  面板基线：标题 %.0f  本次 %.0f  历史 %.0f  新纪录 %.0f  提示 %.0f" % [
		c.y - 90.0, c.y, c.y + 60.0, c.y + 120.0, c.y + 180.0,
	])


func _capture(shot_name: String) -> void:
	# 等这一帧画完，否则拿到的是上一帧、甚至是空白贴图。
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("截图失败 %s：%s" % [path, error_string(err)])
	else:
		print("已保存 %s" % ProjectSettings.globalize_path(path))
