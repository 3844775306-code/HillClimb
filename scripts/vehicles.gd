extends RefCounted
class_name Vehicles
## 可选车辆的中央定义表：id、文案、场景路径；外加一组「从场景里读出这辆车的事实」
## 的工具。
##
## 和 [Maps] / [Upgrades] 一个套路 —— 存档只存「选了哪辆车」这一个字符串，
## 改平衡不用碰存档代码。
##
## ## 物理数值为什么一个都不在这张表里
##
## 质量、碰撞形状、马达和燃油那几个 `@export` 全在各车的 `.tscn` 里，这里只**读**
## （见 [method stats]）。两条理由：
##
## 1. 编辑器里选中车节点就能实时调，和调默认车是同一套手感；
## 2. 表里再抄一份数字就一定会漂。[Upgrades] 的 `base()` 注释里记着这个教训 ——
##    当年抄了一份常量，结果改了车忘了改表，车库页脚显示「推重比 1.005 安全」
##    而实车已经是 2.68，只有跑测试才会发现。
##
## 所以选车界面上那行数字、测试里的断言、车库页脚的推重比，全都是现读现算的，
## 和真车永远一致。
##
## ## 这个类不许引用 [HillCar]
##
## 依赖链是 `car.gd → Upgrades → Vehicles`。一旦这里出现 `HillCar` 这个名字（哪怕
## 只是类型标注），编译期就成环 —— 和 upgrades.gd 里那条 `load()` 而不是 `preload()`
## 的注释是同一件事。所以下面凡是涉及车的地方一律 `Node2D` 或无类型。

const JEEP := "jeep"
const MOTO := "moto"
const RACER := "racer"
const BUS := "bus"
const MONO := "mono"
const MONSTER := "monster"
const TANK := "tank"
const ROVER := "rover"

## 展示顺序 = 选车界面的卡片顺序，默认车排第一（光标默认停在它上面）。
##
## **新加的车一律追加在后面**，不要插队：老玩家的光标停在存档里那辆车上，
## 插队会让所有车的相对位置一起挪。
const IDS: Array[String] = [JEEP, MOTO, RACER, BUS, MONO, MONSTER, TANK, ROVER]

## 开局白送几辆 —— 就是 [constant IDS] 的**前两辆**：越野车 / 摩托。
##
## 和 [constant Maps.FREE_COUNT] 一个写法、一个理由（用「前几个」而不是名单，
## 免得名单和 [constant IDS] 两处漂）。
const FREE_COUNT := 2
## 其余每辆的解锁价。**一律这个数**，想按车分档就在 [member VEHICLES] 里给每辆加
## 一个 `price` 键，再由 [method price_of] 优先读它。
const UNLOCK_PRICE := 100000

## 轮子刚体的分组标记。
##
## 定义在**这里**而不是 [HillCar]：依赖方向是 car.gd → Upgrades → Vehicles，
## 这个类是依赖链的根（见类注释），所以常量放这里只有一个定义、又不会成环。
## [HillCar] 那边引的就是这一个。
const WHEEL_GROUP := "wheel"

## 存档里没有 `[vehicle]` 段、或者读出来是个没见过的 id 时回落到它。
## **必须是 [constant IDS] 的第一个**，否则老玩家开机会发现自己的车换了。
const DEFAULT := JEEP

