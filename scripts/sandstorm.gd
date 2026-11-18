extends HillFeature
## 沙尘暴：一段持续把车往回推的风区。**不挖地形**，纯粹是加在空中的力。
##
## ## 力为什么要去重
##
## 车是三个同级刚体（车壳 + 两个轮子），[method Area2D.get_overlapping_bodies]
## 会把三个都报上来。照着列表一个个 `apply_central_force` 的话，风会是设计值的
## 三倍，而且车壳和轮子分别受力还会额外产生扭矩把车吹翻。所以这里先按「哪辆车」
## 去重，一股风只加在车壳上一次，再靠关节把轮子一起拖住。
##
## ## 力度是量出来的，不是猜的
##
## 车壳质量 130，[constant WIND_FORCE] 除以它就是这个风区里的减速度。
## 实测见 tests/hazards —— 目标手感是「明显被拖慢、但不至于推回去」：
## 满油门穿过风区应该掉速，但仍在前进。调大会变成原地不动甚至倒退。
##
## ## 视觉分三层
##
## 一层平面色块加几条等宽直线，看着像起雾的玻璃，不像风。所以画面拆成三层，
## 靠 `z_index` 分工（区块节点的 z 是 0，车的 z 是 1）：
##
##   远处（z = −1）  一整片沙色，**下浓上淡、左右两头淡出**，随风的强弱一起浓淡
##   中景（z = 0）   十几条被风拉长的沙线，有的压在土坡前、有的贴着地刮
##   近处（z = 2）   两三条又短又快、从车头前面扫过去的沙线
##
## 贴地那层沙团由本节点自己的 [method _draw] 画，也是 z = 0，但**落在中景沙线之后**
## （父节点先画、孩子后画）—— 慢的在后、快的在前，深度的错觉就出来了。
##
## ## 一阵一阵
##
## [member _gust] 是两个正弦叠出来的风势，乘在**速度、透明度、沙团生成率**上。
## 恒定的风看着像贴图在平移，有起伏才像风。
##
## **它只乘视觉，不乘力。** [constant WIND_FORCE] 是量出来的常数：让它随时间抖，
## 手感就变成随机数，那套 A/B 标定（开风/关风各跑一趟比车速）也就白做了。

## 作用在车壳上的横向风力（牛顿）。方向是 −x，也就是顶风。
##
## **除法要用整辆车的质量，不是车壳的。** 力只加在车壳上，但轮子是被关节拖着
## 走的，稳态下整辆车（174）一起加速，所以减速度是 WIND_FORCE / 174。
## 实测（tests/hazards 的 F 节）：45000 → −255.6 px/s²（设计值 −258.6）。
##
## 手感靠 A/B 量：同一段路开风 / 关风各跑一次，比到风区右沿时的车速。
## 45000 时只慢 15%，偏弱 —— 车在风里还是照常加速，只是慢一点。80000
## （≈460 px/s²）大约吃掉一半推力，看得出被顶住，又不至于走不动。
const WIND_FORCE := 80000.0

## 风区从地表往上多高（像素）。风口要盖住车飞起来的高度，不然跳一下就没有风了。
const WIND_TOP := 620.0
## 往下探多少。车挂在坑里、或者翻到地表以下时也该继续吹。
const WIND_BELOW := 120.0

## 中景沙线的条数，以及它们的速度区间（像素/秒）。
const STREAKS := 14
const STREAK_SPEED_MIN := 260.0
const STREAK_SPEED_MAX := 520.0
## 近景沙线（从车头前面扫过去的那几条）：条数少、速度高、身长短。
const NEAR_STREAKS := 3
const NEAR_SPEED_MIN := 640.0
const NEAR_SPEED_MAX := 940.0
## 绕回右侧时速度在这个倍率区间里重掷，免得看久了看出循环。
const SPEED_REROLL := Vector2(0.75, 1.25)

## 沙色。**alpha 由顶点色 / `modulate` 现算**，所以这两个常量只给色相和饱和度。
const SAND_COLOR := Color(0.78, 0.64, 0.36)
const STREAK_COLOR := Color(0.90, 0.80, 0.58)

## 风区左右两端各淡出多少（占宽度的比例）。硬邦邦的矩形边会让「进风区」
## 像一头撞上一堵墙 —— 沙线在两端淡入淡出，进出就是渐渐的了。
const EDGE_FADE := 0.16
## 整片沙的厚度（透明度），以及上沿相对地面的浓度。
## 沙是贴着地刮起来的，所以底下最浓，到顶几乎看不见。
const HAZE_ALPHA := 0.34
const HAZE_TOP_RATIO := 0.10
## 那片沙横竖各切几格。横着 3 段正是「左淡出 / 中间实 / 右淡出」；
## 竖着切 6 段是为了让上下渐变真的是渐变，而不是几层看得出来的台阶。
const HAZE_SEGS := 3
const HAZE_BANDS := 6

