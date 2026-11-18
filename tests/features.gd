extends Node
## 四张新地形的实测：山地的石子、隧道、月球的重力与环形山、森林的树。
##
## 需求原话是五条：
##
##   1. 山地：地上每隔一段距离有些小石子，摩擦力更大、起伏更大
##   2. 隧道：司机碰到隧道上壁也会死亡；**整段路都有上壁**，上壁离地面的距离
##      **随机波动**，每隔一段距离倒挂一些钟乳石，头撞到就死
##   3. 月球：重力作用更小
##   4. 月球：环形山是**凹字形**、一次**连着 3～5 个**，轮子会陷进去，
##      最好借低重力跃过去
##   5. 森林：每隔一段距离一棵树，只有高速撞击才能推倒、否则被弹回，
##      而且**树的高度和越野车高度一样**
##
## 摩擦和起伏是 [Maps] 里的两个倍率（`friction_scale` / `amp_scale`），
## 由 tests/maps.gd 盯着；这个套件管**摆上去的东西和挖出来的东西**：石子、石拱、
## 钟乳石、树、一排环形山，外加月球的重力（唯一一条「改的是车、不是地形」的需求）。
##
## 屋顶图的烟囱也在这儿（[scripts/chimneys.gd]）：它同时是**摆上去的东西**（一根砖
## 柱子长在某一级平屋面上）和**改车的东西**（囱口的烟把车往上托），于是分两节 ——
## 摆位是纯几何、托力必须跑真物理。
##
## ## 车高、洞顶、树高：三个数互相钉死
##
## 车高是从 scenes/car.tscn **现量的**（车轮半径 + 车手头的半径和位置），
## 不是抄一个常数。洞顶的下限、钟乳石的长度上限、树高都拿去和这个量出来的车高比：
## 抄一个 116 的话，哪天玩家在编辑器里把车调高了，洞还按老高度盖、
## 「正常开过去就撞顶」这种错会被测试原样放过去。
##
## ## 有的节用真实起伏、有的节用平地
##
## 摆位（石子贴不贴地、树站没站在地上）**必须**用真实起伏测：
## 「按本段左沿的高度摆」和「按脚下的地表摆」在平地上没有区别 —— 而那正是
## 这里最容易犯的错。跑车（撞顶、推倒、弹回）**必须**压平地形：
## 不压平的话「到树跟前还剩多少速度」是随机的，同一个坑赶上坡就冲不过去。

const CAR := preload("res://scenes/car.tscn")
const STONES := preload("res://scenes/stones.tscn")
const TUNNEL := preload("res://scenes/tunnel.tscn")
const TREES := preload("res://scenes/trees.tscn")

## `stretch/aspect = expand` 下画布高能出到的三档。基准是 1280×720，比 16:9 更宽的
## 机器保持 720、两侧多出来；比 16:9 更**窄**的机器才会长高：
##
##   16:9 手机  1280×720
##   3:2  手机  1280×853   （2160×1440 ÷ 1.6875）
##   4:3  平板  1280×960   （1024×768 ÷ 0.8）
##
## 隧道的上壁厚度要盖住屏幕上半，**画布越高要求越厚**，所以这里取的是最紧的那一档。
const CANVAS_HEIGHTS := [720, 853, 960]

const STONES_SCRIPT := preload("res://scripts/stones.gd")
const TUNNEL_SCRIPT := preload("res://scripts/tunnel.gd")
const TREES_SCRIPT := preload("res://scripts/trees.gd")
const CHIMNEYS_SCRIPT := preload("res://scripts/chimneys.gd")

const SEED := 1337
const CHUNKS := 80
## 「在附近找一块 XXX 的区块」这类挑块循环的搜索长度（区块数）。
##
## 挑块是为了让某一条断言有东西可测（比如「洞顶跟着当地地表走」在平地上测不出
## 东西），但**搜索范围不能是整张图**：地形起伏过了 2 km 是按复利涨、不封顶的
## （[constant HillTerrain.GROWTH_RATE]），「起伏最大的一块」会一路飘到 6 km 开外，
## 而那儿的形状类地形已经被逼得不像样了 —— 隧道断面能测出来的东西只剩「它没崩」。
## 16 块 = 出生点往后到 1.6 km，正好是**一趟跑得出来的范围**，也还在复利起点
## （2 km）之内，于是这一节不会被幅度那边的改动牵着走。
const NEAR_CHUNKS := 16
## 车出生点比地面高多少（和 scenes/main.tscn 里 Car 的摆位一致）。
const CAR_LIFT := 39.0
const DT := 1.0 / 60.0
const SETTLE_FRAMES := 12
## 助跑距离。够长才能冲到极速，又要让起点落在**前一个区块**里 ——
## 起点在区块外的话，区块还没建出来车就已经到了。
const RUN_UP := 700.0
const CW := HillTerrain.CHUNK_WIDTH
## 洞里正常开过去时，车顶离石头（含钟乳石尖）至少要剩多少像素。
##
## 「不会撞到」不能只量「> 0」—— 贴着 1 像素擦过去也算「没碰到」，玩家看到的是
## 一路刮着石头开。车会颠、会被山丘抛起来，所以余量得留够。整条洞顶是按实测
## 抬过两次的（见 scripts/tunnel.gd 的 HEAD_GAP_MIN），实测最紧处 60 上下。
const TUNNEL_MARGIN := 50.0
## 「正常速度」碾过石子路时油门收到多快（像素/秒）。
##
## 满油门平地极速 800 上下。300 差不多是玩家过一段碎石路会用的速度 ——
## 需求里石子是「颠一下」，不是「必须全油门冲过去」。
const SLOW_CAP := 300.0
## 烟囱那两节往前查多少栋房子。
##
## 一栋房子里只有「中间那几级平屋面」摆得下烟囱，而**一半以上的房子压根没有中间
## 平屋面**（只分得出一级钢梯，见 [method HillTerrain.roof_profile]）：能摆的栋数
## 大概是 `0.45 × 能摆的比例`。40 栋里稳定有五六根 —— 跑车那节还要从里面挑一栋。
const CHIMNEY_SCAN := 40


## 测试专用地形：地表恒定，见文件头「有的节用真实起伏、有的节用平地」。
class FlatTerrain extends HillTerrain:
	func _base_height(_x: float) -> float:
		return GROUND_Y


var _failures := 0
var _assertions := 0
var _world: Node2D
var _terrain: HillTerrain
var _car: HillCar


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()

	_section_stones_place()
	await _section_stones_drive()
	_section_tunnel_plan()
	_section_tunnel_shape()
	await _section_tunnel_drive()
	await _section_tunnel_die()
	_section_craters_plan()
	_section_craters_shape()
	await _section_trees_place()
	await _section_trees_slow()
	await _section_trees_fast()
	await _section_moon_gravity()
	_section_chimneys_place()
	await _section_chimneys_lift()

	print("")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


func _approx(label: String, got: float, want: float, tol: float = 0.001) -> void:
	_check(label, absf(got - want) <= tol, "%.4f（期望 %.4f ±%.4f）" % [got, want, tol])


## 相对误差断言。用在「量出来的东西应该等于某条公式」的地方。
func _within(label: String, got: float, want: float, rel: float) -> void:
	var ok := absf(got - want) <= absf(want) * rel
	_check(label, ok, "%.1f（期望 %.1f ±%.0f%%）" % [got, want, rel * 100.0])


# ---------------------------------------------------------------- 量车

## 车高（像素）：车轮底到车手头顶，在 Car 的局部坐标里算。
##
## 就是用户说的「越野车的高度」。树高要等于它，洞顶的下限要从它推。
## **从场景现量**，不抄常数 —— 见文件头。
func _car_height() -> float:
	var car := CAR.instantiate()
	var wheel: Node2D = car.get_node("RearWheel")
	var wheel_shape: CircleShape2D = (car.get_node("RearWheel/Shape") as CollisionShape2D).shape
	var chassis: Node2D = car.get_node("Chassis")
	var head: Node2D = car.get_node("Chassis/Head")
	var head_shape: CircleShape2D = (car.get_node("Chassis/Head/HeadShape") as CollisionShape2D).shape
	var bottom := wheel.position.y + wheel_shape.radius
	var top := chassis.position.y + head.position.y - head_shape.radius
	car.free()
	return bottom - top


## 车手头顶高出**车身原点**多少（像素，往上为正）。
##
## 洞顶上壁厚度那条推导要用它（见 [constant CANVAS_HEIGHTS] 那一段），
## 量的是 [method _car_height] 的那个「顶」，只是不要车轮那一截 ——
## 因为镜头跟的是**车身刚体**的位置，不是整个车场景的原点。
func _head_above_chassis() -> float:
	var car := CAR.instantiate()
	var head: Node2D = car.get_node("Chassis/Head")
	var head_shape: CircleShape2D = (car.get_node("Chassis/Head/HeadShape") as CollisionShape2D).shape
	# 车身的局部坐标里 y 向下，所以「头顶」是 head.position.y − 半径，取负才是高出多少。
	var top := head.position.y - head_shape.radius
	car.free()
	return -top


func _wheel_radius() -> float:
	var car := CAR.instantiate()
	var shape: CircleShape2D = (car.get_node("RearWheel/Shape") as CollisionShape2D).shape
	var r := shape.radius
	car.free()
	return r


# ---------------------------------------------------------------- 场景搭建

## 找出这个种子下、这张图上第一块**本来**会摆特殊地形的区块。
##
## **问 [method Maps.feature_at]，不问地形的 `feature_kind_at`**：这里要的是
## 「这块地方本来就该有」，地形否决与否由后面的地形自己决定（有的节还要专门
## 挑一块没被否决的）。
func _find_index(map_id: String) -> int:
	for i in range(Maps.FEATURE_MIN_CHUNK, Maps.FEATURE_MIN_CHUNK + CHUNKS):
		if Maps.feature_at(SEED, map_id, i) != Maps.FEATURE_NONE:
			return i
	return -1


## 同上，但要**地形真的摆上了**的那一块（冰湖和树前面是陡上坡会被否决掉，
## 见 [method HillTerrain.feature_kind_at]）。
func _find_placed(map_id: String) -> int:
	var t := _real_terrain(map_id)
	var found := -1
	for i in range(Maps.FEATURE_MIN_CHUNK, Maps.FEATURE_MIN_CHUNK + CHUNKS):
		if t.feature_kind_at(i) != Maps.FEATURE_NONE:
			found = i
			break
	t.free()
	return found


## 真实噪声地形，但**不进树**：不进树就不建区块、不摆东西，只要一条地表折线。
func _real_terrain(map_id: String) -> HillTerrain:
	var t := HillTerrain.new()
	t.world_seed = SEED
	t.map_id = map_id
	t._configure_noise()
	return t


## 铺一张只有这张图的世界。`flat` 为真时地表压平（跑车用），
## 为假时是真实噪声起伏（量摆位用）。
##
## `stream_at` 是**要看的那块区块的下标**，-1 表示不用管。区块是按「目标节点周围
## [constant HillTerrain.VIEW_RADIUS] 个区块」建出来的，而目标只有
## [method _spawn_car] 会设 —— 只看几何、不摆车的那几节于是**一块区块都不会建**，
## `_chunk_node(i)` 永远是 null。所以给一个空节点当目标就够了：那几节要的是区块
## 被建出来，不是要一辆车。[method HillTerrain.set_target] 自己会同步刷一次。
func _setup(map_id: String, flat: bool, stream_at := -1) -> void:
	if _world != null:
		_world.queue_free()
		_car = null
	_world = Node2D.new()
	add_child(_world)

	_terrain = FlatTerrain.new() if flat else HillTerrain.new()
	_terrain.stones_scene = STONES
	_terrain.tunnel_scene = TUNNEL
	_terrain.trees_scene = TREES
	_world.add_child(_terrain)
	_terrain.world_seed = SEED
	_terrain.map_id = map_id
	# 不摆金币和油桶：这一节只关心地形，少两个会动的节点少两种干扰。
	if stream_at >= 0:
		var probe := Node2D.new()
		probe.position = Vector2(float(stream_at) * CW, 0.0)
		_world.add_child(probe)
		_terrain.set_target(probe)


## 摆一辆车。`vx` 是初速度（0 = 从静止起步）。
func _spawn_car(map_id: String, x: float, vx := 0.0) -> HillCar:
	if _car != null and is_instance_valid(_car):
		_car.queue_free()
	var car := CAR.instantiate()
	car.position = Vector2(x, _terrain.height_at(x) - CAR_LIFT)
	_world.add_child(car)
	# 地图要在进树之后套：apply_map 读的是 @onready 的轮子节点。
	car.apply_map(map_id)
	car.fuel = 1.0e9
	if not is_zero_approx(vx):
		for body: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
			body.linear_velocity = Vector2(vx, 0.0)
	_terrain.set_target(car.chassis)
	# 记下来：有的量法（[method _drive_capped]）要每帧看车还活着没有。
	# 上面那句 `_car.queue_free()` 一直等着这个赋值，早先漏了它 —— 于是
	# 上一次的车从来没被清掉过，而 `_car` 永远是 null。
	_car = car
	return car


