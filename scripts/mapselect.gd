extends Control
class_name HillMapSelect
## 选图界面：一页四张图，选一张开着跑。
##
## 车库点「开始游戏」进这里，这里选完进道具商店（`scenes/shop.tscn`），
## 商店结算完才进 `scenes/main.tscn`；按 Esc 回车库。
##
## 和车库、HUD 一样全部用 [method CanvasItem.draw_*] 画，字体走 [UiFonts]。
## 卡片上那点地形配色是**从 [Maps] 实时读出来画的**，不是贴图 —— 改了地图的
## 配色或起伏倍率，这里立刻跟着变，不会出现「预览和真图不一样」。
##
## ## 一页四张：这一页和选车那一页是同一套几何
##
## 十二张图横排一屏时每张只有 80 像素宽，而卡上最长的说明要 527 像素 —— 全都糊在
## 一起。所以这里和 [HillVehicleSelect] 一样改成**轮播**：一次摆 [constant VISIBLE]
## 张，其余的挪到窗口外。卡宽因此锁死在 `(1160 − 18×3) / 4 = 276.5`，和选车页
## 逐位相同 —— 两页的卡片是同一个尺寸，锁卡（[HillLockBadge]）才有一套尺寸可用。
##
## 窗口外那几张 [method _card_rect] 给的是**空矩形**，空矩形 `has_point()` 恒为假，
## 于是「看不见的卡点不到」是几何上自然成立的，不用在 [method _card_at] 里再写判断。
##
## ## 锁住的图：买法是两下
##
## 前 [constant Maps.FREE_COUNT] 张白送，其余每张 [constant Maps.UNLOCK_PRICE] 金币
## （见 [method SaveData.unlock_map] 上面那段）。点一下**只把光标挪过去**，再点一下
## 才真扣钱 —— 一次点中就买的话，翻页时手指擦过一张 50000 的图就没了。
##
## 光标在锁卡上时卡片会明说「再点一下购买」，买不起则明说「金币不够」：点了没反应
## 又不说话，玩家会以为卡坏了（文案在 [HillLockBadge.hint_line]）。
##
## ## 页脚右下角：经典 / 随机
##
## 模式是**整页一个**（不是每张图一个）：页脚两格，选哪张图都用这个模式，见
## [constant Maps.MODES]。它落在存档里（[member SaveData.map_mode]），所以下次
## 打开还是上次那个。
##
## 开关的三条路（鼠标 / Tab / 手柄 Y）都只走 [method _set_mode]，判「现在是哪一格」
## 也只有一个地方（[method _mode_slot] 读存档，不是另存一份成员变量）。**这一页里
## 除了它，没有第二个「点了不改变选中的图」的东西** —— 所以它在页脚，离卡片远远的。

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

const PANEL_W := 1160.0
const GAP := 18.0
const CARD_TOP := 196.0
const CARD_H := 348.0
## 卡片顶部那块地形预览的高度。
const PREVIEW_H := 118.0
## 预览里的地面基准线（相对卡片顶部的 y）。
const PREVIEW_GROUND := 76.0
## 卡片里每一行的基线，**相对卡片顶部**（预览下面就是这些行）。
##
## 这是一套**为了折行重排过的行距**：说明和地形说明现在各能占两行，卡上一共八行字，
## 而卡片高度还是 348。旧的六个基线（164 / 192 / 226 / 266 / 292 / 328）是给六行
## 布的局，两行说明的第二行会正好压在下一行上（实测越界 3 像素，见 tests/mapselect
## 的「相邻两行字不上下重叠」）。现在按「组内紧、组间松」重排：
##
##   组内（同一段的第二行）21 / 19 像素，组间至少 25 像素 —— 折出来的第二行因此
##   明显归上面那一行，而不是归下面那一行。
##
## 这些数**和 tests/mapselect 里量字号的那张表是同一份**：测试直接读这些常量，
## 改了这里测试就跟着量新位置，不会出现「布局改了、量还是旧位置」。
const LINE_NAME := 44.0          # 图名，36 号
const LINE_STATS := 70.0         # 参数行，16 号
const LINE_NOTE := 96.0          # 说明第一行，17 号
const NOTE_STEP := 21.0          # 说明第二行往下挪多少
const LINE_FEATURE := 146.0      # 地形名，21 号
const LINE_FEATURE_NOTE := 172.0 # 地形说明第一行，15 号
const FEATURE_NOTE_STEP := 19.0  # 地形说明第二行往下挪多少
const LINE_RECORD := 14.0        # 纪录，18 号，**从卡片下沿往上量**
## 卡片里文字左右各自的留白。文字可用宽度 = 卡宽 − 2 × 这个数。
const PAD := 20.0
## 缩号的下限。再放不下就让它出去（也只剩很短的余地），不无限缩。
const MIN_FONT := 12

