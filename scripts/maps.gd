extends RefCounted
class_name Maps
## 十二张地图的中央定义表：配色、地形难度、物理修正、以及各自的特殊地形。
##
## 和 [Upgrades] 一个套路 —— 数值全部集中在这里，存档只存「选了哪张图」这一个
## 字符串，改平衡不用碰存档代码。
##
## ## 三条约定
##
## 1. **平原那一行必须是恒等变换**（`amp_scale` / `friction_scale` / `fuel_scale`
##    全 1.0，`drag` / `seed_offset` 全 0，`shape` 是 `SHAPE_NOISE`）。这样默认地图
##    的行为和加地图之前逐位一致，之前所有基于平原的实测数字和测试基准都不会被
##    这次改动废掉。
## 2. **特殊地形的位置是纯函数**（见 [method feature_at]），不依赖区块的生成顺序。
##    区块是随镜头滚动回收再重建的，任何「上一次特殊地形出现在哪」的状态都不可靠。
##    **地形形态（[constant SHAPE_*]）也是纯函数**，见 [method gap_at]。
## 3. **没有特殊地形的地图也要能上卡片**：形状地图（屋顶 / 彩虹）的招牌是地形本身，
##    `feature` 是 [constant FEATURE_NONE]，卡片文案走 [method gimmick_of]。

const PLAINS := "plains"
const DESERT := "desert"
const SNOW := "snow"
const VOLCANO := "volcano"
const MOUNTAIN := "mountain"
const TUNNEL := "tunnel"
const MOON := "moon"
const FOREST := "forest"
const ROOFTOP := "rooftop"
const ARENA := "arena"
const RAINBOW := "rainbow"
const NIGHT := "night"

## 十二张图。**前八张的顺序不要动**：记录是按图分开记的、选图界面按 `IDS` 的下标
## 摆卡片（四张一页），挪动已有条目会让所有人存档里「选中的是第几张」的直觉
## （和所有截图）全部错位。新图一律往后追加。
const IDS: Array[String] = [
	PLAINS, DESERT, SNOW, VOLCANO, MOUNTAIN, TUNNEL, MOON, FOREST,
	ROOFTOP, ARENA, RAINBOW, NIGHT,
]

## 开局白送几张 —— 就是 [constant IDS] 的**前四张**：平原 / 荒漠 / 雪地 / 火山。
##
## 用「前几个」而不是一张「免费名单」：名单要跟着 [constant IDS] 手工同步，加一张
## 新图时两处就会漂。要换成别的四张，把这个数改了就行。
const FREE_COUNT := 4
## 其余每张的解锁价。**一律这个数**，不按图分档 —— 想分档的话在 [member MAPS] 里
## 给每张加一个 `price` 键，再由 [method price_of] 优先读它。
const UNLOCK_PRICE := 50000

## 地形形态。**这是比「噪声起伏」更粗的一层**：它决定地表折线长什么样，
## 而不是在地表上挖点什么。噪声那几个旋钮（`amp_scale` / `noise_freq` /
## `noise_octaves`）对形状地图**一点作用都没有** —— 形状地图的地表是解析算出来的。
##
## 为什么要有这一层：屋顶和彩虹的地表是「平顶 / 拱 + 一条缝」这种**周期性解析形状**，
## 不是噪声能凑出来的。硬拿噪声去近似的话，「两块屋顶一样高」「缝的宽度可控」
## 这两条就没法保证了。
const SHAPE_NOISE := "noise"
## 屋顶：地表是一栋栋**房子**，房子之间是一条缝。每栋房子的屋面是**水平的**
## （不倾斜），高低错落靠两层：一栋房子内部用**钢梯**连起几段不同高度的屋面
## （见 [method HillTerrain.roof_profile]），房子之间靠**天际线**（见
## [method HillTerrain._sky]）。难的是缝 —— 得跳过去。
##
## **缝的右沿比左沿低**（[constant DROP_LO]～[constant DROP_HI]，每缝一条）：
## 右低左高是用户要的 —— 每一跳都是从高的那边往低的那边飞，落地摔不狠，
## 起跳点又一点没动（跳距标定不受影响）。
const SHAPE_ROOFS := "roofs"
## 彩虹：**没有地表，只有一堆散落在空中的平台**（见 [constant PLATFORM_RAINBOW]）。
##
## 早先这里是一串「交叠的拱 + 每块末尾 50% 概率的缝」，整条图是一条连续的单值
## 折线。用户改成「散落在空中的彩虹和云朵、任意两块不相连」之后那条路走不通了
## —— 一张散落的场天然是多值的，画不出中间的空档。
##
## 所以这张图**一个地块多边形都不建**（见 [method HillTerrain._build_chunk]），
## 每块平台是一个自己的 [HillPlatform] 节点，各自带碰撞体。
const SHAPE_ARCHES := "arches"

## 本张图的形态。表里没写就是 [constant SHAPE_NOISE]。
const DEFAULT_SHAPE := SHAPE_NOISE

## 形状地图的地表形态从第几个区块开始生效。
##
## **0 号区块整块保持平坦**：车出生在 x = 200，而缝是「区块末尾那一段」
## （见 [method gap_at]），不跳过 0 号区块的话第一条缝会正好落在出生直道里，
## 玩家连起步都还没起步就掉下去了。
const SHAPE_START_CELL := 1

## 一个形状周期有多长（一个平顶/一座拱 + 一条缝）。
##
## **必须正好等于 [constant HillTerrain.CHUNK_WIDTH]**，这是整套形状地图成立的前提：
## 周期和区块对齐之后，**每个区块最多装一条缝，而且缝绝不会跨在区块缝上**。
## 跨了的话，缝的两半会被分到两个区块里，区块各自独立重建 —— 房子（一种区块内
## 状态）就会一半有、一半没有，车开到区块交界处会毫无道理地掉下去。
##
## 彩虹图也吃这个常量：平台的格子宽是它的一半（[constant CELL_W]），
## 于是格子和区块边界对齐、一个 x 只落在一个格子里。
##
## 这里不能直接引用 `HillTerrain.CHUNK_WIDTH`（maps.gd 是叶子脚本，谁也不依赖），
## 所以写成常量、由 tests/maps 断言两边相等：改了区块宽度而没改这里，测试当场红。
const SHAPE_PITCH := 800.0

## 特殊地形的种类。`FEATURE_NONE` 表示这张图这一段是普通地形。
const FEATURE_NONE := ""
const FEATURE_BRIDGE := "bridge"
const FEATURE_SANDSTORM := "sandstorm"
const FEATURE_LAKE := "lake"
const FEATURE_CRATER := "crater"
## 山地：地上撒一片小石子，轮子碾过去会颠。
const FEATURE_STONES := "stones"
## 隧道：一段被垫平的洞，顶上压着一块石头 —— 车顶撞上就死。
const FEATURE_TUNNEL := "tunnel"
## 月球：一串浅浅的环形山，配合低重力能把车弹起来。
const FEATURE_CRATERS := "craters"
## 森林：一棵和车一样高的树，撞得够快才推得倒。
const FEATURE_TREES := "trees"
## 屋顶：**每栋房子上可能有一根烟囱**，囱口的烟柱把车往上托。
##
## 和别的特殊地形不一样，它**不挖地形、不摆刚体**，只是给「房子上的烟囱」
## 开一条每块区块都会问一次的路（见 [method feature_at]）：烟囱本身由
## [scripts/rooftop_art.gd] 画在房子上，力和烟由 [scripts/chimneys.gd] 摆。
const FEATURE_CHIMNEYS := "chimneys"

## 烟囱：一栋房子上有烟囱的概率，以及一根烟囱的粗细高低。
##
## 0.45 是「抬头总能看见几根」定的：一屏大约三栋房子，按这个概率平均一屏一根多一点。
## 掷中的那一栋还要**真的有一级够宽的中间平屋面**才摆得下（见
## [method HillChimneys.chimney_rect]），所以实际出现率比这个数低。
const CHIMNEY_CHANCE := 0.45
## 烟囱的宽度、高度区间（像素）。砖砌的方烟囱：26 宽、60 上下 —— 比窗户（26×34）
## 高一头，站在屋面上才像烟囱而不像一扇立着的窗。最小值也不是随手取的：
## 低于 18 宽画不出砖缝，低于 40 高会被车壳整个盖住。
const CHIMNEY_W_LO := 22.0
const CHIMNEY_W_HI := 30.0
const CHIMNEY_H_LO := 46.0
const CHIMNEY_H_HI := 78.0
## 世界尺度换算：多少像素算一米。
const PIXELS_PER_METER := 10.0
## 车出生点离地图原点多远，计分时扣掉，避免白送里程。
##
## 这两个常量放这里而不是 [HillGame] 里，是因为地形也要用（油桶补给频率随里程
## 衰减），而地形反向引用关卡脚本就变成两个 `class_name` 互相引用，编译期容易
## 扯皮。所以定义放在这个「谁都依赖、自己不依赖谁」的叶子类里。
const START_OFFSET := 200.0

## 一个区块出现特殊地形的概率。算上「不与上一个相邻」的规则，实际密度约为
## `p(1-p)`，即 0.10 对应平均 11 个区块（880 px × 11 ≈ 880 m）碰一次。
## 定这个量的依据是**时间**不是距离：跑一局大概 20~30 秒，880 m 在平均车速下
## 约 11 秒，不密不疏。调大的话会变成每几秒一个，特殊地形就不特殊了。
const FEATURE_CHANCE := 0.10
## 这一块区块必定有特殊地形 —— 保底，保证再短的一局也能见到本图的招牌地形。
## 前面留给玩家起步。
const FEATURE_MIN_CHUNK := 3

## 隧道从第几块区块开始盖上壁（[constant FEATURE_TUNNEL] 专用）。
##
## **出生点那一段不盖**：车摆在 x = 200（0 号区块），开局就压在石头底下的话
## 玩家连「先开一段」都没有 —— 而且那里的地表正好被 [constant HillTerrain.FLAT_LENGTH]
## 压平，是个天然的起步直道，本该露着天。
##
## 4 块 = 3200 像素 ≈ 300 米的开阔路段，之后**一路盖到天边**、中间不断。
const TUNNEL_START_CHUNK := 4

## 环形山一次连着来几个。用户要的是「每次连续出现 3-5 个」。
const CRATERS_MIN := 3
const CRATERS_MAX := 5

## 特殊地形的展示文案。按地形种类索引，选图界面上用。
##
## **[constant FEATURE_NONE] 也要有一条。** 选图界面是拿本图的 `feature` 直接下标
## 这张表的，没有这一条的话，屋顶 / 竞技场 / 黑夜三张图一进选图界面就崩。
const FEATURE_INFO := {
	FEATURE_NONE: {
		"zh": "标准地形", "en": "NO HAZARD",
		"zh_note": "只有起伏本身，没有额外的花招",
		"en_note": "just the hills, nothing extra",
	},
	FEATURE_BRIDGE: {
		"zh": "吊桥", "en": "ROPE BRIDGE",
		"zh_note": "绳子做的，开上去会晃", "en_note": "springy, sways under the wheels",
	},
	FEATURE_SANDSTORM: {
		"zh": "沙尘暴", "en": "SANDSTORM",
		"zh_note": "风把你往回推", "en_note": "the wind pushes you back",
	},
	FEATURE_LAKE: {
		"zh": "冰湖", "en": "FROZEN LAKE",
		"zh_note": "踩上去半秒后裂开", "en_note": "breaks half a second after you touch it",
	},
	FEATURE_CRATER: {
		"zh": "火山口", "en": "CRATER",
		"zh_note": "得跳过去，掉下去烧死", "en_note": "jump it, or burn",
	},
	FEATURE_STONES: {
		"zh": "碎石路", "en": "STONES",
		"zh_note": "轮子碾过去会颠", "en_note": "loose rocks under the wheels",
	},
	FEATURE_TUNNEL: {
		"zh": "隧道", "en": "TUNNEL",
		"zh_note": "车顶撞上壁就没命", "en_note": "hit the roof and it's over",
	},
	FEATURE_CRATERS: {
		"zh": "环形山", "en": "CRATERS",
		"zh_note": "一排凹坑，轮子会陷进去 —— 借低重力跃过去",
		"en_note": "a row of pits — use the low gravity to clear them",
	},
	FEATURE_TREES: {
		"zh": "树", "en": "TREES",
		"zh_note": "撞得够快才推得倒，慢了被弹回来", "en_note": "hit it fast to knock it down",
	},
	FEATURE_CHIMNEYS: {
		"zh": "烟囱", "en": "CHIMNEYS",
		"zh_note": "屋上的烟柱会把你往上托一把", "en_note": "chimney smoke lifts you",
	},
}

