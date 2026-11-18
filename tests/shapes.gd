extends Node
## 形状地图（屋顶 / 彩虹）和黑夜挡布：用户那三条地图需求的实测。
##
## 需求原话：
##
##   1. 屋顶模式：间隔两侧的屋顶**右侧比左侧略低**，且需要一些**倾斜屋顶**
##   2. 彩虹模式：地形为**多个拱形交叉** + 白云
##   3. 黑夜模式：**只能看见汽车周围的地形**
##
## 第二轮的彩虹需求（4～8）和第 2 条一起**被第三轮整个取代了**，见下。
##
## ## 彩虹：从「拱」换成「散在空中的平台场」
##
## 需求原话（第三轮，现行）：「整个地图由散落在空中的一些随机圆弧彩虹和椭圆云朵
## 构成，任意彩虹、云朵不相连，且彩虹圆弧长度、朝向各异，彩虹和云朵的覆盖范围
## 包括上下 200 米使得车难以掉下去」。
##
## 这一版把「地形」整个拿掉了：**这张图没有地表**，`height_at` 答的是「x 上面的
## 天花板」，区块一块地都不建（0 号区块那块出生台除外）。平台是独立的刚体
## （[HillPlatform]），布局是 `Maps` 里一片全局格网
## （[constant Maps.CELL_W] × [constant Maps.ROW_H]），一格最多一块，
## **每块的外接框严格缩在自己的格子里** —— 所以「任意两块不相连」是构造出来的。
##
## 老那一套（拱 + 缝 + 云朵铺在缝上）在这张图上已经全没了：`Maps.has_gaps` 对
## 彩虹返回 `false`，`Maps.arches_at` / `cloud_pad_at` / `HillTerrain.shape_rise`
## 也都删了。上一轮那两条逮住的 bug（拱越过区块两端、一条缝摆两朵云）是那一代的
## 事，回归断言跟着那一代的代码一起走了 —— 替代它们的是
## [_section_arches_shape] 里「真实碰撞体两两对一遍」那条，它盖的是同一类错误
## （两块东西叠在一起），而且是对**建出来的节点**量的。
##
## 第三轮又追加了一条：**「目前彩虹片段太短了」** —— 弧长下限因此从实际的
## 三十几像素提到 [constant Maps.ARC_LEN_LO]，并且格子跟着放大到正方形
## （见那里的注释：格子只有 250 高的时候，随机朝向会把长弧系统性地卡掉）。
##
## 第四轮是**两条一起到的**：**「彩虹片段再加长 3 倍」**和**「云朵支撑不了车」**
## —— 两条都指向「平台要更大更实在」，而且**是同一类毛病**：东西比车小。
## 于是格子从 400 涨到 800（弧长才能涨到 600～1100），云朵的**下限**从 110 涨到 240
## （110 比车的轮距还窄，两个轮子架不到一块板上 —— 这就是「支撑不了车」，
## 和「彩虹片段太短了」一模一样，只是尺子从弧长换成板宽）。
##
## 断言跟着改成：最短的弧比轴距长、中位数至少**四倍**轴距、
## 最长的那一批超过 950（旧上限 400 的三倍是 1200，格子给到的天花板在 1070 上下）、
## 最短的云比轮距宽、中位云至少两倍轮距。
##
## ## 屋顶：一栋栋房子，屋面是平的，高低靠钢梯和天际线
##
## 需求原话（第二轮）：**屋顶下面的地块是房子**（要画出窗户和楼层），**屋顶改为用
## 瓦片铺、且仅为水平直线但高低错落**，**同一个房子上高度不平的屋顶用钢制梯子连接**，
## **有的屋上添加烟囱，烟囱的烟气可以把车向上吹**。
##
## 于是老的那套「六种形状（矩形 / 三角 / 半圆 / 梯形 / 两种斜坡）」整块换掉：
## **屋面一律是水平的**（[_section_roof_profile] 里量「平段上地表起伏恒为 0」），
## 高低错落分成两层：
##
##   · **房子内部** —— 一栋房子几段不同高度的屋面，钢梯连起来。钢梯按 smoothstep
##     取形，`1.5 / LADDER_RUN ≈ 55°`，就是用户选的那个坡度；两头斜率为 0，
##     上梯子和下梯子都不留折角（直线梯子的顶端折角会把车弹起来，老的三角形
##     屋顶顶点就是这么把车抛到空中 355 像素的）。
##   · **房子之间** —— 一条长波**天际线**（[constant HillTerrain.SKY_AMPLITUDE]），
##     一栋一个高度。
##
## ## 落差是**构造出来的**，不是攒出来的
##
## 每条缝的落差 [constant Maps.DROP_LO]～[constant Maps.DROP_HI] 是掷骰子来的，
## 而下一栋的左沿高度写成 `上一栋的右沿 + 落差`（[method HillTerrain.roof_profile]）——
## **测出来的落差永远等于掷出来的那个数**，天际线在两栋之间怎么起伏都改不动它
## （[_section_roof_drop] 就是拿这个等式逐条对的：老设计里落差会被屋顶形状的
## 端部高度吃掉一部分，那条等式得写成三项）。
##
## 落差的用法还是老样子：**右边更低**（用户要的「屋顶右侧比左侧略低」），
## 每一跳都是从高的那边往低的那边飞。
##
## ## 缝宽还是**算出来的**
##
## 平着起跳、落点低 `d` 像素时，下落预算是 `d + 21` 像素（21 是轮子半径：轮心还比
## 落点高的时候，轮子能啃着缝沿的圆角翻上去），于是 `t = √(2(d+21)/980)` 秒，
## 缝宽上限 = 起跳速度 × t。**最紧的是落差最浅的那条缝**（`d = 24` → `t = 0.303`），
## 起跳速度是实测的（[_section_roof_drive] 那张表）。**车的参数一改，这张表先变，
## 缝宽跟着重算。**
##
## 那张表现在的读数（落差 24～60、缝宽 130～150 那一档）：起跳 542～624 px/s，
## 需要 338～447，每条都过。拿最慢的 542 配最紧的 0.303 得 164 —— 这就是
## [constant Maps.GAP_MAX] 取 150 的来历（余量 9%）；而**最难的一对**
## 「最宽的缝 × 最浅的落差」需要 495，那两个极端的骰子各占 1/36、互相独立，
## 迟早会撞上一条 —— 这张表会直接把那条印成「**给不起**」。
##
## ## 这个套件逮住过几个 bug（下面各有一条回归断言）
##
##  · **「向右下」那块屋顶的开头是个 24 像素的坑。** 老 [method HillTerrain.roof_rise]
##    在 `lx <= 0` 时直接返回 0，而那一支在 `lx = 0` 处正好是它的**最高点** ——
##    那个点又是左边那条缝的落点，车落地就栽进去。（那块形状现在没了，
##    但「落点台必须是平的」这条断言留着。）
##  · **缝顶钉死在 [constant HillTerrain.GROUND_Y] 的年代**，屋顶一上天际线，
##    云朵就会陷进高的那几栋、悬在低的那几栋的半空里。现在 [method
##    HillTerrain.gap_rect] 返回的是**缝左沿真正的高度**。
##  · **彩虹的弧短得不像路。** 用户原话「目前彩虹片段太短了」：最早的
##    45～80 半径配 0.7～2.4 张角，最短的一截只有三十几像素 —— 车长 178、
##    轴距 [member _car_wheelbase]，两个轮子根本架不到弧上。现在布局掷的是
##    **弧长**（[constant Maps.ARC_LEN_LO]～HI）而不是半径，格子也改成正方形
##    （见 [constant Maps.ROW_H]），并按长度和轴距两条回归断言钉住。
##  · **彩虹的弧和云会叠在一起。** 布局要保证「任意两块不相连」，而「按图形算
##    相交」是很难验的（弧是环扇形、云是斜板）—— 现在改成**外接框缩在格子里**，
##    于是「不相交」是可以构造证明的，测试再拿**真实碰撞体的世界外接框**两两
##    对一遍，两边互相印证。见 [_section_arches_shape] 的「任意两块平台都不相连」。
##
## ## 跑车那几节用的是**真地形**，不是压平的地形
##
## 屋顶和云朵的难点就在起伏上（助跑、起跳、落地），压平了等于把要测的东西测没了。
## 代价是这几节的结论**依赖当前车辆参数**（`max_wheel_speed` / `motor_strength` /
## 车重 / 轴距）：参数是活的（用户在编辑器里实时调），所以 [_print_car_params] 把
## 量到的参数打在文件头当凭据，数字对不上时先比这一行。

const CAR := preload("res://scenes/car.tscn")
const MAIN := preload("res://scenes/main.tscn")
const PICKUP := preload("res://scripts/pickup.gd")
const HAZARD_SCENE := preload("res://scenes/hazard_zone.tscn")

const SEED := 1337
## 几何节扫几块区块。
const CHUNKS := 60
const CW := HillTerrain.CHUNK_WIDTH
const DT := 1.0 / 60.0
## 两节跑车的起点：出生直道（[constant HillTerrain.FLAT_LENGTH] = 700）上，
## 和玩家开局差不多的地方。助跑就是那条直道本身。
const START_X := 100.0
const CAR_LIFT := 39.0
const SETTLE := 12
## 真实出生点那辆车**落定**要跑多少帧。它出生时离地 80 像素（场景里那个 `340` 的
## 含义，见 [_section_arches_spawn]），落地本身只要 20 帧上下；给到 120 帧（2 秒）
## 是为了让「有没有弹起来」这件事彻底过去。
const SPAWN_LAND := 120
## 出事时留着复盘的帧数（见 [method _trace]）。900 帧 = 15 秒，一整趟都装得下。
const TRACE := 900
## 打印轨迹时的密度：前面每这么多帧一行，最后那一截一行不漏。
const TRACE_STEP := 8
const TRACE_TAIL := 24
## 钢梯中段的理论最陡坡度：`1.5 / LADDER_RUN`（smoothstep 的导数在正中间取到
## 1.5）。实测最陡处见 [_section_roof_profile]，真凭据是 [_section_roof_drive]：
## 车全油门带着这几段梯子真的开了过去。
const LADDER_SLOPE := 1.5 / Maps.LADDER_RUN
## 「卡住」的门槛：横向速度低于 [constant STALL_VX] 连续超过 [constant STALL_FRAMES]
## 帧（半秒）才算。撞钢梯脚那一帧必然跌破（实测 85 px/s），那是设计的一部分；
## 卡住就上不去梯子、过不了下一栋，是 bug。见 [_section_roof_drive] 的文件头。
const STALL_VX := 60.0
const STALL_FRAMES := 30

## 彩虹平台场：从第几列开始扫。0 号区块是出生台，占掉一列
## （[constant Maps.CELL_W] = 一整个区块宽），所以平台从第 1 列起。
##
## **列和区块的换算是 `区块 = 列 / COLS_PER_CHUNK`**（现在是 1：一列 = 一块区块），
## 下面每一节都从这一列开始数，不写第二遍。
const PLATFORM_COL0 := Maps.SHAPE_START_CELL
## 扫多少列来量分布。列数 × [constant Maps.ROW_COUNT] 就是格子总数 ——
## 40 列 × 5 行 = 200 格，填充率的标准差约 0.028，够卡住 ±5% 那条断言了。
const PLATFORM_COLS := 40
## 建多少块区块来量「真实碰撞体两两不相邻」。3 块 × 十几块平台 ≈ 四十来块平台、
## 八百多对，够用；再多只是拖着跑。
const NODE_CHUNKS := 3
## 量节点的时候探针摆在哪个区块。**这个数不是随便取的**：
## [method HillTerrain._refresh_chunks] 只建探针所在区块前后共
## `2 × HillTerrain.VIEW_RADIUS + 1` 块（半径 2 → 5 块），所以探针在区块
## `SHAPE_START_CELL + 2` 时，`SHAPE_START_CELL`～`+2` 这三块**都**在窗口里。
## 探针摆在 `+ NODE_CHUNKS`（= +3）的话回不到第一块，量到的只剩两块。
const PROBE_CHUNK := Maps.SHAPE_START_CELL + 2
## 跑车那一节开多少秒。出生台 800 像素，按 855 的末速不到 1 秒就出完了，
## 剩下的时间全在平台场上。
const DRIVE_SECONDS := 14.0
## 窗户换脸那一节连看多少拍（[constant HillRooftopArt.WINK_STEP] 一格 = 1 秒）。
##
## 120 拍 = 两分钟。一扇窗最短 12 拍换一次、最长 60 拍，所以两分钟里至少换两次脸 ——
## 「绝大多数窗都动过」这条断言才有意义（只看 10 拍的话，大半窗还没来得及动）。
const ANIM_TICKS := 120

var _failures := 0
var _assertions := 0
var _world: Node2D
var _terrain: HillTerrain
var _car: HillCar
## 车的**轴距**（前后轮中心的距离），[_print_car_params] 量出来。
## 彩虹那一节拿它当「一截弧短到什么程度就不算路了」的尺子。
var _car_wheelbase := 0.0
## 车的**轮距**（前后轮**外沿**之间的距离 = 轴距 + 两个轮子半径），
## [_print_car_params] 量出来。云朵那一节拿它当「一块板短到什么程度就托不住车」的尺子。
var _car_span := 0.0


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1：它会直接放大物理步长
	SaveData.persist = false
	SaveData.reset_progress()

	_print_car_params()

	_section_roof_profile()
	_section_roof_art()
	_section_roof_drop()
	_section_roof_seam()
	await _section_roof_drive()
	_section_arches_shape()
	await _section_arches_cloud()
	await _section_arches_drive()
	await _section_arches_fall()
	await _section_arches_spawn()
	await _section_night()

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


# ---------------------------------------------------------------- 量车

## 这一批数字量于哪个参数的车。**参数是活的**（见文件头），失败时先比这一行。
func _print_car_params() -> void:
	var car := CAR.instantiate()
	# **`@onready` 的那几个成员在这儿还是 null**：车没进树。要拿车壳和轮子得自己
	# 从节点树上取（`car.chassis` 只有进树之后才绑上）。
	var chassis := car.get_node("Chassis") as RigidBody2D
	var wheel := car.get_node("RearWheel") as RigidBody2D
	var front := car.get_node("FrontWheel") as RigidBody2D
	var shape := (wheel.get_node("Shape") as CollisionShape2D).shape as CircleShape2D
	# 轴距：彩虹那一节拿它当「一截弧短到什么程度就不算路了」的尺子
	# （见 [_section_arches_shape]）。前后轮是车场景里直接摆好的两个刚体。
	_car_wheelbase = absf(front.position.x - wheel.position.x)
	# **两个轮子的外沿跨多远** —— 云朵那一节拿它当「一块板短到什么程度就托不住车」的
	# 尺子（见 [_section_arches_cloud]）。**这才是「支不支持得住」的那把尺**：
	# 车是拿两个轮子站着的，两个轮子都落在板上才站得住，板再长也没用。
	# 只量轴距不够 —— 轮子自己有半径，外沿比轴距宽两个半径。
	_car_span = _car_wheelbase + shape.radius * 2.0
	# 车壳本身多长（不算轮子）。**只打出来给人看**，不参与断言：车壳比轮距长
	# 是正常的（前后都探出去一截），拿它当「托得住」的尺子会偏严。
	var poly := ((chassis.get_node("Body") as CollisionShape2D).shape \
			as ConvexPolygonShape2D).points
	var lo := INF
	var hi := -INF
	for p in poly:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	print("=== 当前车辆参数（两节跑车都依赖它）===")
	print("  max_wheel_speed %.1f   motor_strength %.0f   max_torque %.0f" % [
			car.max_wheel_speed, car.motor_strength, car.max_torque])
	print("  车轮半径 %.1f   轴距 %.1f   轮距（含轮子）%.1f   车壳长 %.1f" % [
			shape.radius, _car_wheelbase, _car_span, hi - lo])
	print("  车壳质量 %.1f   车轮质量 %.1f" % [chassis.mass, wheel.mass])
	car.free()


# ---------------------------------------------------------------- 场景搭建

## 真实形状地形，但**不进树**：不进树就不建区块、不摆东西，只要一条地表折线
## （和 tests/features.gd 的 [method _real_terrain] 同一个道理）。
func _real_terrain(map_id: String) -> HillTerrain:
	var t := HillTerrain.new()
	t.world_seed = SEED
	t.map_id = map_id
	return t


## 铺一张只有这张图的世界。`stream_at` 是要建出来的区块下标（-1 = 一块都不建）。
func _setup(map_id: String, stream_at := -1) -> void:
	if _world != null:
		_world.queue_free()
		_car = null
	_world = Node2D.new()
	add_child(_world)
	_terrain = HillTerrain.new()
	# 缝底 / 平台带底下那条死区（"掉下去 = 死"）。不摆的话车会**蹲在缝底出不来** ——
	# 那正是死区存在的理由（见 terrain.gd 的 `_add_gap_hazard`）。
	_terrain.hazard_scene = HAZARD_SCENE
	_world.add_child(_terrain)
	_terrain.world_seed = SEED
	_terrain.map_id = map_id
	if stream_at >= 0:
		# 给个空节点当跟随目标就够了：这些节要的是区块被建出来，不是要一辆车
		# （[method HillTerrain.set_target] 自己会同步刷一次）。
		var probe := Node2D.new()
		probe.position = Vector2(float(stream_at) * CW, 0.0)
		_world.add_child(probe)
		_terrain.set_target(probe)


## 摆一辆车。`y` 给 `INF` 时按脚下地表算（正常情况），否则用给的绝对高度 ——
## **必须在 `add_child` 之前定好位置**：进树之后再摆，刚体会被瞬移一次
## （car.gd 的注释里写了两条理由），而这里要的正是「一进树就坐在云上」。
func _spawn_car(map_id: String, x: float, y := INF, vx := 0.0) -> HillCar:
	if _car != null and is_instance_valid(_car):
		_car.queue_free()
	var car := CAR.instantiate()
	car.position = Vector2(x, (_terrain.height_at(x) - CAR_LIFT) if is_inf(y) else y)
	_world.add_child(car)
	# 地图要在进树之后套：apply_map 读的是 @onready 的轮子节点。
	car.apply_map(map_id)
	car.fuel = 1.0e9
	if not is_zero_approx(vx):
		for body: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
			body.linear_velocity = Vector2(vx, 0.0)
	_terrain.set_target(car.chassis)
	_car = car
	return car


func _chunk_node(index: int) -> Node:
	return _terrain.get_node_or_null("Chunk%d" % index)


## 这一块区块里所有的平台节点（彩虹图）。别的图返回空数组。
func _platforms_in(index: int) -> Array[HillPlatform]:
	var out: Array[HillPlatform] = []
	var chunk := _chunk_node(index)
	if chunk == null:
		return out
	for child in chunk.get_children():
		if child is HillPlatform:
			out.append(child as HillPlatform)
	return out


## 一块平台**实际碰撞体**在世界坐标里的外接框。
##
## 刻意不照着 [method Maps.platforms_in_column] 那套公式重算一遍 —— 那样只是把
## 同一个式子抄成两份，抄错了也照样对得上。这里读的是**建出来的节点和它真正的
## 变换**：云的斜置、彩虹弧的实际张角全都算在里面，和碰撞系统吃的是同一份数据。
func _platform_rect(node: HillPlatform) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var any := false
	for xf in _colliders_under(node):
		var t := xf.get_global_transform()
		for corner in _collider_corners(xf):
			var w := t * corner
			lo = lo.min(w)
			hi = hi.max(w)
			any = true
	if not any:
		return Rect2()
	return Rect2(lo, hi - lo)


