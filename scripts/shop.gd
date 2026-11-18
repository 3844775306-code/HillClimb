extends Control
class_name HillShop
## 道具商店：跑之前花钱买道具，买完直接开跑。
##
## 流程是 **选车 → 车库 → 选图 → 这里 → 跑**。上一站是 [HillMapSelect]，
## 它把选好的图写进存档之后跳到这里；这里选完跳 `scenes/main.tscn`。
##
## ## 为什么是「货架」而不是「点一下就买」
##
## 在商店里勾选**不扣钱**，按「出发」才扣。理由是道具不落盘（见
## [member SaveData.run_items]）：勾一下扣一次钱的话，玩家勾完反悔按 Esc 走人，
## 钱就白花了。所以这里的勾选只是一份**清单**，[method _go] 里一次性结算。
##
## 也因此，勾选的上限由**余额**当场卡住（[method _can_toggle_on]）：买不起的
## 那一格点不动，而不是让玩家选到最后才发现钱不够。「出发」于是不会失败。
##
## 和车库、选图一样全部用 [method CanvasItem.draw_*] 画，字体走 [UiFonts]。
## 卡片是从 [member Items.CATALOG] 上排版出来的 —— 加一件道具只要往那张表里
## 加一行，这里不用动。

const BG_TOP := Color(0.09, 0.12, 0.19)
const BG_BOTTOM := Color(0.04, 0.06, 0.10)
const CARD := Color(0.13, 0.16, 0.23, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.10)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.97, 0.98, 1.0, 0.60)
const GOLD := Color(1.0, 0.84, 0.24)
## 买不起时那一格的描边。
const COLD := Color(0.98, 0.42, 0.36)

const PANEL_W := 960.0
const GAP := 22.0
const CARD_TOP := 208.0
const CARD_H := 296.0
## 卡片里文字左右各自的留白。
const PAD := 22.0
## 「出发」按钮的宽高，以及它离底边多远。
const GO_W := 400.0
const GO_H := 66.0

const MAP_SCENE := "res://scenes/mapselect.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"

var _font: Font
var _cjk := false
var _sel := 0
var _hover := -1
## 这一趟勾中的道具（有序，按勾选先后）。**还没付钱** —— 见文件头。
var _chosen: Array = []


func _ready() -> void:
	_font = UiFonts.load_cjk_font()
	_cjk = _font != null
	if not _cjk:
		_font = get_theme_default_font()
	# 每次进商店都是**空清单**：上一次的勾选没有任何意义，道具早就在上一局里
	# 用掉了（见 [method SaveData.end_run]）。
	_chosen.clear()
	queue_redraw()


func _t(zh: String, en: String) -> String:
	return zh if _cjk else en


# ---------------------------------------------------------------- 布局

func _card_rect(i: int) -> Rect2:
	var n := Items.IDS.size()
	var w := minf(PANEL_W, size.x - 120.0)
	var card_w := (w - GAP * float(n - 1)) / float(n)
	return Rect2(
		(size.x - w) * 0.5 + float(i) * (card_w + GAP),
		CARD_TOP,
		card_w,
		CARD_H
	)


func _card_at(pos: Vector2) -> int:
	for i in range(Items.IDS.size()):
		if _card_rect(i).has_point(pos):
			return i
	return -1


func _go_rect() -> Rect2:
	return Rect2(Vector2((size.x - GO_W) * 0.5, size.y - GO_H - 74.0), Vector2(GO_W, GO_H))


func _total() -> int:
	return Items.cost_of(_chosen)


# ---------------------------------------------------------------- 输入
#
# **不接 InputEventScreenTouch。** 手指按下时引擎会再补一个合成鼠标事件
# （project.godot 的 emulate_mouse_from_touch），两边都接就是一次点按跑两遍 ——
# 原来就是这样：道具卡勾上又取消，手机上永远攒不出一份清单，也就是「买不了装备」。
# 见 tests/tap。

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_on_key((event as InputEventKey).physical_keycode)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_on_pad((event as InputEventJoypadButton).button_index)
	elif event is InputEventMouseMotion:
		var card := _card_at((event as InputEventMouseMotion).position)
		if card != _hover:
			_hover = card
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_click((event as InputEventMouseButton).position)