func _chunk_node(index: int) -> Node:
	return _terrain.get_node_or_null("Chunk%d" % index)


## 特殊地形在区块内的跨度（世界坐标）：`position.x` 是左沿，`size.x` 是宽度。
## 洞底、环形山都在这条跨度里 —— 它同时就是「垫平的那一段路」。
func _span_of(map_id: String, index: int) -> Rect2:
	var kind: String = Maps.get_map(map_id)["feature"]
	var lay := Maps.feature_layout(kind)
	return Rect2(
		float(index) * CW + float(lay["inset"]),
		0.0,
		float(lay["width"]),
		float(lay["depth"]),
	)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle() -> void:
	await _frames(SETTLE_FRAMES)


## 一边踩油门一边每帧回调。`st` 是个字典 —— GDScript 的 lambda 捕获局部变量是
## **按值复制**的，往里写数字出不来，写字典里的键才能带出来。
func _drive(seconds: float, st: Dictionary, on_frame: Callable = Callable()) -> void:
	Input.action_press("drive_forward")
	var frames := int(round(seconds / DT))
	for i in frames:
		await get_tree().physics_frame
		if on_frame.is_valid():
			on_frame.call(st)
	Input.action_release("drive_forward")


## 踩油门开，但速度到了 `cap` 就松 —— 「正常开过去」而不是「全油门冲」。
##
## 石子的需求是「颠一下」，而玩家正常过一段石子路是会收油的。全油门冲过去是
## 另一回事（后驱抬头，见 [method _section_stones_drive]），所以「会不会死」
## 这条要在正常速度下量。
func _drive_capped(seconds: float, cap: float, st: Dictionary,
		on_frame: Callable = Callable()) -> void:
	var frames := int(round(seconds / DT))
	for i in frames:
		var car := _car
		if car == null or not car.alive:
			break
		if car.chassis.linear_velocity.x < cap:
			Input.action_press("drive_forward")
		else:
			Input.action_release("drive_forward")
		await get_tree().physics_frame
		if on_frame.is_valid():
			on_frame.call(st)
	Input.action_release("drive_forward")


func _consts(script: GDScript) -> Dictionary:
	return script.get_script_constant_map()


# ---------------------------------------------------------------- 石子：摆位

## 石子必须**贴着自己脚下的地表**，不能按本段左沿的高度摆。
##
## 山地的起伏倍率是 1.35，一段 600 像素里地表能差出一百多像素：按左沿摆的话，
## 一半的石头浮在半空、另一半整个埋进土里 —— 而车碾过去的时候只有露头那一部分
## 有碰撞，于是「颠一下」变成了「这一段的石头时有时无」。
func _section_stones_place() -> void:
	print("=== 石子：摆位（真实起伏）===")
	var index := _find_index(Maps.MOUNTAIN)
	_check("找得到一块有石子的区块", index >= 0, "区块 %d" % index)
	if index < 0:
		return

	_setup(Maps.MOUNTAIN, false, index)
	var chunk := _chunk_node(index)
	var stones: Node = chunk.get_node_or_null("Stones") if chunk != null else null
	_check("石子上树了", stones != null, "Chunk%d/Stones" % index)
	if stones == null:
		return

	var span := _span_of(Maps.MOUNTAIN, index)
	var lowest := INF
	var highest := -INF
	var x := span.position.x
	while x <= span.position.x + span.size.x:
		lowest = minf(lowest, _terrain.height_at(x))
		highest = maxf(highest, _terrain.height_at(x))
		x += 10.0
	var relief := highest - lowest
	print("  本段 x %.0f → %.0f，地表 y %.0f → %.0f（起伏 %.0f 像素）" % [
		span.position.x, span.position.x + span.size.x, lowest, highest, relief])
	# 这条是**给上面那条断言兜底**的：地表要真是平的，「按左沿摆」和「按地表摆」
	# 结果一样，上面那条就永远过、永远测不出东西。
	_check("这一段地表确实不平（不然这条测不出东西）", relief > 20.0,
			"起伏 %.0f 像素" % relief)

	var consts := _consts(STONES_SCRIPT)
	var exposed: float = consts["EXPOSED"]
	var count := 0
	var buried := 0
	var worst := 0.0
	var worst_at := 0.0
	var tallest := 0.0
	var off_layer := 0
	var off_group := 0
	for child in stones.get_children():
		if not (child is StaticBody2D):
			continue
		var body: StaticBody2D = child
		count += 1
		var shape: CircleShape2D = (body.get_node("Shape") as CollisionShape2D).shape
		tallest = maxf(tallest, shape.radius * exposed)
		# 圆心应该在地表以下 (1 − EXPOSED) 倍半径处，露出来的正好是 EXPOSED 倍半径。
		var ground := _terrain.height_at(body.position.x)
		# **加号**：y 轴朝下，「埋在地表以下」是 y 更大。
		var want := ground + shape.radius * (1.0 - exposed)
		if absf(body.position.y - want) > worst:
			worst = absf(body.position.y - want)
			worst_at = body.position.x
		if body.position.y > ground:
			buried += 1
		if body.collision_layer != 2:
			off_layer += 1
		if not body.is_in_group("ground"):
			off_group += 1

	_check("撒了不止一块", count >= 3, "%d 块" % count)
	_check("每块都贴着自己脚下那一处地表（不是本段左沿的高度）", worst < 0.5,
			"最大偏差 %.2f 像素（最差一块在 x=%.0f）" % [worst, worst_at])
	_check("每块的中心都在地表以下（一半以上埋在土里）", buried == count,
			"%d / %d 块" % [buried, count])
	_check("石头都在层 2（车撞得到）", off_layer == 0, "层号不对的有 %d 块" % off_layer)
	# 进 "ground" 组：车轮踩在石头上算着地，不然碾过一排石头会被算成腾空。
	_check("石头都在 \"ground\" 组里", off_group == 0, "不在组里的有 %d 块" % off_group)

	var wheel_r := _wheel_radius()
	_check("露头比车轮半径矮得多（是颠一下，不是撞墙）", tallest < wheel_r * 0.6,
			"最高露头 %.1f 像素，车轮半径 %.1f" % [tallest, wheel_r])

	# 确定性：种子取的是世界坐标左沿，所以区块被回收重建之后石头必须回到原地。
	# 用全局随机（`randi()`）的话，区块随镜头滚一遍石头就换位置了。
	var before := _stone_span(stones)
	_setup(Maps.MOUNTAIN, false, index)
	var again: Node = _chunk_node(index).get_node_or_null("Stones")
	_check("重建之后石头在同一批位置（种子取得对）",
			again != null and _stone_span(again) == before,
			"%d 块 vs %d 块" % [before.size(), 0 if again == null else _stone_span(again).size()])


## 一批石头的 x 坐标（按顺序）。用来比对「重建前后是不是同一批」。
func _stone_span(stones: Node) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for child in stones.get_children():
		if child is StaticBody2D:
			xs.append((child as Node2D).position.x)
	return xs


# ---------------------------------------------------------------- 石子：颠一下

## 车碾过石子会颠，压平地（没有石头）不会。
##
## A/B 对比，和 tests/hazards.gd 里量风力的手法一样：只量「有石子比没石子颠」
## 说明不了石头有碰撞（地形本身的起伏一样会颠），但**压平的地表上**就只有石子
## 会造成竖直方向的运动，于是「把石头删掉再跑一趟」就是干净的对照。
##
## 第三趟量的是**正常速度**（收着油门开）：石子是按「颠一下」设计的，会不会把人
## 颠死得在玩家真会用的速度下量。全油门冲那一趟的结果**只如实打出来**，见这一节末尾。
func _section_stones_drive() -> void:
	print("=== 石子：碾过去会颠 ===")
	var index := _find_index(Maps.MOUNTAIN)
	if index < 0:
		return
	var span := _span_of(Maps.MOUNTAIN, index)
	var end := span.position.x + span.size.x
	var runs := {}
	var note := ["有石子·全油门", "没石子·全油门", "有石子·正常速度"]

	for round_i in 3:
		_setup(Maps.MOUNTAIN, true)
		# 平地：地表恒定，所以除了石子之外没有别的东西能让车上下动。
		var car := _spawn_car(Maps.MOUNTAIN, span.position.x - RUN_UP)
		await _settle()
		if round_i == 1:
			# 对照趟：把石头拆掉，其余一模一样。
			var stones: Node = _chunk_node(index).get_node_or_null("Stones")
			if stones != null:
				stones.queue_free()
			await _frames(2)
		var st := {"peak": 0.0, "max_x": -1.0e9, "reason": "", "tilt": 0.0, "tilt_at": 0.0}
		car.crashed.connect(func(r: String) -> void: st["reason"] = r)
		var probe := func(s: Dictionary) -> void:
			s["peak"] = maxf(s["peak"], absf(car.chassis.linear_velocity.y))
			s["max_x"] = maxf(s["max_x"], car.chassis.global_position.x)
			# 车壳转到多少度。死因只有「crash」一种，但「翻了」和「头蹭到石头」
			# 是两回事，这个数一眼分得出来（翻过去至少 90°）。
			var tilt := absf(rad_to_deg(car.chassis.rotation))
			if tilt > float(s["tilt"]):
				s["tilt"] = tilt
				s["tilt_at"] = car.chassis.global_position.x
		# 7 秒不是随手加的：4 秒只开到 2982，而这一段到 3100 才结束 —— 差一点就
		# 量不到「开过整段」。石子会把车拖慢，所以留的余量比按极速算的多。
		# 收着油门那一趟要 12 秒：300 的速度过这 1500 像素，光路程就要 5 秒。
		if round_i == 2:
			await _drive_capped(12.0, SLOW_CAP, st, probe)
		else:
			await _drive(7.0, st, probe)
		runs[round_i] = st
		print("  %s：颠得最狠 %.0f px/s，最远 x=%.0f，最大侧倾 %.0f°（在 x=%.0f），死因「%s」" % [
			note[round_i], st["peak"], st["max_x"], st["tilt"], st["tilt_at"], st["reason"]])

	var with_stones: float = runs[0]["peak"]
	var without: float = runs[1]["peak"]
	var slow: Dictionary = runs[2]
	_check("有石子的时候确实颠起来了（比没有时明显）", with_stones > without + 5.0,
			"%.0f vs %.0f px/s" % [with_stones, without])
	_check("正常速度碾过整段石子路不会死", String(slow["reason"]) == "",
			"死因「%s」" % slow["reason"])
	_check("正常速度确实开过了整段石子路", float(slow["max_x"]) > end,
			"最远 %.0f，段末 %.0f" % [slow["max_x"], end])

	# 全油门那一趟**如实打出来**：那是**后驱抬头**，不是「石头太高」。
	# 每撞一颗石子车头被顶起来一次（实测 vy 281 px/s），而油门一直踩着 ——
	# 后轮扭矩把仰角一路往上加（0° → −27° → −86° → −161° → 翻过去），
	# 于是翻在石子路的末端。收着油门就不翻（上面那条「正常速度不会死」量的就是这个）。
	# 这是登山赛车的正经玩法，所以石子本身不动：需求要的是「颠一下」，
	# 而「颠一下」正是上面第一条断言量到的东西。
	print("  全油门那趟翻车是**后驱抬头**（仰角累积到 %.0f°），不是石头太高 —— 收油门就不翻" % runs[0]["tilt"])


# ---------------------------------------------------------------- 隧道：全图都要有上壁

