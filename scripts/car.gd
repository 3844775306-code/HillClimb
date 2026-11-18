extends Node2D
class_name HillCar
## 登山赛车本体。
##
## 结构：车身和两个轮子是三个独立的 [RigidBody2D]，靠两个 [PinJoint2D] 铰接在
## 一起。驱动方式是给轮子施加力矩，让摩擦力把车推出去 —— 所以轮子会打滑、车身
## 在斜坡上会后仰、轮子会打滑，这些都是物理自然涌现的。
##
## **腾空时的姿态是唯一一处明写的控制**：两个轮子都离地之后，按前进把车往逆时针
## 拧、按倒退往顺时针拧（见 [method _apply_air_control]）。不写不行 —— 光靠轮子的
## 反作用力矩，腾空时车几乎不转，飞出去就只能听天由命，落点没得挑。

## 死因代码，交给 HUD 翻译成对应语言的文案。
const REASON_CRASH := "crash"
const REASON_FUEL := "fuel"
## 掉进冰湖。
const REASON_DROWN := "drown"
## 掉进火山口。
const REASON_BURN := "burn"
## 掉下吊桥。
const REASON_FALL := "fall"
## 车手撞到隧道洞顶。
const REASON_CEILING := "ceiling"

## 「洞顶」那一层石头的分组。隧道洞顶（连同倒挂的钟乳石）整块进这个组，
## 车手的头碰到就判 [constant REASON_CEILING]，见 [method _on_head_body_entered]。
##
## **和 `"ground"` 分开**：地面是「车手栽下去了 = 翻车」，洞顶是「车手扎进石头里
## 了 = 撞顶」，两句话不一样，所以不能共用一个组。
const CEILING_GROUP := "ceiling"

## 轮子刚体的分组标记。**定义在 [Vehicles] 里**（那是依赖链的根，理由写在那边），
## 这里只是引过来 —— 两边各写一份字面量的话，改了一处就会静默认不出轮子。
##
## 漏打了这个标记的车：[member wheels] 是空的，`rear_wheel` / `front_wheel` 跟着是
## null，于是马达不转、摩擦不改、惯量倍率不生效 —— 全是静默的，车只是「开着不对」。
const WHEEL_GROUP := Vehicles.WHEEL_GROUP

## 腾空多久算一节奖励。**所有档共用一个节拍**：档位换的是「这一节值多少」，
## 不是「多久发一次」—— 不然 6 秒之后会变成每 1.5 秒发一大笔，玩家感觉不到
## 「越来越值钱」，只会觉得飘字变得忽快忽慢。
const AIR_BONUS_INTERVAL := 0.5
## 腾空多久**才开始**算奖励（秒）。**必须等于 [constant AIR_BONUS_TIERS] 里第一档
## 那个秒数** —— 两处写成一个数是为了让下面这个短名字能用；tests/air 里有一条
## 断言钉着两者相等，改一处忘了另一处会被抓住。
##
## 少了这一条起奖线，小颠一下就白送钱：地形本来就坑坑洼洼，两个轮子同时离地
## 零点几秒是常事，按 [constant AIR_BONUS_INTERVAL] = 0.5 从 0 起算的话，一路
## 小跳着开也能一直捡钱 —— 而这条奖励的本意是「真的飞起来了」。
const AIR_BONUS_DELAY := 2.5
## 腾空奖励的档位表：`[起算秒数, 这一节多少金币]`，**按秒数从小到大**。
##
## 用户原话：「腾空时间超过 2.5 秒后每 0.5 秒 50 金币，超过 4 秒后每 0.5 秒 100
## 金币，超过 6 秒后每 0.5 秒 200 金币」。
##
## 落在一节上的金额是**这一节开始那一刻已经跨过的最高一档**（见
## [method air_bonus_coins]）：2.5 秒那一节起每 0.5 秒发一次，到 4 秒换成 100，
## 到 6 秒换成 200，8 秒（[constant AIR_BONUS_STOP]）之后彻底停发。
##
## 一趟飞满 8 秒是 3×50 + 4×100 + 4×200 = **1350 块**，比一个空翻（300）还多 ——
## 这是故意的：2.5 秒以上的滞空在真地形上极难凑，凑到了就该比转圈值钱。
const AIR_BONUS_TIERS: Array = [[2.5, 50], [4.0, 100], [6.0, 200]]
## 腾空超过这么多秒（含）之后**一分钱都不再发**。
##
## 用户说的是「超过 8 秒后不再奖励金币」。**不封顶的话这条奖励会变成「谁卡在
## 天上谁赢」**：真地形上 8 秒以上的滞空基本只出现在车被卡住、或者掉出地形这种
## 意外里，那时候每一节 200 块可以无限刷下去，而正常跑图根本拿不到。
const AIR_BONUS_STOP := 8.0
## 空中转满几圈算一次空翻。
const FLIP_TURNS := 1.0
## 每次空翻奖励多少金币。
const FLIP_BONUS_COINS := 300
## 独轮行驶多久算一节奖励。
##
## **这个数还没有实机标定过。** 2 秒是照「油门到底能把车头抬多久」的直觉定的，
## 和空翻那条「转满一圈」是同一个量级的手感门槛。四辆车抬头的难易差得很远
## （越野车沉、摩托轻），真上线之前该拿 `tests/vehicles_drive` 那类实机跑一趟，
## 看看谁随便就是一次、谁永远够不着，再回来改这个数。
const WHEELIE_TIME := 2.0
## 每次独轮奖励多少金币。
const WHEELIE_BONUS_COINS := 75

## 防护罩复活前，往下探地面用的射线长度（像素）。
##
## 两头都放得很宽，是为了容下四张图里最极端的起伏：默认振幅上限 140，噪声再
## 乘 1.6，再加上挖坑的深度 —— 死亡点上下 1400 以内必定有地面。射线**起点在
## 上方 1400**（不是从车里往外打），所以哪怕落点在坑底、在山上，都是同一条射线管。
const GROUND_SCAN := 1400.0
## 「实心地面」所在的物理层。
##
## 地形、隧道、吊桥桥面、石头、树、冰面都是 layer 2（[HillTerrain]、[HillTunnel]
## 等），layer 0 留给感应区和危险区（[HillHazardZone]、[HillSandstorm]）。所以这条
## 射线问的是「哪儿能站」，而不是「哪儿是地形」—— 隧道和吊桥是另外的刚体，
## 但它们确实能站人，车落在上面是对的。
const GROUND_LAYER := 2

signal crashed(reason: String)
## 腾空满一节。由关卡去发钱 —— 车只管物理，不管货币。
signal air_bonus(coins: int)
## 空中转满一圈。`back` 为真表示后空翻（车头朝上往后翻），假表示前空翻。
##
## 和 [signal air_bonus] 一样只管报数，钱由关卡发。
signal flip_bonus(coins: int, back: bool)
## 独轮行驶满一节。`rear` 为真表示后轮独自着地（车头抬起来）。
##
## 和另外三个一样只管报数，钱由关卡发。
signal wheelie_bonus(coins: int, rear: bool)
## 用掉了一件道具（见 [member Items.IDS]）。
##
## 和上面三个信号一样只管报数，飘字和音效由关卡/HUD 去做 —— 车只管物理，
## 不管界面。
signal item_used(id: String)

@export_group("马达")
## 轮子的目标角速度（弧度/秒）。正数向右开。
@export var max_wheel_speed := 50.0
## 力矩系数：与「目标转速 - 当前转速」的差值相乘得到力矩。
##
## 静止时单轮推力 = max_wheel_speed * motor_strength / 轮半径(21)，
## 两轮合计约 1.0 倍自重 —— 刚好够爬上 50° 左右的陡坡，
## 又低于约 1.45 倍自重才会发生的后仰翻车线。调大爬坡更猛但容易翘头。
@export var motor_strength := 60000.0
## 力矩上限。正常行驶不会触及（静止时仅 30 * 60000 = 1800000），
## 只在被顶住反转等极端情况下兜底。
@export var max_torque := 2000000.0
## 松开油门时保留的力矩系数（发动机制动）。调小则滑行更远。
@export var coast_strength_scale := 0.05

