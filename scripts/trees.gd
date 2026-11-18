extends HillFeature
## 森林：一段路上站着**一丛 3～5 棵树**，棵数随机、间隔也随机。站着的时候推不动
## （冻结的刚体）：慢慢撞上去会被弹回来，速度够了才推得倒（[constant KNOCK_SPEED]）。
## 被撞倒之后**整棵再就地留 [constant DISAPPEAR_DELAY] 秒就消失**（用户要求）——
## 那一秒里它躺在地上、碰撞体还在，车能碾过去也能被它绊一下，然后就没了。
##
## ## 「被弹回来」是**主动**做的，不是物理自己弹的
##
## 冻结的刚体等于静态体，而车自己的恢复系数只有 0.1（车壳 0.05）—— 两边一乘
## 基本是 0，车撞上去就是「顶死」：实测车速从 250 掉到 **−0.1**，看着像撞在一堵
## 墙上，和「被树弹回来」是两回事。所以 [method _bounce] 主动把三个刚体的水平
## 速度翻过来，大小取撞上**之前**在感知区里记下的那一份
## （[member _grove] 里的 `approach`，碰撞那一瞬间速度已经被吃掉了，用当时的
## `linear_velocity` 算出来的接近 0，等于没弹）。
##
## ## 树高 = 越野车高
##
## 需求原话是「树的高度和越野车高度一样」，所以 [constant TREE_HEIGHT] 直接抄的是
## 实测车高：scenes/car.tscn 里车轮底在 +39、车手头顶在 −77，**合计 116 像素**。
## 这个数不是随手定的，也不是「看着差不多」—— 车手头顶和树顶一样高，撞上去
## 的时候正好是人扎进树冠那一瞬间。
##
## ## 树**不在 `"ground"` 组里**
##
## 树身有 116 高，正好在车手头顶的高度上，撞上去车手必然碰到它。要是把树放进
## `"ground"` 组，[method HillCar._on_head_body_entered] 会把这一下判成翻车 ——
## 需求要的「高速推倒、低速弹回」就直接变成「撞树必死」了。
## 树用层 2 让车撞得到（车壳和轮子的掩码都是 3），但**不进组**，所以怎么撞都不判死。
##
## 代价是「站在倒下的树上」不算着地（[method HillCar._touching_ground] 看的就是
## 这个组），那一秒里腾空计时接着走。树倒下来只有树干那么高、1 秒就没了，
## 比「撞树必死」划算得多。
##
## ## 树冠只画不碰
##
## 碰撞体就是树干那根 18 × 116 的方杆，树冠是一团画上去的叶子。树倒下来之后
## 车要从树冠上碾过去 —— 给树冠加碰撞的话，它倒在哪就在哪变成一堵比车轮还高的墙，
## 「能碾过去」这条就废了。车碾过树冠时轮子会陷进叶子里一点，看着像开进
## 灌木丛，比被一堵叶子墙挡死好。
##
## ## 一丛几棵、站在哪儿，是**世界坐标的纯函数**
##
## 区块是随镜头滚过去才建的，同一块地方会被建了又拆、拆了又建。用 `randf()` 撒树的
## 话，玩家一回头树丛就换了个形状（隧道那边同一个坑：洞顶的形状也只能由世界坐标
## 决定，见 scripts/tunnel.gd 文件头）。所以棵数和每一段的间隔都从**本段左沿的世界
## 坐标**哈希出来（[method _grove_xs]）：同一块地方问多少次都是同一丛树。
##
## 整丛在段内居中。段宽 700（[constant Maps.FEATURE_TREES]），最多 5 棵 × 最长间隔
## [constant GROVE_GAP_MAX] 165 = 4 × 165 = 660，所以怎么抽都装得下、两端必定各留
## 一段空地 —— 不然第一棵树会正好骑在段边界上，和上一块区块接壤的地方凭空冒出个障碍。
##
## ## 判「撞上了」是**算出来的**，不靠引擎的接触回调
##
## 早先这里问的是 `car.chassis.get_colliding_bodies()`，那要求车壳把
## `contact_monitor` 打开 —— 默认是关的，结果是每帧刷一行
## `ERROR: Parameter "contact_monitor" is null.`，而且一辆车都没等到：
## [method _bounce] 从来没触发过，测试量到的「撞后最低 vx = −0.1」就是顶死。
##
## 现在直接算（[method _touching]）：车壳的碰撞形状（**从场景现读**，不抄数）和
## 树干那个竖直矩形，在**车壳自己的坐标系**里比一下。车壳形状最右到 +90、树干半宽 9，
## 所以接触发生在车心离树 **99** 像素的时候 —— 和下面 [constant SENSE_PAD] 那段
## 算出来的是同一个数。车翻了、歪着、斜着都判得对，因为整个判定是在车壳的局部
## 坐标里做的；而它只在车已经在感知区里的时候才算，不是每帧全图扫。