## 「全图都需要有上壁」+「上壁的分布是连续的」：先当**纯函数**验。
##
## 隧道和别的地形不一样：它不掷骰子、也不吃「相邻不连放」—— 见
## [method Maps.feature_at] 里那个例外。所以这里扫的是**一整段区块号**，
## 不是别处那种「找出第一块会摆的」。
##
## 出生点那一段反过来要求**没有**上壁（用户后来补的：「开局出生点处不应该有隧道」）。
func _section_tunnel_plan() -> void:
	print("=== 隧道：每一块区块都要有上壁（出生点除外）===")
	var head := Maps.TUNNEL_START_CHUNK + 6
	var missing := 0
	var first_missing := 0
	for i in range(head, head + 200):
		if Maps.feature_at(SEED, Maps.TUNNEL, i) != Maps.FEATURE_TUNNEL:
			missing += 1
			if missing == 1:
				first_missing = i
	_check("连着 200 块都是隧道（中间不断档）", missing == 0,
			"漏了 %d 块（第一块在 %d）" % [missing, first_missing])

	# 一块都不能提前：出生点那几块必须露着天。车摆在 x = 200（0 号区块），
	# 开局就压在石头底下的话，玩家连「先开一段」都没有。
	var early := 0
	for i in range(0, Maps.TUNNEL_START_CHUNK):
		if Maps.feature_at(SEED, Maps.TUNNEL, i) != Maps.FEATURE_NONE:
			early += 1
	_check("出生点那一段没有上壁（开局露着天）",
			early == 0 and Maps.TUNNEL_START_CHUNK > 0,
			"区块 0～%d 里有 %d 块盖上了" % [Maps.TUNNEL_START_CHUNK - 1, early])
	_check("出生点（x = 200）落在没盖的那一段里",
			Maps.feature_at(SEED, Maps.TUNNEL, 0) == Maps.FEATURE_NONE,
			"0 号区块 = 「%s」" % Maps.feature_at(SEED, Maps.TUNNEL, 0))

	var lay := Maps.feature_layout(Maps.FEATURE_TUNNEL)
	_approx("拱盖满一整块区块宽（= 地形的区块宽）", float(lay["width"]), CW, 0.01)
	_approx("从区块左沿起，不留内缩", float(lay["inset"]), 0.0, 0.01)
	# 隧道**不能**垫平：地形是一块一块垫的（每块垫到自己左沿的高度），
	# 全图垫平会在每个区块边界留一道台阶，车在洞底一颠就撞顶 —— 随机死亡。
	_check("隧道不挖地形、也不垫平（不然每 800 像素一道台阶）",
			not Maps.digs(Maps.FEATURE_TUNNEL), "digs = %s" % Maps.digs(Maps.FEATURE_TUNNEL))


# ---------------------------------------------------------------- 隧道：形状与连续

## 洞顶下沿的采样点（世界坐标）。从碰撞体那一圈多边形里切出**下沿那一半**：
## 顶点顺序是「下沿从左到右、拱背从右到左」，所以前半就是下沿。
func _tunnel_bottom(tunnel: Node) -> PackedVector2Array:
	var poly: PackedVector2Array = (tunnel.get_node("Arch/Shape") as CollisionPolygon2D).polygon
	var out := PackedVector2Array()
	for i in poly.size() / 2:
		out.append(poly[i])
	return out


## 下沿在 `x` 处的 y（采样点之间线性插值）。洞顶是起伏的，所以「头顶离洞顶多远」
## 必须按 x 查 —— 拿一个常数去减，等于把这根曲线当成水平的。
func _bottom_y(bottom: PackedVector2Array, x: float) -> float:
	for i in range(bottom.size() - 1):
		if x <= bottom[i + 1].x:
			var a := bottom[i]
			var b := bottom[i + 1]
			var t := 0.0 if is_equal_approx(a.x, b.x) else (x - a.x) / (b.x - a.x)
			return lerpf(a.y, b.y, t)
	return bottom[bottom.size() - 1].y


## 区块节点下挂着的东西，不判断区块在不在。
func _chunk_child(index: int, name: String) -> Node:
	var chunk := _chunk_node(index)
	return chunk.get_node_or_null(name) if chunk != null else null


## 这一丛树摆在哪儿（**纯函数**，不用等区块建出来）。
##
## 跑车那一节要拿它开个头：区块是**围着车** stream 的，而「第一棵树在哪」得在生车
## 之前就知道 —— 等区块建出来再问的话，车还没生出来呢（区块压根不在场上）。
## 顺手也就多了一条交叉验证：探针算出来的位置必须和区块上真摆的那一丛一模一样。
func _grove_xs_of(map_id: String, index: int) -> PackedFloat32Array:
	var kind: String = Maps.get_map(map_id)["feature"]
	var lay := Maps.feature_layout(kind)
	var from := float(index) * CW + float(lay["inset"])
	var node := _probe_trees(from, float(lay["width"]))
	var xs: PackedFloat32Array = node.call("_grove_xs")
	node.get_parent().free()
	return xs


## 一个**独立于区块**的树丛节点（做法同 [method _probe_tunnel]）：一丛几棵、站在
## 哪儿都是世界坐标的纯函数，所以不用赌哪一块区块还在场上。
func _probe_trees(from: float, width: float) -> Node:
	var holder := Node2D.new()
	_terrain.add_child(holder)
	var node: Node = TREES.instantiate()
	holder.add_child(node)
	node.setup(Rect2(from, 0.0, width, 0.0), _terrain.height_at(from))
	return node


## 一丛里的树，按 x 从小到大。
##
## `Trees` 底下挂着每棵树的刚体和每棵树的感知区（Area2D）—— 这里只要刚体，
## 所以拿 `as RigidBody2D` 过一遍，感知区自然被滤掉。
func _grove_trees(trees: Node) -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for child in trees.get_children():
		var body := child as RigidBody2D
		if body != null:
			out.append(body)
	out.sort_custom(func(a: RigidBody2D, b: RigidBody2D) -> bool:
		return a.position.x < b.position.x)
	return out


## 一棵树配套的感知区：**按横坐标找**。树的 `Tree%d` 和 `Sense%d` 是同一轮种下去的，
## 但测试不该赌这个顺序 —— 赌错了就成了「量的是邻居的感知区」，还照样绿。
func _sense_for(trees: Node, x: float) -> Area2D:
	for child in trees.get_children():
		var zone := child as Area2D
		if zone != null and absf(zone.position.x - x) < 0.5:
			return zone
	return null


## 一个**独立于区块**的隧道节点：挂在测试地形下面，跨度自己给。
##
## 区块是跟着镜头回收重建的，问「世界坐标 x 处的洞顶在哪」不该去赌哪一块还在场上。
## 洞顶的每个数都是**世界坐标的纯函数**（见 scripts/tunnel.gd 文件头），区块只决定
## 「谁来画这一段」，所以探针算出来的和真区块上那一段逐像素一致 —— 反过来，
## 这也正是「跨区块连续」那条能成立的原因。
func _probe_tunnel(from: float, width: float) -> Node:
	var holder := Node2D.new()          # 假装是区块节点：ground_at 往上两级找地形
	_terrain.add_child(holder)
	var tun: Node = TUNNEL.instantiate()
	holder.add_child(tun)
	# **必须在 add_child 之后 setup** —— setup 里就要建东西了。
	tun.setup(Rect2(from, 0.0, width, 0.0), _terrain.height_at(from))
	return tun


