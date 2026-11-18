extends HillFeature
class_name HillChimneys
## 屋顶图的烟囱：长在某一级平屋面上的一根砖柱子，**囱口的烟柱把车往上托**。
##
## ## 一半是画，一半是力
##
## 砖柱子本身**不在这里画**：它和瓦、窗户、钢梯一起由 [scripts/rooftop_art.gd]
## 铺在房子上（那里才是「房子长什么样」的唯一出处）。这里只管两件事：
##
##  · **力区**（[Area2D]）—— 一根矩形，车开进去就被往上托；
##  · **烟**（[method _draw] 里那些上升的烟团）—— 让那根矩形看得见。
##
## 两边都从 [method chimney_rect] 拿位置，所以砖柱子和烟柱**永远对得上**：
## 各算一遍的话，改一次骰子就会出现「囱口在左边、烟从右边冒出来」。
##
## ## 烟柱是矩形，看着像一股上升的烟
##
## 力区是个**矩形**（[constant SMOKE_W] × [constant SMOKE_H]），不是烟团那种形状 ——
## 车在柱子里受到的力要是稳定的一个数，不能跟着烟团的疏密抖。烟团只是给这只矩形
## 一个「看得见的样子」。**改烟团的画法不许动力区的尺寸**：[member _area] 的框决定
## 车在哪儿被托，手感是按它标定的（沙尘暴同一条纪律，见 scripts/sandstorm.gd）。
##
## 力区的**底面贴在屋面那条线上**，不是贴在囱口：车是**沿着屋面开过去**的，
## 它的车壳正好压在屋面往上 90 像素那一带，囱口（屋面往上 46～78）只在当中一小截。
## 底面放在囱口的话，只有腾空跃过屋顶时才吃得到力，那正是「开过去被托一把」的反面。
## 所以烟团从囱口往上飘，力却从屋面就开始算 —— 这一段差在画面里看不出来
## （烟是半透明的，力区根本不画），手感却是两回事。
##
## ## 力度是「几倍自重」，不是写死的牛顿数
##
## [constant SMOKE_LIFT_G] = 1.4 表示「往上 1.4 倍自重」，净 +0.4 g。**运行时用车自己的
## 总质量 × 本地重力算**（[method HillCar.total_mass] / [method HillCar.local_gravity]）：
## 车的质量是活的（车主会在编辑器里实时改 car.gd），写死 174 或 130 的力在他调完参数
## 之后就变成另一个手感了。月球那种 0.35 重力的图上，这条也跟着对。

## 向上的推力是**几倍自重**。1.4 → 净上升 0.4 g：开过去会被托得离一下地，
## 但绝不会自己飞起来（那一档要用登月车的 1.9）。
##
## 0.4 g 是**选出来的**，量法见 tests/shapes 的烟囱那节：同一段路开烟 / 关烟各跑一趟，
## 比竖直速度。调到 1.0 以下就成了累赘（烟柱反而变重），调到 1.9 车会被吸上去。
const SMOKE_LIFT_G := 1.4

## 烟柱（力区）的宽度和高度。
##
## 96 宽 ≈ 半个车身（车长 180）：开过去托一下、托不满一整段路。再宽就成了屋顶上
## 的一段电梯，再窄的话高速过去一帧就穿过去了，力等于没加。
const SMOKE_W := 96.0
## 420 高：车腾空跃过屋顶时也得在柱子里（跳一下能到两三百像素），而且这是
## 「看得见一柱烟」的下限 —— 再矮就成了一小团浮在囱口。
const SMOKE_H := 420.0

## 烟囱离它那一级屋面的两头各留多少。留一点，砖柱子才不压在屋檐的棱上
## （棱那儿是钢梯或者缝，看着像要把烟囱挤下去）。
const CHIMNEY_EDGE := 8.0

