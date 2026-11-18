extends HillFeature
class_name HillClouds
## 彩虹图：架在缝上的云朵。**踩上去之后过一会儿就消散**，然后车就掉进缝里。
##
## ## 云朵是「架在缝上的一块板」，不是地形
##
## 缝是地形形态自己挖的（[method HillTerrain._carve] 的形状那一支），云朵是另摆的
## 一个 [StaticBody2D]。这样「踩一会儿就散」才有地方可散 —— 把云做成地表折线的一部分
## 的话，消散就得回头改地形，而地形是**纯函数**（区块滚出视野再滚回来会重建），
## 改不动也留不住状态。
##
## ## 长短随机的云，寿命跟着长短走
##
## 云比缝长出多少是随机的（[constant Maps.CLOUD_PAD_LO]），而**寿命按长度等比**
## （[constant LIFE_PER_PX]）：「过一朵云要多久」本身就正比于它多长，寿命跟着长度
## 走，长云短云的难度就是同一个 —— 随机的只是观感。固定 1 秒的话，一朵长云
## 会变成「必死」，一朵短云又白给。
##
## ## 云朵问地形「缝在哪、多长出来一截」，不自己算
##
## 缝的位置要世界种子才算得出来，而 [HillFeature] 这边拿不到种子（也**不该**拿到：
## 那样就有两处各算一遍缝的宽度了）。所以走 [method HillTerrain.gap_rect] 和
## [method HillTerrain.cloud_pad]，和挖缝、摆死区共用同一个结论 ——
## 按种子掷出来的尺寸还保证区块重建之后是同一朵云。
##
## ## 计时一旦开始就不会撤销
##
## 和冰湖同一条规矩：踩上去的那一刻就定死了，车倒回去、跳起来，都照样散。
## 做成「离开就重置」的话，玩家可以反复点刹把云无限期地拖住 —— 那就不叫危险地形了。

## 云的寿命和它自己的长度成正比：每像素多少秒。数越小云散得越快。
##
## 这个数是用户分三轮拧出来的，**别凭手感重定**：
##   1. 原始值 `1/250` —— 一秒的云长 250 像素；
##   2. 「加快为原来的 1.5 倍」→ `1/375`；
##   3. 「再缩短为原来的 0.7」→ `0.7/375`。
## 合起来寿命是原始值的 0.7 倍（消散速度 ≈ 2.14 倍）。写成 `0.7 / 375.0` 而不是
## 算好的 `1/536`，是为了让上面这条链条一眼能对回去。
##
## 现在缝宽 150～220、云再长出 48～300（云长 198～520），寿命落在 0.37～0.97 秒。
## **这是本图最紧的一条线**：过一朵云要 `云长 ÷ 车速`，寿命是 `云长 ÷ 536`，
## 所以车速**必须快过 536 px/s** 才过得去（平路极速 815，拱上有起伏会更慢）。
## 每一朵都按同一把尺子算 —— 长云短云的难度是同一个，随机的只是观感。
const LIFE_PER_PX := 0.7 / 375.0
## 消散过程本身持续多久（淡出）。
const FADE_TIME := 0.3
## 云朵的厚度。**顶面要和拱脚齐平**，所以刚体中心在 `top + CLOUD_H / 2`。
const CLOUD_H := 34.0
## 感知区往云朵上面探多高。
const SENSE_H := 95.0
## 感知区上沿比云朵顶面高多少（要够得着车壳，又不能高到「从上面飞过去也算踩过」）。
const SENSE_UP := 88.0
## 圆头的分段数。
const ARC_SEGS := 10

const CLOUD_COLOR := Color(1.0, 0.99, 1.0, 0.97)
const CLOUD_SHADE := Color(0.78, 0.82, 0.96, 0.97)
## 被踩住、开始倒计时之后云会变淡，玩家看得见还剩多久。这是倒计时结束时的透明度。
const HOLD_ALPHA := 0.45

## 一朵云：body / sense / left / timer（-1 = 还没人踩）/ life / broken / fade / gone。
var _clouds: Array[Dictionary] = []


func _build() -> void:
	var terrain := terrain_node()
	if terrain == null or not terrain.has_method("gap_rect"):
		return
	# 本节点是「一块区块整宽」（见 [constant Maps.FEATURE_LAYOUT]），所以区块序号
	# 就是「本地左沿 ÷ 本地宽度」，一个区块里最多一条缝（缝宽 ≤ 220 < 800）。
	#
	# **别写成「从左沿扫到右沿」那种 range**：右沿属于下一块区块，末尾会多扫一格，
	# 于是每条缝都被摆上两朵云。两朵云的坐标完全重合（云朵用的是绝对世界坐标），
	# 看不出有两朵 —— 但踩化一朵之后另一朵还架着，车直接开过去，这张图就白做了。
	#
	# 彩虹图也不是每块区块都留缝（[constant Maps.VOID_CHANCE]）：没留缝的区块
	# `gap_rect` 返回空矩形，这儿就什么都不摆。云朵节点本身照旧每块区块都挂着，
	# 绝大多数情况下它是空的 —— 挖缝和摆云必须是同一个结论，见 [constant Maps.FEATURE_CLOUDS]。
	var w := maxf(span.size.x, 1.0)
	var index := int(round(span.position.x / w))
	var gap: Rect2 = terrain.call("gap_rect", index)
	if gap.size.x > 0.0:
		_build_cloud(gap, float(terrain.call("cloud_pad", index)))