## `root` 底下所有的碰撞节点，深度优先（形状和多边形两种都要）。
##
## **`Area2D` 底下的不算**：云朵那圈感知区（探车用的）比云本身高出一大截，
## 算进去的话「两块不相连」会变成「两朵云的**感知区**不相连」—— 量错了东西。
func _colliders_under(root: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child in root.get_children():
		if child is Area2D:
			continue
		if child is CollisionShape2D or child is CollisionPolygon2D:
			out.append(child as Node2D)
		out.append_array(_colliders_under(child))
	return out


## 一个碰撞节点的**局部**角点表。矩形和多边形各展开成 4 个 / n 个点，
## 于是「转一下再取包围盒」这件事在上面的循环里是同一套代码。
func _collider_corners(xf: Node2D) -> Array[Vector2]:
	if xf is CollisionPolygon2D:
		var pts: Array[Vector2] = []
		for p in (xf as CollisionPolygon2D).polygon:
			pts.append(p)
		return pts
	var s := (xf as CollisionShape2D).shape
	if s is RectangleShape2D:
		var half := (s as RectangleShape2D).size * 0.5
		return [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	if s is CircleShape2D:
		var r := (s as CircleShape2D).radius
		return [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]
	return []


## `root` 底下所有 [CollisionShape2D]，深度优先。黑夜那一节拿它量「车有多大」
## —— **用碰撞形状而不是画出来的多边形**：车壳的 [Polygon2D] 和它的碰撞多边形是
## 两套数据，而挡布关心的是「哪一片像素上有东西」，两者重合；碰撞形状是每一台车
## 都有的那套（画图节点各车叫什么都不一定）。
func _shapes_under(root: Node) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	if root == null:
		return out
	for child in root.get_children():
		if child is CollisionShape2D:
			out.append(child as CollisionShape2D)
		out.append_array(_shapes_under(child))
	return out


## 一个碰撞形状**从它自己的原点**伸出去多远，旋转不变（宁可偏大，不许偏小：
## 这条量的是「车有没有探进黑里」，量小了就等于放过了一个真的越界）。
func _shape_reach(shape: CollisionShape2D) -> float:
	var s := shape.shape
	if s is CircleShape2D:
		return (s as CircleShape2D).radius
	if s is RectangleShape2D:
		var half := (s as RectangleShape2D).size * 0.5
		return half.length()
	if s is ConvexPolygonShape2D:
		var far := 0.0
		for p in (s as ConvexPolygonShape2D).points:
			far = maxf(far, p.length())
		return far
	if s is CapsuleShape2D:
		var cap := s as CapsuleShape2D
		return cap.height * 0.5 + cap.radius
	return 0.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle() -> void:
	await _frames(SETTLE)


## 全油门开，直到过线 / 死掉 / 超时。**腾空时松油门。**
##
## 「腾空时按前进」在 car.gd 里根本不是油门，是**空中姿态**：它把车逆时针拧
## （[member HillCar.air_spin] 14 rad/s ≈ 800°/s，一秒一整圈）。一直按着不放的
## 机器人一旦被弹到空中就必然后空翻、然后拿车顶落地 —— 那测的是自己有多不会开车，
## 不是地图。真人腾空时要么松开、要么反着拧，所以这一节按「着地才给油」开。
##
## `st` 是个字典 —— GDScript 的 lambda 捕获局部变量是**按值复制**的，
## 往里写数字出不来，写字典里的键才能带出来（和 tests/features.gd 同一套）。
func _drive_until(stop_x: float, max_seconds: float, st: Dictionary,
		on_frame: Callable = Callable()) -> void:
	var frames := int(round(max_seconds / DT))
	for i in frames:
		var car := _car
		if car == null or not is_instance_valid(car) or not car.alive:
			break
		if String(st.get("reason", "")) != "":
			break
		if car.chassis.global_position.x > stop_x:
			break
		if car.grounded:
			Input.action_press("drive_forward")
		else:
			Input.action_release("drive_forward")
		await get_tree().physics_frame
		if on_frame.is_valid():
			on_frame.call(st)
	Input.action_release("drive_forward")


# ---------------------------------------------------------------- 地表剖面

## 地表折线的 ASCII 剖面：每列一个采样点（20 像素），每行 10 像素，
## `#` 是地面、`-` 是 GROUND_Y 那条基准线（只在没有地面的列上画）。
##
## 「缝右边是不是真的低一截」「拱是不是真的交叉」这两件事数字断言看不出来，
## 用字符看最快。只画几块，别把日志刷爆。
func _profile(map_id: String, chunks: int) -> void:
	var t := _real_terrain(map_id)
	var rows := 20
	var cols := chunks * HillTerrain.CHUNK_POINTS + 1
	var top := 130.0
	var row_px := 10.0
	var base_row := int(floor(top / row_px))
	var cells: Array = []
	for r in rows:
		var line := PackedStringArray()
		for c in cols:
			line.append(" ")
		cells.append(line)
	for c in cols:
		var x := float(Maps.SHAPE_START_CELL) * CW + float(c) * HillTerrain.POINT_SPACING
		var r := int(floor((t.height_at(x) - HillTerrain.GROUND_Y + top) / row_px))
		if r >= 0 and r < rows:
			cells[r][c] = "#"
		if cells[base_row][c] == " ":
			cells[base_row][c] = "-"
	print("=== %s 剖面（每列 %d 像素，每行 %.0f 像素）===" % [
			map_id, int(HillTerrain.POINT_SPACING), row_px])
	for r in rows:
		print("  " + "".join(cells[r]))
	t.free()


# ---------------------------------------------------------------- 屋顶：剖面

## 一栋房子长什么样：屋面平、钢梯连、落点台和跳台都在。
##
## **这一节量的是「用户要的那三个词」**：
##
##   · 「仅为水平直线」 —— 平段上地表起伏恒为 0（拿 20 像素的采样网格去量，
##     不是拿解析式自己证自己）。
##   · 「高地错落」 —— 一栋之内靠钢梯分段爬（段数随机），一栋之外靠天际线。
##   · 「用钢制梯子连接」 —— 每段钢梯至少爬 [constant Maps.LADDER_MIN]，
##     两头斜率为 0（不漏折角）、中段 `1.5 / LADDER_RUN` ≈ 55°。
##
## 还有一条是**给碰撞用的**：地表折线和剖面逐点吻合。剖面是解析算的，地表是
## `_base_height + _carve` —— 后者要是在屋顶上多挖了一铲子，这条立刻红。
func _section_roof_profile() -> void:
	print("=== 屋顶：一栋栋房子，屋面平、钢梯连 ===")
	var t := _real_terrain(Maps.ROOFTOP)
	var counts := {}
	var flat_err := 0.0
	var land_min := INF
	var land_max := -INF
	var ledge_min := INF
	var sect_min := INF
	var rise_min := INF
	var short_rungs := 0
	var end_slope := 0.0
	var mid_slope := 0.0
	var match_err := 0.0
	var bad_head := 0
	var len_err := 0.0
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + CHUNKS):
		var left := float(i) * CW
		var prof: Dictionary = t.roof_profile(i)
		var pts: PackedVector2Array = prof["pts"]
		var ramps: PackedInt32Array = prof["ramps"]
		var span := Maps.span_at(SEED, i)
		len_err = maxf(len_err, absf(float(prof["len"]) - span))
		counts[ramps.size()] = int(counts.get(ramps.size(), 0)) + 1
		# 折线的两头必须是屋顶的两头。容差 1e-3 而不是 1e-9：`pts` 是
		# [PackedVector2Array]，分量按 **float32** 存（x ≈ 670 时精度才 6e-5），
		# 而 `y0`/`y1` 是字典里的 float64。差的是最后几位，不是几何。
		if pts.size() < 3 or absf(pts[0].x) > 1e-3 or absf(pts[pts.size() - 1].x - span) > 1e-3 \
				or absf(pts[0].y - float(prof["y0"])) > 1e-3 \
				or absf(pts[pts.size() - 1].y - float(prof["y1"])) > 1e-3:
			bad_head += 1
		# 地表折线和剖面逐点吻合（每 5 像素一个点）。
		var lx := 0.0
		while lx <= span:
			match_err = maxf(match_err, absf(t.height_at(left + lx)
					- HillTerrain.roof_profile_y(prof, lx)))
			lx += 5.0
		var flat_index := 0
		# 每段钢梯至少爬 LADDER_MIN —— 但**整栋房子爬不到 LADDER_MIN 时例外**：
		# 那一栋只有一段梯子，它爬的就是全部（见 [method HillTerrain._ladder_count]，
		# 段数是按 `总爬升 ÷ LADDER_MIN` 往下减的）。房子总是有一部分在往上/往下错落，
		# 那段错落必须由钢梯吃掉，不然屋顶右沿就接不上（会变成一道坎）。
		var floor := minf(Maps.LADDER_MIN, absf(float(prof["y0"]) - float(prof["y1"])))
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var w := b.x - a.x
			if ramps.has(k):
				var climb := absf(b.y - a.y)
				rise_min = minf(rise_min, climb)
				if climb < floor - 1e-3:
					short_rungs += 1
				# 钢梯的形状：中段最陡、两头平（smoothstep）。**用解析式量，不是用
				# 20 像素的网格量** —— 网格是弦，量出来的永远比切线的坡度小。
				if w > 1.0:
					var step := w * 0.02
					for u: float in [0.02, 0.5]:
						var p0 := HillTerrain.roof_profile_y(prof, a.x + w * u - step)
						var p1 := HillTerrain.roof_profile_y(prof, a.x + w * u + step)
						var sl := absf(p1 - p0) / (step * 2.0)
						if u < 0.5:
							end_slope = maxf(end_slope, sl)
						else:
							mid_slope = maxf(mid_slope, sl)
			else:
				# 平段：地表必须真的是水平的。**只挑网格点量** —— 采样点落在哪儿
				# 都是同一个高度，这才叫「水平直线」。
				var lo := INF
				var hi := -INF
				var gx := ceilf(a.x / HillTerrain.POINT_SPACING) * HillTerrain.POINT_SPACING
				while gx <= b.x:
					var h := t.height_at(left + gx)
					lo = minf(lo, h)
					hi = maxf(hi, h)
					gx += HillTerrain.POINT_SPACING
				if lo <= hi:
					flat_err = maxf(flat_err, hi - lo)
				if flat_index == 0:
					land_min = minf(land_min, w)
					land_max = maxf(land_max, w)
				elif k == pts.size() - 2:
					ledge_min = minf(ledge_min, w)
				else:
					sect_min = minf(sect_min, w)
				flat_index += 1
	print("  钢梯段数分布：%s（1～%d 段）" % [counts, Maps.LADDER_MAX])
	print("  平段上地表起伏最大 %.6f 像素；落点台 %.1f～%.1f；最短跳台 %.1f；最短中间平路 %.1f" % [
			flat_err, land_min, land_max, ledge_min, sect_min])
	print("  钢梯：最矮一段爬 %.1f 像素；两头坡度最大 %.3f、中段最陡 %.3f（%.1f°，理论 %.3f）" % [
			rise_min, end_slope, mid_slope, rad_to_deg(atan(mid_slope)), LADDER_SLOPE])
	print("  地表和剖面的最大偏差 %.6f 像素；屋顶长度对不上 %.2f 像素、折线两头不对的 %d 栋" % [
			match_err, len_err, bad_head])
	_check("屋面是水平的（平段上地表起伏 < 0.001 像素）", flat_err < 0.001,
			"最大 %.6f 像素" % flat_err)
	_check("落点台就是 ROOF_LAND（%.0f 像素）" % Maps.ROOF_LAND,
			absf(land_min - Maps.ROOF_LAND) < 0.01 and absf(land_max - Maps.ROOF_LAND) < 0.01,
			"%.2f～%.2f" % [land_min, land_max])
	_check("跳台至少 ROOF_LEDGE（%.0f 像素）" % Maps.ROOF_LEDGE,
			ledge_min >= Maps.ROOF_LEDGE - 0.01, "最短 %.2f" % ledge_min)
	_check("两段钢梯之间至少 SECTION_MIN（%.0f 像素）" % Maps.SECTION_MIN,
			sect_min >= Maps.SECTION_MIN - 0.01, "最短 %.2f" % sect_min)
	_check("每段钢梯至少爬 LADDER_MIN（%.0f 像素；总爬升不够的按总爬升算）" % Maps.LADDER_MIN,
			short_rungs == 0, "爬不够的有 %d 段，最矮 %.3f" % [short_rungs, rise_min])
	_check("钢梯中段最陡不超过 1.5 / LADDER_RUN（%.3f ≈ %.0f°）" % [
			LADDER_SLOPE, rad_to_deg(atan(LADDER_SLOPE))],
			mid_slope <= LADDER_SLOPE * 1.02,
			"最陡 %.3f（%.1f°）" % [mid_slope, rad_to_deg(atan(mid_slope))])
	_check("钢梯两头是平的（不漏折角）", end_slope <= LADDER_SLOPE * 0.25,
			"端部坡度 %.3f（中段的 %.0f%%）" % [end_slope, 100.0 * end_slope / maxf(mid_slope, 1e-6)])
	_check("每栋房子 1～%d 段钢梯" % Maps.LADDER_MAX,
			counts.size() >= 1 and int(counts.keys().min()) >= 1 \
			and int(counts.keys().max()) <= Maps.LADDER_MAX, "%s" % [counts])
	_check("不止一种段数（段数是随机的）", counts.size() >= 2, "%s" % [counts])
	_check("地表折线和剖面逐点吻合（屋顶上没被挖过）", match_err < 1e-6,
			"最大 %.6f 像素" % match_err)
	_check("屋顶长度 = 区块宽 − 缝宽（[method Maps.span_at]）", len_err < 0.01 and bad_head == 0,
			"长度差 %.3f，折线两头不对的 %d 栋" % [len_err, bad_head])
	t.free()


# ---------------------------------------------------------------- 屋顶：房子画在哪儿

## 房子上的瓦、楼层、窗户、钢梯（[scripts/rooftop_art.gd]）—— 这里量的**全是纯函数**。
##
## 无头跑（`--headless`）根本不发 `NOTIFICATION_DRAW`，`_draw` 里画了什么一条都验不到，
## 所以断言全打在 [HillRooftopArt] 的静态函数上：瓦铺到哪儿、楼层多密、窗户摆几列、
## 哪一扇亮着、横档多密、导轨离坡面多高。**真实观感**（瓦像不像瓦、窗像不像窗）
## 这一节验不了，只能靠截图看。
##
## 重点是**重建前后逐位一致**：区块会随镜头滚出视野再重建，同一栋房子必须每次都长得
## 一模一样。这一节用两条来钉：
##
##  · **瓦钉在世界格点上**：每一块瓦的圆心都是 [constant HillRooftopArt.TILE_PITCH]
##    的整数倍（世界坐标）。这条比「平移后不变」更贴题：房子是 800 一块、瓦是 22 一块，
##    两边除不尽，**只有钉在世界格点上，相邻两栋的瓦缝才接得上** —— 按区块内坐标铺
##    的话每栋房子的瓦都从自己的左沿重新起步，一眼就看出来。
##  · **同一个输入调两次结果相同**：窗户亮暗用了 `randf()` 的话，回头一看亮着的
##    窗户就换了一批 —— 玩家一眼能看出来。
func _section_roof_art() -> void:
	print("=== 屋顶：房子画在哪儿（瓦 / 楼层 / 窗户 / 钢梯）===")
	var t := _real_terrain(Maps.ROOFTOP)
	var flats := 0
	var tile_gap := 0
	var tile_out := 0
	var phase_err := 0.0
	var shift_err := 0.0
	var tiles := 0
	var tile_pitch_err := 0.0
	var ladder_pts := 0
	var sample_err := 0.0
	var ladders := 0
	var rung_len_err := 0.0
	var rung_gap_lo := INF
	var rung_gap_hi := 0.0
	var rail_err := 0.0
	var rail_under := 0
	var rows_total := 0
	var floor_gap_err := 0.0
	var floor_high := 0
	var col_gap_err := 0.0
	var cols_min := 999
	var win_out := 0
	var win_over := 0
	var windows := 0
	var lit := 0
	var flip := 0
	var mid_flip := 0
	# 问窗户用的时刻：挑一个**正好落在拍子边界上**的数 —— 123.0 和 123.5 都在第 123 拍里，
	# 所以拿它俩能同时验「同一拍答案一样」和「拍子只认整拍」。
	var tk := 123.0
	var tk_mid := tk + HillRooftopArt.WINK_STEP * 0.5
	# 每一扇画得出来的窗（[区块号, 层, 列]），后面拿它连看好几拍。
	var win_keys: Array[Array] = []
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + 20):
		var prof := t.roof_profile(i)
		var start := float(i) * CW
		var span := float(prof["len"])
		var pts: PackedVector2Array = prof["pts"]
		var ramps: PackedInt32Array = prof["ramps"]
		var y_hi := -INF
		for p in pts:
			y_hi = maxf(y_hi, p.y)

		# --- 瓦：每一级平屋面都要铺满，相位只认世界 x ---
		for k in pts.size() - 1:
			var y := float(pts[k].y)
			var xa := start + float(pts[k].x)
			var xb := start + float(pts[k + 1].x)
			if ramps.has(k):
				continue          # 钢梯那几段是钢的，不铺瓦
			flats += 1
			var cs := HillRooftopArt.tile_centers(xa, xb)
			if cs.is_empty():
				tile_gap += 1
				continue
			# 瓦钉在世界格点上：圆心到最近的 TILE_PITCH 整数倍有多远。
			for cx in cs:
				phase_err = maxf(phase_err, absf(cx - roundf(cx / HillRooftopArt.TILE_PITCH)
						* HillRooftopArt.TILE_PITCH))
			# 整段平移**整数块瓦**：位置必须跟着平移同样的量（格点自己平移到自己）。
			var far := HillRooftopArt.tile_centers(xa, xb)
			var jump := HillRooftopArt.TILE_PITCH * 40.0
			if not far.is_empty():
				var moved := HillRooftopArt.tile_centers(far[0] + jump, far[far.size() - 1] + jump)
				if moved.size() != far.size():
					shift_err = INF
				else:
					for j in far.size():
						shift_err = maxf(shift_err, absf(moved[j] - far[j] - jump))
			tiles += cs.size()
			for j in cs.size() - 1:
				tile_pitch_err = maxf(tile_pitch_err, absf(cs[j + 1] - cs[j] - HillRooftopArt.TILE_PITCH))
			# 瓦**整个**掐在这一级屋面里：最外那两块瓦的拱会往外铺半个间距，
			# 不掐就探出房子的棱、悬在缝上面。这一条守的是那个掐。
			for cx in cs:
				for p in HillRooftopArt.tile_arc(cx, y, xa, xb):
					if p.x < xa - 1e-3 or p.x > xb + 1e-3 \
							or absf(p.y - y) > HillRooftopArt.TILE_R + 1e-3:
						tile_out += 1

		# --- 钢梯：画出来的坡必须和车压着走的那条坡逐位相同 ---
		for k in ramps.size():
			var s := HillRooftopArt.ladder_samples(prof, k)
			ladders += 1
			for p in s:
				ladder_pts += 1
				sample_err = maxf(sample_err, absf(
						p.y - HillTerrain.roof_profile_y(prof, p.x)))
			var rungs := HillRooftopArt.ladder_rungs(s)
			var rail := HillRooftopArt.ladder_rail(s)
			for j in rungs.size():
				rung_len_err = maxf(rung_len_err, absf(rungs[j][0].distance_to(rungs[j][1])
						- HillRooftopArt.LADDER_W))
				if j > 0:
					var gap := rungs[j][0].distance_to(rungs[j - 1][0])
					rung_gap_lo = minf(rung_gap_lo, gap)
					rung_gap_hi = maxf(rung_gap_hi, gap)
			for j in rail.size():
				rail_err = maxf(rail_err, absf(rail[j].distance_to(s[j])
						- HillRooftopArt.LADDER_W))
				if rail[j].y >= s[j].y:
					rail_under += 1

		# --- 楼层与窗户 ---
		#
		# 地板线画到地块底边为止，所以这里用**真的底边**（[method HillTerrain._build_chunk]
		# 那一份算法：本区块最深那一点再往下 [constant HillTerrain.DEPTH]）—— 随便取个
		# 「够深」的数会把窗和地板线的条数量大，那两行的读数就不作数了。
		var deepest := HillTerrain.GROUND_Y
		for q in HillTerrain.CHUNK_POINTS + 1:
			deepest = maxf(deepest, t.height_at(start + float(q) * HillTerrain.POINT_SPACING))
		var rows := HillRooftopArt.floor_ys(y_hi + HillRooftopArt.FLOOR_H,
				deepest + HillTerrain.DEPTH)
		rows_total += rows.size()
		for r in rows.size():
			if r > 0:
				floor_gap_err = maxf(floor_gap_err,
						absf(rows[r] - rows[r - 1] - HillRooftopArt.FLOOR_H))
			if rows[r] < y_hi + HillRooftopArt.FLOOR_H - 1e-3:
				floor_high += 1
		var cols := HillRooftopArt.window_centers(0.0, span)
		cols_min = mini(cols_min, cols.size())
		for c in cols.size():
			if c > 0:
				col_gap_err = maxf(col_gap_err,
						absf(cols[c] - cols[c - 1] - HillRooftopArt.WIN_PITCH))
			if cols[c] - HillRooftopArt.WIN_W * 0.5 < -1e-3 \
					or cols[c] + HillRooftopArt.WIN_W * 0.5 > span + 1e-3:
				win_out += 1
			for r in rows.size():
				var top := rows[r] - HillRooftopArt.WIN_SILL - HillRooftopArt.WIN_H
				if not HillRooftopArt.window_fits(prof, start, cols[c], top):
					continue
				windows += 1
				# 下面这一串都按 `tk` 那一拍问。窗户是**活**的（用户要的
				# 「窗户动画」），但只认拍子 —— 见 [method HillRooftopArt.window_tick]。
				var on := HillRooftopArt.window_lit(SEED, i, r, c, tk)
				if on:
					lit += 1
				if on != HillRooftopArt.window_lit(SEED, i, r, c, tk):
					flip += 1
				# 同一拍里换个时刻问：还在这一拍里，答案必须一样。
				# 直接拿 `now()` 的话每帧都在动，所以这里钉死在拍子中间。
				if on != HillRooftopArt.window_lit(SEED, i, r, c, tk_mid):
					mid_flip += 1
				win_keys.append([i, r, c])
				# 「屋面单调 ⇒ 量窗的两头就够」这条前提自己验一遍：窗宽的
				# 四分之一、一半、四分之三处也得在屋面底下。
				for f in [0.25, 0.5, 0.75]:
					if HillTerrain.roof_profile_y(prof,
							cols[c] + (f - 0.5) * HillRooftopArt.WIN_W) >= top:
						win_over += 1
	t.free()

	# --- 窗户换脸：整座城一起眨还是各眨各的 ---
	#
	# 一拍里没有哪扇窗会中途变脸（上面 `mid_flip`），隔一段再看必须有窗换了脸
	# （不然「动画」根本没做），而且**换脸要散开**：全城同一个周期的话，到点了
	# 整条街一起眨眼，那一眼就看出来是假的。
	var moved := 0
	var flip_hi := 0
	var ticks: Array[bool] = []
	for w: Array in win_keys:
		ticks.clear()
		for k in ANIM_TICKS + 1:
			ticks.append(HillRooftopArt.window_lit(SEED, int(w[0]), int(w[1]), int(w[2]),
					float(k) * HillRooftopArt.WINK_STEP))
		var changed := false
		for k in ticks.size() - 1:
			if ticks[k] != ticks[k + 1]:
				changed = true
				break
		if changed:
			moved += 1
	var per_tick: Array[int] = []
	per_tick.resize(ANIM_TICKS)
	per_tick.fill(0)
	for w: Array in win_keys:
		var prev := HillRooftopArt.window_lit(SEED, int(w[0]), int(w[1]), int(w[2]), 0.0)
		for k in range(1, ANIM_TICKS + 1):
			var cur := HillRooftopArt.window_lit(SEED, int(w[0]), int(w[1]), int(w[2]),
					float(k) * HillRooftopArt.WINK_STEP)
			if cur != prev:
				per_tick[k - 1] += 1
			prev = cur
	for n: int in per_tick:
		flip_hi = maxi(flip_hi, n)
	var busiest := float(flip_hi) / maxf(1.0, float(win_keys.size()))
	print("  %d 扇窗、%d 拍：%d 扇至少换过一次脸；最挤的一拍有 %d 扇一起变（%.0f%%）" % [
			win_keys.size(), ANIM_TICKS, moved, flip_hi, busiest * 100.0])
	_check("同一拍里问两次答案一样（窗户只认拍子，不认帧）", mid_flip == 0,
			"同一拍里翻了 %d 次" % mid_flip)
	_check("隔 %d 拍再看，绝大多数窗都换过脸（动画真的在动）" % ANIM_TICKS,
			moved > win_keys.size() * 8 / 10, "%d / %d 扇" % [moved, win_keys.size()])
	_check("换脸是各眨各的，没有整条街一起眨",
			busiest < 0.25, "最挤的一拍 %.0f%% 的窗同时变" % (busiest * 100.0))
	_check("也没有哪一拍是一扇都不变的", flip_hi > 0, "最挤的一拍 %d 扇" % flip_hi)

	print("  %d 级平屋面铺了 %d 块瓦（间距 %.0f）；%d 段钢梯、%d 个坡面采样点" % [
			flats, tiles, HillRooftopArt.TILE_PITCH, ladders, ladder_pts])
	print("  %d 条地板线；窗户最少的一栋 %d 列；画得出来的窗 %d 扇，其中亮着 %d 扇" % [
			rows_total, cols_min, windows, lit])
	print("  横档间距 %.2f～%.2f 像素（设计 %.0f，弦比弧短一点是坡脚那一下弯）；导轨高于坡面 %.2f～%.2f" % [
			rung_gap_lo, rung_gap_hi, HillRooftopArt.LADDER_RUNG,
			HillRooftopArt.LADDER_W - rail_err, HillRooftopArt.LADDER_W])
	_check("每一级平屋面都铺满了瓦", tile_gap == 0, "空着的 %d 级（共 %d 级）" % [tile_gap, flats])
	_check("瓦的间距正好是 TILE_PITCH", tile_pitch_err < 1e-3, "最大 %.4f" % tile_pitch_err)
	_check("瓦钉在世界格点上（相邻两栋的瓦缝才接得上）", phase_err < 1e-3,
			"离最近的格点 %.6f 像素" % phase_err)
	_check("整段平移整数块瓦，位置跟着平移", shift_err < 1e-3, "最大 %.4f" % shift_err)
	_check("没有一块瓦探出它那一级屋面", tile_out == 0, "探出去的顶点 %d 个" % tile_out)
	_check("钢梯画出来的坡 = 车压着走的坡（逐点对 [method HillTerrain.roof_profile_y]）",
			sample_err < 1e-3, "最大 %.4f 像素" % sample_err)
	_check("横档都是一根 LADDER_W 长", rung_len_err < 1e-3, "最长差 %.4f" % rung_len_err)
	_check("横档间距均匀（按坡面弧长铺，弦比弧略短）",
			rung_gap_lo > HillRooftopArt.LADDER_RUNG * 0.75 and rung_gap_hi < HillRooftopArt.LADDER_RUNG * 1.01,
			"%.2f～%.2f（设计 %.0f）" % [rung_gap_lo, rung_gap_hi, HillRooftopArt.LADDER_RUNG])
	_check("两根导轨：一根就是坡面，另一根抬 LADDER_W 且在**上面**",
			rail_err < 1e-3 and rail_under == 0,
			"离坡面差 %.4f，穿到坡下的 %d 个点" % [rail_err, rail_under])
	_check("地板线间距正好是 FLOOR_H", floor_gap_err < 1e-3, "最大 %.4f" % floor_gap_err)
	_check("第一层地板线在最低那一级屋面之下", floor_high == 0,
			"跑到屋面上的 %d 条" % floor_high)
	_check("窗户列距正好是 WIN_PITCH", col_gap_err < 1e-3, "最大 %.4f" % col_gap_err)
	_check("每栋房子至少一列窗，且都不越出房子", cols_min >= 2 and win_out == 0,
			"最少 %d 列，越出房子的 %d 扇" % [cols_min, win_out])
	_check("画出来的窗整扇都在屋面底下（量窗宽中间也验过一遍）", win_over == 0,
			"压在屋面上的 %d 处" % win_over)
	_check("亮暗两种窗都有（不是全亮也不是全暗）", lit > 0 and lit < windows,
			"%d / %d 扇亮着" % [lit, windows])
	_check("同一扇窗两次问同一个答案（没用 randf）", flip == 0, "翻来覆去的 %d 扇" % flip)