@export_group("惯性")
## 转动惯量倍率。1.0 = Godot 按碰撞形状自动算出来的值（车壳 321403、单轮 4851）。
## 三个刚体一起放大。
##
## 这是「车有多沉」的手感旋钮：调大之后碾过碎石和鼓包时，轮子不会被地形顶得
## 弹起来，而是贴着地面滚过去，车身俯仰摆动变小、也更保速；代价是爬坡略慢。
## 实测（tests/inertia.tscn）：
##
##   倍率   搓板路出速   俯仰标准差   40°稳态爬坡   45°稳态爬坡
##   1.0      254         2.53°       237 px/s      193 px/s
##   2.0      348         2.50°       212 px/s      190 px/s   ← 默认
##   4.0      329         2.15°       193 px/s      165 px/s
##
## 2.0 是收益/代价的拐点：搓板路提速明显，爬坡只掉 11%（40° 上仍有 212 px/s，
## 远没到爬不动的程度）。4.0 开始伤爬坡。想要极限爬坡就调回 1.0。
##
## 值得记一笔：单个车壳的惯量对俯仰几乎没影响，真正起作用的是**轮子**的惯量
## —— 试过只放大车壳，搓板路各项指标纹丝不动（2.53→2.79→2.44，都在噪声里）。
## 所以这个倍率是三个刚体一起乘的，别只调车壳。
##
## 为什么调的是【转动】惯量而不是质量：把质量统一放大 k 倍、同时把力矩也放大
## k 倍，运动方程两边同乘 k，加速度分毫不变 —— 纯质量缩放是个恒等式，玩家
## 感觉不到任何差别。而只加质量不加力矩会直接压低推重比，把好不容易调出来的
## 爬坡能力毁掉（见「马达」一组的注释）。转动惯量没有这个问题：它只改变转动
## 的难易，不碰推重比，所以爬坡只受「轮子提速变慢」这一个间接影响。
@export var inertia_scale := 2.0

@export_group("空中姿态")
## 腾空时按前进/倒退，把车拧转多快。单位是**角加速度**（弧度/秒²）。
##
## 方向照《登山赛车》的手感：**前进 = 逆时针**（车头抬起来，往后来一个后空翻），
## **倒退 = 顺时针**（车头扎下去，前空翻）。两个方向都得有 —— 只有一个方向的话，
## 飞起来就只能往一边翻，落点没得挑。
##
## 为什么单位是角加速度、不是力矩：真正施加的力矩 = 这一项 × 车壳的转动惯量。
## 四辆车的车壳惯量差着十几倍（9 万 ~ 145 万），写死一个力矩数会让巴士几乎拧不动、
## 摩托一碰就转三圈。乘上惯量之后**四辆车差到 20% 以内**（实测见
## `tests/air_control`：巴士 280°、越野 256°、赛车 240°、摩托 205°，都是 1 秒）。
## 剩下的那 20% 拉不平 —— 两个轮子被 [PinJoint2D] 拴在车壳上一起转，它们拖的
## 那一坨和车壳惯量无关，壳越轻被拖得越狠。
##
## 同理，升级「敏捷」改的是惯量（见 [method Upgrades.apply]），乘上去之后空中
## 姿态不会因为练了敏捷反而变笨 —— 出力跟着惯量一起涨。和 `inertia_scale`
## 也是同一个道理：那个倍率乘在三个刚体上，乘多少这里都跟着。
##
## 角速度不会无限涨：引擎默认 `angular_damp = 1.0` 一直在削，稳态角速度就是
## 这一项自己（14 rad/s = 800°/s），前 1 秒按 `θ = air_spin × (t − 1 + e^-t)`
## 爬升，实测转过 256°，**一次 1.2 秒的跳跃正好够翻一整圈**。
##
## **刻意不写进各车的 `.tscn`。** 别处都是「每辆车自己一个值」，这一项正好相反：
## 它是四辆车必须一样的那一项，多开四个旋钮就一定会漂开，一漂就有一半车翻不了身。
@export var air_spin := 14.0

@export_group("自平衡")
## 陀螺仪回正角加速度的**上限**（弧度/秒²）。**0 = 关**，只有独轮车打开。
##
## 独轮车只有一个轮子，车身铰接在轮心上，重心必定在接地点上方 —— 纯物理下它
## 开场就倒。这一项模拟真·电动独轮车那套陀螺仪：着地时按倾角把车壳往直立方向拧。
##
## 和 [member air_spin] 一样乘**车壳当前的转动惯量**，所以换车、练敏捷都不会
## 让回正忽强忽弱。
##
## **这个数是「能救回多大倾角」的旋钮，不是「会不会倒」的开关。** 见
## [method _apply_balance] 里为什么必须封顶：不封顶的话倒得越狠回正越猛，
## 结果是永远不倒。真要调手感就拖这个数，`tests/balance` 会打出对应的极限倾角。
@export var balance_torque := 0.0
## 回正力矩爬满的倾角（弧度）。这个角度以内线性回正，再往外力矩封顶、不再增加，
## 于是重力倾覆（∝ sin θ）早晚会赢 —— 车照样翻。
##
## **这个数是「陀螺仪有多硬」。** [member balance_assist] 只抵得掉给油那一下的
## 绝大部分，残差还在（实测约 8.8 万）—— 而陀螺仪对**恒定**力矩的等效刚度只有
## `斜率 − m·g·d`（重力是正反馈，吃掉一大半），斜率 = `balance_torque × 惯量 ÷ 本值`。
## 于是常驻倾角 = 残差 ÷ (斜率 − m·g·d)。独轮车取 0.18（≈10°）：斜率从
## 184 万/弧度涨到 512 万，剩下的 263,294/弧度 变成 456 万，同一个残差的偏移量
## 从 19° 压到 3° —— 而那 3° 是**前倾**，正好是真独轮车加速时的样子。
##
## **它不影响极限倾角。** 极限倾角是「最大回正力矩 = m·g·d·sin θ」解出来的，两边
## 都封顶在 [member balance_torque] × 惯量上，和本值无关（独轮车 35.7°）。
## `tests/balance` 的扰动表量的是这一个，`满油门 2 秒` 量的才是本值。
@export var balance_full_angle := 0.5
## 阻尼项：车身角速度的多少倍反向抵消。调大压摆、调小更「活」。
@export var balance_damping := 0.6
## 马达反作用力的**预判补偿**：陀螺仪提前把马达自己造出来的抬头力矩抵掉，
## 等于真车手「先往前压、再拧油门」。**1.0 = 按算出来的物理量全额补**。
## 0 = 关，其余车辆分毫不变。
##
## **为什么光靠上面那条反馈不行。** 给油那一瞬间，轮子把地面往后蹬、地面把轮子
## 往前推，销子再把这个力拽到车壳上。力作用在**轮心**，而车壳重心在轮心上方 `d`
## 处，于是冒出一个实打实的抬头力矩 `d · P`。反馈回路得**先看到**倾角才出力，
## 等它反应过来车已经仰起来了 —— 而独轮车只有这一个支点，一仰就是翻。
##
## 补偿量要乘两样东西：力臂 `d`（见 [method _pin_lever]）和反作用力
## `P = τ/r × share`（share 见 [method _reaction_share]）。
##
## **补过头比补不够更麻烦。** 差出来的那点力矩会变成一个**恒定的**倾角偏移：
## 陀螺仪对恒定力矩的等效刚度只有 `斜率 − m·g·d`（重力是正反馈，吃掉一大半），
## 独轮车那套数下只剩 263,294/弧度 —— 残差 5 万就是 11° 的常驻倾角，再颠一下就
## 越过极限倾角翻了。所以下面 [member balance_full_angle] 不能给太大。
##
## 这是**前馈**，不是「更强的陀螺仪」：它只抵马达造出来的那部分，
## 和重力的倾覆力矩毫无关系。所以 [member balance_torque] 该多小还是多小、
## 极限倾角该是多少还是多少 —— `tests/balance` 两头都量。
@export var balance_assist := 0.0

