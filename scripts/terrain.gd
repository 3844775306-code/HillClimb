extends Node2D
class_name HillTerrain
## 程序化无限地形。
##
## 地形是一条由噪声驱动的折线：每 [constant CHUNK_POINTS] 个采样点打包成一个
## 「区块」，区块随摄像机前后滚动生成与回收，因此地图在理论上没有尽头。
## 起伏幅度随前进距离增长，越远越难。
##
## 地图（[Maps]）影响四件事：配色、噪声种子、起伏幅度倍率，以及本图特有的
## 特殊地形（吊桥 / 沙尘暴 / 冰湖 / 火山口）。特殊地形会在折线上挖出坑来，
## 挖坑的逻辑必须写在 [method height_at] 里而不是只写在建区块的时候 ——
## 后者会让「地形折线」和「镜头钳位用的地面高度」对不上，车会看到两种地面。

signal pickup_collected(kind: String, amount: float)

## 相邻采样点的水平间距（像素）。越小地形越平滑，碰撞体也越密。
const POINT_SPACING := 20.0
## 每个区块包含的采样点数。
const CHUNK_POINTS := 40
const CHUNK_WIDTH := POINT_SPACING * CHUNK_POINTS
## 出生点平地的基准高度（世界坐标 y，向下为正）。
const GROUND_Y := 420.0
## 出生点平地的长度，让玩家有时间起步。
const FLAT_LENGTH := 700.0
## 从平地过渡到丘陵的渐变长度，避免出生点出现断崖。
const BLEND_LENGTH := 800.0
## 起始起伏幅度。
const BASE_AMPLITUDE := 42.0
## 每前进 1000 像素，起伏幅度增加多少。
const AMPLITUDE_PER_1000 := 7.0
## 线性增长段（[constant AMPLITUDE_PER_1000]）的幅度上限。到了这个数，
## 「每公里涨一点」这条就停住，改由 [constant GROWTH_RATE] 那段复利接手。
##
## 封的是**短波层**的幅度（波长 769 像素）。这个上限是「同一个波长上，幅度再大
## 坡度就爬不上去了」推出来的，所以它只对短波层成立 —— **长波层不受它管**，
## 见 [constant LONG_AMPLITUDE]：同样的幅度摊在更长的波长上，平均坡度反而更缓。
const MAX_AMPLITUDE := 140.0

## 起伏幅度从哪个里程开始**复利**增长（米）。用户原话：「进一步提升地形起伏随里程
## 的增长幅度：**2000米后每500米提升当前幅度的10%**」。
##
## 为什么从这里接手：线性那条 1.45 km 就撞上 [constant MAX_AMPLITUDE] 了，
## 长波层的权重 3 km 也涨满（[constant LONG_FULL]）—— 也就是说 **3 km 之后整张图
## 的难度就定型了**，再往前开只是把同一套坡重放一遍。这一段接在两者后面。
##
## **不计上限。** 用户看过实测表（见 [method _growth]）之后拍板要的就是这条曲线：
## 幅度一路涨下去，2 km 之后余量开始被吃掉、3.5 km 往后地形自己会变成爬不上去的墙。
## 所以这不是「忘了封顶」，是**故意的**——想让它长命，调小 [constant GROWTH_RATE] 就是了。
const GROWTH_FROM_METERS := 2000.0
## 复利一步走多少米（用户说的「每 500 米」）。
const GROWTH_STEP_METERS := 500.0
## 复利每步涨多少（用户说的「提升当前幅度的 10%」）。
## **是「当前幅度」的 10%，所以是复利不是单利**：4 km 处比 3.5 km 处多 10%，
## 而 3.5 km 处本身就比 3 km 处大 10%。单利（每 500 米加 14 像素）到后面就追不上了。
const GROWTH_RATE := 0.10

## 长波层的波长（1/像素）。2381 像素，和竞技场那张图一个量级（那张图本来就是
## 「坡缓但很高」的样板）。
const LONG_FREQ := 0.00042
## 长波层的地图种子偏移。**和短波层错开**：两层用同一个种子虽然理论上是去相关的
## （频率差着三倍多，取到的是置换表里完全不同的位置），但错开一个常数就没有
## 「两条曲线在原点附近碰巧同相」这种事要论证了。
const LONG_SEED_OFFSET := 8161
## 天际线层的种子偏移（同上，三层各错开一个数）。
const SKY_SEED_OFFSET := 51427
## 长波层的幅度上限（像素，峰值；已经是不用再乘的**最终值**，不像短波层那样
## 还要乘 1.6）。和短波层一样再乘 [method Maps.amp_scale]。
##
## **这是「又长又陡」里那个「长」的来源。** 短波层的波长只有 769 像素，
## 幅度爬到 [constant MAX_AMPLITUDE] 就到头了，于是：
##
##  · 难度在 1.5 km 左右**不再增长**（幅度封顶了）；
##  · 而且**长坡这个种类根本不存在**。实测（tests/slope_probe，平原三个种子平均）：
##    「平均坡度 ≥20° 且连续 400 像素」在 1.5 km 之后卡在 6% 不动，
##    「连续 700 像素」是 0.1%，「连续 1100 像素」是 **0.0%**。
##
## 加这一层之后，最陡的那一类坡仍然由短波层定（[constant MAX_AMPLITUDE] 没动），
## 长波层只管把**同样的陡度拉长**：240 像素的起伏 / 2381 像素的波长 ≈ 32°，
## 而短波层 224 像素 / 769 像素已经能到 61° 了。所以总起伏变大、爬坡反而更从容 ——
## 实测车能完整爬上的最陡坡度是 **55°**（tests/climb），32° 的长坡还在能力之内，
## 而它要爬 1200 像素才到顶，这才是「又陡又长」。
##
## **幅度是照「噪声实际能走多高」定的，不是照上面那条公式定的。** `get_noise_1d`
## 的值域名义上是 ±1，但 FBM 实际取值集中在 ±0.6 上下（短波层那个 `* 1.6` 就是
## 拿来补这个的）。所以 200 这个数**量不出 27.8°** —— 实测（tests/slope_probe，
## 平原三个种子）那一档的「≥20° 且连续 400 像素」只有 7.9%，和没加之前差不了多少。
## 按典型幅度算：240 × 0.6 = 144 像素 / 2381 像素 ≈ 20.8°，刚好压在 20° 这条线上，
## 于是在长波最陡的那几段（一个波长里有四分之一左右）判据成立。
##
## **上限是「最陡的那一段还得爬得上去」卡的**，见 [method _long_map_scale] 里那张表：
## 定这个数的时候两头的约束是「平原的概率真要涨上去」和「山地最陡的连续 400 像素
## 要留在实测爬坡能力 55° 以下」。
const LONG_AMPLITUDE := 240.0
## 长波层权重涨满的位置（像素，约 3 km）。
##
## **权重才是「随里程增长」那个旋钮**（[method _long_weight]）：短波层 1.5 km
## 就封顶了，长波层从这里接手，一路涨到 3 km。
const LONG_FULL := 30000.0

## 屋顶图那条**天际线**的幅度（像素，峰值）和波长（1/像素）。
##
## 用户要的「高地错落」：一栋房子的屋顶是**水平**的，但一栋比一栋高一点或者低一点。
## 这个起伏不是「屋顶的形状」，而是整条天际线 —— 所以它单独一层噪声，和别的图
## 一点关系都没有：形状地图（屋顶 / 彩虹）本来一条噪声都不掺。
##
## **这一层只决定「每栋房子自己多高」，决定不了落差。** 落差是
## [method Maps.drop_at] 掷出来的、按「比上一个右沿低多少」构造的
## （见 [method roof_profile]），天际线在中间怎么起伏都改动不了它。
##
## 幅度 30、波长 1/0.00025 = 4000 像素 ≈ 五栋房子：**邻居之间有差别，隔远了才
## 看得出这是条起伏的天际线**。一个八度（和长波层同理）：两个八度会在天线上
## 加出一堆小疙瘩，而每栋房子自己的屋顶是平的，疙瘩只会长在檐口上。
##
## 幅度上限是**跳距**卡的：缝两侧的高度差里有一项是「两栋房子的天际线之差」，
## 4000 像素的波长上跨 660 像素（一栋房子加一条缝）最多差 15 像素左右 ——
## 摊到 [constant Maps.DROP_LO] 那 24 像素的落差上不至于把缝抹平（见那里的算式）。
const SKY_FREQ := 0.00025
const SKY_AMPLITUDE := 30.0
## 天际线**淡入**的长度（像素，从 [constant FLAT_LENGTH] 起算）。
##
## 出生直道是平的 [constant GROUND_Y]，第一栋房子紧接在 x = 800 起步。天际线一上来
## 就是满幅度的话，接缝处会凭空落一个二三十像素的坎 —— 而那儿正是玩家第一次
## 上屋顶的地方。淡到 800 像素（一栋房子的长度）之后就是满幅度。
const SKY_FADE := 800.0
## 地形实体在地表以下**至少**延伸多厚，保证车辆永远不会从底部穿出。
##
## 「至少」是要紧的：底边不是固定在某个世界高度上，而是**本区块最深的那一处地表
## 再往下这么多**（见 [method _build_chunk]）。所以这是一个局部保证 ——
## 不管起伏长到多大、不管这张图的 `amp_scale` 是多少，任何一个区块的地表底下
## 都实打实地有 600 像素厚的实心地块。
const DEPTH := 600.0
## 摄像机前后各保留多少个区块。
const VIEW_RADIUS := 2