## 一屏摆几张卡。**这是整页几何的锚**：卡宽 = (1160 − 18×(VISIBLE−1)) / VISIBLE。
## 和 [constant HillVehicleSelect.VISIBLE] 必须一致 —— 两页的卡片一样宽，两边卡上的
## 文案约束、锁卡尺寸才是同一套。
const VISIBLE := 4
## 左右翻页箭头离面板边缘多远、多大。
const ARROW_OUT := 30.0
const ARROW_R := 19.0
## 卡片下面那排圆点指示器。
const DOT_Y := 580.0
const DOT_R := 5.0
const DOT_STEP := 17.0

## 页脚右下角那两格模式开关（经典 / 随机）的尺寸。
##
## 96 宽是照「经典」「RANDOM」这两种写法里更宽的那个量的（英文比中文长，见
## [constant MIN_FONT] 上面那条注释讲的同一件事），字号 20。
const MODE_W := 96.0
const MODE_H := 38.0
const MODE_GAP := 6.0
## 整排离屏幕右边和底边各留多少。底边这里和页脚提示文字同一档（那是
## `size.y - 26` 的基线），于是开关和左边那行字看起来是一行上的东西。
const MODE_MARGIN := 60.0
const MODE_BOTTOM := 12.0

const GARAGE_SCENE := "res://scenes/garage.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"

var _font: Font
var _cjk := false
## 实际能选的地图。取 [constant Maps.IDS] 本身，但要过 [member _ids] 这一道：
## 下面所有几何（卡宽、窗口、圆点）都是照着**摆出来的张数**算的，将来地图表要
## 过滤掉几张（比如还没做完的）时，改的只是这一处。
var _ids: Array[String] = []
## 光标：**在 [member _ids] 里的下标**，不是屏幕上的第几格。
var _sel := 0
## 窗口最左边那一格放的是 [member _ids] 里的第几张。光标跑到窗口外面时它才动，
## 一次动一格（见 [method _move]）。
var _first := 0
var _hover := -1
## 鼠标停在哪个箭头上：−1 左边，1 右边，0 没停。
var _arrow_hover := 0
## 鼠标停在哪一格模式开关上，−1 = 都没停。
var _mode_hover := -1


func _ready() -> void:
	_font = UiFonts.load_cjk_font()
	_cjk = _font != null
	if not _cjk:
		_font = get_theme_default_font()
	_ids = Maps.IDS
	# 光标停在存档里选中的那张图上，按回车就是「继续用这张」。存档里的图不在表里
	# （或者存档坏了）时 find 会给 -1，那就退回第一张。
	_sel = maxi(0, _ids.find(SaveData.selected_map))
	# 开局把窗口滚到「光标看得见」，而且**滚得尽可能少** —— 存档里选的是平原
	# （第 0 张）时窗口就该停在最左边，而不是绕到最后三张去（见 [method _follow]）。
	_first = 0
	_follow()
	queue_redraw()


func _t(zh: String, en: String) -> String:
	return zh if _cjk else en


# ---------------------------------------------------------------- 布局

## 一张卡的宽度。只由 [constant VISIBLE] 决定，**和图的张数无关** —— 张数一变卡宽
## 就变的话，卡上每行字的可读性都会跟着抖（见类注释）。
func _card_w() -> float:
	var w := minf(PANEL_W, size.x - 120.0)
	return (w - GAP * float(VISIBLE - 1)) / float(VISIBLE)


## 一屏真能摆几张。图比 [constant VISIBLE] 少时按实际张数算，卡片照样 276.5 宽，
## 只是整行短一点、居中。
func _visible_count() -> int:
	return mini(_ids.size(), VISIBLE)


