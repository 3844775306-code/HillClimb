extends Node2D
class_name HillRooftopArt
## 屋顶图的房子：屋面上铺的瓦、立面上的楼层线和窗户、连接两级屋面的钢梯，以及
## 坐在屋面上的砖烟囱。窗户**会随时间换脸**（哪几扇亮着不是定死的）。
##
## ## 一栋房子 = 一个区块，一个节点
##
## 一个区块一栋房子，窗户按 [constant FLOOR_H] × [constant WIN_PITCH] 排下来就是
## 几十扇 —— 一扇一个节点的话，镜头来回滚就是几百个节点的生灭。所以和
## [scripts/sandstorm.gd] / [scripts/hazard_zone.gd] 同一个路子：**一个节点，
## 全部在 [method _draw] 里画**，节点数不随画出来的东西涨。
##
## 由 [method HillTerrain._build_chunk] 挂在区块节点下（**地表之后**，于是盖住土色；
## 车在 z = 1，又盖住这里画的全部）。区块被回收时跟着一起释放。
##
## ## 画出来的每一笔都是**世界坐标的纯函数**
##
## 区块会随镜头滚出视野再重建（[method HillTerrain._build_chunk]），同一栋房子必须
## 每次都长得一模一样。所以这里一根 `randf()` 都不能有：
##
##  · **瓦的相位**按世界 x 取模（[method tile_centers]）—— 跨区块的那一排瓦接得上。
##  · **亮着的窗户**由 [method Maps._hash01] 按「哪一栋 + 哪一层 + 哪一列 + 第几拍」
##    掷（[method window_lit]），和种子、房号、格子绑定，重建前后逐位一致。
##  · 楼层锚在**自家最低那一级屋面**上（每栋各量各的），钢梯跟着剖面走。
##  · **烟囱**由 [method Maps.chimney_at] 掷、[method HillChimneys.chimney_rect] 定形，
##    和托车的那股烟同一个函数（见 [method _draw_chimneys]）。
##
## ## 唯一「活」的一维是时间
##
## 窗户不是一辈子一个状态：它按世界的拍子换脸（[method window_tick]），这是用户要的
## 「窗户动画」。时间取**绝对时钟**（[method now]）、不自己累加 delta —— 累加的话，
## 重建出来的那一栋从 0 开始，和它隔壁就对不上拍了。除此之外每一笔都只认世界坐标，
## 所以镜头来回滚不会让房子变形。
##
## ## 算式全抽成 static 纯函数，[method _draw] 只照着画
##
## 无头跑（`--headless`）根本不发 `NOTIFICATION_DRAW`，画里的算式没有测试跑得到 ——
## 「瓦铺到哪儿」「窗户摆几列」「哪一扇亮着」「横档多密」这些**会错的地方**于是都抽成
## 静态纯函数，测试直接调它们。[scripts/sandstorm.gd] 的 `puff_visual` 立的就是这条规矩。
##
## ## 本节点的局部坐标就是世界坐标
##
## 区块节点在原点（[method HillTerrain._build_chunk] 连 `position` 都没设），地表折线
## 用的也是世界坐标，所以这里画图不做任何换算 —— 只有问剖面高度的时候要把世界 x
## 减成区块内坐标：吃区块内坐标的是 [method HillTerrain.roof_profile_y]。

## 一排半圆瓦的间距（像素）。22 是「一栋 650 宽的房顶铺三十来块」定的：
## 再密就成了一条花边，再疏就看不出是瓦。
const TILE_PITCH := 22.0
## 瓦的拱高 = 半径（半圆瓦，正好是间距的一半）。
const TILE_R := TILE_PITCH * 0.5
## 半圆瓦用几段折线拼。8 段的弦高误差 11 × (1 − cos 11.25°) ≈ 0.21 像素，看不见。
const TILE_ARCS := 8
## 屋脊线从瓦顶往下多少。它是瓦排的上沿，和瓦一起才读得成「这一层是瓦顶」。
const RIDGE_DROP := 1.0

