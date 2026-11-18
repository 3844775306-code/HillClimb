extends Node
## 车辆契约与几何的静态检查：**不跑物理**，秒级出结果。
##
## ## 为什么要有这个测试
##
## 车的几何和「坑」的几何是耦合的：**车壳底面比坑口宽，车就会横架在坑上** ——
## 两个轮子悬空、油门倒车都推不动，而死亡区还在坑的更下面，所以它既死不了也
## 出不来，只能等油烧完。这条已经实测过（分析见 README「车壳长度」那一段）。
##
## 加多辆车之后，「谁比坑宽」从一件事变成一张表，而这张表人脑记不住：坑的尺寸
## 在 [constant Maps.FEATURE_LAYOUT]，死亡线上沿的比例却**散在各自的特殊地形脚本
## 里**（吊桥 0.75、冰湖用默认 0.55、火山口是 LAVA_LEVEL）。这里把它们凑到一起算。
##
## ## 四组检查
##
## A. **契约** —— 节点名 / 层掩码 / 接触监听 / 铰链位置。下游全是按名字和层号找车
##    的（effects 读轮子半径、冰湖改轮子摩擦、Upgrades 数质量、特殊地形靠
##    `body.get_parent()` 认车），哪一项错了都是**静默失灵**，不报错、只是不对。
## B. **几何** —— 离地间隙（太小会搁浅在 V 谷上）、车壳底面长度（太大就会架在坑上）。
## C. **马达与燃油** —— 推重比、极速、以及**力矩有没有被 [member HillCar.max_torque]
##    限幅**（限幅了起步推力就只有设计值的几分之一，而车库页脚还在按公式报数）。
## D. **车 × 坑** —— 每种坑挖到死亡线上沿时口有多宽，比车壳窄就是卡死。

## 那些「住在别人家」的常量，要从**脚本源文件本身**读，不能在这里抄一份：
## 改了那边就必须让这个测试响，而不是继续拿旧数字算表。
##
## 用 `load()` 而不是 `const X := preload()` —— 后者在 Godot 里是个**类引用**，
## 类引用上不许调 `get_script_constant_map()` 这种非静态方法（解析期就报错）。
const BRIDGE_SCRIPT_PATH := "res://scripts/rope_bridge.gd"
const CRATER_SCRIPT_PATH := "res://scripts/crater.gd"

## 坑的剖面按 1 像素扫一遍。区块宽 800，一个坑最多扫 800 次，无所谓。
const SCAN_STEP := 1.0

## 每种坑的死亡区上沿：`frac × 深度`，从坑沿往下算。
##
## **这三个值是从三个地方抄来的，改那边就要改这里。** 出处都写在行尾了。
## 火山口那个是具名常量，所以下面顺手断言一次 —— 改了 `LAVA_LEVEL` 忘了改这里会响。
const KILL_FRAC := {
	Maps.FEATURE_BRIDGE: {"frac": 0.75, "who": "rope_bridge.gd 的 add_hazard(..., 0.75)"},
	Maps.FEATURE_LAKE: {"frac": 0.55, "who": "ice_lake.gd 用 feature.gd 的默认值 0.55"},
	Maps.FEATURE_CRATER: {"frac": 0.35, "who": "crater.gd 的 LAVA_LEVEL"},
}

## 有坑的特殊地形（要参与 D 组的）。沙尘暴不挖地形，没有坑口可言。
const PITS: Array[String] = [Maps.FEATURE_BRIDGE, Maps.FEATURE_LAKE, Maps.FEATURE_CRATER]

## 离地间隙的下限。README 记的实测值：车壳底面离轮底太近，车会横架在 V 形山谷上
## 搁浅（轮子悬空、被静摩擦锁住）。默认车留了约 31 px。
const MIN_CLEARANCE := 31.0

var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	# 只读存档、不写。这个测试不碰存档，但 Upgrades/garage 那边是 autoload，
	# 保险起见还是把盘关上。
	SaveData.persist = false

	print("=== A. 契约 ===")
	for id in Vehicles.available():
		_contract(id)
	print("")

	print("=== B/C. 几何与马达 ===")
	_geometry_table()
	print("")

	print("=== D. 车 × 坑（车壳底面 vs 坑口）===")
	_pit_matrix()
	print("")

	_pit_ceiling()
	print("")

	if _failures == 0:
		print("全部通过")
	else:
		print("!! %d 项不通过" % _failures)
	get_tree().quit()


