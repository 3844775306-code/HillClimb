extends Control
class_name HillTouchControls
## 手机版的操作层：左下刹车踏板、右下油门踏板、右上角暂停键，以及暂停菜单。
##
## ## 为什么不画进 HUD
##
## [HillHud] 是**只画不读输入**的（它 `mouse_filter` 是 IGNORE，结束面板那句「点一下
## 再跑一局」故意留给 game.gd 的 `_unhandled_input` 去收）。这一层反过来：**只读输入，
## 而且要在 `_input` 阶段抢在 GUI 前面把事件吃掉** —— 手指按在踏板上时，那一下不能
## 再穿透到下面的界面去。两个关注点分开，谁也不碍谁。
##
## ## 踏板喂的是**动作**，不是直接拧轮子
##
## 按下去就 [`Input.action_press`]`("drive_forward")`，抬起来 `action_release`。
## 好处是**车那边一行都不用改**（car.gd 读的还是 `Input.is_action_pressed`），
## 键盘、手柄、触屏三种输入在车看来是同一条路，不会出现「触屏开车手感不一样」。
## 登月车的「双键起飞」也是白捡的：车只会看到两个动作同时按下。
##
## ## 多指：按 `index` 一根一根记账
##
## 不是「这个踏板上有没有人按着」这种布尔量，因为两件事都会出错：
##
##  · **两根手指按同一个踏板**时，先抬起来的那根不能把动作放掉。所以每个区域还要
##    数着有几根手指（[member _hold]），归零才真的 `action_release`。
##  · 手指**从一个踏板滑到另一个踏板**（横着扫过屏幕）要能换过去，
##    而不是一直踩着最开始那个。
##
## ## 动作是全局状态，必须有人收尾
##
## [`Input.action_press`] 不像按键那样松开就没了 —— 它是全局的、会一直按着。
## 局结束时、切场景时、切到后台时如果还有指头按着，油门就一直是踩死的：
## 下一局一开局车自己就窜出去。所以 [method release_all] 挂了四个地方：
## 车翻了（[method set_locked]）、指头抬了、退出场景（[method _exit_tree]）、
## 应用切到后台（[constant NOTIFICATION_APPLICATION_FOCUS_OUT]）。
##
## ## 只在触屏设备上存在
##
## [method is_touch_device] 为假时整层 `visible = false` 且**完全不处理输入**，
## 桌面版行为和加这一层之前一模一样。判定见 [method wants_touch_controls]。

## 踏板边长（正方形，像素）。
##
## 180 是「横屏下一只大拇指按得住、又不会挡住赛道」的折中。屏幕宽 1280 时
## 两个踏板加起来占 408 像素，中间还剩 872 像素给地形。
const PEDAL := 180.0
## 踏板离屏幕底边、侧边的距离。
const PEDAL_MARGIN := 24.0
## 暂停键边长、离右边缘的距离。
const PAUSE_BTN := 58.0
const PAUSE_MARGIN := 20.0
## 暂停键离**顶边**的距离。必须在 HUD 那行地图名下面 —— 地图名基线 y=50、字号 28，
## 占 22～58；这里从 74 起，中间留 16 像素。
const PAUSE_BTN_Y := 74.0
## 暂停菜单三个按钮的尺寸和间距。
const MENU_W := 380.0
const MENU_H := 78.0
const MENU_GAP := 20.0

## 区域 → 输入动作。**只有这两个区域是「按住」语义**，其余（暂停键、菜单按钮）
## 都是「点一下」，见 [method _apply]。
const ZONE_ACTION := {
	"brake": "drive_back",
	"gas": "drive_forward",
}
## 左边刹车、右边油门。刹车是仪表盘那支指针的红，油门是金币的金 —— 和全局配色一致。
const BRAKE_COLOR := Color(1.0, 0.42, 0.32)
const GAS_COLOR := Color(1.0, 0.84, 0.24)
const FILL := Color(0.07, 0.09, 0.13, 0.30)
const FILL_HELD := Color(0.07, 0.09, 0.13, 0.62)
const EDGE := Color(1.0, 1.0, 1.0, 0.30)
const LABEL := Color(0.97, 0.98, 1.0, 0.88)
const GLYPH_SIZE := 54
const LABEL_SIZE := 24
const TITLE_SIZE := 40
const BTN_TEXT_SIZE := 30
## 暂停菜单的压暗层和按钮底色。
const DIM := Color(0.03, 0.05, 0.09, 0.72)
const PANEL := Color(0.07, 0.09, 0.13, 0.92)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.26)