## 烟团：池子大小、每秒生几颗、寿命、速度、基础半径。
##
## 和沙尘暴的沙团是同一套参数、方向反过来（那个往左飘、这个往上升）。
const PUFFS := 40
const PUFF_RATE := 11.0
const PUFF_LIFE_MIN := 1.1
const PUFF_LIFE_MAX := 2.6
const PUFF_SPEED_MIN := 46.0
const PUFF_SPEED_MAX := 96.0
const PUFF_SIZE := 8.0
const PUFF_ALPHA := 0.34
## 越老越大（> 1 是变大）：散开的烟是虚的。
const PUFF_GROW := 2.4
## 上升途中往两边散开多少（像素/秒）。笔直上升的一柱烟看着像一根管子。
const PUFF_DRIFT := 26.0

## 烟的颜色：从囱口那一层暖灰（被下面的火烤着）升到上面的冷灰，一路变淡。
##
## 烟**画在车后面**（本节点和地表同层，z = 0；车在 z = 1）：半透明的灰盖在车上
## 会把车糊住，而车是玩家唯一要盯着的东西。
const SMOKE_WARM := Color(0.72, 0.68, 0.62)
const SMOKE_COOL := Color(0.60, 0.62, 0.66)
## 囱口那点亮：底下烧着火，砖口才透出一点暖色。
const EMBER := Color(1.0, 0.62, 0.28)
const EMBER_R := 5.0
const EMBER_ALPHA := 0.55

var _area: Area2D
## 烟囱（砖柱子）的世界坐标矩形，`position` 是左上角、`end.y` 是它站的那条屋面线。
var _chimney := Rect2()
## 囱口：烟团从这儿生出来。
var _mouth := Vector2.ZERO
## 烟柱的顶（力区的上沿）。
var _top := 0.0

var _puffs: Array[Puff] = []
var _emit := 0.0
var _rng := RandomNumberGenerator.new()


## 一颗上升的烟团。字段和 [Puff]（sandstorm.gd）一个路子。
class Puff:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var span := 0.0
	var size := 1.0
	var tint := 1.0


func _build() -> void:
	var terrain := terrain_node()
	if terrain == null or not terrain.has_method("roof_profile"):
		return
	var index := int(span.position.x / HillTerrain.CHUNK_WIDTH)
	var prof: Dictionary = terrain.call("roof_profile", index)
	var dice := Maps.chimney_at(int(terrain.get("world_seed")), index)
	_chimney = chimney_rect(prof, dice, span.position.x)
	if _chimney.size.x <= 0.0:
		# 这一栋没有烟囱（骰子没中，或者中间那几级平屋面都太窄摆不下）。
		# 什么都不摆 —— 连 Area2D 都不建，省一颗每帧被物理引擎问一次的节点。
		return
	_mouth = Vector2(_chimney.position.x + _chimney.size.x * 0.5, _chimney.position.y)
	_top = _chimney.end.y - SMOKE_H
	_rng.seed = int(_chimney.position.x)
	_build_area()


## 力区。**改烟团的画法时这一块不能跟着动**：它的尺寸决定车在哪儿被托，
## tests/shapes 的烟囱那节就是拿它做 A/B 的。
func _build_area() -> void:
	_area = Area2D.new()
	_area.name = "Smoke"
	_area.collision_layer = 0
	_area.collision_mask = 1
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(SMOKE_W, SMOKE_H)
	cs.shape = box
	_area.add_child(cs)
	# 底边压在屋面那条线上，往上 [constant SMOKE_H]（见文件头：底边为什么不贴在囱口）。
	_area.position = Vector2(_mouth.x, _chimney.end.y - SMOKE_H * 0.5)
	add_child(_area)


# ------------------------------------------------------------ 纯函数：摆在哪儿