## 整行左边缘。**居中的是「真摆出来的那几张卡」**，不是 VISIBLE 个格子的空槽 ——
## 否则图少的时候卡会全挤在左边。
func _row_left() -> float:
	var count := _visible_count()
	var span := float(count) * _card_w() + GAP * float(maxi(count - 1, 0))
	return (size.x - span) * 0.5


## 第 [param i] 张图此刻在第几格（0 是最左）。返回 ≥ [constant VISIBLE] 或 −1
## 表示**它在窗口外**，不该画也不该能点。
##
## 取模是关键：`_first` 和 `i` 各自都可能绕回来，直接相减会得到负数或超过 VISIBLE
## 的数。图不比一屏多的时候（`n <= VISIBLE`）不需要窗口，一律照原顺序摆。
func _slot_of(i: int) -> int:
	var n := _ids.size()
	if n == 0 or i < 0 or i >= n:
		return -1
	if n <= VISIBLE:
		return i
	return wrapi(i - _first, 0, n)


## 第 [param i] 张图的卡片矩形。**窗口外给空矩形** [constructor Rect2]。
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


## 左（−1）/ 右（+1）箭头的圆心。
##
## **箭头的位置只有这一处算**：画它（[method _draw_arrows]）和点它（[method _arrow_at]）
## 用的是同一个点。两处各算一遍的话，改了 `ARROW_OUT` 就会出现「看着在这儿、点的是
## 那儿」——而箭头只在光标悬停时变色，错位时玩家只会觉得「这个按钮有时候不管用」。
func _arrow_pos(dir: int) -> Vector2:
	var y := CARD_TOP + CARD_H * 0.5
	if dir < 0:
		return Vector2(_row_left() - ARROW_OUT, y)
	var count := _visible_count()
	var right := _row_left() + float(count) * _card_w() \
			+ GAP * float(maxi(count - 1, 0)) + ARROW_OUT
	return Vector2(right, y)


## 左右箭头那两块热区。返回 −1 / 0 / 1。
##
## **和 `_card_at` 分开**：箭头画在面板外侧的留白里（1280 宽时左右各 60 px，箭头占
## 中间 38 px），不压卡片。合成一个函数的话，「按坐标算不算点中卡片」这条测试就会
## 被箭头污染 —— 点左边缘本来是「什么都没点到」，会变成「点到了上一页」。
func _arrow_at(pos: Vector2) -> int:
	if _ids.size() <= VISIBLE:
		return 0
	# 1.35 倍而不是 1.6：1280 宽时面板离屏幕边只剩 60 px，热区放大到 1.6 倍
	# （30.4 px）就会伸进第 0 张卡里，点卡片左边缘变成翻页。
	for dir in [-1, 1]:
		var at := _arrow_pos(dir)
		if absf(pos.y - at.y) <= ARROW_R * 1.35 and absf(pos.x - at.x) <= ARROW_R * 1.35:
			return dir
	return 0


# ---------------------------------------------------------------- 模式开关
#
# 页脚右下角两格：经典 / 随机。**这一页里唯一一个「不是地图」的开关**，所以它
# 摆在地图卡片之外的页脚里，不占卡片的地方（卡片那 348 高的版面是按地图的
# 名字／说明／地形名／纪录排的，塞不下第三个按钮）。

## 第 `slot` 格的矩形。`slot` 就是 [member Maps.MODES] 里的下标。
##
## **纯函数，位置只有这一处算**：画它（[method _draw_mode]）、点它（[method _mode_at]）、
## 测试里点同一个坐标，读的都是这一份。理由和 [method _arrow_pos] 上面那段一样。
func mode_rect(slot: int) -> Rect2:
	var total := MODE_W * 2.0 + MODE_GAP
	var origin := Vector2(size.x - MODE_MARGIN - total, size.y - MODE_BOTTOM - MODE_H)
	return Rect2(origin + Vector2(float(slot) * (MODE_W + MODE_GAP), 0.0),
			Vector2(MODE_W, MODE_H))