## 形状地图的缝：宽度范围（像素，世界尺度）。
##
## 缝就是「地表上少了一块」：地表折线在那儿往下掉 [constant GAP_DEPTH]，掉成一条
## 爬不出来的窄沟，**没有东西架着**（跳过去，掉下去摔死）。这一套（缝、落差、
## 屋檐、跳台）现在**只有屋顶图在用** —— [constant SHAPE_ARCHES] 那张图没有地表，
## 自然也没有缝，见 [constant CELL_W] 那一段。
##
## 130～150 是**跳得过去但要挑时机**的宽度，这个上限是**量出来的**，不是拍脑袋
## 定的：
##
##  · 平着起跳、落点低 `d` 时的下落预算是 `d + 21` 像素（`d` 是这条缝自己的落差
##    [constant DROP_LO]～[constant DROP_HI]，21 是轮子半径 —— 轮心还比落点高的
##    时候，轮子能啃着缝沿的圆角翻上去）。`t = √(2(d+21)/980)` 秒，于是
##    **缝宽上限 = 起跳速度 × t**。
##  · **最紧的是落差最浅的那条缝**：`d = 24` → `t = 0.303 秒`（落差 36 的年代是
##    0.34，所以同样宽度现在更难过一点 —— 落差的随机范围一放宽，上限就得跟着收）。
##  · 起跳那一刻的速度**是量出来的，不是极速**：实测 542～624 px/s，只有极速
##    （约 1050）的一半上下。吃速度的是那段钢梯 —— 55° 的坡车是「撞」上去的
##    （见 tests/shapes.gd 屋顶那节的文件头），一撞掉三四百，紧接着 250 像素的
##    跳台捡不回来全部。这一段的实测表格在 tests/shapes.gd 的屋顶一节里逐条印。
##  · 于是上限卡在 `实测起跳 × 0.303`：542 × 0.303 = **164**。取 150，留 9% 余量。
##
## **这 9% 不宽裕。** 最紧的配对是「最宽的缝（150）＋ 最浅的落差（24）」，
## 需要 `150 ÷ 0.303 = 495 px/s` —— 两个极端各占 1/36 的骰子、还互相独立，
## 跑久了总会撞上一条。真红了别猜，先看 tests/shapes 印的那张表：
## 给不起的缝会带着「需要 / 实测」自己报出来。
##
## 下限 130 是「还得是一条缝」：130 已经比车长（178）还短，前后轮不会同时悬空，
## 但落差和缝底的死区都在，照样得挑时机 —— 再窄就纯粹是块凹地了。
const GAP_MIN := 130.0
const GAP_MAX := 150.0

## 缝有多深。**深到爬不出来**是对的一半：另一半是缝底有一条死区
## （见 [method HillTerrain._add_gap_hazard]），掉进去判 [constant HillCar.REASON_FALL]。
## 只挖不判死的话，玩家会蹲在缝底把油耗光 —— 那不是难度，是罚站。
const GAP_DEPTH := 420.0
## 缝壁倒角的水平长度。420 / 40 ≈ 84°，几乎是直上直下：蹭着缝壁是爬不上去的。
const GAP_EDGE := 40.0

## 缝**两侧屋檐的高低差**（每一条缝各掷一次）：缝右边那栋房子的屋顶起点，比左边
## 那栋的屋顶右沿低这么多。用户要的「间隔两侧的屋顶右侧比左侧略低」。
##
## 24～60 像素（≈ 2.4～6 米）。**下限 24 是跳距的地基**，见 [constant GAP_MAX]：
## 落差越小，车轮啃着缝沿翻过去的余量就越少，缝就得越窄。上限 60 是「一眼看得出来」
## 定的 —— 再深就是一道悬崖，起跳点在对岸的取景里都找不着了。
##
## **落差是「比上一个右沿低」，不是一个绝对高度。** 每一栋房子的起点高度写成
## `HillTerrain._sky(上一栋的右沿) − 本缝的落差`，所以落差是**构造出来的、不是
## 攒出来的**：既不会一路累加（跑五十栋沉下去一千多米），也不会被天际线本身的
## 起伏吃掉或者放大 —— 测出来的落差永远等于这里掷出来的那个数。
##
## 彩虹图没有这条差：它没有缝，屋檐高度差也就无从谈起。
const DROP_LO := 24.0
const DROP_HI := 60.0

## 屋顶左端**先平多少像素**才开始第一段钢梯。这一段是**落点**，必须是平的 ——
## 这个数是量出来的，不是留的余量：
##
##  · 车**不是平着落地**的。起跳后车头会朝下压十几度（后轮翻过跳台那一道沿时
##    把车头带下去），实测 `14.3°`。
##  · 前轮落地的位置在缝右沿**之后** 60～140 像素（起跳越快落得越远）。
##
## 早先（屋顶还是一整块形状的年代）没有这一段的时候，车正好砸在坡最陡的那一截
## 上：车头朝下 14° 去撞一道上坡，前轮等于正面撞上一面 24° 的斜墙，实测那一帧
## `694 → 113 px/s` 全掉光。200 是「盖得住落点」定的。
const ROOF_LAND := 200.0

## 屋顶右端留多长一截平跳台（最后一栋的高度必须提前这么多稳定下来）。
##
## 这是**跳距**要的，不是造型要的：缝宽的上限是「起跳那一刻的速度 × 时间」，
## 而那个时间的前提是**平着起跳**。它是车**唯一能把速度捡回来**的地方 ——
## 跳过一条缝落地要吃掉 80～90 px/s，而那之后屋顶上要么在爬钢梯、要么是刚爬完
## 的一段平路，只有这一截又平又长。[constant GAP_MAX] 从 220 一路收到 150，
## 靠的就是把它从 110 加长到 250：**每 100 像素跳台大约换回 15～35 px/s**。
const ROOF_LEDGE := 250.0

## 钢梯的**段数**（一栋房子上几段）。同一栋房子高低不平，段与段之间用钢梯连起来。
##
## 1～3 段：一段就是「一栋房子两级屋顶」，三段是「三级」。再多的话每段平路只剩
## 一百多像素，车还没把速度捡回来就又得上梯子。
##
## 这只是**上限之外的一个候选值**，真正的段数还要看这栋房子爬多高、跨多宽
## （见 [method HillTerrain.roof_profile]）：爬升不够分、跨度不够平路，都会减段。
const LADDER_MAX := 3

## 一段钢梯**最少爬多少像素**。低于这个数就不值得单独设一段梯子 —— 造出来是一块
## 几乎看不出高低差的小台阶，还不如并到别的段里去。
const LADDER_MIN := 10.0

## 两段钢梯之间**至少留多长平路**（也是减段用的那个下界：平路凑不出来就少设一段梯子，
## 见 [method HillTerrain.roof_profile]）。
const SECTION_MIN := 70.0

## 钢梯的水平长度 = 爬升 × `LADDER_RUN`。**中段坡度 = atan(1.5 / `LADDER_RUN`)**
## —— `1.5` 是 smoothstep 中点的导数（见下面那段），不是笔误。
##
## 1.05 → **55.0°**，正是用户选的「陡（≈55°）」。想放缓就调大这个数
## （1.2 → 51.3°，1.6 → 43.2°），代价是每段钢梯要吃掉更多房子的宽度。
##
## **不是直线。** 钢梯按 smoothstep 取形（见 [method HillTerrain.roof_profile_y]），
## 于是**两头斜率为 0**、中间才是最陡的那一下。这不只是好看：直线梯子会在顶端留
## 一个折角，车高速冲上去会被那道折角弹起来（老的三角形屋顶顶点就是这么把车抛到
## 空中 355 像素的）。两头平着接，上梯子和下梯子都不断速度。
const LADDER_RUN := 1.05

## ------------------------------------------------------------------
## 彩虹图：散落在空中的**平台场**
##
## 用户的需求原话：「整个地图由散落在空中的一些随机圆弧彩虹和椭圆云朵构成，
## 任意彩虹、云朵不相连，且彩虹圆弧长度、朝向各异，彩虹和云朵的覆盖范围包括
## 上下 200 米使得车难以掉下去」。
##
## 于是这张图不再是一条连续的地表折线（原来那套「几个拱互相压着、取上包络」的
## 写法画不出空档 —— 一张散落的场**天然是多值的**），而是一堆各自独立的平台。
##
## ## 「任意两块不相连」是**构造出来的**，不是检查出来的
##
## 用一个全局格子铺满整条高度带，**每块平台严格缩在自己的格子里**。格子两两不相交，
## 所以平台的**外接框**也两两不相交 —— 不需要碰撞检测、不需要拒绝采样、
## 也不会出现「掷了一百次才放下一块」的性能坑。
##
## 格子宽取**正好一块区块**（[constant SHAPE_PITCH]），于是格子和区块边界对齐：
## 一个 x 只可能落在一个格子里，[method ceiling_dy_at] 是 O(1)，区块之间不用互相寻址。
## 这是纯函数成立的前提 —— 区块会滚出视野再重建。
const PLATFORM_RAINBOW := "rainbow"
const PLATFORM_CLOUD := "cloud"