@export_group("起飞")
## 同时按住前进和倒退就点火。**只有登月车打开。**
## 关闭时下面四个数一个都不生效，其余车辆完全不受影响。
@export var hover_enabled := false
## 上推力 = **本地自重** × 这个数。> 1 才离得开地。
##
## 「本地自重」要乘地图的重力倍率（[member RigidBody2D.gravity_scale]，月球 0.35）
## —— 见 [method _hover_weight]。不乘的话月球上 1.9 倍自重会变成 5.4 倍，直接窜出去。
@export var hover_lift := 1.9
## 前进推力 = 本地自重 × 这个数。
@export var hover_push := 0.8
## 起飞时的前进速度上限（px/s）。**0 = 自动取「轮速 × 轮半径」**，也就是
## [method Vehicles.stats] 里那个 `top_speed`。
##
## 取自动值而不是写死一个数：「前进速度和正常行驶一样」这条要在**升级极速之后
## 依然成立**，而升级改的正是 `max_wheel_speed`。写死的话练过极速的车一飞就掉速。
@export var hover_speed := 0.0
## 起飞时的油耗倍率。
@export var hover_fuel_scale := 3.0

@export_group("燃油")
@export var fuel_max := 100.0
@export var fuel_idle_drain := 1.6
@export var fuel_throttle_drain := 4.4
## 油耗倍率，由地图决定（火山是 1.6）。**它乘在消耗速率上，不改上面两个常量**
## —— 上面两个是调出来的手感基准，改它们等于把所有地图的基准一起改了。
var fuel_drain_scale := 1.0

## 车灯开着时**额外**的耗油速度（每秒）。
##
## 用户原话是「耗油速度是前进速度的 0.5 倍」，**没有照字面做**：车速表上的数是
## 米/秒换算成的 km/h（见 [method HillDashboard.speed_kmh_of]），字面乘 0.5 会让
## 满油 100 的油箱一秒见底 —— 那不叫费油，那叫开灯就死。所以改成
## 「油门耗油的一半」：[member fuel_throttle_drain] 4.4 的一半 = 2.2，
## 满油开灯能撑约 15 秒（不开灯空转 1.6、约 62 秒；全油门 4.4、约 23 秒）。
##
## 和另外两条一样要乘 [member fuel_drain_scale]：火山图（1.6 倍）上开灯更费。
const HEADLIGHT_DRAIN := 2.2
## 车灯开关的动作名。绑定见 project.godot（空格 / 手柄 B）。
const HEADLIGHT_ACTION := "headlights"

@onready var chassis: RigidBody2D = $Chassis

## 车上所有的轮子，**按场景里的次序（后 → 前）**。两轮车是两个，独轮车是一个。
##
## 靠 [constant WHEEL_GROUP] 这个标记收，而不是写死节点名：独轮车只有一个轮子，
## `$RearWheel` / `$FrontWheel` 那种写死两个名字的写法在它身上直接是 null。
##
## **凡是要遍历全车轮子的地方一律走这一份**（马达、摩擦、惯量、扶正、腾空判据）。
## 拿下面那两个别名去遍历的话，独轮车会被算两遍 —— 质量翻倍、碎屑翻倍，
## 而且都不会报错，只是不对。
@onready var wheels: Array[RigidBody2D] = _collect_wheels()

## 后轮 / 前轮。**独轮车上两个指向同一个轮子**（它只有一个）。
##
## 留着是因为二十来个测试和 effects / trees / hazards / dashboard 都在用这两个名字
## 取「一个轮子看看」。别名让它们原样能用，不用一次改二十个文件。
## 但它们**只适合「取一个轮子」的场合**，遍历请用 [member wheels]（见上）。
@onready var rear_wheel: RigidBody2D = wheels[0] if not wheels.is_empty() else null
@onready var front_wheel: RigidBody2D = wheels[-1] if not wheels.is_empty() else null
@onready var head: Area2D = $Chassis/Head

## 当前油门，-1（倒车）到 1（前进）。
var throttle := 0.0
var fuel := 100.0
## 车灯开着吗。**只有黑夜图开得起来**（见 [method headlights_available]）：
## 锥形亮区是 [HillNight] 在那块挡布上挖出来的洞，别的图根本没有挡布，
## 开了也只是白烧油。
var headlights_on := false
var alive := true
var engine_on := true
## 这一帧在喷起飞推力吗（登月车）。**由 [method _read_throttle] 每帧重算**，
## 松开任意一个键、没油、熄火，三件事都会让它变回 false。
var hovering := false
## 本次跑到过的最远 x 坐标，用于计分。
var max_distance := 0.0
## 本局用的地图 id，[method apply_map] 设。
var map_id := Maps.PLAINS
## 两个轮子是不是都没碰到地面。
var grounded := true
## 本次连续腾空时长（秒）。着地立刻清零。
var air_time := 0.0
## 这一趟腾空里车身累计转过的角度（弧度）。**带正负**：Godot 2D 的 y 轴朝下，
## 所以正角度在屏幕上是顺时针 —— 车头（局部 +x）往下扎，就是前空翻。
## 也就是说 `> 0` 前空翻、`< 0` 后空翻。着地清零。
var flip_angle := 0.0
## 上一帧车身的角度，用来累计跨过 ±π 的转动。
var _last_rotation := 0.0
## 这一趟独轮已经持续多久（秒）。两个轮子**同时**着地或**同时**离地就清零。
var wheelie_time := 0.0
## 这一帧马达**实际**加在所有轮子上的力矩之和（不是需求值，是 clamp 之后真正的
## 那个数）。[method _apply_motor] 写，[method _apply_balance] 的前馈项读 —— 所以
## 它必须排在前面跑。记需求值的话，马达被上限削掉的那一截会被当成真加上了，
## 预判项凭空多出一块。
var _motor_torque := 0.0
## 轮子材质的原始摩擦系数。第一次 [method apply_map] 时从场景里读出来，
## 之后所有地图都是「原始值 × 倍率」—— 不在这里抄一份 car.tscn 的数字，
## 否则编辑器里调了摩擦、这里悄悄用过期的值。
var _base_wheel_friction := -1.0
## 地图给的摩擦倍率（雪地 0.12）。[method apply_map] 设。
var _map_friction_scale := 1.0
## **脚下这一小段路**的抓地倍率，和地图倍率相乘。
##
## 存在的理由：地图倍率是整张图恒定的（雪地全程滑），而冰湖这种「同一张图上
## 只有某几十米特别滑」的地形需要临时再压一层。写成赋值函数是为了让漏掉恢复
## 的危险降到最低 —— 只要有人写 `car.surface_grip = x`，轮子摩擦立刻跟着变。
##
## **它不能改成「把地面材质的 friction 调小」。** 实测（tests/surface_probe）：
## 车胎是 rough = true，此时地面那侧无论有没有材质、friction 是 0.06 还是 0.7，
## 结果逐位相同（车速 813、轮面 813、打滑 1.00×、2 秒 1134 像素）。地面材质
## 完全被忽略，唯一能改抓地力的地方就是轮子自己的材质。
var surface_grip := 1.0:
	set(value):
		if is_equal_approx(surface_grip, value):
			return
		surface_grip = value
		_apply_wheel_friction()
## 出生时车是悬空的（要往下掉一下才落地），落地之前不给腾空奖励，
## 否则每次重开都白送 25 块。
var _has_landed := false

## 氮气还剩多少秒。> 0 就是在喷。
var nitro_time := 0.0
## 防护罩的免死窗口还剩多少秒。见 [method _on_head_body_entered]。
var shield_grace := 0.0


func _ready() -> void:
	# 必须在 fuel = fuel_max 之前：升级会改 fuel_max，先加满再改等于白升。
	#
	# 拿的是**当前选中那辆车**的等级表：这台车就是照着 `selected_vehicle` 造出来的
	# （换车在 [method HillGame._enter_tree] 里，就在 add_child 那一刻），两者必然一致。
	# 升级现在是按车分开的，拿错表就等于把别的车的改装装到这辆上。
	Upgrades.apply(self, SaveData.current_levels())
	fuel = fuel_max
	max_distance = chassis.global_position.x
	# 起始角度得记下来，否则第一帧会凭空多算一个「从 0 转到现在」的增量。
	_last_rotation = chassis.rotation
	head.body_entered.connect(_on_head_body_entered)
	_apply_inertia_scale()