# ---------------------------------------------------------------- A. 契约

## 一辆车必须满足的硬条件：有哪些节点、层号怎么设、轮子几个、铰链对得上。
##
## **轮子是按分组标记收的，不是按节点名。** 独轮车只有一个轮子（连 `FrontWheel`
## 都没有），写死 `RearWheel` / `FrontWheel` 那一套在它身上直接是 null。
## 这里的判据是「直接子节点 + 带 [constant Vehicles.WHEEL_GROUP] 标记的
## [RigidBody2D]」，和 [method Vehicles.wheels_of] / `HillCar._collect_wheels`
## **必须逐字一致** —— 三处漂开的话，选车卡片上画的轮子和实车就不是一回事了。
func _contract(id: String) -> void:
	var car := Vehicles.instantiate(id)
	if car == null:
		_check("%s 能实例化" % id, false, true)
		return
	var zh: String = Vehicles.get_vehicle(id)["zh"]
	print("  [%s]" % id)

	for path in ["Chassis", "Chassis/Head", "Chassis/Body", "Effects"]:
		_check("  %s 存在" % path, car.has_node(path), true)

	var chassis := car.get_node_or_null("Chassis") as RigidBody2D
	var head := car.get_node_or_null("Chassis/Head") as Area2D
	if chassis == null or head == null:
		car.free()
		return

	var wheels: Array[RigidBody2D] = []
	var joints: Array[PinJoint2D] = []
	for child in car.get_children():
		var body := child as RigidBody2D
		if body != null:
			if body == chassis:
				continue
			# 车上除了车壳和轮子不该有别的刚体。真有一个（比如谁给某辆车加了个
			# 独立悬挂配重），那它也得进 `wheel` 组 —— 否则 `bodies()` / 马达 /
			# 惯量 / [method Vehicles.stats] 的质量求和都会漏掉它，而且无声无息。
			_check("  %s 打了 wheel 分组标记" % body.name,
					body.is_in_group(Vehicles.WHEEL_GROUP), true)
			if body.is_in_group(Vehicles.WHEEL_GROUP):
				wheels.append(body)
			continue
		var joint := child as PinJoint2D
		if joint != null:
			joints.append(joint)

	_check("  至少一个轮子", wheels.size() >= 1, true)
	# 独轮车是唯一一辆单轮车，而且**「只有一个轮子」正是它另外两条逻辑的前提**：
	# 打开陀螺仪自平衡（`balance_torque`）和永远不发独轮奖励（`wheels.size() < 2`
	# 那道闸）。这里把它钉住，免得哪天有人给它加个辅助轮 —— 那两处都会静默失效。
	if id == Vehicles.MONO:
		_check("  独轮车只有一个轮子", wheels.size(), 1)
	else:
		_check("  两个轮子", wheels.size(), 2)
	_check("  轮子都有 Shape 且是圆形", _all_circles(wheels), true)

	# 层号：地形和特殊地形都在层 2（"ground" 组），车在层 1，车要能碰到地形、
	# 头要能碰到地形。
	var bodies: Array[RigidBody2D] = [chassis]
	bodies.append_array(wheels)
	for body in bodies:
		_check("  %s 层=1 掩码=3" % body.name,
				[body.collision_layer, body.collision_mask], [1, 3])
		_check("  %s can_sleep=false" % body.name, body.can_sleep, false)

	# 轮子必须开接触监听：[method HillCar._touching_ground] 和腾空奖励都靠
	# get_colliding_bodies()，不开就永远判成「在空中」，每局白送腾空奖励。
	for wheel in wheels:
		_check("  %s 接触监听" % wheel.name, wheel.contact_monitor, true)
		_check("  %s 上报接触数≥2" % wheel.name, wheel.max_contacts_reported >= 2, true)

	_check("  车壳是凸多边形", chassis.get_node("Body").shape is ConvexPolygonShape2D, true)
	_check("  头 Area2D 层=0 掩码=2（只碰地面）", [head.collision_layer, head.collision_mask], [0, 2])
	# Effects 要排在 Chassis 前面才画在车体之下，而且它靠 get_parent() 认车。
	_check("  Effects 排在 Chassis 之前",
			car.get_node("Effects").get_index() < chassis.get_index(), true)

	# 铰链：位置必须和轮子**完全一致**。PinJoint2D 的锚点是在进树那一刻按两边
	# 刚体的当前位置算好存进物理服务器的，位置对不上就等于给车装了个偏心的轴。
	#
	# 按「这个关节认的是哪个轮子」去配对，而不是认 `RearJoint` / `FrontJoint`
	# 这两个名字：独轮车只有一个关节（就叫 `RearJoint`），写死两个名字在它身上
	# 是 null，而 `get_node(null)` 会直接报错。
	_check("  关节数 == 轮子数", joints.size(), wheels.size())
	for wheel in wheels:
		var found: PinJoint2D = null
		for joint in joints:
			if _joint_b(joint) == wheel:
				found = joint
		if found == null:
			_check("  %s 有铰链" % wheel.name, false, true)
			continue
		_check("  %s 铰链在轮心上" % wheel.name, found.position, wheel.position)
		_check("  %s 铰链连的是车壳和它自己" % wheel.name,
				[_joint_a(found), _joint_b(found)], [chassis, wheel])

	car.free()