## 树高（像素）= 越野车的高度，见文件头。
const TREE_HEIGHT := 116.0
## 树干宽度。
const TRUNK_W := 18.0
## 树干占的高度，剩下的算树冠。
const TRUNK_H := 64.0
## 树的质量。比车轻（车 174）—— 一辆车撞上去推得动它，才叫「推倒」。
const TREE_MASS := 70.0

## 推倒需要的速度（像素/秒）。
##
## 参照物是现成的两个数：冰湖的速度门槛是 600（冰面 300 宽、只给 0.5 秒），
## 满油门在平地上是 800 上下。取 500 —— 平地上一脚油门就够，而爬着坡撞上去
## （坡上掉到 300 上下）就只能被弹回来。这正是那条地形否决规则
## （[constant HillTerrain.TREE_APPROACH]）要挡的情况：前面是长上坡、
## 到树跟前提不起速的地方根本不摆树。
const KNOCK_SPEED := 500.0
## 推倒时树顶被推出去的速度（像素/秒）。
const KNOCK_PUSH := 260.0
## 推倒时顺带的一点平移速度（倍率）。不给的话树是「原地转一圈」而不是「倒下去」。
const KNOCK_SLIDE := 0.25

## 一丛几棵。用户要的是「3～5 棵成群出现」。
const TREE_COUNT_MIN := 3
const TREE_COUNT_MAX := 5
## 相邻两棵的间隔范围（像素）。上限 × 4 = 660，要装得进段宽 700（见文件头）。
##
## 间隔在这个范围里随机取 —— 用户要的是「间隔随机」。等距摆的话一丛树看着像栅栏，
## 而且车碾过去的节奏会卡在同一个频率上。
const GROVE_GAP_MIN := 110.0
const GROVE_GAP_MAX := 165.0

## 被撞倒之后多久整棵消失（秒）。用户原话：「树木被撞到后 1 秒后消失」。
##
## 只有**被推倒**的树会消失。慢慢撞上去是「推不倒、被弹回来」，树还站着 ——
## 那是另一条需求，和这一条不冲突（树没「被撞到」到该消失的程度）。
const DISAPPEAR_DELAY := 1.0
## 消失前最后这段时间用来淡出（秒），免得「啪」地一下凭空没了。
const FADE_TIME := 0.25

## 感知区比树干每侧宽出多少像素。**必须在物理撞上之前就判出速度**：树是冻结的，
## 等碰上了才想起来要倒，那一下已经被弹回来了，车顿一下树再慢慢倒，很假。
##
## 车壳比轮子还往前伸（车壳形状到 +90、前轮只到 +58），所以接触发生在车心离树
## 99 像素的时候；感知区每侧宽 45（加树干半宽共 54）→ 提前 45 像素触发。
## 全速（约 1050 像素/秒）也有 2.6 帧的提前量。
const SENSE_PAD := 45.0
## 感知区上下各探出多少（像素）。太高会误伤「从树上飞过去」的车。
const SENSE_VPAD := 20.0

