extends Control
class_name HillVehicleSelect
## 选车界面：一行卡片轮播，选一辆开着跑。
##
## 流程是 **这里** → 车库 → 选图 → 跑。这是 `run/main_scene`，开局第一站。
##
## 选车排在车库**前面**：升级是按车分开的（[method SaveData.levels_of]），车库那一页
## 的四个数字属于「当前选中那辆车」，所以得先把车定下来，才有得升级。
##
## 按 Esc 等于「就开存档里那辆，直接进车库」，不选也走得下去 —— 光标本来就停在
## 上次开的那辆车上。
##
## 和车库、选图、HUD 一样全部用 [method CanvasItem.draw_*] 画，字体走 [UiFonts]。
##
## **卡片上那辆车是从场景里实时读出来画的**（[method Vehicles.silhouette]），
## 不是贴图也不是另画的示意图：改车的形状、配色、轮子半径，这里立刻跟着变。
## 数值那一行同理，全部由 [method Vehicles.stats] 现算。
##
## ## 为什么是轮播而不是「几行几列」
##
## 八辆车摆成两行四列时，一行里挤的车越多卡就越窄：四列时卡宽 276.5，八列时只剩
## 129.3，卡上那六行字（车名 36 号、说明 15 号）缩号缩到 13 号也放不下，而
## `draw_string` 不裁不绕 —— 撑出去是画到**隔壁卡**上。所以车的张数一多，唯一还
## 能保住可读卡宽的办法就是**一次只摆四张，其余的挪到窗口外**。
##
## [constant VISIBLE] 就是「一屏几张」，它**锁死了卡宽**
## `(1160 − 18×3) / 4 = 276.5`；车库、选图那两页的文案宽度约束全是照这个数量出来的，
## 改它等于把三页的文案一起推翻。窗口外那几张 [method _card_rect] 给的是**空矩形**
## —— 空矩形 `has_point()` 恒为假，于是「看不见的卡点不到」是几何上自然成立的，
## 不需要在 [method _card_at] 里再写一条 if。

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
const RED := Color(1.0, 0.42, 0.36)
const GROUND := Color(0.30, 0.36, 0.30)
const TYRE := Color(0.13, 0.14, 0.17)

const PANEL_W := 1160.0
const GAP := 18.0
const CARD_TOP := 196.0
const CARD_H := 348.0
## 卡片顶部那块预览的高度。
const PREVIEW_H := 118.0
## 预览里车身四周的留白（缩放时用掉）。
const PREVIEW_PAD := 26.0
const PAD := 20.0

## 卡片上那几行字的基线，**相对卡片顶部**（最后两行是相对卡片**底边**，负号就是
## 「从底下往上量」）。
##
## 写成常量是为了能测：`tests/vehicleselect` 照这组数摆出「每行字落在哪儿」的表格，
## 才算得出有没有上下叠在一起、有没有被锁卡那块底板从当中切开（见 [HillLockBadge]）。
## 数字留在 `_draw_card()` 里的话，测试只能自己抄一份 —— 抄了就一定会漂：布局改了、
## 量还是旧位置，两边都自认为对。选图那一页的 `LINE_*` 是同一条理由。
##
## 编排的道理：预览下面紧接着车名（36 号，最显眼），再两行数字（整车/满油），空一格
## 之后是定位标签和说明，最后把推重比钉在卡片底部（它是这个游戏里最要命的一个数）。
const LINE_NAME := 46.0
const LINE_SIZE := 74.0
const LINE_FUEL := 98.0
const LINE_ROLE := 138.0
const LINE_NOTE := 162.0
const LINE_RATIO := -40.0
const LINE_WHEELIE := -16.0

## 一屏摆几张卡。**这是整页几何的锚**：卡宽 = (1160 − 18×(VISIBLE−1)) / VISIBLE。
const VISIBLE := 4
## 左右翻页箭头离面板边缘多远、多大。
const ARROW_OUT := 30.0
const ARROW_R := 19.0
## 卡片下面那排圆点指示器。
const DOT_Y := 580.0
const DOT_R := 5.0
const DOT_STEP := 17.0

