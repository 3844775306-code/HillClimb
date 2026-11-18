extends HillFeature
## 火山口：助跑坡顶上一个 220 宽、420 深的坑，坑底是岩浆。掉下去烧死。
##
## 地形本身（助跑坡 + 坑）是 [method HillTerrain._carve] 按同一张
## [constant Maps.FEATURE_LAYOUT] 挖出来的，这里只负责往坑里摆岩浆和死亡区。
##
## 跳得过去是因为坡：车在 30° 的助跑坡上把速度转成向上的分量，到坡顶就飞出去了。
## 速度不够就飞不过 220 的宽度，掉进岩浆。这不需要在这里写任何判定 ——
## 交给重力和 [HillHazard]。

const LAVA_COLOR := Color(0.86, 0.28, 0.05, 0.92)
const LAVA_CORE := Color(1.00, 0.72, 0.18, 0.95)
const LAVA_FILL := Color(0.90, 0.30, 0.06, 0.55)

## 岩浆液面在坑深里的位置。**烧死区的顶就贴在这个液面上** —— 看见岩浆的地方
## 就是会死的地方，两个数共用这一个常量，不会各调各的。
##
## 为什么液面要抬这么高（0.35，而不是贴着坑底）：车**掉不到坑底**。实测
## （tests/pit_probe，把车丢在坑正上方）—— 车壳比后轮还往后伸 26 像素
## （车壳形状 -78…90，轮子在 -52/+58），这条尾巴会卡在 84° 的坑壁上，整辆车
## 吊在半空：车壳 y=439、后轮心 y=463、前轮心 y=450，而坑底在 690。
## 死区顶原来按 0.55 摆（y=501），吊着的车三个刚体一个都够不着 ——
## 「掉进火山口」变成了「挂在火山口壁上掉血」。抬到 0.35（y=417）之后，
## 吊着的两个轮心都在液面之下，掉进去就烧死。
##
## 也不能更高：跳过去的车在坑的上空是抛物线下坠的，液面越往上越容易把
## 「擦着坑沿飞过去」也算成掉进去。0.35 留出的余量实测够用（全油门过坑时
## 车壳最高 y=180，坑沿 270）。
const LAVA_LEVEL := 0.35


func _build() -> void:
	var left := span.position.x
	var width := span.size.x
	var depth := span.size.y
	if width <= 0.0 or depth <= 0.0:
		return

	# 浆面比坑底高一大截，看着像积了一池。左右各收 `edge * 0.45`：坑壁是余弦
	# 圆角，在液面这个高度上坑壁正好内缩 0.403 * edge（解 (1-cos(πu))/2 = 0.35
	# 得 u = 0.403），收 0.45 就刚好贴着壁、不糊到岩石上。
	var inset := float(Maps.feature_layout(Maps.FEATURE_CRATER)["edge"]) * 0.45
	var x0 := left + inset
	var x1 := left + width - inset
	var surface := rim_y + depth * LAVA_LEVEL
	var bottom := rim_y + depth + 40.0

	var lava := Polygon2D.new()
	lava.name = "Lava"
	lava.color = LAVA_COLOR
	lava.polygon = PackedVector2Array([
		Vector2(x0, surface), Vector2(x1, surface),
		Vector2(x1, bottom), Vector2(x0, bottom),
	])
	add_child(lava)

	# 中间一条更亮的芯，让「这是液体」一眼能看出来。
	var core := Polygon2D.new()
	core.name = "LavaCore"
	core.color = LAVA_CORE
	var shrink := (x1 - x0) * 0.12
	core.polygon = PackedVector2Array([
		Vector2(x0 + shrink, surface + 8.0),
		Vector2(x1 - shrink, surface + 8.0),
		Vector2(x1 - shrink, surface + 26.0),
		Vector2(x0 + shrink, surface + 26.0),
	])
	add_child(core)

	# 死亡区的顶 = 浆面。`frac` 传的就是 [constant LAVA_LEVEL]，所以「看着在岩浆
	# 里」和「算死」永远同一高度。
	add_hazard(pit_hazard_rect(depth, LAVA_LEVEL), HillCar.REASON_BURN, LAVA_FILL)