## 暂停菜单里按了这个之后要干什么，由 [signal pause_action] 交给 [HillGame]。
## 「继续」不在这里：它在这层内部就办完了（[method set_paused]）。
const ACTION_RESTART := "restart"
const ACTION_MAP := "map"

## 菜单里问 [HillGame] 要做什么。**这层不认识那几个场景的路径**，
## 由 game.gd 接住 —— 那三个路径本来就归它管（见 game.gd 顶上那三个常量）。
signal pause_action(id: String)

## 整层的逻辑开关。**和 [member visible] 不是一回事**：`_input` 是不过可见性的，
## 隐藏着的节点照样收得到输入事件，所以判定必须靠这个布尔量。
var enabled := false
## 局结束时锁住：踏板收起来（不画、不响应），把点击让给结束面板。
var locked := false

## 每根按下去的手指 → 它现在管着哪个区域。**记的是全部手指**，不只是踩在踏板上的，
## 这样「按下 → 滑出去 → 又滑回来」还能重新踩上（[method _drag]）。
var _down := {}
## 区域 → 有几根手指按着。归零才真的放开动作。
var _hold := {}
var _paused := false
var _font: Font
var _cjk := false


## 这台设备该不该显示触屏操作层。
##
## **拆成两个函数是为了能测**：真机判定（`OS.has_feature`）在 PC 上永远是 false，
## 合成一个函数的话，「有触摸屏的 PC」这条分支就永远跑不到。
static func wants_touch_controls(is_mobile: bool, has_touchscreen: bool) -> bool:
	return is_mobile or has_touchscreen


static func is_touch_device() -> bool:
	return wants_touch_controls(OS.has_feature("mobile"), DisplayServer.is_touchscreen_available())


## 踏板区在屏幕上占掉的高度（含底边留白）。HUD 和仪表盘拿它把自己的东西往上挪 ——
## **这个数只有这一份**，踏板改大小的时候它们跟着动，不会有一处忘了改而对撞。
static func bottom_inset() -> float:
	return PEDAL + PEDAL_MARGIN * 2.0


## 字体由 [HillHud] 传进来，不在这里自己 [`UiFonts.load_cjk_font`]：
## 那个函数要读几 MB 的系统字体文件，一局里加载两遍纯属浪费。
func setup(font: Font, cjk: bool, touch: bool) -> void:
	_font = font
	_cjk = cjk
	# 整层铺满视口：所有坐标都是从 `size` 现算的，屏幕一转或比例一变自己就跟着挪。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 这一层自己读 `_input`，不需要 GUI 阶段的命中测试；而且它整块都是装饰，
	# 设成 IGNORE 免得挡住下面的界面。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_enabled(touch)


func _ready() -> void:
	# 暂停时这一层还得收得到输入、还得画那三个按钮，所以不能跟着暂停。
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if not value:
		release_all()
	queue_redraw()


## 局结束了：松开一切、收起踏板。结束面板接管点击。
func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	release_all()
	queue_redraw()


func is_paused() -> bool:
	return _paused


## 暂停/继续。**切换场景前必须回到 false**（见 [method _request]）。
func set_paused(value: bool) -> void:
	if _paused == value:
		return
	_paused = value
	# 菜单弹出来的那一刻，脚下的油门必须先松开 —— 否则「暂停」这个动作本身
	# 会让车在暂停期间一直踩着油门（动作是全局的，暂停拦不住它）。
	release_all()
	get_tree().paused = value
	queue_redraw()


## 把动作全部放开、指头账本清空。四个收尾点都调它。
func release_all() -> void:
	for zone in _hold.keys():
		if ZONE_ACTION.has(zone):
			Input.action_release(String(ZONE_ACTION[zone]))
	_hold.clear()
	_down.clear()
	queue_redraw()


