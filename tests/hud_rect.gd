extends Node
## 打印 HUD 这个 Control 的实际位置和尺寸。
##
## 起因：结束面板的遮罩只盖住了屏幕下半部分，文字也挤成一团，
## 而 hud.gd 里是按 Rect2(Vector2.ZERO, size) 铺遮罩、按 size * 0.5 定中心的 ——
## 所以问题一定出在 size 上。别再猜，直接读。

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	SaveData.persist = false
	SaveData.reset_progress()
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	for i in range(3):
		await get_tree().process_frame
	var hud: HillHud = main.hud
	print("视口尺寸        %s" % str(get_viewport().get_visible_rect().size))
	print("HUD size        %s" % str(hud.size))
	print("HUD position    %s" % str(hud.position))
	print("HUD global_pos  %s" % str(hud.global_position))
	print("HUD anchors     L%.2f T%.2f R%.2f B%.2f" % [
		hud.anchor_left, hud.anchor_top, hud.anchor_right, hud.anchor_bottom,
	])
	print("HUD offsets     L%.2f T%.2f R%.2f B%.2f" % [
		hud.offset_left, hud.offset_top, hud.offset_right, hud.offset_bottom,
	])
	print("父节点          %s（%s）" % [hud.get_parent().name, hud.get_parent().get_class()])
	# 面板上各条文案的基线（对照 04_gameover 的实测位置）
	var c := hud.size * 0.5
	print("=> 遮罩覆盖 y 0..%.0f" % hud.size.y)
	print("=> 标题基线 y=%.0f   本次=%.0f   历史=%.0f   新纪录=%.0f   提示=%.0f" % [
		c.y - 90.0, c.y, c.y + 60.0, c.y + 120.0, c.y + 180.0,
	])
	get_tree().quit()