# ---------------------------------------------------------------- 屋顶：缝的落差

## 每条缝都是**右边更低**，而且**低的就是掷出来的那个数**：
## `下一栋的左沿 = 上一栋的右沿 + drop_at(缝号)`（[method HillTerrain.roof_profile]）。
##
## 拿这个等式逐条对，而不是只断言「> 0」：只断言 > 0 的话，把落差写成 1 像素、
## 或者让天际线把落差吃掉一半，都能过 —— 而那两条都是错的方向
## （玩家看得出来 / 跳不过去）。老设计里屋顶形状有自己的端部高度，这条等式得写成
## 三项；现在屋面是平的，落差**就是**它本身，一像素不多一像素不少。
func _section_roof_drop() -> void:
	print("=== 屋顶：每条缝右边都低一截，低的就是掷出来的那个数 ===")
	_profile(Maps.ROOFTOP, 2)
	var t := _real_terrain(Maps.ROOFTOP)
	var drops: Array = []
	var bad: Array = []
	var mid_err := 0.0
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + CHUNKS):
		var span := Maps.span_at(SEED, i)
		var l := t.height_at(float(i) * CW + span - 0.5)
		var r := t.height_at(float(i + 1) * CW + 0.5)
		var want := Maps.drop_at(SEED, i)
		drops.append(r - l)
		if absf((r - l) - want) > 0.02:
			bad.append("%d:%.2f/%.2f" % [i, r - l, want])
		# 缝**里面**那条落差是 smoothstep：缝正中间应该正好落了一半。
		#
		# 缝底还挖着 [_basin] 那口平底锅（深 [constant Maps.GAP_DEPTH]），落差是
		# **骑在它上面**的 —— 所以量的时候先把平底减掉。不减的话量到的是
		# `GAP_DEPTH`（420）本身，跟落差一点关系都没有（这一条踩过一次）。
		# 缝正中间离两条沿都有 65 像素上下，稳稳落在平底里（倒角只有
		# [constant Maps.GAP_EDGE]），所以那个减数是常数。
		var mid := (span + CW) * 0.5
		mid_err = maxf(mid_err, absf(
				t.height_at(float(i) * CW + mid) - l - Maps.GAP_DEPTH - want * 0.5))
	var lowest := _low(drops)
	var highest := _high(drops)
	print("  %d 条缝的落差：最小 %.2f，最大 %.2f 像素（掷骰范围 %.0f～%.0f）" % [
			drops.size(), lowest, highest, Maps.DROP_LO, Maps.DROP_HI])
	print("  缝正中间的高度偏差最大 %.3f 像素（减掉缝底 %.0f 像素的平底之后）" % [
			mid_err, Maps.GAP_DEPTH])
	_check("每条缝右边都比左边低", lowest > 0.0, "最浅的一条低 %.2f 像素" % lowest)
	_check("落差和 drop_at 掷出来的数一模一样", bad.size() == 0,
			"%d / %d 条对不上 %s" % [bad.size(), drops.size(), bad.slice(0, 3)])
	_check("落差都落在 DROP_LO～DROP_HI（%.0f～%.0f）里" % [Maps.DROP_LO, Maps.DROP_HI],
			lowest >= Maps.DROP_LO - 0.02 and highest <= Maps.DROP_HI + 0.02,
			"%.2f～%.2f" % [lowest, highest])
	_check("落差的范围真的用满了（不是挤在一头）",
			lowest <= Maps.DROP_LO + 5.0 and highest >= Maps.DROP_HI - 5.0,
			"实测 %.2f～%.2f" % [lowest, highest])
	_check("缝里的落差是 smoothstep（正中间落一半）", mid_err < 0.6,
			"最大偏差 %.3f 像素" % mid_err)
	t.free()


func _low(xs: Array) -> float:
	var m := INF
	for x: float in xs:
		m = minf(m, x)
	return m


func _high(xs: Array) -> float:
	var m := -INF
	for x: float in xs:
		m = maxf(m, x)
	return m


## 中位数。**必须先排序。** `xs[xs.size() / 2]` 取的是**扫描顺序里第 n/2 个元素**，
## 不是中位数 —— `lens` / `cloud_w` 都是按列扫出来的，中间那个落在哪一列全看运气。
## 这两条断言（弧长、云宽）都栽在这上面过：弧长中位被读成 644，真值在 816 上下
## （差了两成，而且**读小了**，所以断言看着还是过的 —— 是条会静悄悄失真的尺子）。
func _median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var ys := xs.duplicate()
	ys.sort()
	return float(ys[ys.size() / 2])


func _mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := 0.0
	for x: float in xs:
		s += x
	return s / float(xs.size())


# ---------------------------------------------------------------- 屋顶：接缝与天际线

## 接缝上没有台阶、缝壁还是墙、天际线不累积。
##
## 四条都是「构造」的回归断言：
##
##  1. **接缝上没有台阶** —— 落差落在缝**里面**（[method HillTerrain._gap_drop]），
##     不是落在下一栋的头上一脚。落在下一栋头上的话，缝右沿那 40 像素的倒角还
##     顶在老高度上，车刚从缝左沿起跳就会撞在那个台阶上。
##  2. **缝壁还是爬不上去的墙**（[constant Maps.GAP_EDGE] = 40 像素的倒角，
##     两个采样点之间 80° 上下）：它要是被落差削平了，缝就不叫缝了。
##  3. **天际线不累积** —— 每栋房子的高度都在 `GROUND_Y ± (天际线 + 落差)` 之内。
##     老设计里落差是「每块各自补回来」的，补不干净就跑五十块沉下去一千八百像素；
##     现在落差是**构造**出来的（左沿 = 上一栋的右沿 + 落差），所以它天然不累积，
##     但这条断言留着：哪天有人把天际线接到「上一栋的高度」上，它立刻红。
##  4. **房子之间真的错落** —— 右沿（= 天际线）有高有低。量的是**幅度**，
##     不是「往上爬的和往下走的都有」：落差永远是正的（缝只会往下掉），所以每栋
##     房子都在往上爬，要往下错落得靠天际线一口气吃掉比落差还多的高度 —— 那是
##     少数（实测 60 栋里一栋都没有）。把少数事件写成断言，换个种子就红了。
##
## 缝顶那条还管着**云朵和死区**：两者都按 [method HillTerrain.gap_rect] 摆，
## 而那个矩形的顶就是缝左沿的高度（[method HillTerrain.height_at]）。
func _section_roof_seam() -> void:
	print("=== 屋顶：接缝上没有台阶、缝壁还是墙、天际线不累积 ===")
	var t := _real_terrain(Maps.ROOFTOP)
	var step := 0.0
	var step_at := 0.0
	var wall := INF
	var wall_at := 0.0
	var drift := 0.0
	var drift_at := 0.0
	var rim_err := 0.0
	var rising := 0
	var falling := 0
	var sky_lo := INF
	var sky_hi := -INF
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + CHUNKS):
		var left := float(i) * CW
		# 接缝 = 区块边界：函数在这儿必须是连续的（本块的尾巴和下一块的开头）。
		var d := absf(t.height_at(left + 1.0) - t.height_at(left))
		if d > step:
			step = d
			step_at = left
		# 缝右壁是**上一块**那条缝的右壁（0 号区块没有缝，所以从第二块起量）。
		if i > Maps.SHAPE_START_CELL:
			var w := (t.height_at(left - HillTerrain.POINT_SPACING) - t.height_at(left)) \
					/ HillTerrain.POINT_SPACING
			if w < wall:
				wall = w
				wall_at = left
		# 天际线不累积：这栋房子的两头都在基准附近。
		var prof: Dictionary = t.roof_profile(i)
		var y0 := float(prof["y0"])
		var y1 := float(prof["y1"])
		var off := maxf(absf(y0 - HillTerrain.GROUND_Y), absf(y1 - HillTerrain.GROUND_Y))
		if off > drift:
			drift = off
			drift_at = left
		if y0 > y1:
			rising += 1
		elif y0 < y1:
			falling += 1
		sky_lo = minf(sky_lo, y1)
		sky_hi = maxf(sky_hi, y1)
		# 缝顶（云朵架在哪儿、死区盖在哪儿）就是缝左沿的高度。
		var gap := t.gap_rect(i)
		if gap.size.x > 0.0:
			rim_err = maxf(rim_err, absf(gap.position.y - t.height_at(float(i + 1) * CW - gap.size.x)))
	var bound := HillTerrain.SKY_AMPLITUDE + Maps.DROP_HI
	print("  接缝上的最大台阶 %.4f 像素（在 x=%.0f）" % [step, step_at])
	print("  缝右壁最缓 %.2f（%.1f°，在 x=%.0f）" % [wall, rad_to_deg(atan(wall)), wall_at])
	print("  房子高度偏离基准最大 %.1f 像素（在 x=%.0f，上限 %.0f）" % [drift, drift_at, bound])
	print("  右沿（天际线）%.1f～%.1f（基准 %.0f，幅度 %.0f 像素）；往上爬的 %d 栋、往下走的 %d 栋；缝顶和缝左沿的最大偏差 %.4f 像素" % [
			sky_lo, sky_hi, HillTerrain.GROUND_Y, HillTerrain.SKY_AMPLITUDE, rising, falling, rim_err])
	_check("接缝上没有台阶（落差没有落成一道坎）", step < 0.5, "最大 %.4f 像素" % step)
	_check("缝的右壁还是爬不上去的墙（≥ 70°）", wall >= 2.75,
			"最缓 %.2f（%.1f°）" % [wall, rad_to_deg(atan(wall))])
	_check("天际线不累积（房子高度都在基准 ± %.0f 内）" % bound, drift <= bound + 0.01,
			"最大偏离 %.1f 像素" % drift)
	_check("房子之间真的错落（右沿有高有低，且幅度 ≥ 20 像素）", sky_hi - sky_lo >= 20.0,
			"%.1f～%.1f，幅度 %.1f 像素" % [sky_lo, sky_hi, sky_hi - sky_lo])
	_check("缝顶跟着缝左沿走（云朵和死区不会错位）", rim_err < 0.01,
			"最大偏差 %.4f 像素" % rim_err)
	t.free()


# ---------------------------------------------------------------- 屋顶：真地形开过去