## 楼层高（像素）。64 ≈ 车高的 0.55 倍：窗户比车矮一点，看着才像窗户而不是天窗。
const FLOOR_H := 64.0
## 窗的尺寸、列距，以及离房子左右两端各留多少。
##
## 窗户是**一列一列**排的（[method window_centers]）：26 宽的窗配 46 的列距，
## 窗与窗之间留 20 像素的墙。两端留 [constant WIN_MARGIN] 是为了窗户不压在
## 房子的边线上 —— 边线是立面的棱，压上去看着像窗开在墙缝里。
const WIN_W := 26.0
const WIN_H := 34.0
const WIN_PITCH := 46.0
const WIN_MARGIN := 26.0
## 窗台离它下面那条地板线多高。
const WIN_SILL := 10.0
## 亮着的窗户占多少。一半一半：全亮像白天、全暗像废墟，一半才像「有人在住」。
const LIT_CHANCE := 0.5

## 窗户换脸的拍子（秒）：世界时间每走这么久，亮不亮重掷一次（[method window_tick]）。
##
## 一秒一格是「看得出来在变」和「别闪成警灯」之间的折中 —— 一栋房子几十扇窗，
## 每格只有「一除以自己周期」的那一小撮窗会变脸。
const WINK_STEP := 1.0
## 一扇窗一次亮（或一次暗）持续多少格。每扇窗自己在这区间里掷一个周期。
##
## 12 格 = 12 秒起步，60 格 = 一分钟封顶。比这短就成霓虹灯，比这长一局里也看不出是活的。
const ACT_MIN := 12
const ACT_MAX := 60

## 钢梯：两根导轨之间的宽度、横档多密、导轨折线沿坡面每多少像素取一个点。
##
## 横档按**坡面弧长**均匀铺（[method ladder_rungs]），不是按水平距离：55° 的坡上
## 两者差着 1.7 倍，按水平距离铺的话陡的那几把梯子横档会挤成一团。
const LADDER_W := 12.0
const LADDER_RUNG := 9.0
const LADDER_STEP := 7.0

## 瓦、屋脊、墙线、窗、钢梯的颜色。
##
## 瓦色**故意比 [code]crust[/code]（0.66, 0.38, 0.29）亮一档**：屋面那 15 像素高的
## 檐口色带是同一族的暖色，两个色一样的话瓦和檐口会糊成一片，看不出瓦。
const TILE := Color(0.82, 0.44, 0.30)
const TILE_DARK := Color(0.36, 0.18, 0.15)
const WALL_LINE := Color(0.40, 0.36, 0.36)
const WIN_FRAME := Color(0.14, 0.13, 0.14)
const WIN_LIT := Color(1.0, 0.86, 0.48)
const WIN_DARK := Color(0.10, 0.11, 0.15)
const STEEL := Color(0.68, 0.72, 0.78)
const STEEL_DARK := Color(0.40, 0.44, 0.50)
const RAIL_W := 3.0
const RUNG_W := 2.5

## 砖烟囱：柱身、砖缝与柱帽、烟口那个洞。
##
## 柱身**比瓦暗一档、也偏冷一点**（瓦是暖橙 0.82/0.44/0.30）：两个色一样的话烟囱会糊
## 在瓦里，看不出屋面上立着个东西。烟口那个洞要够黑，不然烟看着像从砖里渗出来的。
const BRICK := Color(0.52, 0.29, 0.25)
const BRICK_DARK := Color(0.31, 0.16, 0.14)
const BRICK_MOUTH := Color(0.06, 0.05, 0.06)
## 砖缝多高一条。
const BRICK_COURSE := 7.0
## 柱帽比柱身两边各宽多少、多高（像素）。
const BRICK_CAP_W := 3.0
const BRICK_CAP_H := 7.0

var _prof := {}
var _start_x := 0.0
var _bottom := 0.0
var _index := 0
var _seed := 0
## 上一次重画是在第几拍（[method window_tick]）。
var _tick := 0


## 由 [method HillTerrain._build_chunk] 调用。`bottom` 是地块的底边（本区块最深那一点
## 再往下 [constant HillTerrain.DEPTH]，由那边算好传进来）—— 楼层线画到那儿为止，
## 再往下什么都没有。
func setup(prof: Dictionary, bottom: float, index: int, world_seed: int) -> void:
	_prof = prof
	_start_x = float(index) * HillTerrain.CHUNK_WIDTH
	_bottom = bottom
	_index = index
	_seed = world_seed
	_tick = window_tick(now())
	queue_redraw()


## 窗户是按世界的拍子换脸的，得有人告诉引擎「该重画了」。
##
## **只在拍子翻页那一下重画**（[constant WINK_STEP] 一秒一次），不是每帧：一栋房子
## 几十扇窗，每帧重画等于白白画六十遍。而一拍之内没有哪扇窗会中途变脸（[method
## window_lit] 只认 [method window_tick]），所以隔一拍看一眼也不会漏掉变化。
func _process(_delta: float) -> void:
	var tick := window_tick(now())
	if tick == _tick:
		return
	_tick = tick
	queue_redraw()