const GARAGE_SCENE := "res://scenes/garage.tscn"

var _font: Font
var _cjk := false
## 实际能选的车。**不是 [constant Vehicles.IDS]** —— 只有 .tscn 做出来的才算数，
## 所以新车还在做的时候，这里不会摆出一张点进去加载不出来的卡片。
var _ids: Array[String] = []
## 光标：**在 [member _ids] 里的下标**，不是屏幕上的第几格。
var _sel := 0
## 窗口最左边那一格放的是 [member _ids] 里的第几辆。光标跑到窗口外面时它才动，
## 一次动一格（见 [method _move]）。
var _first := 0
var _hover := -1
## 鼠标停在哪个箭头上：−1 左边，1 右边，0 没停。
var _arrow_hover := 0


func _ready() -> void:
	_font = UiFonts.load_cjk_font()
	_cjk = _font != null
	if not _cjk:
		_font = get_theme_default_font()
	_ids = Vehicles.available()
	# 光标停在存档里选中的那辆车上，按回车就是「继续开这辆」。存档里的车没做出来
	# （或者存档坏了）时 find 会给 -1，那就退回第一辆。
	_sel = maxi(0, _ids.find(SaveData.selected_vehicle))
	# 开局把窗口滚到「光标看得见」，而且**滚得尽可能少** —— 存档里开的是越野车
	# （第 0 辆）时窗口就该停在最左边，而不是绕到最后三辆去（见 [method _follow]）。
	_first = 0
	_follow()
	queue_redraw()


func _t(zh: String, en: String) -> String:
	return zh if _cjk else en


# ---------------------------------------------------------------- 布局

## 一张卡的宽度。只由 [constant VISIBLE] 决定，**和车的张数无关** —— 张数一变卡宽
## 就变的话，卡上那六行字每一辆车的可读性都会跟着抖（见类注释）。
func _card_w() -> float:
	var w := minf(PANEL_W, size.x - 120.0)
	return (w - GAP * float(VISIBLE - 1)) / float(VISIBLE)


## 一屏真能摆几张。车比 [constant VISIBLE] 少时按实际张数算，卡片照样 276.5 宽，
## 只是整行短一点、居中。
func _visible_count() -> int:
	return mini(_ids.size(), VISIBLE)


## 整行左边缘。**居中的是「真摆出来的那几张卡」**，不是 VISIBLE 个格子的空槽 ——
## 否则车少的时候卡会全挤在左边。
func _row_left() -> float:
	var count := _visible_count()
	var span := float(count) * _card_w() + GAP * float(maxi(count - 1, 0))
	return (size.x - span) * 0.5


## 第 [param i] 辆车此刻在第几格（0 是最左）。返回 ≥ [constant VISIBLE] 或 −1
## 表示**它在窗口外**，不该画也不该能点。
##
## 取模是关键：`_first` 和 `i` 各自都可能绕回来，直接相减会得到负数或超过 VISIBLE
## 的数。车不比一屏多的时候（`n <= VISIBLE`）不需要窗口，一律照原顺序摆。
func _slot_of(i: int) -> int:
	var n := _ids.size()
	if n == 0 or i < 0 or i >= n:
		return -1
	if n <= VISIBLE:
		return i
	return wrapi(i - _first, 0, n)


## 第 [param i] 辆车的卡片矩形。**窗口外给空矩形** [constructor Rect2]。
##
## 空矩形是有意选的返回值：`Rect2(Vector2.ZERO, Vector2.ZERO).has_point(p)` 恒为假
## （判断是半开的，`p.x < 0` 不成立），所以「点不到看不见的卡」不用另外写判断。
func _card_rect(i: int) -> Rect2:
	var slot := _slot_of(i)
	if slot < 0 or slot >= VISIBLE:
		return Rect2()
	var x := _row_left() + float(slot) * (_card_w() + GAP)
	return Rect2(x, CARD_TOP, _card_w(), CARD_H)