## 从出生直道全油门一路开，跨过好几条缝：不许死。
##
## **真地形**，不是压平的 —— 爬钢梯、起跳、落地全在这节里。缝宽 130～150，
## 车在上一栋的跳台上有几百像素助跑，跳过去靠的就是那段助跑速度，压平了就测不到了。
##
## 量的主项不是「跨过几条」（那只是个结果数），而是**每条缝起跳那一瞬间的速度**，
## 拿它去比那条缝按物理需要多少：下落预算 `这条缝的落差 + 轮半径` 给出
## `t = √(2·预算/重力)`，需要 `缝宽 ÷ t`。落差是每缝一条的
## （[method Maps.drop_at]），所以滞空也是每缝一个 —— **最紧的是落差最浅的那条**。
## 给不起的缝就是**必死缝**，表里一眼能看出是哪一条、差多少 ——
## 而「车在 x=3138 摔了」查不出原因。
##
## 主项这样量还有个好处：**它跟车的参数是解耦的读数**。车调快了/调慢了，
## 这张表直接告诉你每条缝还差多少，不用反推。
##
## **钢梯会「撞」，不是「爬」—— 这是设计的一部分，不是 bug。**
## 实测：车全速（约 540 px/s）开到钢梯脚下，一帧之内从 537 掉到 85 px/s，
## 然后车身被顶起 30°、慢慢爬上梯子，再在 250 像素的跳台上把速度捡回来。
## 原因是几何上躲不掉的：房子一共 650～670 宽，落点台和跳台占掉 450，
## 一段钢梯只有 `爬升 × LADDER_RUN`（爬 40 像素 → 跑 42 像素）；而碰撞体是
## 每 20 像素一个采样点的折线，42 像素的坡摊到折线上，第一段弦就是 43° 的坎 ——
## 轮子撞的是那道坎。[tests/climb.gd] 自己就是为这件事才给坡度加了 260 像素的
## 圆弧过渡（见那边的 `ARC_RADIUS` 注释）。
##
## 所以这一节量的不是「掉不掉速」（那必然掉），而是：
##  · **掉速之后捡不捡得回来** —— 上面那张表：每条缝的起跳速度都要够。
##  · **车会不会卡住** —— 掉到 60 px/s 以下不许连续超过半秒。
##
## 想让车「骑」上梯子而不是撞上去，得把坡放缓（或者把过渡段拉到一百多像素，
## 那要吃掉半栋房子）：`LADDER_RUN` 是那个旋钮，用户选的是陡（≈55°）。
func _section_roof_drive() -> void:
	print("=== 屋顶：全油门跨过好几条缝 ===")
	var target := float(Maps.SHAPE_START_CELL + 3) * CW
	# 这一趟路上是些什么房子。起跳速度是「钢梯 × 车」的结论：光看一个数字说不清
	# 是哪栋房子吃掉的，得知道那栋爬多高、分几段、几段平路。
	var houses: Array = []
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + 4):
		var dice: Dictionary = Maps.roof_dice(SEED, i)
		houses.append("%d:%d段 落差%.0f" % [
				i, int(dice["ladders"]), Maps.drop_at(SEED, i)])
	print("  路上这几栋房子：%s" % ["，".join(houses)])
	_setup(Maps.ROOFTOP)
	var car := _spawn_car(Maps.ROOFTOP, START_X)
	# 房子（画师）必须挂在土色**之后**：同一层 z，后画的在上面。挂反了的话那块实心
	# 地块会把整面立面连窗户一起埋掉 —— 车照样开得动、别的断言照样绿，只有截图
	# 能看出来（这一条真踩过：房子整个不见了，测试全绿）。见 scripts/terrain.gd
	# `_build_chunk` 里那段「必须先建、后挂」。
	var order_seen := 0
	var order_bad := 0
	var order_detail := ""
	# 画师手里的坐标必须**就是那块区块的世界坐标**。画师画砖柱子用的自己的
	# `_start_x`（世界 x）配区块内坐标的剖面（[method HillRooftopArt._draw_chimneys]），
	# 力那边是「区块的世界 x」配同一份剖面（[scripts/chimneys.gd]）—— 函数是同一个，
	# 但**喂进去的数是各自算的**：`_start_x` 写成区块内坐标、或者建区块时 index 错一位，
	# 砖柱子就画到隔壁房子上、烟还在这边冒，而车照样开得动（只有截图看得出来）。
	# 所以拿节点**真收到**的字段（`setup` 之后）和地形自己的数据对一遍，再用两边的
	# 字段各算一次烟囱矩形，要求逐位相同。
	var frame_bad := 0
	var frame_detail := ""
	var chimneys_in_view := 0
	var art: HillRooftopArt = null
	for chunk in _terrain.get_children():
		var cname := String(chunk.name)
		if not cname.begins_with("Chunk"):
			continue
		var house_i := int(cname.substr(5))
		var ground_at := -1
		var art_at := -1
		for c in chunk.get_child_count():
			var child := chunk.get_child(c)
			if String(child.name) == "Ground":
				ground_at = c
			elif child is HillRooftopArt:
				art_at = c
				if art == null:
					art = child
		if art_at < 0:
			continue
		order_seen += 1
		if art_at < ground_at:
			order_bad += 1
			order_detail = "%s：Ground 在 %d、画师在 %d" % [chunk.name, ground_at, art_at]

		var node: HillRooftopArt = chunk.get_child(art_at)
		var prof: Dictionary = _terrain.roof_profile(house_i)
		var art_prof: Dictionary = node.get("_prof")
		var bad := ""
		if absf(float(node.get("_start_x")) - float(house_i) * CW) > 1e-3:
			bad = "_start_x %s（该 %s）" % [node.get("_start_x"), float(house_i) * CW]
		elif int(node.get("_index")) != house_i:
			bad = "_index %d（该 %d）" % [int(node.get("_index")), house_i]
		elif int(node.get("_seed")) != SEED:
			bad = "_seed %d（该 %d）" % [int(node.get("_seed")), SEED]
		elif art_prof.get("len") != prof.get("len") or art_prof.get("pts") != prof.get("pts"):
			bad = "剖面对不上（长 %s / %s）" % [art_prof.get("len"), prof.get("len")]
		else:
			var art_rect := HillChimneys.chimney_rect(art_prof,
					Maps.chimney_at(int(node.get("_seed")), int(node.get("_index"))),
					float(node.get("_start_x")))
			var force_rect := HillChimneys.chimney_rect(prof,
					Maps.chimney_at(SEED, house_i), float(house_i) * CW)
			if art_rect != force_rect:
				bad = "砖柱子 %s、受力区 %s" % [art_rect, force_rect]
			elif art_rect.size.x > 0.0:
				chimneys_in_view += 1
		if bad != "":
			frame_bad += 1
			frame_detail = "%s：%s" % [chunk.name, bad]
	_check("画师排在土色之后（房子盖得住地块，窗户才露得出来）",
			order_seen >= 2 and order_bad == 0,
			"看了 %d 块，排反的 %d 块 %s" % [order_seen, order_bad, order_detail])
	_check("画师拿到的坐标就是那块区块的世界坐标（砖柱子和烟才对得上）",
			frame_bad == 0, "对不上的 %d 块 %s" % [frame_bad, frame_detail])
	print("  看过的 %d 块里，摆得下烟囱的 %d 根（没烟囱的房子上，上面那条矩形比对是空过的 —— 真的摆位在 tests/features.gd 里按四十栋房子量）" % [
			order_seen, chimneys_in_view])

	# 窗户**真的挂在帧循环上**。上面那一节验的是算式（`window_lit` 会不会换脸），
	# 这条验的是「有没有人告诉引擎该重画了」—— 漏了 `_process` 的话算式全对、
	# 窗户一辈子一动不动，而用户报的正是「窗户动画还没做」。
	#
	# 拍子是一秒一格，所以这里得**真的等一秒多**：无头跑的帧比现实跑得快，
	# `await _frames(60)` 只有零点几秒，钟不会走。所以等真实计时器。
	var tick0 := 0
	var tick1 := 0
	if art != null:
		tick0 = int(art.get("_tick"))
		await get_tree().create_timer(HillRooftopArt.WINK_STEP * 1.3).timeout
		tick1 = int(art.get("_tick"))
	_check("窗户的拍子跟着真实时钟翻页（红线是 `_process` 没接上）",
			art != null and tick0 > 0 and tick1 > tick0,
			"第 %d 拍 → 第 %d 拍（等了 %.1f 秒）" % [
				tick0, tick1, HillRooftopArt.WINK_STEP * 1.3])
	# 下落预算里的轮半径取**车上的真值**，不写常量：轮子是活的（见文件头）。
	var r := ((car.rear_wheel.get_node("Shape") as CollisionShape2D).shape as CircleShape2D).radius
	await _settle()
	var st := {"reason": "", "max_x": -INF, "min_vx": INF, "min_vx_at": 0.0,
			"min_vx_line": "", "min_vx_idx": 0, "rims": {},
			"slow": 0, "stall": 0,
			"last_rim": Maps.SHAPE_START_CELL - 1, "log": []}
	car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	await _drive_until(target, 30.0, st, func(s: Dictionary) -> void:
		var x := car.chassis.global_position.x
		s["max_x"] = maxf(float(s["max_x"]), x)
		# 「路上最慢到了多少」从出生直道尽头起算：车就是从静止起步的，
		# 把那几帧算进去的话量到的永远是 0。爬三角形/半圆那几块屋顶时掉速最狠。
		var v := absf(car.chassis.linear_velocity.x)
		if x > HillTerrain.FLAT_LENGTH and v < float(s["min_vx"]):
			s["min_vx"] = v
			s["min_vx_at"] = x
			s["min_vx_line"] = _trace_line(car)
			s["min_vx_idx"] = (s["log"] as Array).size()
		# 「卡住」= **连续**慢，不是「某一帧慢」。撞钢梯脚那一帧必然慢
		# （见这一节的文件头），那不算卡住；撞完爬不上去、一直慢才算。
		var slow := (int(s["slow"]) + 1) if v < STALL_VX else 0
		s["slow"] = slow
		s["stall"] = maxi(int(s["stall"]), slow)
		# 每条缝**起跳那一瞬间**（车心越过缝左沿 = 屋顶右沿）记一笔速度。
		# 只记第一次：车可能被弹回来再压一趟，那一趟不算起跳。
		var rims: Dictionary = s["rims"]
		var i := int(s["last_rim"]) + 1
		while i < Maps.SHAPE_START_CELL + 40:
			var rim := float(i + 1) * CW - Maps.gap_for(SEED, Maps.ROOFTOP, i)
			if x < rim:
				break
			rims[i] = v
			s["last_rim"] = i
			i += 1
		_trace(car, s))
	var crossed := int(floor(float(st["max_x"]) / CW)) - Maps.SHAPE_START_CELL
	print("  最远 x=%.0f（跨过 %d 条缝），路上最慢 %.0f px/s（在 x=%.0f，撞钢梯脚），死因「%s」" % [
			st["max_x"], crossed, st["min_vx"], st["min_vx_at"], st["reason"]])
	print("  低于 %.0f px/s 的最长一段：%d 帧（%.2f 秒）" % [
			STALL_VX, int(st["stall"]), float(st["stall"]) / 60.0])
	_check("全油门一路开过去不会死", String(st["reason"]) == "",
			"死因「%s」，最远 x=%.0f" % [st["reason"], st["max_x"]])
	# 物理那条线：平着起跳、落点低 `d`，轮心还比落点高的时候轮子已经啃上对岸了，
	# 所以下落预算 = **这条缝自己的落差** + 轮半径。落差是每缝一条的
	# （[method Maps.drop_at]），所以滞空时间也是每条缝一个 —— **最紧的是落差最浅
	# 的那条**（`t` 最小），表里那个「需要」跟着那条缝的落差走。
	var g := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)) \
			* Maps.gravity_scale(Maps.ROOFTOP)
	var rims: Dictionary = st["rims"]
	var ids: Array = rims.keys()
	ids.sort()
	print("  起跳速度是「缝宽 ÷ 滞空」，滞空按每条缝自己的落差算（轮半径 %.1f）" % r)
	var short := 0
	var worst := INF
	var worst_at := 0
	var worst_need := 0.0
	var tightest := INF
	for i: int in ids:
		var gap := Maps.gap_for(SEED, Maps.ROOFTOP, i)
		var drop := Maps.drop_at(SEED, i)
		var t_i := sqrt(2.0 * (drop + r) / g)
		var need := gap / t_i
		var got := float(rims[i])
		print("    缝 %2d 宽 %5.1f 落差 %4.1f 滞空 %.3f 起跳 %5.0f 需要 %5.0f %s" % [
				i, gap, drop, t_i, got, need, "过" if got >= need else "**给不起**"])
		tightest = minf(tightest, t_i)
		if got - need < worst:
			worst = got - need
			worst_at = i
			worst_need = need
		if got < need:
			short += 1
	_check("跨过了 3 条缝以上", crossed >= 3,
			"跨过 %d 条（最远 x=%.0f，要过 x=%.0f）" % [crossed, st["max_x"], target])
	_check("每条缝的起跳速度都给得起（缝宽 ÷ 自己那条缝的滞空 %.3f 秒）" % tightest,
			short == 0,
			"%d 条给不起，最紧的是第 %d 条（需要 %.0f，实测 %.0f）" % [
			short, worst_at, worst_need, worst_need + worst])
	if float(st["min_vx"]) <= 200.0:
		print("  最慢那一帧：%s" % st["min_vx_line"])
	# 出事（死 / 卡住 / 有给不起的缝）才打轨迹。**这三种都是「车慢了」**，
	# 而慢在哪儿、当时什么姿态，只有轨迹答得上来 —— 上面那张表只给「差多少」。
	# 只是撞了一下钢梯脚（上面那行）不算出事，那每栋房子都会发生，轨迹没信息量。
	var stuck := int(st["stall"]) >= STALL_FRAMES
	if stuck:
		_dump_around(st, int(st["min_vx_idx"]), 10)
	_dump_trace(st, target, stuck or short > 0)
	_check("车不会被钢梯卡住（掉到 %.0f px/s 以下不许连续超过 %.1f 秒）" % [
			STALL_VX, float(STALL_FRAMES) / 60.0],
			not stuck,
			"最长连续 %d 帧（%.2f 秒）低于 %.0f px/s，最慢 %.0f px/s（在 x=%.0f）" % [
			int(st["stall"]), float(st["stall"]) / 60.0, STALL_VX,
			st["min_vx"], st["min_vx_at"]])


## 出事时能复盘：车上路之后的姿态，只留最近 [constant TRACE] 帧。
##
## 车卡住之后就**不再录**（`frozen`）：环形缓冲装的是「最近 900 帧」，而卡住之后
## 剩下的十几秒全是同一行静止的读数 —— 上一次跑就是这样，900 帧的日志里
## 「怎么卡进去的」那一帧早被冲掉了，导出来全是 `x=3121 vx=0`。
func _trace(car: HillCar, st: Dictionary) -> void:
	if bool(st.get("frozen", false)):
		return
	var stall := int(st.get("stall", 0)) + 1 \
			if absf(car.chassis.linear_velocity.x) < 20.0 else 0
	st["stall"] = stall
	if stall > 30:                       # 半秒没动 = 卡住了，这一帧不再录
		st["frozen"] = true
		return
	var log: Array = st["log"]
	log.append(_trace_line(car))
	if log.size() > TRACE:
		log.pop_front()


## 轨迹里的一行。单独拆出来是给「路上最慢那一帧」用的：那一帧可能在
## [constant TRACE] 帧的窗口之外（车跑完全程要十几秒），光靠环形缓冲会把它冲掉。
## **两个轮子都打**，还有各自轮下的地表：掉速那一下是「哪个轮子啃在哪儿」，
## 只打前轮的话爬钢梯时（前轮上了梯子、后轮还在平地上）读不出车被顶起来的原因。
func _trace_line(car: HillCar) -> String:
	var body := car.chassis
	var fx := car.front_wheel.global_position.x
	var fy := car.front_wheel.global_position.y
	var rx := car.rear_wheel.global_position.x
	var ry := car.rear_wheel.global_position.y
	return "x=%6.0f y=%6.0f 车壳 %6.1f° vx=%5.0f vy=%5.0f 前轮(%6.0f,%6.0f) 后轮(%6.0f,%6.0f) 地表(%6.0f,%6.0f,%6.0f) 着地=%s" % [
			body.global_position.x, body.global_position.y, rad_to_deg(body.rotation),
			body.linear_velocity.x, body.linear_velocity.y,
			fx, fy, rx, ry,
			_terrain.height_at(body.global_position.x), _terrain.height_at(fx),
			_terrain.height_at(rx), str(car.grounded)]


## 环形缓冲里第 `idx` 帧前后各 `span` 帧。
##
## 「掉速最狠的那一帧」在哪儿是算出来的（[member st].min_vx_idx），而掉速是**一次
## 碰撞**：碰撞前后的姿态、速度、离地高度全在相邻那几帧里，隔 8 帧一行的总表正好
## 把那一瞬间跳过去 —— 上一次跑就是只知道「在 x=1748 慢到 85」，看不出是撞在什么上。
func _dump_around(st: Dictionary, idx: int, span: int) -> void:
	var log: Array = st["log"]
	if log.is_empty() or idx >= log.size():
		return
	print("    （最慢那一帧前后各 %d 帧）" % span)
	for k in range(maxi(idx - span, 0), mini(idx + span + 1, log.size())):
		print("    %s" % [log[k]])


## 车没走完全程就把轨迹打出来 —— 「crash」/「fall」这种死因光看一个数字查不出
## 原因（是撞在缝壁上、还是落地时头朝下）。全程每 [constant TRACE_STEP] 帧一行，
## 最后 [constant TRACE_TAIL] 帧一行不漏。
##
## `force` 给「车走完了全程、但路上掉过速」那种情况用：那时候没有死因可查，
## 掉速那一下**在哪一格、姿态什么样**只能从轨迹里读出来。
func _dump_trace(st: Dictionary, stop_x: float, force := false) -> void:
	var log: Array = st["log"]
	if log.is_empty():
		return
	if not force and String(st["reason"]) == "" and float(st["max_x"]) >= stop_x:
		return
	var tail := maxi(log.size() - TRACE_TAIL, 0)
	print("  轨迹 %d 帧（每 %d 帧一行，最后 %d 帧全打）：" % [log.size(), TRACE_STEP, TRACE_TAIL])
	var i := 0
	while i < tail:
		print("    " + str(log[i]))
		i += TRACE_STEP
	for k in range(tail, log.size()):
		print("    " + str(log[k]))

# ---------------------------------------------------------------- 彩虹：平台场