## 车重、离地间隙这些不在这里 —— 全部从场景读。
## `zh_role` 是卡片上那行定位标签，和地图界面的 `_stats_line` 一个用法。
##
## **`zh_note` / `en_note` 要短。** 卡宽 276.5，去掉两侧留白只剩 236.5 —— 15 号字下
## 中文约 15 个字、英文约 33 个字符就到头了，再长 `fit_size` 会缩号，缩到 12 号还没完
## 就画到隔壁卡上。tests/vehicleselect 的文案一节会现量这两个数，改文案之后跑一下。
const VEHICLES := {
	JEEP: {
		"zh": "越野车", "en": "JEEP",
		"zh_role": "均衡", "en_role": "BALANCED",
		"zh_note": "什么都行一点，没有一样最强", "en_note": "the all-rounder",
		"scene": "res://scenes/car.tscn",
	},
	MOTO: {
		"zh": "摩托", "en": "MOTORCYCLE",
		"zh_role": "灵巧", "en_role": "NIMBLE",
		"zh_note": "最轻最灵活，也最容易翻", "en_note": "lightest, flippiest, tiny tank",
		"scene": "res://scenes/vehicles/moto.tscn",
	},
	RACER: {
		"zh": "赛车", "en": "RACER",
		"zh_role": "速度", "en_role": "SPEED",
		"zh_note": "起步快、极速高，不爱翻", "en_note": "quickest and fastest",
		"scene": "res://scenes/vehicles/racer.tscn",
	},
	BUS: {
		"zh": "巴士", "en": "BUS",
		"zh_role": "续航", "en_role": "RANGE",
		"zh_note": "最重、爬坡最差，油箱最大", "en_note": "heaviest, but a huge tank",
		"scene": "res://scenes/vehicles/bus.tscn",
	},
	MONO: {
		"zh": "独轮车", "en": "UNICYCLE",
		"zh_role": "平衡", "en_role": "BALANCE",
		"zh_note": "陀螺仪扶着，只有一个轮子", "en_note": "one wheel, gyro-assisted",
		"scene": "res://scenes/vehicles/mono.tscn",
	},
	MONSTER: {
		"zh": "怪兽卡车", "en": "MONSTER TRUCK",
		"zh_role": "越障", "en_role": "OFF-ROAD",
		"zh_note": "轮胎最大，碾过去而不是被顶起来", "en_note": "huge tyres, rolls over anything",
		"scene": "res://scenes/vehicles/monster.tscn",
	},
	TANK: {
		"zh": "坦克", "en": "TANK",
		"zh_role": "抓地", "en_role": "GRIP",
		"zh_note": "履带抓地极强，雪地照样稳，但很慢", "en_note": "tracks grip hard, even on snow",
		"scene": "res://scenes/vehicles/tank.tscn",
	},
	ROVER: {
		"zh": "登月车", "en": "LUNAR ROVER",
		"zh_role": "飞行", "en_role": "FLIGHT",
		"zh_note": "同时按前进后退就起飞，油耗三倍", "en_note": "both pedals to fly, 3x fuel",
		"scene": "res://scenes/vehicles/rover.tscn",
	},
}

## 重力。和 [Upgrades.GRAVITY] 是同一个数，这里留一份是为了让 stats() 不依赖 Upgrades
## （依赖方向是 Upgrades → Vehicles，反过来引用就成环了）。
const GRAVITY := 980.0

static var _scenes := {}
static var _stats := {}
static var _silhouettes := {}


static func has_vehicle(id: String) -> bool:
	return VEHICLES.has(id)


## 解锁这辆车要花多少金币；**0 表示不用花钱**（免费的，或者这个 id 不存在）。
##
## 和 [method Maps.price_of] 逐条同规矩，理由见那边。
static func price_of(id: String) -> int:
	var i := IDS.find(id)
	if i < 0 or i < FREE_COUNT:
		return 0
	return UNLOCK_PRICE


## 这辆车是不是白送的（在 [constant IDS] 里，而且排在前 [constant FREE_COUNT] 个）。
##
## **不认识的 id 一律不算免费**，理由和 [method Maps.is_free] 那条一样：
## [method SaveData.vehicle_unlocked] 拿它当权限判断用，兜底必须是否决。
static func is_free(id: String) -> bool:
	var i := IDS.find(id)
	return i >= 0 and i < FREE_COUNT


static func get_vehicle(id: String) -> Dictionary:
	if VEHICLES.has(id):
		return VEHICLES[id]
	return VEHICLES[DEFAULT]


## 这辆车的场景路径。不认识的 id 给默认车的。
static func scene_path(id: String) -> String:
	return str(get_vehicle(id)["scene"])


## 加载场景。**读不到返回 null**（新车还没做出来时就是这个状态，见 [method available]）。
static func scene(id: String) -> PackedScene:
	var path := scene_path(id)
	if _scenes.has(path):
		return _scenes[path]
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	_scenes[path] = packed
	return packed


## 实例化一辆车（**不进场景树**，所以 `_ready()` 不会跑，拿到的是原厂值）。
## 调用方负责 free()。读不到就退回默认车，再读不到返回 null。
static func instantiate(id: String) -> Node2D:
	var packed := scene(id)
	if packed == null and id != DEFAULT:
		packed = scene(DEFAULT)
	if packed == null:
		return null
	return packed.instantiate() as Node2D


## 真的能选的车（场景存在的那些）。新车还只有 .tscn 没做的阶段，界面和测试都用它，
## 免得选到一台加载不出来的车。
static func available() -> Array[String]:
	var out: Array[String] = []
	for id in IDS:
		if scene(id) != null:
			out.append(id)
	return out