## 平台散布的高度带：`GROUND_Y ± [constant BAND]`。用户要的「上下 200 米」，
## 200 米 × [constant PIXELS_PER_METER] = 2000 像素。
##
## `Maps` 是**叶子脚本**（够不着 [constant HillTerrain.GROUND_Y]），所以平台的高度
## 一律写成**相对 GROUND_Y 的 `dy`**（负 = 往上），由地形那边加上 GROUND_Y。
const BAND := 2000.0
## 格子的宽。**取一整个区块宽（800）**，`tests/maps` 已经钉着
## `SHAPE_PITCH == HillTerrain.CHUNK_WIDTH`，所以这条链路是接上的。
##
## **为什么非要从 400 涨到 800**：格子是弧能占的地方，弧长要涨 3 倍就得跟着涨。
## 一段长 `L` 的弧是**一条又长又扁的带子**，它能塞进多大的方框由**对角线**定：
## 斜着放要 `L ≤ 格子对角线`。400×400 的内框是 376×380，对角线 535 ——
## 1200 像素的弧怎么转都塞不进去。
##
## **800 是「一块区块」这个约束给的上限**（见 [constant COLS_PER_CHUNK]），
## 于是 776×780 的内框能装下 776 像素；再长就只能在斜着的几个方向上塞进去，
## 「朝向各异」会退化成「长弧全是斜的」。这一头的取舍见 [constant ARC_LEN_HI]。
const CELL_W := SHAPE_PITCH
## 一块区块盖住几列。**区块和格子的换算只有这一处** ——
## [method platforms_at] 拿它拼列号，改了 CELL_W 忘了改这里就会漏掉平台。
const COLS_PER_CHUNK := int(SHAPE_PITCH / CELL_W)
## 格子的高，以及一列里有几格。**`ROW_H × ROW_COUNT` 必须正好等于 `2 × BAND`**
## （400 × 10 = 4000），否则带子的上下两头会多出半格，平台会跑到带子外面去。
## `tests/shapes` 有一条断言钉着这个乘法。
##
## **800 不是随手取的高：它和 [constant CELL_W] 一起构成一个正方形格子。
## 400 是上一代的值，配的是「弧长 240～400」那一档。** 用户第二次说
## 「彩虹片段再加长 3 倍」，弧长要涨到 600～1100，格子就非涨不可 —— 弧是斜着放的，
## 能不能塞下由**对角线**定，400×400 的内框对角线才 535。
##
## 格子只有 250 高的时候更糟：一段 400 像素长的弧躺平了要 400 像素宽、
## 立起来要 400 像素高，于是「朝向随机」会把长弧系统性地卡掉 —— 实测 46% 的格子
## 被迫把半径压小，压完中位数只剩 281。
##
## 现在的口径：**内框 776×780 能保证 776 像素的弧在任意朝向下都塞得下**
## （斜着放能到 1070，但正横正竖就是 776）。[constant ARC_LEN_HI] 取在 776 之上，
## 所以最长的那一批会被对分按**当次的朝向**压到 776～1070 之间 —— 换来的好处是
## **朝向仍然是全随机的**：压完的弧照样能朝任何方向，不会退化成「长弧全是斜的」。
##
## 代价是格子面积大了 4 倍：平台密度 `FILL / (CELL_W × ROW_H)` 跟着掉。
## 那一头用 [constant FILL] 补回来 —— 但注意**平台长度也涨了 3 倍**，
## 所以补的量比上一代小（见 FILL 那段）。
const ROW_H := 800.0
const ROW_COUNT := 5
## 出生台的地面高度（相对 `GROUND_Y`，负 = 往上）：**架在中间那一行的「上沿」上，
## 不是架在 `GROUND_Y` 上。**
##
## ## 架在行中间 = 车一冲出去就撞墙
##
## 带子是以 `GROUND_Y` 为中心上下各 [constant BAND] 的，行号从带子顶往下排 ——
## 于是 `ROW_COUNT / 2` 那一行（现在是第 2 行）**正好骑在 `GROUND_Y` 上**，
## 它的内框是 `dy ∈ [-390, +390]`。
##
## 车出生在 `GROUND_Y`、冲过出生台右沿时是**水平**飞出去的（实测 `vx = 934`）。
## 行要是骑在它头上，那半行平台就**不是落点而是挡在胸口的墙**：车撞的是平台的
## **侧面**，实测在 `x = 1103` 正面撞上（那块弧的外接框 `x 1183～1447`、
## `y 73～800`，弧的鼓包正好在车的高度上），`vx` 从 `+908` 一帧之内变成 `-72`，
## 车被弹回来、翻着跟头掉出带子 —— 全程 3.4 秒、只落了 1 次地。
##
## ## 架在行沿上 = 整行都在车底下
##
## 取 `-ROW_H / 2`（= 中间那一行的上沿，因为 `BAND = ROW_COUNT × ROW_H / 2` 且
## `ROW_COUNT` 是奇数）。于是**没有任何一块平台横跨出生台的高度**：
## 中间那一行的内框变成 `dy ∈ [-390, +390]` 里的上半截够不着、下半截在车底下，
## 左边几行整行都在车上面（纯造景），右边几行整行都在车下面（真正的场地）。
##
## 这一条在 `tests/shapes` 里钉成断言了（「没有平台横跨出生台的高度」），
## 因为它是**凭肉眼看地图看不出来的** —— 撞墙要跑起来才知道。
##
## 顺带把场地也变深了：车从 `dy = -400` 起飞，能用的深度从 2000 涨到 2400
## （带子底还是 `GROUND_Y + BAND`，没动）。
const PAD_DY := -ROW_H * 0.5
## 平台和格子边之间留的余量。20 像素的间隔是「不相连」在像素上的兑现：
## 平台的外接框缩在格子里 [constant EDGE_X] / [constant EDGE_Y] 之后，
## 相邻两格里最靠近的两块之间至少隔着两个余量。
const EDGE_X := 12.0
const EDGE_Y := 10.0

## 每一格里掷中「这儿有东西」的概率。**这是这张图密度的总闸** ——
## 「车难以掉下去」全靠它：掉下去多半落得到下面一块上。
## 它也是唯一一个该用实测来调的旋钮（见 tests/shapes 跑车那一节的里程）。
##
## 0.8 是给 [constant CELL_W] / [constant ROW_H] 从 400 涨到 800 补的。
##
## 0.92 是**实测顶上去的，不是推出来的** —— 推出来的是 0.8，跑出来不够。
##
## 推的那一步是这样的：格子面积涨了 4 倍、弧长涨了约 3 倍，所以「每行被平台盖住的
## 比例」`FILL × 弧长 / CELL_W` 反而更高（0.8 × 918 / 800 > 1），看着该够。
##
## **漏掉的是「出生台底下只剩两排」。** 带子是以出生台为中心 ±2000（用户定的
## 「上下 200 米」），行高从 400 涨到 800 之后，`ROW_COUNT` 从 10 掉到 5
## —— 而车没有跳跃键，只能往下走，所以**出生台上面那三排全是够不着的造景**，
## 底下只剩第 3、4 两排。实测就是车开出出生台、掉过这两排、直接出带子判死
## （里程 1111、只落了 1 次）。行数少了 2.5 倍，只能拿密度补回来。
##
## 顶到 0.92 之后每排基本是连续的网，「散落」的观感靠**平台自己的位置和角度**
## 撑（[method _rainbow_in_box] 把外接框在格子里的余量抖开）—— 格子里的位置是随机的，
## 只是「这格有没有东西」这件事几乎不再是随机的了。
const FILL := 0.92
## 填进去的东西里，彩虹占多少（剩下的是云）。
##
## 彩虹是**纯造景**（用户明确要的「朝向各异、可倒扣，能不能骑上去不管」），
## 云朵是**落点**（水平、顶面平、踩了会散）。所以这个比例定的是「观感 vs 落脚点」：
## 调高更像用户描述的那张图，调低更好骑。
##
## **「调低更好骑」这句推错了 —— 实测调低更骑不动。** 别照着上面的直觉再调一遍。
##
## 拿车的出射弹道（实测 `x=919 y=-9 vx=935 vy=119 g=975`）在四百张图上做纯几何求交：
##
## | 比例 | 第一块碰上彩虹 | 第一块碰上云 | 一路没有云 |
## |---|---|---|---|
## | 0.55 | 62% | 36% | 37% |
## | 0.35 | 43% | 55% | 22% |
##
## 看着是 0.35 好 —— 第一落点从「彩虹」换成了「云」。但**真跑起来 0.35 更差**：
## 六个种子从「一个跑满 15 秒、一个 4.9 秒」掉到「四个一起在 3.60 秒、x=2753 出带子」，
## 而且四个种子的死法一模一样 —— 那是**弹道上一个东西都没碰到**的签名。
##
## 道理是：彩虹细归细，它**横向铺得开**（弧长中位 802），一列里挡道的多半是它；
## 抽掉两成彩虹换来的云虽然「更适合落脚」，可云的板子短（中位 526）而且只朝一个方向斜，
## **补不上抽掉的那些跨度**。总的挡道面积掉了，车就直接飞出去了。
##
## 所以这一格真正的旋钮不是「彩虹还是云」，是 [constant FILL]（有没有东西）。
## 彩虹比例动的是观感，不是可骑性 —— 别再拿它当难度调。
const RAINBOW_SHARE := 0.55

## 一道彩虹的配色，从弧的内侧往外一条一条铺。
##
## **不叫 `RAINBOW`**：那个名字已经是这张图的 id 了（[constant RAINBOW] = `"rainbow"`），
## 同一个脚本里一个名字只能有一个意思。
const RAINBOW_COLORS := [
	Color(0.95, 0.30, 0.34), Color(0.96, 0.60, 0.24), Color(0.97, 0.87, 0.34),
	Color(0.44, 0.80, 0.44), Color(0.38, 0.64, 0.93), Color(0.64, 0.46, 0.90),
]
## 相邻两条色带的间距。**一道彩虹的厚度和外接框都是拿这个数推出来的**
## （[constant ARC_THICK]、[method arc_bounds]），改了这里平台占的地方就跟着变。
const RAINBOW_BAND := 5.0

## 一道彩虹有几条色带。改这里要连着 [constant RAINBOW_COLORS] 一起改
## —— [constant ARC_THICK] 是按这个数算出来的。
const RAINBOW_COUNT := 6
## 一道彩虹的**厚度**（外弧半径 − 内弧半径）。
const ARC_THICK := RAINBOW_BAND * RAINBOW_COUNT

## 一段弧的**弧长**，像素。**这才是「彩虹多大」的那个数** ——
## 用户要的是「弧长各异」，所以掷的是长度，半径是拿长度除以张角推出来的
## （`r = len / span`）。
##
## 这一档是**两次用户反馈叠出来的**：
##   1. 早先半径 45–80 配张角 0.7–2.4，最短的弧才 32 像素（比车还短），
##      用户说「彩虹片段太短了」→ 改成 240～400；
##   2. 用户接着说「再加长 3 倍」→ 改成现在这档。
##
## 下限 600 是**车的长度**卡的（车壳 178、轴距 110）：一截比车还短的弧，
## 车挂上去两个轮子都悬在弧外，看着不像路、踩着也不稳 —— 这是原地打转的那条线。
## 上一代取 240 只是「比车长一点」，这一代取 600 ≈ 3.4 倍轴距，
## 一段弧上能稳稳放下整台车还有富余。
##
## 上限 1100 故意**定在**「任意朝向都塞得下」的 776 **之上**：定在下面的话
## 长度是准的但天花板太低，定在上面则由对分按当次朝向压到 776～1070
## —— 长度分布更宽，代价是顶端不再是「掷多少就是多少」。
## 取舍见 [constant ROW_H] 那段。
const ARC_LEN_LO := 600.0
const ARC_LEN_HI := 1100.0
## 弧的张角。0.55 是一段很缓的长弧（半径上千，像一道远处的地平线），
## 2.3 已经超过半圆（一个「C」）。**张角越小，同一段长度弯得越缓、半径越大。**
const ARC_SPAN_LO := 0.55
const ARC_SPAN_HI := 2.3
## 半径的地板。[method _platform_in_cell] 为了把弧塞进格子会把半径往下压
## （见那里的对分），但压到这个数就不再压了 —— 再小就成一个小圆点了。
const ARC_R_MIN := 55.0
## [method arc_bounds] 沿着弧采多少个点量外接框。32 个点在这个尺度上的误差是
## 零点零几像素（`r·(1−cos(span/64))`），而它每格要被对分调用十来次，
## 不能更密了。
const ARC_SAMPLES := 32