## 彩虹图：**没有地表**，整张图是散在空中的平台（[method Maps.platforms_in_column]）。
##
## 用户的需求原话：「整个地图由散落在空中的一些随机圆弧彩虹和椭圆云朵构成，
## 任意彩虹、云朵不相连，且彩虹圆弧长度、朝向各异，彩虹和云朵的覆盖范围包括
## 上下 200 米使得车难以掉下去」。四句话，四条断言：
##
##   1. **任意两块不相连** —— 布局把每块平台的外接框严格缩在自己的格子里
##      （[constant Maps.EDGE_X] / [constant Maps.EDGE_Y]），而格子两两不相交，
##      所以这是**构造出来的**，不是拒绝采样撞出来的。这里两边都量：纯函数那一侧
##      对格子，**建出来的节点**那一侧对真实碰撞体的世界外接框 —— 后者连跨区块的
##      相邻也一起盖住，而且吃的是碰撞系统真正用的那份数据。
##   2. **圆弧长度各异** —— 弧长铺满 [constant Maps.ARC_LEN_LO]～HI。
##      **这一条用户为它专门来过一次**（「目前彩虹片段太短了」），所以除了「区间两端
##      都够得着」之外还钉了一条**地板**：最短的弧也得比**车的轴距**长
##      （见 [_car_wheelbase]）—— 一截比车还短的弧，两个轮子都悬在弧外，
##      看着不像路、踩着也不稳，那正是用户抱怨的那个样子。
##   3. **朝向各异** —— `tilt` 铺满一整圈：朝上的、**倒扣的**、立着的都得有。
##      用户明确选了「大幅倾斜 / 可倒扣，纯造景」，所以这一节**不检查好不好骑** ——
##      按构造大部分平台是站不住的，那是选定的效果，不是 bug。
##      这一条只对**圆弧**量：云朵是特意限在 ±[constant Maps.CLOUD_TILT] 里的，
##      混进来会把「立着的」那一栏灌满。
##   4. **覆盖上下 200 米** —— 每块平台都在 `GROUND_Y ± Maps.BAND` 里，而且带子的
##      **上下两头都有平台**，不是挤在中间一条。
func _section_arches_shape() -> void:
	print("=== 彩虹：散落在空中的平台场 ===")
	_approx("ROW_H × ROW_COUNT = 2 × BAND（带子正好铺满，不多不少半格）",
			Maps.ROW_H * float(Maps.ROW_COUNT), 2.0 * Maps.BAND, 0.001)
	# 格子宽 = 一整个区块宽 = 800。**这条不是「随便相等一下」**：区块是按
	# `index * COLS_PER_CHUNK` 去数自己的列的（[method Maps.platforms_at]），
	# 两边对不上就会「区块把自己的那一列漏掉、又建出别人的列」，而且不报错。
	_approx("格子宽 = 一个区块宽（区块数得清自己的列）",
			Maps.CELL_W, CW, 0.001)
	_approx("COLS_PER_CHUNK × CELL_W = 一个区块宽（列和区块的换算闭合）",
			float(Maps.COLS_PER_CHUNK) * Maps.CELL_W, CW, 0.001)
	# 这张图**没有地表**：`height_at` 答的是「x 上面的天花板」，区块一块地都不建
	# （0 号区块那块出生台除外）。
	_check("彩虹图不再是「有缝」的地图（它整条图都是空档）",
			not Maps.has_gaps(Maps.RAINBOW), "has_gaps = true")
	_check("彩虹图的 feature 是 FEATURE_NONE（云朵是平台，不是特殊地形）",
			Maps.get_map(Maps.RAINBOW)["feature"] == Maps.FEATURE_NONE,
			str(Maps.get_map(Maps.RAINBOW)["feature"]))
	_check("彩虹图有自己的 gimmick 文案（地图卡片不会掉回「标准地形」）",
			Maps.get_map(Maps.RAINBOW).has("gimmick"), "没有 gimmick 键")

	_platform_map(3)

	# —— 布局层（纯函数，扫得宽一点）——
	var kinds := {Maps.PLATFORM_RAINBOW: 0, Maps.PLATFORM_CLOUD: 0}
	var rows_hit := {}
	var lens: Array = []
	var spans: Array = []
	var radii: Array = []
	var arc_tilts: Array = []
	var cloud_tilts: Array = []
	var cloud_w: Array = []
	var floor_dy := -INF
	var ceil_dy := INF
	var outside := 0
	for col in range(PLATFORM_COL0, PLATFORM_COL0 + PLATFORM_COLS):
		for p in Maps.platforms_in_column(SEED, col):
			var kind := String(p["kind"])
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			# **行号按外接框的中心算，不按平台自己的中心**：彩虹 `dy` 是圆心，
			# 圆心可能落在相邻那半格里（弧在格子里的位置由 `off` 定）。
			# 用圆心分行会把这朵花记到错的格子里，然后「每一行都有平台」就是个假结论。
			var box_dy := float(p["dy"]) + float(p["off"].y)
			floor_dy = maxf(floor_dy, box_dy)
			ceil_dy = minf(ceil_dy, box_dy)
			rows_hit[int(floor((box_dy + Maps.BAND) / Maps.ROW_H))] = \
					int(rows_hit.get(int(floor((box_dy + Maps.BAND) / Maps.ROW_H)), 0)) + 1
			# 「每块都在带子里」：外接框整个落在 ±BAND 之间，不只看中心。
			if box_dy - Maps.half_height(p) < -Maps.BAND - 0.01 \
					or box_dy + Maps.half_height(p) > Maps.BAND + 0.01:
				outside += 1
			if kind == Maps.PLATFORM_CLOUD:
				cloud_w.append(float(p["w"]))
				cloud_tilts.append(float(p["tilt"]))
			else:
				lens.append(float(p["len"]))
				spans.append(float(p["span"]))
				radii.append(float(p["r"]))
				arc_tilts.append(float(p["tilt"]))
	var cells := PLATFORM_COLS * Maps.ROW_COUNT
	var got := int(kinds[Maps.PLATFORM_RAINBOW]) + int(kinds[Maps.PLATFORM_CLOUD])
	var fill := float(got) / float(cells)
	var rainbow_share := float(kinds[Maps.PLATFORM_RAINBOW]) / float(got)
	print("  %d 列 × %d 行 = %d 格：摆了 %d 块（填充率 %.3f，期望 %.2f）；彩虹 %d / 云 %d（%.2f）" % [
			PLATFORM_COLS, Maps.ROW_COUNT, cells, got, fill, Maps.FILL,
			kinds[Maps.PLATFORM_RAINBOW], kinds[Maps.PLATFORM_CLOUD], rainbow_share])
	print("  用到的行 %d / %d 行（第 %d～%d 行）；平台中心 dy %.0f～%.0f（带子是 ±%.0f）" % [
			rows_hit.size(), Maps.ROW_COUNT, int(_low(rows_hit.keys())), int(_high(rows_hit.keys())),
			ceil_dy, floor_dy, Maps.BAND])
	_check("填充率在 FILL 上下 5% 里", absf(fill - Maps.FILL) < 0.05,
			"%.3f（期望 %.2f）" % [fill, Maps.FILL])
	_check("彩虹和云朵都有，比例在 RAINBOW_SHARE 上下 8% 里",
			absf(rainbow_share - Maps.RAINBOW_SHARE) < 0.08,
			"%.2f（期望 %.2f）" % [rainbow_share, Maps.RAINBOW_SHARE])
	_check("每块平台的外接框整个都在 ±200 米的带子里", outside == 0,
			"%d 块探出带子" % outside)
	# 「覆盖上下 200 米」：每一行都得有东西 —— 少一行就是一条横着贯穿全图的空档，
	# 车从那儿往下掉是**一路掉到底**（10 行里少一行，概率上每次都会撞上）。
	_check("带子的每一行都有平台（没有横贯全图的空行）",
			rows_hit.size() == Maps.ROW_COUNT, "只用到 %d / %d 行" % [
					rows_hit.size(), Maps.ROW_COUNT])
	_check("带子上下两头都有平台（不是挤在中间一条）",
			int(rows_hit.get(0, 0)) > 0 and int(rows_hit.get(Maps.ROW_COUNT - 1, 0)) > 0,
			"第 0 行 %d 块，第 %d 行 %d 块" % [int(rows_hit.get(0, 0)),
					Maps.ROW_COUNT - 1, int(rows_hit.get(Maps.ROW_COUNT - 1, 0))])

	# 「圆弧长度各异」：两端都要够着区间边界 —— 只断言「不止一种」的话，
	# 全都挤在区间正中间也能过，那看着一点也不「各异」。
	print("  圆弧：弧长 %.0f～%.0f 像素（区间 %.0f～%.0f）；张角 %.2f～%.2f 弧度（区间 %.2f～%.2f）" % [
			_low(lens), _high(lens), Maps.ARC_LEN_LO, Maps.ARC_LEN_HI,
			_low(spans), _high(spans), Maps.ARC_SPAN_LO, Maps.ARC_SPAN_HI])
	print("  半径因此是推出来的：%.0f～%.0f 像素（张角越小、同样长的弧半径越大）" % [
			_low(radii), _high(radii)])
	_check("短的那一端够得着 ARC_LEN_LO", _low(lens) < Maps.ARC_LEN_LO + 20.0,
			"最短 %.0f 像素" % _low(lens))
	# **长的那一端不能按 ARC_LEN_HI 直接卡。** [constant Maps.ARC_LEN_HI] 故意定在
	# 「任意朝向都塞得下」那条线（776）**之上**，超过的那一批会被对分按当次朝向
	# 压到 776～1070 —— 所以实测的最长值必然低于 ARC_LEN_HI，这不是 bug。
	# 要卡的是**它确实比旧的那一档长得多**：旧上限 400，翻 3 倍是 1200，
	# 而格子能给到的天花板在 1070 上下，所以「超过 950」是个够紧又过得去的线。
	_check("最长的那一批远超旧上限（格子确实撑住了更长的弧）",
			_high(lens) > 950.0, "最长 %.0f 像素（旧的 ARC_LEN_HI 是 400）" % _high(lens))
	# **用户抱怨过的那两条**（「目前彩虹片段太短了」→「再加长 3 倍」）。轴距是活的
	# 车参数，见 [method _print_car_params]；一截比轴距还短的弧，两个轮子都架不到弧上。
	print("  最短的弧 %.0f 像素、中位 %.0f 像素；车的轴距 %.0f 像素" % [
			_low(lens), _median(lens), _car_wheelbase])
	_check("最短的弧比车的轴距长（一截比车还短的弧不算路）",
			_low(lens) > _car_wheelbase, "最短 %.0f vs 轴距 %.0f" % [
					_low(lens), _car_wheelbase])
	_check("中位数的弧至少四倍轴距（一段弧上放得下整台车还有富余）",
			_median(lens) > _car_wheelbase * 4.0,
			"中位 %.0f vs 轴距 %.0f" % [_median(lens), _car_wheelbase])
	_check("张角铺得开（最短的那一端够得着 ARC_SPAN_LO）",
			_low(spans) < Maps.ARC_SPAN_LO + 0.15, "最短 %.2f 弧度" % _low(spans))
	_check("张角铺得开（最长的那一端够得着 ARC_SPAN_HI）",
			_high(spans) > Maps.ARC_SPAN_HI - 0.15, "最长 %.2f 弧度" % _high(spans))
	print("  云朵宽 %.0f～%.0f 像素（区间 %.0f～%.0f）；倾角 %.3f～%.3f 弧度（上限 ±%.2f）" % [
			_low(cloud_w), _high(cloud_w), Maps.CLOUD_W_LO, Maps.CLOUD_W_HI,
			_low(cloud_tilts), _high(cloud_tilts), Maps.CLOUD_TILT])
	# 容差 50 不是随手放的：云朵只有 `RAINBOW_SHARE` 那一份（实测 67 朵），
	# 宽度在 560 像素的区间里均匀取，67 个样本的最大值离上限平均还差
	# `560 / 68 ≈ 8` 像素，但**尾部很长** —— 卡 20 的话换个常量就会假红。
	_check("云朵的宽度铺得开", _low(cloud_w) < Maps.CLOUD_W_LO + 50.0 \
			and _high(cloud_w) > Maps.CLOUD_W_HI - 50.0,
			"%.0f～%.0f" % [_low(cloud_w), _high(cloud_w)])
	# **用户第四轮的原话：「云朵目前没有支撑作用」「云朵支撑不了车」。**
	#
	# 这不是手感问题，是**几何上就托不住**：云朵曾经是 110～340 宽，而车的轮距是
	# [member _car_span] —— 110 的云比车还短，两个轮子一个在云上、一个在空中，
	# 车当然站不住（按均匀分布算，有三分之一还多的云比车短）。
	# 这和「彩虹片段太短了」是同一类毛病，只是尺子从**弧长 vs 车长**换成了
	# **板宽 vs 轮距**。所以这里钉的不是「宽不宽」，是**最短的那朵也得站得下整台车**。
	print("  最短的云 %.0f 像素、中位 %.0f 像素；车的轮距 %.0f 像素" % [
			_low(cloud_w), _median(cloud_w), _car_span])
	_check("最短的云也比车的轮距宽（不然两个轮子架不到一块板上）",
			_low(cloud_w) > _car_span, "最短 %.0f vs 轮距 %.0f" % [
					_low(cloud_w), _car_span])
	_check("中位数的云至少两倍轮距（站得下还有地方挪）",
			_median(cloud_w) > _car_span * 2.0,
			"中位 %.0f vs 轮距 %.0f" % [_median(cloud_w), _car_span])

	# 「朝向各异」。**弧中点的方向就是 `tilt`**：sin < 0 是朝上（像个山包），
	# sin > 0 是**倒扣**（像个碗）。用户要的是「大幅倾斜 / 可倒扣」，
	# 所以这里要的是「两种都有、而且立着的也有」，不是「都是朝上的」。
	var arcs := arc_tilts.size()
	var up := 0
	var down := 0
	var on_side := 0
	for a: float in arc_tilts:
		var s := sin(a)
		if s < -0.5:
			up += 1
		elif s > 0.5:
			down += 1
		if absf(s) < 0.5:
			on_side += 1
	var sorted_tilts := arc_tilts.duplicate()
	sorted_tilts.sort()
	var gap := TAU - float(sorted_tilts[arcs - 1]) + float(sorted_tilts[0])
	for k in range(1, arcs):
		gap = maxf(gap, float(sorted_tilts[k]) - float(sorted_tilts[k - 1]))
	print("  朝向：朝上 %d（%.0f%%）、倒扣 %d（%.0f%%）、立着 %d（%.0f%%）；" % [
			up, 100.0 * float(up) / float(arcs), down, 100.0 * float(down) / float(arcs),
			on_side, 100.0 * float(on_side) / float(arcs)])
	print("  一圈里最大的空档 %.2f 弧度（整圈 %.2f；均匀分布时约 %.2f）" % [
			gap, TAU, TAU * log(float(arcs)) / float(arcs)])
	_check("确实有朝上的弧（不是全都倒扣）", up > arcs / 8, "%d 块朝上" % up)
	_check("确实有**倒扣**的弧（用户要的「可倒扣」）", down > arcs / 8, "%d 块倒扣" % down)
	_check("确实有立着的弧（弧平面接近竖直）", on_side > arcs / 8, "%d 块立着" % on_side)
	_check("倾角铺满一整圈（最大的空档 < 0.4 弧度）", gap < 0.4, "%.2f 弧度" % gap)

	# —— 节点层：拿**真实碰撞体**两两对一遍 ——
	_setup(Maps.RAINBOW, PROBE_CHUNK)
	var nodes: Array[HillPlatform] = []
	var boxes: Array[Rect2] = []
	var hollow: Array = []
	var built := 0
	var any_lo := INF
	var any_hi := -INF
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + NODE_CHUNKS):
		var list := _platforms_in(i)
		if list.is_empty():
			continue
		built += 1
		for p in list:
			var r := _platform_rect(p)
			nodes.append(p)
			boxes.append(r)
			any_lo = minf(any_lo, r.position.y)
			any_hi = maxf(any_hi, r.end.y)
			# **每一块平台都得真的进物理空间。** 这一条防的是一整类错误，不是某一处：
			# [CollisionShape2D] / [CollisionPolygon2D] 只跟**直接父节点**登记，父节点
			# 不是 [CollisionObject2D] 时它一个形状都不往物理服务器上交 —— 不报错、
			# 不进树，只是**没有碰撞**。云朵就是这么错的：车从云中间穿过去，
			# 而节点树看着完全正常（在树里、没 disabled、形状和尺寸都对）。
			#
			# 所以判据只问物理服务器，不问节点树长什么样。彩虹这一半是好的，
			# 正是它把「层 / 掩码 / 位置都对，云却拦不住车」这件事衬出来的。
			var shapes := PhysicsServer2D.body_get_shape_count(p.get_rid())
			if shapes < 1:
				hollow.append("%s@x%.0f" % [p.name, p.position.x])
	_check("建出来足够的区块来量（太少就说明地形根本没建）", built >= 3,
			"只建出 %d 块区块" % built)
	_check("每块平台的碰撞体都真的进了物理空间（不是只有一块画出来的）",
			hollow.is_empty(), "%d 块是空壳：%s" % [hollow.size(), ", ".join(PackedStringArray(hollow))])
	if built >= 3:
		var worst := INF
		var worst_at := ""
		var touching := 0
		for a in nodes.size():
			for b in range(a + 1, nodes.size()):
				var sep := _rect_sep(boxes[a], boxes[b])
				if sep <= 0.0:
					touching += 1
				if sep < worst:
					worst = sep
					worst_at = "%s / %s" % [nodes[a].name, nodes[b].name]
		print("  %d 块平台的碰撞体两两对了一遍（%d 对）：最近的一对隔 %.2f 像素（%s）" % [
				nodes.size(), nodes.size() * (nodes.size() - 1) / 2, worst, worst_at])
		_check("任意两块平台都不相连（最近的一对也隔着 20 像素以上）",
				touching == 0 and worst >= 19.9,
				"贴着的有 %d 对；最近只隔 %.2f 像素" % [touching, worst])
		print("  平台的碰撞体外接框跨 y %.0f～%.0f；带子是 %.0f～%.0f" % [
				any_lo, any_hi, HillTerrain.GROUND_Y - Maps.BAND,
				HillTerrain.GROUND_Y + Maps.BAND])
		_check("每块平台都在 ±200 米的带子里（顶不出上沿、掉不出下沿）",
				any_lo >= HillTerrain.GROUND_Y - Maps.BAND - 0.01 \
				and any_hi <= HillTerrain.GROUND_Y + Maps.BAND + 0.01,
				"%.0f～%.0f" % [any_lo, any_hi])
		# `height_at` 在这张图上答的是「x 上面的天花板」—— 拿建出来的节点对一遍：
		# 相机取景、道具落点、[method HillTerrain.skyline_at] 全建在这个结论上。
		#
		# **比的是「同一列」，不是「盖住这个 x」。** [method Maps.ceiling_dy_at] 只查
		# `floor(x / CELL_W)` 那一列，答的是那一列里最高的平台 —— 这是有意的：
		# 格子之间留着 [constant Maps.EDGE_X] = 12 像素的缝，所以有些 x **谁都不盖**，
		# 但「这一列上面的天花板有多高」照样有答案，相机和道具要的也正是后者。
		# 早先这条断言要求平台的外接框真的盖住 x，于是采样点落进缝里（x = 2003，
		# 第 4 列的外接框止于 1988、第 5 列从 2012 起）就判「上面没有平台」，
		# 拿 `GROUND_Y + BAND` 去比，差出 3800 多像素 —— 是断言写窄了，不是代码错了。
		#
		# 列号由外接框自己反推（`floor(左沿 / CELL_W)` 到 `floor(右沿 / CELL_W)`），
		# 而不是拿平台中心的列号加一减一 —— 长弧横跨两三列是常事。
		var col_top := {}
		for k2 in nodes.size():
			var rr := boxes[k2]
			var c0 := int(floor(rr.position.x / Maps.CELL_W))
			var c1 := int(floor((rr.end.x - 0.01) / Maps.CELL_W))
			for c in range(c0, c1 + 1):
				col_top[c] = minf(col_top.get(c, INF), rr.position.y)
		var worst_ceil := 0.0
		var worst_x := 0.0
		for k in 40:
			var x := float(Maps.SHAPE_START_CELL + 1) * CW + float(k) * 20.0 + 3.0
			var col := int(floor(x / Maps.CELL_W))
			var want: float = col_top.get(col, HillTerrain.GROUND_Y + Maps.BAND)
			var d := absf(_terrain.height_at(x) - want)
			if d > worst_ceil:
				worst_ceil = d
				worst_x = x
		_check("height_at = 「x 上面的天花板」（相机和道具全建在这条上）",
				worst_ceil < 0.01, "最大差 %.4f 像素（在 x=%.0f）" % [worst_ceil, worst_x])

	# 出生台：全图唯一一块真地。没它的话车一出生就在空中。
	#
	# **得换个探针位置**：上面那次建的是 `PROBE_CHUNK` 前后那几块，0 号区块不在窗口里。
	# 探针摆到 `SHAPE_START_CELL` 上，窗口就盖住了 0 号。
	_setup(Maps.RAINBOW, Maps.SHAPE_START_CELL)
	var pad := _chunk_node(0)
	var pad_body := pad.get_node_or_null("Ground") if pad != null else null
	var pad_poly := pad_body.get_child(0) as CollisionPolygon2D if pad_body != null else null
	# 出生台面**比 `GROUND_Y` 高半行**（[constant Maps.PAD_DY]）。这一条不是可有可无的
	# 装饰：彩虹图的平台格子是从带子顶往下排的，出生台要是压在 `GROUND_Y` 上，
	# 中间那一行就骑在车的胸口，车一冲出去先撞的是平台的**侧面**。
	# 详见 [constant Maps.PAD_DY] 那段。
	var pad_y := HillTerrain.GROUND_Y + Maps.PAD_DY
	print("  0 号区块：%s；height_at(200) = %.1f（出生台面该在 %.1f，GROUND_Y = %.1f）" % [
			"有出生台" if pad_body != null else "**没有出生台**",
			_terrain.height_at(200.0), pad_y, HillTerrain.GROUND_Y])
	_check("0 号区块铺着出生台（车得有个地方出生）", pad_body != null, "Chunk0/Ground 不在")
	_approx("出生台上 `height_at` 就是出生台面（车坐在实地上）",
			_terrain.height_at(200.0), pad_y, 0.001)
	var first := _platforms_in(0)
	_check("0 号区块里没有平台（出生台是整块地，不是平台）", first.is_empty(),
			"摆了 %d 块" % first.size())
	# **出生台的右沿不许立起一道墙。** 这是实测逮住过的一个 bug：地块多边形
	# 一路采到 `x = 800`（区块右沿，`CHUNK_POINTS + 1` 是闭区间），而 `height_at`
	# 在那一刻从 `GROUND_Y` 变成「天花板」，最后一个顶点于是跳到天上两千像素，
	# 连成一道看不见的竖墙 —— 车开过去撞停在 x = 696，整张图玩不了。
	# 所以这里不只看 `height_at`，还要看**多边形里真正写进去的那些顶点**。
	if pad_poly != null:
		# **只数地表那一段顶点**（前 [constant HillTerrain.CHUNK_POINTS] + 1 个）：
		# 后面的两个是绕到底部收口的角，y 本来就该在下面。
		var pad_lo := INF
		var pad_hi := -INF
		for k in mini(pad_poly.polygon.size(), HillTerrain.CHUNK_POINTS + 1):
			pad_lo = minf(pad_lo, pad_poly.polygon[k].y)
			pad_hi = maxf(pad_hi, pad_poly.polygon[k].y)
		print("  出生台地表 %d 个顶点：y %.1f～%.1f（台面 %.1f）" % [
				mini(pad_poly.polygon.size(), HillTerrain.CHUNK_POINTS + 1),
				pad_lo, pad_hi, pad_y])
		_approx("出生台的地表顶点全在台面上（右沿没有立起来的墙）",
				pad_lo, pad_y, 0.01)
		_approx("出生台的地表顶点全在台面上（没有突然塌下去的）",
				pad_hi, pad_y, 0.01)

	# **没有任何一块平台横跨出生台的高度。** 上面那两条钉的是「出生台自己是不是平的」，
	# 这条钉的是「出生台**旁边**有没有东西挡路」—— 是另一个 bug，而且要跑起来才看得见。
	#
	# 车从出生台右沿飞出去时是**水平**的（实测 vx = 935、vy ≈ 0），高度就在台面上。
	# 一块平台要是上沿在台面之上、下沿在台面之下，它对着车的就是**侧面**，
	# 车撞上去会被原速弹回来（实测 vx 从 +908 一帧之内变成 −72，车翻着跟头掉出带子）。
	# 平台按构造缩在自己的格子里，所以「横跨」只可能发生在**台面所在的那一行**；
	# 但这一行是哪一行、行沿在哪，是 [constant Maps.PAD_DY] 和 [constant Maps.ROW_H]
	# 两个数的事 —— 改了任何一个，这里就得重算，所以直接拿所有平台量，不重算行号。
	var straddle: Array = []
	for col in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + PLATFORM_COLS):
		for p in Maps.platforms_in_column(SEED, col):
			var top: float = HillTerrain.GROUND_Y + float(p["dy"]) + float(p["off"].y) \
					- float(p["half"].y)
			var bottom: float = HillTerrain.GROUND_Y + float(p["dy"]) + float(p["off"].y) \
					+ float(p["half"].y)
			if top < pad_y and bottom > pad_y:
				straddle.append("%s@x%.0f y%.0f～%.0f" % [p["kind"], p["x"], top, bottom])
	print("  跨出生台高度（y = %.1f）的平台：%d 块%s" % [
			pad_y, straddle.size(),
			"" if straddle.is_empty() else "  " + ", ".join(straddle.slice(0, 4))])
	_check("没有平台横跨出生台的高度（不然车一冲出去撞的是它的侧面）",
			straddle.is_empty(), "%d 块横跨，头一块 %s" % [
					straddle.size(), straddle[0] if not straddle.is_empty() else "-"])