## 油桶出现概率的起点。**和加地图之前的值一致**，保证前面几百米的手感不变。
const FUEL_CHANCE_BASE := 0.40
## 每前进一米，油桶出现概率降多少。
const FUEL_CHANCE_PER_METER := 0.00006
## 概率下限。跑再远也留一口油，否则这张图会变成「必死」而不是「难」。
const FUEL_CHANCE_FLOOR := 0.20

## 摆冰湖之前要看多长一段助跑。
const LAKE_APPROACH := 320.0
## 这段助跑里最多允许爬多少像素，超过了就不往这儿摆冰湖。
##
## 24 像素 / 320 像素 ≈ 4°。实测（tests/rim_probe）雪地 80 个区块里 8 个湖，
## 其中 5 个前面是上坡，最陡的一个在 300 像素里爬了 144（≈26°）—— 车到湖边
## 早就没速度了，而冰面只给 0.5 秒，那是「必死」不是「危险」。
const LAKE_MAX_CLIMB := 24.0

## 摆树之前要看多长一段助跑。比冰湖长：树要的是「撞上去够快」，
## 而速度是**长坡上一点点磨掉**的，看短短 320 像素会漏掉那种「爬了很久、
## 到树跟前已经只剩怠速」的情况。
const TREE_APPROACH := 420.0
## 这段助跑里最多允许爬多少像素。
##
## 30 / 420 ≈ 4°，和冰湖同一条线。超过就说明车到树跟前提不起速，只能被弹回来
## —— 而树是**站着的障碍**，弹回来之后要是身后也还是上坡，就再也冲不起来了。
## 那等于用油耗死玩家，和冰湖前面是陡坡是同一类问题（见 [method feature_kind_at]）。
const TREE_MAX_CLIMB := 30.0

## 缝底那条死区从缝沿往下多少开始算（比例）。
##
## 和 [method HillFeature.pit_hazard_rect] 的 `frac` 是同一件事：死区只盖**下半截**，
## 这样「从缝上面飞过去」不算掉进去 —— 车飞过缝的时候离缝底还远。
const GAP_HAZARD_FRAC := 0.55
## 死区的下沿比缝底再低这么多，保证真掉进去一定落在区域内。
const GAP_HAZARD_PAD := 80.0
## 缝底死区的颜色。偏黑的深蓝，一眼看得出「这是个洞，别掉进去」。
const GAP_FILL := Color(0.04, 0.05, 0.12, 0.55)
## 彩虹图缝底死区的颜色：**全透明**。
##
## 那张图的拱底下没有地块（见 [method _build_chunk]），缝里本来就是一片天 ——
## 涂一层深蓝等于在半空挂一块黑板。掉下去就是往天里掉，判死的那条线不该看得见。
const GAP_FILL_AIR := Color(0.0, 0.0, 0.0, 0.0)

## 地形种子。**这一张图的一切都是从它推出来的**：地表高度、金币油桶、特殊地形、
## 沟、云、树林、石头（各自用自己的 [RandomNumberGenerator] 按位置或按它播种）。
## 所以换一个种子 = 换一张完整的地图，见 [constant Maps.MODES]。
##
## 默认值就是经典模式的种子（[constant Maps.CLASSIC_SEED]）。**开局由
## [method HillGame._ready] 显式赋值**：经典模式给这个常数，随机模式给
## [method Maps.random_seed] 现摇的那个。写在这里只是为了让「没有游戏节点」的
## 场景（测试里单独摆一块地形）也有个确定的值。
@export var world_seed := Maps.CLASSIC_SEED:
	set(value):
		world_seed = value
		if _ready_done:
			_configure_noise()
			_rebuild()
@export var map_id := Maps.PLAINS:
	set(value):
		map_id = value
		if _ready_done:
			_configure_noise()
			_rebuild()
@export var coin_scene: PackedScene
@export var fuel_scene: PackedScene
## 各种特殊地形的场景。哪张图出哪种由 [method Maps.feature_at] 决定，
## 这里只管「这种地形长什么样」。
@export var bridge_scene: PackedScene
@export var sandstorm_scene: PackedScene
@export var lake_scene: PackedScene
@export var crater_scene: PackedScene
@export var stones_scene: PackedScene
@export var tunnel_scene: PackedScene
@export var trees_scene: PackedScene
@export var chimneys_scene: PackedScene
## 死亡区场景。形状地图那条死区是**地形自己**摆的 ——
## 屋顶图一个特殊地形节点都没有，而那条缝照样要判死；彩虹图连地表都没有，
## 平台带下面那条判死线也是地形自己铺的（见 [method _add_gap_hazard]）。
@export var hazard_scene: PackedScene

var _noise := FastNoiseLite.new()
## 长波层。另开一条噪声而不是给 `_noise` 加八度：加八度是往**短**里长
## （lacunarity 2.0 是乘频率），而这一层要的是**长**。
var _long_noise := FastNoiseLite.new()
## 天际线层。屋顶图那「一栋比一栋高一点」的起伏（见 [constant SKY_AMPLITUDE]），
## 别的图不用 —— 但节点上照样留着，`_configure_noise` 里一把配好。
var _sky_noise := FastNoiseLite.new()
var _chunks := {}
var _target: Node2D
var _ready_done := false


func _ready() -> void:
	_configure_noise()
	_ready_done = true


func set_target(node: Node2D) -> void:
	_target = node
	_refresh_chunks()


## 返回世界坐标 x 处的地面高度（y 值）。
func height_at(x: float) -> float:
	return _base_height(x) + _carve(x)