## 一辆车上所有的轮子，**按场景里的次序（后 → 前）**。两轮车是两个，独轮车一个。
##
## **全项目只有这一份判据**：直接子节点 + 带 [constant WHEEL_GROUP] 标记的
## [RigidBody2D]。[HillCar] 的 `wheels`、选车卡片画的轮子、坦克画履带用的轮子，
## 三处都调这一个函数 —— 各写一份的话，改了判据就会有地方静默地少数一个轮子。
##
## 参数写成 [Node2D] 而不是 [HillCar]，是因为依赖方向（见类注释）：在那个类型上
## 取一次属性就成环。这也正好让它能用在没进树、甚至不是车的节点上。
static func wheels_of(car: Node2D) -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for child in car.get_children():
		var body := child as RigidBody2D
		if body != null and body.is_in_group(WHEEL_GROUP):
			out.append(body)
	return out


## 一辆车的「事实」：质量、几何、马达、油箱，以及由它们推出来的几个数。
##
## 全部现读现算，**这里不写死任何一个数字**。第一次调用时从场景读一次并缓存
## （和 [Upgrades.base] 一样的做法：读的是没进场景树的实例，拿到的是没被改装倍率
## 乘过的原厂值）。
##
## 键：mass / weight / radius / wheel_y / wheelbase / chassis_len / bottom_y /
## clearance / wheel_speed / motor_strength / max_torque / fuel_max / inertia_scale /
## top_speed / thrust / ratio / launch_ratio / torque_demand / torque_clamped
static func stats(id: String) -> Dictionary:
	if _stats.has(id):
		return _stats[id]
	var car := instantiate(id)
	if car == null:
		return {}
	var chassis := car.get_node("Chassis") as RigidBody2D
	var wheels := wheels_of(car)
	if wheels.is_empty():
		# 轮子没打 [constant WHEEL_GROUP] 标记就是这个状态。给个空表让调用方走
		# 「算不出来」那条路，而不是拿一个假的数继续往下算 —— 那种错是静默的。
		push_error("%s 一个轮子都没找到：轮子刚体缺 `wheel` 分组标记？" % id)
		car.free()
		return {}
	var rear: RigidBody2D = wheels[0]
	var front: RigidBody2D = wheels[-1]
	var body := car.get_node("Chassis/Body") as CollisionShape2D
	var shape := body.shape as ConvexPolygonShape2D
	var radius: float = (rear.get_node("Shape") as CollisionShape2D).shape.radius

	# `car` 是 Node2D（不能在这里写出车的类型 —— car.gd → Upgrades → Vehicles 会成环，
	# 和 upgrades.gd 里那条 load/preload 的注释是同一类问题），所以下面每个数都要
	# **显式写类型**：在 Node2D 上取 max_wheel_speed 拿到的是 Variant，`:=` 推不出来。
	var wheel_speed: float = car.max_wheel_speed
	var motor: float = car.motor_strength
	var max_torque: float = car.max_torque

	var mass := chassis.mass
	for wheel in wheels:
		mass += wheel.mass
	var weight := mass * GRAVITY
	var bottom := _bottom_edge(shape.points)
	# 静止时单轮推力 = 目标转速 × 力矩系数 ÷ 轮半径，**几个轮子就乘几**。
	# 这条式子是 README「调爬坡能力时看推力自重比」那一节的实现。
	#
	# **轮数是变量，不能写死 2。** 独轮车只有一个轮子出力，写死 2 会让选车卡片和
	# 车库页脚一起虚报一倍的推重比 —— 而推重比正是这个游戏里最要命的那个数。
	var count := float(wheels.size())
	var thrust := count * wheel_speed * motor / radius
	# 静止时（轮速 0）需要的扭矩 = 转速 × 力矩系数。**超过 max_torque 就被限幅**，
	# 起步推力达不到上面那个设计值 —— 这是这个项目里一条很隐蔽的常量，
	# 实测过它已经是常驻限幅（见 README 和 tests/upgrade_calib 的 A 段）。
	var demand := wheel_speed * motor
	var clamped := minf(demand, max_torque)
	var fuel_max: float = car.fuel_max
	var idle: float = car.fuel_idle_drain
	var burn: float = car.fuel_throttle_drain
	var out := {
		"id": id,
		"mass": mass,
		"weight": weight,
		"radius": radius,
		"wheel_y": rear.position.y,
		"wheelbase": absf(front.position.x - rear.position.x),
		# 车壳底面：车架两个最靠下的顶点连成的边。**它就是「会不会横架在坑口上」
		# 的那个长度**，车壳两端还有没有轮子都改变不了这一点。
		"chassis_len": (bottom[1] - bottom[0]).length(),
		"bottom_y": maxf(bottom[0].y, bottom[1].y),
		"clearance": rear.position.y + radius - maxf(bottom[0].y, bottom[1].y),
		"wheels": wheels.size(),
		"wheel_speed": wheel_speed,
		"motor_strength": motor,
		"max_torque": max_torque,
		"fuel_max": fuel_max,
		"fuel_seconds": fuel_max / (idle + burn),
		"inertia_scale": car.inertia_scale,
		"top_speed": wheel_speed * radius,
		"thrust": thrust,
		"ratio": thrust / weight,
		"launch_ratio": (count * clamped / radius) / weight,
		"torque_demand": demand,
		"torque_clamped": demand > max_torque,
	}
	car.free()
	_stats[id] = out
	return out