func _all_circles(wheels: Array[RigidBody2D]) -> bool:
	for wheel in wheels:
		var shape := wheel.get_node_or_null("Shape") as CollisionShape2D
		if shape == null or not (shape.shape is CircleShape2D):
			return false
	return true


## 关节两端指向的节点（[member PinJoint2D.node_a] 是相对关节自己的路径）。
## 路径为空时返回 null —— `get_node_or_null(NodePath(""))` 拿到的是关节自己。
func _joint_a(joint: PinJoint2D) -> Node:
	return joint.get_node_or_null(joint.node_a) if joint.node_a != NodePath("") else null


func _joint_b(joint: PinJoint2D) -> Node:
	return joint.get_node_or_null(joint.node_b) if joint.node_b != NodePath("") else null


# ---------------------------------------------------------------- B/C. 几何与马达

func _geometry_table() -> void:
	print("  %-10s %6s %7s %7s %7s %7s %7s %8s %8s %7s" % [
		"车", "质量", "车壳长", "轮距", "离地", "极速", "满油门", "推重比", "实际起步", "力矩",
	])
	for id in Vehicles.available():
		var s := Vehicles.stats(id)
		if s.is_empty():
			continue
		print("  %-8s %6.0f %7.0f %7.0f %7.0f %7.0f %6.1fs %8.2f %8.2f %7s" % [
			Vehicles.get_vehicle(id)["zh"], s["mass"], s["chassis_len"], s["wheelbase"],
			s["clearance"], s["top_speed"], s["fuel_seconds"], s["ratio"], s["launch_ratio"],
			"限幅" if s["torque_clamped"] else "OK",
		])
	print("  注：全是**原厂值**（车实例没进树，Upgrades 还没作用）。")
	print("      推重比 = 轮数×转速×力矩系数÷半径÷(质量×980)，是设计值；实际起步是")
	print("      同一式子里把力矩上限算进去的结果（下限幅时两列相等）。力矩列「限幅」=")
	print("      静止时需要的扭矩（转速×力矩系数）超过 max_torque，起步推力达不到设计值。")
	print("      **轮数是变量**：独轮车只有一个轮子出力，写死 2 会让它的推重比虚高一倍。")

	for id in Vehicles.available():
		var s := Vehicles.stats(id)
		if s.is_empty():
			continue
		var name: String = Vehicles.get_vehicle(id)["zh"]
		# 离地间隙：车壳底面必须离轮底够远，否则会横架在 V 形山谷上搁浅。
		if s["clearance"] < MIN_CLEARANCE:
			_failures += 1
			print("  FAIL %s 离地只有 %.0f px（要 ≥ %.0f），会搁浅在 V 谷上" % [
				name, s["clearance"], MIN_CLEARANCE])
		else:
			print("  OK   %s 离地 %.0f px" % [name, s["clearance"]])
		# 力矩被限幅不是错误，但一定要看见 —— 限幅了就等于换了一台更弱的发动机，
		# 而车库页脚显示的推重比还是设计值。
		if s["torque_clamped"]:
			print("  注意 %s 的力矩被限幅：需要 %.2fe6，上限 %.2fe6 → 起步推重比只有 %.2f（设计 %.2f）" % [
				name, s["torque_demand"] / 1e6, s["max_torque"] / 1e6,
				s["launch_ratio"], s["ratio"]])


