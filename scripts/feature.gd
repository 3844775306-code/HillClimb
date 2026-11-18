extends Node2D
class_name HillFeature
## 特殊地形（吊桥 / 沙尘暴 / 冰湖 / 火山口）的共同底座。
##
## 只负责三件事：接住地形给的摆位信息、「从一个碰撞体找到那辆车」，以及
## 「问地形某处的地表有多高」。具体长什么样交给子类的 [method _build]。
##
## ## 坐标
##
## 特殊地形节点挂在区块节点下，而区块节点在原点，所以**本节点的局部坐标就是世界
## 坐标**。挖地形的 [method HillTerrain._carve] 用的是同一套世界坐标，两边不用做
## 任何换算 —— 坑挖在哪，冰面就铺在哪。
##
## ## 尺寸的唯一来源
##
## [member span] 是地形从 [constant Maps.FEATURE_LAYOUT] 算出来再传进来的，所以
## 尺寸不要在子类里另写一份常量：改了布局表，挖出来的坑和摆上去的东西必须一起动。

## 本段特殊地形的水平范围。`position.x` 是左沿，`size.x` 是宽度，`size.y` 是挖多深。
var span := Rect2()
## 坑沿的世界坐标 y（区块起点处的**未开挖**地表高度）。
var rim_y := 0.0

## 死亡区场景（[HillHazard]）。四种地形里有三种要用，所以放在底座上，
## 由 scenes/main.tscn 统一接线。沙尘暴不用，空着就行。
@export var hazard_scene: PackedScene


## 由 [method HillTerrain._spawn_feature] 调用。**必须在进树之后**调 ——
## 子类的 @onready 变量要等节点进树才会填上。
func setup(rect: Rect2, rim: float) -> void:
	span = rect
	rim_y = rim
	_build()


## 子类在这里摆自己的东西。
func _build() -> void:
	pass


## 从碰到的刚体找到车。
##
## 车的车壳和两个轮子是三个同级刚体、都是 Car 节点的孩子，所以父节点就是车。
## 不这么认的话就得给每个刚体挂元数据，或者让特殊地形反向引用关卡脚本。
static func car_of(body: Node) -> HillCar:
	if body == null:
		return null
	return body.get_parent() as HillCar


## 世界坐标 `x` 处的地表高度。
##
## 「摆在地上」的地形（石子、树）必须拿这个数，**不能拿 [member rim_y]**：
## `rim_y` 是**本段左沿**的地表高度，而一段有几百像素宽、地表一路起伏
## （山地起伏倍率 1.35、森林 0.95，一段 600 像素里能差出一百多像素），
## 按左沿的高度摆会让石子浮在半空或者整棵埋进土里。
##
## 只能往树上问：高度由噪声、地图、种子、开挖共同决定，特殊地形这边一份都算不出来。
## 找不到地形（测试里把一个地形节点单独当孤儿跑）就退回 `rim_y` —— 至少不会摆到
## 几百像素外去，而且退回之后的行为是「当作平地」，测试里一眼能看出来。
func ground_at(x: float) -> float:
	var terrain := terrain_node()
	if terrain != null and terrain.has_method("height_at"):
		return float(terrain.call("height_at", x))
	return rim_y


## 本节点所属的地形（本节点 → 区块 → 地形）。找不到就返回 null。
##
## 特殊地形里除了「地表多高」还有别的问题要问地形（比如云朵要问「缝在哪」，
## 那由世界种子决定，这边一份都算不出来），拿地形这个对象本身就抽出来了。
func terrain_node() -> Node:
	var chunk := get_parent()
	return chunk.get_parent() if chunk != null else null


## 摆一个死亡区。`rect` 用世界坐标。
##
## 返回摆好的那个区，调用方可以接着给它改名字（隧道里一排钟乳石各带一块，
## 不命名的话全叫 `HazardZone`）。不需要名字的调用方忽略返回值就行。
func add_hazard(rect: Rect2, reason: String, color: Color) -> HillHazard:
	if hazard_scene == null:
		return null
	var zone: Node2D = hazard_scene.instantiate()
	add_child(zone)
	zone.call("setup", rect, reason, color)
	return zone as HillHazard


## 坑底那块夺命区域：只盖住坑的**下半截**。
##
## 从坑沿往下 `frac × 深度` 才开始算，为的是「从上面飞过去」不算掉进去 ——
## 冰面架在坑口、桥面会下垂、车飞过火山口时离坑底还远，这些时候都不该判死。
##
## `frac` 由各种地形自己给：冰湖 0.55 就够（水就在那儿，车轮一沾水就算掉进去），
## 吊桥要给到 0.75 —— 绳子桥被车压着会大幅下垂，取 0.55 的话「还骑在桥上、
## 只是被压得比较低」也会被判成掉下去。
##
## 但也不能给到接近 1：坑底必须落在区域内，否则车掉到坑底反而不死。
## 坑底在 `rim_y + depth`，区域下沿是 `rim_y + depth*frac + depth*(1-frac) + 80`
## —— 永远比坑底低 80 像素，所以无论 `frac` 取多少，真掉下去都逃不掉。
func pit_hazard_rect(depth: float, frac: float = 0.55) -> Rect2:
	return Rect2(
		span.position.x,
		rim_y + depth * frac,
		span.size.x,
		depth * (1.0 - frac) + 80.0,
	)
