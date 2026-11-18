extends HillFeature
## 吊桥：横跨深坑的一串木板，两头钉在岸上，中间靠关节连着。
##
## 「柔软」不是画出来的，是物理自己涌出来的 —— 每块板是一个独立刚体，
## 板与板之间只有一个 [PinJoint2D]，所以桥会随车的重量下垂、会晃、会在车
## 冲上去时把车弹起来。车掉到桥下就是 [constant HillCar.REASON_FALL]。
##
## ## 为什么板子要预先摆成下垂的弧形
##
## 如果 14 块板平铺在一条直线上（总长 = 跨度），那是一个**绷紧的临界平衡**：
## 理论上撑得住，实际上任何一点扰动都会让它朝上拱或者朝下垮，而且车一压就
## 直接塌成 V 字。所以链条总长要比跨度多一截（[constant SAG]），让它在静止
## 时就处于「下垂」这个真实平衡点上。
##
## 弧垂用抛物线近似：链长 L、跨度 S、多出来的长度 E = L − S 时，
## 中点下垂 s = sqrt(3·S·E/8)。这是悬链线在小弧垂下的展开，误差远小于
## 一块板的厚度，够用了。

## 木板数量。
const PLANKS := 14
## 链条比跨度多出来的长度（像素）。0 = 绷紧的临界平衡，见文件头。
##
## **不能取大。** 弧垂越大，链子的水平张力越小（H ∝ 1/弧垂），被车压出来的
## 下沉量就越大（Δ ≈ P·S/(4H)）—— 8 像素对应静止弧垂 35 像素、过车再沉 40 上下，
## 已经是肉眼很明显的「软桥」了。早先取 20（弧垂 55），算下来过车要沉 180 像素，
## 而坑只有 380 深，车会连人带桥垂到摔死区里 —— 那是「桥自己把车弄死」。
const SAG := 8.0
## 板厚（像素）。板长由「跨度 + SAG」除以板数算出来，不写死。
const THICKNESS := 12.0
## 单块板的质量。14 块合计 280，比整辆车（174）重 —— 板的重量就是链子的张力来源
## （张力 ∝ 板重），所以**加重木板反而让桥更不容易被压塌**，同时保留下垂和回弹。
## 反过来取轻了，车一上去就把链子拽成 V 字。
const PLANK_MASS := 20.0

const ROPE_COLOR := Color(0.55, 0.42, 0.26)
const PLANK_COLOR := Color(0.42, 0.29, 0.16)
const ANCHOR_COLOR := Color(0.30, 0.24, 0.18)
## 桥底那片摔死区，用比地形暗的红棕色，掉下去时能看清。
const FALL_FILL := Color(0.35, 0.10, 0.10, 0.45)


