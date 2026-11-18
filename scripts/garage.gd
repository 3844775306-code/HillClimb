extends Control
class_name HillGarage
## 局前车库：花累计金币给车升级。
##
## 流程是 **选车 → 车库 → 选图 → 开跑**：车库改的是「刚选中那辆车」，所以它排在
## 选车后面，页眉那个「◆ 车名」标签就是这一页属于谁。改完点「选地图」往下走。
##
## 它本身不加载车辆场景 —— 面板上的数字全部由 [Upgrades] 按等级换算，没有物理在跑。
##
## 和 HUD 一样全部用 [method CanvasItem.draw_*] 画，字体走 [UiFonts]。

const BG_TOP := Color(0.09, 0.12, 0.19)
const BG_BOTTOM := Color(0.04, 0.06, 0.10)
const CARD := Color(0.13, 0.16, 0.23, 0.92)
const CARD_SEL := Color(0.19, 0.24, 0.34, 0.98)
const BORDER := Color(1.0, 1.0, 1.0, 0.10)
const BORDER_SEL := Color(0.62, 0.90, 1.0, 0.85)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.97, 0.98, 1.0, 0.60)
const GOLD := Color(1.0, 0.84, 0.24)
const SKY := Color(0.62, 0.90, 1.0)
const GREEN := Color(0.36, 0.88, 0.48)
const RED := Color(0.96, 0.42, 0.36)

## 点「选地图」往下走。往回一步是选车界面（V 键）—— 车库改的是**当前选中那辆车**，
## 想改别的车得先换车，所以这条回头路是必需的，不是可有可无的。
const MAP_SCENE := "res://scenes/mapselect.tscn"
const VEHICLE_SCENE := "res://scenes/vehicleselect.tscn"

const PANEL_W := 1160.0
const ROW_H := 88.0
const ROW_GAP := 10.0
const ROWS_TOP := 150.0
const PILL_W := 184.0
const PILL_H := 48.0

## 等级方块区的总宽，以及「当前效果」文字距方块区起点的偏移。
##
## 方块尺寸是从 [constant PIPS_ROOM] **反推**出来的（见 [method pip_size]），
## 不是写死的 26px —— 升级上限从 4 级改成 10 级时，写死的方块会把这一行撑到
## 350px 宽，直接压到右边的「当前效果」上。测试量版面时也读这两个常量，
## 免得两边各写一个数字、改级数时对不上。
const PIPS_ROOM := 240.0
const PIPS_GAP := 6.0
const EFFECT_OFFSET := 264.0


## 单块等级方块的边长。10 级要塞进 [constant PIPS_ROOM]，所以由它反推。
func pip_size() -> float:
	return (PIPS_ROOM - PIPS_GAP * float(Upgrades.MAX_LEVEL - 1)) / float(Upgrades.MAX_LEVEL)

var _font: Font
var _cjk := false
var _sel := 0
var _hover := -1
var _hover_start := false
var _flash := 0.0        ## 买不起时点一下，让那一行红一下
var _flash_row := -1


func _ready() -> void:
	_font = UiFonts.load_cjk_font()
	_cjk = _font != null
	if not _cjk:
		_font = get_theme_default_font()
	queue_redraw()


func _t(zh: String, en: String) -> String:
	return zh if _cjk else en


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()


# ---------------------------------------------------------------- 布局

func _row_rect(i: int) -> Rect2:
	var w := minf(PANEL_W, size.x - 120.0)
	return Rect2(
		(size.x - w) * 0.5,
		ROWS_TOP + float(i) * (ROW_H + ROW_GAP),
		w,
		ROW_H
	)


func _start_rect() -> Rect2:
	var w := 340.0
	var y := ROWS_TOP + float(Upgrades.IDS.size()) * (ROW_H + ROW_GAP) + 28.0
	return Rect2((size.x - w) * 0.5, y, w, 62.0)


func _pill_rect(row: Rect2) -> Rect2:
	return Rect2(row.position.x + row.size.x - PILL_W - 30.0, row.position.y + 20.0, PILL_W, PILL_H)


# ---------------------------------------------------------------- 输入
#
# **不接 InputEventScreenTouch。** 手指按下时引擎会再补一个合成鼠标事件
# （project.godot 的 emulate_mouse_from_touch），两边都接就是一次点按跑两遍 ——
# 原来就是这样：碰一下改装行直接把两级都买了。见 tests/tap。

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_on_key((event as InputEventKey).physical_keycode)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_on_pad((event as InputEventJoypadButton).button_index)
	elif event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).position
		var row := _row_at(pos)
		var on_start := _start_rect().has_point(pos)
		if row != _hover or on_start != _hover_start:
			_hover = row
			_hover_start = on_start
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_click((event as InputEventMouseButton).position)