## 点在哪一格上，−1 = 都没点到。
func _mode_at(pos: Vector2) -> int:
	for slot in Maps.MODES.size():
		if mode_rect(slot).has_point(pos):
			return slot
	return -1


## 当前选中的是第几格。
func _mode_slot() -> int:
	return maxi(0, Maps.MODES.find(SaveData.map_mode))


## 两格之间来回切。**点已经在亮着的那一格是空操作**（不是「切到另一个」）：
## 一个开关按下去没反应比按了跳到别处好，而且这样它和选图／选车的两段式点击
## 也不冲突 —— 这个函数从不改变光标。
func _set_mode(slot: int) -> void:
	if slot < 0 or slot >= Maps.MODES.size():
		return
	if Maps.MODES[slot] == SaveData.map_mode:
		return
	SaveData.set_map_mode(Maps.MODES[slot])
	# 卡片上那行「本图最远」也要跟着换口气，见 [method _draw_card]。
	queue_redraw()


## 键盘／手柄切模式：在 [member Maps.MODES] 里往前走一格（到头绕回去）。
func _cycle_mode() -> void:
	_set_mode(wrapi(_mode_slot() + 1, 0, Maps.MODES.size()))


# ---------------------------------------------------------------- 输入
#
# **不接 InputEventScreenTouch。** 手指按下时引擎会再补一个合成鼠标事件
# （project.godot 的 emulate_mouse_from_touch），两边都接就是一次点按跑两遍 ——
# 原来就是这样：手指擦过一张锁着的图会连「选中」和「买下」一起走完，当场扣钱。
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
		var mode := _mode_at(m.position)
		if card != _hover or arrow != _arrow_hover or mode != _mode_hover:
			_hover = card
			_arrow_hover = arrow
			_mode_hover = mode
			queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b := event as InputEventMouseButton
		# 滚轮也翻页：轮播本来就是这个手势，键盘只是备选。
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
		# 模式开关的键盘路：**不能用 M / V 那类字母** —— 那几个字母在这一页上
		# 没有别的意思，但和游戏里「M 换地图、V 换车」是同一套键，按错的代价是
		# 换场景。Tab 在这一页上是空的。
		KEY_TAB:
			_cycle_mode()
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
		JOY_BUTTON_Y:
			_cycle_mode()
		JOY_BUTTON_B:
			get_tree().change_scene_to_file(GARAGE_SCENE)


## 光标挪一格，窗口跟着走。
##
## 光标是**首尾环绕**的（十二张图里按右键十二次回到原地），窗口也环绕 —— 于是
## 「绕回去」也只是一格一格地滚，不会整屏跳。规则只有一条：
##
## > **光标走出窗口才滚，而且一次只滚一格。**
##
## 走的是 [param delta] 的方向而不是「新位置比旧位置大还是小」：从第 0 张往左绕到
## 第 11 张时新位置是大的，但方向是往左，两者会判反。
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
## 越界的 `_first` 折回来；光标在窗口外（存档里选着一张排在很后面的图）→ 窗口贴到
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
	# 模式开关排在最前面。它画在页脚、和卡片和箭头都不重叠，所以次序其实无所谓 ——
	# 摆在这里是为了让「页面上有哪几块可点的东西」一眼可见：模式 → 箭头 → 卡片。
	var slot := _mode_at(pos)
	if slot >= 0:
		_set_mode(slot)
		return
	var arrow := _arrow_at(pos)
	if arrow != 0:
		_move(arrow)
		return
	var card := _card_at(pos)
	if card < 0:
		return
	if card != _sel:
		# 第一下：只把光标挪过来。**不在这里顺手买** —— 连着 [method _activate]
		# 的话，一次点击就等于「选中并买下」，翻页时擦到哪张就买哪张。
		_sel = card
		_follow()
		queue_redraw()
		return
	_activate(card)