## 套用地图的物理修正。地形之外，地图对车的影响全在这一个函数里。
##
## 平原那一行是恒等变换（摩擦 ×1、阻尼 0、油耗 ×1），所以默认地图的手感和
## 加地图之前一模一样。
##
## **车不自己去读存档里选了哪张图**，由关卡在 `_ready()` 里调这个函数。这样单独
## 实例化一辆车跑测试时不会因为玩家存档里选了雪地就悄悄变滑 —— 默认永远是平原。
func apply_map(id: String) -> void:
	map_id = id
	var m := Maps.get_map(id)

	_map_friction_scale = float(m["friction_scale"])
	_apply_wheel_friction()

	for body in bodies():
		body.linear_damp = m["drag"]
		# 重力也是每张图一个（月球 0.35）。写进刚体自己的 gravity_scale，
		# **不动项目的重力设置**：那是所有场景共用的，改了会把车库、测试里
		# 那些单独实例化的东西一起改掉。重开一局时 [method apply_map] 会按存档
		# 选的那张图重新写一遍，所以月球跑完回平原不会留着低重力。
		#
		# 只影响重力加速度，碰不到扭矩/惯量那两套（[member inertia_scale] 是按
		# 碰撞形状算的），所以车的手感参数不用跟着重调。
		body.gravity_scale = float(m["gravity_scale"])

	fuel_drain_scale = m["fuel_scale"]


## 把「原始摩擦 × 地图倍率 × 表面倍率」写进两个轮子。
##
## **必须 duplicate()。** 轮子的物理材质是 car.tscn 里的 sub-resource，
## 同一个场景的所有实例共用同一个 Resource 对象 —— 直接改它的 friction，
## 雪地会把同进程里别的车一起改滑，而且重开一局还留着上一局的值。
## 每次都重新 duplicate 一次，所以两个轮子不会互相串。
func _apply_wheel_friction() -> void:
	var scale := _map_friction_scale * surface_grip
	for wheel in wheels:
		var mat: PhysicsMaterial = wheel.physics_material_override
		if mat == null:
			continue
		mat = mat.duplicate()
		if _base_wheel_friction < 0.0:
			_base_wheel_friction = mat.friction
		mat.friction = _base_wheel_friction * scale
		wheel.physics_material_override = mat


## 对外统一的死亡入口，给特殊地形用（冰湖、火山口、吊桥底下）。
func die(reason: String) -> void:
	_die(reason)


## 把三个刚体的转动惯量按 inertia_scale 放大。
##
## Godot 在 [member RigidBody2D.inertia] 保持 0 时按碰撞形状自动算惯量，
## 所以「读出来 × 倍率 再写回去」就等于手动指定。两个坑：
##
## 1. 必须用 [method PhysicsServer2D.body_get_param]，不能读 RigidBody2D.inertia
##    —— 后者在自动模式下恒为 0，那是「自动」这个状态的哨兵值，不是算出来的惯量。
## 2. 物理服务器要等到**第 2 个物理帧**才把形状换算成惯量，在那之前读回来是 0。
##    所以这里得等上两帧再读，不能直接在 _ready() 里同步读，否则倍率会静默失效
##    （读到 0、乘完还是 0，看上去一切正常，实际什么都没改）。
##
## 代价是前两个物理帧车身仍用自动惯量，33 毫秒，感觉不到。
##
## 那两帧的窗口里车可能已经被 queue_free() 了（重开关卡就会），所以下面有
## is_inside_tree() 兜底。实测（0/1/2 帧后 free）Godot 4 本身也会在实例被释放后
## 安全丢弃这个协程，不会打出「previously freed instance」，兜底只是双保险。
func _apply_inertia_scale() -> void:
	if is_equal_approx(inertia_scale, 1.0):
		return
	for i in range(10):
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		if _auto_inertia(chassis) > 0.0:
			break
	for body in bodies():
		var auto_inertia := _auto_inertia(body)
		if auto_inertia > 0.0:
			body.inertia = auto_inertia * inertia_scale


func _auto_inertia(body: RigidBody2D) -> float:
	return PhysicsServer2D.body_get_param(body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)


## 收 [member wheels]：直接子节点里带 [constant WHEEL_GROUP] 标记的 [RigidBody2D]，
## **按节点次序**（场景里后轮写在前面，所以结果就是后 → 前）。
##
## 判据本身在 [method Vehicles.wheels_of] 里，这里只是转一手 —— 选车卡片画的轮子和
## 坦克画履带用的轮子都要同一份答案，各写一份迟早漂开。
##
## 那边用「自己的直接子节点」而不是 `get_tree().get_nodes_in_group()`：后者会把
## 同一个世界里别的车的轮子一起收进来，而测试里经常同时摆着好几辆车。多转的这一手
## 还顺带让 [member wheels] 在**没进树**的实例上也可用（`@onready` 在 `_ready`
## 之前求值，而 `get_children()` 和分组标记都和树无关）。
func _collect_wheels() -> Array[RigidBody2D]:
	return Vehicles.wheels_of(self)


## 整车的所有刚体：车壳 + 每个轮子**各一次**。凡是「整车一起动」的地方都走这里
## （地图阻尼/重力、惯量倍率、扶正、复活挪位、找最低点）。
##
## 独轮车在这里自动只有两个刚体。**这就是不能拿 `rear_wheel` / `front_wheel`
## 遍历的原因**：那一对在独轮车上指向同一个轮子，写 `[chassis, rear, front]`
## 会让它出现两次。
func bodies() -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = [chassis]
	out.append_array(wheels)
	return out


func _physics_process(delta: float) -> void:
	if not alive:
		return
	# 道具要排在 _apply_motor 前面：这一帧按下的氮气，这一帧就该有劲。
	_update_items(delta)
	# 车灯排在 _burn_fuel 前面：这一帧按亮的灯，这一帧就开始费油。
	_update_headlights()
	_read_throttle()
	_apply_motor()
	_apply_hover()
	_burn_fuel(delta)
	_update_airborne(delta)
	# 必须排在 _update_airborne 后面：它是对不对得看 `grounded`，而 `grounded`
	# 是上面那一行刚算出来的。排在 _apply_motor 旁边就会用上一帧的触地状态，
	# 起跳那一帧会在地面上多拧一下。
	_apply_air_control()
	# 同理也排在 `_update_airborne` 后面：自平衡只在着地时出力。
	_apply_balance()
	max_distance = maxf(max_distance, chassis.global_position.x)


## 读这一帧的油门，顺带判起飞手势。
##
## **起飞必须把两个动作分开读。** `Input.get_axis("drive_back", "drive_forward")`
## 在两边同时按下时返回 0（−1 + 1），正好把「同时按前进和倒退」这个手势吃掉
## —— 而那正是要认的手势。从 [member throttle] 上根本看不出来。
func _read_throttle() -> void:
	throttle = 0.0
	hovering = false
	if not engine_on or fuel <= 0.0:
		return
	if hover_enabled:
		hovering = Input.is_action_pressed("drive_forward") \
				and Input.is_action_pressed("drive_back")
		# 起飞时轮子照常**全速转**，不是 0。两件事一起靠它成立：
		#   · 「前进速度等于正常行驶速度」—— 落地那一刻轮子已经在正常转速上；
		#   · 油耗算式不用另写一条 —— throttle = 1 时 [method _burn_fuel] 本来
		#     就是满油门，乘上倍率正好是「满油门的三倍」。写成 0 的话只剩怠速
		#     （1.6），悬停反而比开车省油。
		throttle = 1.0 if hovering else Input.get_axis("drive_back", "drive_forward")
	else:
		throttle = Input.get_axis("drive_back", "drive_forward")


