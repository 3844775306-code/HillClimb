extends Node2D
## 车上的两套纯视觉特效：**踩油门时的尾气**、**轮子打滑扬起的碎屑**。
##
## ## 铁律：这里的一切都不许碰物理
##
## 这个节点只**读**物理状态（油门、轮子接触、接触点速度、轮子半径），只**写**自己
## 池子里的粒子，连随机数都用独立实例、不消耗全局 RNG。README 坑 #9 就是这么踩
## 出来的：一个「只是好看」的浮动动画让同种子的一局路程差了 37%。所以：
##
##   - 粒子活在**世界坐标**里，和刚体没有任何父子关系；
##   - 不碰任何 CollisionShape / position / physics_material，一个都不碰。
##
## tests/effects.tscn 跑两遍同一局（开特效 / 关特效）守着这条线。
##
## ## 挂法
##
## car.tscn 里挂在车根节点下、排在 Chassis **前面**，并且 `top_level = true`：
##
##   - `top_level` 让它的变换不继承车身，于是粒子存的就是世界坐标、画出来也就是
##     世界坐标。挂到轮子底下就错了 —— 轮子一转，已经落地的尘土会跟着转圈。
##   - 排在 Chassis 前面：同级节点按顺序画，于是它画在**地形之上、车体之下**，
##     尘土看起来是从车底扬起来的，而不是糊在车身上的贴纸。
##
## ## 两种粒子的来路
##
## 尾气是「发动机在使劲」的量度：轮子转不到目标转速（爬坡、打滑、被顶住）时烟更多
## 也更黑，和真车一个道理。碎屑是**接触点的搓动速度** —— 轮子表面那一点相对地面的
## 速度，公式见 [method _emit_dust]，纯滚动时它接近零，所以平路巡航只有一层薄尘，
## 空转/急刹才会炸开。

## 粒子池上限。**必须有上限**：原地空转可以一直出粒子，不封顶迟早拖垮帧率。
@export var max_grains := 220
## 关掉就不再产生新粒子（已有的会正常淡出）。测试拿它跑对照组。
@export var enabled := true

@export_group("尾气")
## 排气管口在**车体**坐标里的位置（车体左边缘是 x = -78）。
@export var exhaust_pipe := Vector2(-92.0, -8.0)
## 满油门时的出烟速率（颗/秒），实际还会乘以「发动机有多吃力」。
## 出得密一点、每颗小一点、淡一点：糊成一片才是烟，一滴一滴的圆点看着像气泡。
@export var exhaust_rate := 30.0
@export var exhaust_life := 0.8
@export var exhaust_size := 4.6
## 出管速度（像素/秒），相对车身算 —— 所以车越快烟越往后拖。
@export var exhaust_speed := 85.0
@export var exhaust_color := Color(0.66, 0.66, 0.69)
@export var exhaust_alpha := 0.34

@export_group("扬尘")
## 搓动速度拉满时的出粒速率（颗/秒），实际还要乘以「搓得多狠」。
@export var dust_rate := 120.0
@export var dust_life := 0.6
@export var dust_size := 5.0
@export var dust_alpha := 0.75

## 搓动速度到这个值算「拉满」。
const SCRUB_FULL := 300.0
## 纯滚动也带起一层薄尘：车速到这个值算「拉满」。
const ROLL_FULL := 2400.0
## 车速低于这个值就不拿它反推地面法线了（慢速时那点方向信息本来也不可信）。
const CONTACT_MIN_SPEED := 60.0
## 落地冲击超过这个速度才炸一朵土，免得下个缓坡也扬一片。
const LAND_MIN_SPEED := 260.0
const LAND_BURST := 14.0
## 尾气往上飘（浮力），碎屑往下落。单位都是像素/秒²。
const SMOKE_RISE := 50.0
const SMOKE_DRAG := 2.2
const DUST_DRAG := 1.1
## 发动机吃力时最高多冒多少烟（1.4 = 多一倍多）。
const EXHAUST_LOAD_BOOST := 1.4
## 吃力时的烟偏黑，像烧不干净的柴油。别压得太黑：火山那张图天是暗的，
## 再黑下去烟就没影了，所以停在「深灰」而不是「黑」。
const EXHAUST_DIRTY := Color(0.30, 0.29, 0.32)

