extends Area2D
## 地上的收集物：金币和油桶。

## [param amount] 对油桶是油量，对金币是面额 —— 由道具自己报，拾取方别自己猜。
signal collected(kind: String, amount: float)

@export_enum("coin", "fuel") var kind := "coin"
## 油桶能补多少油。全图统一，不随里程衰减 —— 衰减的是「多久碰得到一个」，
## 见 [method HillTerrain.fuel_chance]。
@export var fuel_amount := 50.0
## 写死的面额。**0 表示「自己抽一个」**（默认），见 [method _roll_coin_value]。
@export var coin_value := 0

## 点错一档的兜底：四档里最小那个。
const COIN_VALUES: Array[int] = [25, 50, 100, 500]
## 近处（[constant COIN_RICH_FROM] 之前）四档各占多少份，和 [constant COIN_VALUES]
## 一一对应。大面额故意稀有 —— 每块地都是 500 的话，「捡到 500」就没有任何感觉了。
##
## 加权平均 = 25×0.60 + 50×0.25 + 100×0.10 + 500×0.05 = **62.5 块一枚**。
## 地形每 800 px（80 米）刷 1~3 枚，也就是**平均 40 米一枚**、约 1560 块一公里。
##
## **份数不用凑够 100。** 抽签是按「和」归一的（见 [method _roll_coin_value]），
## 写成百分比只是读起来顺眼；真按 100 卡着写的话，改一档就得同时改另一档，
## 而这两组数其实是一起插值的（见 [method weights_at]），插完本来就不是整数。
const COIN_WEIGHTS: Array[float] = [60.0, 25.0, 10.0, 5.0]
## 远处（[constant COIN_RICH_FULL] 之后）的份数。
##
## 用户原话：「里程越远出现大面值金币概率越高」。
##
## 加权平均 = 25×0.20 + 50×0.30 + 100×0.30 + 500×0.20 = **150 块一枚**，
## 是近处的 [b]2.4 倍[/b]。**小面额没有取消，只是从 60% 掉到 20%** —— 一路全是
## 500 的话，500 就变成了新的「普通金币」，远处和近处的差别反而看不出来了。
const COIN_WEIGHTS_FAR: Array[float] = [20.0, 30.0, 30.0, 20.0]
## 从哪个里程（米）开始变富、到哪个里程涨满，中间平滑过渡（[method weights_at]）。
##
## 起点取 400 米而不是 0：前 400 米是出生区，那儿不该和出生点有任何差别 ——
## 「越远越富」要玩家先跑一段才感觉得到，一开局就富等于这条规则不存在。
##
## 终点取 2000 米：一趟全油门的极限大约 1.5 km（tests/range），能跑到 2 km 已经
## 是要一路捡油桶的水平了；再往后的地形开始变成爬不上去的墙
## （见 [constant HillTerrain.GROWTH_RATE]），奖励在那儿涨满正好对上。
const COIN_RICH_FROM := 400.0
const COIN_RICH_FULL := 2000.0


## 某个里程（米）上四档各占多少份，和 [constant COIN_VALUES] 一一对应。**纯函数**，
## 抽签（[method _roll_coin_value]）和测试都走这里，两处各写一遍的话
## 「测试测的那条曲线」和「真用的那条曲线」会分家。
##
## **平滑过渡，不是在某个里程上从一张表跳到另一张。** 跳变的话同一个 x 左右两枚
## 金币的分布完全不一样，而玩家过那个点的速度是每秒几十米 —— 看起来就是
## 「刚才好像变了一下，又好像没有」。smoothstep 两端导数为 0，接上去没有折角，
## 也不会出现「差一米就贵一倍」的档。
static func weights_at(meters: float) -> Array[float]:
	if meters <= COIN_RICH_FROM:
		return COIN_WEIGHTS.duplicate()
	if meters >= COIN_RICH_FULL:
		return COIN_WEIGHTS_FAR.duplicate()
	var t := smoothstep(COIN_RICH_FROM, COIN_RICH_FULL, meters)
	var out: Array[float] = []
	for i in COIN_VALUES.size():
		out.append(lerpf(COIN_WEIGHTS[i], COIN_WEIGHTS_FAR[i], t))
	return out