## 这栋房子上那根烟囱的世界坐标矩形（`position` 是左上角，`end.y` 落在屋面上）。
##
## `dice` 是 [method Maps.chimney_at] 的结论（空字典 = 这栋没有），`start_x` 是本区块
## 左沿的世界 x。摆不下就返回一个**空矩形**（宽 0），调用方照空处理。
##
## 摆在**中间那几级平屋面**上，跳过第 0 段（落点）和最后一段（跳台）——
## 理由见 [method Maps.chimney_at]。
##
## 掷中的那一级太窄就**顺延下一级**，而不是整根作废：一栋房子里各级平屋面宽的宽、
## 窄的窄（窄的只有 [constant Maps.SECTION_MIN] = 70），只看掷中的那一级的话，
## 一栋有三级屋面的房子会因为「正好掷到最窄那级」而整个没有烟囱。
##
## 纯函数（剖面和骰子都是现算的），所以画房子的那边和摆烟的那边算出来一定一样。
static func chimney_rect(prof: Dictionary, dice: Dictionary, start_x: float) -> Rect2:
	if dice.is_empty():
		return Rect2()
	var pts: PackedVector2Array = prof.get("pts", PackedVector2Array())
	var ramps: PackedInt32Array = prof.get("ramps", PackedInt32Array())
	if pts.size() < 2:
		return Rect2()
	# 平段 = 不是钢梯的那几段（见 [method HillTerrain.roof_profile] 的 `ramps`）。
	var flats: Array[int] = []
	for i in pts.size() - 1:
		if not ramps.has(i):
			flats.append(i)
	if flats.size() <= 2:
		return Rect2()
	var mids: Array[int] = []
	for j in range(1, flats.size() - 1):
		mids.append(flats[j])
	var w := float(dice.get("w", 0.0))
	var h := float(dice.get("h", 0.0))
	if w <= 0.0 or h <= 0.0:
		return Rect2()
	var want := int(dice.get("section", 0))
	var at := float(dice.get("at", 0.5))
	for s in mids.size():
		var k: int = mids[(want + s) % mids.size()]
		var a := pts[k]
		var b := pts[k + 1]
		if b.x - a.x < w + 2.0 * CHIMNEY_EDGE:
			continue
		# 沿着这一级平屋面摆在 `at` 那个位置（[method Maps.chimney_at] 只给 0.3～0.7），
		# 摆到最靠边也只能贴到 `CHIMNEY_EDGE`。
		var cx := lerpf(a.x + CHIMNEY_EDGE + w * 0.5, b.x - CHIMNEY_EDGE - w * 0.5, at)
		return Rect2(start_x + cx - w * 0.5, a.y - h, w, h)
	return Rect2()


## 烟柱（力区）的世界坐标矩形：在囱口的正上方，底边压在**屋面**上。
static func smoke_rect(chimney: Rect2) -> Rect2:
	if chimney.size.x <= 0.0:
		return Rect2()
	var cx := chimney.position.x + chimney.size.x * 0.5
	return Rect2(cx - SMOKE_W * 0.5, chimney.end.y - SMOKE_H, SMOKE_W, SMOKE_H)


## 托起 `mass` 这么重的车要用多大的力。`gravity` 是**本地**重力
## （[method HillCar.local_gravity]，月球是它的 0.35 倍）。
##
## 抽出来是为了能测：无头跑里 [method _physics_process] 的力有没有真的加上去
## 要跑真物理才看得出来，而这个式子是「1.4 倍自重」那句话本身。
static func smoke_lift(mass: float, gravity: float) -> float:
	return mass * gravity * SMOKE_LIFT_G


# ------------------------------------------------------------ 力

## 只有在**车壳**上使一次劲。车是三个刚体（车壳 + 两个轮子），
## [method Area2D.get_overlapping_bodies] 会把三个都报上来 —— 逐个加的话
## 力是设计值的三倍，而且车壳和轮子分别受力还会多出一个扭矩把车掀翻
## （沙尘暴那边同一条，见 scripts/sandstorm.gd 的文件头）。
##
## 力的大小**按整辆车的质量算**（[method HillCar.total_mass]），却只加在车壳上：
## 轮子是被销子拖着的，稳态下三个刚体一起加速，所以净加速度就是设计值
## （`SMOKE_LIFT_G` − 1 倍重力）。按车壳质量算的话，独轮车和大巴就是两个手感。
func _physics_process(_delta: float) -> void:
	if _area == null:
		return
	for body in _area.get_overlapping_bodies():
		var car := car_of(body)
		if car != null and car.alive and body == car.chassis:
			var lift := smoke_lift(car.total_mass(), car.local_gravity())
			car.chassis.apply_central_force(Vector2(0.0, -lift))


