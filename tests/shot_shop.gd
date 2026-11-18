extends Node
## 道具商店的截图：几种勾选状态各存一张 png，用来肉眼检查卡片和「出发」按钮。
##
## 用法（需要真实渲染，会短暂弹出窗口）：
##   godot --path . res://tests/shot_shop.tscn
##
## 无头模式也能跑，但**不要**拿无头下的图判断版面 —— 无头视口是 1280×1280，
## 卡片会被拉伸（见 README 的坑 #7）。
##
## 全程只改内存里的存档（`persist = false`），**不按「出发」** —— 那一按会
## `change_scene_to_file()`，截图脚本当场就没了。

const OUT_DIR := "res://.shots"
const SHOP := preload("res://scenes/shop.tscn")

var _s: HillShop


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveData.persist = false
	SaveData.reset_progress()

	_s = SHOP.instantiate()
	add_child(_s)
	for i in range(3):
		await get_tree().process_frame

	var view := get_viewport().get_visible_rect().size
	print("视口 %s   界面 size %s   道具 %d 件" % [
		str(view), str(_s.size), Items.IDS.size()])

	# 一张「买得起、什么都没勾」：余额那行是原色，三张卡都写着「空格 带上」。
	await _shot("01_empty", Items.PRICE * 3)

	# 一张「勾了一件」：卡片提亮、按钮上写出要花多少。
	await _shot("02_one", Items.PRICE * 3, [Items.NITRO])

	# 一张「三件全勾」：余额归零，按钮写「出发 · 花 150」。
	await _shot("03_all", Items.PRICE * 3, Items.IDS)

	# 一张「钱不够」：卡片描边转红、底下那行写「金币不够」。
	# 这是最容易画坏的一屏（三种状态的字要同时放得下），所以单独截一张。
	await _shot("04_broke", Items.PRICE - 10)

	# 一张「余额差一点点」：勾了一件就买不起第二件，能看出余额是**实时的**。
	await _shot("05_tight", Items.PRICE, [Items.NITRO])

	get_tree().quit()


func _shot(shot_name: String, coins: int, chosen: Array = []) -> void:
	SaveData.total_coins = coins
	_s._chosen = chosen.duplicate()
	_s._sel = 0
	_s._hover = -1
	_s.queue_redraw()
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("截图失败 %s：%s" % [path, error_string(err)])
	else:
		print("已保存 %-10s 余额 %3d  已选 %d 件  要花 %d" % [
			shot_name, coins, chosen.size(), _s._total()])