## 某个里程上**一枚金币值多少**（加权平均）。给文档和经济相关的测试用 ——
## 「越远越富」这句话到底富了多少，得有个数说出来。
static func mean_value_at(meters: float) -> float:
	var weights := weights_at(meters)
	var total := 0.0
	var sum := 0.0
	for i in COIN_VALUES.size():
		total += weights[i]
		sum += weights[i] * float(COIN_VALUES[i])
	return sum / total if total > 0.0 else 0.0

## 每档长什么样：半径、币身色、内盘色、外圈色。
##
## **四档必须一眼分得出。** 除了这把颜色和大小，币面上还直接写着面额
## （见 [method _draw_coin]）—— 光靠颜色分档要玩家背下色卡，写个数字是零成本。
## 所以四档的半径是拉开给的，字号才塞得下三位数。
##
## 碰撞体不跟着变（[code]scenes/pickup.tscn[/code] 里固定 22）—— 捡取判定
## 宁可大方一点，半径写小的那档不该变得更难捡。
const COIN_STYLE := [
	{"r": 15.0, "size": 11, "face": Color(0.95, 0.84, 0.46),
			"inner": Color(1.00, 0.95, 0.72), "ring": Color(0.66, 0.48, 0.06)},
	{"r": 18.0, "size": 13, "face": Color(1.00, 0.82, 0.15),
			"inner": Color(1.00, 0.94, 0.62), "ring": Color(0.70, 0.48, 0.03)},
	{"r": 21.0, "size": 15, "face": Color(1.00, 0.60, 0.12),
			"inner": Color(1.00, 0.84, 0.48), "ring": Color(0.62, 0.26, 0.02)},
	{"r": 24.0, "size": 18, "face": Color(1.00, 0.42, 0.26),
			"inner": Color(1.00, 0.76, 0.42), "ring": Color(0.56, 0.09, 0.07)},
]

const CAN_RED := Color(0.86, 0.18, 0.18)
const CAN_DARK := Color(0.14, 0.14, 0.16)

## 这一枚是第几档（[constant COIN_STYLE] / [constant COIN_VALUES] 的下标）。
var _tier := 0

## 币面上那个数字用的字体。
##
## **只需数字，所以直接用引擎的默认字体**，不走 [UiFonts] —— 那个是为了中文
## 才去系统里找字体文件（一个 ttc 十几兆），每枚金币都读一遍是灾难。
## 默认字体是引擎自带的，`ThemeDB.fallback_font` 只是取个引用，不读盘。
var _font: Font = null

## 上下浮动的相位。由自己的位置播种，不用全局 randf()。
var _phase := 0.0


func _ready() -> void:
	# 地形本来就是按 world_seed 生成的，收集物位置每次都一样，用位置当种子才能让
	# 「同种子 = 同一局」成立。种子用区块内的局部 x：同一个区块里几个道具的 x 不同，
	# 相位也就不同；跨区块撞相位无所谓，玩家看不出来。
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(position.x))
	_phase = rng.randf() * TAU
	_roll_coin_value()
	# 币面上要写面额，需要一个字体。数字用引擎自带的就够了（[UiFonts] 那套是给
	# 中文用的，会去读系统字体文件，不能每枚金币来一次）。
	_font = ThemeDB.fallback_font
	body_entered.connect(_on_body_entered)
	queue_redraw()


## 抽出这一枚的面额。
##
## **面额在这里抽，不在 [HillTerrain] 里抽。** 摆道具的地方只负责「在哪儿摆一个
## 金币」，值多少是这个道具有自己的属性 —— 而且地形脚本那边一改，所有地图的
## 生成结果都会跟着动（地形是按 [member HillTerrain.world_seed] 逐区块复现的），
## 那是张不能碰的多米诺。
##
## **另起一个 RNG，不复用上面那个。** 复用的话，抽面额会消耗掉相位那条随机流，
## 所有金币的浮动相位当场全变 —— 而相位是喂给 `_draw()` 的，不影响物理，
## 但改动面额顺带把画面搅一遍没有任何好处。
func _roll_coin_value() -> void:
	if coin_value > 0:
		# 场景里写死了就听它的（测试、特制关卡用），画法按最接近的那一档。
		_tier = maxi(0, COIN_VALUES.find(coin_value))
		return
	var rng := RandomNumberGenerator.new()
	# 换个乘数，和相位那条流错开
	rng.seed = int(absf(position.x)) * 2654435761 + 0x9E37
	# 权重是按里程插出来的（[method weights_at]）。**这里读的是 `position.x` 本身，
	# 不是区块内的局部 x**：地形那边摆道具时给的就是世界坐标，见
	# [method HillTerrain._build_chunk]。
	var weights := weights_at(Maps.meters_at(position.x))
	var total := 0.0
	for w in weights:
		total += w
	# **用 `randf()` 抽，不用 `randi_range()`。** 权重现在是从 smoothstep 里插出来的
	# 小数，整数抽签只能把它四舍五入回整数，那等于把平滑过渡又变回台阶 —— 而且
	# 每 500 米一档的台阶在金币上比在地形上更容易被看出来（攒一堆一比对就知道了）。
	var pick := rng.randf() * total
	for i in COIN_VALUES.size():
		pick -= weights[i]
		if pick < 0.0:
			_tier = i
			coin_value = COIN_VALUES[i]
			return
	# 浮点累减的兜底。理论上 `randf() < 1` 保证走不到这儿，但「理论上」不该是
	# 最后一档金币不出现的理由 —— 真漏下来就按最大的档发，别发一枚 0 块的。
	_tier = COIN_VALUES.size() - 1
	coin_value = COIN_VALUES[_tier]