## 对**光标所在的那张卡**按了一下（点击 / 回车 / 手柄 A）。
##
## 三段：通的图直接进商店；锁着的图这一下是「买」，买不起就什么也不发生（卡片上
## 写着「金币不够」）。买下来之后**不顺手进图** —— 卡片当场变成通的样子、金币当场
## 少掉，玩家看得见自己买到了什么，再按一下才出发。
func _activate(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	var id: String = _ids[index]
	if SaveData.map_unlocked(id):
		_pick(index)
		return
	if SaveData.unlock_map(id):
		queue_redraw()


## 选定地图，进道具商店。
##
## **这里不直接开跑**：地图选完还差一步「买不买道具」，所以先落在
## `scenes/shop.tscn`，由它结算完再进 `scenes/main.tscn`。地图现在写进存档，
## 商店那边换场景时不用再传参。
func _pick(index: int) -> void:
	SaveData.select_map(_ids[index])
	get_tree().change_scene_to_file(SHOP_SCENE)


# ---------------------------------------------------------------- 绘制

## 画一行卡片里的字：**放不下就缩号**，宁可小一号也不越到隔壁卡上。
func _card_string(at: Vector2, text: String, px: int, color: Color, room: float) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fit_size(_font, text, px, room), color)


## 画一段卡片里的散文：**放不下就折行，还放不下才缩号**。见 [method fit_lines]。
func _card_para(at: Vector2, text: String, px: int, color: Color, room: float,
		max_lines: int, step: float) -> void:
	var fit := fit_lines(_font, text, px, room, max_lines)
	var lines: PackedStringArray = fit["lines"]
	for i in range(lines.size()):
		draw_string(_font, at + Vector2(0.0, float(i) * step), lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fit["size"], color)


## 这行字用 `font` 画、放进 `room` 宽里该用多大字号。
##
## 卡片宽度是死的（面板 1160，四张卡各 276.5），文案却是活的。实测（tests/mapselect）：
## 英文说明在没有中文字体的机器上更长 —— 「the baseline; springy rope bridges」
## 17 号字要 278 像素，比可用宽度多出 41；中文最长的那句也有 187，只剩 50 的余量，
## 再多写三个字就出去。而 `draw_string` 的 width 传 -1 时**不裁不绕**，多出来的部分
## 会直接画到隔壁卡片上，两张卡的字叠在一起。所以这里量一次、按需缩号。
##
## 只有放不下时才缩，放得下的时候字号和以前逐位一致 —— 这不是重新排版。
##
## 字体是**传进来**的，不是从 `_font` 里读的：没有中文字体的机器上真正画的是英文
## 那一份，而那份的字宽要用 fallback 字体才量得准。测试要能把两种字体都量一遍，
## 所以这里是个纯函数（`static`），量法和画的走同一份代码。
##
## [HillVehicleSelect] 和 [HillLockBadge] 都用这一份 —— 三个地方的卡片一样宽，
## 是同一个问题，实现也只该有一份。
static func fit_size(font: Font, text: String, px: int, room: float) -> int:
	while px > MIN_FONT \
			and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
		px -= 1
	return px