## 慢速撞上来时，**撞上去的速度**有多少还给车（倍率，方向相反）。
##
## 0 = 顶死（物理本来的样子），1 = 原速弹回。取 0.5：撞得越狠弹得越远，
## 但弹回来之后还有一段路可以再提一次速 —— 和「推不倒就退回去重来」这个玩法一致。
## 见文件头「被弹回来是主动做的」。
const BOUNCE_KEEP := 0.5

const TRUNK_COLOR := Color(0.40, 0.28, 0.17)
const TRUNK_DARK := Color(0.26, 0.18, 0.11)
const LEAF_COLOR := Color(0.22, 0.46, 0.20)
const LEAF_LIGHT := Color(0.34, 0.58, 0.26)

## 一丛树里每一棵的账。**每棵树各记各的**（早先只有一个成员，一丛树共用一份账
## 的话，撞倒一棵会把另外几棵的状态一起改掉）。
##
## 键：`body` 树那个刚体、`sense` 它的感知区、`toppled` 推倒了没有、
## `approach` 撞之前跑多快（带方向，见文件头）、`bounced` 这一趟弹过了没有、
## `age` 推倒之后过了多久（秒）、`dead` 已经清掉了。
var _grove: Array[Dictionary] = []


func _build() -> void:
	if span.size.x <= 0.0:
		return
	for x in _grove_xs():
		_plant(x)


## 这一丛树各自的横坐标（世界坐标，从左到右）。
##
## **纯函数**：只吃 [member span] 的左沿（见文件头「一丛几棵、站在哪儿是纯函数」）。
## 棵数和每一段的间隔各用一条互不相干的哈希，所以相邻两丛不会「棵数一样、
## 间隔也一样」地排成一列。
func _grove_xs() -> PackedFloat32Array:
	var base := int(roundf(span.position.x))
	var n := TREE_COUNT_MIN \
			+ int(Maps._hash01(base * 31 + 7) * float(TREE_COUNT_MAX - TREE_COUNT_MIN + 1))
	n = clampi(n, TREE_COUNT_MIN, TREE_COUNT_MAX)

	var gaps := PackedFloat32Array()
	var total := 0.0
	for i in range(n - 1):
		var gap := lerpf(GROVE_GAP_MIN, GROVE_GAP_MAX, Maps._hash01(base * 131 + i * 977 + 13))
		gaps.append(gap)
		total += gap

	# 整丛居中：占的宽度就是间隔之和（每棵树自己那 18 像素宽算在间隔里）。
	var xs := PackedFloat32Array()
	var x := span.position.x + (span.size.x - total) * 0.5
	xs.append(x)
	for gap in gaps:
		x += gap
		xs.append(x)
	return xs


## 种一棵：树根踩在**它自己脚下**的地表上。高度得问地形要
## （[method HillFeature.ground_at]）：森林这一段有 700 像素宽，`rim_y` 只是
## 左沿的高度，照着它摆的话一丛树里靠右的几棵会浮在半空或者埋进土里。
func _plant(x: float) -> void:
	var i := _grove.size()
	var ground := ground_at(x)

	var body := _make_tree(i, x, ground)
	var sense := _make_sense(i, x, ground)
	add_child(body)
	add_child(sense)

	_grove.append({
		"body": body,
		"sense": sense,
		"toppled": false,
		"approach": 0.0,
		"bounced": false,
		"age": 0.0,
		"dead": false,
	})