## 道具：按键使用 + 两个计时器倒扣。
##
## 按键在物理帧里用 [method Input.is_action_just_pressed] 读，而不是在
## `_unhandled_input` 里收事件 —— 和上面那行 `Input.get_axis` 是同一套读法，
## 而且「刚按下」和这一帧真正生效的力矩落在同一帧，不会差一帧。
##
## 能不能用**不在这里判**，一律问 [method SaveData.use_item]：带没带、用没用过
## 只有那一处实现，三个道具共用。返回 true 才产生效果。
func _update_items(delta: float) -> void:
	nitro_time = maxf(0.0, nitro_time - delta)
	shield_grace = maxf(0.0, shield_grace - delta)
	if _pressed(Items.NITRO) and SaveData.use_item(Items.NITRO):
		nitro_time = Items.NITRO_TIME
		item_used.emit(Items.NITRO)
	if _pressed(Items.FUEL) and SaveData.use_item(Items.FUEL):
		add_fuel(fuel_max * Items.FUEL_RATIO)
		item_used.emit(Items.FUEL)


## 这件道具的按键这一帧刚被按下吗。被动道具（[constant Items.SHIELD]）没有按键，
## 这里返回 false。
##
## `InputMap.has_action` 那一问是兜底：动作名是从 [member Items.CATALOG] 里读的，
## 而那张表和 project.godot 里的绑定是两份，会漂。真漂了的话，
## `is_action_just_pressed` 会每帧往控制台打一条错误 —— 一条静默的 false 比
## 刷屏好。`tests/shop` 里另有一条断言把这件事拦在测试里。
func _pressed(id: String) -> bool:
	var action := Items.action_of(id)
	return action != "" and InputMap.has_action(action) and Input.is_action_just_pressed(action)


## 车壳碰撞多边形的包围盒（**车壳本地坐标**）。
##
## 车灯摆在哪儿只认它，不认美术：八辆车里 `BodyVisual` 和 `Body` 用的是逐字相同的
## 那份点（`scenes/car.tscn` 里两个数组一模一样），但美术节点的名字各不相同
## （`Cab` / `Windows` / `RoofLights` / `Turret` / `Barrel`……），按名字找会一辆车
## 一个特例。碰撞多边形则是每辆车都有、且都叫 `Body` 的那一份数据。
func skin_box() -> Rect2:
	var pts := _skin_points()
	if pts.is_empty():
		# 兜底：读不到多边形（以后哪辆车换成胶囊之类的形状）也别让车灯和车灯锥凭空
		# 消失 —— 给一个大概的车壳。tests/shapes 里钉着八辆车都走不到这一行。
		return Rect2(-60.0, -24.0, 120.0, 36.0)
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


## 车壳碰撞多边形的顶点（车壳本地坐标）。
##
## 只收 [member chassis] 的**直接**子节点里的 [CollisionShape2D]（每辆车正好一个，
## 叫 `Body`）：轮子是车壳的兄弟节点，车手的头挂在 `Chassis/Head` 底下 —— 都不是
## 直接子节点，所以灯不会量到车轮或头盔上去。
func _skin_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if chassis == null:
		return out
	for child in chassis.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		if cs.shape is ConvexPolygonShape2D:
			for p: Vector2 in (cs.shape as ConvexPolygonShape2D).points:
				out.append(cs.transform * p)
		elif cs.shape is RectangleShape2D:
			var half := (cs.shape as RectangleShape2D).size * 0.5
			out.append(cs.transform * Vector2(-half.x, -half.y))
			out.append(cs.transform * Vector2(half.x, half.y))
	return out


## 车头两颗灯的位置（**车壳本地坐标**），先远后近。
##
## [HillNight] 照着这个画灯珠，车灯锥也从**靠前那颗**（`x` 大的那颗）射出去 ——
## 从轴心射的话，车壳自己的前半截会落在锥形里，被照得比后半截亮一截。
##
## 摆法只用车壳包围盒的高度和前端：两颗灯落在离底边 45% 和 20% 车高的位置，靠前那颗
## 往回半个灯距。**不写死偏移量** —— 八辆车的车头天差地别（摩托是个尖、大巴是一面墙、
## 赛车是个铲），写死的偏移在半数车上会把灯画到车壳外面去。
func headlight_lamps() -> PackedVector2Array:
	var box := skin_box()
	var height := maxf(box.size.y, 1.0)
	# 灯距（和灯珠半径）都从车高推：大巴的灯自然比摩托的大，不用再开一个按车型调的旋钮。
	var gap := height * 0.25
	return PackedVector2Array([
		Vector2(box.end.x - gap, box.end.y - height * 0.45),
		Vector2(box.end.x - gap * 0.45, box.end.y - height * 0.20),
	])


## 这张图开不开得了车灯。**只有黑夜图开得了** —— 挡布只在黑夜图上出现
## （见 [method Maps.is_night]），白天图开了只有油耗、没有光。
func headlights_available() -> bool:
	return Maps.is_night(map_id)


## 开关车灯。空格和 HUD 上那颗按钮**都走这一个入口**：两条路径各写一份的话，
## 按钮那边迟早会忘了同步状态，于是「按钮亮着、路上没光」。
##
## 不是黑夜图就直接忽略（见 [method headlights_available]）。
func toggle_headlights() -> void:
	if not headlights_available():
		return
	headlights_on = not headlights_on


## 车灯开关的按键。和道具一样在**物理帧**里读「刚按下」
## （理由见 [method _update_items]：和这一帧真正生效的那点油耗落在同一帧）。
func _update_headlights() -> void:
	if InputMap.has_action(HEADLIGHT_ACTION) and Input.is_action_just_pressed(HEADLIGHT_ACTION):
		toggle_headlights()


## 腾空到 [param seconds] 这一刻，**已经跨过了第几节**腾空奖励。
##
## 起奖线之前返回 −1（而不是负数往下数），见下面那个「向零截断」的说明。
## 纯函数，不碰任何成员 —— tests/air 直接拿它对着 [constant AIR_BONUS_TIERS]
## 把整条时间轴算一遍，不用真去飞 8 秒。
static func air_bonus_tick(seconds: float) -> int:
	# 不能写成 `int((t - DELAY) / INTERVAL)` 就完事 —— 起奖线之前那个式子是负的，
	# 而 `int()` 是**向零截断**：t = 0.5 时算出 −1、t = 0 时算出 −2，两个数之间的
	# 「变大」会照样触发一次发奖，正好把这条起奖线绕过去了（第一次发钱变成 0.5 秒，
	# 和写死 1.0 那一版一模一样）。所以没到起奖线时钉成一个比任何合法节号都小的
	# −1，比不出「变大」，起奖线之前那些帧就被吃掉了。
	if seconds < AIR_BONUS_DELAY:
		return -1
	return int((seconds - AIR_BONUS_DELAY) / AIR_BONUS_INTERVAL)


## 腾空到 [param seconds] 这一刻落到的那一节**值多少金币**（不在奖励区间里就是 0）。
##
## **取的是「已经跨过的最高一档」，不是「最接近的那一档」**：2.5 秒刚过就该是
## 50 而不是 0，4.0 秒刚过就该是 100 而不是 50 —— 用户说的「超过 4 秒后每 0.5 秒
## 100 金币」就是这个意思。档位表按秒数升序排，所以一路覆盖下去最后留下的就是
## 最高的那一档；表如果哪天被写乱了顺序，这个循环会给出错的档，tests/air 里有
## 一条断言盯着表的升序性。
static func air_bonus_coins(seconds: float) -> int:
	if seconds < AIR_BONUS_DELAY or seconds >= AIR_BONUS_STOP:
		return 0
	var coins := 0
	for tier in AIR_BONUS_TIERS:
		if seconds >= float(tier[0]):
			coins = int(tier[1])
	return coins