const PIPE_DARK := Color(0.28, 0.29, 0.33)
const PIPE_MOUTH := Color(0.09, 0.09, 0.11)

## 碎块的形状，撒的时候随机挑一种，免得所有石块长得一模一样。
## 顶点都在单位圆附近，画的时候按粒子半径缩放、再按自转角度旋转。
##
## 写成 Vector2 的数组而不是 PackedVector2Array：后者的构造函数不算常量表达式
## （`const` 里用不了），而这里每帧都要按角度重算顶点，本来也得另建数组。
const CHUNK_SHAPES := [
	[
		Vector2(-1.0, -0.7), Vector2(1.1, -0.9), Vector2(0.8, 1.0), Vector2(-0.9, 0.8),
	],
	[
		Vector2(-1.1, 0.3), Vector2(0.1, -1.2), Vector2(1.0, 0.7),
	],
	[
		Vector2(-0.8, -1.0), Vector2(1.0, -0.4), Vector2(0.5, 1.1), Vector2(-1.1, 0.7),
	],
]

## 每种地形的碎屑风格。
##
## **颜色不在这里**：颜色一律从 [Maps] 的调色板取（`crust` 是地表那一层、`dirt` 是
## 下面的土），所以换配色只有一处要改，新地图不写这张表也能有一份说得过去的碎屑。
## 这里只放「手感」：
##
##   size       颗粒半径倍率        rate   出粒速率倍率
##   chunk      有棱角的碎块占比    lift   沿地面法线的初速（向外）
##   gravity    下坠加速度          mix    尘的颜色偏向 dirt 多少
##   chunk_mix  碎块的颜色偏向 dirt 多少    glow   碎块要不要带火星的光晕
##
## `mix` / `chunk_mix` 是**对比度**旋钮，不是配色：尘和碎块得有本事从脚下的地面里
## 跳出来。雪地那张最典型 —— 雪是白的、地表也是白的，混 20% 的灰根本看不见，
## 混到 50% 才在白雪上显出「被铲起来的一层」。
const STYLES := {
	Maps.PLAINS: {
		"size": 1.0, "rate": 1.0, "chunk": 0.35, "lift": 170.0,
		"gravity": 900.0, "mix": 0.45, "chunk_mix": 0.30, "glow": false,
	},
	Maps.DESERT: {
		# 沙子细、轻、量大：颗粒小一圈、数量多三成，重力只有平原的一半不到，
		# 所以扬起来之后会在空中多飘一会儿才落。
		"size": 0.8, "rate": 1.3, "chunk": 0.08, "lift": 130.0,
		"gravity": 420.0, "mix": 0.55, "chunk_mix": 0.65, "glow": false,
	},
	Maps.SNOW: {
		# 雪片几乎不往下掉：重力压到 260，看起来是被甩起来又慢慢飘下去。
		"size": 0.85, "rate": 1.2, "chunk": 0.15, "lift": 150.0,
		"gravity": 260.0, "mix": 0.50, "chunk_mix": 0.55, "glow": false,
	},
	Maps.VOLCANO: {
		# 碎块最多、最重（火山渣），而 crust 在这张图里是岩浆橙 —— 碎块自动就是
		# 火星，所以只有这一张图开 glow，而且碎块**一点 dirt 都不混**：
		# 混了就从火星变成黑渣，光晕白开。
		"size": 1.1, "rate": 0.9, "chunk": 0.45, "lift": 140.0,
		"gravity": 1100.0, "mix": 0.30, "chunk_mix": 0.0, "glow": true,
	},
}