# ---------------------------------------------------------------- D. 车 × 坑

## 把每个坑的剖面按 1 像素扫出来，换算成「相对坑沿往下多深」（世界坐标，正数 = 更深）。
##
## 直接用 [method HillTerrain._carve_in_chunk] —— 那是挖地形的真函数（静态的，
## 不依赖噪声和种子）。这里**不重写一份余弦公式**：哪天坑的形状改了，这个测试
## 得跟着一起改，抄一份就等于给自己埋一个「测试和实车对不上」的坑。
##
## 关键是**不能直接用开挖量**，坑里还有第二项：`_level` 把坑那一段垫到左沿高度上
## （外加火山口的 `drop` 倾斜）。世界高度是
##
##     height_at(x) = base(x) + carve_in_chunk + (base(x0) + drop·t − base(x)) · w
##
## 坑那一段 `w == 1`（[method HillTerrain._level_weight] 的中间分支），也就是：
##
##     height_at(x) = base(x0) + drop·t + carve_in_chunk(x)
##
## ——**自然地表高度 `base(x)` 整个抵消掉了**，所以这个剖面不需要噪声、不需要种子，
## 静态就能算准。而坑沿 `rim_y = base(x0) + carve_in_chunk(x0)`，两项一减就得到
## 下面的式子。
func _depths(kind: String) -> PackedFloat32Array:
	var layout := Maps.feature_layout(kind)
	var x0 := float(layout["inset"])
	var x1 := x0 + float(layout["width"])
	# 坑沿的参考高度：和 HillTerrain.skyline_at 一致（火山口的助跑坡是往上抬的，
	# `min(0, carve)` 取的就是那个抬高量）。死亡区上沿也是从这个高度往下算的
	# —— `rim_y` 由 `_spawn_feature` 传 `skyline_at(rect.position.x)` 而来。
	var rim := minf(HillTerrain._carve_in_chunk(kind, x0), 0.0)
	var drop := float(layout.get("drop", 0.0))
	# 从半个步长开始扫、到右沿前半个步长结束：正落在两沿上的采样点是 0 开挖量
	# （`_basin` 在 x<=x0 和 x>=x1 都返回 0），留着会让「口宽」多算 2 像素。
	var out := PackedFloat32Array()
	var lx := x0 + SCAN_STEP * 0.5
	while lx < x1:
		var t := clampf((lx - x0) / float(layout["width"]), 0.0, 1.0)
		out.append(HillTerrain._carve_in_chunk(kind, lx) - rim + drop * t)
		lx += SCAN_STEP
	return out


## 挖到「相对坑沿往下 d」时，坑口还有多宽。坑口 = 开挖量 ≥ d 的那一整段。
func _mouth(depths: PackedFloat32Array, d: float) -> float:
	var first := -1
	var last := -1
	for i in depths.size():
		if depths[i] >= d:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return 0.0
	return float(last - first + 1) * SCAN_STEP


## 车壳架住的那个深度：从坑沿往下第一个「坑口窄到装不下车壳」的深度。
## 返回 INF 表示一路到坑底都比车壳宽（掉到底，不会卡在半路）。
##
## 扫到**最深处**为止：剖面是个碗（两端 0、中间最深），所以不能拿数组末项当上界
## —— 末项是右沿，约等于 0。
func _trap_depth(depths: PackedFloat32Array, chassis_len: float) -> float:
	var deepest := 0.0
	for v in depths:
		deepest = maxf(deepest, v)
	var d := 0.0
	while d <= deepest:
		if _mouth(depths, d) <= chassis_len:
			return d
		d += 1.0
	return INF