## 腾空计时 + 空翻计数。两个轮子都不碰地就算在飞：满 [constant AIR_BONUS_INTERVAL]
## 发一节腾空奖励（金额看 [constant AIR_BONUS_TIERS]），转满 [constant FLIP_TURNS]
## 圈发一次空翻奖励。
##
## 判据是**轮子的接触**，不是「车身离地高度」：吊桥和冰面这些平台根本不在地形
## 折线上，拿 [method HillTerrain.height_at] 比高度会把站在桥上当成在飞。
##
## 只看 `"ground"` 组而不是「有没有碰到任何东西」：车自己的轮子和车身在几何上
## 是重叠的（靠关节的 disable_collision 才不打架），万一哪次自碰撞漏出来，
## 按「碰到任何东西」判会让车永远算是着地的。
func _update_airborne(delta: float) -> void:
	# 逐个轮子分开问。**「独轮」必须问「哪一个着地」，不能只看「有没有触地」**
	# —— 见下面 [method _update_wheelie]。
	#
	# `rear_down` 单拎出来只为了飘字的文案（「后轮」还是「前轮」），不参与判据。
	# 两轮车上这一段的结论和以前写死 `rear_wheel` / `front_wheel` 时逐位相同。
	var down := 0
	var rear_down := false
	for wheel in wheels:
		if _touching_ground(wheel):
			down += 1
			if wheel == rear_wheel:
				rear_down = true
	var touching := down > 0
	grounded = touching
	# 车身这一帧转过多少。**不管在不在空中都要更新**：只在空中更新的话，落地
	# 滚一段再起飞，那第一帧会把地面上滚过的角度一起算进空翻里。
	#
	# `wrapf` 不能省：`RigidBody2D.rotation` 是折算到 ±π 的，车身从 +180° 转到
	# −180° 时这个值会一步跳 −2π，不折算就会被当成「倒退了一整圈」白送 300 块。
	var turned := wrapf(chassis.rotation - _last_rotation, -PI, PI)
	_last_rotation = chassis.rotation
	if touching:
		_has_landed = true
		air_time = 0.0
		# 落地就把这一趟转过的角度作废：空翻必须**在空中转完**。不作废的话，
		# 空中转半圈、落地再蹭半圈，也能凑出一整圈来骗钱。
		flip_angle = 0.0
		_update_wheelie(delta, down, rear_down)
		return
	# 腾空就把独轮的账清零：独轮是「骑在一个轮子上走」，不是「两个都不沾地」。
	wheelie_time = 0.0
	var before := air_time
	air_time += delta
	flip_angle += turned
	if not _has_landed:
		return
	# 第几节：**先减掉起奖线**，所以第一次发钱落在 AIR_BONUS_DELAY 那一刻。
	var n_now := air_bonus_tick(air_time)
	var n_before := air_bonus_tick(before)
	if n_now > n_before:
		# 金额按**跨过这一节那一刻**的档位算，不是按上一节 —— 4.0 秒那一节起的
		# 就该是 100，不是 50。超过 AIR_BONUS_STOP 之后 air_bonus_coins 返回 0，
		# 这一句因此必须判一下：发一笔 0 块会让 HUD 飘一个「+0 腾空」出来。
		var coins := air_bonus_coins(air_time)
		if coins > 0:
			air_bonus.emit(coins)
	# 转满一圈发一次；多转的部分**留着**，接着转就是连翻（两圈发两次）。
	if absf(flip_angle) >= TAU * FLIP_TURNS:
		var back := flip_angle < 0.0
		flip_angle -= TAU * FLIP_TURNS * signf(flip_angle)
		flip_bonus.emit(FLIP_BONUS_COINS, back)


## 腾空时的姿态控制：按前进往**逆时针**拧，按倒退往**顺时针**拧。
##
## **只在两个轮子都不着地时生效。** 地面上按前进是开车，不是翻跟头 —— 少了这道
## 闸，车一给油就会原地转起来。
##
## 读的是 [member throttle] 而不是直接读输入：没油或者熄火时 `throttle` 本来就是
## 0，于是「没油了连空中都调不了姿态」是白来的，不用另写一条判断。
##
## 力矩乘的是**车壳当前的转动惯量**，而且是问物理服务器要的
## （[method _auto_inertia]），不是读 `RigidBody2D.inertia` —— 后者在自动模式下
## 恒为 0，那是「自动」这个状态的哨兵值，乘出来等于没有空中姿态
## （见 [method _apply_inertia_scale] 那段注释，同一个坑）。乘完的效果是
## 「四辆车、任何敏捷等级，角加速度都是 [member air_spin]」。
##
## 只拧车壳、不单独拧轮子：轮子的惯量只有车壳的百分之几，而它们是被两个
## [PinJoint2D] 拴在车壳上的 —— 车壳转，销子自然把轮子拽着一块转。
func _apply_air_control() -> void:
	# 起飞时让开：「前进」这一个键在下面要求把车身**逆时针拧**，而它同时又只是
	# 起飞的半个手势 —— 两个一起上，飞机会原地打转。
	if hovering or grounded or is_zero_approx(throttle):
		return
	var inertia := _auto_inertia(chassis)
	if inertia <= 0.0:
		return
	# 负号：Godot 2D 的 y 轴朝下，正角度在屏幕上是**顺时针**（见 [member flip_angle]
	# 那段）。前进要的是逆时针，所以是负的；倒退给负油门，符号自然反过来。
	chassis.apply_torque(-air_spin * inertia * throttle)


## 独轮行驶计时。**只有恰好一个轮子着地才算**：
##
##  · [param down] 是着地的轮子数。全都着地（`down == 轮子总数`）是正常行驶，
##    一个都不着地是腾空（上面那条路已经清零了，这里再判一次是兜底）；
##  · [param rear_down] 是**后轮在不在着地的那些轮子里面**，只用来决定飘字的文案
##    （「后轮」还是「前轮」），不参与判据。
##
## 所以判据就是 `down == 1`。两轮车上它和旧的写法 `rear_down != front_down` 逐位
## 等价；换成「数个数」是为了独轮车 —— 那种车上「前轮」和「后轮」是同一个轮子，
## 用两个布尔值根本说不出「着地一个」到底算哪一头。
##
## 哪一头离地都算：后轮独走是抬头、前轮独走是翘尾，两种都难，都发奖。
##
## 满 [constant WHEELIE_TIME] 发一次，**多出来的部分留着**：接着骑就是连发。
## 和空翻那边一个规矩（见 [method _update_airborne] 里 `flip_angle` 的处理）。
func _update_wheelie(delta: float, down: int, rear_down: bool) -> void:
	# **独轮车永远不发这条奖。** 它只有一个轮子，「恰好一个着地」是它的常态而不是
	# 特技 —— 不加这道闸，它每骑满 [constant WHEELIE_TIME] 白拿 75 币，一路捡钱。
	# `wheels.size() < 2` 这一问就是为它写的：`down == 1` 在它身上恒成立。
	if wheels.size() < 2 or down != 1:
		wheelie_time = 0.0
		return
	wheelie_time += delta
	if wheelie_time >= WHEELIE_TIME:
		wheelie_time -= WHEELIE_TIME
		wheelie_bonus.emit(WHEELIE_BONUS_COINS, rear_down)


func _touching_ground(wheel: RigidBody2D) -> bool:
	for body in wheel.get_colliding_bodies():
		if body.is_in_group("ground"):
			return true
	return false


## 转速式的马达：给每个轮子施加与「目标转速偏差」成正比的力矩。
## 比起直接写 angular_velocity，这样轮子仍然会打滑、会被地面顶回来。
func _apply_motor() -> void:
	var target := throttle * max_wheel_speed
	var strength := motor_strength
	# 力矩上限得跟着一起放大，否则多出来那一截会在下面 clamp 那一步被削掉，
	# 现象是「氮气好像没劲」（见 [constant Items.NITRO_TORQUE]）。
	var ceiling := max_torque
	if nitro_time > 0.0:
		strength *= Items.NITRO_TORQUE
		ceiling *= Items.NITRO_TORQUE
		# 目标转速也抬起来。只加力矩的话，车被推得比轮面线速度还快时差值为负，
		# 马达反过来当刹车，推力和马达当场对打（见 [constant Items.NITRO_SPEED]）。
		# **只在前进时抬**：倒车中按氮气不该让刹车更狠。
		if throttle > 0.0:
			target *= Items.NITRO_SPEED
		# 直接推车壳：后轮离地时力矩一点用都没有，而飞起来正是最想加速的时候。
		# 用力 = 车重 × 倍率，所以四辆车（车架 55~200）拿到的是同一个 g 数。
		chassis.apply_central_force(Vector2(chassis.mass * Upgrades.GRAVITY * Items.NITRO_PUSH, 0.0))
	if absf(throttle) < 0.01:
		strength *= coast_strength_scale
	var applied := 0.0
	for wheel in wheels:
		var diff: float = target - wheel.angular_velocity
		var torque := clampf(diff * strength, -ceiling, ceiling)
		wheel.apply_torque(torque)
		# 记**实际**加上的那个数，给 [method _apply_balance] 的预判项用。
		applied += torque
	_motor_torque = applied