func _process(delta: float) -> void:
	# 轻轻上下浮动，让道具在地形上更显眼。**只重画，不动 `position`** ——
	# 见 `_draw()` 里的说明。
	_phase += delta * 3.0
	queue_redraw()


func _draw() -> void:
	# 浮动做成绘制时的偏移，而不是改 `position`。
	#
	# 一开始是直接 `position.y = _base_y + sin(...)`，结果这个纯装饰的动画把
	# Area2D 的碰撞体一起带着上下动 —— 于是「这一帧能不能捡到」取决于空闲帧的
	# 节奏，同一个世界种子跑两次结果都不一样（实测真实地形里程能差 37%，
	# 1459 m vs 1994 m，因为漏捡一个油桶就会改变烧干时刻）。
	# 装饰不该进物理世界，所以现在碰撞体固定在原地，只挪画出来的东西。
	var bob := Vector2(0.0, sin(_phase) * 4.0)

	if kind == "fuel":
		var can := Rect2(Vector2(-14.0, -18.0) + bob, Vector2(28.0, 34.0))
		draw_rect(can, CAN_RED)
		draw_rect(can, CAN_DARK, false, 3.0)
		draw_rect(Rect2(Vector2(-7.0, -25.0) + bob, Vector2(14.0, 7.0)), CAN_DARK)
		var band := Color(1.0, 0.9, 0.5, 0.85)
		draw_rect(Rect2(Vector2(-9.0, -6.0) + bob, Vector2(18.0, 3.0)), band)
		draw_rect(Rect2(Vector2(-9.0, 1.0) + bob, Vector2(18.0, 3.0)), band)
	else:
		_draw_coin(bob)


## 一枚金币：币身 → 外圈 → 浅色内盘 → 面额数字。
##
## 数字是**画上去的，不是贴图**：四档 × 三位数，一共四个不同的字串，
## 没有任何理由为它做四张图。
func _draw_coin(bob: Vector2) -> void:
	var style: Dictionary = COIN_STYLE[_tier]
	var r: float = style["r"]
	draw_circle(bob, r, style["face"])
	draw_arc(bob, r, 0.0, TAU, 28, style["ring"], 3.0, true)
	# 内盘：给数字垫一块浅色的底。没有它的话，深色的数字直接压在币身上，
	# 对比度全靠币身色，红色那档（500）尤其糊。
	draw_circle(bob, r - 4.0, style["inner"])
	if _font == null:
		return
	var size: int = style["size"]
	var text := str(coin_value)
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	# `draw_string` 的 y 是**基线**，不是中心。基线下沉约四分之一字高，
	# 这里减掉 ascent 的一半把整行字摆正；`ascent` 用的是 `get_ascent(size)`，
	# 只有 `Font` 基类有，`FontFile` 也一样有。
	var baseline := bob + Vector2(-extent.x * 0.5, _font.get_ascent(size) * 0.5)
	draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			style["ring"])


func _on_body_entered(_body: Node) -> void:
	collected.emit(kind, fuel_amount if kind == "fuel" else float(coin_value))
	# 关掉监测，避免同一帧里被车身和轮子各触发一次。
	set_deferred("monitoring", false)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.18)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(queue_free)