## 云朵的宽度。**下限是「托得住车」卡的，上限是格子卡的。**
##
## ## 下限：一块比车短的板架不住车
##
## 用户的原话是「云朵目前没有支撑作用」「云朵支撑不了车」。这不是手感问题
## —— **旧的 110～340 里，有成片比车还短的**：车是拿两个轮子站着的，
## 轮距（轴距 + 两个轮子半径）比板宽还大的话，一个轮子在板上、另一个悬在空中，
## 车当场就翻。这和「彩虹片段太短了」是同一类毛病（东西比车小），
## 只是尺子从弧长换成板宽。
##
## 240 是照着**轮距**留的余量（`tests/shapes` 的 [_print_car_params] 现量出来，
## 约 160），不是照着车壳长。轮距是活的车参数，换一辆更宽的车这条线会跟着动
## —— 那边的断言就是拿现量的轮距比的。
##
## ## 上限：格子内框宽 776
##
## `半宽 = (w·cos a + 34·sin a) / 2 ≤ 388`（[constant EDGE_X] 已经让过了）。
## 按最陡的 [constant CLOUD_TILT] 解出来 `w ≤ 822`，取 800 留一点余量。
##
## 800 这个上限顺带把**坡道**这一头也解决了：云朵是这张图里唯一能把车**送上去**
## 的东西（平台全不相连、车又没有跳跃键），而一块 340 宽的板按 22° 只能把车抬高
## `340 × sin22° = 127` 像素 —— 连 [constant ROW_H] 的一半都不到。
const CLOUD_W_LO := 240.0
const CLOUD_W_HI := 800.0
## 云朵的厚度（顶面到底面）。见 [constant HillPlatform.CLOUD_H]。
const CLOUD_H := 34.0
## 云朵的**最大倾角**（弧度，≈22°）。
##
## **云朵不再是纯水平的**：这张图里平台之间全是不相连的空档，而车没有跳跃键 ——
## 平着的一块板只能把车送下去，送不上去。有坡才有高度：车沿着一块斜板爬上去、
## 从高的一头冲出去，才够得着更高的一块。
##
## 22° 卡在「爬得动」上（拱那一代记的实测是 30° 还很轻松，35° 是雪地的打滑线）。
## 再陡的话云朵看着就不像云了。
const CLOUD_TILT := 0.38