func _on_key(code: int) -> void:
	match code:
		KEY_LEFT, KEY_A, KEY_UP, KEY_W:
			_move(-1)
		KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
			_move(1)
		# **空格是勾选，回车是出发。** 别把回车也做成勾选 —— 这个界面的主操作
		# 是「出发」，一进来就按回车应该直接开跑（一件不买也是合法开局）。
		KEY_SPACE:
			_toggle(_sel)
		KEY_ENTER, KEY_KP_ENTER:
			_go()
		KEY_ESCAPE:
			get_tree().change_scene_to_file(MAP_SCENE)


func _on_pad(button: int) -> void:
	match button:
		JOY_BUTTON_DPAD_LEFT:
			_move(-1)
		JOY_BUTTON_DPAD_RIGHT:
			_move(1)
		JOY_BUTTON_X:
			_toggle(_sel)
		JOY_BUTTON_A, JOY_BUTTON_START:
			_go()
		JOY_BUTTON_B:
			get_tree().change_scene_to_file(MAP_SCENE)


func _move(delta: int) -> void:
	_sel = wrapi(_sel + delta, 0, Items.IDS.size())
	queue_redraw()


func _on_click(pos: Vector2) -> void:
	if _go_rect().has_point(pos):
		_go()
		return
	var card := _card_at(pos)
	if card >= 0:
		_sel = card
		_toggle(card)


# ---------------------------------------------------------------- 购买

## 再加一件还买得起吗。
##
## 判据是**勾选清单的总价 + 这一件的价**，不是「余额够不够一件」—— 三件一起
## 勾的时候要看合计，否则前三下都点得动、到「出发」才发现钱不够。
func _can_toggle_on(id: String) -> bool:
	return SaveData.total_coins >= _total() + Items.PRICE


func _toggle(i: int) -> void:
	_sel = i
	var id: String = Items.IDS[i]
	if _chosen.has(id):
		_chosen.erase(id)
	elif _can_toggle_on(id):
		_chosen.append(id)
	queue_redraw()


## 结算并开跑。
##
## 钱和道具在 [method SaveData.buy_run_items] 里**一次写盘**落地（和买升级同一
## 条规矩：内存里一起改完，最后只写一次盘），然后立刻换场景。
##
## 一件都没勾就直接走：那是最常见的一趟（不想买、或者没钱），不该逼玩家按一次
## 「确认不买」。
func _go() -> void:
	if not _chosen.is_empty() and not SaveData.buy_run_items(_chosen):
		# 走到这里说明有东西没对上（余额在商店里不会变，勾选时已经卡过一道）。
		# 不换场景，让玩家看见界面停着，比带着一份没付钱的清单开跑强。
		push_warning("道具结算失败，余额 %d，清单 %s" % [SaveData.total_coins, str(_chosen)])
		queue_redraw()
		return
	get_tree().change_scene_to_file(MAIN_SCENE)


# ---------------------------------------------------------------- 绘制

## 画一行字：**放不下就缩号**。规则直接用选图界面那一份
## [method HillMapSelect.fit_size]（选车界面也是借它的）—— 那是个纯函数，量法和
## 画的走同一份代码，三张界面共用一条缩号规则，测试量一遍就都覆盖了。
func _string(at: Vector2, text: String, px: int, color: Color, room: float) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			HillMapSelect.fit_size(_font, text, px, room), color)


func _draw() -> void:
	_draw_background()
	_draw_header()
	for i in range(Items.IDS.size()):
		_draw_card(i)
	_draw_go()
	_draw_footer()


func _draw_background() -> void:
	var w := size.x
	var h := size.y
	draw_polygon(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM])
	)