func _make_tree(i: int, x: float, ground: float) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.name = "Tree%d" % i
	# 原点放在**树根**（地面上的那一点），树干往上摆 —— 倒下去的时候绕的就是
	# 靠近地面这一头，和真树一样。
	body.position = Vector2(x, ground)
	body.mass = TREE_MASS
	# 层 2 = 地面层（车壳和轮子的掩码是 3，撞得到）；掩码也要 2 ——
	# 树是刚体，得和**地形**碰（地形在层 2 上、自己的掩码是 0），
	# 掩码留 0 的话树会直接穿过地面掉下去。
	body.collision_layer = 2
	body.collision_mask = 2
	# 阻尼：树倒下去之后要停在地上，不能一直滚。叶子茂密的树不是根滚木。
	body.linear_damp = 0.8
	body.angular_damp = 2.5
	# 站着不动：冻结的刚体是「无限重」的，车推不倒它。
	# **但「被弹回来」不是它自己做的**（恢复系数相乘基本是 0），见 [method _bounce]。
	body.freeze = true

	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var box := RectangleShape2D.new()
	box.size = Vector2(TRUNK_W, TREE_HEIGHT)
	cs.shape = box
	# 碰撞体从地面往上 116：整棵树高，包括树冠那一段。
	cs.position = Vector2(0.0, -TREE_HEIGHT * 0.5)
	body.add_child(cs)
	body.add_child(_trunk_visual())
	body.add_child(_canopy_visual())
	return body


## 感知区：比树干宽一圈，用来在**撞上之前**读出车的速度。
func _make_sense(i: int, x: float, ground: float) -> Area2D:
	var sense := Area2D.new()
	sense.name = "Sense%d" % i
	sense.collision_layer = 0
	# 只认车那一层（1）。地形在层 2 上，不用去凑热闹。
	sense.collision_mask = 1
	var scs := CollisionShape2D.new()
	scs.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TRUNK_W + SENSE_PAD * 2.0, TREE_HEIGHT + SENSE_VPAD * 2.0)
	scs.shape = rect
	sense.add_child(scs)
	sense.position = Vector2(x, ground - TREE_HEIGHT * 0.5)
	return sense


func _physics_process(delta: float) -> void:
	for t in _grove:
		if bool(t["dead"]):
			continue
		if bool(t["toppled"]):
			# 倒下了：只跑消失的计时，不再看车 —— 一棵树只算一次账，
			# 而且这时候它已经不在「站着推不动」那套规则里了。
			_tick_life(t, delta)
			continue
		_watch(t)


## 看着一棵站着的树：车进了它的感知区就记速度，够快推倒、够慢弹回。
func _watch(t: Dictionary) -> void:
	var sense: Area2D = t["sense"]
	if not is_instance_valid(sense):
		return
	# 每帧查重叠，不听 `body_entered`：区块是随车滚动、在车**已经**开到跟前时
	# 才建出来的，那种情况下信号根本不会响（和死亡区一个道理）。
	var seen := false
	for body in sense.get_overlapping_bodies():
		var car := car_of(body)
		if car == null or not car.alive:
			continue
		seen = true
		# 拿车壳的速度，不是碰到的那个部件的：车壳就是车。
		if car.chassis.linear_velocity.length() >= KNOCK_SPEED:
			_knock(t, car)
			return
		# 慢速这一侧：先把「撞之前跑多快」记下来 —— 感知区就是为这个存在的，
		# 等物理碰上了再读就只剩个零头了。取绝对值最大的那一次。
		if absf(car.chassis.linear_velocity.x) > absf(float(t["approach"])):
			t["approach"] = car.chassis.linear_velocity.x
		# 真的碰上了才开始反弹。**判接触要算**（[method _touching]），
		# 不能拿「在感知区里」当接触：感知区比树干每侧宽 45 像素，
		# 拿它判的话车会在离树 45 像素的地方凭空被弹回去。
		if not bool(t["bounced"]) and _touching(car, t["body"]):
			t["bounced"] = true
			_bounce(t, car)
	# 车走远了就把这一趟的账结掉，下一趟重新来。
	if not seen:
		t["bounced"] = false
		t["approach"] = 0.0


