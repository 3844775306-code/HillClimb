extends Control
class_name HillDashboard
## 右下角的仪表盘：一个车速表、一个轮速表，都有刻度和指针。
##
## **自己一个节点，不塞进 [HillHud] 的 `_draw` 里。** HUD 是事件驱动的 —— 只在
## 飘字计时器变化时才 [method CanvasItem.queue_redraw]，平时一帧都不重画；表针每帧
## 都在动，混进去就等于把整个 HUD（十来条 `draw_string`）拖成 60 fps 重画。
## 代价是两处都有一份配色常量，见 [constant PANEL_BG] 那段。
##
## 两个表的量程**跟着车走**，不是写死的数 —— 见 [method _measure_dials]。
##
## 轮速表有什么用：车速表告诉你跑多快，轮速表告诉你**轮子在不在打滑**。沙地、冰面、
## 或者顶着一块石头空转时，轮速表顶到头而车速表趴在下面 —— 一眼就知道是动力没传下去，
## 不是车没劲。两个表读数都高才是真的在飞。

## 和 [HillHud] 里那几个同色。**故意抄一份而不是引用 `HillHud.PANEL_BG`**：
## `hud.gd` 要用 `HillDashboard.new()` 建这个节点，这边再去引用 `HillHud` 的常量
## 就成了两个脚本互相依赖，GDScript 对循环引用是要报错的。四个颜色抄一份，比
## 让运行时炸掉划算。改配色时两处一起改。
const PANEL_BG := Color(0.07, 0.09, 0.13, 0.55)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.97, 0.98, 1.0, 0.72)
const SKY := Color(0.62, 0.90, 1.0)
const GOLD := Color(1.0, 0.84, 0.24)
## 表盘底色。比 [constant PANEL_BG] 厚一点：刻度是细线，飘在云上会糊。
const DIAL_BG := Color(0.06, 0.08, 0.12, 0.72)
## 指针。和结束面板的「翻车了！」同色 —— 这一版配色里红的就是「要紧的东西」。
const NEEDLE := Color(1.0, 0.42, 0.32)

## 表盘半径。
const RADIUS := 78.0
## 两个表盘之间的间距。
const GAP := 26.0
## 表盘底边离屏幕底边的距离。要**同时**让开左下角的油条（它在 `size.y - 60` 那一行）
## 和右下角的道具栏（`size.y - 54` 起，标签还要再往上 12）。100 是这两者里更紧的那个
## 加一圈余量。
const BOTTOM_MARGIN := 100.0
## 表盘右边离屏幕右边的距离，和 HUD 顶栏的地图名对齐（那边也是 30）。
const SIDE_MARGIN := 30.0
## 表名那一条占多高（字号 + 和表盘的间隔）。
const TITLE_BAND := 28.0
## 几个表盘。0 号是车速表、1 号是轮速表，见 [method center_of]。
const SLOTS := 2

## 指针的起止角（度）。屏幕坐标系 y 朝下，所以**正角度是顺时针**。
##
## 从 150°（左下）顺时针扫 240° 到 30°（右下），是标准车速表的摆法：下半圈留给
## 表名和数字读数，指针只在上半圈里跑，中间那块地方永远不会被针尖扫到。
const START_DEG := 150.0
const SWEEP_DEG := 240.0
## 指针长度（半径的比例），以及尾巴越过圆心多少 —— 有一点尾巴才看得出是绕圆心转的。
const NEEDLE_LEN := 0.86
const NEEDLE_TAIL := 0.13

## 刻度：大刻度每这么多一格、带数字，小刻度是它的一半或四分之一。
## 量程会被向上取整成大刻度的整数倍（见 [method dial_max]），所以最后一格一定是整格。
const SPEED_MAJOR := 100.0
const SPEED_MINOR := 25.0
const RPM_MAJOR := 200.0
const RPM_MINOR := 50.0

const TITLE_SIZE := 20
const TICK_SIZE := 17
const VALUE_SIZE := 30
const UNIT_SIZE := 18

## 表针追得有多快（1/秒）。指数逼近：每帧走 `1 - exp(-k·dt)`，和相机那边一个写法。
##
## 不追不行 —— 物理速度逐帧都在抖，直接拿它画指针，指针会抖成一片噪点。
## 14 是「看着还是即时」和「不抖」之间的折中：60 fps 下 0.17 秒追上 90%。
const NEEDLE_FOLLOW := 14.0
## 差值小于这个就直接归位。指数逼近永远差那么一点点，针停在离零一像素的地方
## 不动，比不动还难看。
const NEEDLE_SNAP := 0.0015