func _card_at(pos: Vector2) -> int:
	for i in range(_ids.size()):
		var r := _card_rect(i)
		if r.has_area() and r.has_point(pos):
			return i
	return -1


## 左右箭头那两块热区。返回 −1 / 0 / 1。
##
## **和 `_card_at` 分开**：箭头画在面板外侧的留白里（1280 宽时左右各 60 px，箭头占
## 中间 38 px），不压卡片。合成一个函数的话，「按坐标算不算点中卡片」这条测试就会
## 被箭头污染 —— 点左边缘本来是「什么都没点到」，会变成「点到了上一页」。
func _arrow_at(pos: Vector2) -> int:
	if _ids.size() <= VISIBLE:
		return 0
	var left := _row_left() - ARROW_OUT
	var right := _row_left() + float(_visible_count()) * _card_w() \
			+ GAP * float(maxi(_visible_count() - 1, 0)) + ARROW_OUT
	var y := CARD_TOP + CARD_H * 0.5
	# 1.35 倍而不是 1.6：1280 宽时面板离屏幕边只剩 60 px，热区放大到 1.6 倍
	# （30.4 px）就会伸进第 0 张卡里，点卡片左边缘变成翻页。
	if absf(pos.y - y) > ARROW_R * 1.35:
		return 0
	if absf(pos.x - left) <= ARROW_R * 1.35:
		return -1
	if absf(pos.x - right) <= ARROW_R * 1.35:
		return 1
	return 0


# ---------------------------------------------------------------- 输入
#
# **不接 InputEventScreenTouch。** 手指按下时引擎会再补一个合成鼠标事件
# （project.godot 的 emulate_mouse_from_touch），两边都接就是一次点按跑两遍 ——
# 原来就是这样：手指擦过一张没选中的车卡会连「选中」和「开局」一起走完。
# 见 tests/tap。

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_on_key((event as InputEventKey).physical_keycode)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_on_pad((event as InputEventJoypadButton).button_index)
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var card := _card_at(m.position)
		var arrow := _arrow_at(m.position)
		if card != _hover or arrow != _arrow_hover:
			_hover = card
			_arrow_hover = arrow
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# 滚轮也翻页：轮播本来就是这个手势，键盘只是备选。
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move(-1)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(1)
		elif b.button_index == MOUSE_BUTTON_LEFT:
			_on_click(b.position)


func _on_key(code: int) -> void:
	match code:
		KEY_LEFT, KEY_A, KEY_UP, KEY_W:
			_move(-1)
		KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(_sel)
		KEY_ESCAPE:
			get_tree().change_scene_to_file(GARAGE_SCENE)


func _on_pad(button: int) -> void:
	match button:
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER:
			_move(-1)
		JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER:
			_move(1)
		JOY_BUTTON_A, JOY_BUTTON_START:
			_activate(_sel)
		JOY_BUTTON_B:
			get_tree().change_scene_to_file(GARAGE_SCENE)


## 光标挪一格，窗口跟着走。
##
## 光标是**首尾环绕**的（八辆车里按右键八次回到原地），窗口也环绕 —— 于是「绕回去」
## 也只是一格一格地滚，不会整屏跳。规则只有一条：
##
## > **光标走出窗口才滚，而且一次只滚一格。**
##
## 走的是 [param delta] 的方向而不是「新位置比旧位置大还是小」：从第 0 辆往左绕到
## 第 7 辆时新位置是大的，但方向是往左，两者会判反。
func _move(delta: int) -> void:
	var n := _ids.size()
	if n == 0:
		return
	_sel = wrapi(_sel + delta, 0, n)
	if n > VISIBLE and _slot_of(_sel) >= VISIBLE:
		_first = wrapi(_first + (1 if delta > 0 else -1), 0, n)
	_follow()
	queue_redraw()