## 世界坐标下的本地重力加速度。地图会给车写 [member RigidBody2D.gravity_scale]
## （月球 0.35），起飞推力必须跟着它走 —— 按固定的 980 算的话，同一辆车在月球上
## 是平原上的 2.9 倍劲，一按就窜出屏幕。
##
## **只是读，不写**：真去改 `gravity_scale` 的话轮子也会跟着变轻，一落地手感全错。
##
## 不叫 `_local_gravity` 了：烟囱的烟气（[scripts/chimneys.gd]）也要按本地重力算力，
## 「本地重力」于是不止起飞一处用。
func local_gravity() -> float:
	return Upgrades.GRAVITY * chassis.gravity_scale


## 整辆车的质量：车壳 + **所有**轮子。
##
## 车壳的质量不是车的质量：两个轮子各有 22，占了总重的四分之一；独轮车只有一个
## 轮子（见 [member wheels]）。凡是「按自重算一个力」的地方都得用它 ——
## 起飞推力（[method _apply_hover]）、烟囱的烟（[scripts/chimneys.gd]）。
##
## 选车界面那份统计（[method Vehicles.stats]）自己又加了一遍：那边拿到的只是
## 一个 Node2D（不能在这里写出车类型 —— car.gd → Upgrades → Vehicles 会成环），
## 够不着这个函数。两处加的是同一批东西，改质量上限的时候两边都得看。
func total_mass() -> float:
	var m := chassis.mass
	for wheel in wheels:
		m += wheel.mass
	return m


## 起飞时的水平速度上限：轮速 × 轮半径，就是 [method Vehicles.stats] 里那个
## `top_speed`。**现算而不是写死**，因为升级「极速」改的正是 `max_wheel_speed`
## —— 写死的话练过极速的车一飞就掉速，「和正常行驶一样」当场不成立。
func hover_top_speed() -> float:
	if hover_speed > 0.0:
		return hover_speed
	return max_wheel_speed * _wheel_radius()


## 轮子半径，从**碰撞形状**里读（和 effects.gd 一个做法）。写成常量的话，哪天
## 轮子调大了这里会静默用旧值 —— 而它乘出来是「起飞时该飞多快」。
func _wheel_radius() -> float:
	if wheels.is_empty():
		return 21.0
	var shape := wheels[0].get_node_or_null("Shape") as CollisionShape2D
	if shape != null and shape.shape is CircleShape2D:
		return (shape.shape as CircleShape2D).radius
	return 21.0


## 起飞推力。方向取**世界**的上下/左右，不取车身：车翻过来的时候也该被往上顶，
## 而且「前进速度」只有在世界坐标里才和「正常行驶速度」可比。
##
## 力按**每个刚体各自的质量**分别施加（[method bodies]），而不是像氮气那样只推
## 车壳。氮气只顶一瞬，两个销子拽得住；悬停是持续的，只推车壳的话轮子会被吊着
## 往下坠，看上去车被拉长了。
func _apply_hover() -> void:
	if not hovering:
		return
	var local_g := local_gravity()
	for body in bodies():
		var w := body.mass * local_g
		body.apply_central_force(Vector2(0.0, -w * hover_lift))
		body.apply_central_force(Vector2(w * hover_push, 0.0))
	_clamp_hover_speed()


## 把车壳的水平速度**钳在** [method hover_top_speed] 上，而不是给个加速度让它
## 自己稳 —— 「前进速度和正常行驶一样」要的是等式，不是近似，而且钳位是幂等的，
## 不会因为帧率不同飘。
##
## 只钳车壳：两个轮子被销子拖着，速度本来就跟着车壳走；逐个钳只会让三个刚体
## 互相拉扯。
func _clamp_hover_speed() -> void:
	var cap := hover_top_speed()
	# 车头朝左时「前进」是 −x，所以拿车头方向的 x 分量去比，左右都成立。
	var dir := signf(chassis.transform.x.x)
	if is_zero_approx(dir):
		return
	if chassis.linear_velocity.x * dir > cap:
		chassis.linear_velocity.x = cap * dir


## 陀螺仪自平衡：着地时把车壳往**直立**方向拧。[member balance_torque] 为 0 时
## 整个函数是空转，其余车辆分毫不变。
##
## **必须封顶，不能直接写 `sin(倾角)`。** sin 在 90° 才取到最大，用它的话车倒得
## 越狠回正越猛，结果是「永远不倒」而不是「能骑」。这里按倾角线性爬升、到
## [member balance_full_angle] 封顶，重力倾覆力矩（∝ sin θ）总会在某个角度超过
## 上限 —— 那个角度就是这辆车能救回来的极限倾角，由 [member balance_torque]
## 决定，`tests/balance` 会把它量出来。
##
## 判据用**车壳直立**（`rotation → 0`）而不是「垂直于坡面」。写死的版本更可预测，
## 而且顺带白来一条限制：在陡坡上重心自然偏离接地点、重力倾覆变大，
## **独轮车爬不了陡坡**是这个模型的自然结果，不用另写判据。
##
## 只在着地时出力：腾空交给 [method _apply_air_control]，两个一起上会打架。
func _apply_balance() -> void:
	if balance_torque <= 0.0 or not grounded:
		return
	var inertia := _auto_inertia(chassis)
	if inertia <= 0.0:
		return
	# 倾角为正 = 屏幕上的顺时针 = **车头往下扎**（见 [member air_spin] 那段）。车头一扎，
	# 重心就跑到接地点前面去了，重力接着往同一边拧它 —— 也就是**正的倾角自己会越滚
	# 越大**（绕支点的重力矩 = m·g·d·sin θ，和 θ 同号）。所以回正力矩必须取**负**：
	# 正的倾角给负的力矩。这里少一个负号就是正反馈，车会倒得比不装陀螺仪还快。
	#
	# 阻尼项 `- damping × ω` 本身就是反向的，两种写法都对，不用跟着翻。
	var lean := wrapf(chassis.rotation, -PI, PI)
	var demand := -clampf(lean / balance_full_angle, -1.0, 1.0) * balance_torque
	demand -= balance_damping * chassis.angular_velocity
	# 前馈：马达的抬头力矩在这里提前抵掉，算式和系数见 [member balance_assist]。
	# 力矩**取正号** —— 马达往前转是正的 τ，销子拽着车壳往前、车壳于是往后仰，
	# 也就是负方向的（逆时针）力矩，所以要拿一个正的（低头）来抵。
	# 除以惯性是因为 `demand` 的量纲是角加速度，函数末尾才乘回去。
	if balance_assist > 0.0:
		var radius := _wheel_radius()
		if radius > 0.0:
			demand += balance_assist * _pin_lever() * _reaction_share() \
					* _motor_torque / radius / inertia
	chassis.apply_torque(demand * inertia)


## 销子（也就是轮心）在车壳重心**下方**多少像素。马达的反作用力就作用在这里，
## 力臂是这个竖直距离 —— 见 [member balance_assist]。
##
## 重心取**当前**的，不写死：形状一改、配重一加它就变，抄一份常量迟早对不上，
## 而且是静默对不上。没进树的实例上 `get_rid()` 是空 RID，读出 0 —— 这时车
## 也没在跑，不要紧。
##
## **注意 Godot 2D 的自动重心不是形状的面积质心。** `RectangleShape2D` /
## `CircleShape2D` 看不出差别（它们的原点就是质心），但 `ConvexPolygonShape2D`
## 的重心取的是**碰撞形状自己的位置**，不是多边形的面积质心 —— 独轮车那个梯形
## 的面积质心在 (0, 3.8)，引擎认的却是 (0, 0)（= 形状的位置）。实测方法：自由
## 刚体上加一个过原点的冲量，量角速度反推力臂，一个偏移 50 的矩形量出来正好是
## 50，梯形量出来是 0。所以独轮车的力臂是 **26**（轮心到形状原点），不是
## 26 − 3.8 = 22.2。**按 22.2 补就会少补 17%，车当场往前扎。**
func _pin_lever() -> float:
	if wheels.is_empty():
		return 0.0
	var rid := chassis.get_rid()
	if rid == RID():
		return 0.0
	var com: Vector2 = PhysicsServer2D.body_get_param(
			rid, PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS)
	var total := 0.0
	for wheel in wheels:
		total += (chassis.transform.affine_inverse() * wheel.position).y - com.y
	return total / float(wheels.size())


