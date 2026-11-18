extends Node
## 车库面板截图：把几种典型状态各存一张 png，用来肉眼检查版面。
##
## 用法（需要真实渲染，会短暂弹出窗口）：
##   godot --path . res://tests/shot_garage.tscn
##
## 无头模式也能跑，但**不要**拿无头下的图判断版面 —— 无头视口是 1280×1280，
## 面板会被拉伸（见 README 的坑 #7）。

const OUT_DIR := "res://.shots"
const GARAGE := preload("res://scenes/garage.tscn")

var _g: HillGarage


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveData.persist = false
	SaveData.reset_progress()

	_g = GARAGE.instantiate()
	add_child(_g)
	for i in range(3):
		await get_tree().process_frame

	var view := get_viewport().get_visible_rect().size
	print("视口 %s   面板 size %s" % [str(view), str(_g.size)])

	# 一分钱没有：四行全是「金币不足」，药丸是灰的
	await _shot("01_broke", 0, {}, 0)

	# 有点钱：能买得起的显示金色价格，买不起的是灰的
	await _shot("02_mixed", 340, {"engine": 1, "fuel": 2}, 1)

	# 引擎快满：看页脚推重比变色（进了金色区间）
	await _shot("03_engine", 0, {"engine": Upgrades.MAX_LEVEL - 2}, 0)

	# 全满：四个绿色「满级」（十格方块全亮），页脚推重比到底
	await _shot("04_maxed", 9999, {
		"engine": Upgrades.MAX_LEVEL, "speed": Upgrades.MAX_LEVEL,
		"fuel": Upgrades.MAX_LEVEL, "agility": Upgrades.MAX_LEVEL,
	}, 3)

	print("推重比（引擎满级）= %.3f   翘头线 %.2f" % [
		Upgrades.thrust_ratio(Upgrades.MAX_LEVEL), Upgrades.WHEELIE_LINE,
	])
	get_tree().quit()


func _shot(shot_name: String, coins: int, levels: Dictionary, sel: int) -> void:
	SaveData.total_coins = coins
	# 改的是**当前选中那辆车**的表（升级按车分开），截图上方的「◆ 车名」就是它。
	var lv := SaveData.current_levels()
	for id in Upgrades.IDS:
		lv[id] = clampi(int(levels.get(id, 0)), 0, Upgrades.MAX_LEVEL)
	_g._sel = sel
	_g._hover = -1
	_g._hover_start = false
	_g.queue_redraw()
	for i in range(3):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("截图失败 %s：%s" % [path, error_string(err)])
	else:
		print("已保存 %s" % shot_name)