func _on_key(code: int) -> void:
	match code:
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_RIGHT, KEY_D, KEY_SPACE:
			_buy(_sel)
		KEY_ENTER, KEY_KP_ENTER:
			_start()
		KEY_V:
			_change_vehicle()


func _on_pad(button: int) -> void:
	match button:
		JOY_BUTTON_DPAD_UP:
			_move(-1)
		JOY_BUTTON_DPAD_DOWN:
			_move(1)
		JOY_BUTTON_A:
			_buy(_sel)
		JOY_BUTTON_START:
			_start()
		JOY_BUTTON_X:
			_change_vehicle()


func _row_at(pos: Vector2) -> int:
	for i in range(Upgrades.IDS.size()):
		if _row_rect(i).has_point(pos):
			return i
	return -1


func _on_click(pos: Vector2) -> void:
	if _start_rect().has_point(pos):
		_start()
		return
	var row := _row_at(pos)
	if row >= 0:
		_sel = row
		_buy(row)
	else:
		queue_redraw()


func _move(delta: int) -> void:
	_sel = wrapi(_sel + delta, 0, Upgrades.IDS.size())
	queue_redraw()


func _buy(index: int) -> void:
	var id: String = Upgrades.IDS[index]
	if SaveData.buy_upgrade(id):
		_flash = 0.0
	else:
		# 买不起或已满级：让那一行红一下，不然点了没反应像是坏了
		_flash = 0.35
		_flash_row = index
	queue_redraw()


## 往下走一步：去选图。车在**进这一页之前**就选好了（见 [constant VEHICLE_SCENE]），
## 所以这里只剩「去哪」这一步。
func _start() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


## 往回一步：换车。改完再回车库，这一页的数字整套换成新车的。
##
## 不是「可有可无的回头路」：升级是按车分开的（[method SaveData.levels_of]），
## 玩家想给另一辆车花钱，只能先换车。
func _change_vehicle() -> void:
	get_tree().change_scene_to_file(VEHICLE_SCENE)


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_draw_background()
	_draw_header()
	for i in range(Upgrades.IDS.size()):
		_draw_row(i)
	_draw_start_button()
	_draw_footer()


func _draw_background() -> void:
	var w := size.x
	var h := size.y
	# draw_polygon 支持逐顶点颜色，四个点就能拉出一条竖直渐变
	draw_polygon(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM])
	)