## 把一句话折成若干行，每行都不超过 [param room] 宽。
##
## **名字里那个 `_lines` 不能省。** GDScript 有个内置的全局函数 `wrap(值, 下限, 上限)`
## （把一个数折进区间），叫 `wrap` 的话内置那个会把这里的四参调用顶掉，报的是
## 「Too many arguments for wrap()」——看着像调用点写错了，其实是名字撞了。
##
## **缩号是不够的。** 卡片 276.5 宽、文字可用 236.5，而图上的说明是散文：屋顶那张
## 「矩形、三角、半圆、梯形、两种斜坡的屋顶随机接龙，缝的右边低一截」17 号字要
## 527 像素 —— 是可用宽度的两倍多，缩到 12 号还有 372，[method fit_size] 兜不住
## （它会停在 [constant MIN_FONT] 上然后照样撑出去）。所以散文先折行，折不下才缩号
## （见 [method fit_lines]）。
##
## 断点挑法：一个字一个字往后量，量到超了就先看这一行里有没有空格 —— 有，而且空格
## 落在**后半行**，就断在空格处（西文按词断，不把单词劈开）；否则按字断（中文本来
## 就能在任意两字之间断开，硬按空格断的话中文会一行到底）。空格落在前半行时不用它，
## 是因为那会把一行切成「短短的一截 + 长长的一截」，看着像排版坏了。
static func wrap_lines(font: Font, text: String, px: int, room: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for i in range(text.length()):
		var ch := text[i]
		if line != "" \
				and font.get_string_size(line + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
			var cut := line.rfind(" ")
			if cut > line.length() / 2:
				lines.append(line.substr(0, cut).strip_edges())
				line = line.substr(cut + 1)
			else:
				lines.append(line)
				line = ""
		line += ch
	lines.append(line.strip_edges())
	return lines


## 把一段话排进「[param room] 宽、最多 [param max_lines] 行」的框里。
##
## 返回 `{"size": 字号, "lines": 行数组}`：**先按原字号折行，行数超了才缩一号重折**，
## 一直缩到 [constant MIN_FONT] 为止。和 [method fit_size] 的分工是「散文走这个、
## 单行字走那个」—— 单行字（图名、纪录、参数行）折行没有意义，缩号才是它该干的事。
##
## 上限之外的文字会被丢掉（[method wrap] 返回的是全部行，调用方只画前 max_lines 行
## 的话就会截断），所以行数上限必须给够：卡片上每处散文的槽位高度是死的，
## 上限就是那点高度装得下的行数。
static func fit_lines(font: Font, text: String, px: int, room: float,
		max_lines: int) -> Dictionary:
	var size := px
	while size > MIN_FONT:
		var lines := wrap_lines(font, text, size, room)
		if lines.size() <= max_lines:
			return {"size": size, "lines": lines}
		size -= 1
	return {"size": MIN_FONT, "lines": wrap_lines(font, text, MIN_FONT, room)}


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
	_draw_mode()


func _draw_background() -> void:
	var w := size.x
	var h := size.y
	# draw_polygon 支持逐顶点颜色，四个点就能拉出一条竖直渐变
	draw_polygon(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM])
	)


func _draw_header() -> void:
	draw_string(_font, Vector2(60.0, 82.0), _t("选择地图", "CHOOSE A MAP"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 46, TEXT)
	# 张数是活的（[member _ids]），**不能写死「四张」** —— 加图的张数早就不止四张了，
	# 而那句话写死之后错得不显眼（说的是「一屏几张」而不是「一共几张」）。
	draw_string(_font, Vector2(60.0, 114.0),
			_t("%d 张图各有各的物理，纪录也是分开记的",
					"%d maps, each with its own physics and its own record") % _ids.size(),
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
	var m: Dictionary = Maps.get_map(id)
	var focused := i == _sel
	var hot := focused or i == _hover
	var room := r.size.x - PAD * 2.0
	var price := SaveData.map_price(id)

	draw_rect(r, CARD_SEL if focused else CARD)
	draw_rect(r, BORDER_SEL if focused else BORDER, false, 2.0)
	_draw_preview(r, m)
	# 预览的下边缘压一条暗线，让画面区和文字区分开
	draw_line(
		r.position + Vector2(0.0, PREVIEW_H),
		r.position + Vector2(r.size.x, PREVIEW_H),
		Color(0.0, 0.0, 0.0, 0.35), 2.0
	)

	var at := r.position + Vector2(PAD, 0.0)
	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_NAME), _t(m["zh"], m["en"]), 36,
			TEXT if hot else TEXT.lerp(TEXT_DIM, 0.25), room)
	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_STATS), _stats_line(m), 16, SKY, room)
	# 说明和地形说明是散文，**折行**，每处最多两行。上限是两行而不是「能折几行折几行」：
	# 卡片的高度是死的，行数一多就把下面那几行顶掉了（行距见 LINE_* 那组常量）。
	_card_para(at + Vector2(0.0, PREVIEW_H + LINE_NOTE), _t(m["zh_note"], m["en_note"]), 17,
			TEXT_DIM, room, 2, NOTE_STEP)

	var info: Dictionary = Maps.FEATURE_INFO[m["feature"]]
	_card_string(at + Vector2(0.0, PREVIEW_H + LINE_FEATURE),
			"◆ " + _t(info["zh"], info["en"]), 21, GOLD, room)
	_card_para(at + Vector2(0.0, PREVIEW_H + LINE_FEATURE_NOTE),
			_t(info["zh_note"], info["en_note"]), 15, TEXT_DIM, room, 2, FEATURE_NOTE_STEP)

	# 底：本图纪录。**锁着的图不画这一行** —— 那些图的纪录必然是 0 米
	# （[method SaveData._grandfather] 会把有成绩的图直接送出去），画出来只是一句
	# 压在暗色底下的「最远 0 m」，白占一行。
	if price <= 0:
		var random := SaveData.map_mode == Maps.MODE_RANDOM
		var best := SaveData.best_of(id)
		_card_string(at + Vector2(0.0, r.size.y - LINE_RECORD), card_record_line(id), 18,
				TEXT_DIM if random else (GOLD if best > 0 else TEXT_DIM), room)
		return

	# 锁卡：整张压暗，再盖上挂锁和价钱。**卡片本身照常画完**（预览、名字、说明），
	# 玩家得能看见自己买的是什么（见 [HillLockBadge] 的类注释）。
	HillLockBadge.dim(self, r)
	var afford := SaveData.total_coins >= price
	HillLockBadge.draw(self, _font, r,
			HillLockBadge.price_line(price, _cjk),
			HillLockBadge.hint_line(focused, afford, _cjk),
			hot,
			HillLockBadge.PRICE if afford else HillLockBadge.DENIED)