## 平台场的 ASCII 图：横轴 20 像素一格（和 [constant HillTerrain.POINT_SPACING] 同），
## 纵轴把整条 4000 像素的带子分成 40 行（一行 100 像素）。`*` = 圆弧彩虹，`o` = 云朵。
##
## 「散落」这件事数字断言看不出来 —— 挤成一团、排成整齐的格子、全糊在上半张，
## 三种都能让上面那些区间断言全过。用字符看最快。
##
## 注意**每一格只画一个字符**，而格子是 400 像素宽、100 像素高 —— 一块 300 像素长的弧
## 在这张图上是一个点。这张图看的是「分布」，不是「尺寸」。
func _platform_map(cols_wanted: int) -> void:
	var cols := cols_wanted * 40
	var rows := 40
	var col_px := CW / 40.0
	var row_px := 2.0 * Maps.BAND / float(rows)
	var cells: Array = []
	for r in rows:
		var line := PackedStringArray()
		for c in cols:
			line.append(" ")
		cells.append(line)
	var origin := float(PLATFORM_COL0) * Maps.CELL_W
	for col in range(PLATFORM_COL0, PLATFORM_COL0 + cols_wanted * 2):
		for p in Maps.platforms_in_column(SEED, col):
			var c := int(floor((float(p["x"]) - origin) / col_px))
			var r := int(floor((float(p["dy"]) + float(p["off"].y) + Maps.BAND) / row_px))
			if c < 0 or c >= cols or r < 0 or r >= rows:
				continue
			cells[r][c] = "*" if String(p["kind"]) == Maps.PLATFORM_RAINBOW else "o"
	print("=== 彩虹平台场（横轴 %d 像素、纵轴 %.0f 像素一格；`*` 弧、`o` 云）===" % [
			int(col_px), row_px])
	print("  ↑ 上沿 dy = %.0f（第 0 行）      ↓ 下沿 dy = +%.0f（第 %d 行）" % [
			-Maps.BAND, Maps.BAND, rows - 1])
	for r in rows:
		print("  |" + "".join(cells[r]) + "|")
	print("  " + "-".repeat(cols + 2))


## 两个矩形之间的**轴向间距**：不相交时是正的（两条轴上取大的那个），相交时 ≤ 0。
## 布局保证相邻两格里最靠近的两块至少隔着 2 × [constant Maps.EDGE_Y]（同一列上下相邻）
## 或 2 × [constant Maps.EDGE_X]（同一行左右相邻），也就是 20 像素 —— 这里就卡这个数。
func _rect_sep(a: Rect2, b: Rect2) -> float:
	return maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x),
			maxf(b.position.y - a.end.y, a.position.y - b.end.y))


## 一组倾角里 |tilt| 的最大值（云朵的倾角上限是 ±[constant Maps.CLOUD_TILT]）。
func _tilt_max(tilts: Array) -> float:
	var most := 0.0
	for a: float in tilts:
		most = maxf(most, absf(a))
	return most


# ---------------------------------------------------------------- 彩虹：云朵

## 云朵平台：**斜着放**，踩上去按它自己的寿命消散。
##
## 两件事在这一节里落地：
##
##  · **斜置**（[constant Maps.CLOUD_TILT]）：这张图没有跳跃键，而不相连的平台之间
##    恒有空档 —— 平放的一块板只能把车送下去，送不上去。云是**唯一的上行手段**：
##    车沿着斜面爬上去、从高的一头甩出去，落点才比起点高。这里量的是「碰撞体和
##    布局给的是同一个倾角」——斜了但碰撞体没斜的话，看着踩在云上、人已经掉下去了。
##  · **寿命跟着长度**（用户拧过三轮的 [constant HillPlatform.LIFE_PER_PX]）：
##    早一点散的话玩家明明踩着云却掉下去，晚一点散云已经化掉了人还站在上面。
##    **下面一律拿这一朵自己的寿命做基准去量**，不是某个写死的秒数 ——
##    用户把每像素的秒数拧过三轮（1/250 → 1/375 → 0.7/375），
##    凡是写死秒数的断言都会在下一轮被拧废。
func _section_arches_cloud() -> void:
	print("=== 彩虹：云朵斜着放、踩上去按自己的寿命消散 ===")
	# 先看一批云的尺寸和寿命（纯函数，不用建地形）。
	var widths: Array = []
	var lives: Array = []
	var tilts: Array = []
	for col in range(PLATFORM_COL0, PLATFORM_COL0 + PLATFORM_COLS):
		for p in Maps.platforms_in_column(SEED, col):
			if String(p["kind"]) != Maps.PLATFORM_CLOUD:
				continue
			var w := float(p["w"])
			var a := float(p["tilt"])
			widths.append(w)
			tilts.append(a)
			# 和 [method HillPlatform._build_cloud] 同一个式子：寿命按**斜面长**
			# 算，不按投影宽 —— 斜置是为了让车能上去，不是为了加难度。
			lives.append(w / cos(a) * HillPlatform.LIFE_PER_PX)
	var short_life := _low(lives)
	var long_life := _high(lives)
	print("  %d 朵云：宽 %.0f～%.0f 像素；倾角 %.3f～%.3f 弧度（±%.2f）；寿命 %.2f～%.2f 秒" % [
			widths.size(), _low(widths), _high(widths), _low(tilts), _high(tilts),
			Maps.CLOUD_TILT, short_life, long_life])
	_check("每朵云都是**斜的**（平放的云在这张图上是死路，一朵都不该有）",
			_low(tilts) <= -Maps.CLOUD_TILT + 0.01 and _high(tilts) >= Maps.CLOUD_TILT - 0.01,
			"倾角只到 %.3f～%.3f" % [_low(tilts), _high(tilts)])
	_check("云朵的倾角不超过 CLOUD_TILT（再陡就不像云了，也爬不动）",
			_tilt_max(tilts) <= Maps.CLOUD_TILT + 0.001,
			"最大 %.3f 弧度（≈%.1f°）" % [_tilt_max(tilts), rad_to_deg(_tilt_max(tilts))])
	# 「成正比」拿最长和最短两朵比：长度比和寿命比必须**一模一样**。
	# 只断言「长的活得久」的话，写成 `1.0 + 长度/1000` 也能过 —— 那不是正比。
	if widths.size() < 2:
		_check("云朵够多，量得下去", false, "只有 %d 朵" % widths.size())
		return
	var k_lo := 0
	var k_hi := 0
	for k in widths.size():
		if float(lives[k]) < float(lives[k_lo]):
			k_lo = k
		if float(lives[k]) > float(lives[k_hi]):
			k_hi = k
	var want_ratio := float(widths[k_hi]) / cos(float(tilts[k_hi])) \
			/ (float(widths[k_lo]) / cos(float(tilts[k_lo])))
	_check("消失时间与斜面长成正比（最长/最短的长度比 = 寿命比）",
			absf(want_ratio - float(lives[k_hi]) / float(lives[k_lo])) < 1e-6,
			"长度比 %.3f" % want_ratio)

	# 建出来，挑一朵**斜得最轻**的云给车踩。
	#
	# 挑最平的，是为了让「云散了车就掉下去」这条断言量的是云本身 —— 斜得厉害的
	# 云上，车本来就自己往下滑，那条断言会变成空转。这只影响测谁，不影响玩法。
	_setup(Maps.RAINBOW, PROBE_CHUNK)
	var pick: HillPlatform = null
	var pick_flat := INF
	var clouds := 0
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + NODE_CHUNKS):
		for p in _platforms_in(i):
			if p.kind != HillPlatform.Kind.CLOUD:
				continue
			clouds += 1
			var a := absf(p.var_tilt())
			if a < pick_flat:
				pick_flat = a
				pick = p
	_check("建出来的区块里有云朵平台", pick != null, "一块都没有（共 %d 块平台）" % clouds)
	if pick == null:
		return
	# **碰撞体必须是平台节点的直接孩子。** 挂在中间的 `Node2D` 底下的话，
	# [CollisionShape2D] 不跟它登记 —— 节点树看着完全正常（在树里、没 disabled、
	# 形状和尺寸都对），物理服务器那边却一个形状都没收到。上一版就是这么错的：
	# 车从云中间穿过去，而感知区照旧工作（那个碰撞体的爹就是 Area2D 自己），
	# 于是倒计时照常开始、云照常变淡 —— 一路上云看起来都是好的。
	var cs := pick.get_node_or_null("Shape") as CollisionShape2D
	_check("云的碰撞体是平台节点的直接孩子（挂在中间的 Node2D 底下就不登记了）",
			cs != null, "Shape 不是直接孩子")
	if cs == null:
		return
	var box := cs.shape as RectangleShape2D
	# **这一条才是真的在问「云硬不硬」。** 上面那条只说节点挂对了地方；
	# 形状到底有没有交到物理服务器手上，只有问物理服务器才知道。
	_check("云的碰撞体真的进了物理空间（不是只有一块画出来的云）",
			PhysicsServer2D.body_get_shape_count(pick.get_rid()) >= 1,
			"物理服务器里 0 个形状 —— 车会直接穿过去")
	# 云自己记着布局给的那个倾角 —— 和碰撞体上真正生效的是同一个数。
	_approx("倾角转在平台节点自己身上（看着踩在云上，碰撞体也在那儿）",
			pick.rotation, pick.var_tilt(), 1e-6)
	_check("云在层 2 且进了 \"ground\" 组（踩上去算着地）",
			pick.collision_layer == 2 and pick.is_in_group("ground"),
			"层 %d，在组里 = %s" % [pick.collision_layer, pick.is_in_group("ground")])
	_check("云是一块扁板（宽高比够扁才像云）", box.size.y == HillPlatform.CLOUD_H \
			and box.size.x > box.size.y * 2.0,
			"%.0f × %.0f" % [box.size.x, box.size.y])
	var real_w := box.size.x
	var life := pick.var_life()
	_approx("寿命 = 斜面长 × 每像素的秒数",
			life, real_w / cos(pick.rotation) * HillPlatform.LIFE_PER_PX, 1e-4)
	print("  挑中的云：宽 %.0f、倾角 %.3f 弧度（≈%.1f°）、寿命 %.2f 秒；位置 (%.0f, %.0f)" % [
			real_w, pick.rotation, rad_to_deg(pick.rotation), life,
			pick.position.x, pick.position.y])

	# 把车摆在这朵云的**顶面中点**上。斜着的板，顶面中点是它中线上的那一点：
	# 局部 `(0, -CLOUD_H / 2)` 转过来就是 `(sin·H/2, -cos·H/2)`。
	var top := pick.position + Vector2(sin(pick.rotation), -cos(pick.rotation)) \
			* (HillPlatform.CLOUD_H * 0.5)
	var car := _spawn_car(Maps.RAINBOW, pick.position.x, top.y - CAR_LIFT)
	await _frames(3)
	_check("车踩上去之后计时开始了", pick.var_timer() >= 0.0, "timer = %.3f" % pick.var_timer())
	# 摆上去之后再盯 12 帧：车必须**还架在云上**。
	#
	# **这条和上面那条是两件事，上一版就是因为只有上面那条才漏过去的**：
	# 「感知区探到车」走的是 Area2D 的碰撞体，「云撑得住车」走的是刚体的碰撞体，
	# 两套互不相干。刚体碰撞体没登记的时候倒计时照常开始 —— 车一边沉一边看着
	# 云在变淡，正是用户报的「掉到云朵上还是会下沉」。
	#
	# 量的是**云的局部坐标**，所以不管这朵云斜多少度，判据都是同一条：
	# 车壳最低不许沉到板子中线以下。
	var slab_mid := -HillPlatform.CLOUD_H * 0.5
	var sunk := -INF
	for _i in 12:
		await _frames(1)
		sunk = maxf(sunk, pick.to_local(car.chassis.global_position).y)
	_check("车摆上去之后没有往下沉（云真的撑得住车）", sunk < slab_mid,
			"车壳最低沉到云的局部 y = %.1f，板子中线在 %.1f" % [sunk, slab_mid])
	# 还剩下六成寿命：云必须还是硬的，同时应该在变淡（玩家看得见还剩多久）。
	await _frames(int(round(life * 0.4 / DT)))
	_check("倒计时里云还在（层还是 2）", pick.collision_layer == 2,
			"层 %d，timer %.3f" % [pick.collision_layer, pick.var_timer()])
	_check("倒计时里云在变淡（玩家看得见还剩多久）", pick.var_visual().modulate.a < 1.0,
			"透明度 %.2f" % pick.var_visual().modulate.a)
	# 寿命之后再过一点点：断。
	#
	# **窗口很窄，所以按寿命正着算，不写死比例**：`_break` 落在 `life` 那一刻，
	# 节点在 `life + FADE_TIME` 就被拆了 —— 「层归 0」只在这 0.3 秒里查得到。
	# 上面已经等掉的那些帧要一起算进来，否则这一条会查到一个**已经释放**的节点
	# （之前那个 `life * 0.7` 就正好落在窗口外面，靠的是「车没真的站上去、
	# 云的寿命早被消耗掉一部分」才勉强对上的）。
	var waited := 15.0 * DT + float(int(round(life * 0.4 / DT))) * DT
	await _frames(int(round(maxf(life + 0.1 - waited, 0.05) / DT)))
	# 提示里不碰 `pick` 的字段：它可能已经释放了，而 `_check` 的第三个参数
	# 是**先求值再传进去**的，写 `pick.var_broken()` 的话连失败信息都打不出来。
	_check("寿命走完之后云断了（层归 0）",
			is_instance_valid(pick) and pick.collision_layer == 0,
			"节点还在 = %s" % str(is_instance_valid(pick)))
	# 断了之后车就往下掉 —— 这朵云是脚下唯一架着的东西。
	var y0 := car.chassis.global_position.y
	await _frames(int(round(0.9 / DT)))
	_check("云散了车就掉下去了", car.chassis.global_position.y > y0 + 40.0,
			"下落 %.0f 像素" % (car.chassis.global_position.y - y0))
	await _frames(int(round(0.5 / DT)))
	_check("淡出之后云整个拆掉了",
			not is_instance_valid(pick), "节点还在" if is_instance_valid(pick) else "已释放")


# ---------------------------------------------------------------- 彩虹：真地形开过去