## 贴地沙团：池子大小、每秒生几颗（还要乘风势）、寿命、速度、基础半径。
const PUFFS := 64
const PUFF_RATE := 16.0
const PUFF_LIFE_MIN := 0.9
const PUFF_LIFE_MAX := 2.2
const PUFF_SPEED_MIN := 180.0
const PUFF_SPEED_MAX := 380.0
const PUFF_SIZE := 9.0
const PUFF_ALPHA := 0.30
## 沙团边飘边散开，所以半径越老越大。
const PUFF_GROW := 1.9

var _area: Area2D
## 远处那片沙的父节点。风势只动它的 `modulate.a` —— 一处属性，十几个格子一起变，
## 拼好的顶点色不用重建。
var _haze: Node2D
var _streaks: Array[Line2D] = []
var _speeds: Array[float] = []
## 每条沙线绕回右侧时重掷速度的基准值（近景线比中景线快一大截，重掷要按各自的比例）。
var _nominal: Array[float] = []
## 抖动：基准高度、频率、幅度。三点正弦一叠，沙线就不是走直线了。
var _bases: Array[float] = []
var _freqs: Array[float] = []
var _amps: Array[float] = []

var _puffs: Array[Puff] = []
var _emit := 0.0
var _rng := RandomNumberGenerator.new()
## 风势的错相位。按区块位置错开，否则一整排区块会一起喘气，像整个屏幕在闪。
var _phase := 0.0
var _time := 0.0
## 当前风势，0.35～1.5。只乘视觉，不乘力。
var _gust := 1.0


## 一颗贴地被卷起来的沙团。字段和 [Grain]（effects.gd）一个路子：
## 位置、速度、寿命、半径，外加一个明暗抖动 —— 一片沙团全是一个纯色，
## 看上去像一块块的贴纸。
class Puff:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var span := 0.0
	var size := 1.0
	var tint := 1.0


func _build() -> void:
	var left := span.position.x
	var width := span.size.x
	if width <= 0.0:
		return
	_phase = float(int(left)) * 0.013
	_rng.seed = int(left)

	_build_area(left, width)
	_build_haze(left, width)
	_build_streaks(left, width, false)
	_build_streaks(left, width, true)


## 风力区。**改视觉时这一块不能跟着动**：它的尺寸决定车在哪儿被吹到，
## tests/hazards 的 E 组就是拿它做 A/B 的（同一段路开风/关风各跑一趟比车速）。
func _build_area(left: float, width: float) -> void:
	_area = Area2D.new()
	_area.name = "Wind"
	_area.collision_layer = 0
	_area.collision_mask = 1
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, WIND_TOP + WIND_BELOW)
	cs.shape = box
	_area.add_child(cs)
	_area.position = Vector2(
		left + width * 0.5,
		rim_y - (WIND_TOP - WIND_BELOW) * 0.5,
	)
	add_child(_area)


## 远处那片沙：横 3 段 × 竖 6 格的四边形拼出来，**每个顶点一个透明度**。
##
## 用顶点色而不是整块一个 `color`：顶点色会在格子之间插值，于是「下浓上淡、
## 两头淡出」是一条连续的渐变；整块一个色只能得到一块平的半透明 —— 那正是
## 原来看着像雾的原因。
##
## 拼完就不再重建，风势只动 [member _haze] 的 `modulate.a`。
func _build_haze(left: float, width: float) -> void:
	_haze = Node2D.new()
	_haze.name = "Haze"
	_haze.z_index = -1
	add_child(_haze)

	var bottom := rim_y + WIND_BELOW
	var top := rim_y - WIND_TOP
	var xs: Array[float] = []
	var hs: Array[float] = []
	for c in HAZE_SEGS + 1:
		var t := float(c) / float(HAZE_SEGS)
		xs.append(left + width * t)
		hs.append(_edge_fade(t))
	var ys: Array[float] = []
	var vs: Array[float] = []
	for r in HAZE_BANDS + 1:
		var t := float(r) / float(HAZE_BANDS)      # 0 是地面那一条，1 是顶
		ys.append(lerpf(bottom, top, t))
		# 0.7 次幂：底部那一带的浓度变化慢，快到顶才迅速淡掉，
		# 这样贴地那层看得见「厚」，而上半部分又是干净的。
		vs.append(lerpf(1.0, HAZE_TOP_RATIO, pow(t, 0.7)))

	for r in HAZE_BANDS:
		for c in HAZE_SEGS:
			var quad := Polygon2D.new()
			quad.polygon = PackedVector2Array([
				Vector2(xs[c], ys[r]), Vector2(xs[c + 1], ys[r]),
				Vector2(xs[c + 1], ys[r + 1]), Vector2(xs[c], ys[r + 1]),
			])
			var alphas: Array[float] = [
				hs[c] * vs[r], hs[c + 1] * vs[r],
				hs[c + 1] * vs[r + 1], hs[c] * vs[r + 1],
			]
			var cols := PackedColorArray()
			for k in 4:
				var col := SAND_COLOR
				col.a = HAZE_ALPHA * alphas[k]
				cols.append(col)
			quad.vertex_colors = cols
			_haze.add_child(quad)


