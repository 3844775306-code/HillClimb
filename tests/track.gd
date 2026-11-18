extends Node
## 坦克履带（[TrackVisual]）的外观测试：跑真物理，量「画在哪」和「动不动」。
##
## 履带是纯外观，但它的位置是有硬契约的 —— 而且这里踩过一次：
##
## > 车开出半屏，履带还留在出发点上画。
##
## 原因是履带挂在**车的根节点**底下，而车的根节点是个普通 [Node2D]，整个游戏过程
## 里一次都不动 —— 真正在跑的是它下面那几个刚体（车壳和轮子，位置由物理服务器写）。
## 所以「履带跟着车走」这句话，靠树结构是**白送不了的**，得专门盯。
##
## 四件事：
##
##   1. 节点是**顶层**的（[member Node2D.top_level]）。这是让它画在世界坐标系里的
##      开关，也是上面那个 bug 的修法本身。
##   2. 闭环的中心 = 两个轮心的中点（等半径时由对称性严格成立）。
##   3. **车往前开，闭环也跟着往前挪同样的距离。** 这一条直接盯着那个 bug：
##      冻住的履带在这里会量出「车走了 800，履带走了 0」。
##   4. 轮子转起来之后履带齿的相位会推进 —— 不然履带跟着车走了，齿却钉死在带子上，
##      看着还是一条冻住的带子。
##
## **不截图。** 无头模式下截出来的图看不到判据，「履带在不在车下面」这件事用坐标
## 量比看图可靠得多，也不会因为换了台机器字体/抗锯齿不同就变。

const TANK := preload("res://scenes/vehicles/tank.tscn")

## 轮半径 24 + 铰链在车体 (0,14)：车壳静止时 y ≈ −38。
const REST_Y := 38.0
const SETTLE := 24
const RUN := 90          ## 1.5 秒
## 「履带跟着车」允许的误差。轮子挂在 [PinJoint2D] 上会有一点点软，车壳挪的时候
## 铰链会拉出几像素；再算上轮子上下摆动时切线几何的微小变化，10 px 已经很紧。
const SLACK := 10.0

var _failures := 0
var _world: Node2D


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()
	_build_world()
	await _run()
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


func _build_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40000.0, 1200.0)
	shape.shape = rect
	shape.position = Vector2(0.0, 600.0)
	body.add_child(shape)
	_world.add_child(body)


## 闭环所有点的平均值。
func _center_of(track: Node2D) -> Vector2:
	var pts: PackedVector2Array = track._loop
	if pts.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	return sum / float(pts.size())


func _run() -> void:
	print("=== 坦克履带 ===")
	var car: HillCar = TANK.instantiate()
	car.position = Vector2(0.0, -REST_Y)
	_world.add_child(car)
	car.apply_map(Maps.PLAINS)
	car.fuel = 1.0e9

	var track := car.get_node_or_null("Track") as Node2D
	if track == null:
		_check("车上有 Track 节点", false, "tank.tscn 里找不到 Track")
		return
	_check("车上有 Track 节点", true, "Track 是 %s" % track.get_class())

	for i in SETTLE:
		await get_tree().physics_frame

	_check("履带是顶层节点（坐标系不跟着不动的车根节点走）", track.top_level,
			"top_level = %s；车根节点在 %s，履带节点在 %s" % [
				str(track.top_level), str(car.global_position), str(track.global_position)])

	# 2：闭环中心就是两个轮心的中点。等半径时由对称性严格成立 —— 不等半径（谁把
	# 两个轮子画成一大一小）时中心会偏，所以这条同时也在盯着「两个轮子一样大」。
	var wheels: Array[RigidBody2D] = car.wheels
	var mid := (wheels[0].global_position + wheels[1].global_position) * 0.5
	var centre := _center_of(track)
	_check("闭环中心 = 两个轮心的中点", centre.distance_to(mid) <= 2.0,
			"闭环中心 %s，轮心中点 %s，差 %.1f px；闭环 %d 个点，周长 %.0f px" % [
				str(centre.round()), str(mid.round()), centre.distance_to(mid),
				(track._loop as PackedVector2Array).size(), track._total])

	# 闭环还得**贴着**两个轮子绕一圈。圈不住的话车下面露出来的就是两个光秃秃的轮子。
	#
	# 判据不能写成「包围盒装得下整个轮子」：闭环是按固定角步长采样出来的**多边形**，
	# 最外侧那一脚未必正好落在轮子的最外点上，包围盒因此比理想圆短几个像素 ——
	# 那是采样误差（弦往里凹），不是履带没圈住。改成量**每个采样点到两个轮心的距离**：
	# 有下界（不许切进胎面）也有上界（不许绕成把整个车框住的大圈）。
	#
	# **只在静止时量。** 闭环是每帧在自己那个 `_physics_process` 里按**当时**的轮心
	# 重建的，而轮子在紧接着的物理步里还要再走一格；车跑起来之后（470 px/s ≈ 8 px/帧）
	# 拿「重建时的闭环」去比「走完之后的轮子」，量到的是这一帧的滞后，不是形状。
	var band_lo := INF
	var band_hi := -INF
	for p in track._loop:
		var gap := INF
		for w: RigidBody2D in wheels:
			var circle := (w.get_node("Shape") as CollisionShape2D).shape as CircleShape2D
			gap = minf(gap, p.distance_to(w.global_position) - circle.radius)
		band_lo = minf(band_lo, gap)
		band_hi = maxf(band_hi, gap)
	_check("闭环贴着两个轮子绕（不切进胎面，也不框成一个大圈）",
			band_lo >= -1.0 and band_hi <= 8.0,
			"采样点离胎面 %.2f ~ %.2f px（下限 −1，上限 8）" % [band_lo, band_hi])

	# 3：**核心那一条。** 车往前开，闭环跟着往前挪同样的距离。
	var x0_car := car.chassis.global_position.x
	var x0_loop := centre.x
	var prev_phase: float = track._cleat_phase
	var phase_travel := 0.0
	Input.action_press("drive_forward")
	for i in RUN:
		await get_tree().physics_frame
		var d: float = track._cleat_phase - prev_phase
		if d < 0.0:
			d += track._total      # 相位取过模，绕回时要补一圈
		phase_travel += d
		prev_phase = track._cleat_phase
	Input.action_release("drive_forward")

	var d_car := car.chassis.global_position.x - x0_car
	var d_loop := _center_of(track).x - x0_loop
	_check("车往前开，履带跟着挪同样的距离", absf(d_loop - d_car) <= SLACK,
			"车挪了 %.0f px，履带挪了 %.0f px（差 %.0f，允许 %.0f）" % [
				d_car, d_loop, absf(d_loop - d_car), SLACK])
	_check("确实开起来了（不是原地不动才「跟着」的）", d_car > 200.0,
			"1.5 秒挪了 %.0f px" % d_car)

	# 4：履带齿在爬。
	_check("履带齿会沿履带往前爬（不是一条冻住的带子）", phase_travel > 100.0,
			"1.5 秒里齿爬了 %.0f px（履带一圈 %.0f px）" % [phase_travel, track._total])

	car.queue_free()