## 拱的形状：盖满整块、跟着**当地**地表起伏、和最矮处也在车顶之上；跨区块连续；
## 下沿挂钟乳石；那块石头自己就是死亡区。
##
## 「碰洞顶会死」不在这一节：判死路径见 [method _section_tunnel_die]，
## 这里只管形状 —— 形状错了，判死再对也是白搭（正常开过去就撞顶了）。
func _section_tunnel_shape() -> void:
	print("=== 隧道：盖满整块、跟着地表、跨区块连续 ===")
	var consts := _consts(TUNNEL_SCRIPT)
	var gap_min: float = consts["HEAD_GAP_MIN"]
	var gap_max: float = consts["HEAD_GAP_MAX"]
	var spike_min: float = consts["SPIKE_LEN_MIN"]
	var spike_max: float = consts["SPIKE_LEN_MAX"]
	var safe: float = consts["SPIKE_SAFE"]
	var car_h := _car_height()
	_approx("隧道脚本里的车高就是现量的车高（两边是同一个数）",
			float(consts["CAR_HEIGHT"]), car_h, 0.01)
	_check("洞顶的下限在车顶之上（平地上正常开过去撞不到）", gap_min > 0.0,
			"下限 = 车高 + %.0f" % gap_min)

	# ① 出生点那一块**不该**有上壁。
	_setup(Maps.TUNNEL, false, 0)
	var spawn := _chunk_node(0)
	_check("出生点那一块没有上壁（开局露着天）",
			spawn != null and spawn.get_node_or_null("Tunnel") == null, "Chunk0/Tunnel")

	# ② 挑一块**地表确实有起伏**的区块：「洞顶跟着当地地表走」这条在平地上测不出来
	# —— 按左沿的高度算和按当地地表算，在平地上是同一个数，而那正是最容易犯的错。
	#
	# **只在近处挑（前 [constant NEAR_CHUNKS] 块），不是把整张图扫一遍。**
	# 扫一遍的话「起伏最大的一块」会一路飘到图的最远端：地形起伏过了 2 km 是按复利
	# 涨的、不封顶（[constant HillTerrain.GROWTH_RATE]），6.4 km 那里一块 800 宽的
	# 地块能有 700 多像素的落差 —— 那儿的洞顶已经被逼成一根贴着地面的斜线，钟乳石
	# 一根都挂不住。**那是「3.5 km 之后地形是墙」这个已知结论的又一个表现，不是
	# 隧道画错了**，而这一节要测的是洞顶的形状，把它钉在脚下这段才有意义。
	# 顺带：不定住的话，幅度那边每调一次，这一节就在测另一块地，红了也说不清是谁的锅。
	var t := _real_terrain(Maps.TUNNEL)
	var index := Maps.TUNNEL_START_CHUNK
	var relief := 0.0
	for i in range(Maps.TUNNEL_START_CHUNK, Maps.TUNNEL_START_CHUNK + NEAR_CHUNKS):
		var lo := INF
		var hi := -INF
		var x := float(i) * CW
		while x <= float(i + 1) * CW:
			lo = minf(lo, t.height_at(x))
			hi = maxf(hi, t.height_at(x))
			x += 5.0
		if hi - lo > relief:
			relief = hi - lo
			index = i
	t.free()
	_check("这一段地表确实不平（不然「跟着地表」这条测不出东西）", relief > 30.0,
			"起伏 %.0f 像素（区块 %d）" % [relief, index])

	_setup(Maps.TUNNEL, false, index)
	var ta := _chunk_child(index, "Tunnel")
	var tb := _chunk_child(index + 1, "Tunnel")
	_check("这一块有上壁", ta != null, "Chunk%d/Tunnel" % index)
	_check("**下一块也有**（上壁一块挨着一块，不断档）", tb != null,
			"Chunk%d/Tunnel" % (index + 1))
	if ta == null or tb == null:
		return

	var span := _span_of(Maps.TUNNEL, index)
	var poly_a: PackedVector2Array = (ta.get_node("Arch/Shape") as CollisionPolygon2D).polygon
	var poly_b: PackedVector2Array = (tb.get_node("Arch/Shape") as CollisionPolygon2D).polygon
	var half := poly_a.size() / 2
	_check("顶点数是偶数（下沿一半 + 拱背一半）", poly_a.size() % 2 == 0,
			"%d 个点" % poly_a.size())

	# ③ 拱盖满整块：两端一像素都不缩。**盖满 + 相邻两块端点重合 = 一条不断的石头带**；
	# 缩一点就在每个区块边界留一截「路在头上却露着天」。
	_approx("下沿从区块左沿起", poly_a[0].x, span.position.x, 0.05)
	_approx("下沿到区块右沿止", poly_a[half - 1].x, span.position.x + span.size.x, 0.05)

	# 下沿必须严格从左到右、拱背严格从右到左，否则多边形自交（物理体会炸）。
	var back := 0
	for i in range(1, half):
		if poly_a[i].x <= poly_a[i - 1].x:
			back += 1
	for i in range(half + 1, poly_a.size()):
		if poly_a[i].x >= poly_a[i - 1].x:
			back += 1
	_check("下沿一路向右、拱背一路向左（多边形不自交）", back == 0, "%d 处反向" % back)
	var below := 0
	for i in half:
		if poly_a[half + i].y >= poly_a[half - 1 - i].y:
			below += 1
	_check("拱背整条都在下沿上方", below == 0, "%d 个点掉到下沿下面" % below)

	# ④ **跨区块连续**：两块石头是各画各的，所以在它们共用的那条边界上必须**重合**。
	# 拱的两端各有一条竖直的「接口边」：A 的右口 = 下沿右端点 → 拱背右端点，
	# B 的左口同理。两条边重合 = 石头带连上了；差一点就是一道缝。
	#
	# 早先洞顶是按 `rim_y`（= **本块左沿**的高度）摆的，两块差着一整段起伏，
	# 这里会差出几十像素 —— 「上壁的分布是连续的」测的就是这一条。
	var edge_x := float(index + 1) * CW
	var bottom_a := _tunnel_bottom(ta)
	var bottom_b := _tunnel_bottom(tb)
	_approx("边界处两边算出的下沿高度一样（洞顶接得上）",
			_bottom_y(bottom_b, edge_x), _bottom_y(bottom_a, edge_x), 0.02)
	_approx("边界处两边算出的拱背高度一样（拱背也接得上）",
			poly_b[poly_b.size() - 1].y, poly_a[half].y, 0.02)
	_approx("边界处两边的接口边在同一条竖线上", poly_b[0].x, poly_a[half - 1].x, 0.02)

	# ⑤ 洞顶跟着**当地地表**走：车顶到石头的余量必须在设计区间里，而且每个 x 都用
	# **它自己脚下的地面**量 —— 用本块左沿的高度量的话，山丘那半边会凭空多出
	# 一整个起伏（早先那个 bug 的形状）。
	var low := INF
	var high := -INF
	var x := span.position.x
	while x <= span.position.x + span.size.x:
		var room := _terrain.height_at(x) - _bottom_y(bottom_a, x) - car_h
		low = minf(low, room)
		high = maxf(high, room)
		x += 2.0
	print("  车顶到洞顶（连石尖）%.0f ～ %.0f 像素（设计 %.0f ～ %.0f + 石尖）" % [
		low, high, gap_min, gap_max])
	_check("最矮处也在车顶之上（平地上正常开过去撞不到）", low >= gap_min - 1.0,
			"最矮 %.0f，下限 %.0f" % [low, gap_min])
	# 石尖是**往下**挂的，只会把余量压小 —— 所以上限就是洞顶本身的上限。
	_check("最高的地方也不离谱（车高 + HEAD_GAP_MAX）", high <= gap_max + 1.0,
			"最高 %.0f，上限 %.0f" % [high, gap_max])
	_check("洞顶离地面的距离是波动的（不是一条直线）", high - low > 25.0,
			"%.0f ～ %.0f，差 %.0f 像素" % [low, high, high - low])

	# ⑥ 钟乳石：一路往下凸出来的尖。判据是「比左右 20 像素处的下沿还低一截」——
	# 洞顶自身的波动在 20 像素里最多变几个像素，缝分得很干净。
	var spikes := 0
	var longest := 0.0
	var longest_at := 0.0
	var worst_room := 1.0e9
	for i in range(4, half - 4):
		var y := bottom_a[i].y
		if y - maxf(bottom_a[i - 4].y, bottom_a[i + 4].y) < 10.0:
			continue
		spikes += 1
		# 比**平滑的洞顶**（不带石尖的那条曲线）低多少 —— 就是这根挂了多长。
		var hang := y - float(ta.call("_ceiling_at", bottom_a[i].x))
		# 石尖到车顶还剩多少。这是钟乳石那条安全线的实测。
		worst_room = minf(worst_room,
				_terrain.height_at(bottom_a[i].x) - y - car_h)
		if hang > longest:
			longest = hang
			longest_at = bottom_a[i].x
	print("  下沿凸出 %d 处尖，最长一根在 x=%.0f、垂 %.0f 像素；石尖离车顶最少 %.0f 像素" % [
		spikes, longest_at, longest, worst_room])
	_check("洞顶下挂着钟乳石", spikes >= 2, "%d 处尖" % spikes)
	_check("石尖够长（不是一排小锯齿）", longest >= spike_min,
			"最长 %.0f，下限 %.0f" % [longest, spike_min])
	_check("石尖也没长得离谱", longest <= spike_max + 1.0,
			"最长 %.0f，上限 %.0f" % [longest, spike_max])
	# 安全线：每一处石尖离车顶都要留着 SPIKE_SAFE。洞顶高的地方石尖才能长、
	# 矮的地方不长 —— 这条就是「长度按当地余量压一道」的实测。
	_check("每处石尖离车顶都留着安全距离", worst_room >= safe - 1.0,
			"最近的一处只剩 %.0f 像素（安全线 %.0f）" % [worst_room, safe])

	# ⑦ 看见的 = 碰得到的：碰撞体和画出来的必须是同一份点。
	# 分开各写一份迟早会漂开，表现是「看着过不去、其实过得去」。
	var vis := ta.get_node_or_null("ArchVisual") as Polygon2D
	_check("画出来的洞顶和碰撞体是同一个形状", vis != null and vis.polygon == poly_a,
			"%d 点 vs %d 点" % [0 if vis == null else vis.polygon.size(), poly_a.size()])

	# ⑧ 洞顶那块石头**自己就是死亡区**，进的是 CEILING_GROUP 而不是 "ground"。
	# 进 "ground" 的话 [method HillCar._on_head_body_entered] 会把这一下判成
	# 「翻车了！」，文案和死因都对不上。
	var arch := ta.get_node_or_null("Arch")
	_check("洞顶在 CEILING_GROUP 组里（头碰到判「撞到洞顶」）",
			arch != null and arch.is_in_group(HillCar.CEILING_GROUP), "Arch 的组")
	_check("洞顶**不在** \"ground\" 组里（碰它不是翻车）",
			arch != null and not arch.is_in_group("ground"), "Arch 的组")
	_check("洞顶在层 2 上（车撞得到）", arch != null and arch.collision_layer == 2,
			"层 %d" % (0 if arch == null else arch.collision_layer))

	# ⑨ 上壁够厚：**石头要盖得住屏幕上半部分**（用户原话）。
	#
	# 厚度不是随手定的，是从镜头位置推出来的（推导写在 tunnel.gd 的 ROOF_MIN 上）：
	# 镜头在车身上方 HillGame.CAMERA_LIFT，车手头顶在车身上方 `_head_above_chassis()`，
	# 而**头碰到洞顶就是死**，所以车身最高只到「洞顶下沿 + 头顶」，
	# 镜头也就最高只到「洞顶下沿 + 头顶 − CAMERA_LIFT」。屏幕正中就是镜头那条线，
	# 于是石头要从洞顶下沿往上盖过「半个屏幕高 + 这个差」。
	#
	# 画布高取 `stretch/aspect = expand` 能出到的那三档（见 [constant CANVAS_HEIGHTS]），
	# 缩放取**最远**的 HillGame.ZOOM_FAR —— 车开最快的时候看得最广，也就最需要厚。
	var roof_min: float = consts["ROOF_MIN"]
	var roof_max: float = consts["ROOF_CROWN"]
	var head_up := _head_above_chassis()
	var budget := HillGame.CAMERA_LIFT - head_up
	_check("镜头比车手头顶还高（不然「盖住屏幕上半」根本不是厚度能解决的事）",
			budget > 0.0, "镜头高 %.0f，头顶高 %.0f，差 %.0f" % [
				HillGame.CAMERA_LIFT, head_up, budget])
	for canvas_h in CANVAS_HEIGHTS:
		var need := budget + float(canvas_h) * 0.5 / HillGame.ZOOM_FAR
		_check("画布高 %d 时最薄的拱背也盖得住屏幕上半（要求 %.0f）" % [canvas_h, need],
				roof_min >= need, "ROOF_MIN = %.0f" % roof_min)
	# 拿**真的多边形**再量一遍：常量对不等于画出来的拱对（`_thickness_at` 是条噪声
	# 曲线，量出来的是这一块区块里的实际厚薄）。下沿第 j 个点配的是拱背第
	# `2 × half − 1 − j` 个点 —— 拱背是倒着接在下沿后面的（见 [method _arch_points]）。
	var thinnest := 1.0e9
	var thinnest_at := 0.0
	for j in half:
		var thick: float = poly_a[j].y - poly_a[2 * half - 1 - j].y
		if thick < thinnest:
			thinnest = thick
			thinnest_at = poly_a[j].x
	var need_max := budget + float(CANVAS_HEIGHTS[CANVAS_HEIGHTS.size() - 1]) * 0.5 / HillGame.ZOOM_FAR
	print("  拱背实测最薄 %.0f 像素（x=%.0f），最厚 %.0f；最高的画布要求 %.0f" % [
		thinnest, thinnest_at, roof_max, need_max])
	_check("画出来的石头实测最薄处也够厚", thinnest >= need_max,
			"最薄 %.0f，要求 %.0f" % [thinnest, need_max])
	_check("拱背厚薄还是有变化的（不是一块等厚的板）", roof_max > roof_min + 20.0,
			"%.0f ～ %.0f" % [roof_min, roof_max])


# ---------------------------------------------------------------- 隧道：开进去

## 全油门从**露天**那一段开进洞里、一路开过好几个区块：不许死，头顶也不许蹭到石头。
##
## 顺带把「头顶离石头最近多少」量出来打出来 —— 这个数是**跑出来的**，不是几何上
## 算的：车过洞口时的一点点俯仰都会算进去。它是「洞顶最矮 16 像素」那条设计的实测。
##
## 车从露天那一段起步，和玩家开局一样：出生点**没有**上壁，所以车落地时不会嵌进石头里。
func _section_tunnel_drive() -> void:
	print("=== 隧道：全油门开进洞里、跨过好几块区块 ===")
	var mouth := float(Maps.TUNNEL_START_CHUNK) * CW
	_setup(Maps.TUNNEL, true)
	var tun := _probe_tunnel(mouth, 8.0 * CW)
	var car := _spawn_car(Maps.TUNNEL, mouth - RUN_UP)
	await _settle()
	var head_r: float = (car.get_node("Chassis/Head/HeadShape") as CollisionShape2D).shape.radius
	var st := {"gap": 1.0e9, "gap_at": 0.0, "max_x": -1.0e9, "reason": ""}
	car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	await _drive(10.0, st, func(s: Dictionary) -> void:
		var head_x := car.head.global_position.x
		s["max_x"] = maxf(s["max_x"], car.chassis.global_position.x)
		# 只量**真有上壁**的那些 x：露天那一段探针照样算得出洞顶的 y，
		# 但那块地方本来就没有石头。
		if head_x < float(mouth):
			return
		var clear := (car.head.global_position.y - head_r) - float(tun.call("_bottom_at", head_x))
		if clear < float(s["gap"]):
			s["gap"] = clear
			s["gap_at"] = head_x)

	print("  头顶离石头最近 %.1f 像素（在 x=%.0f），最远到 x=%.0f，洞口 x=%.0f，死因「%s」" % [
		st["gap"], st["gap_at"], st["max_x"], mouth, st["reason"]])
	_check("全油门开进洞里没撞顶", String(st["reason"]) == "", "死因「%s」" % st["reason"])
	_check("车开过了好几块区块（不是只跨了一块）",
			float(st["max_x"]) > mouth + 2.0 * CW,
			"最远 %.0f，要过 %.0f" % [st["max_x"], mouth + 2.0 * CW])
	_check("洞里一路都没碰到石头（连钟乳石）", float(st["gap"]) > 0.0,
			"最近 %.1f 像素" % st["gap"])
	# 「正常行驶不会撞到」不能只量「> 0」：贴着 1 像素擦过去也叫「没碰到」。
	_check("余量够（正常开过去不是贴着石头擦）", float(st["gap"]) >= TUNNEL_MARGIN,
			"最近 %.1f 像素（要 ≥ %.0f）" % [st["gap"], TUNNEL_MARGIN])


# ---------------------------------------------------------------- 隧道：撞顶

## 在洞里被抛起来 → 车手撞到石头 → 死，死因是「撞到洞顶」。
##
## 判死不能只写「车死了」：死因要是 REASON_CRASH（车手栽在地上那种），
## 说明洞顶那块石头的分组摆错了 —— 而「碰到上壁会死」和「翻车了」在 HUD 上是两句话。
##
## 车的起步位置和玩家一样在**露天**那一段（见 [method _section_tunnel_drive]），
## 进洞之后再抛。
func _section_tunnel_die() -> void:
	print("=== 隧道：在洞里撞顶 ===")
	var mouth := float(Maps.TUNNEL_START_CHUNK) * CW
	var mid := mouth + 2.0 * CW
	_setup(Maps.TUNNEL, true)
	var tun := _probe_tunnel(mouth, 8.0 * CW)
	var car := _spawn_car(Maps.TUNNEL, mouth - RUN_UP)
	await _settle()

	var st := {"reason": "", "max_x": -1.0e9, "launched": false}
	car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	# 进洞之后往上抛一下（模拟「飞进洞里」）。700 px/s 差不多是 204 像素的弹跳高度，
	# 而洞顶离地面最矮的那一档是「车高 + 60」= 176 —— 抬过一次洞顶（见
	# scripts/tunnel.gd 的 HEAD_GAP_MIN），抛低了就不一定够得着了。
	Input.action_press("drive_forward")
	for i in int(12.0 / DT):
		await get_tree().physics_frame
		if String(st["reason"]) != "":
			break
		st["max_x"] = maxf(float(st["max_x"]), car.chassis.global_position.x)
		if not bool(st["launched"]) and car.chassis.global_position.x > mid - 60.0:
			st["launched"] = true
			for body: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
				body.linear_velocity = Vector2(body.linear_velocity.x, -700.0)
	Input.action_release("drive_forward")

	print("  抛起来的地方洞顶 y=%.1f（在 x=%.0f 左右），最远到 x=%.0f，死因「%s」" % [
		float(tun.call("_bottom_at", mid)), mid, st["max_x"], st["reason"]])
	_check("车开到了洞里（抛之前得先有洞）", bool(st["launched"]),
			"最远 x=%.0f，要过 %.0f" % [st["max_x"], mid - 60.0])
	_check("在洞里被抛起来会撞顶死", String(st["reason"]) != "", "死因「%s」" % st["reason"])
	_check("死因是「撞到洞顶」而不是翻车",
			String(st["reason"]) == HillCar.REASON_CEILING, "死因「%s」" % st["reason"])


