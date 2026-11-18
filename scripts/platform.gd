extends StaticBody2D
class_name HillPlatform
## 彩虹图上**散落在空中的一块平台**：圆弧彩虹 或 椭圆云朵。
##
## ## 一个平台一个节点，不再是一条连续的地表
##
## 这张图原来是一条**单值折线**：`Maps.arches_at` 每块区块产几个互相压着的拱，
## 地形那边取上包络（[method HillTerrain.shape_rise]），整块区块绕成一个实心多边形。
## 用户改成「散落在空中的彩虹和云朵，任意两块不相连」之后这条路走不通了：
## 一张散落的场**天然是多值的**（同一个 x 上可能压着上下两块），而单值折线画不出
## 中间那些空档。
##
## 所以平台不再由地形折线表达，改成**一块平台一个 [StaticBody2D]**，各自带自己的
## 碰撞多边形。地形那边（[method HillTerrain._build_chunk]）只负责把这一块里的平台
## 实例化出来，不建任何地块多边形。
##
## 「任意两块不相连」**不是在这里检查的**：布局（[method Maps.platforms_in_column]）
## 把每块平台严格缩在自己的格子里，而格子两两不相交 —— 不相连是构造出来的。
## 这里只负责把已经不相交的那些东西画出来。
##
## ## 云朵会散，彩虹不会
##
## 「踩上去过一会儿就消散」是这张图上一轮的用户需求（[constant LIFE_PER_PX] 拧过
## 三轮），这次没说要删，所以留着，只挂在**云朵**上。彩虹是纯造景（用户要的
## 「朝向各异、可倒扣」），不参与计时。
##
## 状态存在这个节点自己身上，而不是地形里：区块滚出视野会被回收重建，任何存在
## 地形上的状态都留不住 —— 现在这套和原来的 scripts/clouds.gd 行为一致。

## 云朵的寿命和它自己的长度成正比：每像素多少秒。数越小云散得越快。
##
## ## 这个数被 536 那条线害了
##
## 它是用户分三轮拧出来的，**原来那条链条是**：
##   1. 原始值 `1/250` —— 一秒的云长 250 像素；
##   2. 「加快为原来的 1.5 倍」→ `1/375`；
##   3. 「再缩短为原来的 0.7」→ `0.7/375`（相当于 `1/536`）。
##
## 三轮拧的时候云朵是**平地上一块会散的装饰**，尺度是「车速必须快过 536 px/s
## 才过得去（平路极速 815）」—— 也就是**只有全速冲过去才站得住**，站上去想停一下
## 是不行的。当时这个尺度是对的：散得不够快就不像「踩过就化」。
##
## ## 现在它是一块落脚点，536 就太紧了
##
## 改版之后云朵**是这张图里唯一能把车送上去的东西**（平台全不相连、车没有跳跃键），
## 也就是要踩上去**当坡道冲**，而不是「路过」。所以尺子换成 **250 px/s**：车以中速
## 也走得完一朵云，慢下来停一下也还剩时间。写成 `1.0 / 250.0` 而不是 `0.004`，
## 是为了让「要求的最低车速」这个意思留在数字里。
##
## ## 但这把尺子不是「云朵没有支撑作用」的原因
##
## 当时记的因果是「车速远低于 536，脚刚沾上云就开始淡出，还没加速云就没了」，
## 于是把尺子从 536 放到 250。**那条归因是推的，不是量的**：真因在
## [method _build_cloud] 上面那段 —— 云**一个碰撞体都没进物理空间**，
## 车是从云中间穿过去的，寿命拧到多长都一样穿过去。用户后来报的
## 「车掉到云朵上还是会下沉」是同一件事。
##
## 尺子留着，是因为 250 对「落脚点」这个新身份本来就是对的（云长 198～520，
## 中速也走得完），**不是因为它是上面那个症状的解**。动机和结论分开记 ——
## 不分开的话，下次再出问题还会照着这个错因果去拧寿命。
const LIFE_PER_PX := 1.0 / 250.0
## 消散过程本身持续多久（淡出）。
const FADE_TIME := 0.3
## 被踩住、开始倒计时之后云会变淡，玩家看得见还剩多久。这是倒计时结束时的透明度。
const HOLD_ALPHA := 0.45