func _draw_header() -> void:
	draw_string(_font, Vector2(60.0, 82.0), _t("道具商店", "ITEM SHOP"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 46, TEXT)
	draw_string(_font, Vector2(60.0, 114.0),
			_t("每场都要重买，跑完就没了 · 每件每场只能用一次",
				"bought per run and gone when it ends · one use each"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, TEXT_DIM)

	var label := _t("金币总数", "TOTAL COINS")
	var amount := str(SaveData.total_coins)
	draw_string(_font, Vector2(0.0, 74.0), label, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 19, TEXT_DIM)
	# 余额按「付完勾选的这些之后还剩多少」实时显示。**这比只显示余额有用**：
	# 玩家关心的是「我还能不能再勾一件」，而不是一个要自己心算的数字。
	var left := SaveData.total_coins - _total()
	draw_string(_font, Vector2(0.0, 122.0), str(left), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 46,
			GOLD if left == SaveData.total_coins else TEXT)
	if not _chosen.is_empty():
		draw_string(_font, Vector2(0.0, 146.0),
				_t("已选 %d 件 −%d" % [_chosen.size(), _total()], "%d chosen  −%d" % [_chosen.size(), _total()]),
				HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 18, TEXT_DIM)
	var text_w := _font.get_string_size(str(left), HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	draw_circle(Vector2(size.x - 60.0 - text_w - 26.0, 106.0), 13.0, GOLD)
	draw_circle(Vector2(size.x - 60.0 - text_w - 26.0, 106.0), 7.0, Color(1.0, 0.94, 0.66))


func _draw_card(i: int) -> void:
	var r := _card_rect(i)
	var id: String = Items.IDS[i]
	var it := Items.get_item(id)
	var col: Color = it["color"]
	var focused := i == _sel
	var hot := focused or i == _hover
	var taken := _chosen.has(id)
	var room := r.size.x - PAD * 2.0

	# 底色永远带一点这件道具的颜色，勾中之后整体提亮 + 描边用道具色。
	var base: Color = CARD
	if taken:
		base = Color(
			0.13 + col.r * 0.10, 0.16 + col.g * 0.10, 0.23 + col.b * 0.10, 0.98
		)
	draw_rect(r, base)
	draw_rect(r, col if taken else (Color(1.0, 1.0, 1.0, 0.30) if focused else BORDER), false,
			3.0 if taken else 2.0)

	# 顶部一条道具色的色带：这一栏是「这件是什么颜色」，和 HUD 上那一格对得上。
	draw_rect(Rect2(r.position, Vector2(r.size.x, 8.0)), col)

	var at := r.position + Vector2(PAD, 0.0)
	_string(at + Vector2(0.0, 74.0), _t(str(it["zh"]), str(it["en"])), 38,
			TEXT if hot else TEXT.lerp(TEXT_DIM, 0.25), room)
	_string(at + Vector2(0.0, 110.0), _t("%d 金币", "%d COINS") % Items.PRICE, 24, GOLD, room)
	_string(at + Vector2(0.0, 150.0), _t(str(it["zh_note"]), str(it["en_note"])), 17, TEXT_DIM, room)

	# 被动道具单独标一句：防护罩没有按键，不写出来玩家会一直找它的键。
	if Items.action_of(id) == "":
		_string(at + Vector2(0.0, 182.0), _t("被动 · 不用按键", "PASSIVE · NO KEY"), 16, col, room)
	else:
		_string(at + Vector2(0.0, 182.0),
				_t("按键 %s" % str(it["key"]), "KEY %s" % str(it["key"])), 16, TEXT_DIM, room)

	# 底：这一格现在是什么状态。三种写法互斥，各占一行。
	var verdict := ""
	var vcol := TEXT_DIM
	if taken:
		verdict = _t("✓ 已带上", "✓ IN THE CART")
		vcol = col
	elif SaveData.total_coins >= _total() + Items.PRICE:
		verdict = _t("空格 带上", "SPACE to add")
	else:
		verdict = _t("金币不够", "NOT ENOUGH COINS")
		vcol = COLD
	_string(at + Vector2(0.0, r.size.y - 22.0), verdict, 20, vcol, room)


## 底下那个「出发」按钮。按钮上直接写清楚这一趟要花多少 —— 这是最后一次
## 让玩家看清价钱的机会。
func _draw_go() -> void:
	var r := _go_rect()
	var cost := _total()
	var label := _t("出发", "GO")
	if cost > 0:
		label = _t("出发 · 花 %d" % cost, "GO · SPEND %d" % cost)
	elif not _chosen.is_empty():
		label = _t("出发", "GO")

	draw_rect(r, Color(0.20, 0.26, 0.36, 0.98))
	draw_rect(r, Color(0.62, 0.90, 1.0, 0.85), false, 3.0)
	draw_string(_font, r.position + Vector2(0.0, r.size.y * 0.5 + 13.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 34, TEXT)

	# 按钮下面那行小字：买了一件都没勾时明确说一句「这趟不带道具」，
	# 免得玩家以为按钮坏了。
	var sub := _t("不带道具直接跑", "no items this run") if _chosen.is_empty() \
			else _t("付完就开跑，中途退出不退款", "coins are spent as the run starts")
	draw_string(_font, Vector2(0.0, r.position.y + r.size.y + 26.0), sub,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, TEXT_DIM)


func _draw_footer() -> void:
	draw_string(_font, Vector2(60.0, size.y - 22.0),
			_t("← → 选择    空格 带上/取消    回车 出发    Esc 回去换地图",
				"LEFT/RIGHT select    SPACE add    ENTER go    ESC maps"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM)