## 一颗粒子。池子只复用、不新建（见 [method _take]）。
## 用一个内部类而不是几个平行数组：字段一多，平行数组的索引就对不上了。
class Grain:
	extends RefCounted
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	## 剩余寿命；<= 0 表示这个槽位是空的，可以复用。
	var life := 0.0
	## 出生时的寿命，用来算淡出比例（life / span）。
	var span := 1.0
	var size := 1.0
	## 死亡时的半径倍率（烟会散开、碎块不变大）。
	var grow := 1.0
	var angle := 0.0
	var spin := 0.0
	## 形状索引（只对碎块有意义）。
	var shape := 0
	## true = 有棱角的碎块，false = 圆的尘/雪/烟。
	var chunk := false
	var glow := false
	var gravity := 0.0
	var drag := 0.0
	var color := Color.WHITE


## 独立的随机数发生器。**不用全局 randf()**：那会和别处的随机共用一条流，于是
## 「加了个特效」就能改变云和油桶的位置 —— 坑 #9 的同一种病。
## 固定种子，所以截图和测试逐次可复现。
var _rng := RandomNumberGenerator.new()

var _car: HillCar = null
## 两个轮子，顺序和 [member _radius] 一一对应。
var _wheels: Array[RigidBody2D] = []
## 轮子半径，从碰撞形状里读 —— 不在这儿抄一份 car.tscn 的数字。
var _radius: Array[float] = []
var _grains: Array[Grain] = []
## 池子满时用来挑牺牲者的游标。
var _cursor := 0
## 出粒累加器（按秒攒，攒够一颗就撒一颗，所以和帧率无关）。
var _dust_accum: Array[float] = []
var _smoke_accum := 0.0
## 上一帧的落地状态和速度，用来判断「这一帧刚砸到地上」以及砸得多重。
var _prev_on_ground: Array[bool] = []
var _prev_vel: Array[Vector2] = []
## 上一帧画面上还有没有粒子。粒子死光的**那一帧**必须再画一次，
## 否则最后一批粒子会僵在屏幕上不退场。
var _was_live := false

## 当前地图的碎屑风格与取色，[method _refresh_style] 按 [member HillCar.map_id] 刷。
var _map_id := ""
var _style: Dictionary = STYLES[Maps.PLAINS]
var _puff_color := Color.WHITE
var _chunk_color := Color.WHITE


func _ready() -> void:
	# 双保险：编辑器里忘了勾也能跑（真忘了勾，粒子会跟着车身一起转）。
	top_level = true
	position = Vector2.ZERO
	rotation = 0.0
	_rng.seed = 0x5EED


## 第一帧才去找车的部件。
##
## **不能在 `_ready()` 里找**：Godot 的 `_ready` 是子节点先跑，而这个节点是车的
## 子节点，所以那时候 [HillCar] 的 `@onready`（chassis / wheels …）还全是 null。
## 拖到第一帧，车的 `_ready` 早就跑完了。
func _resolve() -> void:
	_car = get_parent() as HillCar
	if _car == null:
		push_warning("Effects 得挂在 HillCar 底下，否则它不知道油门和轮子在哪。")
		return
	# 走 [member HillCar.wheels] 而不是 `rear_wheel` / `front_wheel`：那一对在独轮车上
	# 是同一个轮子，写成一数组会让它被收两遍 —— 尘土加倍、而且不报错。
	for wheel: RigidBody2D in _car.wheels:
		_wheels.append(wheel)
		_radius.append(_shape_radius(wheel))
		_dust_accum.append(0.0)
		_prev_on_ground.append(false)
		_prev_vel.append(Vector2.ZERO)
	_refresh_style()


## 轮子半径从**碰撞形状**里读。写成常量的话，哪天轮子调大了，碎屑会从轮子里面
## 冒出来 —— 而且没人会想到要去改特效。
func _shape_radius(wheel: RigidBody2D) -> float:
	var node := wheel.get_node_or_null("Shape") as CollisionShape2D
	if node != null and node.shape is CircleShape2D:
		return (node.shape as CircleShape2D).radius
	return 21.0