## 马达的力矩有多大比例变成**拽车壳**的力。见 [member balance_assist]。
##
## 轮子上加力矩 τ，整车平动加速度 `a = (τ/r) / (m_c + Σm_w + ΣI_w/r²)`（分母
## 把每个轮子的转动惯量按 `I/r²` 折算成平动惯量），车壳通过销子分到的是
## `m_c · a`，所以比例就是 `m_c / (m_c + Σm_w + ΣI_w/r²)`。
## **不是 1.0** —— 当成 1.0 补，独轮车会往前扎。
##
## **现算而不是写死**：分母里有轮子的转动惯量，它跟着 [member inertia_scale] 走
## —— 玩家练了「敏捷」这个比例就变，写死等于给改装过的车补错一块。
func _reaction_share() -> float:
	var radius := _wheel_radius()
	if radius <= 0.0:
		return 0.0
	var total := chassis.mass
	for wheel in wheels:
		total += wheel.mass + _auto_inertia(wheel) / (radius * radius)
	if total <= 0.0:
		return 0.0
	return chassis.mass / total


func _burn_fuel(delta: float) -> void:
	var rate := fuel_idle_drain + absf(throttle) * fuel_throttle_drain
	# 起飞时油耗翻倍。**不用另写一条「悬停按满油门算」**：[method _read_throttle]
	# 已经把 throttle 顶成 1.0，所以这里本来就是满油门，乘倍率就够了。
	if hovering:
		rate *= hover_fuel_scale
	# 车灯是**恒定的额外消耗**，和油门、悬停各算各的：加在倍率**之后**，
	# 否则悬停时开灯会跟着翻三倍（见 [constant HEADLIGHT_DRAIN]）。
	if headlights_on:
		rate += HEADLIGHT_DRAIN
	fuel = maxf(0.0, fuel - rate * fuel_drain_scale * delta)
	if fuel <= 0.0:
		_die(REASON_FUEL)


func add_fuel(amount: float) -> void:
	fuel = minf(fuel_max, fuel + amount)


## 车手头部碰到地面 = 翻车。这是《登山赛车》最经典的一条规则。
##
## 碰到隧道洞顶（[constant CEILING_GROUP]）也是死，但死因不同：那是「撞到洞顶」，
## HUD 上的文案不一样。两个组分别认，**顺序不要紧** —— 一块石头不会同时属于
## 两个组，隧道洞顶只进洞顶组、不进地面组。
##
## 防护罩就插在这里：该判死的那一下，先问 [method SaveData.use_item] 能不能用。
## 能用就**不判死**，交给 [method _right_self] 扶正并挪出去，再开一个免死窗口 ——
## 落点是从上面掉下去的，落地那一下、以及刚落稳就被地形顶一下，都不该当场再判死。
func _on_head_body_entered(body: Node) -> void:
	var reason := ""
	if body.is_in_group(CEILING_GROUP):
		reason = REASON_CEILING
	elif body.is_in_group("ground"):
		reason = REASON_CRASH
	else:
		return
	if shield_grace > 0.0:
		return
	if SaveData.use_item(Items.SHIELD):
		_right_self()
		item_used.emit(Items.SHIELD)
		return
	# **传上面算出来的那个 `reason`，不要写死 REASON_CRASH。** 写死的话上面那两行
	# 白算了：撞洞顶也报「翻车了」，而 HUD 上那是两句不同的话
	# （「撞到洞顶」/「翻车了」），测试也因此只能量到「死了」而不是「怎么死的」。
	_die(reason)


## 防护罩生效：先把车扶正，再整车挪到死亡地右边
## [constant Items.SHIELD_RESPAWN_METERS] 米的地面上。
##
## **必须三个刚体一起转，不能只写 `chassis.rotation = 0`。** 它们是靠两个
## [PinJoint2D] 铰在一起的独立刚体，只拧车壳的话，铰链会被拉到一个它不认的
## 姿态上，物理求解器下一帧会用很大的力把轮子拽回来 —— 表现是车原地抽搐一下，
## 然后以更糟的姿态再翻一次。
##
## 三个中心吃的是**同一个旋转变换**，所以相对位置原样保留，扶正之后车还是那辆
## 车，只是躺平了。
##
## 顺带把腾空/空翻的账目清零：这一下既不是腾空也不是空翻，是物理外挂，
## 不能让它白送一节腾空奖或者一圈空翻奖。
func _right_self() -> void:
	var rot := chassis.rotation
	var pivot := chassis.global_position
	var xf := Transform2D(-rot, Vector2.ZERO)
	for body in bodies():
		body.global_position = pivot + xf * (body.global_position - pivot)
		body.rotation -= rot
		# 角速度必须清零：不清的话它接着转，扶正只管一帧。
		body.angular_velocity = 0.0
		body.linear_velocity *= Items.SHIELD_KEEP
	shield_grace = Items.SHIELD_GRACE
	_last_rotation = chassis.rotation
	flip_angle = 0.0
	wheelie_time = 0.0
	_respawn_shift()


## 把扶正好的车整体挪到死亡地右边 50 米，落在那里的地面上。
##
## 高度是**重新量的**，不是照搬死亡点的高度：地形本来就有起伏，照搬的话车会正
## 好嵌进对面那座山里（或者悬在坑口上方）。量法是往下打一条射线问物理引擎
## 「这个 x 的实心地面在哪儿」—— 用射线而不是问 [HillTerrain]，是因为车不该知道
## 地形节点是谁（见 [member map_id] 那段注释同一个理由），而且隧道、吊桥这些
## 能站人的东西是别的刚体，射线一视同仁。
##
## 射线打不到东西（区块还没建出来、或者这一段真的悬空）就**只往上抬一下，原地
## 不动**。不知道对面是什么的时候，挪过去比不挪危险得多 —— 宁可这次防护罩买亏
## 了，也不能把车塞进山体里。这条正常跑永远走不到（地形在车前方两个区块内都是
## 建好的，而 50 米只有 0.6 个区块），留的是别处调用时的兜底。
func _respawn_shift() -> void:
	var dx := Maps.PIXELS_PER_METER * Items.SHIELD_RESPAWN_METERS
	var ground := _ground_y_at(chassis.global_position.x + dx)
	var delta := Vector2(0.0, -Items.SHIELD_LIFT)
	if is_finite(ground):
		delta.x = dx
		# 三个刚体里**最靠下的那个**（扶正之后就是轮心）落到地面上方 SHIELD_LIFT
		# 处。轮子还有半径，所以真正落地前会掉一小段 —— 和出生时一样，落地前
		# 不给腾空奖励（[member _has_landed] 那时已经是 true 了，这段路够短，
		# 攒不满 AIR_BONUS_INTERVAL 那半秒）。
		delta.y = ground - Items.SHIELD_LIFT - _lowest_body_y()
	for body in bodies():
		body.global_position += delta


## 三个刚体里最靠下的那个的 y。扶正之后这就是轮心的 y。
func _lowest_body_y() -> float:
	var lowest := -INF
	for body in bodies():
		lowest = maxf(lowest, body.global_position.y)
	return lowest


## 世界坐标 x 处的实心地面高度（y）。从上方 [constant GROUND_SCAN] 处往下打一条
## 射线，取第一个碰撞点。打不到返回 NAN。
func _ground_y_at(x: float) -> float:
	# 没进树的车（测试里 detached 实例化出来的那种）没有世界可以问，直接当打不到。
	var world := get_world_2d()
	if world == null:
		return NAN
	var from := Vector2(x, chassis.global_position.y - GROUND_SCAN)
	var to := Vector2(x, chassis.global_position.y + GROUND_SCAN)
	var query := PhysicsRayQueryParameters2D.create(from, to, GROUND_LAYER)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector2).y


func _die(reason: String) -> void:
	if not alive:
		return
	alive = false
	throttle = 0.0
	crashed.emit(reason)