## 把窗口拉回「光标一定看得见」的状态，**并且是欠着也不溢出**。
##
## 两条出路：光标本来就在窗口里（含 `n <= VISIBLE` 时根本不需要窗口）→ 只需要把
## 越界的 `_first` 折回来；光标在窗口外（存档里开着一辆排在很后面的车）→ 窗口贴到
## 光标上，让它落在**最右边那一格**。贴右边而不是居中，是为了跟 [method _move] 的
## 行为一致：往右走就是「光标从右边滑进来」。
func _follow() -> void:
	var n := _ids.size()
	if n <= VISIBLE:
		_first = 0
		return
	_first = wrapi(_first, 0, n)
	if _slot_of(_sel) < VISIBLE:
		return
	_first = wrapi(_sel - (VISIBLE - 1), 0, n)


func _on_click(pos: Vector2) -> void:
	var arrow := _arrow_at(pos)
	if arrow != 0:
		_move(arrow)
		return
	var card := _card_at(pos)
	if card < 0:
		return
	if card != _sel:
		# 第一下：只把光标挪过来。**不在这里顺手买** —— 连着 [method _activate]
		# 的话，一次点击就等于「选中并买下」，翻页时擦到哪辆就买哪辆。
		_sel = card
		_follow()
		queue_redraw()
		return
	_activate(card)


## 对**光标所在的那辆车**按了一下（点击 / 回车 / 手柄 A）。
##
## 三段：通了（白送的或买过的）直接进车库；锁着的这一下是「买」，买不起就什么也
## 不发生（卡片上写着「金币不够」）。买下来之后**不顺手进车库** —— 卡片当场变成通
## 的样子、金币当场少掉，玩家看得见自己买到了什么，再按一下才走。
##
## 和选图那一页 [method HillMapSelect._activate] 是同一条规矩，见
## [method SaveData.unlock_map] 上面那段。
func _activate(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	var id: String = _ids[index]
	if SaveData.vehicle_unlocked(id):
		_pick(index)
		return
	if SaveData.unlock_vehicle(id):
		queue_redraw()


## 选中并去**车库**。**先写存档再换场景**：换场景是延到帧末的，写盘是立刻的，
## 顺序反过来的话玩家可能在写盘之前就切走了。
##
## 下一步是车库而不是选图：升级是按车分开的，玩家得先定下开哪辆车，再决定给它
## 花多少钱。车库页眉会显示刚选中的车名，改完才轮到选图。
func _pick(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	SaveData.select_vehicle(_ids[index])
	get_tree().change_scene_to_file(GARAGE_SCENE)


# ---------------------------------------------------------------- 绘制

## 画一行卡内的字，放不下就缩号。
##
## 缩号的规则用的是选图界面那一份 [method HillMapSelect.fit_size]：两张界面的卡一样宽
## （都是 1160 面板里的 276.5），文案一样是活的，`draw_string` 一样不裁不绕 ——
## 撑出去会直接画到隔壁卡上。同一套问题留一份实现，改一处两边一起变。
func _card_string(at: Vector2, text: String, px: int, color: Color, room: float) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			HillMapSelect.fit_size(_font, text, px, room), color)


func _draw() -> void:
	_draw_background()
	_draw_header()
	# 只画窗口里那几张。**不画窗口外的**，不是「画了再裁掉」：这些卡上没有遮罩，
	# 画出去就是画在别的卡上，或者是画到屏幕外白烧一次绘制。
	for i in range(_ids.size()):
		var slot := _slot_of(i)
		if slot >= 0 and slot < VISIBLE:
			_draw_card(i)
	_draw_arrows()
	_draw_dots()
	_draw_footer()


func _draw_background() -> void:
	draw_polygon(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(size.x, 0.0),
				Vector2(size.x, size.y), Vector2(0.0, size.y)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM])
	)