## 车壳碰到树干了吗。**算出来的**，见文件头。
##
## 树干是个竖直矩形（宽 [constant TRUNK_W]、高 [constant TREE_HEIGHT]，从树根往上
## 长）。把它换算到**车壳自己的坐标系**里，再和车壳碰撞形状的包围盒比一下 ——
## 车壳的形状、位置、角度全是从场上现读的，所以车翻着、斜着都判得对。
func _touching(car: HillCar, tree: RigidBody2D) -> bool:
	if not is_instance_valid(tree):
		return false
	var local := car.chassis.to_local(tree.global_position)
	var trunk := Rect2(
		local + Vector2(-TRUNK_W * 0.5, -TREE_HEIGHT),
		Vector2(TRUNK_W, TREE_HEIGHT)
	)
	return _chassis_box(car).intersects(trunk)


## 车壳碰撞形状的包围盒（在**车壳自己的坐标系**里）。**从场景现读**，不抄数：
## 车壳改了形状这里跟着变（和 scripts/tunnel.gd 的车高是同一条规矩）。
##
## 车壳节点（scenes/car.tscn 的 `Chassis`）底下只有车壳这一个直接挂着的碰撞形状；
## 车手那个在 `Chassis/Head` 下面，是孙子节点，认不到这里来。
## 形状认不出来时返回空盒子 = 「碰不上」，于是弹回不会触发 —— 那时候
## tests/features 的「车被弹了回来」会直接红，不会静悄悄地坏掉。
func _chassis_box(car: HillCar) -> Rect2:
	for child in car.chassis.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		var poly := cs.shape as ConvexPolygonShape2D
		if poly == null:
			continue
		var box := Rect2()
		var first := true
		for p: Vector2 in poly.points:
			var q: Vector2 = cs.position + p
			if first:
				box = Rect2(q, Vector2.ZERO)
				first = false
			else:
				box = box.expand(q)
		return box
	return Rect2()


## 慢速撞上来的**反弹**：用户要的是「推不倒就被弹回来」。
##
## 方向和大小都从撞之前记下的速度来（[member _grove] 的 `approach`），
## 整车刚体一起写 —— 它们靠铰链连着，只写车壳的话求解器会用很大的力把轮子拽回来，
## 表现是车原地抽搐一下（和 [method HillCar._right_self] 同一个道理）。
##
## 走 [method HillCar.bodies] 而不是自己列 `[chassis, rear_wheel, front_wheel]`：
## 那一对别名的轮子在独轮车上是同一个，列出来等于写两遍同一个速度。
func _bounce(t: Dictionary, car: HillCar) -> void:
	var approach := float(t["approach"])
	if is_zero_approx(approach):
		return
	var speed := absf(approach) * BOUNCE_KEEP
	var dir := -signf(approach)
	for body in car.bodies():
		body.linear_velocity.x = dir * speed


## 推倒。解冻之后就是普通物理了：车把它顶倒、它砸在地上、就地躺
## [constant DISAPPEAR_DELAY] 秒、然后消失。
func _knock(t: Dictionary, car: HillCar) -> void:
	t["toppled"] = true
	t["age"] = 0.0

	var tree: RigidBody2D = t["body"]
	if not is_instance_valid(tree):
		return
	# 车往哪边撞，树就往哪边倒。原地不动（速度全在垂直方向上）就按向右倒算。
	var dir := signf(car.chassis.linear_velocity.x)
	if is_zero_approx(dir):
		dir = 1.0

	tree.freeze = false
	# 一点平移：不给的话树是「原地转一圈」，看着像被风吹的。
	tree.linear_velocity = Vector2(dir * KNOCK_PUSH * KNOCK_SLIDE, 0.0)

	# 角冲量按「细长杆绕中心」算：I = m·h²/12，目标角速度 ω = 2·v/h
	# （树顶以 v 的速度倒下去），于是 ΔL = I·ω = m·h·v/6。
	# 这样写的好处是「树顶倒多快」由 [constant KNOCK_PUSH] 直接说了算，
	# 以后改树高或者改树重都不用回来重调这个数。
	#
	# 正角度在屏幕上就是顺时针（y 轴朝下），树顶朝 +x 倒 —— 正好是 dir 的方向。
	#
	# **直接写角速度，不用 apply_torque_impulse。** 实测：刚 `freeze = false` 的
	# 刚体上打进去的冲量会**丢掉**（撞倒那一帧量到的角速度是 0.00，树是被车推着
	# 才慢慢转的 —— 0.83 秒才 23°，而按这个冲量本该 90°）。冲量进的是「下一帧要
	# 用的那份」，而刚解冻的刚体在这一帧里会被重新塞回物理空间，那份就被清了。
	# 写速度没有这个问题，而且想表达的意思本来也就是速度（「树顶以 KNOCK_PUSH
	# 的速度倒下去」）。
	tree.angular_velocity = dir * 2.0 * KNOCK_PUSH / TREE_HEIGHT