## 特殊地形在**区块内**的布局（像素，`inset` 相对区块左沿）。
##
## 全部塞进同一个区块（宽 800）里，所以 [method HillTerrain._carve] 只看 x 所在的
## 那一个区块就够，不必跨区块寻址 —— 跨区块会在缝合处让「地表折线」和「特殊地形」
## 对不上，车会看到两种地面。
##
## 火山口那一行要竖着看：`inset` 280 是**坑**的左沿，它前面还有一段 260 长的助跑坡
## （`ramp_len`），所以坡脚在区块内坐标 20 处，没有伸进上一个区块。坡后面还有
## 260 长的收尾下坡（`back_len`）。整条剖面 20 → 280 → 460 → 720，全在一个区块内。
##
## 坑口 180 宽（原来是 220）：玩家反馈「火山口不能太宽」。加上 `drop` 之后对岸
## 还低 40，起跳点比落点高，实际难度比 220 + 平对岸低了不少。
##
## `drop` 是**右沿比左沿低多少**（像素，只有火山口用得上）。玩家反馈「火山口右侧
## 应该比左侧稍低」：从坡顶起跳、落到低一点的对岸，起跳高落地低，看着像真跳过去
## 了。40 像素 = 游戏里的 4 米，一眼看得出来又不成悬崖。见 [method HillTerrain._level]。
##
## 吊桥的 `width` 比桥面总长（木板数 × 板宽）**短一点**，这一点点差就是桥的下垂量：
## 链子两端钉死、总长 420 跨 400，按悬链线近似 s ≈ sqrt(3·S·(L-S)/8) ≈ 55 px。
## 长度正好相等的话链子是「恰好绷直」的临界状态，车一压就整条折下去。
const FEATURE_LAYOUT := {
	FEATURE_BRIDGE: {
		"inset": 120.0, "width": 400.0, "depth": 380.0, "edge": 45.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
	FEATURE_SANDSTORM: {
		# 不挖地形，纯粹是个风区。故意比区块宽、往两边各探 50，
		# 免得沙尘暴看起来像个正好对齐区块的方盒子。
		# `depth` 0 也顺带关掉了「垫平两端」—— 没挖坑就谈不上两端。
		"inset": -50.0, "width": 900.0, "depth": 0.0, "edge": 0.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
	# 冰湖的 `width` 是一条**速度门槛**，不是随便定的：冰面在车踩上去 0.5 秒后
	# 裂（见 scripts/ice_lake.gd 的 BREAK_DELAY），所以过湖所需速度 = width / 0.5。
	# 300 宽 = 至少 600 px/s 才过得去 —— 冲得够快能压着冰过去，慢一点就掉下去。
	# 早先写的是 500 宽，那需要 1000 px/s，比雪地上的极速还高，等于「必死」而不是
	# 「危险」：玩家没有任何操作能改变结果。
	#
	# 但光有门槛还不够：门口得能提起速来。湖前面是上坡的话车到湖边就没速度了，
	# 那也是「必死」。所以地形那边还有一条否决规则，见
	# [method HillTerrain.feature_kind_at] 的 `LAKE_APPROACH`。
	FEATURE_LAKE: {
		"inset": 120.0, "width": 300.0, "depth": 150.0, "edge": 100.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
	FEATURE_CRATER: {
		"inset": 280.0, "width": 180.0, "depth": 420.0, "edge": 60.0,
		"ramp_len": 260.0, "ramp_h": 150.0, "back_len": 260.0, "drop": 40.0,
	},
	# 一片小石子，**不挖地形**：石子是摆在地上的独立刚体，地表原样不动。
	# 所以这一行只有「石子撒在哪一段」这一个信息，`depth` 0 顺带关掉了垫平。
	FEATURE_STONES: {
		"inset": 100.0, "width": 600.0, "depth": 0.0, "edge": 0.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
	# 隧道**不挖地形、也不垫平**：从 [constant TUNNEL_START_CHUNK] 起一路都是隧道，
	# 洞顶是另摆的一层石头刚体（地表是一条单值折线，画不出「上面石头、中间空的、
	# 下面又是石头」）。
	#
	# `inset` 0、`width` 800 = 一个区块整宽：洞顶**一块挨一块盖满**，
	# 中间一段都不能断（用户的要求：「全图都需要有上壁」「分布是连续的」）。
	# 表里只能填死数，`width` 和 [constant HillTerrain.CHUNK_WIDTH] 是否一致
	# 由 tests/features 盯着（maps.gd 是叶子脚本，引用不到那个常量）。
	#
	# 早先是「`level` 1.0 把 400 宽的一段垫平成平路，再在这一段上盖洞顶」。全图盖满
	# 之后垫平反而成了错：地形是**一块一块**垫的（每块垫到自己左沿的高度），
	# 于是每 800 像素就多出一道台阶，车在洞底一颠就撞顶 —— 那是随机死亡。
	# 洞顶自己会跟着当地的真实地表走（见 [HillTunnel._ceiling_at]），不需要垫平。
	FEATURE_TUNNEL: {
		"inset": 0.0, "width": 800.0, "depth": 0.0, "edge": 0.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
	# 月球的环形山：**一排 3～5 个「凹」字形的坑**（用户要求「每次连续出现 3-5 个」）。
	#
	# 和早先那个「又宽又浅的碗」（70 深、360 宽、27° 斜坡）是反着来的：`edge` 22
	# 像素却要掉 90 —— 侧壁约 76°，**车轮碾上去会直接陷进去，靠动力爬不出来**。
	# 玩法因此变成「借月球 0.35 的重力从坑沿跃过整排」，而不是慢慢开过去。
	#
	# `width` 520 要装得下最多 5 个坑：5 × 70 + 4 × 40 = 510。两端各留 140 的过渡段
	# （`inset` 140、右边 800 − 140 − 520 = 140），整排居中摆。
	#
	# **没有致命区**：掉进坑里只是出不来，死不了（和火山口反着来 —— 那个 420 深、
	# 掉下去烧死）。想出来得倒车、或者等惯性把自己甩出去。
	FEATURE_CRATERS: {
		"inset": 140.0, "width": 520.0, "depth": 90.0, "edge": 22.0,
		"notch": 70.0, "notch_gap": 40.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
	# 森林：一丛 3～5 棵树站在这 `width` 里（棵数和间隔随机，见 scripts/trees.gd），
	# 地表不动。
	#
	# 700 是**装得下**算出来的：最多 5 棵、相邻最长 `GROVE_GAP_MAX` 165 →
	# 4 × 165 = 660 < 700。所以不管哈希抽出哪一丛，两棵之间都塞得下、
	# 也不会探出段外压到隔壁区块的地盘上。
	FEATURE_TREES: {
		"inset": 120.0, "width": 700.0, "depth": 0.0, "edge": 0.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
	# 烟囱**不挖地形、不垫平**：它就是长在屋面（已经是平的那几级）上的一根砖柱子，
	# 一像素地表都不动。所以这一行的 `depth` 是 0、`edge` 是 0，只有
	# 「哪一段归这块区块管」这一个信息 —— 和隧道一样是整块区块。
	#
	# `width` 800 的意思和隧道那条一样：**每块区块都发**（见 [method feature_at]），
	# 因为烟囱摆在哪一级屋面要问过判过剖面的 [method HillChimneys.chimney_rect]
	# 才知道，maps.gd 这边算不出来。发出去了那块摆不出烟囱，就什么也不摆 ——
	# 比在这里猜「这块有没有」便宜，也不会出现「骰子说有、剖面说摆不下」。
	FEATURE_CHIMNEYS: {
		"inset": 0.0, "width": 800.0, "depth": 0.0, "edge": 0.0,
		"ramp_len": 0.0, "ramp_h": 0.0, "back_len": 0.0, "drop": 0.0,
	},
}

const MAPS := {
	PLAINS: {
		"zh": "平原",
		"en": "PLAINS",
		"zh_note": "标准地形，吊桥是软的",
		"en_note": "the baseline; springy rope bridges",
		"sky": Color(0.53, 0.78, 0.92),
		"dirt": Color(0.36, 0.24, 0.16),
		"crust": Color(0.35, 0.68, 0.28),
		"far": Color(0.44, 0.60, 0.68),
		"mid": Color(0.34, 0.52, 0.50),
		"near": Color(0.26, 0.44, 0.36),
		"cloud": Color(1.0, 1.0, 1.0),
		"amp_scale": 1.0,
		"seed_offset": 0,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"feature": FEATURE_BRIDGE,
	},
	DESERT: {
		"zh": "荒漠",
		"en": "DESERT",
		"zh_note": "风沙拖着你，跑不快",
		"en_note": "drag holds you back",
		"sky": Color(0.93, 0.81, 0.60),
		"dirt": Color(0.62, 0.48, 0.30),
		"crust": Color(0.88, 0.76, 0.48),
		"far": Color(0.80, 0.68, 0.47),
		"mid": Color(0.71, 0.56, 0.37),
		"near": Color(0.58, 0.44, 0.29),
		"cloud": Color(0.99, 0.95, 0.87),
		"amp_scale": 1.15,
		"seed_offset": 8317,
		"friction_scale": 1.0,
		"drag": 0.6,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"feature": FEATURE_SANDSTORM,
	},
	SNOW: {
		"zh": "雪地",
		"en": "SNOW",
		"zh_note": "轮子抓不住地，刹不住",
		"en_note": "almost no grip",
		"sky": Color(0.78, 0.86, 0.94),
		"dirt": Color(0.55, 0.60, 0.68),
		"crust": Color(0.95, 0.97, 1.0),
		"far": Color(0.72, 0.80, 0.88),
		"mid": Color(0.60, 0.70, 0.80),
		"near": Color(0.48, 0.58, 0.70),
		"cloud": Color(1.0, 1.0, 1.0),
		"amp_scale": 0.90,
		"seed_offset": 20261,
		# 0.12 → 摩擦系数 0.31。见 tests/grip_climb_probe：摩擦不是「越小越滑」的
		# 线性旋钮，2.60 一路压到 0.78 车都还咬得死死的（平地打滑 1.00×），
		# 因为起步时的推力需求本来就低，轮子自己的惯量才是瓶颈。0.31 是实测
		# 出来的那一段：平地打滑 1.68×、1.5 秒里程从 739 掉到 331，
		# 而 20°/30°/35° 坡上仍能以 453/367/327 的速度往上爬 —— 打得滑，但爬得动。
		"friction_scale": 0.18,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"feature": FEATURE_LAKE,
	},
	VOLCANO: {
		"zh": "火山",
		"en": "VOLCANO",
		"zh_note": "油耗快，火山口得跳过去",
		"en_note": "thirsty engine, jump the craters",
		"sky": Color(0.24, 0.16, 0.18),
		"dirt": Color(0.22, 0.16, 0.16),
		"crust": Color(0.74, 0.28, 0.11),
		"far": Color(0.34, 0.22, 0.24),
		"mid": Color(0.28, 0.17, 0.19),
		"near": Color(0.20, 0.12, 0.14),
		"cloud": Color(0.32, 0.27, 0.29),
		"amp_scale": 1.25,
		"seed_offset": 39461,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.6,
		"gravity_scale": 1.0,
		"feature": FEATURE_CRATER,
	},
	MOUNTAIN: {
		"zh": "山地",
		"en": "MOUNTAIN",
		"zh_note": "坡更陡、抓地更死，满地碎石子",
		"en_note": "steeper and grippier, stones under the wheels",
		"sky": Color(0.60, 0.74, 0.88),
		"dirt": Color(0.40, 0.34, 0.28),
		"crust": Color(0.56, 0.56, 0.54),
		"far": Color(0.52, 0.58, 0.62),
		"mid": Color(0.39, 0.47, 0.43),
		"near": Color(0.29, 0.37, 0.31),
		"cloud": Color(1.0, 1.0, 1.0),
		# 1.35 是幅度上限的倍率：山地的上限从 140 抬到 189 像素。**没动 BASE_AMPLITUDE**
		# ——出生点附近那一百多米的手感和别的图一样，难是往后越来越难。
		"amp_scale": 1.35,
		"seed_offset": 51421,
		# 抓着不放：和雪地（0.18）正好是这条轴的两头。实测见 tests/grip_climb_probe，
		# 摩擦系数 2.60 → 3.51，爬 30° 坡比平原更稳、更不容易空转。
		"friction_scale": 1.35,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"feature": FEATURE_STONES,
	},
	TUNNEL: {
		"zh": "隧道",
		"en": "TUNNEL",
		"zh_note": "整张图都在洞里，洞顶压得很低，别加油门抬头",
		"en_note": "a roof the whole way — don't pop a wheelie inside",
		"sky": Color(0.44, 0.50, 0.60),
		"dirt": Color(0.28, 0.27, 0.27),
		"crust": Color(0.48, 0.46, 0.44),
		"far": Color(0.37, 0.39, 0.43),
		"mid": Color(0.28, 0.30, 0.34),
		"near": Color(0.20, 0.22, 0.26),
		"cloud": Color(0.86, 0.88, 0.91),
		"amp_scale": 1.10,
		"seed_offset": 62773,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"feature": FEATURE_TUNNEL,
	},
	MOON: {
		"zh": "月球",
		"en": "MOON",
		"zh_note": "重力只有三分之一，一跳老高",
		"en_note": "one third gravity, floaty as anything",
		# 天空是黑的、云也是黑的（见 `cloud`）—— 月球上没有云，
		# 但 [HillBackground] 照样会画，所以把云的配色压到和天空一样就看不见了。
		"sky": Color(0.04, 0.05, 0.10),
		"dirt": Color(0.34, 0.33, 0.32),
		"crust": Color(0.72, 0.71, 0.68),
		"far": Color(0.22, 0.21, 0.24),
		"mid": Color(0.16, 0.15, 0.18),
		"near": Color(0.11, 0.10, 0.13),
		"cloud": Color(0.06, 0.07, 0.12),
		"amp_scale": 1.05,
		"seed_offset": 73609,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		# **整张图唯一的物理修正就是这一条。** 0.35 是手感值：起跳高度和滞空时间
		# 都是 1/0.35 ≈ 2.9 倍，横着能飞出去的距离也是；太低了（0.15）车会飘到
		# 操作不动、镜头也跟不上。
		"gravity_scale": 0.35,
		"feature": FEATURE_CRATERS,
	},
	FOREST: {
		"zh": "森林",
		"en": "FOREST",
		"zh_note": "树挡在路上，撞得够快才推得倒",
		"en_note": "trees block the road — hit them fast",
		"sky": Color(0.56, 0.80, 0.86),
		"dirt": Color(0.32, 0.24, 0.16),
		"crust": Color(0.28, 0.52, 0.24),
		"far": Color(0.30, 0.46, 0.36),
		"mid": Color(0.22, 0.38, 0.28),
		"near": Color(0.15, 0.29, 0.21),
		"cloud": Color(1.0, 1.0, 1.0),
		"amp_scale": 0.95,
		"seed_offset": 84551,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"feature": FEATURE_TREES,
	},
	ROOFTOP: {
		"zh": "屋顶",
		"en": "ROOFTOPS",
		"zh_note": "一条街的房子：平屋顶 + 钢梯，每两栋之间一道缝",
		"en_note": "a street of houses: flat roofs, steel ladders, a gap between them",
		"sky": Color(0.40, 0.50, 0.68),
		"dirt": Color(0.28, 0.25, 0.26),
		"crust": Color(0.66, 0.38, 0.29),
		"far": Color(0.34, 0.38, 0.48),
		"mid": Color(0.26, 0.29, 0.38),
		"near": Color(0.18, 0.20, 0.28),
		"cloud": Color(0.98, 0.95, 0.92),
		# 起伏倍率对本图**没有作用**（地表是形状算出来的，不是噪声），填 1.0 是
		# 为了让「平原必须是恒等变换」那条约定之外的行也一眼看得出自己不动那些旋钮。
		"amp_scale": 1.0,
		"seed_offset": 96821,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"shape": SHAPE_ROOFS,
		"feature": FEATURE_CHIMNEYS,
		"gimmick": {
			"zh": "楼顶裂缝", "en": "ROOF GAPS",
			"zh_note": "屋顶之间是空的，得跳", "en_note": "nothing but air between the roofs",
		},
	},
	ARENA: {
		"zh": "竞技场",
		"en": "ARENA",
		"zh_note": "坡又长又缓，一路甩上去",
		"en_note": "long, gentle, very tall rollers",
		"sky": Color(0.20, 0.23, 0.30),
		"dirt": Color(0.30, 0.28, 0.32),
		"crust": Color(0.86, 0.78, 0.36),
		"far": Color(0.28, 0.28, 0.36),
		"mid": Color(0.21, 0.21, 0.29),
		"near": Color(0.15, 0.15, 0.22),
		"cloud": Color(0.72, 0.74, 0.82),
		# 「地形较为平滑但起伏很大」= 幅度往上调、频率往下调，两件事一起做。
		#
		# 只调幅度会变成一堆陡坡（噪声本来的波长是 769 像素，幅度翻三倍之后
		# 同一段水平距离里要爬三倍的高度，坡度跟着翻三倍）；只调频率会变成
		# 一条平缓的大波浪、一点都不「大」。所以是 `amp_scale` 2.2 + 频率降到
		# 0.00042（波长 2381 像素）+ 只用两层八度。
		#
		# 八度从 3 降到 2 也是「平滑」的一部分：第三层八度的波长只有 192 像素，
		# 它才是地表上那些小疙瘩的来源。**实测坡度见 tests/features 的竞技场一节。**
		"amp_scale": 2.2,
		"noise_freq": 0.00042,
		"noise_octaves": 2,
		"seed_offset": 107347,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"feature": FEATURE_NONE,
		"gimmick": {
			"zh": "大起伏", "en": "BIG ROLLERS",
			"zh_note": "坡缓但很高，冲上去再冲下来", "en_note": "gentle and enormous at the same time",
		},
	},
	RAINBOW: {
		"zh": "彩虹",
		"en": "RAINBOW",
		"zh_note": "没有地面 —— 空中散着一片彩虹弧和云朵，全都不挨着",
		"en_note": "no ground at all: scattered arcs and clouds, none of them touching",
		"sky": Color(0.33, 0.30, 0.56),
		# **一张没有地表的地图**：`_base_height` 只用来给相机和道具找一个「上面」，
		# 区块本身不生成地面多边形，车站在哪块彩虹/云上就靠那块东西自己撑着。
		# `dirt` / `crust` 因此在这张图上用不到，留着是为了配色表结构统一。
		"dirt": Color(0.80, 0.84, 0.97),
		"crust": Color(0.98, 0.86, 0.42),
		"far": Color(0.44, 0.40, 0.66),
		"mid": Color(0.36, 0.33, 0.58),
		"near": Color(0.28, 0.26, 0.48),
		"cloud": Color(1.0, 0.98, 1.0),
		"amp_scale": 1.0,
		"seed_offset": 118109,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		"shape": SHAPE_ARCHES,
		# 彩虹和云朵都是**独立刚体**，地形自己什么feature都不出。
		"feature": FEATURE_NONE,
		"gimmick": {
			"zh": "空中散布", "en": "SCATTERED",
			"zh_note": "上下 200 米全是平台，落点看运气，掉到底就没了",
			"en_note": "platforms fill ±200 m — the fall is luck, the bottom is death",
		},
	},
	NIGHT: {
		"zh": "黑夜",
		"en": "NIGHT",
		"zh_note": "只看得见车周围一小圈，金币还是亮的",
		"en_note": "you only see the circle around the car",
		"sky": Color(0.03, 0.04, 0.08),
		"dirt": Color(0.22, 0.21, 0.24),
		"crust": Color(0.42, 0.44, 0.50),
		"far": Color(0.16, 0.17, 0.22),
		"mid": Color(0.12, 0.12, 0.17),
		"near": Color(0.08, 0.08, 0.12),
		"cloud": Color(0.10, 0.11, 0.16),
		"amp_scale": 1.05,
		"seed_offset": 129671,
		"friction_scale": 1.0,
		"drag": 0.0,
		"fuel_scale": 1.0,
		"gravity_scale": 1.0,
		# **这一条是本图唯一的机制**：一块盖住全屏的黑布，车周围挖一个洞。
		# 见 scripts/night.gd 和 [constant NIGHT_Z]。
		"night": true,
		"feature": FEATURE_NONE,
		"gimmick": {
			"zh": "黑夜", "en": "DARKNESS",
			"zh_note": "只看得到车灯那一圈", "en_note": "only the patch you're standing in",
		},
	},
}

## 黑夜挡布画在哪一层。**必须比地形（0）、车（1）和金币油桶（也都是 0）高**，
## 否则它盖不住这些东西 —— 挡布盖得住的才叫「看不见」，洞里的才看得见。
## 这个数是**跨脚本的约定**（night.gd 照着写 z，terrain.gd 一个都不许往上抬），
## 所以放在这个谁都依赖的叶子类里。
const NIGHT_Z := 2


## 取一张地图的定义。id 不认识就退回平原 —— 存档里的字符串可能是旧版本写的。
static func get_map(id: String) -> Dictionary:
	if MAPS.has(id):
		return MAPS[id]
	return MAPS[PLAINS]


## 世界坐标 x 处的里程（米）。计分和补给衰减共用这一套换算。
static func meters_at(x: float) -> float:
	return maxf(0.0, x - START_OFFSET) / PIXELS_PER_METER


## 里程（米）对应的世界坐标 x。**[method meters_at] 的反函数**，只此一处，
## 谁要按里程定一个 x（地形那个复利起点就是）都得走这里：两处各写一遍的话，
## 哪天 START_OFFSET 动了，只有一边跟着动。
static func x_at(meters: float) -> float:
	return START_OFFSET + meters * PIXELS_PER_METER


## id 是否合法。
static func has_map(id: String) -> bool:
	return MAPS.has(id)


## 解锁这张图要花多少金币；**0 表示不用花钱**（免费的，或者这个 id 不存在）。
##
## 不认识的 id 给 0：那是「没什么可收的」，不是「免费」。**「能不能开」不问这里**，
## 问 [method is_free] / [method SaveData.map_unlocked] —— 一个 id 不存在时
## 这两处都回答「不能开」，所以坏档不会因为「价钱是 0」就被放行。
##
## 坏档、手改过的 cfg、以后删掉的地图落到这里，真正托底的是
## [method SaveData._repair_locked_selection]（把选中的那张换回平原），不是这条。
static func price_of(id: String) -> int:
	var i := IDS.find(id)
	if i < 0 or i < FREE_COUNT:
		return 0
	return UNLOCK_PRICE


## 这张图是不是白送的（在 [constant IDS] 里，而且排在前 [constant FREE_COUNT] 个）。
##
## **不认识的 id 一律不算免费。** [method SaveData.map_unlocked] 把这个返回值当成
## 「能不能开」用，那就是一道权限判断 —— 权限判断的兜底必须是否决。认不出来的东西
## 当作「能开」比当作「不能开」危险得多，哪怕现在每个调用点都先过了 [method has_map]。
static func is_free(id: String) -> bool:
	var i := IDS.find(id)
	return i >= 0 and i < FREE_COUNT


## 这块区块该放什么特殊地形。
##
## 纯函数：只取决于（世界种子、地图、区块序号），所以区块滚出视野再滚回来、
## 或者因为镜头来回晃而重建，结论永远一样 —— 否则玩家会看到桥凭空换地方。
##
## 相邻区块不连放两个：连着两个沟就是必死路段，不是难度。
##
## **隧道是个例外：每一块区块都是**（从 [constant TUNNEL_START_CHUNK] 起）。它
## 既不吃 [constant FEATURE_CHANCE]，也不吃相邻规则 —— 那两条规则说的是「孤零零的
## 一小段特殊地形」，而隧道的上壁**本来就该连成一片**：停一块就是天上开个天窗。
##
## 出生点那一段（0 号区块，车摆在 x = 200）**不盖拱**：开局就压在石头底下，
## 玩家连「先开一段」都没有。见 [constant TUNNEL_START_CHUNK]。
static func feature_at(world_seed: int, map_id: String, index: int) -> String:
	if index < 0:
		return FEATURE_NONE
	var kind: String = get_map(map_id)["feature"]
	if kind == FEATURE_NONE:
		return FEATURE_NONE
	if kind == FEATURE_TUNNEL:
		return kind if index >= TUNNEL_START_CHUNK else FEATURE_NONE
	if kind == FEATURE_CHIMNEYS:
		# **每一块区块都发**，和隧道同一个道理：烟囱摆在本栋的哪一级平屋面上，
		# 要拿 [method HillTerrain.roof_profile] 判过才知道（那一级够不够宽、
		# 是不是落点/跳台），maps.gd 这边一份剖面都算不出来。所以这里只挡掉
		# 出生那一栋（车摆在人家屋面上，开局就顶着一柱烟不合适），
		# 剩下交给 [method HillChimneys.chimney_rect]：摆不下就什么也不摆。
		return kind if index >= SHAPE_START_CELL else FEATURE_NONE
	if index < FEATURE_MIN_CHUNK:
		return FEATURE_NONE
	if _roll(world_seed, index) >= FEATURE_CHANCE:
		return FEATURE_NONE
	if _roll(world_seed, index - 1) < FEATURE_CHANCE:
		return FEATURE_NONE
	return kind


## 本区块的环形山连着摆几个。
##
## 和 [method feature_at] 一样是**纯函数**：挖地形（[method HillTerrain._carve]）
## 和测试问的是同一个结论，不能各掷各的骰子 —— 各自掷的话，测试量到的「一排几个」
## 和玩家看到的不是一回事。
static func craters_at(world_seed: int, index: int) -> int:
	var slots := CRATERS_MAX - CRATERS_MIN + 1
	return CRATERS_MIN + int(_hash01(world_seed * 6151 + index * 89 + 13) * float(slots))


## 某种特殊地形在区块内的布局。不认识的种类给「不挖地形」的那一份 ——
## 地形和特殊地形节点都照着这个字典走，所以挖出来的坑和铺上去的冰面永远对齐。
static func feature_layout(kind: String) -> Dictionary:
	if FEATURE_LAYOUT.has(kind):
		return FEATURE_LAYOUT[kind]
	return FEATURE_LAYOUT[FEATURE_SANDSTORM]


## 区块内特殊地形的水平范围（`inset` 换算成世界坐标），没有特殊地形返回宽 0 的矩形。
##
## `chunk_width` 由调用方给（地形的 POINT_SPACING × CHUNK_POINTS），这样区块宽
## 只有一处定义，不存在「表里写 800、地形改成 900」这种对不上的可能。
static func feature_rect(world_seed: int, map_id: String, index: int,
		chunk_width: float) -> Rect2:
	return rect_of(feature_at(world_seed, map_id, index), index, chunk_width)


## 某种特殊地形在区块内的矩形。**从「是哪种」算，不自己再掷一次骰子。**
##
## 地形那边除了 [method feature_at] 的骰子，还有自己的否决规则（冰湖前面是上坡
## 就不摆，见 [method HillTerrain.feature_kind_at]）。挖坑和摆冰面都必须听**同一个**
## 结论，所以「是哪种」由调用方给进来 —— 否则会出现「挖了坑但不摆桥」。
## 尺寸仍然只在这张表里定义一份。
static func rect_of(kind: String, index: int, chunk_width: float) -> Rect2:
	if kind == FEATURE_NONE:
		return Rect2()
	var layout := feature_layout(kind)
	var x0 := float(index) * chunk_width + float(layout["inset"])
	return Rect2(x0, 0.0, float(layout["width"]), float(layout["depth"]))


## 该区块「本来」会不会是特殊地形，不管相邻规则。返回小于 [constant FEATURE_CHANCE]
## 就是命中。
##
## 相邻检查必须问这个而不能问 [method feature_at] —— 后者会把被相邻规则否掉的
## 区块报成「不是」，于是再下一个区块也跟着被否，连着空掉三四个区块。
##
## 第 [constant FEATURE_MIN_CHUNK] 块返回 0.0：必定命中。顺带把下一块排除掉
## （相邻规则会看到 0.0 < FEATURE_CHANCE 而否掉它），不会两个保底撞在一起。
static func _roll(world_seed: int, index: int) -> float:
	if index < FEATURE_MIN_CHUNK:
		return 1.0
	if index == FEATURE_MIN_CHUNK:
		return 0.0
	return _hash01(world_seed * 9781 + index * 31 + 7)


## 该地图的地形噪声种子。每张图偏移一个常数，于是八张图的地形完全不同，
## 而平原偏移为 0，所以它的地形和以前一模一样。
static func noise_seed(world_seed: int, map_id: String) -> int:
	return world_seed + int(get_map(map_id)["seed_offset"])


# ---------------------------------------------------------------- 玩法模式
#
# 每张地图都有两种玩法：**经典**（地形永远是同一个种子，也就是玩家已经背下来的
# 那张图）和**随机**（每局现摇一个种子，地图每局都不一样）。
#
# 判据只有一个数：[member HillTerrain.world_seed]。地形、金币、油桶、特殊地形、
# 沟、云、树林、石头……**全部**是从它推出来的（各自用自己的
# [RandomNumberGenerator] 按位置或按它播种，见 stones.gd / trees.gd / pickup.gd
# 的注释），所以换一个种子就是换一张完整的地图，不需要任何一处「重新生成」的代码。
#
# 两边各自固定的一件事：
#
#  · 经典模式的种子**永远是 1337，不许动**。纪录榜上每一个数字都是在这一个地形上
#    跑出来的，换种子等于把玩家的纪录换成别人家的地形上的成绩。
#  · 随机模式**不写任何纪录**（见 [method HillGame._on_car_crashed]）：地形每局
#    都不一样，距离之间没有可比性，记进去的话纪录榜就成了运气榜。

## 经典模式：固定种子，纪录和成就都算数。
const MODE_CLASSIC := "classic"
## 随机模式：每局现摇种子，只收金币。
const MODE_RANDOM := "random"
## 模式表。**次序就是界面上的次序**（选图页页脚那两格）。
const MODES: Array[String] = [MODE_CLASSIC, MODE_RANDOM]

## 经典模式的种子。见上面那一段，**这个数不许动**。
const CLASSIC_SEED := 1337

## 随机模式摇出来的种子有多大。取 2^30：`world_seed` 会被各处乘上几千再拼进
## 哈希（[method _roll] 的 `world_seed * 9781`），留够余量不让它溢出到负数。
const SEED_MAX := 1 << 30

## 界面上的两个字。zh/en 分开写，跟 [method get_map] 的 "zh"／"en" 一个规矩。
const MODE_LABEL := {
	MODE_CLASSIC: {"zh": "经典", "en": "CLASSIC"},
	MODE_RANDOM: {"zh": "随机", "en": "RANDOM"},
}
## 界面上的说明。**玩家会照着这一行理解两种模式的差别**，所以要写清楚
## 「地图一不一样」和「算不算成绩」这两件事，而不是「经典 / 随机」四个字本身。
const MODE_NOTE := {
	MODE_CLASSIC: {
		"zh": "经典模式：地图每次都一样，纪录和成就都算数",
		"en": "classic: same map every run, records and achievements count",
	},
	MODE_RANDOM: {
		"zh": "随机模式：地图每局重新生成，只收金币、不计纪录和成就",
		"en": "random: a fresh map every run, coins only, no records",
	},
}

## 上一次摇出来的种子。只为「同一微秒里连摇两次不会撞」用，见 [method random_seed]。
static var _last_seed := -1


## 不认识的模式一律当经典 —— 存档里手改过一个错字之类的情况不该让选图页崩掉。
static func normalize_mode(mode: String) -> String:
	return mode if MODES.has(mode) else MODE_CLASSIC


static func mode_label(mode: String) -> Dictionary:
	return MODE_LABEL[normalize_mode(mode)]


static func mode_note(mode: String) -> Dictionary:
	return MODE_NOTE[normalize_mode(mode)]


## 随机模式开局摇的种子：**每次调用都不一样**。
##
## **自己开一个发生器，不用全局 `randi()`。** 全局那一条流别的地方也在用
## （特效、沙尘的粒子），从这里抽一个数会把它们整体推后一格 —— 那些地方看着是
## 随机的，实际上一帧一帧都被测试比对过，凭空挪一格会让那些测试莫名其妙地红。
##
## 拿系统时钟播种（[method RandomNumberGenerator.randomize]），所以**跨进程**
## 也不同（关掉游戏再打开还是新地图）。同一微秒内连摇两次会撞，撞了往后挪一格 ——
## 「每局都不一样」是这条模式的卖点，不能因为时钟分辨率偶尔破一次。
static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := rng.randi_range(1, SEED_MAX)
	if s == _last_seed:
		s = s % SEED_MAX + 1
	_last_seed = s
	return s


## 地形起伏幅度的倍率。
static func amp_scale(map_id: String) -> float:
	return get_map(map_id)["amp_scale"]


## 这张图的地形形态（[constant SHAPE_NOISE] / [constant SHAPE_ROOFS] /
## [constant SHAPE_ARCHES]）。表里没写就是噪声那一款。
static func shape_of(map_id: String) -> String:
	return get_map(map_id).get("shape", DEFAULT_SHAPE)


## 出生直道那块平地的绝对高度（相对 [constant HillTerrain.GROUND_Y]，负 = 往上）。
##
## **彩虹图高半行**（[constant PAD_DY]），别的图就在 `GROUND_Y` 上。
##
## 三处问的是**同一个函数**，不许各算各的：
##
##   · 铺 0 号区块那块平地的多边形（[method HillTerrain._build_chunk]）
##   · `height_at` 在出生直道上的答案（[method HillTerrain._base_height]）
##   · 把车摆到出生点的那一下（[method HillGame._enter_tree]）
##
## 前两处一旦对不上，车就生在出生台的实心多边形里；第三处漏了，车**也**生在
## 实心多边形里。实测两种都是同一个后果：车头传感器一进树就撞上地面
## （[method HillCar._on_head_body_entered] 直接发 `crashed`），**开局第一帧就死**。
static func pad_dy(map_id: String) -> float:
	return PAD_DY if shape_of(map_id) == SHAPE_ARCHES else 0.0


## 这张图是不是形状地图（地表是解析形状而不是噪声）。
##
## 形状地图的 `amp_scale` / `noise_freq` / `noise_octaves` **全部失效** ——
## 调用方（[HillTerrain]）靠这一个函数分流，不要各自去 match 形状名。
static func is_shaped(map_id: String) -> bool:
	return shape_of(map_id) != SHAPE_NOISE


## 这张图的地表形态是不是「有缝」（缝 = 地表上少了一块，掉下去要判死）。
##
## **现在只有屋顶图有缝。** 彩虹图原来也有（50% 的区块末尾挖一条，
## 见早先的 `VOID_CHANCE`），改成散落的平台场之后那张图**根本没有地表**，
## 「地表上少了一块」也就无从谈起 —— 它整条图都是空档。
static func has_gaps(map_id: String) -> bool:
	return shape_of(map_id) == SHAPE_ROOFS


## 形状地图第 `index` 个区块末尾那条缝有多宽。**屋顶图专用**。
##
## 彩虹图改成散落的平台场之后不再挖缝（见 [constant PLATFORM_RAINBOW]）——
## 那张图里本来就没有「地表」这个东西，也就无所谓「地表上少了一块」。
## 于是全图只剩屋顶图还有缝，`chance` 那一路（彩虹图的 50% 掷骰）随之取消。
##
## **纯函数**，和 [method feature_at] 一样：地形挖缝（[method HillTerrain._carve]）、
## [method HillTerrain.gap_rect]、算下一栋房子起点高度的
## （[method HillTerrain.roof_profile]），问的全是这一个结论。各自掷骰子的话，
## 会出现「挖了缝但屋顶铺到别处」这种最难看出来的错。
##
## 缝的宽度**跟着世界种子变**：不然每开一局这条图都是一模一样的缝，
## 玩家跑第二趟就没有判断可言了。区块序号进哈希，所以同一条缝滚出视野再滚回来
## 还是同一条。
static func gap_at(world_seed: int, index: int) -> float:
	var spread := GAP_MAX - GAP_MIN
	return GAP_MIN + _hash01(world_seed * 4133 + index * 977 + 29) * spread


## **本图**第 `index` 块末尾那条缝有多宽。
##
## `map_id` 现在不参与计算（有缝的只剩屋顶图），但**签名里留着**：调用点
## （[method HillTerrain.gap_rect] / [method HillTerrain._rim_lx]、tests/random_mode）
## 说的都是「本图的那条缝」，将来真要有第二张带缝的图，要改的只有这一个函数体。
static func gap_for(world_seed: int, map_id: String, index: int) -> float:
	return gap_at(world_seed, index)


## 形状地图第 `index` 个区块里，**屋顶** 有多长（= 一个区块宽 − 那条缝）。
##
## 屋顶长度是随机的，就随机在这里：缝宽在 [constant GAP_MIN]～[constant GAP_MAX]
## 之间掷，剩下的全归屋顶。**两个数是一个数**（`PITCH − 缝宽`）：
## 缝有多宽、屋顶有多长，各算一遍是一定会对不上的。
##
## 所以屋顶长度落在 650～670 之间，其中 450 是固定的两段（落点
## [constant ROOF_LAND] + 跳台 [constant ROOF_LEDGE]），剩下的给钢梯和中间的平路。
## 想让它更参差的话要动的是缝宽范围 —— 而缝宽的上限由「跳不跳得过去」定死
## （见 [constant GAP_MAX]），那不是能随便放的参数。
static func span_at(world_seed: int, index: int) -> float:
	return SHAPE_PITCH - gap_at(world_seed, index)


## 第 `col` 列里散落的所有平台。**纯函数**，和 [method roof_dice] 一样：
## 区块会滚出视野再重建，滚回来重建出来的必须还是那几块。
##
## 一列 = [constant CELL_W] 像素宽 = 一个区块，共 [constant ROW_COUNT] 格。
## 每格独立掷骰子：先掷「这一格有没有东西」（[constant FILL]），再掷「是彩虹还是云」
## （[constant RAINBOW_SHARE]），最后掷尺寸和位置。
##
## 返回的每块是 `{kind, x, dy, off, half, …}`：`x` / `dy` 是**这块东西自己的中心**
## —— 彩虹是圆心、云是板的中心 —— 世界坐标，`dy` 相对 [constant HillTerrain.GROUND_Y]
## 且负 = 往上。**外接框**则要再加上 `off`：中心在 `(x + off.x, dy + off.y)`、
## 半宽半高是 `half`。彩虹的圆心不在弧的中间，所以 `off` 不是零。
##
## 彩虹多 `r` / `span` / `tilt` / `len`（`len` = 弧长，测试要看），云多一个 `w`。
static func platforms_in_column(world_seed: int, col: int) -> Array:
	var out: Array = []
	for row in ROW_COUNT:
		var p := _platform_in_cell(world_seed, col, row)
		if not p.is_empty():
			out.append(p)
	return out


## 一块区块里的全部平台。地形建区块时问这个。
##
## 区块盖住哪几列由 [constant COLS_PER_CHUNK] 定（现在是 1：一块区块正好一列）。
## **写成乘法而不是写死 `index * 2`**：格子宽一改，这里忘了跟着改就会**漏平台**
## —— 区块把不属于自己的列建出来、自己的那一列反而空着，而两边都不会报错。
static func platforms_at(world_seed: int, index: int) -> Array:
	var out: Array = []
	for c in COLS_PER_CHUNK:
		out.append_array(platforms_in_column(world_seed, index * COLS_PER_CHUNK + c))
	return out


## 世界坐标 `x` 处，**最高的那块平台的顶**（相对 GROUND_Y 的 `dy`）；
## 那一列一块平台都没有的话返回带子的底（[constant BAND]）。
##
## 这个函数是给 [method HillTerrain.height_at] 用的 —— 那张图里地表不再是单值的，
## 而相机钳位、刷道具这些调用方要的其实是一个「这一带的顶棚在哪」。
##
## **只查一个格子。** 这不是近似：平台按构造缩在自己的格子里，所以能盖住 `x` 的
## 平台必然在 `floor(x / CELL_W)` 那一列里。
static func ceiling_dy_at(world_seed: int, x: float) -> float:
	var col := int(floor(x / CELL_W))
	var best := BAND
	for p in platforms_in_column(world_seed, col):
		best = minf(best, float(p["dy"]) + float(p["off"].y) - half_height(p))
	return best


## 一段弧的**外接框**，坐标是**相对圆心**的（圆心在原点）。
##
## 弧是环扇形：半径从 `r − 15` 到 `r + 15`（[constant ARC_THICK]），角度从
## `tilt − span/2` 到 `tilt + span/2`。它的外接框**不是**边长 `2(r+15)` 的正方形
## —— 那只在张角接近整圈时才对。张角小的时候外接框是**又长又扁**的一条：
## 长度约 `2r·sin(span/2)`，厚度约 `15·2 + r·(1−cos(span/2))`。
##
## **这个区别是整件事的关键。** 按正方形算的话半径被格子卡在 ≤100，弧长只能到
## 一百多像素（比车还短）；按真实外接框算，一个 776×780 的格子（[constant CELL_W]
## 那一代）能装下**上千像素长的缓弧** —— 半径可以上千，只要张角跟着变小。
## 用户要的「长」就是这个。
##
## 沿弧采 [constant ARC_SAMPLES] 个点直接量 —— 两端的内外弧端点都采到了，
## 所以两个径向端面的点都落在已采点的凸包里，不必另算。
static func arc_bounds(r: float, span: float, tilt: float) -> Rect2:
	var outer := r + ARC_THICK * 0.5
	var inner := maxf(r - ARC_THICK * 0.5, 0.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in ARC_SAMPLES + 1:
		var a := tilt - span * 0.5 + span * float(i) / float(ARC_SAMPLES)
		var dir := Vector2(cos(a), sin(a))
		lo = lo.min(dir * inner)
		hi = hi.max(dir * inner)
		lo = lo.min(dir * outer)
		hi = hi.max(dir * outer)
	return Rect2(lo, hi - lo)


## `a` 这个角上，一段弧的**顶**在哪 —— 也就是弧上 y 最小的那一点。
static func arc_top(r: float, span: float, tilt: float) -> Vector2:
	var lo := tilt - span * 0.5
	var hi := tilt + span * 0.5
	# sin 在 `−π/2 + 2kπ` 处取最小。把这一族角挪进 `[lo, hi]` 里，落进去就是内点，
	# 落不进去说明最高的地方在弧的**端点**上，比一比哪头高。
	var a := -PI * 0.5 + ceilf((lo + PI * 0.5) / TAU) * TAU
	if a < lo or a > hi:
		a = lo if sin(lo) < sin(hi) else hi
	# 取**外**弧：同一个角上外弧永远不比内弧低。
	return Vector2(cos(a), sin(a)) * (r + ARC_THICK * 0.5)


## 一块平台**顶上那一点**相对自身中心的偏移（[method HillTerrain._platform_top] 用）。
##
## 彩虹给的是**弧上最高那一点** —— 这个不能拿外接框的顶去凑：外接框的顶边是**一条
## 水平线**，顶上那一点的 x 只有弧本身对称时才落在框的正中间。缓弧一转（这张图的弧
## 什么朝向都有），框顶中点就跑到弧外面去了，金币会凭空浮在弧旁边。
##
## 云给的还是它自己的中心：云是一块板，车走的是板面，金币从板心往上抬 36 像素正好
## 在面上面一点（见 [method HillTerrain._spawn_platform_pickups]）。
static func top_offset(p: Dictionary) -> Vector2:
	if String(p["kind"]) == PLATFORM_CLOUD:
		return Vector2.ZERO
	return arc_top(float(p["r"]), float(p["span"]), float(p["tilt"]))


## 一块平台的外接框在竖直方向上的半高。散布的约束（[constant EDGE_X] /
## [constant EDGE_Y]）、[method ceiling_dy_at] 和地形那边刷道具都用它，所以只算一处。
##
## 两个字段都是 [method _platform_in_cell] 量好存进去的：`half` 是外接框的半宽半高，
## `off` 是**外接框中心相对平台自身中心**的偏移（彩虹的圆心不在弧的中间，云是 0）。
## 这里不重算 —— 重算的话「生成时按哪个框塞进格子」和「约束时按哪个框判相交」
## 就会是两套算法，哪天对不上就是两块东西叠在一起。
static func half_height(p: Dictionary) -> float:
	return float(p["half"].y)


## 第 `(col, row)` 格里那一块平台；空格子返回 `{}`。
##
## ## 不相连靠的是「缩在格子里」
##
## 每块平台的外接框都缩在内缩过的格子（四边各让出 [constant EDGE_X] / [constant EDGE_Y]）
## 里面，而格子两两不相交 —— 于是任意两块的**外接框**不相交，比「图形不相交」
## 更强的结论。不需要拒绝采样，也不会出现「掷了一百次才放下一块」。
##
## 这一层只管格子：内外缩多少、这格有没有东西、是彩虹还是云。**尺寸和位置是
## [method _rainbow_in_box] / [method _cloud_in_box] 在格子里定的** ——
## 彩虹那边要为了「塞得下」把半径往下压，是那里的事。
static func _platform_in_cell(world_seed: int, col: int, row: int) -> Dictionary:
	var key := world_seed * 6043 + col * 907 + row * 181 + 13
	if _hash01(key) >= FILL:
		return {}
	var x0 := float(col) * CELL_W + EDGE_X
	var x1 := float(col + 1) * CELL_W - EDGE_X
	# 带子的上沿在 `-BAND`（往上为正的负方向），第 `row` 格往下走 `row` 个 ROW_H。
	var y0 := -BAND + float(row) * ROW_H + EDGE_Y
	var y1 := -BAND + float(row + 1) * ROW_H - EDGE_Y
	if _hash01(key + 1) < RAINBOW_SHARE:
		return _rainbow_in_box(key, Rect2(x0, y0, x1 - x0, y1 - y0))
	return _cloud_in_box(key, Rect2(x0, y0, x1 - x0, y1 - y0))


## 格子 `box`（已内缩）里的一段彩虹弧。
##
## ## 掷的是长度，半径是推出来的，塞不下就把半径压小
##
## 先掷**张角**和**弧长**，半径 `r = len / span`。张角小的时候这个半径很大
## （0.55 配 400 像素就是 727）—— 但那是**一段很缓的长弧**，外接框又长又扁，
## 照样装得进格子（见 [method arc_bounds]）。
##
## 「装得进」由**对分**保证：半径在 `[ARC_R_MIN, r]` 上二分成十次，取最大的那个
## 装得下的。外接框的尺寸随半径单调增，所以对分出来的就是真正贴边的那个值
## —— 比「按比例缩一次」准（外接框的厚度有 30 像素是常数，不跟着半径缩，
## 按比例缩一次会缩过头），也不会像拒绝采样那样掷出空格子。
##
## 半径压到地板还是装不下的话返回 `{}` —— 那格就空着。**按实测这是不会发生的**
## （地板半径 55、张角 2.3 的外接框才 165×165 上下，格子有 776×780），
## 留着是万一改了常量以后不至于悄悄叠在一起。
static func _rainbow_in_box(key: int, box: Rect2) -> Dictionary:
	var span := lerpf(ARC_SPAN_LO, ARC_SPAN_HI, _hash01(key + 3))
	var len := lerpf(ARC_LEN_LO, ARC_LEN_HI, _hash01(key + 2))
	# 朝向**完全随机**：用户明确要的「朝向各异、可倒扣，纯造景，
	# 能不能骑上去不管」。这里不做任何「往朝上的方向掰」的处理。
	var tilt := _hash01(key + 4) * TAU

	var fits := func(r: float) -> bool:
		var b := arc_bounds(r, span, tilt)
		return b.size.x <= box.size.x and b.size.y <= box.size.y

	var lo := ARC_R_MIN
	var hi := len / span
	if not fits.call(lo):
		return {}
	if fits.call(hi):
		lo = hi
	else:
		for _i in 10:
			var mid := (lo + hi) * 0.5
			if fits.call(mid):
				lo = mid
			else:
				hi = mid

	var b := arc_bounds(lo, span, tilt)
	# 圆心放在「外接框刚好落在格子里」的任意位置：留给它的活动余地就是格子减外接框。
	# 余地大就抖得开（小弧），余地小就基本钉在格子中间（大弧）—— 「散落」的观感来源。
	var slack := box.size - b.size
	var at := box.position - b.position + Vector2(
			slack.x * _hash01(key + 5), slack.y * _hash01(key + 6))
	return {
		"kind": PLATFORM_RAINBOW,
		"x": at.x, "dy": at.y,
		"r": lo, "span": span, "tilt": tilt, "len": lo * span,
		"off": b.position + b.size * 0.5,
		"half": b.size * 0.5,
	}


## 格子 `box` 里的一朵云：一块 `w × CLOUD_H` 的板转 [constant CLOUD_TILT] 以内的角。
##
## 云的尺寸是**反过来算**的：先掷宽度，外接框是转出来的
## （`w·|cos a| + CLOUD_H·|sin a|` 宽、`w·|sin a| + CLOUD_H·|cos a|` 高），
## 再拿外接框在格子里定位。宽度上限 800 配 22°，外接框 384×322，
## 格子 776×780 装得下（横向余量最小，才 8 像素），所以这里不需要彩虹那套对分
## —— 但那 8 像素是**算出来的、不是留出来的**，改 [constant CLOUD_W_HI] 之前
## 先把 `(w·cos a + 34·sin a)/2 ≤ 388` 重算一遍。
static func _cloud_in_box(key: int, box: Rect2) -> Dictionary:
	var w := lerpf(CLOUD_W_LO, CLOUD_W_HI, _hash01(key + 2))
	var tilt := lerpf(-CLOUD_TILT, CLOUD_TILT, _hash01(key + 7))
	var a: float = absf(tilt)
	var half := Vector2(
			(w * cos(a) + CLOUD_H * sin(a)) * 0.5,
			(w * sin(a) + CLOUD_H * cos(a)) * 0.5)
	if half.x * 2.0 > box.size.x or half.y * 2.0 > box.size.y:
		return {}
	var slack := box.size - half * 2.0
	var at := box.position + half + Vector2(
			slack.x * _hash01(key + 5), slack.y * _hash01(key + 6))
	return {
		"kind": PLATFORM_CLOUD,
		"x": at.x, "dy": at.y,
		"w": w, "tilt": tilt,
		"off": Vector2.ZERO,
		"half": half,
	}


## 形状地图第 `index` 块屋顶那栋房子自己的骰子：**几段钢梯、每段分多高、中间几段
## 平路各多长**。返回的都是**没折算过的权重**，像素长度由地形按这栋房子实际爬多高、
## 跨多宽算出来（见 [method HillTerrain.roof_profile]）。
##
## 为什么不在这里直接给像素：这几个数**互相挤**。爬升要按段数分，段与段之间还要
## 留平路，最后一段平路是「余量」—— 分到地形那边去算，末段一减就对得上，
## 屋顶右沿正好落在缝的左沿上，一像素不差。在这儿先算的话，浮点一凑就会出现
## 「屋顶比缝早结束半像素」的多边形裂缝。
##
## 纯函数：区块会滚出视野再重建，同一栋房子必须每次长得一模一样。
static func roof_dice(world_seed: int, index: int) -> Dictionary:
	var key := world_seed * 7717 + index * 331 + 91
	var n := 1 + int(_hash01(key) * float(LADDER_MAX))
	var rises: Array[float] = []
	var sects: Array[float] = []
	# 权重都在 0.35～1.35 之间：完全不等的分配（0～1）会经常分出一段只有几个像素
	# 高的梯子，看着像没画完。**每个元素一个错开的键**，不然三段的权重会一模一样。
	for k in LADDER_MAX:
		rises.append(0.35 + _hash01(key + 11 + k * 7))
		sects.append(0.35 + _hash01(key + 101 + k * 13))
	return {"ladders": clampi(n, 1, LADDER_MAX), "rises": rises, "sects": sects}


## 第 `index` 块区块**末尾那条缝**的落差（像素，[constant DROP_LO]～[constant DROP_HI]）。
##
## 缝的右沿比左沿低这么多。**只有屋顶图用**，而且这个数被用在三处，必须是同一个：
## 挖缝的（[method HillTerrain._carve]）、算下一栋房子起点高度的
## （[method HillTerrain.roof_profile]）、测试里量落差的。
static func drop_at(world_seed: int, index: int) -> float:
	return lerpf(DROP_LO, DROP_HI, _hash01(world_seed * 6151 + index * 733 + 17))


## 第 `index` 栋房子上有没有烟囱，有的话长什么样。返回 `{}` 表示没有。
##
## 有的话给三样：
##  · `section` —— 摆在本栋**中间那几级平屋面**里的第几级（0 起，多了取模）
##  · `at`      —— 落在那一级的哪个位置（0 是左沿、1 是右沿，只取中间一段）
##  · `w`/`h`   —— 烟囱的宽和高（像素）
##
## **这里不给世界坐标**，只给骰子：烟囱具体摆在哪儿要问剖面
## （[method HillTerrain.roof_profile]）—— 平段有多宽、落在哪儿，是地形那边按
## 爬升和段数分出来的，maps.gd 一份都算不出来。两头对齐靠
## [method HillChimneys.chimney_rect]：剖面 + 这几颗骰子 → 世界坐标，**两处共用它**。
##
## 「中间那几级」是**避开落点和跳台**：落点是车砸下来的地方、跳台是唯一能把速度
## 捡回来的地方，在这两处放一柱向上的烟，等于白送一个「跳过去更容易」的buff，
## 而缝宽是按没有烟的时候标定的（见 [constant GAP_MAX]）。
##
## 纯函数：区块会滚出视野再重建，同一栋房子上的烟囱必须每次都在同一处。
static func chimney_at(world_seed: int, index: int) -> Dictionary:
	if index < SHAPE_START_CELL:
		return {}
	var key := world_seed * 5279 + index * 269 + 61
	if _hash01(key) >= CHIMNEY_CHANCE:
		return {}
	return {
		"section": int(_hash01(key + 7) * 3.0),
		"at": lerpf(0.3, 0.7, _hash01(key + 13)),
		"w": lerpf(CHIMNEY_W_LO, CHIMNEY_W_HI, _hash01(key + 19)),
		"h": lerpf(CHIMNEY_H_LO, CHIMNEY_H_HI, _hash01(key + 23)),
	}


## 这张图是不是「黑夜」：一进关卡就要盖一块挡布（见 scripts/night.gd）。
static func is_night(map_id: String) -> bool:
	return bool(get_map(map_id).get("night", false))


## 选图卡片上那行「招牌」文案。
##
## 默认取本图特殊地形的那一条（[constant FEATURE_INFO]），形状地图没有特殊地形，
## 就自己带一条 `gimmick` —— 不然十二张卡里有三张写着「标准地形」，
## 玩家看不出它们的区别在哪。
static func gimmick_of(map_id: String) -> Dictionary:
	var m := get_map(map_id)
	if m.has("gimmick"):
		return m["gimmick"]
	var feature: String = m["feature"]
	if FEATURE_INFO.has(feature):
		return FEATURE_INFO[feature]
	return FEATURE_INFO[FEATURE_NONE]


## 该地图的地形噪声频率和八度数。表里没写的都退回这两个默认值 ——
## **默认值必须和加新图之前 [HillTerrain._configure_noise] 里写死的那两个数一模一样**，
## 否则八张老图的地形会跟着这次改动一起变。
static func noise_freq(map_id: String) -> float:
	return float(get_map(map_id).get("noise_freq", 0.0013))


static func noise_octaves(map_id: String) -> int:
	return int(get_map(map_id).get("noise_octaves", 3))


## 这张图的重力倍率。只有月球不是 1.0。
##
## **不是全局改 `Physics2D` 的重力**：那是引擎级设置，改完整个进程里所有刚体
## （包括下一个场景、测试里临时搭的车）都跟着变，而地图是「这一局」的事。
## 由 [method HillCar.apply_map] 挨个写进三个刚体的 `gravity_scale`。
static func gravity_scale(map_id: String) -> float:
	return get_map(map_id)["gravity_scale"]


## 这种特殊地形会不会**动地表**（挖坑或者垫平）。
##
## 挖坑的（吊桥 / 冰湖 / 火山口 / 环形山）要看两端垫得对不对；不动的（沙尘暴 /
## 碎石路 / 隧道 / 森林）摆位各有一套自己的规矩。测试里那些「扫两端」的检查靠
## 这一个函数分流，省得每加一种地形就得回去补一次白名单。
##
## 判据是**表里的数**，不是种类名：以后新加的地形只要填了 `depth` 或 `level`
## 就自动进那套检查，漏填就自动不进。
static func digs(kind: String) -> bool:
	var layout := feature_layout(kind)
	return float(layout["depth"]) > 0.0 or float(layout.get("level", 0.0)) > 0.0


## 整数 → [0, 1) 的确定性哈希。和 [HillBackground] 里那个是同一套位运算，
## 这里要能跨场景用，所以单独放一份。
static func _hash01(n: int) -> float:
	var h := (n * 374761393 + 668265263) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h) / 2147483648.0