func _build() -> void:
	var left := span.position.x
	var width := span.size.x
	if width <= 0.0:
		return

	var plank_len := (width + SAG) / float(PLANKS)
	var sag := sqrt(3.0 * width * SAG / 8.0)

	# 弧线上第 u 个位置（u 从 0 到 1）。抛物线过 (0,0)、(0.5,sag)、(1,0)。
	var point := func(u: float) -> Vector2:
		return Vector2(left + width * u, rim_y + 4.0 * sag * u * (1.0 - u))

	var shape := RectangleShape2D.new()
	shape.size = Vector2(plank_len, THICKNESS)

	# 关节打在**板缝**上：第 k 个关节在 u = k / PLANKS 处。先把位置全算出来，
	# 免得摆板子和打关节两处各算一遍、算歪一个像素。
	var knots: Array[Vector2] = []
	for k in range(PLANKS + 1):
		knots.append(point.call(float(k) / float(PLANKS)))

	# 板子摆在下垂的弧上，并且**沿着弧的切线转**。不转的话视觉上是一串
	# 平躺的板浮在斜线上，而且板端对不上关节。
	for i in range(PLANKS):
		var u := (float(i) + 0.5) / float(PLANKS)
		var body := RigidBody2D.new()
		body.name = "Plank%d" % i
		body.position = point.call(u)
		# 抛物线在 u 处的斜率：d/du[4·sag·u(1−u)] / (width) → 切线角。
		body.rotation = atan2(4.0 * sag * (1.0 - 2.0 * u), width)
		body.mass = PLANK_MASS
		# 阻尼：链条会一直微微晃，加点阻尼让它停下来，不然整个区块永远在算。
		body.linear_damp = 0.6
		body.angular_damp = 1.0
		# 层 2 = 地面，掩码 0 = 板子和板子之间不碰撞。板子互相挤压会把
		# 关节顶开，桥就炸了 —— 链式结构靠关节传力，不能靠碰撞。
		body.collision_layer = 2
		body.collision_mask = 0
		body.add_to_group("ground")
		var cs := CollisionShape2D.new()
		cs.shape = shape
		body.add_child(cs)
		# 视觉：一块木板 + 一段绳子，都挂在板子底下跟着动。
		body.add_child(_make_plank_visual(plank_len))
		body.add_child(_make_rope_visual(plank_len))
		add_child(body)

	for k in range(1, PLANKS):
		var joint := PinJoint2D.new()
		joint.name = "Joint%d" % k
		joint.position = knots[k]
		add_child(joint)
		joint.node_a = joint.get_path_to(get_node("Plank%d" % (k - 1)))
		joint.node_b = joint.get_path_to(get_node("Plank%d" % k))

	add_child(_make_anchor(knots[0]))
	add_child(_make_anchor(knots[PLANKS]))
	_anchor_joint("AnchorL", "Plank0", knots[0])
	_anchor_joint("AnchorR", "Plank%d" % (PLANKS - 1), knots[PLANKS])

	# 死区从坑沿往下 0.75 才起算，给下垂的桥面留出余量。见
	# [method HillFeature.pit_hazard_rect]。
	add_hazard(pit_hazard_rect(span.size.y, 0.75), HillCar.REASON_FALL, FALL_FILL)


## 岸上的固定桩。
func _make_anchor(pos: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "AnchorL" if pos.x < span.position.x + span.size.x * 0.5 else "AnchorR"
	body.position = pos
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(THICKNESS * 2.0, THICKNESS * 2.0)
	cs.shape = shape
	body.add_child(cs)
	var vis := Polygon2D.new()
	vis.color = ANCHOR_COLOR
	vis.polygon = PackedVector2Array([
		Vector2(-THICKNESS, -THICKNESS),
		Vector2(THICKNESS, -THICKNESS),
		Vector2(THICKNESS, THICKNESS),
		Vector2(-THICKNESS, THICKNESS),
	])
	body.add_child(vis)
	return body


## 关节的 `node_a` / `node_b` 是**相对关节自己**解析的路径（和 car.tscn 里
## 写成 `../Chassis` 是同一个道理），所以这里必须用关节的 `get_path_to`，
## 不能用本节点的 —— 用本节点的会得到 `Plank0` 这种「本节点的孩子」路径，
## 关节拿去一查是空的，于是**整条链子一个关节都没接上**，木板直接自由落体。
## 这个错不会报任何错，只会让桥安静地散架。
func _anchor_joint(anchor: String, plank: String, pos: Vector2) -> void:
	var joint := PinJoint2D.new()
	joint.name = "Joint_%s" % anchor
	joint.position = pos
	add_child(joint)
	joint.node_a = joint.get_path_to(get_node(anchor))
	joint.node_b = joint.get_path_to(get_node(plank))


func _make_plank_visual(plank_len: float) -> Polygon2D:
	var vis := Polygon2D.new()
	vis.name = "Visual"
	vis.color = PLANK_COLOR
	var h := plank_len * 0.5
	var t := THICKNESS * 0.5
	vis.polygon = PackedVector2Array([
		Vector2(-h, -t), Vector2(h, -t), Vector2(h, t), Vector2(-h, t),
	])
	return vis


## 绳子画成板子自带的一段横线，接起来就是连续的绳。比在桥节点上单画一条
## [Line2D] 好 —— 那条线不会跟着链子弯。
func _make_rope_visual(plank_len: float) -> Line2D:
	var line := Line2D.new()
	line.name = "Rope"
	line.width = 2.0
	line.default_color = ROPE_COLOR
	var h := plank_len * 0.5
	line.points = PackedVector2Array([Vector2(-h, 0.0), Vector2(h, 0.0)])
	return line