## 按当前地图刷新碎屑的风格和取色。
func _refresh_style() -> void:
	_map_id = _car.map_id
	_style = STYLES.get(_map_id, STYLES[Maps.PLAINS])
	var pal: Dictionary = Maps.get_map(_map_id)
	var crust: Color = pal["crust"]
	var dirt: Color = pal["dirt"]
	# 扬起来的主要是地表那一层（地形上那条 crust 色的边），所以颜色以 crust 为主、
	# 往 dirt 混一点。火山那张图 crust 是岩浆橙、dirt 是黑渣，混出来正好是暗红灰。
	_puff_color = crust.lerp(dirt, float(_style["mix"]))
	# 碎块同样以地表色起手：平原是草屑、荒漠是沙粒、雪地是冰碴、火山是火星。
	# 混多少 dirt 各图自己定（见 STYLES 的 chunk_mix）。
	_chunk_color = crust.lerp(dirt, float(_style["chunk_mix"]))


func _process(delta: float) -> void:
	if _car == null:
		_resolve()
		if _car == null:
			return
	if _car.map_id != _map_id:
		_refresh_style()
	if enabled:
		_emit_exhaust(delta)
		for i in _wheels.size():
			_detect_landing(i)
			_emit_dust(i, delta)
	var live := _step(delta)
	if live > 0 or _was_live:
		queue_redraw()
	_was_live = live > 0


## 推进所有粒子。返回还活着的颗数。
func _step(delta: float) -> int:
	var live := 0
	for g in _grains:
		if g.life <= 0.0:
			continue
		g.life -= delta
		if g.life <= 0.0:
			continue
		live += 1
		g.vel.y += g.gravity * delta
		# 隐式阻尼：vel /= (1 + k·dt) 对任何步长都稳定，显式的 vel *= (1 - k·dt)
		# 在 dt 大一点的时候会过冲变成负速度（粒子倒着飞）。
		g.vel /= 1.0 + g.drag * delta
		g.pos += g.vel * delta
		g.angle += g.spin * delta
	return live


## 当前活着的粒子数。给测试用（tests/effects.gd 靠它确认特效真的在跑，
## 否则「开特效和关特效结果一样」会被一个根本没出粒子的实现骗过去）。
func live_count() -> int:
	var n := 0
	for g in _grains:
		if g.life > 0.0:
			n += 1
	return n


# ---------------------------------------------------------------- 尾气

func _emit_exhaust(delta: float) -> void:
	if not _car.alive or not _car.engine_on:
		return
	var th := absf(_car.throttle)
	if th < 0.05:
		return
	# 发动机有多吃力：轮子离目标转速越远，说明坡越陡/越滑/被顶得越死。
	var peak := maxf(absf(_car.max_wheel_speed), 1.0)
	var load := clampf(1.0 - absf(_car.rear_wheel.angular_velocity) / peak, 0.0, 1.0)
	_smoke_accum += exhaust_rate * th * (1.0 + load * EXHAUST_LOAD_BOOST) * delta
	while _smoke_accum >= 1.0:
		_smoke_accum -= 1.0
		_spawn_smoke(load)


func _spawn_smoke(load: float) -> void:
	var chassis := _car.chassis
	# 管口朝哪：车体局部 -x 在世界里的方向。
	var back := -chassis.transform.x.normalized()
	var g := _take()
	g.chunk = false
	g.glow = false
	# 管口那一小段长度上也撒开一点，不然烟会从同一个点上长出来，像一串珠子。
	g.pos = chassis.to_global(exhaust_pipe + Vector2(_rng.randf_range(0.0, 9.0), 0.0))
	# 垂直于出管方向的散开量：让烟锥有宽度，而不是一条线。
	var side := Vector2(-back.y, back.x) * _rng.randf_range(-22.0, 22.0)
	# 初速 = 车身速度 + 相对车身的出管速度 + 一点上飘。车身速度那一项是关键：
	# 车往前跑的时候烟只比车慢一点，于是看起来是「被甩在后面」，而不是定在车尾。
	g.vel = chassis.linear_velocity * 0.85 \
		+ back * exhaust_speed * _rng.randf_range(0.5, 1.3) + side \
		+ Vector2(0.0, -25.0) * _rng.randf_range(0.2, 1.0)
	g.life = exhaust_life * _rng.randf_range(0.75, 1.25)
	g.span = g.life
	g.size = exhaust_size * _rng.randf_range(0.7, 1.3)
	# 1.7 而不是更大：涨得太快，几颗就糊成一块，反而又变回「大圆点」。
	g.grow = _rng.randf_range(1.5, 1.9)
	g.gravity = -SMOKE_RISE
	g.drag = SMOKE_DRAG
	g.color = exhaust_color.lerp(EXHAUST_DIRTY, load)
	g.color.a = exhaust_alpha