var _car: HillCar
var _font: Font
var _cjk := false
## 表盘底边离屏幕底边多远。桌面版面就是 [constant BOTTOM_MARGIN]（让开左下角的
## 油条和右下角的道具栏）；手机版面由 [method setup] 按踏板高度顶上去。
var _bottom_margin := BOTTOM_MARGIN
## 两个表的量程（km/h 和 rpm）。[method setup] 里按车算一次，见 [method _measure_dials]。
var _dial_speed := 500.0
var _dial_rpm := 600.0
## 表针当前的位置（0~1 的比例），是**追**出来的，不是直接读物理值。
var _needle_speed := 0.0
var _needle_rpm := 0.0


## [param font] 由 [HillHud] 传进来，不在这里自己 [`UiFonts.load_cjk_font`]：
## 那个函数要读几 MB 的系统字体文件，一局里加载两遍纯属浪费。
##
## [param touch] 为真时（手机版面）整组表盘往上抬到踏板上面，见 [member _bottom_margin]。
func setup(car: HillCar, font: Font, cjk: bool, touch: bool = false) -> void:
	_car = car
	_font = font
	_cjk = cjk
	# **这个数从踏板那边推，不在两个文件里各写一遍**：踏板改大改小，
	# 这里跟着动，不会出现「踏板长大了、表盘还留在原地被压住」。
	_bottom_margin = HillTouchControls.bottom_inset() + 12.0 if touch else BOTTOM_MARGIN
	_needle_speed = 0.0
	_needle_rpm = 0.0
	_measure_dials()


func _process(delta: float) -> void:
	if _car == null:
		return
	var k := 1.0 - exp(-NEEDLE_FOLLOW * delta)
	_needle_speed = _follow(_needle_speed, speed_ratio(), k)
	_needle_rpm = _follow(_needle_rpm, rpm_ratio(), k)
	queue_redraw()


func _draw() -> void:
	if _car == null:
		return
	_draw_gauge(0, _needle_speed, _dial_speed, _t("车速", "SPEED"), "km/h",
			SPEED_MAJOR, SPEED_MINOR, SKY)
	_draw_gauge(1, _needle_rpm, _dial_rpm, _t("轮速", "WHEELS"), "rpm",
			RPM_MAJOR, RPM_MINOR, GOLD)


# ------------------------------------------------------------ 读数

## 车速（km/h）。
##
## 取速度的**大小**：倒车时指针也往正方向走。表盘是从 0 起、只有正刻度的，
## 让针往不存在的负刻度那边甩，除了吓人没别的用。
static func speed_kmh_of(velocity: Vector2) -> float:
	return velocity.length() / Maps.PIXELS_PER_METER * 3.6


## 角速度（弧度/秒）换算成每分钟转数。
static func rpm_of(omega: float) -> float:
	return omega * 60.0 / TAU


func speed_ratio() -> float:
	if _car == null or _dial_speed <= 0.0:
		return 0.0
	return clampf(speed_kmh_of(_car.chassis.linear_velocity) / _dial_speed, 0.0, 1.0)


func rpm_ratio() -> float:
	if _car == null or _dial_rpm <= 0.0:
		return 0.0
	# 所有轮子**都是驱动轮**，转速基本一样（实测满油门 407 / 411 rpm），取平均。
	# 取最大的那个会在独轮时虚高：抬起来的那个轮子空转，读数是它自己的，不是车的。
	#
	# 走 [member HillCar.wheels] 而不是那两个别名：独轮车上两个别名是同一个轮子，
	# 写成 `(rear + front) * 0.5` 恰好也等于它自己的转速、结果没错，但那是**碰巧**
	# —— 读起来像在平均两个轮子，其实一个轮子被念了两遍。
	var omega := 0.0
	if not _car.wheels.is_empty():
		for wheel in _car.wheels:
			omega += absf(wheel.angular_velocity)
		omega /= float(_car.wheels.size())
	return clampf(rpm_of(omega) / _dial_rpm, 0.0, 1.0)


# ------------------------------------------------------------ 量程