## 沙线。`near` 为真时是画在车**前面**的那几条：更短、更快、更淡 ——
## 有它们，车才像是开在沙里，而不是开在一张沙的布景前面。
func _build_streaks(left: float, width: float, near: bool) -> void:
	var count := NEAR_STREAKS if near else STREAKS
	var lo := NEAR_SPEED_MIN if near else STREAK_SPEED_MIN
	var hi := NEAR_SPEED_MAX if near else STREAK_SPEED_MAX
	var taper := _taper()
	var bounds := Vector2(60.0, 150.0) if near else Vector2(90.0, 260.0)

	for i in count:
		var line := Line2D.new()
		line.name = ("Near%d" if near else "Streak%d") % i
		line.width = 1.6 if near else 2.4
		line.width_curve = taper
		line.antialiased = true
		line.default_color = STREAK_COLOR
		line.z_index = 2 if near else 0

		# 一条沙线是**三段**而不是两点：中间那点抬高一点就成了微微的弧，
		# 像被风搅起来的一缕。两点只能画直线，十几条直线排在一起就是雨丝。
		var len := _rng.randf_range(bounds.x, bounds.y)
		var dy := _rng.randf_range(-10.0, 16.0)
		var bow := _rng.randf_range(-7.0, 7.0)
		line.points = PackedVector2Array([
			Vector2.ZERO,
			Vector2(len * 0.5, dy * 0.5 + bow),
			Vector2(len, dy),
		])

		var y := rim_y - _rng.randf_range(-WIND_BELOW, WIND_TOP)
		line.position = Vector2(_rng.randf_range(left, left + width), y)
		add_child(line)

		_streaks.append(line)
		var speed := _rng.randf_range(lo, hi)
		_speeds.append(speed)
		_nominal.append(speed)
		_bases.append(y)
		_freqs.append(_rng.randf_range(0.4, 1.9))
		_amps.append(_rng.randf_range(4.0, 15.0))