# ---------------------------------------------------------------- 碎屑

func _detect_landing(i: int) -> void:
	var wheel := _wheels[i]
	var on := _on_ground(wheel)
	if on and not _prev_on_ground[i] and _prev_vel[i].length() > LAND_MIN_SPEED:
		_burst(i, _prev_vel[i].length())
	_prev_on_ground[i] = on
	_prev_vel[i] = wheel.linear_velocity


## 砸地扬起来的那一朵。方向和打滑的相反：不是一条线，是以接触点为心朝上半圈炸开。
func _burst(i: int, impact: float) -> void:
	var wheel := _wheels[i]
	var dir := _ground_dir(wheel)
	var origin := wheel.global_position + dir * _radius[i]
	var count := int(clampf(LAND_BURST * impact / LAND_MIN_SPEED, 3.0, LAND_BURST * 2.0))
	for k in count:
		var out := (-dir).rotated(_rng.randf_range(-1.1, 1.1))
		var vel := out * impact * _rng.randf_range(0.08, 0.26)
		_spawn_dust(origin + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-5.0, 3.0)), vel)


func _emit_dust(i: int, delta: float) -> void:
	var wheel := _wheels[i]
	if not _on_ground(wheel):
		# 离地就不再攒：不清零的话，落地瞬间会把空中攒的都补喷出来。
		_dust_accum[i] = 0.0
		return
	var dir := _ground_dir(wheel)
	# 地面到轮心的方向（轮心在地面法线正上方 r 处）。
	var p := dir * _radius[i]
	# **搓动速度**：轮子上接触点那一点相对地面的速度。
	#   点的速度 = 刚体速度 + ω × p，2D 里 ω × p = ω * (-p.y, p.x)
	# 纯滚动时 v = ω·r，这一项正好抵消成 0；空转时它朝后、急刹时它朝前 ——
	# 所以碎屑会朝轮子真正在搓的那个方向飞，不需要另外判断油门正负。
	var scrub := wheel.linear_velocity + Vector2(-p.y, p.x) * wheel.angular_velocity
	var roll := wheel.linear_velocity.length()
	var amount := clampf(scrub.length() / SCRUB_FULL, 0.0, 1.0) + roll / ROLL_FULL
	_dust_accum[i] += dust_rate * float(_style["rate"]) * amount * delta
	while _dust_accum[i] >= 1.0:
		_dust_accum[i] -= 1.0
		var origin := wheel.global_position + p
		var vel := scrub * _rng.randf_range(0.35, 0.7) \
			+ (-dir) * float(_style["lift"]) * _rng.randf_range(0.5, 1.2)
		_spawn_dust(origin, vel)


## 轮心指向地面的方向。
##
## 用**车速方向**反推地面法线：轮子被地面约束着，落地时它的速度方向基本就贴着
## 坡面，所以速度的垂线就是法线。直接用世界坐标的「正下方」在 40° 的坡上会偏出去
## 20 多个像素 —— 碎屑会从地底下、而不是从轮胎底下冒出来。
func _ground_dir(wheel: RigidBody2D) -> Vector2:
	var v := wheel.linear_velocity
	if v.length() > CONTACT_MIN_SPEED:
		return Vector2(-v.y, v.x).normalized()
	return Vector2.DOWN


## 轮子是不是压在地形上。判据和 [method HillCar._update_airborne] 一致：只看
## `"ground"` 组，不看「碰到了任何东西」—— 车自己的两个轮子在几何上是重叠的
## （靠关节的 disable_collision 才不打架），按后者判会永远算着地。
func _on_ground(wheel: RigidBody2D) -> bool:
	for body in wheel.get_colliding_bodies():
		if body.is_in_group("ground"):
			return true
	return false