func _notification(what: int) -> void:
	# 切到后台（来电、Home 键、切窗口）：指头不会再有抬起事件了，
	# 不收尾的话回来时油门是踩死的。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()


func _exit_tree() -> void:
	release_all()
	# **暂停是挂在 SceneTree 上的全局状态**，这一层只是它的开关。带着 true 被释放
	# （切场景 / 重开一局），新场景一进去就是冻住的，而且再也没人能解开它。
	if _paused:
		_paused = false
		get_tree().paused = false


# ---------------------------------------------------------------- 布局（都是纯函数）


func pedal_rects() -> Dictionary:
	return {
		"brake": Rect2(PEDAL_MARGIN, size.y - PEDAL_MARGIN - PEDAL, PEDAL, PEDAL),
		"gas": Rect2(size.x - PEDAL_MARGIN - PEDAL, size.y - PEDAL_MARGIN - PEDAL, PEDAL, PEDAL),
	}


func pause_rect() -> Rect2:
	return Rect2(size.x - PAUSE_MARGIN - PAUSE_BTN, PAUSE_BTN_Y, PAUSE_BTN, PAUSE_BTN)


## 暂停菜单三个按钮的位置，从上到下：继续 / 重开 / 返回选图。
##
## 整个菜单**竖直居中**：横屏手机的高度只有 720，菜单占 3×78+2×20 = 274，
## 居中之后上下各留 223，离顶栏和底边都够远。
func menu_rects() -> Array:
	var ids := ["resume", ACTION_RESTART, ACTION_MAP]
	var total := float(ids.size()) * MENU_H + float(ids.size() - 1) * MENU_GAP
	var top := (size.y - total) * 0.5
	var x := (size.x - MENU_W) * 0.5
	var out := []
	for i in ids.size():
		out.append({"id": ids[i], "rect": Rect2(x, top + float(i) * (MENU_H + MENU_GAP), MENU_W, MENU_H)})
	return out


## 这个位置上是什么。**所有命中测试都走这一个入口**（没有第二处坐标判断），
## 于是「暂停时不响应踏板」「锁住时什么都不响应」这两条只需要在这里写一遍。
func zone_at(pos: Vector2) -> String:
	if _paused:
		for item in menu_rects():
			if (item["rect"] as Rect2).has_point(pos):
				return String(item["id"])
		return ""
	if locked:
		return ""
	if pause_rect().has_point(pos):
		return "pause"
	var rects := pedal_rects()
	for zone in ZONE_ACTION.keys():
		if (rects[zone] as Rect2).has_point(pos):
			return String(zone)
	return ""


# ---------------------------------------------------------------------------- 输入


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_drag(drag.index, drag.position)


func _press(index: int, pos: Vector2) -> void:
	# index 为负是鼠标合成的触摸，跳过：这一层只认真的手指。
	if index < 0:
		return
	var zone := zone_at(pos)
	# **按在空白处也要记账**（记成空区域）：手指接着滑到踏板上时，
	# `_drag` 得知道这根指头是「已经按下的」，而不是凭空冒出来的。
	_down[index] = zone
	if zone == "":
		return
	_apply(zone)
	get_viewport().set_input_as_handled()
	queue_redraw()


func _release(index: int) -> void:
	if not _down.has(index):
		return
	var zone: String = _down[index]
	_down.erase(index)
	if zone == "":
		return
	_drop(zone)
	get_viewport().set_input_as_handled()
	queue_redraw()


func _drag(index: int, pos: Vector2) -> void:
	if not _down.has(index):
		return
	var was: String = _down[index]
	var zone := zone_at(pos)
	if zone == was:
		return
	# **只有踏板参与「拖过去就换」。** 暂停键和菜单按钮是「点一下」语义：
	# 按下暂停的那根手指只要稍微挪一下就被判成点了「重开」，那就没法用了。
	if not ZONE_ACTION.has(was) and not ZONE_ACTION.has(zone):
		return
	_drop(was)
	_down[index] = zone
	if zone != "":
		_apply(zone)
	queue_redraw()