# ---------------------------------------------------------------- 环形山：一排几个

## 一排环形山「连着几个」是**纯函数**说了算的，不掷骰子。
##
## [method Maps.craters_at] 只吃「世界种子 + 区块号」，挖地形的和测试问的是同一个
## 结论。各自掷骰子的话，测试量到的「一排 4 个」和玩家看到的 3 个就是两码事 ——
## 而且区块会随镜头反复重建，坑的个数会在玩家眼前变。
func _section_craters_plan() -> void:
	print("=== 环形山：一排几个 ===")
	_check("个数范围就是用户要的 3～5",
			Maps.CRATERS_MIN == 3 and Maps.CRATERS_MAX == 5,
			"%d～%d" % [Maps.CRATERS_MIN, Maps.CRATERS_MAX])

	var seen := {}
	var out_of_range := 0
	for i in range(300):
		var n := Maps.craters_at(SEED, i)
		if n < Maps.CRATERS_MIN or n > Maps.CRATERS_MAX:
			out_of_range += 1
		seen[n] = int(seen.get(n, 0)) + 1
	_check("300 个区块里没有越界的个数", out_of_range == 0, "越界 %d 个" % out_of_range)
	_check("3 / 4 / 5 三种都出现过", seen.size() == 3, "出现过 %s" % seen)
	_check("同一个区块问两次结果一样（不掷骰子）",
			Maps.craters_at(SEED, 7) == Maps.craters_at(SEED, 7),
			"第 7 块两次都是 %d" % Maps.craters_at(SEED, 7))
	# 换个种子就该换个数 —— 不然「一排几个」其实是常数，只是碰巧在这个种子上
	# 凑出了三种，那它就不是随机，是写死的。
	var other := 0
	for i in range(300):
		if Maps.craters_at(SEED + 1, i) != Maps.craters_at(SEED, i):
			other += 1
	_check("换个种子个数会变（真的是按种子算的）", other > 30,
			"300 块里有 %d 块和另一个种子不同" % other)

	var lay := Maps.feature_layout(Maps.FEATURE_CRATERS)
	# 最宽的一排（5 个）得装得进本段：5 × 70 + 4 × 40 = 510 ≤ 520。
	var widest := float(Maps.CRATERS_MAX) * float(lay["notch"]) \
			+ float(Maps.CRATERS_MAX - 1) * float(lay["notch_gap"])
	_check("最宽的一排装得进本段", widest <= float(lay["width"]),
			"%.0f ≤ %.0f" % [widest, float(lay["width"])])
	print("  3/4/5 各出现 %d / %d / %d 次" % [seen[3], seen[4], seen[5]])


# ---------------------------------------------------------------- 环形山：形状

## 环形山是「凹」字形的坑：**陡壁 + 平底**，一溜溜连着摆。
##
## 「轮子会陷进去」是几何事实，不用跑车去证：坑壁的斜率约 `depth·π/(2·edge)` ≈ 6.4，
## 而车轮能爬的最陡坡差不多就是 45°（斜率 1）—— 76° 的壁它上不来。
## 「借低重力跃过去」不在这里测：低重力由 [method _section_moon_gravity] 盯着，
## 跳跃距离是两者的合成，手感的东西测试断言不了。
func _section_craters_shape() -> void:
	print("=== 环形山：形状（真实起伏）===")
	var lay := Maps.feature_layout(Maps.FEATURE_CRATERS)
	var notch := float(lay["notch"])
	var gap := float(lay["notch_gap"])
	var depth := float(lay["depth"])
	var edge := float(lay["edge"])
	var t := _real_terrain(Maps.MOON)

	var built := 0
	var counts := {}
	var bad_plan := PackedStringArray()
	var bad_shape := PackedStringArray()
	var steepest := 0.0
	var narrowest_flat := 1.0e9
	var deepest := 0.0
	var spacing_worst := 0.0
	for index in range(Maps.FEATURE_MIN_CHUNK, Maps.FEATURE_MIN_CHUNK + CHUNKS):
		if t.feature_kind_at(index) != Maps.FEATURE_CRATERS:
			continue
		built += 1
		var want := Maps.craters_at(SEED, index)
		if want < Maps.CRATERS_MIN or want > Maps.CRATERS_MAX:
			bad_plan.append("第 %d 块 %d 个" % [index, want])
		counts[want] = int(counts.get(want, 0)) + 1

		# 扫这一段的剖面。环形山这一段的地形被垫平了（[method HillTerrain._level]），
		# 所以 `x = a` 处的地表就是**垫平之后**的坑沿高度，坑深 = 地表相对它掉下去多少。
		#
		# **方向别写反**：`height_at = _base_height + _carve`，而挖坑是**加大** y
		# （屏幕坐标 y 朝下 = 往下挖）。所以深度是 `height_at − rim` 而不是反过来 ——
		# 反过来写的话「坑」全是负数，扫出来 0 个坑、最深 0 像素，而最陡的斜率照样
		# 量得出来（6.4，就是 `_basin` 的坑壁），于是只有「个数」和「深度」两条红，
		# 看着像地形没挖，其实是量的人把尺子拿反了。
		var a := float(index) * CW + float(lay["inset"])
		var b := a + float(lay["width"])
		var rim := t.height_at(a)
		var runs: Array = []
		var cur := PackedFloat32Array()
		var steep := 0.0
		var x := a
		var prev := t.height_at(a) - rim
		while x <= b:
			var here := t.height_at(x) - rim
			if here > depth * 0.5:
				cur.append(x)
			elif not cur.is_empty():
				runs.append(cur)
				cur = PackedFloat32Array()
			steep = maxf(steep, absf(here - prev))
			prev = here
			x += 1.0
		if not cur.is_empty():
			runs.append(cur)
		steepest = maxf(steepest, steep)

		if runs.size() != want:
			bad_shape.append("第 %d 块扫出 %d 个坑（设计 %d 个）" % [index, runs.size(), want])
			continue

		# 每个坑：宽、深、坑底有多平；顺带记坑与坑的中距。
		var centers := PackedFloat32Array()
		for r in runs:
			var run: PackedFloat32Array = r
			var left := run[0]
			var right := run[run.size() - 1]
			centers.append((left + right) * 0.5)
			# 深过半的那一段：余弦壁各占掉半个 edge，所以宽 = notch − edge。
			if absf((right - left) - (notch - edge)) > 4.0:
				bad_shape.append("第 %d 块有个坑宽 %.0f（期望 %.0f）" % [
					index, right - left, notch - edge])
			var here_depth := 0.0
			var flat := 0
			for sx in range(int(left), int(right) + 1):
				var d := t.height_at(float(sx)) - rim
				here_depth = maxf(here_depth, d)
				if d >= depth * 0.98:
					flat += 1
			deepest = maxf(deepest, here_depth)
			narrowest_flat = minf(narrowest_flat, float(flat))
		for i in range(1, centers.size()):
			spacing_worst = maxf(spacing_worst, absf((centers[i] - centers[i - 1]) - (notch + gap)))

	t.free()

	print("  扫了 %d 片环形山，个数分布 %s" % [built, counts])
	print("  最深 %.0f 像素（设计 %.0f），最窄的一处坑底 %.0f 像素宽，最陡的一处 %.1f 像素/像素（≈%.0f°）" % [
		deepest, depth, narrowest_flat, steepest, rad_to_deg(atan(steepest))])
	print("  坑与坑的中距最大偏差 %.2f 像素（设计间距 %.0f）" % [spacing_worst, notch + gap])
	_check("这张图上找得到环形山", built >= 3, "%d 片" % built)
	_check("每一片的个数都在 3～5 之间", bad_plan.is_empty(),
			"越界的有 %s" % ("无" if bad_plan.is_empty() else "；".join(bad_plan)))
	_check("每一片扫出来的坑数都 = [method Maps.craters_at] 说的个数", bad_shape.is_empty(),
			"对不上的有 %s" % ("无" if bad_shape.is_empty() else "；".join(bad_shape)))
	_check("坑与坑等距连着（一排骨牌式的「凹凹凹」）", spacing_worst < 1.5,
			"最大偏差 %.2f 像素" % spacing_worst)
	_check("挖到了设计深度", absf(deepest - depth) < 1.0,
			"%.1f vs %.1f" % [deepest, depth])
	# 「凹字形」= 陡壁 + 平底。平底不平时就是「V」。
	_check("坑底是平的（不是 V 字）", narrowest_flat >= 20.0,
			"最窄的一处平底只有 %.0f 像素" % narrowest_flat)
	_check("坑壁陡得多（轮子爬不上来，会陷进去）", steepest > 4.0,
			"最陡 %.1f 像素/像素（≈%.0f°）" % [steepest, rad_to_deg(atan(steepest))])


# ---------------------------------------------------------------- 树：一丛几棵