## 卡片底部那一行字：这张图的历史最远，或者（随机模式下）明说这一局不计纪录。
##
## 随机模式下换掉这句话，是因为那个数是在**另一张地形**上跑出来的（经典模式那座
## 固定的山），留在卡片上等于摆一个玩家永远追不上的目标。
##
## 抽成**纯函数**是为了能测：画的那一份和测试里断言的那一份是同一个字符串，
## 不然改了文案两边就各说各话（见 tests/random_mode）。
func card_record_line(id: String) -> String:
	if SaveData.map_mode == Maps.MODE_RANDOM:
		return _t("随机地形 · 不计纪录", "RANDOM - NO RECORD")
	return _t("本图最远 %d m", "BEST %d m") % SaveData.best_of(id)


## 卡片顶部那张地形预览：天空铺底色，再按地图的起伏倍率画一条地皮。
##
## 起伏倍率直接用 [member Maps.MAPS] 里的数，所以荒漠的包看着就比雪地大 ——
## 预览图上能直接看出「这张图颠」。
func _draw_preview(r: Rect2, m: Dictionary) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, PREVIEW_H)), m["sky"])

	var crust := _preview_wave(r, float(m["amp_scale"]))
	# 地皮 = 地表线 + 沿卡片下边闭合
	var dirt := PackedVector2Array(crust)
	dirt.append(r.position + Vector2(r.size.x, PREVIEW_H))
	dirt.append(r.position + Vector2(0.0, PREVIEW_H))
	draw_colored_polygon(dirt, m["dirt"])
	draw_polyline(crust, m["crust"], 4.0, true)