# ------------------------------------------------------------ 烟

func _process(delta: float) -> void:
	if _area == null:
		return
	_emit += PUFF_RATE * delta
	while _emit >= 1.0:
		_emit -= 1.0
		_spawn_puff()
	var live := false
	for p in _puffs:
		if p.life <= 0.0:
			continue
		p.life -= delta
		p.pos += p.vel * delta
		# 边升边散：速度随寿命掉（烟到上面是飘着的，不是射上去的）。
		p.vel *= 1.0 - minf(1.0, 0.9 * delta)
		live = live or p.life > 0.0
	# 池子里一颗活的都没有、这一帧也没生新的（比如刚被回收又建回来）就不重画：
	# 区块有一半时间是滚出视野之外的，那些区块没必要每帧重铺一遍烟团。
	if live:
		queue_redraw()


func _spawn_puff() -> void:
	var p := _take_puff()
	if p == null:
		return
	p.pos = _mouth + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-4.0, 0.0))
	p.vel = Vector2(
		_rng.randf_range(-PUFF_DRIFT, PUFF_DRIFT),
		-_rng.randf_range(PUFF_SPEED_MIN, PUFF_SPEED_MAX),
	)
	p.life = _rng.randf_range(PUFF_LIFE_MIN, PUFF_LIFE_MAX)
	p.span = p.life
	p.size = PUFF_SIZE * _rng.randf_range(0.65, 1.35)
	p.tint = _rng.randf_range(0.88, 1.12)


## 取一个空槽位。池子满了就**不生成**（沙尘暴那边是复用游标处的，这里少了就少了 ——
## 烟柱短，颗粒数本来就不该无限涨）。
func _take_puff() -> Puff:
	for p in _puffs:
		if p.life <= 0.0:
			return p
	if _puffs.size() < PUFFS:
		var fresh := Puff.new()
		_puffs.append(fresh)
		return fresh
	return null


func _draw() -> void:
	if _area == null:
		return
	# 先画囱口那点暖色，再画烟：烟盖在火上，才像从里面冒出来的。
	draw_circle(_mouth, EMBER_R, Color(EMBER, EMBER_ALPHA))
	for p in _puffs:
		if p.life <= 0.0:
			continue
		var v := smoke_visual(p)
		if float(v["alpha"]) <= 0.004:
			continue
		draw_circle(p.pos, float(v["radius"]), v["color"])


## 一颗烟团这一帧该画成什么样：半径 + 颜色（含透明度）。
##
## 抽成函数是为了**能测**（沙尘暴的 `puff_visual` 立的规矩）：无头跑不一定发
## `NOTIFICATION_DRAW`，画里的算式没人验 —— 而「是不是真的越升越淡、越升越宽」
## 正是这套动画最容易写反的地方。
func smoke_visual(p: Puff) -> Dictionary:
	var t := p.life / p.span            # 1 是刚冒出来，0 是散尽
	var span_h := maxf(1.0, _chimney.end.y - _top)
	var up := clampf((_chimney.end.y - p.pos.y) / span_h, 0.0, 1.0)   # 0 屋面，1 柱顶
	var col := SMOKE_WARM.lerp(SMOKE_COOL, up)
	col.a = PUFF_ALPHA * t * (1.0 - up)
	return {
		# 越老越大（`PUFF_GROW` > 1）。烟团一路往上，于是「越老」在画面上就是「越高」。
		"radius": lerpf(p.size * PUFF_GROW, p.size, t),
		"alpha": col.a,
		"color": col,
	}
