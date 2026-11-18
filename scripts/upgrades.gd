extends RefCounted
class_name Upgrades
## 车辆升级项的中央定义表：等级 → 参数倍率、等级 → 花销。
##
## 等级本身存在 [SaveData] 里，这里只负责换算。分开的好处是改平衡不用碰存档代码、
## 改存档格式不用碰数值。
##
## ## 两条设计约束
##
## 1. **所有倍率在 Lv.0 时恒等于 1.0**（[method apply] 是乘在车辆当前参数上的，
##    不是从常量重算）。所以：
##    - 编辑器里调 `@export` 的基准值依然有效，升级是在那之上叠乘；
##    - 测试用例把 Lv 全设为 0 就等于「原厂车」，自己设的 `inertia_scale` 之类
##      不会被悄悄改掉。
## 2. **引擎是唯一影响推重比的项。** 见 [method apply] 里对「极速」的处理。

## 每项 10 级。
##
## **从 4 级改成 10 级不是把每级倍率照抄一遍就完事** —— 那样有两处会直接坏掉：
##
##  · 敏捷。旧值 −12.5%/级，十级是 `1 − 1.25 = −0.25`，转动惯量成了**负数**，
##    刚体直接不成立。第 8 级就归零了。
##  · 引擎。旧值 ×1.05/级，十级是 ×1.629。越野车满级推重比 1.68 × 1.629 = 2.74，
##    远超 [constant WHEELIE_LINE] 1.45 —— 玩家砸满引擎换来一台一踩油门就翻的车，
##    正是 [method apply] 那段注释里极力避免的事。
##
## 所以四个每级倍率是**照「满级落在哪儿」反推**的：让 Lv.10 正好等于旧版的 Lv.4。
## 结果是**满级后的强度分毫未变**，只是把同一段涨幅切成了十份（每级 +2%，看得见地
## 在长）。想改强度就改下面这四个数，别改 MAX_LEVEL。
const MAX_LEVEL := 10
## 花销：**第一级 1000 币**，每级 ×1.15，单项点满 20304 币，四项 81216。
##
## ×1.15 的阶梯是
## 1000 / 1150 / 1323 / 1521 / 1749 / 2011 / 2313 / 2660 / 3059 / 3518。
##
## **增长率不能跟着基价一起放大。** 十级按 ×1.5 涨的话最后一级单独就要
## 1000 × 1.5⁹ = 38443 币，单项总额 113000 打底 —— 那不是「贵一点」，是把升级
## 系统从游戏里删掉。×1.15 每级只涨 15%，十级下来才 3.5 倍，整条线还在
## 「跑几趟就能点一级」的范围内。
##
## 和金币面额（[constant Pickup.COIN_VALUES]，期望值随里程从 62.5 涨到 150，
## 见 [method Pickup.mean_value_at]）对一下：一趟 1000 米平均下来大约捡 1710 块，
## 所以**一级起步价约等于三分之二趟**，第一级当天就能买；想点满一项要跑十几趟 ——
## 这是长期目标，不是开场就要清的清单。
##
## （远处金币值钱这件事**没有**把升级变便宜太多：一趟 1 km 只多一成，而 1 km 之后
## 地形已经很颠，跑得到 2 km 的趟数远少于 1 km 的。真要重新配平，动
## [constant BASE_COST] 之前先看 [method Pickup.mean_value_at] 那条曲线。）
##
## 想调就动这两个数，改完 `tests/upgrade_calib` 的 A 段会把整张表和总额打出来。
const BASE_COST := 1000
const COST_GROWTH := 1.15

## 每级倍率。改这里就能调平衡，改完用 tests/upgrade_calib.tscn 量一遍。
##
## 四个数都是反推出来的，等式右边是**旧版 Lv.4 的值**，用来核对：
##
##     引擎 1.0197^10 = 1.2155   （旧 1.05^4  = 1.2155）
##     极速 1.0236^10 = 1.2627   （旧 1.06^4  = 1.2625）
##     油箱 1+0.06×10 = 1.60     （旧 1+0.15×4 = 1.60）
##     敏捷 1−0.05×10 = 0.50     （旧 1−0.125×4 = 0.50）
##
## `tests/upgrade_calib` 的 A 段会把这些等式再算一遍，改了倍率忘了对上就会失败。
const ENGINE_PER_LEVEL := 1.0197   ## 扭矩：满级 ×1.216
const SPEED_PER_LEVEL := 1.0236    ## 极速：满级 ×1.263
const FUEL_PER_LEVEL := 0.06       ## 油箱：+6%/级，满级 ×1.60
const AGILITY_PER_LEVEL := 0.05    ## 转动惯量：−5%/级，满级 ×0.50（惯量越小越敏捷）

