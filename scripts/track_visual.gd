extends Node2D
## 坦克的履带。**纯外观，不参与碰撞** —— 车底下真正推车走的还是那两个圆形轮子，
## 见 `scenes/vehicles/tank.tscn` 里「为什么不做成一条真履带」那段。
##
## 挂在**车的根节点下、排在两个轮子后面**：同级节点按顺序画，排在后面才画得在
## 轮子上面（挂在 Chassis 底下的话会被两个轮子盖住）。
##
## 轮子从 [method Vehicles.wheels_of] 收 —— 和 [HillCar] 收轮子用的是同一份判据，
## 所以轮子挪了位置、换了半径，履带回自己跟着变，不用同步任何常量。
##
## 画法：把每个轮子当成一个圆，取两个圆的**外公切线**，配两段圆弧围成闭环
## （等半径时就是标准跑道形）。切线端点的角度是唯一有推导的地方，写在
## [method _closed_loop] 里。
##
## ## 这个节点必须是**顶层**的（`top_level = true`）
##
## 车的根节点是个普通 [Node2D]，整个游戏过程中**一次都不动**：真正在跑的是它下面
## 那几个刚体（车壳和轮子，位置由物理服务器写）。所以履带要是当普通子节点挂在根
## 节点底下，它的变换就永远停在出发点上 —— 车开出半屏，履带还留在原地画。
##
## 提成顶层之后，这个节点的局部坐标系就是世界坐标系，于是可以**直接拿轮子的
## [member Node2D.global_position] 来画**，不用自己做任何父子换算。
##
## ## 每物理帧都要重算
##
## 两个轮子各挂在一个 [PinJoint2D] 上，会各自上下摆动，所以连**形状**都每帧在变
## （一边过坎时两个轮心不再等高，闭环就成了个歪的跑道形）。在 `_ready` 里算一次
## 就够了的写法，在车一动的时候画面就散架。

## 履带中线比轮半径外扩多少像素。
const OUTSET := 3.0
## 履带画多粗。和 [constant OUTSET] 配起来，履带内缘正好压在胎面上。
const BAND_WIDTH := 7.0
## 每段圆弧采样多少个点。半径 24 的轮子绕半圈约 78 px，12 段已经看不出折线。
const ARC_STEPS := 12
## 履带齿的间距（沿履带量的像素）。半径 24 的轮子绕一圈约 172 px，
## 15 px 一颗差不多是履带该有的密度。
const CLEAT_SPACING := 15.0

const BAND_COLOR := Color(0.16, 0.17, 0.15, 1.0)
const CLEAT_COLOR := Color(0.36, 0.37, 0.32, 1.0)
const CLEAT_INNER := Color(0.09, 0.10, 0.09, 1.0)

## 两个轮子，**按车体里的左右次序**（`_wheels[0]` 在左）。`_ready` 里收一次。
var _wheels: Array[RigidBody2D] = []
## 闭环折线（世界坐标），每物理帧重算。
var _loop := PackedVector2Array()
## 两个轮心的世界坐标，撒履带齿时定「朝外」的方向用。
var _centers := PackedVector2Array()
## 闭环的总长（像素），和 [member _loop] 一起更新。
var _total := 0.0
## 履带齿沿履带爬了多远（像素）。见 [method _physics_process]。
var _cleat_phase := 0.0


func _ready() -> void:
	# 见类注释「这个节点必须是顶层的」。
	top_level = true
	_collect()
	if _wheels.size() != 2:
		# 收不到就永远收不到（轮子是被销子钉在车壳上的，身份一辈子不变），
		# 别每帧白算一遍。
		set_physics_process(false)
		return
	_step(0.0)


func _physics_process(delta: float) -> void:
	_step(delta)
	queue_redraw()