func _build_cloud(gap: Rect2, pad: float) -> void:
	# 云比缝**两边各长出 `pad / 2`**。探出来这一段压在缝沿（拱脚）上，
	# 「架在缝上」才看着像那么回事 —— 只盖住缝的话，两端会和地面脱开一条缝。
	# `pad / 2` 最少是 [constant Maps.CLOUD_PAD_LO] 的一半，和改成长短随机之前一样。
	var over := pad * 0.5
	# 顶面高度问**缝左边一点**的地表：那里是拱脚（或者平顶右沿），正是车开过来的高度。
	# 不能拿 `rim_y`（那是整段左沿的高度），也不能拿缝里的地表（那已经掉下去了）。
	var top := ground_at(gap.position.x - over)
	var left := gap.position.x - over
	var width := gap.size.x + over * 2.0
	var mid := Vector2(left + width * 0.5, top + CLOUD_H * 0.5)

	var body := StaticBody2D.new()
	body.name = "Cloud%d" % int(round(left))
	body.position = mid
	# 层 2 = 地面、掩码 0，和地形/冰面/石头的规矩一样。
	body.collision_layer = 2
	body.collision_mask = 0
	# 进 "ground" 组：轮子踩在云上算「着地」，不然踩云那一瞬间会被算成腾空。
	body.add_to_group("ground")
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var box := RectangleShape2D.new()
	box.size = Vector2(width, CLOUD_H)
	cs.shape = box
	body.add_child(cs)
	body.add_child(_slab(width))
	add_child(body)

	# 感知区：和冰湖同一套（[Area2D] 探车）。**不能用刚体自己的
	# `get_colliding_bodies()`** —— 那要先开 contact_monitor，静态体上更是没有。
	var sense := Area2D.new()
	sense.name = "Sense%d" % int(round(left))
	sense.collision_layer = 0
	sense.collision_mask = 1
	var scs := CollisionShape2D.new()
	var sbox := RectangleShape2D.new()
	sbox.size = Vector2(width, SENSE_H)
	scs.shape = sbox
	sense.add_child(scs)
	sense.position = Vector2(mid.x, top - SENSE_UP + SENSE_H * 0.5)
	add_child(sense)

	_clouds.append({
		"body": body, "sense": sense, "left": left, "life": width * LIFE_PER_PX,
		"timer": -1.0, "broken": false, "fade": 0.0, "gone": false,
	})


## 云朵的样子：**顶面是平的、两端收成半圆**。
##
## 不画成真正的椭圆，是因为椭圆的两端收成一个点：车从拱脚开过来，在缝沿那 20 像素里
## 会先踩空（椭圆的最高点只在正中间），看着就是「车悬在云外面」。顶面平、两端圆
## 的这团东西在这么扁的宽高比（200 : 34）下看着就是一个椭圆云朵，
## 而且**整条顶面都能踩**。
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


func _physics_process(delta: float) -> void:
	for c in _clouds:
		if bool(c["gone"]):
			continue
		if float(c["timer"]) >= 0.0 or bool(c["broken"]):
			_tick(c, delta)
			continue
		if _car_on(c):
			c["timer"] = float(c["life"])


## 倒计时 → 消散。**倒计时那一段里云会慢慢变淡**，玩家看得见还剩多久。
func _tick(c: Dictionary, delta: float) -> void:
	if not bool(c["broken"]):
		c["timer"] = float(c["timer"]) - delta
		if float(c["timer"]) > 0.0:
			# 用**这一朵自己的**寿命做分母，不是某个全局常数：长短不一的云
			# 才都是「从头到尾一样地淡下去」。
			_set_alpha(c, lerpf(HOLD_ALPHA, 1.0, float(c["timer"]) / float(c["life"])))
			return
		_break(c)
	c["fade"] = float(c["fade"]) - delta
	var alpha := maxf(0.0, float(c["fade"]) / FADE_TIME)
	_set_alpha(c, alpha)
	if alpha > 0.0:
		return
	c["gone"] = true
	# 拆掉而不是藏起来：藏起来的话下一次区块重建时这个节点还挂在那儿，
	# 而且「云没了」这件事要能从场上查证（tests/features 就是这么验的）。
	(c["body"] as Node).queue_free()
	(c["sense"] as Node).queue_free()


func _break(c: Dictionary) -> void:
	c["broken"] = true
	# **层归 0 是在倒计时走完这一刻，不是淡出结束那一刻**：倒计时就是这朵云的寿命，
	# 淡出只是把消散画出来。迟 0.3 秒才断的话，玩家能站在一朵已经化掉的云上。
	(c["body"] as StaticBody2D).collision_layer = 0
	c["fade"] = FADE_TIME


func _set_alpha(c: Dictionary, alpha: float) -> void:
	var body: Node2D = c["body"]
	if is_instance_valid(body):
		body.modulate.a = alpha


## 有没有车踩在这朵云上。踩的就是**还活着**的车，翻车之后躺在云上不算。
func _car_on(c: Dictionary) -> bool:
	var sense: Area2D = c["sense"]
	if not is_instance_valid(sense):
		return false
	for body in sense.get_overlapping_bodies():
		var car := car_of(body)
		if car != null and car.alive:
			return true
	return false