## 没有特殊地形时的地表高度。两种情况：**噪声起伏**（八张老图）或者
## **解析形状**（屋顶 / 彩虹，见 [constant Maps.SHAPE_*]）。
##
## 形状地图一条噪声都不掺：`amp_scale` / `noise_freq` / `noise_octaves` 对它无效。
## 「两块屋顶一样高」「缝宽可控」这两条用噪声凑不出来，硬凑的结果是「看着像屋顶、
## 骑着像随机地形」。
func _base_height(x: float) -> float:
	var shape := Maps.shape_of(map_id)
	# 出生直道那一段平地的绝对高度。**彩虹图高半行**，别的图就在 `GROUND_Y` 上。
	#
	# 这个数**和 [method _build_chunk] 里铺 0 号区块那块平地用的是同一个函数**
	# （[method Maps.pad_dy]）—— 彩虹图的地块是写死成平的、不走 `height_at`，
	# 两边一旦对不上，车就出生在地块**里面**。实测的后果不是「有点怪」而是：
	# 车被实心多边形当场弹出去（12 帧里从 x=100 飞到 x=-5）、`crashed` 立刻发出来，
	# 整张图出生即死。
	var pad_y := GROUND_Y + Maps.pad_dy(map_id)
	if x < FLAT_LENGTH:
		return pad_y
	if shape == Maps.SHAPE_ROOFS:
		# 屋顶：一栋房子一个剖面（[method roof_profile]），剖面是一列折点：
		# 平段 + 钢梯 + 平段…… **屋顶本身永远是水平的**（用户要的），高低错落靠
		# 钢梯在一栋房子内部爬、靠天际线在房子之间错（见 [method _sky]）。
		#
		# 剖面和缝共用一个结论（[method Maps.span_at]）：屋顶正好铺满缝左边那一段，
		# 右边那条缝就是屋顶的右沿，所以缝的宽度就是玩家看到的宽度。
		var ri := int(floor(x / CHUNK_WIDTH))
		if ri < Maps.SHAPE_START_CELL:
			return GROUND_Y
		return roof_profile_y(roof_profile(ri), x - float(ri) * CHUNK_WIDTH)
	if shape == Maps.SHAPE_ARCHES:
		# 彩虹图**没有地表**。这个函数在这张图上只剩一个用途：给「车在哪儿」以外的
		# 东西一个参考高度 —— 相机取景、道具落点、[method skyline_at] 的兜底。
		#
		# 于是它答的是「x 上方最高的那块平台有多高，没有就是带子的底」。
		# 这**不是**地表：区块不照着它建多边形（见 [method _build_chunk] 的形状那一支），
		# 车也不站在它上面 —— 平台的碰撞体各自独立。把 `height_at` 定义成
		# 「顶着 x 的那块天花板」而不是随便一条噪声，是为了让相机和道具
		# **自动跟着平台走**：不然相机会盯着一片空天，金币会撒在没人到得了的地方。
		#
		# 带子底（`GROUND_Y + BAND`）是兜底值：那一列一块平台都没有的时候，
		# 答案就是「这块地方下面 200 米都空着」。
		#
		# **出生直道例外**（0 号区块）：那儿是真的有一块平地（见 [method _build_chunk]），
		# 「没有地表」从 1 号区块才开始。不这么办的话车一出生就在空中，
		# 连往哪儿开都还没看清就掉下去了。
		#
		# 这块平地**不在 `GROUND_Y` 上**，而在 `GROUND_Y + Maps.PAD_DY`（高半行）——
		# 理由在 [constant Maps.PAD_DY] 那段：架在 `GROUND_Y` 上的话，正好骑在
		# 出生台高度上的那半行平台会变成一堵墙，车一冲出去就撞侧面。
		if x < float(Maps.SHAPE_START_CELL) * CHUNK_WIDTH:
			return pad_y
		return GROUND_Y + Maps.ceiling_dy_at(world_seed, x)
	var amplitude := minf(BASE_AMPLITUDE + (x - FLAT_LENGTH) * 0.001 * AMPLITUDE_PER_1000, MAX_AMPLITUDE)
	amplitude *= Maps.amp_scale(map_id)
	# 长波层：**形状和短波层完全无关**（另一条噪声、另一个波长），只有幅度随里程涨。
	# 它加在 `hill` 上而不是替代短波层 —— 短波层那些小疙瘩是这个游戏的手感，
	# 长波层只是把它们托在一条更长的大坡上。
	var long_amplitude := LONG_AMPLITUDE * _long_map_scale(map_id) * _long_weight(x)
	# 复利那一段（[constant GROWTH_RATE]）**两层一起乘**：用户说的是「地形起伏」，
	# 不是「短波层起伏」。只乘长波层的话，过了 2 km 只有大坡变高、小疙瘩照旧，
	# 「颠」和「陡」这两件事就脱钩了；只乘短波层则相反 —— 一堆小疙瘩堆在几条老坡上。
	#
	# **代价是量过的，用户拍板认了**：两层一起乘、不封顶，3.5~5.5 km 那一段最陡的
	# 连续 400 px 会到 60~63°，比车能爬的 55° 还陡 —— 也就是 3.5 km 往后是**必然
	# 上不去的墙**，不是「难」；2~3.5 km 那一段也已经到 51~54°，余量只剩一两度。
	# tests/difficulty 里那条安全线因此分了三段（2 km / 3.5 km），那里写着实测值。
	# 想要长命的话就调小 [constant GROWTH_RATE]。
	var growth := _growth(x)
	amplitude *= growth
	long_amplitude *= growth
	var hill := _noise.get_noise_1d(x) * amplitude * 1.6
	hill += _long_noise.get_noise_1d(x) * long_amplitude
	# smoothstep 渐入，出生点附近保持平坦。
	var blend := clampf((x - FLAT_LENGTH) / BLEND_LENGTH, 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	return GROUND_Y - hill * blend


## 长波层的权重：出生点之后从 0 涨到 [constant LONG_FULL]（约 3 km）处的 1。
##
## 用 smoothstep（**两端斜率为 0**）而不是线性：线性的话出生点一过就开始按比例
## 往上加，前几百米的手感会跟着变 —— 而出生点这一段的手感是钉死的
## （[constant FUEL_CHANCE_BASE] 那条注释也是同一个讲究）。smoothstep 让前 500 米
## 只涨到 1% 上下，越远涨得越快。
##
## 3 km 之后封顶，所以「越远长坡越多」在 3 km 之内一直成立。**这个距离是量出来的**：
## 全油门跑一趟大约 1.5 km（tests/range），把封顶点放在 3 km 是把「增长的整条曲线」
## 铺在玩家真能跑到的里程上，而不是在看不见的地方涨完。
func _long_weight(x: float) -> float:
	var t := clampf((x - FLAT_LENGTH) / (LONG_FULL - FLAT_LENGTH), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 复利那一段的倍率：`GROWTH_FROM_METERS` 之前恒为 1，之后每 500 米乘一次 1.1。
##
## **是连续的指数，不是一级一级的台阶。** 用户说的「每 500 米提升 10%」两种写法都
## 满足（走满 500 米正好乘 1.1），但台阶那种写法在这里是**错的**：幅度是按 x
## 逐点算的，在某一个 x 上从 240 跳成 265，那一处的噪声值会被整整放大 10% ——
## 20 像素的点距配上 140 的幅度，一跳就是十几个像素，地形上会出现**每 500 米一道
## 折痕**，一眼就看得出来，而 [constant tests/difficulty.MAX_LOCAL_STEP] 那条
## 「不许有断崖」的线也就跟着红了。指数在每一处都是光滑的，走满 500 米仍然是精确的
## 1.1 倍。
##
## 用 [method Maps.meters_at] 而不是拿 `x - FLAT_LENGTH` 换算：里程的零点在
## [constant Maps.START_OFFSET]，和出生平地（[constant FLAT_LENGTH]）不是一回事，
## 两套混着用会差出 50 米。
##
## ## 实测代价（tests/difficulty，「连续 400 px 的平均坡度」最大的一处）
##
## 两层一起乘、不封顶。红线 53°（[constant tests/difficulty.MAX_SUSTAINED]），
## 车实测能爬 55°（tests/climb）：
##
## | 里程段 | 平原 | 竞技场 | 火山 | 山地 |
## |---|---|---|---|---|
## | 2.0~3.5 km（倍率 1.0→1.35） | 46° | **54°** | 52° | 51° |
## | 3.5~5.5 km（倍率 1.35→1.95） | 60° | 62° | 61° | **63°** |
##
## 也就是说：**2 km 之后余量开始被吃掉**（竞技场 2.0~3.5 km 就已经 54°，
## 离车的 55° 只差一度），**3.5 km 之后是必然上不去的墙**。
## `tests/difficulty` 的安全线因此分三段：2 km 之内按老红线 53°，
## 2~3.5 km 放宽到车的极限 55°，再往外只打数。
## 用户是看着这张表选的这一档 —— 别当成 bug 去「修」。
func _growth(x: float) -> float:
	var steps := (Maps.meters_at(x) - GROWTH_FROM_METERS) / GROWTH_STEP_METERS
	if steps <= 0.0:
		return 1.0
	return pow(1.0 + GROWTH_RATE, steps)


## 长波层吃的地图倍率：**开平方，不是原样乘**。
##
## 短波层乘 `amp_scale` 是对的（那张图「起伏大」就是大在短波层上），但长波层再按
## 原样乘一遍会把**最陡的那几张图顶到车的爬坡极限上**。实测（tests/difficulty，
## 「连续 400 像素的平均坡度」的最大值）：
##
## | 地图 | amp_scale | 只有短波层 | 长波层原样乘 | 长波层开平方 |
## |---|---|---|---|---|
## | 平原 | 1.0 | 32.6° | 43.5° | 43.5° |
## | 竞技场 | 2.2 | 39.4° | **54.4°** | 见下 |
## | 火山 | 1.25 | 38.9° | 48.6° | 见下 |
## | 山地 | 1.35 | 43.5° | **53.5°** | 见下 |
##
## 车能完整爬上的最陡坡度是 **55°**（tests/climb）—— 原样乘等于在竞技场和山地上
## 造出**贴着极限**的长坡，而那是「爬不上去」不是「难」。竞技场尤其说不过去：
## 它自己的招牌文案是「坡又长又**缓**」。
##
## 开平方把 2.2 拉回 1.48、1.35 拉回 1.16，于是「越陡的图长坡也越陡」这个方向
## 还在，但不会叠成双倍。平原（1.0）不折不扣 —— 基准图的增长曲线一点没被削。
static func _long_map_scale(map_id: String) -> float:
	return sqrt(Maps.amp_scale(map_id))


## 天际线：世界坐标 `x` 处「这一带的屋顶基准高度」。
##
## 用户要的「高地错落」分两层，这是**房子之间**那一层（房子内部错落靠钢梯，
## 见 [method roof_profile]）：一栋房子一个高度，邻居之间差个十几二十像素，
## 隔上四五栋看得出这是一条起伏的天际线。
##
## 淡入（[constant SKY_FADE]）是为了出生直道：直道是平的 [constant GROUND_Y]，
## 第一栋房子紧接在 x = 800 起步，天际线要是在那儿已经是满幅度，接缝处就会
## 凭空落一个二三十像素的坎。
##
## **它改动不了落差。** 落差是 [method Maps.drop_at] 掷出来的、按「比上一个右沿
## 低多少」构造的（见 [method roof_profile]）：天际线在两栋之间怎么起伏，
## 测出来的落差都还是那个数。
func _sky(x: float) -> float:
	var u := clampf((x - FLAT_LENGTH) / SKY_FADE, 0.0, 1.0)
	return GROUND_Y + SKY_AMPLITUDE * _sky_noise.get_noise_1d(x) * (u * u * (3.0 - 2.0 * u))


## 第 `index` 块区块那栋房子的**屋顶剖面**。
##
## 返回：
##  · `len`   —— 屋顶右沿在区块内的坐标（= 缝的左沿，[method Maps.span_at]）
##  · `y0`/`y1` —— 左沿 / 右沿的高度（世界 y）
##  · `pts`   —— 折点表（[PackedVector2Array]，区块内坐标），从 `(0, y0)` 到 `(len, y1)`
##  · `ramps` —— 哪几段是钢梯（段号 = 起点折点的下标，`i` 表示 `pts[i]` → `pts[i+1]`）
##
## 剖面是**平段和钢梯交替**：平段上地表是水平的（用户要的「屋顶仅为水平直线」），
## 钢梯按 smoothstep 爬一段（两头斜率为 0，见 [method roof_profile_y]）。
## 最左那一段至少 [constant Maps.ROOF_LAND]（落点），最右那一段至少
## [constant Maps.ROOF_LEDGE]（跳台），中间的平路长度、每段钢梯爬多高都随机。
##
## **落差和天际线是两种东西，各自独立**：
##  · 左沿高度 = `上一栋的右沿 + 本缝的落差`。上一栋的右沿就是**世界坐标上一个
##    屋顶真正结束的地方**，所以落差是构造出来的：天际线在两栋之间怎么起伏都
##    改动不了它。
##  · 右沿高度 = 本栋那个位置的天际线（[method _sky]）。
##    于是这一栋的**总爬升 = 落差 − 天际线的漂移**，正好就是「上一栋的右沿 →
##    这一栋的右沿」这段真实的高差 —— 房子该爬多高，一格不多一格不少。
##
## 第一栋（[constant Maps.SHAPE_START_CELL]）的左沿**钉在 [constant GROUND_Y]**：
## 它前面没有缝，接的是出生直道，压低的话直道尽头会凭空多出一个坎。
##
## 纯函数：区块会滚出视野再重建，同一栋房子必须每次长得一模一样。
func roof_profile(index: int) -> Dictionary:
	var span := Maps.span_at(world_seed, index)
	var y1 := _sky(float(index) * CHUNK_WIDTH + span)
	var y0 := GROUND_Y
	if index > Maps.SHAPE_START_CELL:
		# **加**不是减：y 轴朝下，「低一截」就是 y 大一点（[method _carve] 里也是
		# `dig += 落差`）。上一栋的右沿就是世界坐标上一个屋顶真正结束的地方，
		# 所以落差是构造出来的 —— 天际线在中间怎么起伏都改不动它。
		var prev_span := Maps.span_at(world_seed, index - 1)
		y0 = _sky(float(index - 1) * CHUNK_WIDTH + prev_span) \
				+ Maps.drop_at(world_seed, index - 1)

	var dice := Maps.roof_dice(world_seed, index)
	var rise := y0 - y1          # 正 = 这栋房子整体往**上**走（y 轴向下，所以是减）
	var n := _ladder_count(rise, span, int(dice["ladders"]), dice["rises"])
	var runs := _ladder_runs(rise, n, dice["rises"])
	var run_len := 0.0
	for r in runs:
		run_len += absf(r) * Maps.LADDER_RUN
	# 中间那 n − 1 段平路总共能分到多少。**末尾那段平路（跳台）不算在内**：
	# 它是余量，最后按「到缝的左沿为止」给，这样折线右端一像素都不差。
	var free := maxf(span - Maps.ROOF_LAND - Maps.ROOF_LEDGE - run_len, 0.0)
	var mids := _section_lengths(free, n, dice["sects"])

	var pts := PackedVector2Array()
	var ramps := PackedInt32Array()
	var x := Maps.ROOF_LAND
	var y := y0
	pts.append(Vector2(0.0, y0))
	pts.append(Vector2(x, y))
	for k in n:
		ramps.append(pts.size() - 1)
		x += absf(runs[k]) * Maps.LADDER_RUN
		y -= runs[k]
		pts.append(Vector2(x, y))
		if k < n - 1:
			x += mids[k]
			pts.append(Vector2(x, y))
	# 末点**直接钉在 `(span, y1)` 上**，不是接着累加：累加出来的和理想值差着浮点的
	# 最后几位，而这一点正好压在缝的左沿上 —— 差一丝就是多边形上的一道缝。
	pts.append(Vector2(span, y1))
	return {"len": span, "y0": y0, "y1": y1, "pts": pts, "ramps": ramps}


## 这栋房子分几段钢梯。候选值来自骰子（[method Maps.roof_dice]），这里按两个
## 「分不下去」的条件往下减：
##
##  · **爬升不够分**：每段至少要爬 [constant Maps.LADDER_MIN]。十二像素高的房子分
##    三段，每段只剩四像素 —— 那不是梯子，是一道搓板。
##  · **跨度不够平路**：每两段钢梯之间至少 [constant Maps.SECTION_MIN] 的平路，
##    另外还要留出落点 [constant Maps.ROOF_LAND] 和跳台 [constant Maps.ROOF_LEDGE]。
##    一栋房子一共才 650～670 宽，450 给了落点和跳台，剩下的还要摊钢梯本身的长度
##    （`爬升 × LADDER_RUN`）—— 三段是**紧的**，挤不下就减成两段。
func _ladder_count(rise: float, span: float, want: int, rises: Array) -> int:
	var n := mini(want, maxi(1, int(absf(rise) / Maps.LADDER_MIN)))
	while n > 1:
		var used := 0.0
		for r in _ladder_runs(rise, n, rises):
			used += absf(r) * Maps.LADDER_RUN
		if span - Maps.ROOF_LAND - Maps.ROOF_LEDGE - used >= float(n - 1) * Maps.SECTION_MIN:
			break
		n -= 1
	return n


## 把总爬升 `rise` 分成 `n` 段，每段按权重分、每段至少 [constant Maps.LADDER_MIN]。
##
## **最后一段吃余量**，所以加起来正好是 `rise`：屋顶右沿的高度不会因为分段的
## 舍入偏掉一丝。返回的是**带符号**的爬升（负 = 这一段往下走，整栋房子都在往下
## 错落时就是它），画梯子那边按绝对值取长度。
static func _ladder_runs(rise: float, n: int, weights: Array) -> Array[float]:
	var sign := -1.0 if rise < 0.0 else 1.0
	var mag := absf(rise)
	var total := 0.0
	for k in n:
		total += float(weights[k])
	var runs: Array[float] = []
	var left := mag
	for k in n:
		var r := left
		if k < n - 1:
			r = mag * float(weights[k]) / maxf(total, 0.0001)
			# 后面每段至少还要 LADDER_MIN，所以这一段最多分到这么多。
			r = minf(r, left - float(n - 1 - k) * Maps.LADDER_MIN)
			r = maxf(r, Maps.LADDER_MIN)
		runs.append(sign * r)
		left -= r
	return runs


## 把 `free` 这么多像素分给 `n − 1` 段平路（钢梯与钢梯之间的那些），每段至少
## [constant Maps.SECTION_MIN]。`n` 为 1 时没有中间段，返回空数组。
##
## **最后一段吃余量**（和 [method _ladder_runs] 同一个道理），于是这些平路加起来
## 正好是 `free`。
static func _section_lengths(free: float, n: int, weights: Array) -> Array[float]:
	var mids: Array[float] = []
	if n <= 1:
		return mids
	var total := 0.0
	for k in n - 1:
		total += float(weights[k])
	var left := free
	for k in n - 1:
		var seg := left
		if k < n - 2:
			seg = free * float(weights[k]) / maxf(total, 0.0001)
			seg = minf(seg, left - float(n - 2 - k) * Maps.SECTION_MIN)
			seg = maxf(seg, Maps.SECTION_MIN)
		mids.append(seg)
		left -= seg
	return mids


## 剖面在区块内坐标 `lx` 处的高度（世界 y）。`prof` 是 [method roof_profile] 的结论。
##
## 折点之间**钢梯按 smoothstep、平段按常数**：
##
##  · 平段返回的是一整段同一个数，地表真的是一条水平线（用户要的「屋顶仅为水平
##    直线」）—— 采样点落在哪儿都不影响高度。
##  · 钢梯两头斜率为 0、中间最陡（`1.5 / LADDER_RUN` ≈ 55°，就是用户选的那个坡度）。
##    直线梯子会在顶端留一个折角，车高速冲上去会被那道折角弹起来；两头平着接，
##    上梯子和下梯子都不掉速度。
##
## `lx` 超出屋顶右沿时**保持右端的值**（不是回 0）：缝的右壁是从屋顶右沿往下掉的，
## 这一段就是那道壁的上半截（见 [method _carve]）。
static func roof_profile_y(prof: Dictionary, lx: float) -> float:
	var pts: PackedVector2Array = prof["pts"]
	if pts.is_empty():
		return GROUND_Y
	var ramps: PackedInt32Array = prof["ramps"]
	for i in pts.size() - 1:
		if lx > pts[i + 1].x:
			continue
		if not ramps.has(i):
			return pts[i].y
		var d := pts[i + 1].x - pts[i].x
		if d <= 0.0:
			return pts[i + 1].y
		var u := clampf((lx - pts[i].x) / d, 0.0, 1.0)
		return lerpf(pts[i].y, pts[i + 1].y, u * u * (3.0 - 2.0 * u))
	return pts[pts.size() - 1].y


## 特殊地形在地表上挖出来的深度（正数 = 往下挖，负数 = 往上抬）。
##
## 这是**纯函数**：一块地方挖多深只取决于「哪个区块、这张图、这个种子」，不看
## 区块有没有被建出来、也不看建出来的顺序 —— 区块会随镜头来回滚动反复重建，
## 带状态的挖法会让沟在玩家眼前变位置。
##
## 分两项：`_carve_in_chunk` 是坑和助跑坡（只和布局表有关），`_level` 是把两端
## 垫平（要看自然地表的高低，所以不能用静态那一份）。
func _carve(x: float) -> float:
	var index := int(floor(x / CHUNK_WIDTH))
	var shape := Maps.shape_of(map_id)
	# 彩虹图**什么都不挖**：这张图没有地表可以挖。平台是各自独立的刚体，
	# 区块一个地块多边形都不建（见 [method _build_chunk] 的形状那一支），
	# `_carve` 交出来的东西没人用。
	#
	# 写成一条早退而不是「让下面那支算出 0」：下面那支每一行都是「在一条折线上
	# 挖个坑」，对一张没有折线的图来说整段都是空转，留着只会让人以为还有用。
	if shape == Maps.SHAPE_ARCHES:
		return 0.0
	# 屋顶的「缝」是形态的一部分，不是特殊地形挖出来的坑：整张图一条特殊地形
	# 都没有，缝照样每块区块末尾都有。
	#
	# **缝的左沿就是屋顶的右沿**（`Maps.span_at`，屋顶长度那个数），右沿压着区块边界，
	# 所以缝永远不跨区块 —— 挖缝的只管自己这一块，摆死区的也只管自己这一块，
	# 两边不必看邻居。屋顶长什么样基本不影响这里：屋顶的右沿落在它自己那个高度上，
	# 缝的右壁接的是**下一栋的左沿**，那个高度是 [method roof_profile] 按落差构造出来的
	# （[method roof_profile_y] 在屋顶右沿之外保持右端的值，正是为这一条）。
	if shape == Maps.SHAPE_ROOFS:
		if index < Maps.SHAPE_START_CELL:
			return 0.0
		var left := _rim_lx(index)
		var rel := x - float(index) * CHUNK_WIDTH
		var dig := _basin(rel, left, CHUNK_WIDTH, Maps.GAP_DEPTH, Maps.GAP_EDGE)
		# 缝右半边那条落差（[method Maps.drop_at]，每缝一条）。
		#
		# **必须落在缝里面，不能落在区块边界上。** 右沿压在边界上，而下一栋房子
		# 的起点比本块的屋顶右沿低那么多 —— 落差要是算在下一栋头上，本块最后那
		# 40 像素的缝壁（[method _basin] 右边的倒角）就还顶在老高度上，比下一栋
		# 屋顶高出一个台阶。车从缝的左沿起跳（老高度，一步没动），出手就撞在
		# 这个台阶上 —— 缝的右壁成了绊脚的坎。
		#
		# 加在这里还有一个好处：区块两端的采样点（`rel` = 0 和 `rel` = 800）
		# 正好是同一根世界坐标，本块的尾巴和下一块的开头对得上（都是
		# `上一栋的右沿 − 落差`），两个多边形在边界上不会错开。
		dig += Maps.drop_at(world_seed, index) * _gap_drop(rel, left, CHUNK_WIDTH - left)
		return dig
	var kind := feature_kind_at(index)
	if kind == Maps.FEATURE_NONE:
		return 0.0
	# 换算成区块内的相对坐标，再按这张图的布局挖。布局保证整个地形都在本区块内，
	# 所以不用去看前后邻居。
	#
	# 「环形山一排几个」要世界种子和区块号才算得出来，[method _carve_in_chunk]
	# 拿不到这两样（它连 lx 都只是区块内坐标），所以个数在这里算好传进去 ——
	# 那个函数保持「给什么挖什么」的纯函数，于是可以单独测。
	var count := Maps.CRATERS_MIN
	if kind == Maps.FEATURE_CRATERS:
		count = Maps.craters_at(world_seed, index)
	return _carve_in_chunk(kind, x - float(index) * CHUNK_WIDTH, count) \
			+ _level(kind, index, x)


## 需要「门口得能提起速来」的地形：种类 → [助跑窗口, 允许爬升]。
##
## 冰湖要的是速度（冰面只给 0.5 秒），树要的也是速度（撞不快就推不倒、
## 被弹回来）。两种都是「车到跟前没速度 = 玩家做什么都没用」，所以同一条规则。
## 表里没有的种类一律放行。
const APPROACH_LIMIT := {
	Maps.FEATURE_LAKE: [LAKE_APPROACH, LAKE_MAX_CLIMB],
	Maps.FEATURE_TREES: [TREE_APPROACH, TREE_MAX_CLIMB],
}


## 本区块要摆哪种特殊地形。**比 [method Maps.feature_at] 多一层地形方面的否决。**
##
## 冰湖和树前面那段是陡上坡的话，车到跟前根本没有速度 —— 冰面只给 0.5 秒、
## 树只认高速撞击，那不是「难」是「必死」：玩家没有任何操作能改变结果。
## 这种位置就不摆，这一块当普通地形过。规则和窗口长度都在 [constant APPROACH_LIMIT]。
##
## 判定必须在**地形**这边做，因为上坡与否是噪声的事，而 [Maps] 是叶子类，
## 够不着地表高度。挖坑（[method _carve]）和摆东西（[method _spawn_feature]）
## 都问这一个函数，所以不会出现「挖了坑但不摆桥」。
func feature_kind_at(index: int) -> String:
	var kind := Maps.feature_at(world_seed, map_id, index)
	if not APPROACH_LIMIT.has(kind):
		return kind
	var limit: Array = APPROACH_LIMIT[kind]
	var layout := Maps.feature_layout(kind)
	var x0 := float(index) * CHUNK_WIDTH + float(layout["inset"])
	return Maps.FEATURE_NONE if _climb_before(x0, float(limit[0])) > float(limit[1]) else kind


## `x` 之前那段助跑里，车爬了多少像素（正数 = 上坡）。
##
## 用 [method _base_height] 而不是 [method height_at]：助跑窗口只有几百像素，
## 而「相邻区块不连放两个特殊地形」（[method Maps.feature_at]）保证了窗口里
## 最多碰上一个区块的边 —— 那个区块必定**没有**特殊地形，所以那段路就是原始
## 地表，正是用 [method _base_height] 算的。
##
## `window` 默认给冰湖那一档，是为了让「只想量一下前面陡不陡」的调用方
## （tests/placement）不用知道有哪几种窗口。
func _climb_before(x: float, window := LAKE_APPROACH) -> float:
	return _base_height(x - window) - _base_height(x)


## 把坑两端的岸垫到同一个高度（外加火山口的 `drop` 倾斜）。
##
## 坑是「以**当地**地表为基准」往下挖的（[method _carve_in_chunk]），而自然地表
## 是有起伏的 —— 于是左沿落在 `_base_height(x0)`、右沿落在 `_base_height(x1)`，
## 两端能差出一大截。实测（tests/rim_probe，种子 1337、扫 80 个区块）：吊桥两端
## 最大差 **158 像素**、火山口 **134 像素**。而桥面和冰面都是按左沿高度（`rim_y`）
## 摆的，所以右端要么悬在半空、要么埋进土里。
##
## 做法：在坑那一段把「当地地表相对左沿的高度差」减掉，让整段落在左沿的高度上，
## 两端各用一段 smoothstep 平滑接回自然地表。**窗口正好用满区块的左右余量**
## ——左边到区块起点（`inset`），右边到区块终点（`CHUNK_WIDTH − inset − width`）
## ——于是有两个好处：
##
##   · 窗口的边缘恰好压在区块边界上，权重正好是 0 —— 和隔壁区块（没特殊地形、
##     一点不垫）无缝接上，缝合处不会多出一道坎。这也是为什么**不需要**给每种
##     地形另填一个「垫多长」的数：能垫多长，区块的余量说了算。
##   · 只有一个例外要注意：吊桥 / 冰湖左边的过渡段只有 `inset`（120 像素）长，
##     赶上 100 像素的高差就是个 40° 的坡。实测最陡的一处 26°，而游戏里 35° 的
##     坡本来就爬得上去（见 [constant Maps.MAPS] 雪地那行的实测注释）。
##
## 火山口的 `drop` 让右沿比左沿低那么多：按跨度线性倾斜，助跑坡顶到落点变成
## 一路下坡，起跳高、落地低。
func _level(kind: String, index: int, x: float) -> float:
	var layout := Maps.feature_layout(kind)
	# **不能只看 `depth` 是不是 0。** 隧道是「垫平但不挖坑」：`depth` 0、`level` 1，
	# 它要的正是这一段的垫平（洞底不平车在里面一颠就撞顶）。判据和
	# [method Maps.digs] 一样，两处必须是同一条，否则会出现「测试认为要检查、
	# 地形却不垫」这种最难查的不一致。
	if not Maps.digs(kind):
		return 0.0                      # 不碰地表的地形（沙尘暴 / 石子 / 树）
	var inset := float(layout["inset"])
	var width := float(layout["width"])
	var x0 := float(index) * CHUNK_WIDTH + inset
	var x1 := x0 + width
	var w := _level_weight(x, x0, x1, inset, CHUNK_WIDTH - inset - width)
	if w <= 0.0:
		return 0.0
	var drop := float(layout.get("drop", 0.0))
	var t := clampf((x - x0) / width, 0.0, 1.0)
	return (_base_height(x0) + drop * t - _base_height(x)) * w


## 垫平的权重：坑那一段是 1，往两边各用余量那么长平滑落到 0。
##
## 权重在窗口边缘**恰好**是 0（不是「约等于」），区块缝合处才不会有台阶。
static func _level_weight(x: float, x0: float, x1: float, pad_l: float, pad_r: float) -> float:
	if x <= x0 - pad_l or x >= x1 + pad_r:
		return 0.0
	if x < x0:
		var u := (x - (x0 - pad_l)) / pad_l if pad_l > 0.0 else 1.0
		return u * u * (3.0 - 2.0 * u)
	if x > x1:
		var u := ((x1 + pad_r) - x) / pad_r if pad_r > 0.0 else 1.0
		return u * u * (3.0 - 2.0 * u)
	return 1.0


## 区块内相对坐标 `lx` 处的开挖深度。火山口的助跑坡是往上抬（负数）。
##
## 静态是为了能单独测：给定地形种类和区块内坐标，结果只由 [constant Maps.FEATURE_LAYOUT]
## 决定，和噪声、种子、区块都无关。
static func _carve_in_chunk(kind: String, lx: float, craters := Maps.CRATERS_MIN) -> float:
	var layout := Maps.feature_layout(kind)
	var depth := float(layout["depth"])
	var x0 := float(layout["inset"])
	var carve := _raise(lx, layout)
	if depth > 0.0:
		if kind == Maps.FEATURE_CRATERS:
			# 环形山是一**排**坑，不是一个。个数由调用方给（默认最少的那一档），
			# 每个坑的形状和个数无关 —— 所以单独测形状的时候不必知道种子。
			carve += _notches(lx, x0, layout, craters)
		else:
			carve += _basin(lx, x0, x0 + float(layout["width"]), depth, float(layout["edge"]))
	return carve


## 月球的一排环形山：`count` 个「凹」字形的坑一字排开，整排**居中**放在本段里。
##
## 和 [method _basin] 那种「又宽又浅的碗」是反着来的：`edge` 很小（22 像素掉 90，
## 约 76°），侧壁接近垂直 —— 车轮碾上去**直接陷进去，靠动力爬不出来**。
## 「陡」在这里是设计出来的玩法（借低重力跃过去），不是挖坏了；tests/hazards 里
## 「没有断崖」那条判据是按 `depth·π/(2·edge)` 算上限的，陡也跟着一起放大，
## 所以它照样过。
##
## 坑与坑之间留 [constant Maps.FEATURE_LAYOUT] 里的 `notch_gap`，是一道和坑沿
## 齐平的窄埂 —— 整排看起来是「凹凹凹」而不是一个大坑。
static func _notches(lx: float, x0: float, layout: Dictionary, count: int) -> float:
	var notch := float(layout["notch"])
	var gap := float(layout["notch_gap"])
	var depth := float(layout["depth"])
	var edge := float(layout["edge"])
	var total := float(count) * notch + float(count - 1) * gap
	var start := x0 + (float(layout["width"]) - total) * 0.5
	var carve := 0.0
	# 每个坑落在自己的 [a, a + notch] 区间里，区间之间隔着 gap，所以同一处 lx
	# 最多命中一个 `_basin`（其余返回 0），加起来就是「那一个」。
	for i in count:
		var a := start + float(i) * (notch + gap)
		carve += _basin(lx, a, a + notch, depth, edge)
	return carve


## 火山口前面那段助跑坡把地面抬高多少（负数 = 往上抬）。
##
## **坡顶必须一直保持到坑的右沿，坑后面还要再接一段下坡。** 只在坑左沿之前抬
## 的话，坑沿会比坡顶矮一个 `ramp_h`，中间凭空多出一道 150 像素的垂直悬崖 ——
## 车冲上去等于撞墙。右沿同理，不收尾的话对岸又是一道悬崖。
##
## `ramp_h` 为 0 的地形（吊桥 / 沙尘暴 / 冰湖）走第一个 if 直接返回 0，所以这段
## 代码对它们完全无影响。
static func _raise(lx: float, layout: Dictionary) -> float:
	var ramp := float(layout["ramp_len"])
	var h := float(layout["ramp_h"])
	if ramp <= 0.0 or h <= 0.0:
		return 0.0
	var x0 := float(layout["inset"])
	var width := float(layout["width"])
	var back := float(layout["back_len"])
	if lx <= x0 - ramp or lx >= x0 + width + back:
		return 0.0
	if lx <= x0:
		var u := (lx - (x0 - ramp)) / ramp
		return -h * (u * u * (3.0 - 2.0 * u))          # 上坡：smoothstep 渐入
	if lx <= x0 + width:
		return -h                                       # 坑沿：保持坡顶高度
	var d := (lx - (x0 + width)) / back
	return -h * (1.0 - d * d * (3.0 - 2.0 * d))        # 收尾：平滑落回原地表


## 一段两头平滑、中间平底的坑：x0 处 0，中间 depth，x1 处回到 0。
##
## 用余弦而不是直线，是为了让坑沿有圆角 —— 直角坑沿会让轮子磕在棱上，
## 测出来的「掉进坑里」就不再是地形问题而是碰撞形状问题。
static func _basin(x: float, x0: float, x1: float, depth: float, edge: float) -> float:
	if x <= x0 or x >= x1:
		return 0.0
	if x >= x0 + edge and x <= x1 - edge:
		return depth
	var u := (x - x0) / edge if x < x0 + edge else (x1 - x) / edge
	u = clampf(u, 0.0, 1.0)
	return depth * (0.5 - 0.5 * cos(PI * u))


## 缝里面那道落差的形状：缝的左沿是 0、区块边界是 1（乘上这条缝自己的落差
## [method Maps.drop_at] 就是像素）。只有屋顶图用，见 [method _carve]。
##
## smoothstep（两端斜率为 0）而不是直线：左端接的是缝的左沿，也就是**起跳点**；
## 右端接的是下一栋房子的开头，也就是那段**平的落点台**
## （[constant Maps.ROOF_LAND]，地表低整整一个落差、斜率为 0）。两头都平着接上，
## 缝沿那一圈不会多出折角。中间那点坡度落在缝底，玩家看不到。
static func _gap_drop(rel: float, left: float, width: float) -> float:
	if width <= 0.0 or rel <= left:
		return 0.0
	if rel >= left + width:
		return 1.0
	var u := (rel - left) / width
	return u * u * (3.0 - 2.0 * u)


## 镜头钳位用的「天际线」：这一段里最高的地表。
##
## 关键是**只取抬高的部分、不取挖下去的部分**（`min(0, …)`）：坑、湖盆、
## 火山口上方给的是坑沿高度，否则镜头会跟着坑底往下掉，跳之前看不见对岸。
## 反过来助跑坡是真把地面抬高了，镜头得跟着它走，所以负数要保留。
##
## **垫平那一项要单独加回来。** 它不在 `min(0, …)` 里：垫平是把地面搬到左沿那个
## 高度上，可能往上也可能往下，而镜头该跟的是**改过之后**的地面。漏掉它的话，
## 在「垫高」的那半边（当地地表比左沿低），天际线会比真实地面低一截，镜头被
## 压得偏低。`_level` 在不垫的地方恒为 0，所以火山口和普通地形的行为没变。
func skyline_at(x: float) -> float:
	var index := int(floor(x / CHUNK_WIDTH))
	var kind := feature_kind_at(index)
	var level := 0.0 if kind == Maps.FEATURE_NONE else _level(kind, index, x)
	var dig := _carve(x) - level
	return _base_height(x) + level + minf(0.0, dig)


## 形状地图第 `index` 个区块末尾那条缝的世界坐标范围（`size.y` 是缝深）。
## 不是形状地图、或者那块不该有缝，返回宽 0 的矩形。**屋顶图专用**。
##
## 缝的左沿就是**屋顶的右沿**（屋顶长度随机，见 [method Maps.span_at]），右沿压在
## 区块边界上。缝顶就是左沿那个点的高度 —— 屋顶图上它随天际线起伏（一栋一个高度）。
##
## 屋顶图那条落差（[method Maps.drop_at]）**不影响这个矩形**：落差是缝里面的事
## （[method _carve] 里的 `_gap_drop`），而这里有意义的是左右两条沿所在的
## **世界坐标范围**和左沿有多高 —— 死区在左沿往下 55% 处，离那道落差远得很。
##
## 缝底的死区问这一个函数 —— 缝挖在哪、死区盖在哪，是同一个结论。
func gap_rect(index: int) -> Rect2:
	if not Maps.has_gaps(map_id) or index < Maps.SHAPE_START_CELL:
		return Rect2()
	var gap := Maps.gap_for(world_seed, map_id, index)
	if gap <= 0.0:
		return Rect2()
	var right := float(index + 1) * CHUNK_WIDTH
	# 缝顶 = 缝左沿的地表高度。**不是 [constant GROUND_Y]**：屋顶图上每条缝的左沿
	# 都在自己那一栋的天际线高度上，死区要盖在缝底 —— 用一个固定高度的话，
	# 天际线高的那几栋死区会悬在缝中间、低的那几栋会盖到屋顶上面去。
	return Rect2(right - gap, height_at(right - gap), gap, Maps.GAP_DEPTH)


## 本图第 `index` 块末尾那条缝的**左沿**在区块内的坐标；没留缝的区块就是区块宽
## （形状一路铺到底）。**屋顶图专用**。
##
## 和 [method Maps.gap_for] 是同一个结论的两面 —— 缝的右沿压在区块边界上，
## 所以「缝有多宽」和「形状铺到哪儿为止」是一个数。这里写成「区块宽 − 缝宽」
## 而不是转手去问 [method Maps.span_at]，是为了让 [method _carve] 里挖缝和取左沿
## 用的一定是**同一次**掷骰子的结果。
func _rim_lx(index: int) -> float:
	return CHUNK_WIDTH - Maps.gap_for(world_seed, map_id, index)


func _configure_noise() -> void:
	_noise.seed = Maps.noise_seed(world_seed, map_id)
	# 频率和八度数由地图给（竞技场要「又缓又高」，就是靠这两个往下调）。
	# 表里没写的图拿到的默认值**就是加这两个旋钮之前写死的数**，所以八张老图
	# 的地形逐位不变（见 [method Maps.noise_freq]）。
	_noise.frequency = Maps.noise_freq(map_id)
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = Maps.noise_octaves(map_id)
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.42

	# 长波层：种子跟着地图走（同一个种子下每张图的长坡不一样，同图可复现），
	# 频率固定 —— 表里没有这个旋钮，因为「长」是难度的主轴，不该被某张图的
	# 配色参数顺手改掉；各图之间的强弱差距由 `amp_scale` 表达（和短波层一样）。
	_long_noise.seed = Maps.noise_seed(world_seed, map_id) + LONG_SEED_OFFSET
	_long_noise.frequency = LONG_FREQ
	_long_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	# **一个八度**。第二层八度的波长只有 1190 像素，会把「长」这个字吃掉一半 ——
	# 而小疙瘩短波层已经够多了，这一层要的就是一条干净的、几百像素不拐弯的大坡。
	_long_noise.fractal_octaves = 1

	# 天际线层：屋顶图专用（别的图一次都不问它）。种子照旧跟着地图走，
	# **偏移一个和另外两层都不同的常数** —— 同一个种子上三层各走各的，
	# 「天际线的低谷正好撞上一条长坡」这种事不用论证。
	_sky_noise.seed = Maps.noise_seed(world_seed, map_id) + SKY_SEED_OFFSET
	_sky_noise.frequency = SKY_FREQ
	_sky_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_sky_noise.fractal_octaves = 1


## 换种子/换地图之后把已经建好的区块全丢掉重建。
func _rebuild() -> void:
	for i in _chunks.keys():
		_chunks[i].queue_free()
	_chunks.clear()
	_refresh_chunks()


func _process(_delta: float) -> void:
	_refresh_chunks()


func _refresh_chunks() -> void:
	if _target == null:
		return
	var center := int(floor(_target.global_position.x / CHUNK_WIDTH))
	for i in range(center - VIEW_RADIUS, center + VIEW_RADIUS + 1):
		if not _chunks.has(i):
			_build_chunk(i)
	# keys() 返回副本，边遍历边删除是安全的。
	for i in _chunks.keys():
		if i < center - VIEW_RADIUS - 1 or i > center + VIEW_RADIUS + 1:
			_chunks[i].queue_free()
			_chunks.erase(i)


func _build_chunk(index: int) -> void:
	var arches := Maps.shape_of(map_id) == Maps.SHAPE_ARCHES
	# 出生台：彩虹图上唯一一块实心地面（[constant Maps.SHAPE_START_CELL]）。
	#
	# **它整块写死成平的，不走 `height_at`。** `height_at` 在 `x = 800`
	# （出生台的右沿）那一刻从「出生台面」变成「x 上面的天花板有多高」——
	# 也就是从 `GROUND_Y + Maps.PAD_DY`（现在是 20）跳到天上两千来像素。
	# 而本区块的多边形**正好采到 x = 800 这个点**（`i in CHUNK_POINTS + 1` 是闭区间，
	# 40 × 20 = 800）。于是最后一个顶点跳到天上，和它前一个顶点（x = 780、同一个高度）
	# 连成一道**立在出生台右沿、看不见的竖墙**。
	#
	# 实测的后果：车全油门开出出生台，车头（`车壳长 178`，中心 696 时车头在 785）
	# 顶在那道墙上，**最远只到 x = 696，上不了平台场** —— 整张图等于玩不了。
	# 这一条是 [_section_arches_drive] 里「跑出了出生台那一段」逮住的。
	var pad := arches and index < Maps.SHAPE_START_CELL
	var start_x := float(index) * CHUNK_WIDTH
	var surface := PackedVector2Array()
	for i in CHUNK_POINTS + 1:
		var x := start_x + float(i) * POINT_SPACING
		surface.append(Vector2(x, (GROUND_Y + Maps.pad_dy(map_id)) if pad else height_at(x)))

	# 沿地表从左到右，再绕到底部闭合，形成一个实心多边形。
	#
	# **底边跟着本区块最深的那一处地表走，不是一个固定的世界高度。**
	# 早先这里是 `GROUND_Y + DEPTH`（一个绝对高度）。那在起伏小的年代够用，但地表是
	# **相对**的：噪声起伏随里程往下长（长波层，见 [constant LONG_AMPLITUDE]），
	# 山地里凹地最深能到 `420 + (224 + 260) × 1.35 ≈ 1074`，而固定底边在 1020 ——
	# 地表跑到地块**底下**去了：多边形自己交叠（收口那两条边翻到了地表上方），
	# 碰撞体就废了，车从那儿直接掉出世界。用户报的就是这个。
	#
	# 根因是「底边是绝对的、地表是相对的」，所以修法是让底边也变成相对的：
	# 取本区块地表最低的那一点，再往下 [constant DEPTH]。于是
	# **「地块比地面厚 DEPTH」成了每一个区块、每一张图、每一个里程上都成立的局部保证**，
	# 和起伏多大无关。只把 DEPTH 往上加是治标 —— 起伏再长一截就又翻过去了。
	var deepest := GROUND_Y
	for p in surface:
		deepest = maxf(deepest, p.y)
	var bottom := deepest + DEPTH
	var solid := PackedVector2Array(surface)
	solid.append(Vector2(start_x + CHUNK_WIDTH, bottom))
	solid.append(Vector2(start_x, bottom))

	var palette := Maps.get_map(map_id)

	# 区块根节点是个空 Node2D：地面实体和特殊地形都是它的孩子，回收时一起释放。
	# 以前根节点直接就是那个 StaticBody2D，加特殊地形就得往刚体上挂非刚体子节点，
	# 位置语义会变得很难读。
	var chunk := Node2D.new()
	chunk.name = "Chunk%d" % index

	# 彩虹图**从 1 号区块起一个地块多边形都不建**：整张图都是散在空中的平台。
	# 0 号区块照旧铺平地（[constant Maps.SHAPE_START_CELL]）—— 车得有个地方出生、
	# 起步、把速度提起来，而且那是全图唯一一处踩得实的地面。
	#
	# 这一支不是「少画一点」而是**真的没有地块**：`height_at` 在那张图上答的是
	# 「x 上面的天花板有多高」（见 [method _base_height]），拿它去绕多边形，
	# 绕出来的是一层看不见的实心天空 —— 车会飘在平台上方两百米的地方开过去。
	var platforms := arches and index >= Maps.SHAPE_START_CELL

	if platforms:
		_add_platforms(index, chunk)
	else:
		var body := StaticBody2D.new()
		body.name = "Ground"
		body.collision_layer = 2
		body.collision_mask = 0
		body.add_to_group("ground")

		var collider := CollisionPolygon2D.new()
		collider.polygon = solid
		body.add_child(collider)

		var dirt := Polygon2D.new()
		dirt.polygon = solid
		dirt.color = palette["dirt"]
		body.add_child(dirt)
		body.add_child(_band(surface, palette["crust"], 0.0, 15.0))

		# 屋顶图：地块就是**房子**，瓦、楼层、窗户、钢梯由画师铺在土色上面。
		#
		# **必须先建、后挂**：画师得挂在 `body` **之后**（同一层 z = 0，后画的在上），
		# 房子才盖得住土色，车（z = 1）再盖住房子。挂反了的话，地块那个实心多边形
		# 会把整面立面连窗户一起埋掉 —— 只剩探出屋面那几笔瓦尖还看得见。
		# 见 tests/shapes.gd 里那条「画师排在土色之后」的断言。
		var art: HillRooftopArt = null
		if Maps.shape_of(map_id) == Maps.SHAPE_ROOFS:
			art = HillRooftopArt.new()
			art.setup(roof_profile(index), bottom, index, world_seed)

		chunk.add_child(body)
		if art != null:
			chunk.add_child(art)

	add_child(chunk)
	_chunks[index] = chunk
	_add_gap_hazard(index, chunk)
	if not platforms:
		_spawn_feature(index, chunk)
	_spawn_pickups(index, surface)


## 把本块区块里的平台实例化出来（[method Maps.platforms_at]）。
##
## 布局那边给的是**相对 [constant GROUND_Y] 的 `dy`**（负 = 往上）：`Maps` 是叶子
## 脚本，够不着地形的高度基准，换算在这一层做 —— 和 [method _base_height] 里
## `ceiling_dy_at` 的用法是同一个约定。
##
## 平台自己带碰撞体、自己带画（见 scripts/platform.gd），这里只负责摆位置。
func _add_platforms(index: int, chunk: Node2D) -> void:
	for data in Maps.platforms_at(world_seed, index):
		var node := HillPlatform.new()
		chunk.add_child(node)
		# **必须在 add_child 之后**才 setup：和特殊地形同一条规矩，节点进树之前
		# 拿不到自己的世界变换，`_physics_process` 也不会跑。
		node.setup(data, Vector2(float(data["x"]), GROUND_Y + float(data["dy"])))


## 地表上那条边。`drop` 是整条线往下平移多少像素。
func _band(points: PackedVector2Array, color: Color, drop: float, width: float) -> Line2D:
	var line := Line2D.new()
	var pts := PackedVector2Array()
	for p in points:
		pts.append(p + Vector2(0.0, drop))
	line.points = pts
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	return line


## 缝底那条死区 / 平台带底下那条判死线。
##
## **只有形状地图有。** 八张老图不挖缝，这个函数直接返回，一个节点都不摆 ——
## 「平原必须逐位不变」那条约定也管到这里：老图的区块树里不会多出一个 HazardZone。
##
## 两条路：
##
##  · **屋顶图**：缝深 420、缝壁 84°，掉进去是**爬不出来**的。不判死的话玩家会蹲在
##    缝底把油耗光，那不是难度是罚站。死区只盖缝的下半截（[constant GAP_HAZARD_FRAC]），
##    这样从缝上面飞过去不算掉进去。
##  · **彩虹图**：整张图是 ±[constant Maps.BAND] 的平台带，带子底下**什么都没有**。
##    所以死区是**整块区块宽**的一条，上沿正好在带子底（`GROUND_Y + BAND`）——
##    布局保证最低那块平台的外接框也在带子里，所以这条线永远碰不到平台，
##    「踩在平台上」和「掉出去」是两件互不干扰的事。掉出带子就是掉出这张图。
##
## 彩虹图这条**看不见**（[constant GAP_FILL_AIR]）：那张图的平台下面本来就只有天，
## 在半空挂一块黑板比不画还糟。
func _add_gap_hazard(index: int, chunk: Node2D) -> void:
	if hazard_scene == null:
		return
	var rect: Rect2
	var fill: Color
	if Maps.shape_of(map_id) == Maps.SHAPE_ARCHES:
		if index < Maps.SHAPE_START_CELL:
			# 0 号区块是出生台，底下是实心地块，没有「掉出去」这回事。
			return
		rect = Rect2(float(index) * CHUNK_WIDTH, GROUND_Y + Maps.BAND,
				CHUNK_WIDTH, DEPTH)
		fill = GAP_FILL_AIR
	else:
		var gap := gap_rect(index)
		if gap.size.x <= 0.0:
			return
		var top := gap.position.y + gap.size.y * GAP_HAZARD_FRAC
		rect = Rect2(gap.position.x, top, gap.size.x,
				gap.size.y * (1.0 - GAP_HAZARD_FRAC) + GAP_HAZARD_PAD)
		fill = GAP_FILL
	var zone: Node = hazard_scene.instantiate()
	chunk.add_child(zone)
	zone.call("setup", rect, HillCar.REASON_FALL, fill)


## 这一块区块要是有特殊地形，就把对应的场景挂进来。
##
## 挖地形的 [method _carve] 和这里的摆位都从 [constant Maps.FEATURE_LAYOUT] 读尺寸，
## 所以坑挖在哪、桥/冰面/岩浆摆在哪，永远对得上 —— 分开写死两遍迟早会对不上。
##
## `rim_y` 给的是坑左沿的**地表**高度（[method skyline_at]，不是
## [method _base_height]）：坑底在 `rim_y + depth`，特殊地形节点自己按这个往下摆。
##
## 两者在三种地形上恰好相等（它们的坑沿就在原始地表上），只有火山口不同 ——
## 它的坑沿立在 150 高的助跑坡顶上，用未开挖的地表高度会把岩浆整个摆到坑底以下。
func _spawn_feature(index: int, chunk: Node2D) -> void:
	# **必须问 [method feature_kind_at]，不能问 [method Maps.feature_at]。**
	# 地形可能否决掉某一块（冰湖前面是上坡），挖坑那边听的是否决后的结论 ——
	# 这里要是自己再掷一次骰子，就会出现「坑没挖，桥却摆上了」。
	var kind := feature_kind_at(index)
	if kind == Maps.FEATURE_NONE:
		return
	var scene := _feature_scene(kind)
	if scene == null:
		return
	var rect := Maps.rect_of(kind, index, CHUNK_WIDTH)
	if rect.size.x <= 0.0:
		return
	var node := scene.instantiate()
	chunk.add_child(node)
	# 必须**在 add_child 之后**再 setup：特殊地形脚本里的 @onready 变量
	# 要等节点进树才会填上，先 setup 会全部是 null。
	node.setup(rect, skyline_at(rect.position.x))


func _feature_scene(kind: String) -> PackedScene:
	match kind:
		Maps.FEATURE_BRIDGE:
			return bridge_scene
		Maps.FEATURE_SANDSTORM:
			return sandstorm_scene
		Maps.FEATURE_LAKE:
			return lake_scene
		Maps.FEATURE_CRATER:
			return crater_scene
		Maps.FEATURE_STONES:
			return stones_scene
		Maps.FEATURE_TUNNEL:
			return tunnel_scene
		Maps.FEATURE_TREES:
			return trees_scene
		Maps.FEATURE_CHIMNEYS:
			return chimneys_scene
	# 环形山**故意没有场景**：它就是地形本身那个浅碗（[method _carve_in_chunk] 的
	# `_basin`），地表折线已经把它画出来了，再摆一个空节点只是白挂一层。
	# 返回 null 时 [method _spawn_feature] 直接收工，不会报错。
	#
	# 竞技场 / 黑夜 / 彩虹也是 null：这三张图的 `feature` 是
	# [constant Maps.FEATURE_NONE]，上面这个 match 根本不会走到这儿
	# （[method _spawn_feature] 先看过 kind 了）。彩虹图的云朵是**平台**，
	# 不走特殊地形这一路（见 [method _add_platforms]）。
	#
	# 屋顶图的烟囱**不是 FEATURE_NONE 了**（[constant Maps.FEATURE_CHIMNEYS]），
	# 但它和别的特殊地形有两处不同，都在上面几行里处理掉了：它**不挖地形**
	# （布局表 `depth` 0）、**不摆刚体**（砖柱子由 [scripts/rooftop_art.gd] 画），
	# 摆出来的只有力和烟（[scripts/chimneys.gd]）。所以 `_carve` 和
	# `_add_gap_hazard` 那边一行都不用改。
	return null


## 用「区块序号」做种子，保证同一次运行里道具位置固定，重开也一致。
func _spawn_pickups(index: int, surface: PackedVector2Array) -> void:
	if index < 1:
		return
	if Maps.shape_of(map_id) == Maps.SHAPE_ARCHES:
		_spawn_platform_pickups(index)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + index

	for _i in rng.randi_range(1, 3):
		var k := rng.randi_range(2, CHUNK_POINTS - 2)
		_add_pickup(coin_scene, "coin", surface[k] + Vector2(rng.randf_range(-8.0, 8.0), -36.0), surface[k])

	if rng.randf() < fuel_chance(surface[0].x):
		var k := rng.randi_range(2, CHUNK_POINTS - 2)
		_add_pickup(fuel_scene, "fuel", surface[k] + Vector2(0.0, -44.0), surface[k])


## 一块平台上有金币的概率。一张区块有两列 × 16 行 × [constant Maps.FILL] ≈ 16 块
## 平台，0.15 换成每块区块 2～3 枚 —— 和噪声图的 `randi_range(1, 3)` 是同一个密度。
##
## **不是每块都有**：全都有的话金币会连成一条指示线，而且「这块有没有金币」
## 就不再提供任何信息了。散着放，它才是「这块落得住」的记号。
const PLATFORM_COIN_CHANCE := 0.15


## 彩虹图的道具**挂在平台的顶上**，不挂在 `surface` 上。
##
## 那张图的 `surface` 是「x 上面那层天花板」（[method _base_height]）：一整段可能
## 都落在同一块平台的顶上，照它撒金币会撒出一串悬在空中的东西 —— 车够不着，
## 也看不出该往哪边开。挂在平台顶上就不一样：金币成了「这块能落」的记号，
## 玩家看不懂这张图的时候，跟着金币走至少不会马上摔到底。
##
## 平台高度从**布局**里问，不问建出来的节点：节点会随镜头滚出视野被回收重建，
## 从节点上取的话道具位置会跟着变。
func _spawn_platform_pickups(index: int) -> void:
	var platforms := Maps.platforms_at(world_seed, index)
	if platforms.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + index
	for p in platforms:
		if rng.randf() >= PLATFORM_COIN_CHANCE:
			continue
		var spot := _platform_top(p)
		_add_pickup(coin_scene, "coin",
				spot + Vector2(rng.randf_range(-8.0, 8.0), -36.0), spot)
	if rng.randf() < fuel_chance(float(index) * CHUNK_WIDTH):
		var p: Dictionary = platforms[rng.randi_range(0, platforms.size() - 1)]
		var spot := _platform_top(p)
		_add_pickup(fuel_scene, "fuel", spot + Vector2(0.0, -44.0), spot)


## 一块平台**顶上那一点**的世界坐标（彩虹是弧顶，云是板心）。
##
## 偏移是 [method Maps.top_offset] 算的 —— 彩虹那边不能拿外接框的顶去凑，
## 理由写在那儿。这里只管把中心搬到世界坐标。
func _platform_top(p: Dictionary) -> Vector2:
	var at := Vector2(float(p["x"]), GROUND_Y + float(p["dy"]))
	return at + Maps.top_offset(p)


## x 处刷出油桶的概率：越远越稀。
##
## 注意衰减的是**频率**不是单桶的量 —— 单桶补多少是 [Pickup] 上的常数（50），
## 全图统一。这样玩家看到油桶就知道能补多少，不用心算。
func fuel_chance(x: float) -> float:
	return maxf(FUEL_CHANCE_FLOOR, FUEL_CHANCE_BASE - Maps.meters_at(x) * FUEL_CHANCE_PER_METER)


func _add_pickup(scene: PackedScene, kind: String, position: Vector2, surface_point: Vector2) -> void:
	if scene == null:
		return
	var chunk: Node = _chunks.get(int(position.x / CHUNK_WIDTH))
	if chunk == null:
		return
	var pickup := scene.instantiate()
	pickup.kind = kind
	pickup.position = position
	# **层数一律 0，黑夜图也不例外。** 金币和油桶跟地形一样待在挡布底下，于是挡布
	# 那个洞（车周围那一圈）照到哪儿才看得见哪儿 —— 地图自己写的「只看得到车灯那一圈」
	# 就是这么来的。原来这里把黑夜图的油桶抬到挡布**之上**，满屏黑里金币照样亮着，
	# 等于整张图没有黑夜：用户就是这么报上来的，见 scripts/night.gd。
	pickup.z_index = 0
	pickup.set_meta("surface_y", surface_point.y)
	pickup.collected.connect(_on_pickup_collected)
	chunk.add_child(pickup)


func _on_pickup_collected(kind: String, amount: float) -> void:
	pickup_collected.emit(kind, amount)