## 重算几何 + 推进履带齿的相位。
##
## 齿爬的速度就是履带面的线速度 = 轮角速度 × 轮半径。两个轮子转速可以不一样
## （一个打滑一个没打滑），取平均 —— 履带是**一条**，本来就只能有一个速度。
func _step(delta: float) -> void:
	_rebuild()
	if delta > 0.0 and _total > 0.001:
		var v := 0.0
		for wheel in _wheels:
			v += wheel.angular_velocity * _radius_of(wheel)
		v /= float(_wheels.size())
		# 取模到一圈的长度上，不然相位会一直涨到几百万，浮点精度早晚不够用
		# （履带齿的位置要靠它加出「第几像素」，精度掉了齿就会开始抖）。
		_cleat_phase = fposmod(_cleat_phase + v * delta, _total)


## 收轮子。**只在 `_ready` 里收一次**：轮子被 [PinJoint2D] 钉在车壳上，
## 是哪两个一辈子不变（位置每帧都变，身份不变）。
##
## 走 [method Vehicles.wheels_of] 而不是 `get_parent().wheels`：后者是 [`@onready`]，
## 而 Godot 的 `_ready` 是**子节点先跑** —— 这个节点也是车的子节点，那时候
## `wheels` 还是空的。
func _collect() -> void:
	var car := get_parent() as Node2D
	if car == null:
		push_warning("履带得挂在车（Node2D）底下，否则不知道轮子在哪。")
		return
	var found := Vehicles.wheels_of(car)
	# 履带是「两个轮子之间」的东西，轮数不是 2 就没意义。**不静默什么都不画** ——
	# 那种错看起来像「履带没加载出来」，查起来要翻半天。
	if found.size() != 2:
		push_warning("履带要两个轮子，%s 上有 %d 个，不画。" % [car.name, found.size()])
		return
	_wheels = [found[0], found[1]]
	# 按**车体局部** x 排序，不依赖场景里的节点次序：切线那套推导默认「第一个在左」。
	# 用局部坐标而不是世界坐标 —— 车翻过来时世界 x 会反号，按世界坐标排的话
	# 「左边那个轮子」会跟着翻，闭环的绕行方向也跟着反，齿的滚动方向就错了。
	if _wheels[0].position.x > _wheels[1].position.x:
		_wheels.reverse()


func _rebuild() -> void:
	_centers = PackedVector2Array([
		_wheels[0].global_position, _wheels[1].global_position])
	_loop = _closed_loop(
		_centers[0], _radius_of(_wheels[0]) + OUTSET,
		_centers[1], _radius_of(_wheels[1]) + OUTSET)
	_total = 0.0
	for i in _loop.size():
		_total += _loop[i].distance_to(_loop[(i + 1) % _loop.size()])


func _draw() -> void:
	if _loop.size() < 3:
		return
	# 一笔画完整个闭环。`antialiased` 开着，否则斜着的切线是锯齿。
	var pts := _loop.duplicate()
	pts.append(_loop[0])
	draw_polyline(pts, BAND_COLOR, BAND_WIDTH, true)
	_draw_cleats()


## 把两个圆的闭环摊成一条折线：左圆远侧半圈 → 上切线 → 右圆远侧半圈 → 下切线。
##
## **端点角度怎么来的**：设 u = (cos θ, sin θ) 是圆心指向切点的单位向量。两个切点
## 连成的线既是切线，就必须和 u 垂直，即 `(c₂ − c₁)·u + r₂ − r₁ = 0`，也就是
## `cos(θ − base) = (r₁ − r₂) / dist`（`base` 是 c₁ 指向 c₂ 的方向角）。
## 所以两个切点的角度就是 `base ± acos((r₁ − r₂) / dist)` —— **而且两个圆上的
## 切点角度是同一个数**，这正是「外公切线」的定义。等半径时 acos(0) = 90°，
## 退化成「垂直于连心线」，围出来就是跑道形。
##
## 半径差大于圆心距时 `acos` 会拿到越界的值（理论上不会出现，除非有人把两个轮子
## 画得一大一小还挨得极近）：clamp 一下退化成近似内切，画出来是歪的但不会崩。
##
## 参数是**世界坐标**的圆心和半径，不是节点 —— 这个节点是顶层的，画的就是世界坐标。
func _closed_loop(ca: Vector2, ra: float, cb: Vector2, rb: float) -> PackedVector2Array:
	var d := cb - ca
	var dist := d.length()
	if dist < 0.001:
		return PackedVector2Array()
	var base := d.angle()
	var off := acos(clampf((ra - rb) / dist, -1.0, 1.0))
	# 左圆从下方切点绕**远侧**（角度递增、经过 base + π）到上方切点；
	# 右圆从上方切点经过 base 那一侧到下方切点，也是递增。
	#
	# 绕行方向不是随便定的：这样一圈走下来，**下边那一趟是从右往左**的，正好是
	# 履带往前开时下侧履带相对车身的运动方向 —— [member _cleat_phase] 靠这个才有
	# 正确的滚动方向（见 [method _draw_cleats]）。
	var out := PackedVector2Array()
	_append_arc(out, ca, ra, base + off, base - off + TAU)
	_append_arc(out, cb, rb, base - off, base + off)
	return out