## 车架最靠下的那条边。凸多边形上取 y 最大的两个顶点即可 —— 车架都是下宽上窄的
## 形状（车顶比车底窄），所以这两个顶点一定相邻。要是哪天有人画了个底部凹陷的车架，
## 这个函数会给出偏长的值（偏保守，宁可让测试喊一声）。
static func _bottom_edge(points: PackedVector2Array) -> Array:
	var best := [Vector2.ZERO, Vector2.ZERO]
	var ys := [-INF, -INF]
	for p in points:
		if p.y > ys[0]:
			ys[1] = ys[0]; best[1] = best[0]
			ys[0] = p.y; best[0] = p
		elif p.y > ys[1]:
			ys[1] = p.y; best[1] = p
	return best


## 车的外形：车架多边形 + 两个轮子的圆心和半径，外加整体包围盒。
##
## 给选车界面的卡片画画用。和 [method stats] 一样是**从场景里读出来的**，不是另画
## 一份示意图：改了车的形状或轮子半径，卡片立刻跟着变 —— 不会出现「卡片上是细长的、
## 开出来是圆胖的」。
##
## 返回的是**车体局部坐标**（就是场景里那套坐标），缩放由卡片自己决定。
## 键：body（PackedVector2Array 碰撞多边形）/ wheels（[{pos, radius}]）/
##     layers（车壳上的 Polygon2D，按画序，顶点已烘进节点变换）/ `box`（Rect2 包围盒）。
##
## **`box` 圈的是「会画出来的全部东西」**：碰撞车架 + 两个轮子 + 所有车壳图层。
## 卡片拿它算缩放和居中，少圈一层，预览就会比预留的框高出一截。
static func silhouette(id: String) -> Dictionary:
	if _silhouettes.has(id):
		return _silhouettes[id]
	var car := instantiate(id)
	if car == null:
		return {}
	var chassis := car.get_node("Chassis") as RigidBody2D
	var body := car.get_node("Chassis/Body") as CollisionShape2D
	var points := (body.shape as ConvexPolygonShape2D).points
	var first: Vector2 = points[0]
	var box := Rect2(first, Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	# 车壳上的 Polygon2D 按节点次序取出来 = 这辆车自己的画法（车身、驾驶室、窗…）。
	# 卡片照着这个画，所以**预览就是实车的缩小版**，不是另画一张示意图：
	# 换了配色或者改了形状，卡片立刻跟着变。
	var layers := []
	for child in chassis.get_children():
		if child is Polygon2D:
			var poly := child as Polygon2D
			# 顶点**烘进节点变换**再交出去。卡片是拿这份顶点直接画的
			# （`draw_colored_polygon` 不吃节点变换），烘焙之后「画出来的形状」和
			# 「包围盒里的形状」永远是同一个 —— 哪天有人给车壳节点加个 offset，
			# 预览会跟着挪，而不是画在原地、盒子却按新位置算。
			var pts := PackedVector2Array()
			for p in poly.polygon:
				pts.append(poly.transform * p)
			layers.append({"polygon": pts, "color": poly.color})
			# 包围盒必须**连车壳一起圈**。只算车架 + 轮子的话，驾驶室、车顶、
			# 尾翼这些长在车架上方的装饰就跑到盒子外面去了 —— 而缩放和居中都是
			# 照盒子算的，结果是预览画出来比预留的框还高，顶出卡片。
			# 这里漏过一次，是 tests/vehicleselect 的「包围盒圈住了车架和两个轮子」
			# 抓出来的（越野车、摩托、赛车三辆都中招，巴士因为车壳是方的没露馅）。
			for p in pts:
				box = box.expand(p)
	var wheels := []
	for wheel in wheels_of(car):
		var radius: float = (wheel.get_node("Shape") as CollisionShape2D).shape.radius
		var centre := wheel.position
		wheels.append({"pos": centre, "radius": radius})
		box = box.expand(centre + Vector2(-radius, -radius))
		box = box.expand(centre + Vector2(radius, radius))
	var out := {"body": points, "wheels": wheels, "layers": layers, "box": box}
	_silhouettes[id] = out
	car.free()
	return out
