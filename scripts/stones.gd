extends HillFeature
## 山地的碎石路：一段路上撒着一排小石头，车轮碾过去会颠一下。
##
## 石头是**静态**的（[StaticBody2D]，层 2 = 地面），不是刚体。需求要的是「颠一下」，
## 而刚体石头会被车轮踢飞、顺着坡滚下去，跑第二趟的时候这一段的难度就和第一趟
## 不一样了；静态石头每次都是同一块地方、同一个高度。顺带省掉「一屏几十个刚体
## 永远在算」的开销 —— 这张图本来就靠起伏和摩擦把人磨死，不该再叠一层随机。
##
## ## 碰撞用圆，外观用多边形
##
## 两个形状**故意不一样**：圆是最好翻过去的形状（没有棱角，轮子沿着圆弧就上去了），
## 多边形只负责看着像石头。反过来拿多边形当碰撞，石头的尖角会变成一个小台阶，
## 车碾过去是「磕一下」而不是「颠一下」。
##
## ## 露出来的高度只有半径的 0.55 倍
##
## 一半多埋在土里：9~15 的半径 → 露头 5~8 像素，远矮于车轮半径（21）。所以是
## 「颠一下」，不是「撞墙」—— 撞墙式的石头会让车在这里凭空损失速度，加上山地
## 本身的大起伏，那就不再是「难」是「必死」了。


## 相邻两块石头的间距范围（像素）。比石头本身宽得多，所以缝一直都在。
const GAP_MIN := 70.0
const GAP_MAX := 140.0
## 石头半径范围（像素）。
const RADIUS_MIN := 9.0
const RADIUS_MAX := 15.0
## 露在地面以上的部分占半径的多少。剩下的埋在土里。
const EXPOSED := 0.55
## 外观多边形的边数。
const SIDES := 7

const STONE_COLOR := Color(0.46, 0.44, 0.41)
const STONE_DARK := Color(0.26, 0.25, 0.24)


func _build() -> void:
	var left := span.position.x
	var width := span.size.x
	if width <= 0.0:
		return

	# 种子取**世界坐标左沿**（= 区块序号 × 区块宽），规则和
	# [method HillTerrain._spawn_pickups] 一样：同一块地方每次跑、来回滚动都是
	# 同一批石头。用 `randi()` 之类的全局随机的话，区块随镜头回收重建一次，
	# 石头就在玩家眼前换个位置。
	var rng := RandomNumberGenerator.new()
	rng.seed = int(left)

	# 第一块从半格间距开始，最后留出 R×1.5 的余量：石头整个落在本段里，
	# 不会骑到段外的地形上（那一段的起伏不归我们管，高度是另一种算法）。
	var x := left + rng.randf_range(GAP_MIN, GAP_MAX) * 0.5
	while x < left + width - RADIUS_MAX * 1.5:
		_place_stone(x, rng)
		x += rng.randf_range(GAP_MIN, GAP_MAX)


func _place_stone(x: float, rng: RandomNumberGenerator) -> void:
	var radius := rng.randf_range(RADIUS_MIN, RADIUS_MAX)
	# 圆心埋在地表以下 `(1 - EXPOSED) × 半径` 处，露出来的正好是 EXPOSED 倍半径。
	#
	# **y 轴朝下，所以是加不是减。** 早先这里写的是减号，圆心跑到地表**以上**
	# 0.45 倍半径的地方去了，露头成了 1.45 倍半径（13～22 像素，和最粗的车轮半径
	# （21）一样高）—— 和文件头里「露头 5～8 像素，是颠一下不是撞墙」正好相反。
	var center := ground_at(x) + radius * (1.0 - EXPOSED)

	# 碰撞：一个圆。层 2 = 地面、掩码 0，和地形/冰面/桥板一样 —— 谁撞进来由
	# 对方的掩码决定（车壳和轮子的掩码是 3），静态体这边不用看别人。
	var body := StaticBody2D.new()
	body.name = "Stone%d" % int(round(x))
	body.position = Vector2(x, center)
	body.collision_layer = 2
	body.collision_mask = 0
	# 进 "ground" 组：车轮踩在石头上算「着地」，不然碾过一排石头会被算成腾空，
	# 白送腾空奖励（见 [method HillCar._touching_ground]）。车手头碰到石头也一样
	# 判翻车 —— 石头只有十几像素高，头够得着的时候车本来就是倒过来的。
	body.add_to_group("ground")
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	body.add_child(cs)
	body.add_child(_blob(radius, rng))
	add_child(body)


## 石头的样子：绕着圆心撒一圈半径带起伏的顶点。
##
## 顶点色让上面亮、下面暗（光从天上来的）—— 一个纯色的多边形看着像地上的泥点，
## 有两个明度才像块石头。y 轴朝下，所以 `y` 越大越靠下、越暗。
func _blob(radius: float, rng: RandomNumberGenerator) -> Polygon2D:
	var vis := Polygon2D.new()
	vis.name = "Visual"
	vis.color = STONE_COLOR
	var pts := PackedVector2Array()
	var colors := PackedColorArray()
	for i in range(SIDES):
		var angle := TAU * float(i) / float(SIDES)
		var r := radius * rng.randf_range(0.82, 1.0)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
		colors.append(STONE_COLOR.lerp(STONE_DARK, 0.5 + 0.5 * sin(angle)))
	vis.polygon = pts
	vis.vertex_colors = colors
	return vis