func _spawn_dust(pos: Vector2, vel: Vector2) -> void:
	var g := _take()
	var chunk := _rng.randf() < float(_style["chunk"])
	g.pos = pos
	g.vel = vel + Vector2(_rng.randf_range(-45.0, 45.0), _rng.randf_range(-45.0, 45.0))
	g.life = dust_life * _rng.randf_range(0.7, 1.3)
	g.span = g.life
	g.gravity = float(_style["gravity"])
	g.drag = DUST_DRAG
	g.chunk = chunk
	g.glow = chunk and bool(_style["glow"])
	if chunk:
		g.size = dust_size * float(_style["size"]) * _rng.randf_range(0.8, 1.5)
		g.grow = 1.0
		g.angle = _rng.randf_range(0.0, TAU)
		g.spin = _rng.randf_range(-9.0, 9.0)
		g.shape = _rng.randi_range(0, CHUNK_SHAPES.size() - 1)
		g.color = _jitter(_chunk_color, 0.18)
	else:
		# 尘会边飘边散开，所以半径越老越大。
		g.size = dust_size * float(_style["size"]) * _rng.randf_range(0.7, 1.3)
		g.grow = 1.9
		g.color = _jitter(_puff_color, 0.12)
	g.color.a = dust_alpha


## 给颜色加一点明暗抖动，免得一片碎屑像一块纯色板。
func _jitter(base: Color, amount: float) -> Color:
	var k := 1.0 + _rng.randf_range(-amount, amount)
	return Color(clampf(base.r * k, 0.0, 1.0), clampf(base.g * k, 0.0, 1.0), clampf(base.b * k, 0.0, 1.0))


# ---------------------------------------------------------------- 池子

## 取一个空槽位。池子满了就复用游标处那颗 —— 视觉上它只是提前退场，物理毫发无损
## （这正是「粒子必须和物理无关」的好处：丢一颗粒子不需要任何补偿）。
func _take() -> Grain:
	for g in _grains:
		if g.life <= 0.0:
			return g
	if _grains.size() < max_grains:
		var fresh := Grain.new()
		_grains.append(fresh)
		return fresh
	_cursor = (_cursor + 1) % _grains.size()
	return _grains[_cursor]


# ---------------------------------------------------------------- 画

func _draw() -> void:
	_draw_pipe()
	for g in _grains:
		if g.life <= 0.0:
			continue
		var t := g.life / g.span
		var col := g.color
		col.a *= t
		if col.a <= 0.004:
			continue
		if g.chunk:
			var r := g.size
			if g.glow:
				# 火星的光晕。压在碎块**下面**画，不然会把碎块自己糊掉。
				draw_circle(g.pos, r * 2.6, Color(1.0, 0.62, 0.22, col.a * 0.20))
			draw_colored_polygon(_chunk_points(g, r), col)
		else:
			draw_circle(g.pos, lerpf(g.size * g.grow, g.size, t), col)


## 排气尾管。画在车体坐标里，所以跟着车身转 —— 它算是车的外观，不是特效，
## `enabled = false` 时也照样画。
func _draw_pipe() -> void:
	if _car == null:
		return
	var chassis := _car.chassis
	var base := chassis.to_global(exhaust_pipe + Vector2(14.0, 0.0))
	var mouth := chassis.to_global(exhaust_pipe)
	draw_line(base, mouth, PIPE_DARK, 7.0)
	# 两头各补一个圆，装成圆头的管子（draw_line 没有圆头）。
	draw_circle(base, 3.5, PIPE_DARK)
	draw_circle(mouth, 3.5, PIPE_MOUTH)


func _chunk_points(g: Grain, r: float) -> PackedVector2Array:
	var src: Array = CHUNK_SHAPES[g.shape]
	var out := PackedVector2Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = g.pos + src[i].rotated(g.angle) * r
	return out