## 全油门从出生台开出去：落到平台上，然后看它能走多远。
##
## **这一节量的是「这张图能不能玩」，不是「一定能通关」。** 用户选的就是
## 「二维散布成网」——落点是随机的，掉到哪一块全看运气，偶尔一路掉到带子底下
## 判死也是这套设计接受的结果（[_section_arches_fall] 单独验那条死线）。
##
## 所以断言只有三条，而且都是**结构性**的：
##
##  · 开出去之后**落到过平台上**（着地的上升沿 ≥ 3 次）—— 一路掉到底的话
##    这一条会红，而「落点看运气」不至于连三次都接不住；
##  · 跑够一段距离（进得去平台场，而不是卡在出生台边上）；
##  · **不是一路掉出平台带** —— 带子底下两千米全是平台，真的掉出去了说明
##    太稀，那才是设计坏了。
##
## **「翻车摔死」不算失败。** 平台是乱摆的，四成还是立着或倒扣的，落点稍偏
## 就是头着地（[constant HillCar.REASON_CRASH]）。这一条早先写成「不许死」，
## 实测每回都在开出出生台几秒后翻掉 —— 卡住它等于禁止用户选的那套设计。
## 死因照原样打出来，真出了「刚出出生台就死」的回归，落点次数会先红。
##
## 另外打两个读数：`grounded` 占的比例（这张图本来就大半时间在空中）和
## 最远跑到哪儿。**这两个数字不设阈值** —— 这张图的远近就是运气，
## 卡死一个数等于把种子的一次抽样当成契约。
func _section_arches_drive() -> void:
	print("=== 彩虹：全油门从出生台开出去 ===")
	var target := float(Maps.SHAPE_START_CELL + 4) * CW
	_setup(Maps.RAINBOW)
	var car := _spawn_car(Maps.RAINBOW, START_X)
	await _settle()
	var st := {"reason": "", "max_x": -INF, "min_y": INF, "max_y": -INF,
			"landings": 0, "grounded": 0, "frames": 0, "was_air": true,
			"stall": 0, "log": []}
	car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	await _drive_until(target, DRIVE_SECONDS, st, func(s: Dictionary) -> void:
		var c := _car
		var x := c.chassis.global_position.x
		var y := c.chassis.global_position.y
		s["max_x"] = maxf(float(s["max_x"]), x)
		s["min_y"] = minf(float(s["min_y"]), y)
		s["max_y"] = maxf(float(s["max_y"]), y)
		s["frames"] = int(s["frames"]) + 1
		if c.grounded:
			s["grounded"] = int(s["grounded"]) + 1
			# 着地的**上升沿**才算一次落点：同一块平台上连着几十帧着地，只算一次。
			if bool(s["was_air"]):
				s["landings"] = int(s["landings"]) + 1
			s["was_air"] = false
		else:
			s["was_air"] = true
		_trace(c, s))
	var frames := maxi(int(st["frames"]), 1)
	var ratio := float(st["grounded"]) / float(frames)
	print("  最远 x=%.0f（目标 %.0f）；落点 %d 次；着地 %d / %d 帧 = %.0f%%" % [
			st["max_x"], target, int(st["landings"]), int(st["grounded"]), frames,
			100.0 * ratio])
	# 死因是**读数**不是判分：这图上翻车是常态（见上面那段）。跟着一起打出来，
	# 是为了让「三秒就翻」和「十四秒都翻不掉」一眼能分开。
	print("  纵向跑过 y %.0f～%.0f（出生台面在 y=%.0f，带子底在 %.0f）；死因「%s」%s" % [
			st["min_y"], st["max_y"], HillTerrain.GROUND_Y + Maps.PAD_DY,
			HillTerrain.GROUND_Y + Maps.BAND, st["reason"],
			"" if String(st["reason"]) == ""
			else "（第 %.1f 秒）" % (float(frames) * DT)])
	# **不判「跑到底」**，因为这张图按设计就跑不到底 —— 车没有跳跃键，从出生台飞出去
	# 就是一次弹道，落点是什么决定一切。而落点六成是**随机朝向的彩虹弧**（纯造景，
	# 30 像素厚的一条带），车以 900 px/s 落上去会被弹起来／转个跟头，
	# 之后要么撞头（`crash`）要么飘出带子（`fall`）。
	#
	# 这条**实测过，不是猜的**：六个种子全油门跑，落点 1～6 次、活 2.5～4.9 秒，
	# 只有一个跑满 15 秒。所以「活多久」是运气，不是这张图的性质，
	# 拿它当断言只会得到一条随种子跳的测试。
	#
	# 判的是**另一件事**：车飞出出生台之后**确实落在了平台上**。
	#
	# 门槛取 2 而不是更高，是因为这条要分的那条线正好在 1 和 2 之间：
	# 「出生台架在 `GROUND_Y` 上」那个 bug 的表现就是**全程只落 1 次地**
	# —— 那一次是出生台自己。车冲出去撞的是平台的**侧面**（实测 vx 从 +908
	# 一帧之内变 −72），弹回来就再也没落过。落地 ≥ 2 次就说明它**进了平台场**。
	#
	# 实测修好之后是 2 次（`max_x` 1184、活 4.3 秒），另一次独立跑是 4 次。
	# 定在 2 是贴着最差的那次定的 —— 上面那段说了，多落几次是运气不是性质。
	# 修法是 [constant Maps.PAD_DY]，结构断言在出生台那一节（「横跨出生台的高度」）。
	_check("车飞出出生台后落到了平台上（不是一头撞在第一块上）",
			int(st["landings"]) >= 2, "只落了 %d 次" % int(st["landings"]))
	# 上面那条之外的兜底：别在出射半秒内就没了。留 2 秒是因为实测最短的那个种子
	# 也活了 2.50 秒 —— 真出现「出门即死」的话，多半是又有人在出生台右沿立了道墙。
	_check("不是出门就死（活了 2 秒以上）", float(frames) * DT > 2.0,
			"只活了 %.2f 秒" % (float(frames) * DT))
	# 门槛不是「一个区块宽」而是**再往里 200 像素**。出生台右沿在 x = 800，
	# 而实测出过一个「右沿立着一道看不见的墙」的 bug：车顶在墙上停在 x = 696 ——
	# 卡 `> 800` 也能逮住它，但留 200 像素余量是免得下一轮把出生台改窄之后
	# 「刚掉出去一点点」也算过。
	_check("真的开出了出生台、进了平台场（x > 出生台右沿 + 200）",
			float(st["max_x"]) > CW + 200.0, "最远 x=%.0f" % st["max_x"])
	# 没跑完全程就把轨迹倒出来：死因「fall」光看一个数字查不出原因
	# （是脚下那一格恰好空着、还是掉速掉到过不去）。见 [method _dump_trace]。
	_dump_trace(st, target)


# ---------------------------------------------------------------- 彩虹：掉出去 = 死

## 平台带底下那条判死线。
##
## **这一条是这套设计的兜底**：带子有 4000 像素厚，但它是有限的 —— 一路掉出去
## 就是掉出这张图，必须判死而不是让玩家在空天里无限往下掉。
##
## 两头都验：**结构**上（那条死区正好压在带子下沿、铺满整块区块宽）和行为上
## （车落在带子下面就死，死因是 [constant HillCar.REASON_FALL]）。
func _section_arches_fall() -> void:
	print("=== 彩虹：掉出平台带 = 死 ===")
	_setup(Maps.RAINBOW, PROBE_CHUNK)
	var index := Maps.SHAPE_START_CELL + 1
	var chunk := _chunk_node(index)
	_check("探针区块建出来了（不然下面量的是空）", chunk != null, "Chunk%d 不在" % index)
	if chunk == null:
		return
	var zone: HillHazard = null
	for child in chunk.get_children():
		if child is HillHazard:
			zone = child as HillHazard
	_check("平台带下面铺了死区", zone != null, "Chunk%d 里没有 HazardZone" % index)
	if zone == null:
		return
	var cs := zone.get_node_or_null("Shape") as CollisionShape2D
	_check("死区的形状挂着", cs != null, "HazardZone/Shape 不在")
	if cs == null:
		return
	var box := cs.shape as RectangleShape2D
	# 死区左上角 = 节点中心往回推半个尺寸（[method HillHazard.setup] 就是那么摆的）。
	var top := zone.position.y - box.size.y * 0.5
	print("  死区：x %.0f～%.0f、y %.0f 往下 %.0f（带子底在 %.0f）" % [
			zone.position.x - box.size.x * 0.5, zone.position.x + box.size.x * 0.5,
			top, box.size.y, HillTerrain.GROUND_Y + Maps.BAND])
	_approx("死区的上沿正好压在带子底（再高就会切到平台）",
			top, HillTerrain.GROUND_Y + Maps.BAND, 0.01)
	_approx("死区铺满整块区块宽（横向不留缝）", box.size.x, CW, 0.01)
	# 「看不见」：这张图平台下面本来就只有天，死区要是画出来就是一条横杠。
	# 颜色来自 [constant HillTerrain.GAP_FILL_AIR]，透明度必须是 0。
	_check("死区是看不见的（颜色整个透明）",
			zone.modulate.a < 0.001 or cs.modulate.a < 0.001
			or _hazard_alpha(zone) < 0.001,
			"modulate.a = %.3f，颜色 alpha = %.3f" % [
					zone.modulate.a, _hazard_alpha(zone)])

	# 行为：把车摆在带子下面，它该当场判死。
	var car := _spawn_car(Maps.RAINBOW, zone.position.x,
			HillTerrain.GROUND_Y + Maps.BAND + 30.0)
	var reason := {"r": ""}
	car.crashed.connect(func(r: String) -> void: reason["r"] = r)
	await _frames(10)
	_check("掉到带子下面就判死，死因是「掉出去」",
			not car.alive and String(reason["r"]) == HillCar.REASON_FALL,
			"活着 = %s，死因「%s」" % [car.alive, reason["r"]])


## 死区画出来的那个多边形的 alpha。**透明有两种做法**（节点的 `modulate` 或者
## 颜色本身），这里两个都摸一遍 —— 摸不到就返回 0（判成「看不见」），
## 因为 [method HillHazard] 不画东西的话本来也看不见。
func _hazard_alpha(zone: HillHazard) -> float:
	for child in zone.get_children():
		if child is Polygon2D:
			return (child as Polygon2D).color.a * (child as Polygon2D).modulate.a
	return 0.0


# ---------------------------------------------------------------- 真实出生点

## **真实出生点**：`scenes/main.tscn` 里那辆车，在每张图上都得坐在出生台面上。
##
## 这一节是事后补的。用户报的原话是 **「刚开始时彩虹地图车就在云里立即死亡」**，
## 而整套测试一条都没盖到，原因是两件事叠在一起：
##
##   · **别的每一节都自己摆车**（[method _spawn_car] 按 `height_at(x) - CAR_LIFT` 摆，
##     也就是「坐在实测出来的地表上」），而真实开局摆的是场景里**写死的**
##     `position = Vector2(200, 340)`；
##   · 全套里唯一实例化 [constant MAIN] 的地方是黑夜那一节，而那两张图是
##     `night` 和 `plains` —— 出生台都在 `GROUND_Y` 上，照搬那个 `340` 正好没事。
##
## 那个 `340` 的含义是「**经典图**的地面之上 80 像素」，是一个**绝对**高度。彩虹图的
## 出生台面架在 `GROUND_Y + Maps.pad_dy()` 上（高 400，理由见 [constant Maps.PAD_DY]），
## 照搬 `340` 就是把车**摆进出生台的实心多边形里**：车头那个传感器一进树就撞上地面
## （[method HillCar._on_head_body_entered] 直接发 `crashed`），**开局第一帧就死**。
## 而那块台子的填色是 [method Maps.get_map] 的 `dirt`（`0.80, 0.84, 0.97`，一整块惨白），
## 车嵌在里面，看着就是「埋在云里」—— 用户看到的就是这个。
##
## 修法是 [method HillGame._spawn_position]：出生点的高度跟着本图的出生台面一起挪
## `Maps.pad_dy(map_id)`。这一节钉三件事，缺一不可：
##
##   1. **出生点脚下就是出生台面** —— 十二张图逐张问 `height_at`（纯函数，不建世界）。
##      这是那条「挪同一个数就准」的公式的**全部依据**：`y` 里已经含着「离地面 80 像素」，
##      所以只要出生地面本身是 `GROUND_Y + pad_dy`，挪量就一定是 `pad_dy`。
##   2. **游戏真把车摆在「场景给的坐标 + `pad_dy`」上** —— 坐标是**从 `main.tscn` 里读**的，
##      不是在这里再抄一遍（抄一遍的话，场景改了测试还绿着）。
##   3. **真跑起来** —— 彩虹图上那辆车活着、落地、停在台面上，平原图当对照组。
##
## 第 2、3 条只挑彩虹和平原两张（`pad_dy` 的 400 和 0 两个极端）来真起一局：
## 别的十张的坐标由第 1 条解析地管住，而位置本身在所有图上走的是**同一条没有分支的
## 代码路径**，没有「这张图才有的分支」可漏。
func _section_arches_spawn() -> void:
	print("=== 真实出生点（main.tscn 那辆车）===")

	# 1) 十二张图：出生点脚下就是出生台面。
	var bare := _real_terrain(Maps.PLAINS)
	var off: Array = []
	for map_id in Maps.IDS:
		bare.map_id = map_id
		var want := HillTerrain.GROUND_Y + Maps.pad_dy(map_id)
		if absf(bare.height_at(Maps.START_OFFSET) - want) > 0.001:
			off.append("%s: %.1f（该 %.1f）" % [
					map_id, bare.height_at(Maps.START_OFFSET), want])
	print("  出生点 x = %.0f 处不是出生台面的图：%d 张%s" % [
			Maps.START_OFFSET, off.size(),
			"" if off.is_empty() else "  " + ", ".join(off)])
	_check("十二张图的出生点上 height_at 就是出生台面（`_spawn_position` 挪多少全靠它）",
			off.is_empty(), "%d 张对不上，头一张 %s" % [
					off.size(), off[0] if not off.is_empty() else "-"])

	# 2) 场景里写死的那个坐标 —— **从 `main.tscn` 里读**。
	#    （[constant MAIN] 是个 `PackedScene`，`get_state()` 能翻出它存下来的属性值。）
	var scene_spawn := Vector2(INF, INF)
	var state := MAIN.get_state()
	for i in state.get_node_count():
		if String(state.get_node_name(i)) != "Car":
			continue
		for j in state.get_node_property_count(i):
			if String(state.get_node_property_name(i, j)) == "position":
				var value: Variant = state.get_node_property_value(i, j)
				if value is Vector2:
					scene_spawn = value
	print("  main.tscn 里车的出生坐标：%s（GROUND_Y = %.0f）" % [
			scene_spawn, HillTerrain.GROUND_Y])
	_check("从 main.tscn 里读到了车的出生坐标（这一节的第 2、3 条全靠它）",
			is_finite(scene_spawn.x), "没读到 —— 场景里 Car 节点的 position 不见了？")
	if not is_finite(scene_spawn.x):
		return

	# **先清场。** 这一节起的是**完整的主场景**（[constant MAIN]），而测试自己搭的
	# 那几个世界（[member _world]、[member _terrain]）是**和它共用同一个物理空间**的：
	# 物理服务器不管节点在不在测试这棵子树里。
	#
	# 不清的话，前几节留下来的东西会直接砸在这辆车上 —— 实测就是这么死的：
	# [_section_arches_fall] 最后那一下 `set_target` 把车摆到 2 号区块，
	# 而 [constant HillTerrain.VIEW_RADIUS] = 2，窗口因此滑到 0～4 号，
	# **把彩虹图的出生台建了出来**（`y` 20～1020，横坐标 0～800 那一整块）。它正好
	# 扣在平原图的出生台（`y` = 420）上面 —— 彩虹图的车脚下也有这么一块台子，
	# 所以它看着没事；平原图的车头（车壳之上 62 像素，趴着时 `y` ≈ 320）整个
	# **插在这块台子里面**，一进树就是 `crash`。查这个的时候单独起一局是对的，
	# 一放进测试里就死 —— 差别就是这摊没扫干净的东西。
	if _world != null:
		_world.queue_free()
		_world = null
		_terrain = null
		_car = null
		await get_tree().process_frame
		await _frames(1)

	for map_id in [Maps.RAINBOW, Maps.PLAINS]:
		var pad_y := HillTerrain.GROUND_Y + Maps.pad_dy(map_id)
		SaveData.selected_map = map_id
		var main: HillGame = MAIN.instantiate()
		add_child(main)

		# 3a) 摆在哪。**一帧都不跑**：摆位置是 [method HillGame._enter_tree] 里的事，而 `car.gd` 一个字节
		#     都不改自己的 `position`（它只改车壳／轮子那几个刚体的 `global_position`），
		#     所以这里读到的正是「游戏把车摆在哪」。
		var want := Vector2(scene_spawn.x, scene_spawn.y + Maps.pad_dy(map_id))
		var got: Vector2 = main.car.position
		print("  %s：车摆在 %s（期望 %s；本图 pad_dy = %.0f，出生台面 %.1f）" % [
				map_id, got, want, Maps.pad_dy(map_id), pad_y])
		_approx("%s：出生点的 x 没被动过" % map_id, got.x, want.x, 0.01)
		_approx("%s：出生点的高度跟着本图的出生台面挪（挪量 = pad_dy）" % map_id,
				got.y, want.y, 0.01)

		# 3b) 真跑。油箱加满：这一节问的是「生在哪儿」，不是「有没有油」
		#     （[method _spawn_car] 也这么干）—— 别让油耗把 `alive` 弄假。
		main.car.fuel = 1.0e9
		var reason := {"r": ""}
		main.car.crashed.connect(func(r: String) -> void: reason["r"] = r)
		await _frames(SPAWN_LAND)
		var car: HillCar = main.car
		var rest: float = car.chassis.global_position.y
		print("  %s：%d 帧后 alive = %s，grounded = %s，车壳 y = %.1f（离台面 %.1f%s）" % [
				map_id, SPAWN_LAND, car.alive, car.grounded, rest, pad_y - rest,
				"" if car.alive else "，死因「%s」" % reason["r"]])
		_check("%s：出生 %d 帧后还活着（没有生在实心地块里）" % [map_id, SPAWN_LAND],
				car.alive, "alive = false，死因「%s」" % reason["r"])
		_check("%s：落地了" % map_id, car.grounded,
				"grounded = false，车壳 y = %.1f（台面 %.1f）" % [rest, pad_y])
		# 车壳原点比轮子着地点高 [constant CAR_LIFT]（轮心 +18、半径 21），所以停在
		# 台面上时它就在 `pad_y - CAR_LIFT`。给的余量是落地那一下的物理下沉／回弹。
		_approx("%s：车壳停在出生台面上（高 %.0f 像素 = 轮心偏移 + 轮半径）" % [
				map_id, CAR_LIFT], rest, pad_y - CAR_LIFT, 4.0)

		main.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------- 黑夜