func _draw_header() -> void:
	draw_string(_font, Vector2(60.0, 82.0), _t("选择车辆", "CHOOSE A VEHICLE"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 46, TEXT)
	# 辆数是活的（[method Vehicles.available]），**不能写死「四辆」** —— 车一辆辆加
	# 进来的时候那句话会当场说错，而且错得不显眼。
	draw_string(_font, Vector2(60.0, 114.0),
			_t("%d 辆车的手感、油耗和爬坡能力都不一样",
					"each of the %d drives, sips fuel and climbs differently") % _ids.size(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, TEXT_DIM)

	var label := _t("金币总数", "TOTAL COINS")
	var amount := str(SaveData.total_coins)
	draw_string(_font, Vector2(0.0, 74.0), label, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 19, TEXT_DIM)
	draw_string(_font, Vector2(0.0, 122.0), amount, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 60.0, 46, GOLD)
	var text_w := _font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	draw_circle(Vector2(size.x - 60.0 - text_w - 26.0, 106.0), 13.0, GOLD)
	draw_circle(Vector2(size.x - 60.0 - text_w - 26.0, 106.0), 7.0, Color(1.0, 0.94, 0.66))


func _draw_card(i: int) -> void:
	var r := _card_rect(i)
	var id: String = _ids[i]
	var v: Dictionary = Vehicles.get_vehicle(id)
	var s: Dictionary = Vehicles.stats(id)
	var focused := i == _sel
	var hot := focused or i == _hover
	var room := r.size.x - PAD * 2.0

	draw_rect(r, CARD_SEL if focused else CARD)
	draw_rect(r, BORDER_SEL if focused else BORDER, false, 2.0)
	_draw_preview(r, id)
	draw_line(r.position + Vector2(0.0, PREVIEW_H), r.position + Vector2(r.size.x, PREVIEW_H),
			Color(0.0, 0.0, 0.0, 0.35), 2.0)

	var at := r.position + Vector2(PAD, 0.0)
	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_NAME), _t(v["zh"], v["en"]), 36,
			TEXT if hot else TEXT.lerp(TEXT_DIM, 0.25), room)
	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_SIZE), _size_line(s), 16, SKY, room)
	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_FUEL), _fuel_line(s), 16, SKY, room)

	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_ROLE),
			"◆ " + _t(v["zh_role"], v["en_role"]), 21, GOLD, room)
	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_NOTE), _t(v["zh_note"], v["en_note"]), 15,
			TEXT_DIM, room)

	# 底：推重比。**这是这个游戏里最要命的一个数**（超过翘头线就会后仰翻车），
	# 而且每辆车不一样，所以放在卡片最底下、按危险程度变色。
	#
	# 分两行写。「推重比 1.68 / 1.45 翘头」挤成一行时英文那份有 315 像素，而卡里只有
	# 236 —— 会被 `fit_size` 一路缩到 13 号，全卡最要紧的数字反而最小。拆成两行之后
	# 中英都在 140 以内，按原字号画。（这两个数就是 tests/vehicleselect 量出来的。）
	#
	# **锁着的车也照画**：推重比正是「值不值得为它花 100000」的主要依据，而且它在
	# 锁卡底板下面（见 [HillLockBadge]），压不着价钱那两行字。
	_card_string(at + Vector2(0.0, r.size.y + LINE_RATIO), _ratio_line(id), 18,
			_ratio_color(id), room)
	_card_string(at + Vector2(0.0, r.size.y + LINE_WHEELIE), _wheelie_line(), 15, TEXT_DIM, room)

	# 锁着的车：整张压暗，再盖上挂锁和价钱。**卡片本身照常画完**（预览、车名、参数、
	# 推重比），玩家得能看见自己买的是什么。画法和选图那一页共用一份
	# （[HillLockBadge]），那两页的卡片几何是同一套。
	var price := SaveData.vehicle_price(id)
	if price <= 0:
		return
	HillLockBadge.dim(self, r)
	var afford := SaveData.total_coins >= price
	HillLockBadge.draw(self, _font, r,
			HillLockBadge.price_line(price, _cjk),
			HillLockBadge.hint_line(focused, afford, _cjk),
			hot,
			HillLockBadge.PRICE if afford else HillLockBadge.DENIED)