## 每种坑的死亡线上沿有多深（相对坑沿）。
func _kill_depth(kind: String) -> float:
	return float(Maps.feature_layout(kind)["depth"]) * float(KILL_FRAC[kind]["frac"])


## 车 × 坑 表。**这是「写参数之前先看一眼」的表，不是判据。**
##
## 判据在实测那边：`tests/pit_probe` 把车丢在坑正上方，量的是车最后停在哪。
## 原因见下面打印的那段话 —— 这张表假设车**水平**卡住，而真车是车头下扎着进去的，
## 斜着的车壳能钻得更深，所以表里的「架住点」是个**偏浅**的估计。
func _pit_matrix() -> void:
	var depths := {}
	for kind in PITS:
		depths[kind] = _depths(kind)

	# 表头：每个坑的死亡线上沿有多深、那里口有多宽。
	var head := "  %-8s" % "车\\坑"
	for kind in PITS:
		head += "%22s" % kind
	print(head)
	var sub := "  %-8s" % ""
	for kind in PITS:
		sub += "%22s" % ("死亡线-%.0f 口宽%.0f" % [_kill_depth(kind), _mouth(depths[kind], _kill_depth(kind))])
	print(sub)

	var warnings := []
	for id in Vehicles.available():
		var s := Vehicles.stats(id)
		if s.is_empty():
			continue
		var name: String = Vehicles.get_vehicle(id)["zh"]
		var row := "  %-8s" % name
		for kind in PITS:
			var d_kill := _kill_depth(kind)
			var entrance := _mouth(depths[kind], 0.0)
			var trap := _trap_depth(depths[kind], s["chassis_len"])
			var cell := ""
			if entrance <= s["chassis_len"]:
				# 车壳比坑口还宽：进都进不去，会横在坑沿上磨。
				cell = "进不去 ★"
				_failures += 1
				print("  FAIL %s 在 %s 进不去：坑口才 %.0f，车壳 %.0f —— 会横在坑沿上" % [
					name, kind, entrance, s["chassis_len"]])
			elif trap == INF:
				cell = "掉到底 ✓"
			elif trap >= d_kill:
				cell = "架-%.0f ✓" % trap
			else:
				cell = "架-%.0f ★" % trap
				warnings.append("  WARN %s 在 %s 会架在 -%.0f 处，而死亡线在 -%.0f：静态算下来吊在死亡区**上面**（车壳 %.0f）" % [
					name, kind, trap, d_kill, s["chassis_len"]])
			row += "%22s" % cell
		print(row)

	print("  表里每个格子是「车壳架住的那个深度」：从坑沿往下扫，第一个坑口窄到装不下")
	print("  车壳的深度。**架住点在死亡线以下（✓）** = 车吊在死亡区里，落得下死；")
	print("  **在死亡线以上（★）** = 吊在死亡区上面，既死不了也出不来，只能烧油。")
	for kind in PITS:
		print("  %-8s 死亡线比例 %.2f 来自 %s" % [kind, KILL_FRAC[kind]["frac"], KILL_FRAC[kind]["who"]])
	for w in warnings:
		print(w)
	if not warnings.is_empty():
		print("  注：★ 是**静态**结论，按车壳水平卡住算的。真车是斜着扎进去的，")
		print("      斜车壳能钻得更深，所以这里可能过于悲观 —— 实测见 tests/pit_probe。")

	# 火山口的比例是具名常量，顺手断言一次：改了 LAVA_LEVEL 就要改 KILL_FRAC。
	var lava: float = _const_of(CRATER_SCRIPT_PATH, "LAVA_LEVEL")
	_check("火山口的死亡线比例 == crater.gd 的 LAVA_LEVEL", KILL_FRAC[Maps.FEATURE_CRATER]["frac"], lava)