## 一丛 **3～5 棵**、间隔随机；树高**等于车高**（用户的原话）；每棵都踩在自己
## 脚下的真实地表上。
##
## 「棵数和间隔」这一半是**当纯函数扫**的（60 个位置，见 [method _probe_trees]）：
## 只量场上那一丛说明不了「随机」—— 随机是分布上的事，得看一片。
##
## 用真实起伏的地形量站位：森林这一段 700 像素宽，按本段左沿的高度种树的话，
## 靠右的那几棵要么悬在半空、要么半截埋进坡里。
func _section_trees_place() -> void:
	print("=== 树：一丛 3～5 棵、站位（真实起伏）===")
	var index := _find_placed(Maps.FOREST)
	_check("找得到一块真的摆了树的区块（没被助跑规则否决）", index >= 0, "区块 %d" % index)
	if index < 0:
		return

	var consts := _consts(TREES_SCRIPT)
	var lo := int(consts["TREE_COUNT_MIN"])
	var hi := int(consts["TREE_COUNT_MAX"])
	var gap_min: float = consts["GROVE_GAP_MIN"]
	var gap_max: float = consts["GROVE_GAP_MAX"]
	var tree_h: float = consts["TREE_HEIGHT"]
	var trunk_w: float = consts["TRUNK_W"]

	_check("一丛的棵数就是用户要的 3～5", lo == 3 and hi == 5, "%d～%d" % [lo, hi])
	_approx("被撞倒后 1 秒消失（用户要的）", float(consts["DISAPPEAR_DELAY"]), 1.0, 0.001)

	# ---- 纯函数那一半：扫 60 个位置，看棵数和间隔的分布 ----
	var layout := Maps.feature_layout(Maps.FEATURE_TREES)
	var width := float(layout["width"])
	_setup(Maps.FOREST, false, index)
	var counts := {}
	var gaps := PackedFloat32Array()
	var out_of_range := 0
	var oversize := 0
	var lopsided := 0
	var repeat_bad := 0
	for k in range(60):
		var from := float(k) * CW + float(layout["inset"])
		var node := _probe_trees(from, width)
		var xs: PackedFloat32Array = node.call("_grove_xs")
		counts[xs.size()] = int(counts.get(xs.size(), 0)) + 1
		for n in range(xs.size() - 1):
			var gap := xs[n + 1] - xs[n]
			gaps.append(gap)
			if gap < gap_min - 0.5 or gap > gap_max + 0.5:
				out_of_range += 1
		# 整丛必须装得进本段，而且两端留的空地一样宽（居中）。
		if xs[xs.size() - 1] - xs[0] > width:
			oversize += 1
		if absf((xs[0] - from) - (from + width - xs[xs.size() - 1])) > 0.5:
			lopsided += 1
		# 同一块地方问两次必须是同一丛：区块随镜头回收重建，哈希没取对的话
		# 玩家一回头树丛就换个形状。
		if node.call("_grove_xs") != xs:
			repeat_bad += 1
		node.get_parent().free()

	var min_seen := 99
	var max_seen := 0
	for k in counts:
		min_seen = mini(min_seen, int(k))
		max_seen = maxi(max_seen, int(k))
	var gmin := gaps[0]
	var gmax := gaps[0]
	for g in gaps:
		gmin = minf(gmin, g)
		gmax = maxf(gmax, g)
	print("  扫了 60 丛：棵数 %s，间隔 %.0f～%.0f 像素（设计 %.0f～%.0f）" % [
		counts, gmin, gmax, gap_min, gap_max])
	_check("棵数只落在 3～5 里", min_seen >= lo and max_seen <= hi,
			"实测 %d～%d" % [min_seen, max_seen])
	_check("3 / 4 / 5 三种都出现过（随机是真的在随机）", counts.size() == 3,
			"出现过 %s" % counts)
	_check("间隔都在范围里", out_of_range == 0, "越界 %d 段" % out_of_range)
	_check("间隔不是个固定值（同一丛里也不等距）",
			not is_equal_approx(gmin, gmax), "%.0f ～ %.0f 像素" % [gmin, gmax])
	_check("整丛都装得进本段（不会压到隔壁区块的地盘上）", oversize == 0,
			"探出段外的有 %d 丛" % oversize)
	_check("整丛居中（两端留的空地一样宽）", lopsided == 0,
			"不居中的有 %d 丛" % lopsided)
	_check("同一个位置问两次是同一丛（区块重建之后树不会跑）", repeat_bad == 0,
			"对不上的有 %d 丛" % repeat_bad)

	# ---- 场上那一丛：一棵一棵量 ----
	var chunk := _chunk_node(index)
	var trees: Node = chunk.get_node_or_null("Trees") if chunk != null else null
	_check("树上树了", trees != null, "Chunk%d/Trees" % index)
	if trees == null:
		return
	var grove := _grove_trees(trees)
	_check("一丛树在场上（3～5 棵）", grove.size() >= lo and grove.size() <= hi,
			"%d 棵" % grove.size())
	if grove.is_empty():
		return

	var span := _span_of(Maps.FOREST, index)
	var car_h := _car_height()
	var xs_here := PackedFloat32Array()
	for t in grove:
		xs_here.append(t.position.x)
	print("  这一丛 %d 棵：x = %s（本段 %.0f → %.0f），车高 %.0f，树高 %.0f" % [
		grove.size(), str(xs_here), span.position.x, span.position.x + span.size.x, car_h, tree_h])

	_approx("树高 = 车高（用户要的就是这一条）", tree_h, car_h, 0.01)
	_check("区块上这一丛和探针算出来的是同一丛（纯函数说了算）",
			_grove_xs_of(Maps.FOREST, index) == xs_here,
			"%s vs %s" % [str(_grove_xs_of(Maps.FOREST, index)), str(xs_here)])
	_check("整丛都站在本段里",
			xs_here[0] >= span.position.x and xs_here[xs_here.size() - 1] <= span.position.x + span.size.x,
			"第一棵 %.0f、最后一棵 %.0f" % [xs_here[0], xs_here[xs_here.size() - 1]])

	var grounded := 0
	var frozen := 0
	var layered := 0
	var off_group := 0
	var box_bad := 0
	var canopy_bad := 0
	var sense_missing := 0
	var sense_narrow := 0
	var sense_tall := 0
	for t in grove:
		# 树根要踩在**它自己脚下**的地表上（不是本段左沿的高度）。
		if absf(t.position.y - _terrain.height_at(t.position.x)) < 0.5:
			grounded += 1
		if t.freeze:
			frozen += 1
		# 掩码必须带上层 2：树是刚体，得和**地形**碰（地形在层 2、自己的掩码是 0）。
		# 掩码留 0 的话树会直接穿过地面掉下去。
		if t.collision_layer == 2 and t.collision_mask == 2:
			layered += 1
		if t.is_in_group("ground"):
			off_group += 1

		var box: RectangleShape2D = (t.get_node("Shape") as CollisionShape2D).shape
		if absf(box.size.x - trunk_w) > 0.01 or absf(box.size.y - tree_h) > 0.01:
			box_bad += 1

		# 树冠画到树顶为止，不能画过头（画过头就成了「看着比车高、其实碰不到」）。
		var canopy := t.get_node_or_null("Canopy") as Polygon2D
		var top := INF
		if canopy != null:
			for pt: Vector2 in canopy.polygon:
				top = minf(top, t.position.y + pt.y)
		if canopy == null or absf(top - (t.position.y - tree_h)) >= 0.5:
			canopy_bad += 1

		# 感知区必须比树干宽：树是冻结的，要在**撞上之前**读出车的速度
		# （撞上了才判的话，那一下已经被弹回来了）。
		var zone := _sense_for(trees, t.position.x)
		if zone == null:
			sense_missing += 1
			continue
		var sbox: RectangleShape2D = (zone.get_node("Shape") as CollisionShape2D).shape
		if sbox.size.x <= trunk_w + 20.0:
			sense_narrow += 1
		if sbox.size.y >= tree_h + 60.0:
			sense_tall += 1

	_check("每棵的树根都踩在自己脚下的地表上", grounded == grove.size(),
			"%d / %d 棵" % [grounded, grove.size()])
	_check("站着的时候都是冻结的（推不动，只能被弹回来）", frozen == grove.size(),
			"%d / %d 棵" % [frozen, grove.size()])
	_check("都在层 2 且掩码带上地形层（碰得到车、也踩得住地）", layered == grove.size(),
			"%d / %d 棵" % [layered, grove.size()])
	_check("都不在 ground 组里（撞树不判翻车）", off_group == 0,
			"进组的有 %d 棵" % off_group)
	_check("树干碰撞体 = TRUNK_W × 树高（整棵树都有碰撞，树冠也算）", box_bad == 0,
			"尺寸不对的有 %d 棵" % box_bad)
	_check("树冠的顶就是树顶", canopy_bad == 0, "对不上的有 %d 棵" % canopy_bad)
	_check("每棵都有自己的感知区", sense_missing == 0, "缺的有 %d 棵" % sense_missing)
	_check("感知区比树干宽（能在撞上前读出速度）", sense_narrow == 0,
			"太窄的有 %d 棵" % sense_narrow)
	_check("感知区不比树高太多（从树上飞过去不该推倒它）", sense_tall == 0,
			"太高的有 %d 棵" % sense_tall)


# ---------------------------------------------------------------- 树：低速弹回

## 慢慢撞上去：那棵树**不倒**，车被挡回来。
##
## 量的是**第一棵**（最靠左那棵）：车从左往右开，撞上的就是它。
func _section_trees_slow() -> void:
	print("=== 树：慢速撞上去 ===")
	var index := _find_placed(Maps.FOREST)
	if index < 0:
		return
	var consts := _consts(TREES_SCRIPT)
	var knock: float = consts["KNOCK_SPEED"]

	_setup(Maps.FOREST, true)
	# 第一棵在哪得**先生车**之前问（区块是围着车 stream 的），所以问纯函数。
	var xs := _grove_xs_of(Maps.FOREST, index)
	if xs.is_empty():
		_check("一丛树在场上", false, "本段一棵都没有")
		return
	var tree_x := xs[0]

	# 初速度取门槛的一半：明确在「推不倒」这一侧。
	var vx := knock * 0.5
	var car := _spawn_car(Maps.FOREST, tree_x - 120.0, vx)
	await _settle()
	var trees: Node = _chunk_node(index).get_node_or_null("Trees")
	var grove := _grove_trees(trees) if trees != null else []
	if grove.is_empty():
		_check("一丛树在场上", false, "Chunk%d/Trees" % index)
		return
	var tree := grove[0]
	_check("区块上第一棵就在探针算的位置上", absf(tree.position.x - tree_x) < 0.01,
			"场上 %.2f vs 探针 %.2f" % [tree.position.x, tree_x])
	var st := {"min_vx": 1.0e9, "max_x": -1.0e9, "reason": ""}
	car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	await _drive(2.0, st, func(s: Dictionary) -> void:
		s["min_vx"] = minf(s["min_vx"], car.chassis.linear_velocity.x)
		s["max_x"] = maxf(s["max_x"], car.chassis.global_position.x))

	print("  撞树速度 %.0f（门槛 %.0f），最远 x=%.0f（第一棵在 %.0f），撞后最低 vx=%.0f，死因「%s」" % [
		vx, knock, st["max_x"], tree_x, st["min_vx"], st["reason"]])
	_check("慢速撞上去树不倒", is_instance_valid(tree) and tree.freeze,
			"freeze=%s" % (is_instance_valid(tree) and tree.freeze))
	_check("车被树挡住了（没穿过去）", float(st["max_x"]) < tree_x,
			"最远 %.0f，树在 %.0f" % [st["max_x"], tree_x])
	_check("撞树不会死", String(st["reason"]) == "", "死因「%s」" % st["reason"])
	# **这条是「弹回来」的机械依据**：车在树跟前掉头了（vx 变负），
	# 不是贴着树停下 —— 停下的话 `min_vx` 会停在 0 附近。
	_check("车被弹了回来（vx 变负）", float(st["min_vx"]) < -10.0,
			"最低 vx=%.1f" % st["min_vx"])
	# 弹回来这一侧树还站着 —— 「1 秒后消失」只管**被推倒**的树（见 scripts/trees.gd
	# 的 DISAPPEAR_DELAY），别把这条规则错用到「推不倒、被弹回」的树上。
	await _frames(75)
	_check("撞了一下但没推倒的树不会消失（再等 1.25 秒还在）",
			is_instance_valid(tree) and tree.freeze,
			"freeze=%s" % (is_instance_valid(tree) and tree.freeze))


# ---------------------------------------------------------------- 树：高速推倒 + 1 秒后消失