## 卡片预览里那条地表线。相位和卡宽无关，所以四张卡的山峰对得齐齐的，
## 一眼能比出谁的起伏大。
func _preview_wave(r: Rect2, amp: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var t := float(i) / float(steps)
		points.append(Vector2(
			r.position.x + t * r.size.x,
			r.position.y + PREVIEW_GROUND - sin(t * TAU * 1.5) * 17.0 * amp))
	return points


## 卡片上那行物理参数，**从数值反推**而不是写死文案 —— 改了地图数值这里自动跟上。
func _stats_line(m: Dictionary) -> String:
	var parts := PackedStringArray()
	var amp := float(m["amp_scale"])
	if not is_equal_approx(amp, 1.0):
		parts.append(_t("起伏 ×%.2f", "HILLS x%.2f") % amp)
	var friction := float(m["friction_scale"])
	if not is_equal_approx(friction, 1.0):
		parts.append(_t("抓地 ×%.2f", "GRIP x%.2f") % friction)
	var drag := float(m["drag"])
	if drag > 0.0:
		parts.append(_t("阻力 +%.1f", "DRAG +%.1f") % drag)
	var fuel := float(m["fuel_scale"])
	if not is_equal_approx(fuel, 1.0):
		parts.append(_t("油耗 ×%.2f", "FUEL x%.2f") % fuel)
	if parts.is_empty():
		return _t("标准物理", "STANDARD PHYSICS")
	return "  ".join(parts)


## 左右两个翻页箭头。**只在真的还有窗口外的图时才画** —— 图比一屏少的时候画出来
## 是个按了没反应的按钮。
func _draw_arrows() -> void:
	if _ids.size() <= VISIBLE:
		return
	_arrow(_arrow_pos(-1), -1)
	_arrow(_arrow_pos(1), 1)


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


## 卡片下面那排圆点：一共几张图、此刻窗口盖住了哪几张、光标在哪一张。
##
## 圆点数 = 图的张数（十二张时十二个点，一排 204 像素，放得下）。
func _draw_dots() -> void:
	var n := _ids.size()
	if n <= 1:
		return
	var y := DOT_Y
	var x0 := size.x * 0.5 - DOT_STEP * float(n - 1) * 0.5
	for i in range(n):
		var at := Vector2(x0 + DOT_STEP * float(i), y)
		var slot := _slot_of(i)
		# 亮起来要同时满足两件事：这一格在窗口里，**而且这张图是通的**。锁住的图
		# 退回「窗口外」那一档的暗色，于是一排点里一眼能看出后面几页还没买。
		var lit := slot >= 0 and slot < VISIBLE and SaveData.map_unlocked(_ids[i])
		if i == _sel:
			draw_circle(at, DOT_R + 1.5, GOLD)
		elif lit:
			draw_circle(at, DOT_R, SKY)
		else:
			draw_circle(at, DOT_R - 1.5, Color(TEXT_DIM, 0.45))
	var counter := _t("%d / %d 张", "%d / %d") % [_sel + 1, n]
	draw_string(_font, Vector2(0.0, y + 7.0), counter, HORIZONTAL_ALIGNMENT_RIGHT,
			size.x * 0.5 - DOT_STEP * float(n) * 0.5 - 16.0, 17, TEXT_DIM)


## 页脚。**三行，从下往上摞**：键位提示 / 当前模式的说明 / （锁着的图还在时）怎么买。
##
## 模式那一行**常驻**，因为它是唯一一处告诉玩家「随机模式不算成绩」的地方 ——
## 玩家在选图页把开关拨过去，成本是整局的时间，不能让他进图之后才发现纪录没了。
func _draw_footer() -> void:
	var y := size.y - 26.0
	draw_string(_font, Vector2(60.0, y),
			_t("← → 翻页    回车 / 点击 确定    Tab 换模式    Esc 回车库",
				"LEFT/RIGHT browse    ENTER / CLICK pick    TAB mode    ESC garage"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM)
	var note: Dictionary = Maps.mode_note(SaveData.map_mode)
	draw_string(_font, Vector2(60.0, y - 26.0), _t(note["zh"], note["en"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			SKY if SaveData.map_mode == Maps.MODE_RANDOM else TEXT_DIM)
	if _locked_count() > 0:
		draw_string(_font, Vector2(60.0, y - 52.0),
				_t("锁住的图点一下选中、再点一下花 %d 金币买下" % Maps.UNLOCK_PRICE,
						"locked maps: tap to select, tap again to buy for %d coins"
								% Maps.UNLOCK_PRICE),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)


## 页脚右下角那两格模式开关。亮着的那一格 = 这一局会用的模式。
##
## 天蓝（[constant SKY]）标当前那一格，和卡片用 [constant BORDER_SEL] 标光标是同一套
## 语言：**这一页上「蓝边 = 你选的那个」**。
func _draw_mode() -> void:
	var slot_now := _mode_slot()
	for slot in Maps.MODES.size():
		var r := mode_rect(slot)
		var on := slot == slot_now
		var hot := on or slot == _mode_hover
		draw_rect(r, CARD_SEL if on else CARD)
		draw_rect(r, BORDER_SEL if on else BORDER, false, 2.0 if on else 1.0)
		var label: Dictionary = Maps.mode_label(Maps.MODES[slot])
		draw_string(_font, Vector2(r.position.x, r.position.y + MODE_H * 0.68),
				_t(label["zh"], label["en"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20,
				TEXT if hot else TEXT_DIM)


## 还有几张图没解锁。只为页脚那一行要不要画。
func _locked_count() -> int:
	var out := 0
	for id in _ids:
		if not SaveData.map_unlocked(id):
			out += 1
	return out