const CLOUD_COLOR := Color(1.0, 0.99, 1.0, 0.97)
const CLOUD_SHADE := Color(0.78, 0.82, 0.96, 0.97)
## 云朵的厚度。直接取布局那边的同一个数 —— 平台的外接框是按它算的。
const CLOUD_H := Maps.CLOUD_H
## 圆头的分段数（云的视觉）。
const ARC_SEGS := 10
## 彩虹弧的分段数（碰撞多边形和色带都是这么多个采样点）。
##
## 12 段配着现在最大的张角，一段之间最多 `2.3 / 12 = 0.19 rad`。弦高
## `r·(1−cos 0.095)` 随半径走：半径压到地板 55 时不到 **0.3 像素**，
## 而半径上千的缓弧角度本来就小得多。折线看起来就是一条弧，再加段数只是白烧顶点。
##
## 采出来的多边形是**内接**的（顶点都在真弧上），所以它整个落在
## [method Maps.arc_bounds] 量出来的外接框**里面** —— 「不相连」少一点余量而已，
## 破不了。
const ARC_STEPS := 12
## 彩虹色带的总厚度。直接取布局那边的同一个数 —— 平台的外接框是按它算的
## （[method Maps.arc_bounds]），两边各写一个数迟早会对不上。
const BAND_THICK := Maps.ARC_THICK

## 感知区往云朵上面探多高。
const SENSE_H := 95.0
## 感知区上沿比云朵顶面高多少（要够得着车壳，又不能高到「从上面飞过去也算踩过」）。
const SENSE_UP := 88.0

enum Kind { RAINBOW, CLOUD }

## 这块是什么。见 [enum Kind]。
var kind := Kind.RAINBOW
## 云朵踩上去之后的倒计时（-1 = 还没人踩）。彩虹永远是 -1。
var _timer := -1.0
## 这块云的寿命（= 宽度 × [constant LIFE_PER_PX]）。
var _life := 0.0
## 淡出还剩多久。
var _fade := 0.0
## 倒计时已经走完（碰撞层在这一刻归零，淡出只是把消散画出来）。
var _broken := false
## 已经拆掉了。
var _gone := false
## 布局给的倾角（彩虹和云都是这个角）。见 [method var_tilt]。
var _tilt := 0.0
var _body_visual: Node2D
var _sense: Area2D


## 底下四个是**给测试读的**：云朵那一节要量的就是「寿命多长、倒计时走到哪、
## 现在多淡、断了没有」，而这些数在节点里本来就是私有的。
## 加一层只读的取数，比让测试去戳 `_life` 好 —— 至少哪天改名了，编译就红。
func var_life() -> float:
	return _life


func var_timer() -> float:
	return _timer


func var_visual() -> Node2D:
	return _body_visual


func var_broken() -> bool:
	return _broken


## 布局给这块的倾角。**存下来是为了让测试能拿它和节点上真正生效的那个角对**：
## 倾角一路是这么走的 —— `Maps.platforms_at` 掷出 → `setup` 存下来 → 建 `Body`
## 转过去。中间哪一段没接上，车就会「看着踩在云上、人已经掉下去了」。
func var_tilt() -> float:
	return _tilt


## 由 [method HillTerrain._build_chunk] 调用。**必须在进树之后**调。
##
## `data` 是 [method Maps.platforms_at] 的结论，`origin` 是这块平台的**世界坐标**
## （布局给的 y 是相对 [constant HillTerrain.GROUND_Y] 的，换算在地形那边做 ——
## 这个脚本是叶子，不认识 [HillTerrain]）。
func setup(data: Dictionary, origin: Vector2) -> void:
	kind = Kind.CLOUD if String(data["kind"]) == Maps.PLATFORM_CLOUD else Kind.RAINBOW
	_tilt = float(data["tilt"])
	position = origin
	name = "%s%d" % ["Cloud" if kind == Kind.CLOUD else "Rainbow", int(round(origin.x))]
	# 层 2 = 地面、掩码 0，和地形 / 冰面 / 石头 / 原来的云朵一样。
	collision_layer = 2
	collision_mask = 0
	# 进 "ground" 组：轮子踩在平台上算「着地」，不然踩上去那一瞬间会被算成腾空。
	add_to_group("ground")
	if kind == Kind.CLOUD:
		_build_cloud(float(data["w"]), float(data["tilt"]))
	else:
		_build_rainbow(float(data["r"]), float(data["span"]), float(data["tilt"]))


# ------------------------------------------------------------------ 云朵