## 展示顺序 = 车库里的行序。
const IDS: Array[String] = ["engine", "speed", "fuel", "agility"]

const TRACKS := {
	"engine": {
		"zh": "引擎", "en": "ENGINE",
		"zh_note": "爬坡更有劲，翘头风险上升",
		"en_note": "more power, more wheelie risk",
		"zh_unit": "扭矩", "en_unit": "TORQUE",
	},
	"speed": {
		"zh": "极速", "en": "TOP SPEED",
		"zh_note": "齿比更高，爬坡推力不变",
		"en_note": "higher gearing, thrust unchanged",
		"zh_unit": "极速", "en_unit": "SPEED",
	},
	"fuel": {
		"zh": "油箱", "en": "FUEL TANK",
		"zh_note": "一箱油跑得更远",
		"en_note": "longer runs per tank",
		"zh_unit": "容量", "en_unit": "CAPACITY",
	},
	"agility": {
		"zh": "敏捷", "en": "AGILITY",
		"zh_note": "转动惯量减半，更利索但更跳",
		"en_note": "quicker, but bouncier",
		"zh_unit": "灵敏", "en_unit": "RESPONSE",
	},
}


static func level_of(levels: Dictionary, id: String) -> int:
	return clampi(int(levels.get(id, 0)), 0, MAX_LEVEL)