## 一个区域被踩下（同一根手指的多次按下由 [member _hold] 计数）。
func _apply(zone: String) -> void:
	if ZONE_ACTION.has(zone):
		var n := int(_hold.get(zone, 0)) + 1
		_hold[zone] = n
		# 第二根手指踩同一个踏板时不用再按一遍动作 —— 但**必须记账**，
		# 否则它先抬起来会把第一根的那一脚也放掉。
		if n == 1:
			Input.action_press(String(ZONE_ACTION[zone]))
		return
	match zone:
		"pause":
			set_paused(true)
		"resume":
			set_paused(false)
		ACTION_RESTART, ACTION_MAP:
			_request(zone)


## 一个区域被放开。
func _drop(zone: String) -> void:
	if not ZONE_ACTION.has(zone):
		return
	var n := int(_hold.get(zone, 0)) - 1
	if n > 0:
		_hold[zone] = n
		return
	_hold.erase(zone)
	Input.action_release(String(ZONE_ACTION[zone]))


func _request(id: String) -> void:
	# **先解暂停再喊人。** `get_tree().paused` 是全局的，带着 true 换场景，
	# 新场景一进去就是冻住的。
	set_paused(false)
	pause_action.emit(id)


# ---------------------------------------------------------------------------- 绘制


func _draw() -> void:
	if _paused:
		_draw_menu()
		return
	if locked:
		return
	var rects := pedal_rects()
	_draw_pedal(rects["brake"], "brake", _t("刹车", "BRAKE"), "◀", BRAKE_COLOR)
	_draw_pedal(rects["gas"], "gas", _t("油门", "GAS"), "▶", GAS_COLOR)
	_draw_pause()


## 一个踏板：半透明底 + 边框 + 一个大箭头 + 名字。踩下去时边框换成高亮色、
## 底色加深 —— 手机上手指盖着半个踏板，**唯一看得见的就是边框那一圈**，
## 所以反馈全做在边框上。
func _draw_pedal(r: Rect2, zone: String, label: String, glyph: String, accent: Color) -> void:
	var held := int(_hold.get(zone, 0)) > 0
	draw_rect(r, FILL_HELD if held else FILL)
	draw_rect(r, accent if held else EDGE, false, 4.0 if held else 3.0)
	if _font == null:
		return
	_center_in(glyph, r, r.size.y * 0.52, GLYPH_SIZE, accent if held else LABEL)
	_center_in(label, r, r.size.y - 22.0, LABEL_SIZE, accent if held else LABEL)


func _draw_pause() -> void:
	var r := pause_rect()
	draw_rect(r, FILL)
	draw_rect(r, EDGE, false, 3.0)
	# 两根竖条：不依赖字体里的「⏸」字形（那个字符不是每个字体都有）。
	var w := 9.0
	var h := 26.0
	var c := r.get_center()
	draw_rect(Rect2(c + Vector2(-w - 4.0, -h * 0.5), Vector2(w, h)), LABEL)
	draw_rect(Rect2(c + Vector2(4.0, -h * 0.5), Vector2(w, h)), LABEL)


func _draw_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	if _font == null:
		return
	var items := menu_rects()
	var first := items[0]["rect"] as Rect2
	_center(_t("暂停", "PAUSED"), Vector2(0.0, first.position.y - 48.0), TITLE_SIZE, LABEL)
	var labels := {
		"resume": _t("继续", "RESUME"),
		ACTION_RESTART: _t("重开", "RESTART"),
		ACTION_MAP: _t("返回选图", "MAPS"),
	}
	for item in items:
		var r := item["rect"] as Rect2
		draw_rect(r, PANEL)
		draw_rect(r, PANEL_EDGE, false, 3.0)
		_center_in(String(labels[String(item["id"])]), r, r.size.y * 0.5 + 11.0,
				BTN_TEXT_SIZE, LABEL)


## 在整块屏幕的宽度上居中。
func _center(text: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


## 在**某个矩形自己的宽度**上居中。踏板贴着左右边缘，用 [method _center] 的话
## 字会跑到屏幕正中间去 —— 这两个函数不能互相顶替。
func _center_in(text: String, r: Rect2, dy: float, font_size: int, color: Color) -> void:
	draw_string(_font, Vector2(r.position.x, r.position.y + dy), text,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_size, color)


func _t(zh: String, en: String) -> String:
	return zh if _cjk else en