## 黑夜图：**场上唯一的光是车头那两颗车灯**；金币、油桶和地形一样待在挡布之下，
## 于是灯照到哪儿才看得见哪儿。
##
## 这一节的主断言是**接线**（[method HillGame._ready] 里那句
## `night.setup(car.chassis, map_id)`）：漏掉它的话，挡布一直停在场景里写死的
## `visible = false` 上，黑夜图一个像素都不挡 —— 而窗口里看是「这局好像亮着」，
## 不像报错。
func _section_night() -> void:
	print("=== 黑夜：只有车灯照到的地方看得见 ===")
	var ahead := Vector2.RIGHT
	var dark := 1.0 - HillNight.UNLIT_LIGHT
	# 锥尖：**车头那颗灯珠**相对车轴心的位置。默认越野车量出来是 86 像素，这里取 90 ——
	# 下面几条要么量车后（锥形照不到）、要么量照程之外，取 60 或 120 结论都一样。
	var apex := Vector2(90.0, 0.0)
	# ---- 光池：车壳被自己的灯照亮一点 ----
	#
	# 用户看过第一版之后补的话：「**只有车灯才有灯光，车周围还是暗的**」—— 第一版
	# 在车周围留了个永远透亮的「洞」（开不开灯车都看得见），那个洞现在整个删掉了，
	# 车壳只剩自己那圈弱光（[constant HillNight.CAR_PEAK]），比锥形暗得多。
	#
	# 光池这几条一律**量车后**（Vector2.LEFT）：正前方那颗灯珠的锥形会盖住同一段距离，
	# 量前面量到的是锥形，不是池子。
	_approx("灯关着：连车心都只是 5% 的暗（车周围是暗的）",
			HillNight.screen_alpha(Vector2.ZERO, ahead, false), dark)
	_approx("灯开着：车壳只剩光池那点亮",
			HillNight.screen_alpha(Vector2.LEFT * HillNight.CAR_CORE * 0.5, ahead, true, apex),
			1.0 - HillNight.CAR_PEAK)
	_approx("池芯边缘还是满亮",
			HillNight.screen_alpha(Vector2.LEFT * HillNight.CAR_CORE, ahead, true, apex),
			1.0 - HillNight.CAR_PEAK)
	_approx("池子外面就退回地板",
			HillNight.screen_alpha(
					Vector2.LEFT * (HillNight.CAR_CORE + HillNight.CAR_SOFT + 1.0), ahead, true, apex),
			dark)
	_check("光池比锥形暗得多（车壳不许抢戏）",
			HillNight.CAR_PEAK > 0.0 and HillNight.CAR_PEAK < 0.6,
			"峰值 %.2f（锥形心里是 1.0）" % HillNight.CAR_PEAK)
	var fading := true
	var prev := 2.0
	var x := 0.0
	while x <= HillNight.CAR_CORE + HillNight.CAR_SOFT:
		var a := HillNight.car_light(x)
		if a > prev:
			fading = false
		prev = a
		x += 5.0
	_check("光池从芯往外一路变暗（没有硬边）", fading,
			"扫了 %.0f 像素" % (HillNight.CAR_CORE + HillNight.CAR_SOFT))

	# ---- 车灯锥：从**车头那颗灯珠**射出去的一段亮区 ----
	#
	# 用户原话：「照亮前方锥形区域……未被车灯照到的地方亮度改为白天的 0.05」，
	# 后来补的第三条是「车灯灯光长度有限」—— 照程就是 [constant HillNight.CONE_REACH]。
	# 上面那些量的是光池（车壳那一圈），**灯照在路上**看 [method HillNight.screen_alpha]。
	_approx("没灯、也没照到的地方 = 白天的 5%",
			HillNight.screen_alpha(Vector2(1500.0, 0.0), ahead, false), dark)
	# 锥尖在**车头那颗灯珠**上，不在车轴心（见 [method HillNight._draw]）：轴心和灯口
	# 之间那一段（车壳自己）于是不吃锥形 —— 从轴心射的话这里会是全亮，车壳被一条 44°
	# 的亮楔子切成「前亮后暗」两截，而用户要的是「车周围还是暗的」。
	_approx("轴心和灯口之间（车壳自己）不吃锥形",
			HillNight.screen_alpha(Vector2(30.0, 0.0), ahead, true, apex),
			1.0 - HillNight.CAR_PEAK)
	_approx("灯口正前方立刻满亮",
			HillNight.screen_alpha(apex + Vector2(20.0, 0.0), ahead, true, apex), 0.0)
	# 「亮」是**比关灯时亮**，不是「全亮」：锥形现在随距离衰减（见下面纵向那几条），
	# 300 像素处只剩八成的光，钉死 0 会变成在量「衰减存不存在」而不是「灯开没开」。
	var lit_front := HillNight.screen_alpha(Vector2(300.0, 0.0), ahead, true)
	var dark_front := HillNight.screen_alpha(Vector2(300.0, 0.0), ahead, false)
	_check("灯开着：正前方比关灯亮", lit_front < dark_front - 0.2,
			"开着 %.4f，关着 %.4f" % [lit_front, dark_front])
	_approx("灯关着：同一个地方还是暗的",
			HillNight.screen_alpha(Vector2(300.0, 0.0), ahead, false), dark)
	# 锥形是**认方向的**：车头转 90°，刚才亮的那点就暗下去，转过去的那边亮起来。
	_approx("车头转 90°，正前方不再是灯心",
			HillNight.screen_alpha(Vector2(300.0, 0.0), Vector2.DOWN, true), dark)
	# 下面这条也不再钉 0：锥形随距离衰减（见下面纵向那几条），300 像素处只剩八成光。
	# 要量的是**方向**，所以拿「转过去那边」和「原来那边」比。
	var turned := HillNight.screen_alpha(Vector2(0.0, 300.0), Vector2.DOWN, true)
	var turned_old := HillNight.screen_alpha(Vector2(300.0, 0.0), Vector2.DOWN, true)
	_check("车头转 90°，灯跟着转到正下方", turned < turned_old - 0.2,
			"正下方 %.4f，原来的前方 %.4f" % [turned, turned_old])
	# 横向：半角以内满亮，半角 + 过渡角之外全灭，中间一路变暗（没有硬边）。
	var half := HillNight.CONE_HALF_DEG
	var soft := HillNight.CONE_SOFT_DEG
	# 横向要和**同半径**的轴向比：纵向那条衰减是两者共有的，比出来的是纯横向的结论
	# （之前直接钉 1.0，是因为那时 400 像素处还落在平顶带里）。
	_approx("半角以内和轴向一样亮（横向是平的）",
			HillNight.cone_light(Vector2.RIGHT.rotated(deg_to_rad(half - 1.0)) * 400.0, ahead),
			HillNight.cone_light(Vector2.RIGHT * 400.0, ahead))
	_approx("半角 + 过渡角之外照不到",
			HillNight.cone_light(Vector2.RIGHT.rotated(deg_to_rad(half + soft + 1.0)) * 400.0, ahead), 0.0)
	_approx("正后方照不到（车底下不该是亮的）",
			HillNight.cone_light(Vector2(-400.0, 0.0), ahead), 0.0)
	var lateral_back := true
	var lateral_prev := 2.0
	var deg := 0.0
	while deg <= half + soft:
		var v := HillNight.cone_light(Vector2.RIGHT.rotated(deg_to_rad(deg)) * 400.0, ahead)
		# 这里必须留个 ε：向量是 float32，转个 0.5° 之后**长度就不再正好是 400**（差个
		# 1e-5 量级），而纵向衰减现在是活的，长度一动亮度就跟着动 —— 不留 ε 的话
		# 就会逮到 1e-7 的假回升。真实的横向过渡在 9° 里掉掉一半，0.5° 一步差 0.05。
		if v > lateral_prev + 0.0001:
			lateral_back = false
		lateral_prev = v
		deg += 0.5
	_check("灯边从满亮一路淡到全灭（不是一条硬边）", lateral_back,
			"扫到 %.0f°（半角 %.0f + 过渡 %.0f）" % [half + soft, half, soft])
	# 纵向：**随距离衰减**。用户原话「光线的强度随距离衰减」——不是「照程之内一样亮、
	# 最后一截才糊」（上一版就是那样：前 547 像素导数恒为 0 的一条平顶带），而是从灯口
	# 那一段往远一路暗下去，到照程尽头正好归零。外面那圈就是用户要的「没被照到 = 0.05」。
	var near_full := HillNight.cone_light(Vector2(HillNight.CONE_NEAR - 1.0, 0.0), ahead)
	_approx("灯口那一段满亮", near_full, 1.0)
	var falls := true
	var falls_prev := 2.0
	var falls_last := -1.0
	var d := 0.0
	while d <= HillNight.CONE_REACH:
		var v := HillNight.cone_light(Vector2(d, 0.0), ahead)
		if v > falls_prev + 0.0001:
			falls = false
		falls_prev = v
		falls_last = v
		d += 5.0
	_check("光强随距离只降不升（这就是「随距离衰减」）", falls,
			"从灯口扫到照程 %.0f 像素" % HillNight.CONE_REACH)
	_check("照程尽头真的暗下去了（不是一条平顶亮带）",
			falls_last <= 0.0 and near_full - falls_prev > 0.5,
			"尽头 %.4f，灯口 %.4f" % [falls_last, near_full])
	# 半程剩一半左右：这条不是量给代码看，是量**观感**的 —— 太陡就成了近处一个亮斑
	# （照程白给一半），太平就退回平顶带。
	_approx("半程剩下约一半的亮度", HillNight.cone_light(Vector2(470.0, 0.0), ahead), 0.5, 0.08)
	_approx("照程之外全灭",
			HillNight.cone_light(Vector2(HillNight.CONE_REACH + 1.0, 0.0), ahead), 0.0)
	_approx("照程之外回到 5% 的地板",
			HillNight.screen_alpha(Vector2(HillNight.CONE_REACH + 1.0, 0.0), ahead, true), dark)
	# 锥形那一段的扇片是细的（18 份），外面整圈是粗的（32 份，11.25° 一片）。
	# 锥形要是漏进粗扇片里，过渡那 9° 会被插值成一条折线（灯边成了多边形）。
	# **量的是过渡角以外**：半角到过渡角之间本来就该有光，那是细扇片的地盘。
	# 锥尖往前挪会让同一个点**离轴更远**（所以亮区只会更窄），这条正是它成立的理由 ——
	# 正前方的 90 像素就是默认越野车灯口到轴心的距离。
	var leak := 0.0
	for radius: float in [150.0, 300.0, 450.0]:
		# 变量名别叫 `deg`：上面横向那条扫描已经有一个 `deg` 了，同名会被当成重复声明。
		var ang := HillNight.CONE_HALF_DEG + HillNight.CONE_SOFT_DEG
		while ang <= HillNight.CONE_HALF_DEG + HillNight.CONE_SOFT_DEG + 20.0:
			var off := Vector2.RIGHT.rotated(deg_to_rad(ang)) * radius
			leak = maxf(leak, HillNight.cone_light(off - apex, ahead))
			ang += 0.5
	_check("锥形照得到的地方全落在细扇片那一段里（粗扇片里一点光都没有）",
			leak <= 1e-6, "粗扇片里最亮 %.4f" % leak)
	# 全屏扫一遍：**黑度不许超过 1 - 0.05**（用户那条地板的另一面 —— 只要有一条
	# 支路漏了 max()，屏幕上就会出现一块 0.95 以上的死黑，而窗口里看着只是「有点黑」）。
	var darkest := 0.0
	var lit_beyond := 0
	var r := 0.0
	while r <= HillNight.REACH:
		var a := 0.0
		while a < TAU:
			var off := Vector2.RIGHT.rotated(a) * r
			darkest = maxf(darkest, HillNight.screen_alpha(off, ahead, true, apex))
			if r > HillNight.CAR_CORE and HillNight.cone_light(off - apex, ahead) > 0.5:
				lit_beyond += 1
			a += TAU / 48.0
		r += 32.0
	_check("灯开着，屏幕上最黑也就 1 - 0.05（地板没漏）",
			darkest <= dark + 1e-6,
			"最黑 %.4f（地板 %.4f）" % [darkest, dark])
	_check("光池之外确实被照亮了一片（锥形真的铺出去了）", lit_beyond > 0,
			"照到 %d 个采样点" % lit_beyond)

	for map_id in [Maps.NIGHT, Maps.PLAINS]:
		var want := Maps.is_night(map_id)
		SaveData.selected_map = map_id
		var main: HillGame = MAIN.instantiate()
		add_child(main)
		await get_tree().process_frame
		print("  %s（is_night = %s）：挡布 visible = %s，z = %d，车 z = %d，地形 z = %d" % [
				map_id, want, main.night.visible, main.night.z_index,
				main.car.z_index, main.terrain.z_index])
		_check("%s：挡布 visible = %s" % [map_id, want], main.night.visible == want,
				"visible = %s（期望 %s）" % [main.night.visible, want])
		_check("%s：挡布在 NIGHT_Z = %d 层" % [map_id, Maps.NIGHT_Z],
				main.night.z_index == Maps.NIGHT_Z, "z = %d" % main.night.z_index)
		_check("%s：挡布跟着**车壳**（不是没接上）" % map_id,
				main.night._target == main.car.chassis,
				"目标 = %s" % ("车壳" if main.night._target == main.car.chassis
						else str(main.night._target)))
		# 车灯**只有黑夜图开得起来**：锥形亮区是挡布挖出来的洞，别的图没有挡布，
		# 开了只有油耗、没有光（见 [method HillCar.headlights_available]）。
		main.car.toggle_headlights()
		_check("%s：开灯 %s" % [map_id, "开得起来" if want else "开不起来"],
				main.car.headlights_on == want,
				"headlights_on = %s" % main.car.headlights_on)
		main.car.toggle_headlights()
		_check("%s：再按一下关得回去" % map_id, not main.car.headlights_on,
				"headlights_on = %s" % main.car.headlights_on)
		# 挡布的网格**不许重叠**：两块 α 0.95 叠起来是 1 - 0.05² = 0.9975，
		# 在 95% 的黑里是一条看得见的深色缝。两段角度各自铺满自己那一段、
		# 合起来正好一整圈，就等价于「每个像素只被涂一次」。
		for lamps in [false, true]:
			var total := 0.0
			var zero_width := 0
			for angles: PackedFloat32Array in main.night._angles(Vector2.RIGHT, lamps):
				for i in angles.size() - 1:
					var w := angles[i + 1] - angles[i]
					if w <= 0.0:
						zero_width += 1
					total += w
			_approx("灯%s：一圈的角度加起来正好 360°" % ("开" if lamps else "关"), total, TAU)
			_check("灯%s：没有宽度为 0 的扇片" % ("开" if lamps else "关"), zero_width == 0,
					"零宽 %d 片" % zero_width)
			var radii := main.night._radii(lamps)
			# **最里面那圈必须是 0**：池芯不是透明的（灯开着时那儿 α = 1 - CAR_PEAK），
			# 从 CAR_CORE 才开始铺的话车周围会留一块**根本没涂过**的画布 —— 屏幕上就是
			# 「车所在的那块还是白天」。这一条是唯一抓得住它的地方。
			_check("灯%s：最里面那圈从车心（半径 0）开始" % ("开" if lamps else "关"),
					radii[0] <= 0.001 and radii[0] >= 0.0, "最里 %.1f 像素" % radii[0])
			var rising := true
			for i in radii.size() - 1:
				if radii[i + 1] <= radii[i]:
					rising = false
			_check("灯%s：半径一圈圈变大、不重复，最后甩到 REACH" % ("开" if lamps else "关"),
					rising and is_equal_approx(radii[radii.size() - 1], HillNight.REACH),
					"%d 圈，最外 %.0f" % [radii.size(), radii[radii.size() - 1]])
		if want:
			# 开灯费油。**用户说的是「耗油速度是前进速度的 0.5 倍」，没有照字面做**：
			# 车速表上的数是 m/s 换算的 km/h，字面乘 0.5 会让满油一秒见底。改成
			# 「油门耗油的一半」（见 [constant HillCar.HEADLIGHT_DRAIN]）。
			#
			# 这里**不写死「正好一半」**：那两个数是 [member HillCar.fuel_idle_drain] /
			# [member HillCar.fuel_throttle_drain]，车主会在编辑器里试着调（调完车的手感
			# 就变），钉死一个比例只会让正常的调参变成一片红。量的是**意图**：
			# 开灯比空转费、比全油门省 —— 灯值这一份油，但不值一整脚油门。
			var car := main.car
			var scale := float(Maps.get_map(map_id)["fuel_scale"])
			_check("开灯的开销夹在空转和全油门之间（%.1f < %.1f < %.1f）" % [
					car.fuel_idle_drain, HillCar.HEADLIGHT_DRAIN, car.fuel_throttle_drain],
					HillCar.HEADLIGHT_DRAIN > car.fuel_idle_drain
					and HillCar.HEADLIGHT_DRAIN < car.fuel_throttle_drain,
					"空转 %.1f，车灯 %.1f，全油门 %.1f" % [
						car.fuel_idle_drain, HillCar.HEADLIGHT_DRAIN, car.fuel_throttle_drain])
			car.throttle = 0.0
			car.hovering = false
			car.headlights_on = false
			car.fuel = 100.0
			car._burn_fuel(1.0)
			var idle_burn := 100.0 - car.fuel
			car.fuel = 100.0
			car.headlights_on = true
			car._burn_fuel(1.0)
			_approx("开灯这一秒多烧的就是 HEADLIGHT_DRAIN（还乘了本图的油耗倍率 %.2f）" % scale,
					100.0 - car.fuel - idle_burn, HillCar.HEADLIGHT_DRAIN * scale)
			# 悬停时**不该**跟着翻三倍：车灯加在倍率**之后**（见 [method HillCar._burn_fuel]）。
			car.hovering = true
			car.headlights_on = false
			car.fuel = 100.0
			car._burn_fuel(1.0)
			var hover_burn := 100.0 - car.fuel
			car.fuel = 100.0
			car.headlights_on = true
			car._burn_fuel(1.0)
			_approx("悬停 + 开灯 = 悬停耗油 + 车灯（不是 ×3）",
					100.0 - car.fuel - hover_burn, HillCar.HEADLIGHT_DRAIN * scale)
			car.hovering = false
			car.headlights_on = false
			car.fuel = car.fuel_max
		# 层级关系就是需求本身：**地形、车和金币油桶全在挡布之下**，只有洞里那一圈
		# 看得见。金币油桶原来被抬到挡布之上（满屏黑里照样亮着），是用户报上来的 bug。
		_check("%s：挡布盖得住地形和车" % map_id,
				main.terrain.z_index < Maps.NIGHT_Z and main.car.z_index < Maps.NIGHT_Z,
				"地形 %d，车 %d，挡布 %d" % [
					main.terrain.z_index, main.car.z_index, Maps.NIGHT_Z])
		var want_z := 0
		var seen := 0
		var wrong := 0
		for node in main.terrain.get_children():
			for child in node.get_children():
				if child.get_script() == PICKUP:
					seen += 1
					if (child as Node2D).z_index != want_z:
						wrong += 1
		_check("%s：摆出来的金币/油桶层号 = %d" % [map_id, want_z],
				seen > 0 and wrong == 0, "%d 个里 %d 个不对" % [seen, wrong])
		# 比上面那条更硬的一条：**挡布之上不该有任何东西**（HUD 在 CanvasLayer 上，
		# 不在这棵树里）。谁再往上来一层 —— 金币、油桶、以后加的任何拾取物 ——
		# 这里就红。
		var above := PackedStringArray()
		for node in main.terrain.get_children():
			for child in node.get_children():
				if child is Node2D and (child as Node2D).z_index >= Maps.NIGHT_Z:
					above.append("%s z=%d" % [child.name, (child as Node2D).z_index])
		_check("%s：挡布之上什么都没有" % map_id, above.is_empty(),
				"干净的" if above.is_empty() else "；".join(above))
		main.queue_free()
		await get_tree().process_frame

	# **光池的芯必须整个装下车**（红线，见 scripts/night.gd）：池芯是满亮的那一圈，
	# 车最远那一角一旦探出去，它就会比车壳别处暗一截 —— 车上多出一块斜的暗斑，
	# 看着像渲染坏了，而不是「天黑」。
	#
	# 距离**现量**，不写死：底盘轴心到每个子节点中心的距离 + 该节点自身的最大半径
	# （旋转不变的上界，宁可量宽一点）。哪台车长得比 [constant HillNight.CAR_CORE] 还大，
	# 这里当场红，而不是等玩家在黑夜里看到车角发灰。
	var worst := 0.0
	var worst_name := ""
	for id in Vehicles.IDS:
		var car := Vehicles.instantiate(id)
		if car == null:
			continue
		add_child(car)
		var zh := String(Vehicles.get_vehicle(id)["zh"])
		var chassis := car.chassis as RigidBody2D
		var org := chassis.global_position
		var far := 0.0
		var far_name := ""
		for shape in _shapes_under(chassis):
			var holder := shape.get_parent() as Node2D
			# **不叫 `d`**：这个函数上面量锥形衰减时已经有一个函数级的 `d` 了
			# （那是沿照程走的距离），GDScript 不许内层块把外层的局部变量盖掉，
			# 重名的话整个脚本读不进来 —— 报的是「already a variable named d」。
			var reach := (holder.global_position - org).length() + _shape_reach(shape)
			if reach > far:
				far = reach
				far_name = holder.name
		# 车灯的位置也是**现量**车壳摆的（见 [method HillCar.headlight_lamps]），不是写死
		# 的偏移：八辆车的车头天差地别（摩托是个尖、大巴是一面墙），写死的偏移在半数车
		# 上会把灯画到车壳外面去。这里逐台车验证两颗灯落在车壳多边形**里面**、先远后近
		# （[method HillNight._draw] 拿靠前那颗当锥尖），而且灯珠大到看得见。
		# `Vehicles.instantiate()` 的返回类型是 Node2D（不是 HillCar），所以这里得转一次
		# —— 直接 `car.headlight_lamps()` 会被当成 Variant，推断不出类型，整个脚本读不进来。
		var husk := car as HillCar
		var lamps := husk.headlight_lamps()
		var skin := husk._skin_points()
		var in_skin := lamps.size() == 2 and skin.size() >= 3
		var radius := 0.0
		if in_skin:
			radius = (lamps[1] - lamps[0]).length() * HillNight.LAMP_RADIUS_RATIO
			if lamps[1].x <= lamps[0].x:
				in_skin = false
			for lamp: Vector2 in lamps:
				if not Geometry2D.is_point_in_polygon(lamp, skin):
					in_skin = false
		print("  %-6s 轴心到最远一角 %5.1f 像素（池芯 %.0f，余量 %+.0f）；灯珠半径 %.1f" % [
				zh, far, HillNight.CAR_CORE, HillNight.CAR_CORE - far, radius])
		_check("%s：两颗车灯都画在车壳上、先远后近（锥尖靠前那颗）" % zh, in_skin,
				"灯 %s，车壳 %d 个点" % [str(lamps), skin.size()])
		_check("%s：灯珠大到看得见（≥ 2 像素）" % zh, radius >= 2.0,
				"半径 %.1f 像素" % radius)
		if far > worst:
			worst = far
			worst_name = "%s 的 %s" % [zh, far_name]
		remove_child(car)
		car.free()
	_check("池芯 %.0f 装得下所有车" % HillNight.CAR_CORE, worst < HillNight.CAR_CORE,
			"最远的一角是 %s 的 %.1f 像素（池芯 %.0f）" % [worst_name, worst, HillNight.CAR_CORE])
	SaveData.selected_map = Maps.PLAINS