## 冲得快：树被推倒、就地倒下、留 1 秒，**然后整棵消失**。
##
## 一整趟只跑一个循环，**树这一辈子的每一帧都顺手记下来**（最大仰角、最后的样子、
## 它活了多少帧），而不是在中间插好几个「等到第 N 帧再看一眼」：撞倒发生在第几帧
## 是哈希出来的（起点到树的距离随机），「再等 20 帧」会随着起点漂 —— 记录下来的
## 是「它到底活了多久」，那才是需求里那个 1 秒。
##
## **油门一直踩着**，撞倒之后也接着踩：树倒在车头前面，车得把它顶开才过得去。
func _section_trees_fast() -> void:
	print("=== 树：高速撞上去、1 秒后消失 ===")
	var index := _find_placed(Maps.FOREST)
	if index < 0:
		return
	var consts := _consts(TREES_SCRIPT)
	var knock: float = consts["KNOCK_SPEED"]
	var delay: float = consts["DISAPPEAR_DELAY"]

	_setup(Maps.FOREST, true)
	# 同 [method _section_trees_slow]：先问纯函数要第一棵的位置，再按它生车。
	var xs := _grove_xs_of(Maps.FOREST, index)
	if xs.is_empty():
		_check("一丛树在场上", false, "本段一棵都没有")
		return
	var tree_x := xs[0]

	# 初速度取门槛的 1.6 倍 + 全油门：明确在「推得倒」这一侧。
	var car := _spawn_car(Maps.FOREST, tree_x - 600.0, knock * 1.6)
	await _settle()
	var trees: Node = _chunk_node(index).get_node_or_null("Trees")
	var grove := _grove_trees(trees) if trees != null else []
	if grove.is_empty():
		_check("一丛树在场上", false, "Chunk%d/Trees" % index)
		return
	var tree := grove[0]
	var tree_name := String(tree.name)
	# **lambda 里只抓这个 WeakRef，绝不抓树本身。** 树到点会 queue_free 掉，
	# 抓的是本体的话引擎每帧都会先打一条 "Lambda capture ... was freed" 再调用它 ——
	# 断言照样全绿，但日志里刷一百多条 ERROR，真正的问题就被埋了。
	# WeakRef 是 RefCounted，活得比树久，取不到东西时 get_ref() 安静地返回 null。
	var tree_ref: WeakRef = weakref(tree)
	_check("区块上第一棵就在探针算的位置上", absf(tree.position.x - tree_x) < 0.01,
			"场上 %.2f vs 探针 %.2f" % [tree.position.x, tree_x])

	var st := {
		"max_x": -1.0e9, "reason": "", "speed_at_hit": 0.0, "hit_frame": -1,
		"fall": 0.0, "fell_at": -1, "last_rot": 0.0, "last_spin": 0.0,
		"last_a": 1.0, "last_alive": -1,
	}
	car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	await _drive(4.0, st, func(s: Dictionary) -> void:
		s["max_x"] = maxf(s["max_x"], car.chassis.global_position.x)
		# 树一 queue_free，这个 lambda 手里的引用就变野了：引擎会把捕获值当 null 传进来。
		# **所以先验有效性、后摸字段**——顺序反过来会往日志里刷一百多条
		# "Lambda capture ... was freed" 加一个属性访问错误。
		# max_x 放在这行之前，是因为树没了之后还得接着看车开过去没有。
		var t: RigidBody2D = tree_ref.get_ref()
		if t == null:
			return
		if not t.freeze and int(s["hit_frame"]) < 0:
			# 撞的那一瞬间车多快。**就在这一帧读**：下一帧树已经倒了、
			# 车也被顶了一下，读到的就不是撞上去的速度了。
			s["speed_at_hit"] = car.chassis.linear_velocity.length()
			s["hit_frame"] = Engine.get_physics_frames()
		var rot := absf(t.rotation)
		if rot > 1.2 and int(s["fell_at"]) < 0 and int(s["hit_frame"]) >= 0:
			s["fell_at"] = Engine.get_physics_frames() - int(s["hit_frame"])
		s["fall"] = maxf(float(s["fall"]), rot)
		s["last_rot"] = rot
		s["last_spin"] = absf(t.angular_velocity)
		s["last_a"] = t.modulate.a
		s["last_alive"] = Engine.get_physics_frames() - int(s["hit_frame"]))

	var hit := int(st["hit_frame"])
	if hit < 0:
		_check("高速撞上去把树推倒了", false,
				"一直没撞上（最远到 x=%.0f，树在 %.0f）" % [st["max_x"], tree_x])
		return

	var lived := float(st["last_alive"]) * DT
	var fell := float(st["fell_at"]) * DT
	print("  撞上去时 %.0f（门槛 %.0f）；%.2f 秒转过大半圈，撞倒之后活了 %.2f 秒（要 %.2f），最后仰角 %.0f°" % [
		st["speed_at_hit"], knock, fell, lived, delay, rad_to_deg(st["last_rot"])])

	_check("高速撞上去把树的冻结解掉了", hit >= 0, "第 %d 帧" % hit)
	_check("推倒的时候车确实够快", float(st["speed_at_hit"]) >= knock,
			"撞上去时 %.0f（门槛 %.0f）" % [st["speed_at_hit"], knock])
	# 它得**在消失之前**就倒下去，不然玩家看到的是一棵歪着的树凭空没了。
	_check("1 秒之内就倒下去了（玩家看得见这一下）", st["fell_at"] >= 0 and fell < delay,
			"%.2f 秒转过大半圈（要在 %.2f 秒之内）" % [fell, delay])
	_check("树就地倒下了（转过大半圈）", float(st["fall"]) > 1.2,
			"最大仰角 %.0f°" % rad_to_deg(st["fall"]))
	_check("倒下之后就停住了（没有一直滚）", float(st["last_spin"]) < 1.5,
			"最后角速度 %.2f rad/s" % st["last_spin"])
	_check("最后是躺着的（不是又竖回去了）", float(st["last_rot"]) > 1.4,
			"最后仰角 %.0f°" % rad_to_deg(st["last_rot"]))
	# **这条是用户那条「1 秒后消失」的直接度量**：树从撞倒到没了，一共活了多久。
	_check("被撞倒之后整整 1 秒才消失", absf(lived - delay) <= DT * 1.5,
			"活了 %.2f 秒（要 %.2f ± 一帧）" % [lived, delay])
	_check("消失前是淡出的，不是啪一下没的", float(st["last_a"]) < 1.0 and float(st["last_a"]) > 0.0,
			"最后一帧不透明度 %.2f" % st["last_a"])
	_check("消失是拆掉不是藏起来（节点从场上摘了）",
			trees.get_node_or_null(tree_name) == null, tree_name)
	# 先确认这一块区块还在场上：区块是被回收重建的，区块被拆掉的话这棵树也会跟着
	# 消失 —— 那就成了「因为区块没了所以算树消失了」，量错了还照样绿。
	_check("这一块区块还活着（树消失不是区块被回收造成的）",
			_chunk_node(index) != null and _chunk_child(index, "Trees") != null,
			"Chunk%d/Trees" % index)
	_check("车开过去了、也没死", float(st["max_x"]) > tree_x and String(st["reason"]) == "",
			"最远 %.0f（树在 %.0f），死因「%s」" % [st["max_x"], tree_x, st["reason"]])


# ---------------------------------------------------------------- 月球重力

## 月球的重力更小：倍率写进三个刚体，**落同样多的帧、掉的高度按倍率缩**。
##
## 量「下落距离之比」而不是「跳得多高」：下落是纯重力，和扭矩、摩擦、地形全无关，
## 所以量出来的比例必须精确等于倍率。跳跃高度会被轮胎、扭矩、着陆姿态搅浑。
func _section_moon_gravity() -> void:
	print("=== 月球重力 ===")
	var moon := Maps.gravity_scale(Maps.MOON)
	var off := PackedStringArray()
	for map_id: String in Maps.IDS:
		if map_id != Maps.MOON and not is_equal_approx(Maps.gravity_scale(map_id), 1.0):
			off.append(map_id)
	_check("只有月球的重力倍率不是 1", off.is_empty(),
			"月球 ×%.2f，其它地图：%s" % [moon, "全部 ×1" if off.is_empty() else "，".join(off)])
	_check("月球的重力更小", moon < 1.0, "×%.2f" % moon)
	_check("月球的重力不是小到没法玩（还能落地）", moon > 0.1, "×%.2f" % moon)

	# 两个车一起落：一个平原、一个月球。没有地面（不铺地形），所以只受重力。
	var world := Node2D.new()
	add_child(world)
	var pair: Array[HillCar] = []
	for i in 2:
		var map_id := Maps.MOON if i == 1 else Maps.PLAINS
		var car := CAR.instantiate()
		car.position = Vector2(float(i) * 2000.0, 200.0)
		world.add_child(car)
		car.apply_map(map_id)
		for body: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
			# 地图的 drag 会把下落变成「带阻尼的下落」，比例就不再等于重力倍率了。
			# 这一节量的是重力，所以把阻尼拿掉。
			body.linear_damp = 0.0
		pair.append(car)
		_approx("%s 的重力倍率写进了三个刚体" % map_id, car.chassis.gravity_scale,
				Maps.gravity_scale(map_id), 0.001)

	await _frames(4)
	var y0 := [pair[0].chassis.global_position.y, pair[1].chassis.global_position.y]
	var frames := 30
	await _frames(frames)
	var drop_earth: float = pair[0].chassis.global_position.y - float(y0[0])
	var drop_moon: float = pair[1].chassis.global_position.y - float(y0[1])
	print("  %d 帧下落：平原 %.1f 像素、月球 %.1f 像素，比值 %.3f" % [
		frames, drop_earth, drop_moon, drop_moon / drop_earth])
	_check("两个车都在往下掉", drop_earth > 0.0 and drop_moon > 0.0,
			"平原 %.1f、月球 %.1f" % [drop_earth, drop_moon])
	_within("月球落得更少，而且比例就是重力倍率", drop_moon / drop_earth, moon, 0.03)

	# 换图之后要还回来：不然月球跑完开平原会一直飘着。
	pair[1].apply_map(Maps.PLAINS)
	_approx("换回平原之后重力还回来了", pair[1].chassis.gravity_scale, 1.0, 0.001)
	world.queue_free()


# ---------------------------------------------------------------- 屋顶：烟囱摆在哪儿

## 烟囱摆在**中间那几级平屋面**上，底面贴屋面、两头留出 [constant
## HillChimneys.CHIMNEY_EDGE]（[method Maps.chimney_at] + [method
## HillChimneys.chimney_rect]）。
##
## 这一节纯几何，**不铺世界、不跑车**：剖面和骰子都是现算的纯函数，区块摆没摆出来
## 跟结论无关。四十栋全查，不挑「有烟囱的那一栋」—— 「一栋只有一级钢梯的房子
## 压根没有中间平屋面，所以一根都不该有」正是要测的行为之一。
func _section_chimneys_place() -> void:
	print("=== 屋顶：烟囱摆在哪儿 ===")
	var t := _real_terrain(Maps.ROOFTOP)
	var houses := 0
	var rolled := 0
	var placed := 0
	var stray := 0          # 骰子没中却摆出来了一根
	var bad_kind := 0       # 落在钢梯上 / 落点 / 跳台上
	var bad_floor := 0      # 底面没贴在这一级的屋面上
	var bad_edge := 0       # 整根没留出 CHIMNEY_EDGE（骑在屋檐棱上）
	var bad_size := 0       # 宽高和骰子对不上
	var mid_secs := {}      # 摆在「中间第几级」上的分布
	var dice_secs := {}     # 骰子掷中的是第几级
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + CHIMNEY_SCAN):
		houses += 1
		var prof := t.roof_profile(i)
		var start := float(i) * CW
		var dice := Maps.chimney_at(SEED, i)
		var rect := HillChimneys.chimney_rect(prof, dice, start)
		if dice.is_empty():
			if rect.size.x > 0.0:
				stray += 1
			continue
		rolled += 1
		dice_secs[int(dice["section"])] = true
		if rect.size.x <= 0.0:
			continue
		placed += 1
		if not is_equal_approx(rect.size.x, float(dice["w"])) \
				or not is_equal_approx(rect.size.y, float(dice["h"])):
			bad_size += 1
		var pts: PackedVector2Array = prof["pts"]
		var ramps: PackedInt32Array = prof["ramps"]
		# 平段 = 不是钢梯的那几段。中间那几段是 `flats[1 .. size-2]`：第 0 段是落点
		# （车砸下来的地方）、最后一段是跳台，烟囱摆这两处等于白送一个 buff，
		# 而缝宽是按没有烟的时候标定的。
		var flats: Array[int] = []
		for k in pts.size() - 1:
			if not ramps.has(k):
				flats.append(k)
		var cx := rect.position.x + rect.size.x * 0.5 - start
		var sec := -1
		for k in pts.size() - 1:
			if cx >= pts[k].x and cx <= pts[k + 1].x:
				sec = k
		if sec < 0 or ramps.has(sec) or sec == flats[0] or sec == flats[flats.size() - 1]:
			bad_kind += 1
			continue
		mid_secs[flats.find(sec)] = true
		if not is_equal_approx(rect.end.y, pts[sec].y):
			bad_floor += 1
		if rect.position.x - (start + pts[sec].x) < HillChimneys.CHIMNEY_EDGE - 0.001 \
				or (start + pts[sec + 1].x) - rect.end.x < HillChimneys.CHIMNEY_EDGE - 0.001:
			bad_edge += 1
	t.free()

	print("  %d 栋房子：掷中 %d 栋，摆上 %d 根（摆在中间第 %s 级）" % [
		houses, rolled, placed, str(mid_secs.keys())])
	_check("骰子没中的房子上一根烟囱都没有", stray == 0, "多出 %d 根" % stray)
	_check("摆上的都落在中间那几级平屋面上", bad_kind == 0,
			"落在钢梯/落点/跳台上的 %d 根" % bad_kind)
	_check("底面正贴在这一级的屋面上", bad_floor == 0, "离屋面 %d 根" % bad_floor)
	_check("两头都留着 CHIMNEY_EDGE（不骑屋檐棱）", bad_edge == 0, "贴棱的 %d 根" % bad_edge)
	_check("宽高就是骰子给的那两个数", bad_size == 0, "对不上的 %d 根" % bad_size)
	_check("一屏总该有几根，也不是栋栋都有", placed >= 3 and placed < houses,
			"%d/%d 栋" % [placed, houses])
	# 掷中的是第几级、最后摆在第几级：两边都别总落在同一级上，否则「顺延下一级」
	# 那段代码等于没跑过。
	_check("掷中的级和摆下的级都是活的", dice_secs.size() >= 2 and mid_secs.size() >= 1,
			"掷中 %s、摆下 %s" % [str(dice_secs.keys()), str(mid_secs.keys())])

	# 顺延：手搓一份剖面，让骰子掷中的那一级**窄得摆不下**，看它是不是挪到下一级。
	# 四十栋里靠运气撞上这个情形太不稳，所以这里直接构造。
	#
	# 剖面 = 平 / 梯 / 平 / 梯 / 平 / 梯 / 平（三段钢梯 → 三处平屋面，中间有两段）：
	# 第 2 段只有 10 宽，第 4 段 110 宽。骰子说「第 0 级」（= 第一段中间平屋面 = pts[2..3]）。
	var wide := PackedVector2Array([
		Vector2(0.0, 200.0), Vector2(100.0, 200.0),     # 落点
		Vector2(140.0, 150.0),                          # 钢梯 1
		Vector2(150.0, 150.0),                          # 中间平屋面 1（10 宽，摆不下）
		Vector2(190.0, 100.0),                          # 钢梯 2
		Vector2(300.0, 100.0),                          # 中间平屋面 2（110 宽）
		Vector2(340.0, 60.0),                           # 钢梯 3
		Vector2(500.0, 60.0),                           # 跳台
	])
	var fake := {"len": 500.0, "y0": 200.0, "y1": 60.0, "pts": wide,
			"ramps": PackedInt32Array([1, 3, 5])}
	var dice2 := {"section": 0, "at": 0.5, "w": 26.0, "h": 60.0}
	var r2 := HillChimneys.chimney_rect(fake, dice2, 0.0)
	_approx("掷中的那级太窄就顺延到下一级（摆在 190～300 那一段的正中）",
			r2.position.x + r2.size.x * 0.5, 245.0)
	_approx("顺延之后底面贴的是**新那级**的屋面（100）", r2.end.y, 100.0)
	var r2l := HillChimneys.chimney_rect(fake, {"section": 0, "at": 0.0, "w": 26.0, "h": 60.0}, 0.0)
	var r2r := HillChimneys.chimney_rect(fake, {"section": 0, "at": 1.0, "w": 26.0, "h": 60.0}, 0.0)
	_approx("`at` = 0 时贴着左边留 CHIMNEY_EDGE", r2l.position.x, 190.0 + 8.0)
	_approx("`at` = 1 时贴着右边留 CHIMNEY_EDGE", r2r.end.x, 300.0 - 8.0)
	# 只有一级钢梯的房子没有中间平屋面（`flats` 只有落点和跳台两段）。
	var single := {"len": 400.0, "y0": 200.0, "y1": 150.0,
			"pts": PackedVector2Array([Vector2(0.0, 200.0), Vector2(100.0, 200.0),
					Vector2(200.0, 150.0), Vector2(400.0, 150.0)]),
			"ramps": PackedInt32Array([1])}
	_check("一级钢梯的房子（没有中间平屋面）摆不出烟囱",
			HillChimneys.chimney_rect(single, dice2, 0.0).size.x <= 0.0, "却有")
	_check("没有剖面就摆不出烟囱",
			HillChimneys.chimney_rect({}, dice2, 0.0).size.x <= 0.0, "却有")

	# 烟柱和砖柱子共用同一份矩形，所以囱口对得上这件事是**结构上**保证的：
	# 这里只钉住它们之间的那三条关系。
	var chim := Rect2(1000.0, 380.0, 26.0, 60.0)
	var smoke := HillChimneys.smoke_rect(chim)
	_approx("烟柱正对着囱口", smoke.position.x + smoke.size.x * 0.5,
			chim.position.x + chim.size.x * 0.5)
	_approx("烟柱底边压在屋面上（不是囱口上）", smoke.end.y, chim.end.y)
	_approx("烟柱高就是 SMOKE_H", smoke.size.y, HillChimneys.SMOKE_H)
	_check("没有烟囱就没有烟柱", HillChimneys.smoke_rect(Rect2()).size.x <= 0.0, "却有")

	_within("托力就是 1.4 倍自重（净 +0.4 g）",
			HillChimneys.smoke_lift(174.0, 980.0) - 174.0 * 980.0, 174.0 * 980.0 * 0.4, 0.001)