# ------------------------------------------------------------------ 纯函数：瓦

## 屋面上一排瓦的**圆心 x**（世界坐标）：世界 x 是 [constant TILE_PITCH] 整数倍的那些点
## 落在 `[xa, xb]` 里的部分。
##
## 按世界坐标取模是为了**跨区块接得上**：房子是 800 一块、瓦是 22 一块，两边除不尽，
## 按区块内坐标铺的话每栋房子的瓦缝都从头开始，相邻两栋的瓦对不齐。
static func tile_centers(xa: float, xb: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if xb <= xa:
		return out
	var cx := ceilf(xa / TILE_PITCH) * TILE_PITCH
	while cx <= xb:
		out.append(cx)
		cx += TILE_PITCH
	return out


## 一块半圆瓦的折线（圆心 `cx`、坐在屋面 `y` 上，所以只画出**上半圈**）。
##
## 只画上半圈是要紧的：地块（土色多边形）和它上面的檐口色带都已经画在下面了，
## 整个圆画下去，下半圈会盖在土色上，看着像一排球嵌在墙里。
##
## `xa`/`xb` 是这一级屋面的两头，瓦的 x **掐在这两头之间**（默认不掐）。最外那两块瓦
## 的圆心落在屋面里，可是拱还要往外铺半个间距 —— 不掐的话，落点台左端那块瓦会探出
## 房子的棱、悬在缝上面，看着像屋檐上掉了一块砖。
static func tile_arc(cx: float, y: float, xa := -INF, xb := INF) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in TILE_ARCS + 1:
		# PI → TAU：y 轴朝下，所以这一段角度落在圆心的**上方**。
		var a := PI + PI * float(i) / float(TILE_ARCS)
		out.append(Vector2(
				clampf(cx + cos(a) * TILE_R, xa, xb),
				y + sin(a) * TILE_R))
	return out


# ------------------------------------------------------------------ 纯函数：楼层与窗户

## 楼层线的高度（世界 y）：从 `top` 起每 [constant FLOOR_H] 一格，到 `bottom` 为止。
##
## `top` 由调用方给成「自家最低那一级屋面 + 一格」，所以**每栋房子的楼层各量各的**，
## 顶层窗永远紧贴在自家屋檐下。锚在一个固定的世界高度上的话，矮房子的屋顶和第一层
## 之间会空出一整层没有窗的墙。
static func floor_ys(top: float, bottom: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var y := top
	while y < bottom:
		out.append(y)
		y += FLOOR_H
	return out


## 一栋房子立面上窗户的**中心 x**（区块内坐标，相对 `xa`）：左右各留
## [constant WIN_MARGIN]，中间按 [constant WIN_PITCH] 排。
##
## 锚在**房子自己的左沿**上，不是世界坐标：房子宽 650～670（每栋不一样），锚在世界上
## 的话宽房子的最右一列会被切掉半个。
static func window_centers(xa: float, xb: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var usable := xb - xa - 2.0 * WIN_MARGIN
	if usable < WIN_W:
		return out
	var n := 1 + int(floor((usable - WIN_W) / WIN_PITCH))
	var left := xa + WIN_MARGIN
	for k in n:
		out.append(left + WIN_W * 0.5 + float(k) * WIN_PITCH)
	return out


## 世界时间（秒）。**绝对时钟，不是自己累加 `delta`。**
##
## 区块随镜头滚出视野就整块释放、再滚回来重建（[method HillTerrain._build_chunk]），
## 自己累加的话每个新区块都从 0 起算，同一排房子会各拍各的；绝对时钟则所有区块、
## 重建前后读到的都是同一个数。
static func now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## 世界时间 `t`（秒）落在第几拍上（[constant WINK_STEP] 一格）。
##
## 窗户只在这一格一格的边界上换脸，所以两个区块、乃至同一个区块重画两次，
## 只要还在同一拍里，算出来的就是同一个状态。
static func window_tick(t: float) -> int:
	return int(floor(t / WINK_STEP))


## 第 `row` 层第 `col` 列那扇窗在时刻 `t` 亮不亮。
##
## **纯函数，只认「哪一栋 + 哪一层 + 哪一列 + 第几拍」**：区块重建、镜头来回滚都
## 必须是同一个状态 —— 用 `randf()` 的话回头一看，亮着的窗户换了一批，那一眼就看出来了。
##
## 「第几拍」是**唯一会变的一维**（用户要的窗户动画），而且时间取的是绝对时钟
## （[method now]）不是自己累加的 delta。
static func window_lit(world_seed: int, index: int, row: int, col: int, t: float) -> bool:
	var key := world_seed * 5171 + index * 409 + row * 101 + col * 37
	# 每扇窗自己一个周期：全城同一个周期的话，到点了整条街一起眨眼。
	var period := ACT_MIN + int(Maps._hash01(key + 5) * float(ACT_MAX - ACT_MIN))
	# 相位也错开 —— 周期相同的窗户不至于同时换脸。
	var phase := int(Maps._hash01(key + 11) * float(period))
	var act := int(floor(float(window_tick(t) + phase) / float(period)))
	# 每「一任」重掷一次，所以一扇窗可以连任（那就一直亮着），也可以一亮一暗地换。
	return Maps._hash01(key + act * 29) < LIT_CHANCE


## 第 `row` 层那扇窗（中心在区块内坐标 `cx`）能不能画：**整扇**都得在屋面底下。
##
## 屋面在这栋房子里是**单调**的（[method HillTerrain._ladder_runs] 给每段钢梯同一个
## 符号），所以一段 x 范围里最低的那一点必落在两头 —— 量两头就够了，不用逐点扫。
## 这条前提由 tests/shapes 自己验：它在窗宽里另取三个点，逐点比一遍。
##
## 剪掉的窗不画（不是画一半再裁）：一栋房子的顶上一层窗正好压在钢梯的坡上，
## 裁一半比不画更怪。
static func window_fits(prof: Dictionary, start_x: float, cx: float, top: float) -> bool:
	var roof_lo := maxf(
			HillTerrain.roof_profile_y(prof, cx - WIN_W * 0.5),
			HillTerrain.roof_profile_y(prof, cx + WIN_W * 0.5))
	return top > roof_lo + 2.0


# ------------------------------------------------------------------ 纯函数：钢梯

## 一把钢梯的坡面折线（**区块内坐标**）：沿坡面每 [constant LADDER_STEP] 像素一个点。
##
## 取形和 [method HillTerrain.roof_profile_y] **逐位一致**（同一段 smoothstep），
## 不然画出来的梯子和车压着走的坡差一丝 —— 55° 的坡上，差一丝就是梯子悬在坡外面。
## 测试拿 [method HillTerrain.roof_profile_y] 逐点对过。
static func ladder_samples(prof: Dictionary, k: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pts: PackedVector2Array = prof.get("pts", PackedVector2Array())
	var ramps: PackedInt32Array = prof.get("ramps", PackedInt32Array())
	if k < 0 or k >= ramps.size() or ramps[k] + 1 >= pts.size():
		return out
	var a := pts[ramps[k]]
	var b := pts[ramps[k] + 1]
	var n := maxi(2, int(ceil(a.distance_to(b) / LADDER_STEP)))
	for s in n + 1:
		var u := float(s) / float(n)
		out.append(Vector2(lerpf(a.x, b.x, u), lerpf(a.y, b.y, u * u * (3.0 - 2.0 * u))))
	return out


## 坡面折线上每个点朝上的法线（单位向量）。y 轴朝下，所以「上」是 `(t.y, -t.x)`。
##
## 端点只有一侧的邻居，就用那一侧的割线 —— 坡面在两头是平的（smoothstep 两端斜率
## 为 0），所以那儿法线基本就是竖直的，误差看不见。
static func ladder_normals(samples: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := samples.size()
	for i in n:
		var t := Vector2.ZERO
		if i == 0:
			t = samples[1] - samples[0] if n > 1 else Vector2.RIGHT
		elif i == n - 1:
			t = samples[n - 1] - samples[n - 2]
		else:
			t = samples[i + 1] - samples[i - 1]
		if t.length_squared() <= 0.0:
			t = Vector2.RIGHT
		out.append(Vector2(t.y, -t.x).normalized())
	return out


## 一把钢梯的横档：**每根的两个端点**（区块内坐标），沿坡面每 [constant LADDER_RUNG]
## 像素一根（按弧长铺，见 [constant LADDER_RUNG] 的注释）。
##
## 第一根从**半格**开始、最后一根落在离坡顶不足一格的地方为止：正好从端点起铺的话，
## 梯脚那根横档会压在屋檐的棱上，看着像多出来一截。
static func ladder_rungs(samples: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var normals := ladder_normals(samples)
	if samples.size() < 2 or normals.size() != samples.size():
		return out
	var walked := 0.0
	var next := LADDER_RUNG * 0.5
	for i in samples.size() - 1:
		var a := samples[i]
		var b := samples[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		while next <= walked + seg:
			var f := (next - walked) / seg
			var p := a.lerp(b, f)
			# 法线在段内插值：一段只有几像素，用哪一端的都看不出区别。
			var nrm := normals[i].lerp(normals[i + 1], f).normalized()
			out.append(PackedVector2Array([p, p + nrm * LADDER_W]))
			next += LADDER_RUNG
		walked += seg
	return out


## 两根导轨里**朝上那一根**的折线（区块内坐标）：坡面点整体沿法线抬
## [constant LADDER_W]。另一根就是坡面自己（梯子躺在坡上，两根导轨一上一下）。
static func ladder_rail(samples: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var normals := ladder_normals(samples)
	for i in samples.size():
		out.append(samples[i] + normals[i] * LADDER_W)
	return out


# ------------------------------------------------------------------ 画

func _draw() -> void:
	if _prof.is_empty():
		return
	var pts: PackedVector2Array = _prof.get("pts", PackedVector2Array())
	if pts.size() < 2:
		return
	# 整幅画只取一次时间：一栋房子的窗户要么全按这一拍画，要么全按下一拍画，
	# 不能一半一半 —— 那会画出一条谁都解释不了的斜线。
	var t := now()
	_draw_facade(pts, t)
	_draw_tiles(pts)
	_draw_chimneys()
	_draw_ladders()


## 立面上的东西：房子左右两条棱、每一层的楼板线、每层的窗。
func _draw_facade(pts: PackedVector2Array, t: float) -> void:
	var span := float(_prof.get("len", 0.0))
	var y_lo := float(pts[0].y)
	var y_hi := y_lo
	for p in pts:
		y_lo = minf(y_lo, p.y)
		y_hi = maxf(y_hi, p.y)
	# 两条棱画到地块底边为止，不从最低那一级量：棱是墙的边，屋顶高低不平，
	# 每一级上面都还该有墙。
	draw_line(Vector2(_start_x, float(pts[0].y)), Vector2(_start_x, _bottom), WALL_LINE, 3.0)
	draw_line(Vector2(_start_x + span, float(pts[pts.size() - 1].y)),
			Vector2(_start_x + span, _bottom), WALL_LINE, 3.0)

	var cols := window_centers(0.0, span)
	var rows := floor_ys(y_hi + FLOOR_H, _bottom)
	for r in rows.size():
		var y := rows[r]
		var vis := _facade_span(y)
		if vis.y - vis.x < 8.0:
			continue
		draw_line(Vector2(_start_x + vis.x, y), Vector2(_start_x + vis.y, y), WALL_LINE, 3.0)
		for c in cols:
			var top := y - WIN_SILL - WIN_H
			if not window_fits(_prof, _start_x, c, top):
				continue
			_draw_window(_start_x + c, top, r, c, t)


func _draw_window(wx: float, top: float, row: int, col: int, t: float) -> void:
	var rect := Rect2(Vector2(wx - WIN_W * 0.5, top), Vector2(WIN_W, WIN_H))
	draw_rect(rect.grow(2.0), WIN_FRAME, true)
	draw_rect(rect, WIN_LIT if window_lit(_seed, _index, row, col, t) else WIN_DARK, true)


## 每一级**平屋面**上铺一排瓦。钢梯那几段不铺（那是钢的，见 [method _draw_ladders]）——
## 所以判据就是「这一对折点是不是钢梯」，和剖面那边 [member _prof].ramps 同一份数据。
func _draw_tiles(pts: PackedVector2Array) -> void:
	var ramps: PackedInt32Array = _prof.get("ramps", PackedInt32Array())
	for i in pts.size() - 1:
		if ramps.has(i):
			continue
		var y := float(pts[i].y)
		var xa := _start_x + float(pts[i].x)
		var xb := _start_x + float(pts[i + 1].x)
		var centers := tile_centers(xa, xb)
		if centers.is_empty():
			continue
		for cx in centers:
			draw_colored_polygon(tile_arc(cx, y, xa, xb), TILE)
		# 屋脊：瓦排的上沿一条暗线，两头落在最外那两块瓦的拱顶上。
		var ridge_y := y - TILE_R + RIDGE_DROP
		draw_line(Vector2(maxf(centers[0] - TILE_R, xa), ridge_y),
				Vector2(minf(centers[centers.size() - 1] + TILE_R, xb), ridge_y),
				TILE_DARK, 3.0)


## 一栋房子最多一根砖烟囱。
##
## **位置由 [method Maps.chimney_at] 掷、形状由 [method HillChimneys.chimney_rect] 算** ——
## 和托车的那股烟（[scripts/chimneys.gd] 的受力区）**同一个函数**：画在这儿的砖柱和
## 烟柱永远落在同一块地方，不会美术一份、物理一份各算各的。
##
## 画在瓦**之后**：烟囱坐在屋面上，它下面那几块瓦该被柱身盖住。
func _draw_chimneys() -> void:
	var rect := HillChimneys.chimney_rect(_prof, Maps.chimney_at(_seed, _index), _start_x)
	if rect.size.x <= 0.0:
		return
	draw_rect(rect, BRICK, true)
	# 砖缝：柱身那么宽的一条条暗线，不画到柱帽上（柱帽自己盖住顶上一截）。
	var y := rect.position.y + BRICK_COURSE
	while y < rect.end.y - 1.0:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), BRICK_DARK, 1.0)
		y += BRICK_COURSE
	# 柱帽：比柱身两边各宽一圈的一条，压在柱顶 —— 没有它，柱身就是一根悬空的方条。
	draw_rect(Rect2(rect.position.x - BRICK_CAP_W, rect.position.y,
			rect.size.x + 2.0 * BRICK_CAP_W, BRICK_CAP_H), BRICK_DARK, true)
	# 烟口那个洞，开在柱帽正中。**烟就是从这儿冒出来的** —— 同一条中线：
	# [method HillChimneys.chimney_rect] 的顶边中点（那边 `_mouth` 就是这么算的）。
	# 洞不开在这儿，看着就像烟从砖缝里渗出来。
	draw_rect(Rect2(rect.position.x + rect.size.x * 0.25, rect.position.y + 2.0,
			rect.size.x * 0.5, BRICK_CAP_H - 3.0), BRICK_MOUTH, true)


## 每段钢梯：横档 + 朝上那根导轨。梯子躺在坡上，另一根导轨就是坡面本身。
func _draw_ladders() -> void:
	var ramps: PackedInt32Array = _prof.get("ramps", PackedInt32Array())
	for k in ramps.size():
		var local := ladder_samples(_prof, k)
		if local.size() < 2:
			continue
		for rung in ladder_rungs(local):
			draw_line(_w(rung[0]), _w(rung[1]), STEEL, RUNG_W)
		draw_polyline(_w_all(ladder_rail(local)), STEEL_DARK, RAIL_W)


## 区块内坐标 → 世界坐标。整个脚本只此一处换算（水平加区块左沿，竖直不动）。
func _w(p: Vector2) -> Vector2:
	return Vector2(_start_x + p.x, p.y)


func _w_all(local: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in local:
		out.append(_w(p))
	return out


## 世界 x 处的屋面高度。
func _roof_at(wx: float) -> float:
	return HillTerrain.roof_profile_y(_prof, wx - _start_x)


## 高度 `y` 处立面**露出来**的那一段 x（区块内坐标）：屋面在它上面、地块底边在它下面。
##
## 屋面在这栋房子里是**单调**的（[method HillTerrain._ladder_runs] 给每段钢梯同一个
## 符号），所以「露出来」的部分是一整段，只有一个交点，两头二分就够。
## 一段都没有（这一层整个在屋面之上，或者整个埋在底下）就返回零长度。
func _facade_span(y: float) -> Vector2:
	var len := float(_prof.get("len", 0.0))
	if len <= 0.0:
		return Vector2.ZERO
	var vis_lo := _roof_at(_start_x) < y
	if vis_lo == (_roof_at(_start_x + len) < y):
		# 两头一样：单调 → 整段都露着，或者整段都不露。
		return Vector2(0.0, len) if vis_lo else Vector2.ZERO
	var a := 0.0
	var b := len
	for _i in 24:
		var m := (a + b) * 0.5
		if (_roof_at(_start_x + m) < y) == vis_lo:
			a = m
		else:
			b = m
	var cross := (a + b) * 0.5
	return Vector2(0.0, cross) if vis_lo else Vector2(cross, len)