## 一朵云：一块**斜着的**板子。
##
## 斜面不是造型，是这张图**唯一的上行手段**。这张图没有跳跃键 —— 车升高只能靠
## 冲上斜坡。而「任意两块不相连」意味着两块之间恒有空档，平着飞过空档只会往下掉。
## 所以云一律斜放（[constant Maps.CLOUD_TILT] ≈ 22°）：车从低的一头冲上去，在高
## 的一头被甩出去，落点就比起点高。平放的云在这张图上是死路，一朵都不出。
##
## ## 倾角挂在**这个 StaticBody2D 自己**身上
##
## 原来三样东西（碰撞体 / 视觉 / 感知区）共用一个 `Node2D "Body"`，倾角挂在它身上。
## 视觉和感知区那样是对的，**碰撞体不是**：[CollisionShape2D] 只跟**直接父节点**
## 登记，父节点不是 [CollisionObject2D] 时它一个形状都不往物理服务器上交 ——
## 不报错、不警告，节点照旧在树里、`disabled` 还是 false、形状和尺寸都读得出来，
## 只是**没有碰撞**。
##
## 云就是这么「看起来好好的」：车从它中间穿过去、一路掉出带子，而「踩上去」
## 那个感知区照旧工作（它的碰撞体的爹就是 [Area2D] 自己），所以倒计时正常开始、
## 云正常变淡、正常散掉。用户报的「车掉到云朵上还是会下沉」就是它。
##
## 所以现在两条：倾角挂在 `self` 上、三个孩子全是 `self` 的直接孩子。
## tests/shapes.gd 里那条断言问的是 [PhysicsServer2D]（`body_get_shape_count`），
## **不看节点树长什么样** —— 「碰撞体挂在谁底下」这种结构本身，错了也测不出来。
func _build_cloud(width: float, tilt: float) -> void:
	rotation = tilt

	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var box := RectangleShape2D.new()
	box.size = Vector2(width, CLOUD_H)
	cs.shape = box
	add_child(cs)
	_body_visual = _slab(width)
	add_child(_body_visual)

	# 感知区：和冰湖同一套（[Area2D] 探车）。**不能用刚体自己的
	# `get_colliding_bodies()`** —— 那要先开 contact_monitor，静态体上更是没有。
	#
	# `position` 是相对 `self` 的，而 `self` 转着 —— 所以「上」是**这块板自己的
	# 上**，斜着放的云感知区也跟着斜，和它的顶面永远贴在一起。
	_sense = Area2D.new()
	_sense.name = "Sense"
	_sense.collision_layer = 0
	_sense.collision_mask = 1
	var scs := CollisionShape2D.new()
	var sbox := RectangleShape2D.new()
	sbox.size = Vector2(width, SENSE_H)
	scs.shape = sbox
	_sense.add_child(scs)
	_sense.position = Vector2(0.0, -CLOUD_H * 0.5 - SENSE_UP + SENSE_H * 0.5)
	add_child(_sense)

	# 寿命按**斜面长**算，不按投影宽：车是沿着斜面走过去的，斜置之后走的路
	# `width / cos(tilt)` 比 `width` 长（22° 多 8%）。按投影宽算的话，同一朵云
	# 只要一斜就变难 —— 而斜置是为了让车能上去，不是为了加难度。
	# 这条换算是把 [constant LIFE_PER_PX] 那条「车速必须快过 250」的尺子**保住**。
	_life = width / cos(tilt) * LIFE_PER_PX


## 云朵的样子：**顶面是平的、两端收成半圆**。
##
## 不画成真正的椭圆，是因为椭圆的两端收成一个点：车从旁边开过来，会在最后那 20 像素里
## 先踩空（椭圆的最高点只在正中间），看着就是「车悬在云外面」。顶面平、两端圆的这团
## 东西在这么扁的宽高比（300 : 34）下看着就是一个椭圆云朵，而且**整条顶面都能踩**。
##
## 下面那道深一点的边是云的底面阴影 —— 纯白一块看着像张纸。
func _slab(width: float) -> Polygon2D:
	var vis := Polygon2D.new()
	vis.name = "Visual"
	vis.color = CLOUD_COLOR
	var r := CLOUD_H * 0.5
	var half := width * 0.5
	var pts := PackedVector2Array()
	for i in ARC_SEGS + 1:                      # 右端半圆，从顶到底
		var a := -PI * 0.5 + PI * float(i) / float(ARC_SEGS)
		pts.append(Vector2(half - r + cos(a) * r, sin(a) * r))
	for i in ARC_SEGS + 1:                      # 左端半圆，从底到顶
		var a := PI * 0.5 + PI * float(i) / float(ARC_SEGS)
		pts.append(Vector2(-half + r + cos(a) * r, sin(a) * r))
	vis.polygon = pts
	var colors := PackedColorArray()
	for p in pts:
		colors.append(CLOUD_COLOR.lerp(CLOUD_SHADE, clampf(p.y / r, 0.0, 1.0)))
	vis.vertex_colors = colors

	var shade := Polygon2D.new()
	shade.name = "Shade"
	shade.color = Color(CLOUD_SHADE.r, CLOUD_SHADE.g, CLOUD_SHADE.b, 0.55)
	shade.polygon = PackedVector2Array([
		Vector2(-half * 0.86, r * 0.35), Vector2(half * 0.86, r * 0.35),
		Vector2(half * 0.72, r * 0.95), Vector2(-half * 0.72, r * 0.95),
	])
	vis.add_child(shade)
	return vis