## 倒下的树在场上还剩多久。用户要的是「撞到后 1 秒消失」。
func _tick_life(t: Dictionary, delta: float) -> void:
	var age := float(t["age"]) + delta
	t["age"] = age
	var left := DISAPPEAR_DELAY - age
	if left <= 0.0:
		_vanish(t)
		return
	if left < FADE_TIME:
		var tree: RigidBody2D = t["body"]
		if is_instance_valid(tree):
			# 淡出：连碰撞体一起「淡」掉的只有样子，碰撞体是拆节点时才走，
			# 所以这最后 0.25 秒里车照样碾得到它（那时候它是实心的，只是看不清楚）。
			tree.modulate.a = left / FADE_TIME


## 整棵拆掉：连碰撞体一起。**是拆掉不是藏起来** —— 藏起来的话树还站在
## 看不见的地方，车到跟前会被一堵空气墙弹回来。
func _vanish(t: Dictionary) -> void:
	t["dead"] = true
	var tree: Node = t["body"]
	var sense: Node = t["sense"]
	if is_instance_valid(tree):
		tree.queue_free()
	if is_instance_valid(sense):
		sense.queue_free()


## 树干。画到 TRUNK_H 为止（上面是树冠）。
func _trunk_visual() -> Polygon2D:
	var vis := Polygon2D.new()
	vis.name = "Trunk"
	var half := TRUNK_W * 0.5
	var pts := PackedVector2Array([
		Vector2(-half, 0.0), Vector2(half, 0.0),
		Vector2(half, -TRUNK_H), Vector2(-half, -TRUNK_H),
	])
	vis.polygon = pts
	# 左边暗、右边亮：树干是个圆柱，得让人看出来是哪一面朝光。
	vis.vertex_colors = PackedColorArray([
		TRUNK_DARK, TRUNK_COLOR, TRUNK_COLOR, TRUNK_DARK,
	])
	return vis


## 树冠。**只有样子，没有碰撞体**，见文件头。
##
## 树冠顶点必须正好落在 `-TREE_HEIGHT` 上：树高是「和越野车一样高」的一条需求，
## 叶子探出去几个像素就成了「看着比车高、其实碰不到」。半径里带着起伏，反推
## 会差几个像素（实测 2.8），所以先把形状画出来、量出最高点，再整团挪上去。
func _canopy_visual() -> Polygon2D:
	var vis := Polygon2D.new()
	vis.name = "Canopy"
	var r := (TREE_HEIGHT - TRUNK_H) * 0.5 + 6.0
	var center := Vector2(0.0, -(TREE_HEIGHT - r))
	var pts := PackedVector2Array()
	var colors := PackedColorArray()
	var sides := 9
	for i in range(sides):
		var angle := TAU * float(i) / float(sides)
		# 半径也带一点起伏，看着像一团叶子而不是一个圆球。
		var wobble := 1.0 + 0.12 * sin(angle * 3.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * r * wobble)
		colors.append(LEAF_COLOR.lerp(LEAF_LIGHT, 0.5 + 0.5 * -sin(angle)))
	var top := INF
	for p: Vector2 in pts:
		top = minf(top, p.y)
	var lift := -TREE_HEIGHT - top
	for i in pts.size():
		pts[i] = Vector2(pts[i].x, pts[i].y + lift)
	vis.polygon = pts
	vis.vertex_colors = colors
	return vis