## 表盘量程：把**轮子空转能到的极限**向上取整到 [param step] 的整数倍。
##
## 为什么不写死一个数：车是活的 —— [Upgrades] 的极速一项会直接乘
## `car.max_wheel_speed`（满级 ×1.263），四辆车的轮径也各不相同（21 / 20 / 23）。
## 写死 300 的话，满级赛车一起步表针就顶死了。
##
## 为什么不用「实测跑到的最高速」：那是地形和抓地力的函数，同一辆车在雪地和在
## 山地能差一倍，拿它定量程等于每张图都得重标。而**空转极限是物理上的天花板** ——
## 马达把轮子往 `max_wheel_speed` 拽，氮气再把目标抬 [constant Items.NITRO_SPEED] 倍，
## 车不可能比这个还快（被撞飞的那一瞬间除外，那也不该是表盘的设计输入）。
## 指针只要不到 100%，表盘就一定够用。
##
## 默认车 Lv0：50 × 1.25 × 21 ÷ 10 × 3.6 = 472.5 km/h → 500；
## 极速满级：×1.263 → 596.8 → 600。
static func dial_max(raw: float, step: float) -> float:
	return maxf(step, ceilf(raw / step) * step)


## 轮半径。**读碰撞形状，不读车上的导出变量** —— 真正决定「轮子转一圈走多远」的是
## 碰撞圆，[method Vehicles.stats] 取的也是同一个。
##
## 找法是把 `car` 的直接子节点扫一遍，取第一个带 [constant Vehicles.WHEEL_GROUP] 标记的
## 那个（场景里后轮在前，所以拿到的就是后轮）。**这里以前走的是一条写死的绝对路径**
## （`RearWheel/Shape`）：独轮车那种只有一个轮子的车未必还叫这个名字，写死就等于
## 量程**静默**退化成兜底值。
##
## 不走 `car.wheels` / `car.rear_wheel`：那些是 [`@onready`]，只有进过树才有值，而这些数
## 在 [method setup] 里就要用（测试里更是不想让车进树，见 tests/dashboard）。
## 分组标记是实例化时就挂上的，不进树一样读得到。
static func wheel_radius_of(car: HillCar) -> float:
	for child in car.get_children():
		var wheel := child as RigidBody2D
		if wheel == null or not wheel.is_in_group(Vehicles.WHEEL_GROUP):
			continue
		var node := wheel.get_node_or_null("Shape")
		if node is CollisionShape2D and (node as CollisionShape2D).shape is CircleShape2D:
			return ((node as CollisionShape2D).shape as CircleShape2D).radius
	# 兜底是默认车（car.tscn）的轮半径。走到这里说明场景被改坏了（轮子没打分组标记、
	# 或者形状不是圆），别静默当成 0 —— 0 会让量程退化成「一格」，表针永远贴边。
	push_warning("读不到 %s 的轮半径，轮速表按默认车的 21 px 算。" % car.name)
	return 21.0


## 量程跟着车走，所以 [method setup] 里按**已经升过级**的车算一次 —— 升级是在
## [method HillCar._ready] 里乘上去的，HUD 的 `setup` 排在它后面，拿到的准是升级后的值。
func _measure_dials() -> void:
	if _car == null:
		return
	var radius := wheel_radius_of(_car)
	var wheel_max: float = _car.max_wheel_speed * Items.NITRO_SPEED
	# 轮面线速度 → m/s → km/h
	_dial_speed = dial_max(wheel_max * radius / Maps.PIXELS_PER_METER * 3.6, SPEED_MAJOR)
	_dial_rpm = dial_max(rpm_of(wheel_max), RPM_MAJOR)


# ------------------------------------------------------------ 几何

## 第 [param slot] 个表盘的圆心。0 = 车速表（左），1 = 轮速表（右）。
##
## 整块从右下角往回排，所以窗口一变形状它自己就跟着挪，不用谁去通知。
func center_of(slot: int) -> Vector2:
	var rightmost := size.x - SIDE_MARGIN - RADIUS
	var x := rightmost - float(SLOTS - 1 - slot) * (RADIUS * 2.0 + GAP)
	return Vector2(x, size.y - _bottom_margin - RADIUS)


## 整块仪表盘占的矩形（含表名那一条）。给版面测试用。
func cluster_rect() -> Rect2:
	var left := center_of(0).x - RADIUS
	var right := center_of(SLOTS - 1).x + RADIUS
	var top := center_of(0).y - RADIUS - TITLE_BAND
	return Rect2(left, top, right - left, center_of(0).y + RADIUS - top)


## 比例（0~1）对应的指针角度（弧度）。超出范围就**钉在两端**，不绕圈 ——
## 指针顶到头是「爆表了」的意思，绕回 0 会让人以为车停了。
static func angle_for(ratio: float) -> float:
	return deg_to_rad(START_DEG + SWEEP_DEG * clampf(ratio, 0.0, 1.0))