# ------------------------------------------------------------------ 彩虹

## 一段圆弧彩虹：六条色带沿弧铺开，朝向由 `tilt` 定（**完全随机**）。
##
## 用户要的「彩虹圆弧长度、朝向各异」：`span` 是弧的张角、`tilt` 是弧中点的方向角，
## 两个都掷骰子。**朝向不做任何限制**（含竖直、倒扣）—— 用户明确选了「纯造景，
## 能不能骑上去不管」，所以这里不为了「好骑」把角度往朝上的方向掰。
##
## 色带按半径铺：`r` 是**中径**，六条分别落在 `r ± 12.5` 之间，最外一条的外沿正好是
## `r + 15` —— 和碰撞多边形的外径是同一个数，看着踩在哪就真的踩在哪。
func _build_rainbow(r: float, span: float, tilt: float) -> void:
	var collider := CollisionPolygon2D.new()
	collider.name = "Shape"
	collider.polygon = _band_polygon(r, span, tilt)
	add_child(collider)

	var bands := Node2D.new()
	bands.name = "Bands"
	add_child(bands)
	var n := Maps.RAINBOW_COLORS.size()
	for k in n:
		var rr := r + (float(k) - float(n - 1) * 0.5) * Maps.RAINBOW_BAND
		bands.add_child(_arc_line(rr, span, tilt, Maps.RAINBOW_COLORS[k]))


## 彩虹的碰撞多边形：外弧正向 + 内弧反向，首尾各一条径向的边封口。
##
## **不是一段细带**：内外两条弧都在 `ARC_STEPS + 1` 个**相同的角度**上采样，
## 于是两端封口是两条径向的直线，中段是一圈折线。宽 30 像素的一圈折线做静态体，
## 车以 815 px/s（一帧 13.6 像素）撞上来是撞得上的 —— 13.6 < 30，穿不过去。
func _band_polygon(r: float, span: float, tilt: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var outer := r + BAND_THICK * 0.5
	var inner := r - BAND_THICK * 0.5
	for i in ARC_STEPS + 1:
		var a := tilt - span * 0.5 + span * float(i) / float(ARC_STEPS)
		pts.append(Vector2(cos(a) * outer, sin(a) * outer))
	for i in range(ARC_STEPS, -1, -1):
		var a := tilt - span * 0.5 + span * float(i) / float(ARC_STEPS)
		pts.append(Vector2(cos(a) * inner, sin(a) * inner))
	return pts


func _arc_line(radius: float, span: float, tilt: float, color: Color) -> Line2D:
	var line := Line2D.new()
	var pts := PackedVector2Array()
	for i in ARC_STEPS + 1:
		var a := tilt - span * 0.5 + span * float(i) / float(ARC_STEPS)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	line.points = pts
	line.width = Maps.RAINBOW_BAND
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	return line


# ------------------------------------------------------------------ 消散

func _physics_process(delta: float) -> void:
	if _gone or kind != Kind.CLOUD:
		return
	if _timer >= 0.0 or _broken:
		_tick(delta)
		return
	if _car_on():
		_timer = _life


## 倒计时 → 消散。**倒计时那一段里云会慢慢变淡**，玩家看得见还剩多久。
func _tick(delta: float) -> void:
	if not _broken:
		_timer -= delta
		if _timer > 0.0:
			# 用**这一朵自己的**寿命做分母，不是某个全局常数：长短不一的云
			# 才都是「从头到尾一样地淡下去」。
			_set_alpha(lerpf(HOLD_ALPHA, 1.0, _timer / _life))
			return
		_broken = true
		# **层归 0 是在倒计时走完这一刻，不是淡出结束那一刻**：倒计时就是这朵云的
		# 寿命，淡出只是把消散画出来。迟 0.3 秒才断的话，玩家能站在一朵已经化掉的云上。
		collision_layer = 0
		_fade = FADE_TIME
	_fade -= delta
	var alpha := maxf(0.0, _fade / FADE_TIME)
	_set_alpha(alpha)
	if alpha > 0.0:
		return
	_gone = true
	# 拆掉而不是藏起来：藏起来的话下一次区块重建时这个节点还挂在那儿，
	# 而且「云没了」这件事要能从场上查证（tests/shapes 就是这么验的）。
	queue_free()


func _set_alpha(alpha: float) -> void:
	if is_instance_valid(_body_visual):
		_body_visual.modulate.a = alpha


## 有没有车踩在这朵云上。踩的就是**还活着**的车，翻车之后躺在云上不算。
func _car_on() -> bool:
	if not is_instance_valid(_sense):
		return false
	for body in _sense.get_overlapping_bodies():
		var car := HillFeature.car_of(body)
		if car != null and car.alive:
			return true
	return false