## 车壳长度上限，以及两条**跨车**的不变量。
##
## 上限单独打出来，因为它是「换个车壳形状」时唯一需要先看的数：坑口最窄的地方决定
## 了车壳最多能多长，超了就会架在坑上（上面那张表）。
##
## 但**它不当判据用**（坑还在改，见上面 ★ 那段注）。真正当判据的是这两条：
##
##  · 新车壳不许比越野车更长。越野车是整套标定的基准 —— 地图难度、坑的尺寸、
##    README 里的实测数字全是照着它调的，新车比它长就等于在动基准。
##  · 整车不许比吊桥的链子重，否则车一上去就把链子拽成 V 字（rope_bridge.gd
##    的 PLANK_MASS 注释）。
func _pit_ceiling() -> void:
	print("=== 车壳长度上限 ===")
	var ceiling := INF
	var who := ""
	var depths := {}
	for kind in PITS:
		depths[kind] = _depths(kind)
		var w := _mouth(depths[kind], _kill_depth(kind))
		print("  %-8s 死亡线上沿处坑口 %6.1f px" % [kind, w])
		if w < ceiling:
			ceiling = w
			who = kind
	print("  → 车壳底面短于 %.1f px 就能掉进坑底（%s 最紧），长于它就会架住" % [ceiling, who])

	var base := Vehicles.stats(Vehicles.DEFAULT)
	var base_len: float = base["chassis_len"]
	var base_name: String = Vehicles.get_vehicle(Vehicles.DEFAULT)["zh"]
	for id in Vehicles.available():
		var s := Vehicles.stats(id)
		if s.is_empty():
			continue
		var name: String = Vehicles.get_vehicle(id)["zh"]
		# 超过坑口上限**只记一笔，不当判据** —— 这是上面那段注释说的第二条。
		# 基准车自己早就超了（168 > 135），而实测（tests/pit_probe）它照样掉到坑底
		# 烧死：这张表是按车壳**水平**卡住算的，真车是斜着扎进去的。所以「超上限」
		# 不是某一辆车引入的缺陷，判它就等于判「谁是基准车」，而不是判这辆车好不好。
		var note := ""
		if s["chassis_len"] >= ceiling:
			note = "  ← 超过坑口上限 %.0f，静态上会架住" % ceiling
			if id == Vehicles.DEFAULT:
				note += "（基准车自己的老问题，不是新车引入的）"
		if id != Vehicles.DEFAULT and s["chassis_len"] > base_len:
			_failures += 1
			print("  FAIL %s 车壳 %.0f px 比 %s（%.0f px）还长：会架在坑上，而基准车不会" % [
				name, s["chassis_len"], base_name, base_len])
		else:
			print("  OK   %s 车壳 %.0f px，比基准短 %.0f，距上限 %.0f%s" % [
				name, s["chassis_len"], base_len - s["chassis_len"],
				ceiling - s["chassis_len"], note])

	# 吊桥那条不变量：桥板总重要比整车重。
	var planks: float = _const_of(BRIDGE_SCRIPT_PATH, "PLANKS")
	var plank_mass: float = _const_of(BRIDGE_SCRIPT_PATH, "PLANK_MASS")
	var chain := planks * plank_mass
	print("  吊桥：%.0f 块 × %.0f = 链子总重 %.0f" % [planks, plank_mass, chain])
	for id in Vehicles.available():
		var s := Vehicles.stats(id)
		if s.is_empty():
			continue
		var name: String = Vehicles.get_vehicle(id)["zh"]
		if s["mass"] > chain:
			_failures += 1
			print("  FAIL %s 整车 %.0f 比链子还重（%.0f），桥会被压成 V 字" % [name, s["mass"], chain])
		else:
			print("  OK   %s 整车 %.0f，链子/车 = %.2f" % [name, s["mass"], chain / s["mass"]])


## 读别人脚本里的一个具名常量。
func _const_of(path: String, key: String) -> Variant:
	var script := load(path) as GDScript
	var map := script.get_script_constant_map()
	if not map.has(key):
		_failures += 1
		print("  FAIL %s 里没有常量 %s" % [path, key])
		return 0.0
	return map[key]


func _check(label: String, got: Variant, want: Variant) -> void:
	# 必须显式写 bool：两个 Variant 比较的结果推断不出类型，:= 会解析报错
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])