## 指针尖端的坐标。
static func tip_of(center: Vector2, radius: float, ratio: float) -> Vector2:
	return center + Vector2.RIGHT.rotated(angle_for(ratio)) * radius * NEEDLE_LEN


# ------------------------------------------------------------ 画

func _draw_gauge(slot: int, ratio: float, dial: float, title: String, unit: String,
		major: float, minor: float, tint: Color) -> void:
	var c := center_of(slot)
	draw_circle(c, RADIUS, DIAL_BG)
	# 外圈：只画有刻度的那 240°，剩下那 120° 是敞口的 —— 敞口朝下，正好让
	# 表名和数字读数有个进出口。
	draw_arc(c, RADIUS, deg_to_rad(START_DEG), deg_to_rad(START_DEG + SWEEP_DEG),
			64, Color(tint.r, tint.g, tint.b, 0.55), 3.0, true)

	# 刻度。`minor` 必须整除 `major`，`major` 必须整除量程（[method dial_max] 保证）。
	var per_major := int(major / minor)
	var ticks := int(dial / minor) + 1
	for i in ticks:
		var v := float(i) * minor
		var dir := Vector2.RIGHT.rotated(angle_for(v / dial))
		var is_major := i % per_major == 0
		var inner := RADIUS - (16.0 if is_major else 9.0)
		draw_line(c + dir * inner, c + dir * (RADIUS - 4.0), TEXT if is_major else TEXT_DIM,
				2.5 if is_major else 1.5)
		if is_major:
			_draw_tick_label(c + dir * (inner - 15.0), str(int(v)))

	_draw_needle(c, ratio)
	_draw_readout(c, ratio, dial, title, unit, tint)


## 大刻度的数字。`at` 是这一格的**中心**，不是基线 —— 和金币上的面额一个道理
## （见 [method Pickup._draw_coin]）：`draw_string` 的 y 是基线，减掉半个 ascent 才摆正。
func _draw_tick_label(at: Vector2, text: String) -> void:
	if _font == null:
		return
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TICK_SIZE)
	draw_string(_font, at + Vector2(-extent.x * 0.5, _font.get_ascent(TICK_SIZE) * 0.5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, TICK_SIZE, TEXT)


func _draw_needle(c: Vector2, ratio: float) -> void:
	var dir := Vector2.RIGHT.rotated(angle_for(ratio))
	var side := dir.orthogonal()
	var half := RADIUS * 0.055
	var tip := c + dir * (RADIUS * NEEDLE_LEN)
	var back := c - dir * (RADIUS * NEEDLE_TAIL)
	draw_colored_polygon(PackedVector2Array([tip, back + side * half, back - side * half]),
			NEEDLE)
	draw_circle(c, RADIUS * 0.11, Color(0.09, 0.11, 0.16))
	draw_circle(c, RADIUS * 0.055, NEEDLE)


## 表名 + 数字读数 + 单位。
##
## 数字摆在**圆心下方**而不是表格子中间：指针扫的是上面那 240°，正下方这一块
## （大概 30°~150° 之间）是指针永远到不了的地方，空着也是空着。
func _draw_readout(c: Vector2, ratio: float, dial: float, title: String, unit: String,
		tint: Color) -> void:
	if _font == null:
		return
	draw_string(_font, Vector2(c.x - 100.0, c.y - RADIUS - 8.0), title,
			HORIZONTAL_ALIGNMENT_CENTER, 200.0, TITLE_SIZE, TEXT_DIM)
	var value := "%d" % int(round(ratio * dial))
	var extent := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_SIZE)
	draw_string(_font, c + Vector2(-extent.x * 0.5, RADIUS * 0.50), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_SIZE, TEXT)
	var unit_extent := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_SIZE)
	draw_string(_font, c + Vector2(-unit_extent.x * 0.5, RADIUS * 0.50 + 22.0), unit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_SIZE, tint)


func _t(zh: String, en: String) -> String:
	return zh if _cjk else en


## 指数逼近，[param k] 是这一帧该走的比例。
##
## 差值小到看不出来时**直接归位**：指数逼近永远差那么一点点，针停在离零一个像素
## 的地方微微发抖，比不动还显眼。[constant NEEDLE_SNAP] 这个门槛按「比例」算，
## 换算到读数上大约是 0.15%（车速表 0.75 km/h），肉眼看不出跳变。
static func _follow(cur: float, want: float, k: float) -> float:
	if absf(want - cur) < NEEDLE_SNAP:
		return want
	return cur + (want - cur) * k