func _draw_header() -> void:
	var title := _t("车库", "GARAGE")
	draw_string(_font, Vector2(60.0, 82.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 46, TEXT)
	# 标题右边挂上当前选的车：升级等级是所有车共享的，可「我待会儿开的是哪辆」
	# 在这个界面里看不出来 —— 点了开始游戏才发现开的是巴士就太晚了。
	var v := Vehicles.get_vehicle(SaveData.selected_vehicle)
	var tag := "◆ " + _t(v["zh"], v["en"])
	var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	draw_string(_font, Vector2(60.0 + tw + 20.0, 82.0), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, GOLD)
	draw_string(_font, Vector2(60.0, 114.0),
			_t("升级只长在这辆车上，换车要重新练 · 升完点「选地图」",
					"upgrades are per car · spend coins, then pick a map"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, TEXT_DIM)

	# 右上角：金币总数
	var label := _t("金币总数", "TOTAL COINS")
	var amount := str(SaveData.total_coins)
	draw_string(_font, Vector2(0.0, 74.0), label,
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 19, TEXT_DIM)
	draw_string(_font, Vector2(0.0, 122.0), amount,
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 46, GOLD)
	# 金币图标贴在数字左边，宽度靠估算 —— 没有 reliable 的 measure 接口
	var text_w := _font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	var dot := Vector2(size.x - 60.0 - text_w - 26.0, 106.0)
	draw_circle(dot, 13.0, GOLD)
	draw_circle(dot, 7.0, Color(1.0, 0.94, 0.66))


func _draw_row(i: int) -> void:
	var row := _row_rect(i)
	var id: String = Upgrades.IDS[i]
	var track: Dictionary = Upgrades.TRACKS[id]
	var level := SaveData.level_of(id)
	var maxed := level >= Upgrades.MAX_LEVEL
	var price := SaveData.upgrade_cost(id)
	var afford := SaveData.can_afford(id)

	var focused := i == _sel
	var hot := focused or i == _hover
	if _flash > 0.0 and _flash_row == i:
		hot = true

	var bg := CARD_SEL if focused else CARD
	if _flash > 0.0 and _flash_row == i:
		bg = bg.lerp(RED, 0.35 * (_flash / 0.35))
	draw_rect(row, bg)

	var border := BORDER_SEL if focused else BORDER
	if _flash > 0.0 and _flash_row == i:
		border = RED
	draw_rect(row, border, false, 2.0)

	# 左：名称 + 说明
	draw_string(_font, row.position + Vector2(34.0, 40.0),
			_t(track["zh"], track["en"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 29, TEXT if hot else TEXT.lerp(TEXT_DIM, 0.25))
	draw_string(_font, row.position + Vector2(34.0, 70.0),
			_t(track["zh_note"], track["en_note"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_DIM)

	# 中：等级方块。边长由 pip_size() 从 PIPS_ROOM 反推，方块大小跟着级数变。
	var sq := pip_size()
	var gap := PIPS_GAP
	var sq_at := row.position + Vector2(row.size.x * 0.40, 44.0 - sq * 0.5)
	for n in range(Upgrades.MAX_LEVEL):
		var r := Rect2(sq_at + Vector2(float(n) * (sq + gap), 0.0), Vector2(sq, sq))
		if n < level:
			draw_rect(r, GOLD)
		else:
			draw_rect(r, Color(1.0, 1.0, 1.0, 0.07))
			draw_rect(r, Color(1.0, 1.0, 1.0, 0.18), false, 1.0)

	# 中右：当前效果
	var mult := Upgrades.display_mult(id, level)
	var unit := _t(track["zh_unit"], track["en_unit"])
	draw_string(_font, row.position + Vector2(row.size.x * 0.40 + EFFECT_OFFSET, 55.0),
			"%s ×%.2f" % [unit, mult],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, SKY if level > 0 else TEXT_DIM)

	# 右：价格 / 满级
	var pill := _pill_rect(row)
	var pill_color := GOLD if afford else Color(1.0, 1.0, 1.0, 0.22)
	var pill_text := str(price)
	if maxed:
		pill_color = GREEN
		pill_text = _t("满级", "MAXED")

	if maxed:
		draw_rect(pill, Color(0.36, 0.88, 0.48, 0.16))
		draw_rect(pill, pill_color, false, 2.0)
	else:
		draw_rect(pill, Color(0.0, 0.0, 0.0, 0.22))
		draw_rect(pill, pill_color, false, 2.0)

	var text_size := _font.get_string_size(pill_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	var text_pos := Vector2(
		pill.position.x + (PILL_W - text_size.x) * 0.5,
		pill.position.y + PILL_H * 0.5 + 9.0
	)
	draw_string(_font, text_pos, pill_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, pill_color)

	if not maxed:
		# 价格左边画个小金币，和右上角那个呼应
		draw_circle(Vector2(text_pos.x - 16.0, text_pos.y - 9.0), 8.0, pill_color)
		if not afford:
			draw_string(_font, row.position + Vector2(row.size.x - PILL_W - 30.0, 84.0),
					_t("金币不足", "NOT ENOUGH"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, RED)


func _draw_start_button() -> void:
	var r := _start_rect()
	# 只看鼠标悬停：空格键是「升级」，拿它点亮开始按钮会让人以为空格能开局
	var hot := _hover_start
	draw_rect(r, Color(0.26, 0.62, 0.36) if hot else Color(0.20, 0.48, 0.29))
	draw_rect(r, GREEN if hot else Color(0.36, 0.88, 0.48, 0.55), false, 2.0)
	var label := _t("选地图  ▶", "PICK MAP  ▶")
	var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
	draw_string(_font, Vector2(r.position.x + (r.size.x - ts.x) * 0.5, r.position.y + 41.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, TEXT)


func _draw_footer() -> void:
	var y := size.y - 26.0
	draw_string(_font, Vector2(60.0, y),
			_t("↑↓ 选择   →/空格 升级   V 换车   回车 选地图   也可以直接点",
				"UP/DOWN  RIGHT/SPACE upgrade   V vehicle   ENTER map"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM)

	# 推重比：让「引擎」的副作用可见。超过 1.45 倍就会后仰翻车。
	# 是**当前选中那辆车**的余量：引擎等级是按车分开的，基数也各不相同，
	# 同一级引擎在巴士上离翘头线还远，在摩托上可能已经压线了。
	# 页眉那个「◆ 车名」标签就是在说这一页的数字属于哪辆车。
	var ratio := Upgrades.thrust_ratio(SaveData.level_of("engine"), SaveData.selected_vehicle)
	var color := GREEN
	if ratio >= Upgrades.WHEELIE_LINE:
		color = RED
	elif ratio > Upgrades.WHEELIE_LINE * 0.9:
		color = GOLD
	var text := _t("推重比 %.2f  /  %.2f 翘头", "POWER/WEIGHT %.2f  /  %.2f wheelie") % [
		ratio, Upgrades.WHEELIE_LINE,
	]
	draw_string(_font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 18, color)