# ---------------------------------------------------------------- 屋顶：烟柱托一把

## 车厢里的烟真的把车往上托（[method HillChimneys._physics_process]）。
##
## **光验 `smoke_lift` 的算式不算数**：那只证明「算式写对了」。力区摆歪了、碰撞掩码
## 漏了、三个刚体各加了一遍 —— 算式全都是对的，手感全是错的。所以这里跑真物理：
## 同一栋房子、同一个高度，**柱子里的车和柱子外的车各落 30 帧**，比谁落得多。
##
## 量下落距离而不是速度：速度是瞬时量，头几帧销子还在被拉直（车一进树，两个轮子是
## 挂在销子上的），单帧读数会抖；下落距离是这段时间的积分，稳得多（月球那节同一个道理）。
func _section_chimneys_lift() -> void:
	print("=== 屋顶：烟柱托一把 ===")
	var idx := _chimney_house()
	if idx < 0:
		_check("前 %d 栋里能找到一栋有烟囱的房子" % CHIMNEY_SCAN, false, "一根都没有")
		return

	# 只有一栋房子、一块区块，而且地形**没有目标** → 一块区块都不建、没有地面。
	# 车就悬在那儿落 30 帧，除了烟柱的力没有别的东西碰它。
	var world := Node2D.new()
	add_child(world)
	var terr := HillTerrain.new()
	terr.world_seed = SEED
	terr.map_id = Maps.ROOFTOP
	world.add_child(terr)
	var chunk := Node2D.new()          # 假装是区块节点：`terrain_node()` 往上两级找地形
	chunk.name = "Chunk%d" % idx
	terr.add_child(chunk)
	var feat: Node2D = CHIMNEYS_SCRIPT.new()
	chunk.add_child(feat)
	# **必须在 add_child 之后 setup** —— setup 里就要建力区了。
	feat.setup(Rect2(Vector2(float(idx) * CW, 0.0), Vector2(CW, 0.0)), 0.0)

	var prof := terr.roof_profile(idx)
	var chim := HillChimneys.chimney_rect(prof, Maps.chimney_at(SEED, idx), float(idx) * CW)
	var smoke := HillChimneys.smoke_rect(chim)
	var cmx := chim.position.x + chim.size.x * 0.5

	# 力区本身：一层不碰地形的检测区，不是一个碰撞体 —— 车撞上砖柱子不该被弹开。
	var areas := 0
	var solids := 0
	for child in feat.get_children():
		if child is Area2D:
			areas += 1
			_check("力区在 0 层、只找 1 层的车（不挡任何东西）",
					child.collision_layer == 0 and child.collision_mask == 1,
					"层 %d / 掩码 %d" % [child.collision_layer, child.collision_mask])
		elif child is CollisionObject2D:
			solids += 1
	_check("烟囱只摆一个力区、不摆碰撞体", areas == 1 and solids == 0,
			"力区 %d 个、碰撞体 %d 个" % [areas, solids])

	# 烟团长什么样。无头跑**不发 `NOTIFICATION_DRAW`**，`_draw` 里画了什么一条都验不到
	# （用户报的正是「烟囱的动画还没做好」），所以算式抽在 [method
	# HillChimneys.smoke_visual] 里，这里直接喂几颗烟团比 —— 和沙尘暴、金币那几处
	# 同一个套路。
	#
	# 一颗烟团在画面上是**越升越大、越升越淡**（老 = 高 = 散）。这两个量都是
	# `life / span` 的函数，所以造两颗：一颗刚到囱口、一颗又老又高。
	var low := HillChimneys.Puff.new()
	low.pos = Vector2(cmx, chim.position.y)              # 囱口上沿
	low.life = 2.0
	low.span = 2.0                                       # 刚冒出来
	low.size = HillChimneys.PUFF_SIZE
	var high := HillChimneys.Puff.new()
	high.pos = Vector2(cmx, chim.position.y - 280.0)     # 升到半空
	high.life = 0.4
	high.span = 2.0                                      # 老了
	high.size = HillChimneys.PUFF_SIZE
	var v_lo: Dictionary = feat.call("smoke_visual", low)
	var v_hi: Dictionary = feat.call("smoke_visual", high)
	var c_lo: Color = v_lo["color"]
	var c_hi: Color = v_hi["color"]
	print("  囱口那颗：半径 %.1f、α %.3f；升到 280 像素那颗：半径 %.1f、α %.3f" % [
			v_lo["radius"], v_lo["alpha"], v_hi["radius"], v_hi["alpha"]])
	_check("烟团越升越大（老了就散开）", float(v_hi["radius"]) > float(v_lo["radius"]),
			"%.1f → %.1f" % [v_lo["radius"], v_hi["radius"]])
	_check("烟团越升越淡", float(v_hi["alpha"]) < float(v_lo["alpha"]) * 0.8,
			"%.3f → %.3f" % [v_lo["alpha"], v_hi["alpha"]])
	_check("囱口那颗是暖灰、高处那颗偏冷", c_lo.r - c_lo.b > c_hi.r - c_hi.b,
			"囱口 r−b %.3f，高处 r−b %.3f" % [c_lo.r - c_lo.b, c_hi.r - c_hi.b])
	# 不能钉「正好等于 PUFF_ALPHA」：淡出的基准是**屋面那条线**（`up` 从屋面算起），
	# 而烟团是从囱口生出来的 —— 囱口本来就在屋面往上 46～78 像素，所以刚出生的那一颗
	# 就已经淡掉一小截了。这是设计的（力区从屋面起算，见脚本文件头），不是误差。
	_check("囱口那颗够看得见（在 PUFF_ALPHA 的一半以上，也不会超过它）",
			float(v_lo["alpha"]) > HillChimneys.PUFF_ALPHA * 0.5
			and float(v_lo["alpha"]) <= HillChimneys.PUFF_ALPHA + 0.001,
			"α %.3f（PUFF_ALPHA %.2f）" % [v_lo["alpha"], HillChimneys.PUFF_ALPHA])
	# 出了柱子顶端就该**看不见**了（不是画成一团永远淡不掉的雾）。
	var over := HillChimneys.Puff.new()
	over.pos = Vector2(cmx, chim.end.y - HillChimneys.SMOKE_H - 40.0)
	over.life = 2.0
	over.span = 2.0
	over.size = HillChimneys.PUFF_SIZE
	var v_over: Dictionary = feat.call("smoke_visual", over)
	_approx("飘出柱子顶端就完全透明了", float(v_over["alpha"]), 0.0, 0.001)

	# 起始高度：柱子顶端往下 120 像素，还在柱子里，30 帧里也不会飘出去。
	var y0 := smoke.position.y + 120.0
	var frames := 30
	var drop: Array[float] = []
	# **加速度按速度差算，不按下落距离**：下面那 4 帧垫底里车已经在动了（烟里是往上、
	# 柱子外是往下），拿位移反推会把那段初速度一起算进加速度里 —— 控制组实测那条
	# 能算出 1251 而真值只有 980。速度差 `Δv / t` 对常力是**精确**的，和起点无关。
	var dv: Array[float] = []
	for run in 3:
		if run == 1:
			# 第二趟把烟囱整个撤掉：同样的高度、同样的位置，只剩重力。
			feat.free()
			await _frames(1)
		var car := CAR.instantiate()
		car.position = Vector2(cmx if run != 2 else cmx + 400.0, y0)
		world.add_child(car)
		car.apply_map(Maps.ROOFTOP)
		car.fuel = 1.0e9
		for body: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
			# 地图的 drag 会把「纯重力」变成「带阻尼的下落」，那样两边就不只差烟了。
			body.linear_damp = 0.0
		await _frames(4)
		var y_start: float = car.chassis.global_position.y
		var v_start: float = car.chassis.linear_velocity.y
		await _frames(frames)
		drop.append(car.chassis.global_position.y - y_start)
		dv.append(car.chassis.linear_velocity.y - v_start)
		car.queue_free()
		await _frames(1)

	var t := float(frames) * DT
	var a_in := dv[0] / t
	var a_out := dv[1] / t
	print("  %d 帧（%.2f 秒）里车壳走了：烟里 %.1f、撤掉烟 %.1f、离柱子 400 像素 %.1f 像素" % [
		frames, t, drop[0], drop[1], drop[2]])
	print("  速度变化 %.0f / %.0f / %.0f 像素每秒 ⇒ 加速度 %.0f / %.0f / %.0f（g = 980）" % [
		dv[0], dv[1], dv[2], a_in, a_out, dv[2] / t])
	_check("撤掉烟之后是自由落体（往下掉）", drop[1] > 40.0, "%.1f 像素" % drop[1])
	_check("柱子里不往下掉，反而被托着往上走", drop[0] < 0.0, "%.1f 像素" % drop[0])
	_within("柱子外的控制组和撤掉烟一样（烟只托柱子里那 96 像素宽）",
			drop[2], drop[1], 0.05)
	# 先把「自由落体」这条自己钉住：控制组的加速度必须就是 g。有这一条在前，下面
	# 「烟里 −0.4 g」才是「力真的加对了」，而不是「两个数都偏了正好差 0.4 g」。
	_within("撤掉烟之后加速度就是 g", a_out, 980.0, 0.05)
	# 净加速度 = (1.4 − 1) g = +0.4 g（往上，y 轴朝下所以是负）。留 25% 的余量：
	# 车是**三个刚体**用销子串起来的，烟只推车壳，销子那头总有一点摆动。
	_within("净加速度是 +0.4 g（1.4 倍自重减掉自重）", a_in, -0.4 * 980.0, 0.25)
	world.queue_free()


## 前 [constant CHIMNEY_SCAN] 栋里第一栋**真的摆上了**烟囱的房子（没有就是 -1）。
##
## 纯函数，不用等区块建出来 —— 跑车那节要拿它开个头，而区块是围着车 stream 的。
func _chimney_house() -> int:
	var t := _real_terrain(Maps.ROOFTOP)
	var found := -1
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + CHIMNEY_SCAN):
		if HillChimneys.chimney_rect(t.roof_profile(i), Maps.chimney_at(SEED, i),
				float(i) * CW).size.x > 0.0:
			found = i
			break
	t.free()
	return found