## 从 level 升到 level+1 的花销。已满级返回 0。
static func cost(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return int(round(float(BASE_COST) * pow(COST_GROWTH, float(level))))


## 单项点满的总花销。
static func total_cost() -> int:
	var sum := 0
	for lv in range(MAX_LEVEL):
		sum += cost(lv)
	return sum


## 那一项在车库面板里显示的数字（都 ≥ 1，越大越好）。
##
## 「敏捷」内部是把转动惯量乘 0.5，但面板上显示的是倒数 —— 惯量减半
## 意味着转起来快一倍，写「灵敏 ×2.00」比写「惯量 ×0.50」不容易被误会成降级。
static func display_mult(id: String, level: int) -> float:
	match id:
		"engine": return pow(ENGINE_PER_LEVEL, float(level))
		"speed": return pow(SPEED_PER_LEVEL, float(level))
		"fuel": return 1.0 + FUEL_PER_LEVEL * float(level)
		"agility": return 1.0 / agility_mult(level)
	return 1.0


static func engine_mult(level: int) -> float:
	return pow(ENGINE_PER_LEVEL, float(level))


static func speed_mult(level: int) -> float:
	return pow(SPEED_PER_LEVEL, float(level))


static func fuel_mult(level: int) -> float:
	return 1.0 + FUEL_PER_LEVEL * float(level)


static func agility_mult(level: int) -> float:
	return 1.0 - AGILITY_PER_LEVEL * float(level)


## 把等级换算成倍率乘到车身上。全部是「乘在当前值上」，Lv.0 时是恒等变换。
##
## **「极速」是齿比改动，不是单纯把转速上限调高。** `max_wheel_speed` 涨多少倍，
## `motor_strength` 就除多少倍：静止时单轮推力 = max_wheel_speed × motor_strength / 轮半径，
## 一涨一降正好抵消，推力不变。
##
## 为什么必须这么绕一下：推重比超过 [constant WHEELIE_LINE] 倍车就会后仰翻车（见 README
## 「调爬坡能力时看推力自重比」）。如果极速也直接推高推力，那么「引擎满级 × 极速满级」
## 就是 1.216 × 1.262 = 1.53 倍，玩家把两项练满反而把车练废了 —— 花了 1300 币换来一台
## 一踩油门就翻的车。做成齿比之后，**推重比只由引擎一项决定**，倍率是 1.216。
##
## 注意这只是**相对**倍率：绝对值取决于车本身的基数，用 [method stock_thrust_ratio]
## 看原厂车离翘头线还有多少余量（`tests/upgrade_calib.tscn` 的 A 段会报出来）。
##
## 齿比相对基数还额外赚一点：扭矩 = (目标转速 − 当前转速) × 力矩系数。转速上限
## 涨到 1.262 倍、系数降到 1/1.262，在**同一个**当前转速下扭矩反而更高
## （推导：t₀ 是基准目标转速，升级后 = (1.262·t₀ − ω)/1.262 = t₀ − ω/1.262 > t₀ − ω）。
## 也就是说中高速段扭矩更大、爬坡更快，只有静止那一瞬间的推力持平。
## 实测见 tests/upgrade_calib.tscn。
static func apply(car: HillCar, levels: Dictionary) -> void:
	var engine := engine_mult(level_of(levels, "engine"))
	var speed := speed_mult(level_of(levels, "speed"))
	car.max_wheel_speed *= speed
	car.motor_strength *= engine / speed
	car.fuel_max *= fuel_mult(level_of(levels, "fuel"))
	car.inertia_scale *= agility_mult(level_of(levels, "agility"))


## 推重比 = 各轮静止推力之和 ÷ 整车重量。超过 [constant WHEELIE_LINE] 车就会后仰翻车。
const WHEELIE_LINE := 1.45
## Godot 2D 默认重力，用来把质量换算成重量。
const GRAVITY := 980.0

static var _bases := {}


## 某辆原厂车的马达基数与整车重量，第一次调用时从**那辆车自己的场景**读出来并缓存。
##
## **这里以前是复制一份常量**（转速 30 / 扭矩 60000 / 轮半径 21 / 整车重量 174），
## 靠 upgrade_calib 的 A 段断言去抓「改了车忘了改这里」。实测证明那样不够：
## 把 `max_wheel_speed` 从 30 调到 80 之后，车库页脚还在按 30 算，显示
## 「推重比 1.005 绿色安全」，而真车已经是 2.68 —— 面板说安全、实车已经翻，
## 而且只有跑测试的时候才会发现。改成运行时读场景，以后调车显示自动跟着变。
##
## 读取**整段委托给 [method Vehicles.stats]**：那边已经有「质量 = 车架 + 全部轮子、
## 半径取轮子碰撞形状」的完整推导，而且是 `Vehicles` 自己的场景知识。这里再读一遍
## 节点路径（曾经是写死的 `Chassis` / `RearWheel` / `FrontWheel` / `RearWheel/Shape`）
## 就等于同一件事两份实现 —— 独轮车没有 `FrontWheel`，那种写死会在加车的第一天
## 就崩在 `get_node` 上，而不是给出一个错的数。**轮子是几个也由那边说了算。**
##
## 读的是**没进场景树**的实例，`_ready()` 不会跑，所以拿到的是没被 [method apply]
## 改过的原始 `@export` 值。场景加载交给 [method Vehicles.instantiate]：它内部
## 走 `load()` 而不是 `preload()`（原因见那里 —— car.gd 引用了 Upgrades，preload
## 会让两者在脚本编译期互相等待，这段注释原来在这里）。
##
## 按车 id 各存一份：车库页脚显示的是**当前选中那辆**的余量，不是越野车的。
## 换车之后那些数会整套变（巴士的推重比天生就低、独轮车只有一个轮子出力），
## 这是设计如此。
static func base(vehicle_id: String = Vehicles.DEFAULT) -> Dictionary:
	if not _bases.has(vehicle_id):
		var s := Vehicles.stats(vehicle_id)
		if s.is_empty():
			# 场景读不到（打包漏文件），或者那辆车一个轮子都没打分组标记。
			# 给个空表，让调用方走「算不出来」那条路，而不是在这里崩。
			_bases[vehicle_id] = {}
			return {}
		_bases[vehicle_id] = {
			"wheel_speed": s["wheel_speed"],
			"motor_strength": s["motor_strength"],
			"radius": s["radius"],
			"wheels": s["wheels"],
			"weight": s["weight"],
		}
	return _bases[vehicle_id]


## 只升引擎时的推重比。极速是齿比改动，一涨一降抵消，不影响这个数。
##
## **轮数是变量**（独轮车只有一个轮子出力），取 [method base] 里存下来的那个。
##
## `vehicle_id` 放在**最后**并且带默认值：[method apply] 之外的老调用点
## （`tests/upgrade_calib`、`scripts/garage`、`scripts/vehicleselect`）一个都不用改，
## 拿到的一直是越野车的数（两轮 → 和以前写死 2 的结果一模一样）。
static func thrust_ratio(engine_level: int, vehicle_id: String = Vehicles.DEFAULT) -> float:
	var b := base(vehicle_id)
	if b.is_empty():
		return 0.0
	var radius: float = b["radius"]
	var weight: float = b["weight"]
	var speed: float = b["wheel_speed"] * speed_mult(MAX_LEVEL)
	var strength: float = b["motor_strength"] * engine_mult(engine_level) / speed_mult(MAX_LEVEL)
	return float(b["wheels"]) * speed * strength / radius / weight


## 原厂车（全 Lv.0）的推重比。**这个数本身就超过翘头线的话，说明车调得太猛了**
## —— 那是「车调快了但改装倍率没跟着重标」的第一现场。
static func stock_thrust_ratio(vehicle_id: String = Vehicles.DEFAULT) -> float:
	return thrust_ratio(0, vehicle_id)


static func max_thrust_ratio(vehicle_id: String = Vehicles.DEFAULT) -> float:
	return thrust_ratio(MAX_LEVEL, vehicle_id)