## 沙线的粗细剖面：两头细、中间稍粗。十几条一样粗的直线排在一起就是雨丝，
## 这个剖面是「像沙不像雨」的关键。所有沙线共用一条（只读）。
static func _taper() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(0.45, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	return curve


## 风区里横向位置的淡入淡出系数：两端各 [constant EDGE_FADE] 那一段由 0 升到 1，
## 中间恒为 1。沙线、沙团、整片沙都用它，进出风区于是是同一个节奏。
static func _edge_fade(t: float) -> float:
	return smoothstep(0.0, EDGE_FADE, t) * smoothstep(0.0, EDGE_FADE, 1.0 - t)


## 风势：慢的一段是「大风小风」，快的一段是「一阵一阵」。
##
## 两个正弦的频率比刻意取成不整的（0.55 与 2.7），两个周期不会很快对齐，
## 于是「咕——呼——咕——呼」听着不像节拍器。
func _gust_at(t: float) -> float:
	var v := 0.78 + 0.30 * sin(t * 0.55 + _phase) + 0.14 * sin(t * 2.7 + _phase * 1.7)
	return clampf(v, 0.35, 1.5)


func _physics_process(_delta: float) -> void:
	if _area == null:
		return
	for body in _area.get_overlapping_bodies():
		var car := car_of(body)
		# 只在车壳上使一次劲；轮子会经关节被一起带走。见文件头。
		if car != null and car.alive and body == car.chassis:
			car.chassis.apply_central_force(Vector2(-WIND_FORCE, 0.0))


## 沙线往左飘、上下抖；沙团生成、飘散；整片沙随风的强弱浓淡。
##
## 移动的是**节点位置**而不是 `points`：[Line2D] 的折点是相对自身的，所以改
## `position` 就够了。改 points 也行，但那是每帧重建一个 PackedVector2Array
## 再上传，而且 `points[i].x -= x` 这种「取下标、改成员、写回」的写法在 Packed
## 数组上历来是出问题的地方，不值得为省一个字段去踩。
func _process(delta: float) -> void:
	if _streaks.is_empty():
		return
	_time += delta
	_gust = _gust_at(_time)

	var left := span.position.x
	var right := left + span.size.x
	var width := maxf(1.0, span.size.x)
	var lit := clampf(_gust * 0.9, 0.0, 1.0)

	for i in _streaks.size():
		var line := _streaks[i]
		line.position.x -= _speeds[i] * _gust * delta
		line.position.y = _bases[i] + sin(_time * _freqs[i] + float(i)) * _amps[i]
		if line.position.x + line.points[2].x < left:
			# 从右边绕回来，换个高度、换个速度 —— 每次都一样的话，看久了能看出循环。
			_bases[i] = rim_y - _rng.randf_range(-WIND_BELOW, WIND_TOP)
			line.position = Vector2(right, _bases[i])
			_speeds[i] = _nominal[i] * _rng.randf_range(SPEED_REROLL.x, SPEED_REROLL.y)
		var t := clampf((line.position.x - left) / width, 0.0, 1.0)
		line.modulate.a = lit * _edge_fade(t)

	_step_puffs(delta)

	# 整片沙跟着风势浓淡。变化幅度压得比沙线小：它是「远处的背景」，
	# 跟着一起大幅闪会像有人在调亮度。
	if _haze != null:
		_haze.modulate.a = clampf(0.72 + 0.5 * (_gust - 1.0), 0.45, 1.0)
	queue_redraw()


# ---------------------------------------------------------------- 贴地沙团

func _step_puffs(delta: float) -> void:
	# 生成率乘风势：风大的时候沙子才被卷得多。攒够一整颗才生，
	# 所以 `_gust` 是随帧率无关的小数也没关系。
	_emit += PUFF_RATE * _gust * delta
	while _emit >= 1.0:
		_emit -= 1.0
		_spawn_puff()

	var left := span.position.x
	var width := maxf(1.0, span.size.x)
	for p in _puffs:
		if p.life <= 0.0:
			continue
		p.life -= delta
		# 先减速再走，顺序反了会多走一帧满速
		p.vel *= 1.0 - minf(1.0, 1.3 * delta)
		p.pos += p.vel * delta
		# 被风托着往上抬一点，落到地面以下就拽住 —— 沙团不该钻到地里去
		p.vel.y -= 26.0 * delta
		p.pos.y = minf(p.pos.y, rim_y + 6.0)
		p.pos.x = clampf(p.pos.x, left, left + width)


func _spawn_puff() -> void:
	var p := _take_puff()
	if p == null:
		return
	p.pos = Vector2(
		_rng.randf_range(span.position.x, span.position.x + span.size.x),
		rim_y + _rng.randf_range(-24.0, 4.0),
	)
	p.vel = Vector2(
		-_rng.randf_range(PUFF_SPEED_MIN, PUFF_SPEED_MAX),
		_rng.randf_range(-30.0, 10.0),
	)
	p.life = _rng.randf_range(PUFF_LIFE_MIN, PUFF_LIFE_MAX)
	p.span = p.life
	p.size = PUFF_SIZE * _rng.randf_range(0.6, 1.4)
	p.tint = _rng.randf_range(0.85, 1.12)


## 取一个空槽位。池子满了就复用游标处那颗 —— 视觉上它只是提前退场。
func _take_puff() -> Puff:
	for p in _puffs:
		if p.life <= 0.0:
			return p
	if _puffs.size() < PUFFS:
		var fresh := Puff.new()
		_puffs.append(fresh)
		return fresh
	return null


## 贴地的沙团。画在**本节点**自己的 `_draw()` 里（z = 0，落在中景沙线后面）。
func _draw() -> void:
	if _puffs.is_empty() or span.size.x <= 0.0:
		return
	for p in _puffs:
		if p.life <= 0.0:
			continue
		var v := puff_visual(p)
		if float(v["alpha"]) <= 0.004:
			continue
		draw_circle(p.pos, v["radius"], v["color"])


## 一颗沙团这一帧该画成什么样：半径 + 透明度。
##
## 抽成一个函数是为了**能测**：无头跑的时候 `_draw()` 不一定被调用（Dummy 渲染器
## 不发 `NOTIFICATION_DRAW`），画里的算式就没人验了 —— 而「沙团是不是真的越老越大」
## 「风区两端是不是真的淡出」正是这套动画最容易写反的地方。
func puff_visual(p: Puff) -> Dictionary:
	var t := p.life / p.span           # 1 是刚生出来，0 是散尽
	var x := clampf((p.pos.x - span.position.x) / maxf(1.0, span.size.x), 0.0, 1.0)
	var col := Color(
		minf(1.0, SAND_COLOR.r * p.tint),
		minf(1.0, SAND_COLOR.g * p.tint),
		minf(1.0, SAND_COLOR.b * p.tint),
	)
	col.a = PUFF_ALPHA * t * _edge_fade(x)
	return {
		# 越老越大（`PUFF_GROW` > 1），和烟一个道理：散开的沙团是虚的
		"radius": lerpf(p.size * PUFF_GROW, p.size, t),
		"alpha": col.a,
		"color": col,
	}