## 从 [param from] 到 [param to] 沿圆弧采 [constant ARC_STEPS] + 1 个点，
## **角度只增不减** —— 跨越 ±π 的那一段由调用方在 [param to] 上加 TAU 补回来。
func _append_arc(out: PackedVector2Array, center: Vector2, radius: float,
		from: float, to: float) -> void:
	for i in range(ARC_STEPS + 1):
		var t := float(i) / float(ARC_STEPS)
		out.append(center + Vector2.from_angle(lerpf(from, to, t)) * radius)


## 履带齿：沿闭环每隔 [constant CLEAT_SPACING] 画一小段跨过履带的短线。
##
## **按弧长撒而不是按角度撒**：两段直线的中点也该有齿，按角度撒的话直线段上
## 一颗都没有。齿的方向取「离最近的那个轮心往外」，直线段上就是垂直于履带。
##
## 每颗齿的位置再加上 [member _cleat_phase] —— **这一步不能省**。不加的话履带跟着
## 车一起走了、齿却钉死在带子上，看着是一条冻住的带子；加了才是「履带在转」。
func _draw_cleats() -> void:
	if _total <= 0.001:
		return
	var n := _loop.size()
	# 先把每段的长度量出来，之后按「走到第几像素」反查落在哪一段上。
	var segs := PackedFloat32Array()
	for i in n:
		segs.append(_loop[i].distance_to(_loop[(i + 1) % n]))
	# 颗数是整数，所以实际间距是 `total / count`（略微偏离常量），这样最后一颗
	# 正好落在起点上、不会和第一颗挤在一起。
	var count := maxi(1, int(_total / CLEAT_SPACING))
	var spacing := _total / float(count)
	for k in count:
		var want := fposmod(float(k) * spacing + _cleat_phase, _total)
		var walked := 0.0
		for i in n:
			if walked + segs[i] >= want:
				var t := (want - walked) / maxf(segs[i], 0.0001)
				_draw_one_cleat(_loop[i].lerp(_loop[(i + 1) % n], t))
				break
			walked += segs[i]


func _draw_one_cleat(p: Vector2) -> void:
	var outward := (p - _nearest_center(p))
	if is_zero_approx(outward.length_squared()):
		return
	outward = outward.normalized()
	draw_line(p - outward * (BAND_WIDTH * 0.9), p + outward * (BAND_WIDTH * 0.9),
			CLEAT_COLOR, 3.0)
	# 齿尖再压一道深色：看着像嵌进履带里的方块，而不是贴上去的一条线。
	draw_line(p + outward * (BAND_WIDTH * 0.2), p + outward * (BAND_WIDTH * 0.9),
			CLEAT_INNER, 2.0)


## 离 [param p] 最近的那个轮心。
func _nearest_center(p: Vector2) -> Vector2:
	var best := _centers[0] if not _centers.is_empty() else p
	var best_d := INF
	for c in _centers:
		var d := c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


## 轮半径从**碰撞形状**里读，和别处一样：`wheel_visual` 的 `radius` 只是个画图参数，
## 真正决定轮子多大的是那个碰撞圆（`tests/vehicles` 的契约一节也盯着这件事）。
func _radius_of(wheel: RigidBody2D) -> float:
	var node := wheel.get_node_or_null("Shape") as CollisionShape2D
	if node != null and node.shape is CircleShape2D:
		return (node.shape as CircleShape2D).radius
	return 21.0