## 卡片顶部：地面 + 这辆车自己的画法，等比缩放到框里。
##
## 用 [method CanvasItem.draw_set_transform] 把画布设成「车体局部坐标」，
## 于是下面可以直接用车里的原始坐标画，缩放和居中都不用自己算 —— 也正因为这样，
## 卡片画的一定是实车形状本身。
func _draw_preview(r: Rect2, id: String) -> void:
	var sil := Vehicles.silhouette(id)
	draw_rect(Rect2(r.position, Vector2(r.size.x, PREVIEW_H)), Color(0.10, 0.13, 0.19))
	if sil.is_empty():
		return
	var box: Rect2 = sil["box"]
	var room := Vector2(r.size.x - PREVIEW_PAD * 2.0, PREVIEW_H - PREVIEW_PAD * 2.0)
	var scale := minf(room.x / maxf(box.size.x, 1.0), room.y / maxf(box.size.y, 1.0))
	var centre := r.position + Vector2(r.size.x * 0.5, PREVIEW_H * 0.5)
	# 地面线画在车底（包围盒下沿 = 轮子最低点），车看着是站在地上的。
	var ground := centre + Vector2(0.0, (box.size.y * 0.5) * scale)
	draw_line(Vector2(r.position.x + 14.0, ground.y), Vector2(r.position.x + r.size.x - 14.0, ground.y),
			GROUND, 2.0)

	draw_set_transform(centre - box.get_center() * scale, 0.0, Vector2.ONE * scale)
	for w in sil["wheels"]:
		draw_circle(w["pos"], w["radius"], TYRE)
		draw_circle(w["pos"], float(w["radius"]) * 0.38, Color(0.72, 0.74, 0.78))
	for layer in sil["layers"]:
		draw_colored_polygon(layer["polygon"], layer["color"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 左右两个翻页箭头。**只在真的还有窗口外的车时才画** —— 车比一屏少的时候画出来
## 是个按了没反应的按钮。
func _draw_arrows() -> void:
	if _ids.size() <= VISIBLE:
		return
	var y := CARD_TOP + CARD_H * 0.5
	var count := _visible_count()
	var left := _row_left() - ARROW_OUT
	var right := _row_left() + float(count) * _card_w() + GAP * float(maxi(count - 1, 0)) + ARROW_OUT
	_arrow(Vector2(left, y), -1)
	_arrow(Vector2(right, y), 1)


func _arrow(centre: Vector2, dir: int) -> void:
	var hot := _arrow_hover == dir
	var col := SKY if hot else TEXT_DIM
	if hot:
		draw_circle(centre, ARROW_R * 1.5, Color(1.0, 1.0, 1.0, 0.07))
	draw_circle(centre, ARROW_R, Color(0.10, 0.13, 0.19, 0.85))
	draw_arc(centre, ARROW_R, 0.0, TAU, 32, col, 1.0, true)
	var tip := centre + Vector2(float(dir) * 6.0, 0.0)
	var back := centre - Vector2(float(dir) * 5.0, 0.0)
	draw_polyline(PackedVector2Array([
		back + Vector2(0.0, -8.0), tip, back + Vector2(0.0, 8.0)]), col, 3.0, true)


## 卡片下面那排圆点：一共几辆、此刻窗口盖住了哪几辆、光标在哪一辆。
##
## 圆点数 = 车的辆数，看着不直观就自己数 —— 八辆时八个点正好，再多就该换成页码了。
func _draw_dots() -> void:
	var n := _ids.size()
	if n <= 1:
		return
	var y := DOT_Y
	var x0 := size.x * 0.5 - DOT_STEP * float(n - 1) * 0.5
	for i in range(n):
		var at := Vector2(x0 + DOT_STEP * float(i), y)
		var slot := _slot_of(i)
		# 亮起来要同时满足两件事：这一格在窗口里，**而且这辆车是通的**。锁着的车退回
		# 「窗口外」那一档的暗色，于是一排点里一眼能看出后面几页还没买。
		var lit := slot >= 0 and slot < VISIBLE and SaveData.vehicle_unlocked(_ids[i])
		if i == _sel:
			draw_circle(at, DOT_R + 1.5, GOLD)
		elif lit:
			draw_circle(at, DOT_R, SKY)
		else:
			draw_circle(at, DOT_R - 1.5, Color(TEXT_DIM, 0.45))
	var counter := _t("%d / %d 辆", "%d / %d") % [_sel + 1, n]
	draw_string(_font, Vector2(0.0, y + 7.0), counter, HORIZONTAL_ALIGNMENT_RIGHT,
			size.x * 0.5 - DOT_STEP * float(n) * 0.5 - 16.0, 17, TEXT_DIM)


## 「多大 / 多快」那一行。全部从 [method Vehicles.stats] 现算。
func _size_line(s: Dictionary) -> String:
	return _t("整车 %.0f · 极速 %.0f", "MASS %.0f · TOP %.0f") % [s["mass"], s["top_speed"]]


## 「一箱油能烧多久」那一行。满油门跑到干的时间，直接反映油箱大小和油耗。
func _fuel_line(s: Dictionary) -> String:
	return _t("满油 %.1f 秒 · 油箱 %.0f", "TANK %.1f s · %.0f") % [s["fuel_seconds"], s["fuel_max"]]


## 卡片最底下那行：原厂推重比。
##
## 说的是**原厂值**（[method Upgrades.stock_thrust_ratio]，引擎 0 级），不是玩家当前的
## 等级 —— 这一页是「挑哪辆车」，横比的应该是基数；升级之后各自会乘上同一个倍率，
## 谁更接近翘头线的顺序不变。当前等级下的实际值在车库页脚上。
func _ratio_line(id: String) -> String:
	return _t("推重比 %.2f", "POWER/WEIGHT %.2f") % Upgrades.stock_thrust_ratio(id)


## 推重比下面那行小字：超过这个数车就后仰翻车。
##
## 单独一行，不并进推重比那行 —— 见 `_draw_card()` 里的注释：并起来会缩号。
## 八辆车共用同一个翘头线，所以这里不带车 id。
func _wheelie_line() -> String:
	return _t("翘头线 %.2f", "WHEELIE LINE %.2f") % Upgrades.WHEELIE_LINE


## 推重比那行的颜色：过了翘头线是红的，九成以上是黄的。
## 和车库页脚同一套判据，只是那边用的是当前等级。
func _ratio_color(id: String) -> Color:
	var ratio := Upgrades.stock_thrust_ratio(id)
	if ratio >= Upgrades.WHEELIE_LINE:
		return RED
	if ratio > Upgrades.WHEELIE_LINE * 0.9:
		return GOLD
	return SKY


## 页脚。锁着的车还在的时候多一行说明**怎么买** —— 两段式购买是这一版新加的，
## 页脚不说的话，那行提示只出现在光标停在锁卡上时。
func _draw_footer() -> void:
	var y := size.y - 26.0
	draw_string(_font, Vector2(60.0, y),
			_t("← → 翻页    回车 / 点击 进车库改装    Esc 跳过（开这辆）",
				"LEFT/RIGHT browse    ENTER / CLICK garage    ESC skip"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM)
	if _locked_count() > 0:
		draw_string(_font, Vector2(60.0, y - 26.0),
				_t("锁住的车点一下选中、再点一下花 %d 金币买下" % Vehicles.UNLOCK_PRICE,
						"locked cars: tap to select, tap again to buy for %d coins"
								% Vehicles.UNLOCK_PRICE),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)


## 还有几辆车没解锁。只为页脚那一行要不要画。
func _locked_count() -> int:
	var out := 0
	for id in _ids:
		if not SaveData.vehicle_unlocked(id):
			out += 1
	return out
