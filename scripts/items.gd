extends RefCounted
class_name Items
## 道具：跑之前花钱买，跑的时候用，**每场每个最多用一次**。
##
## 和 [Maps]、[Upgrades] 一个套路 —— 名字、说明、价格、数值全部集中在这一张表里，
## 存档只存「这一局带了哪几个」和「哪几个已经用掉了」，改平衡不用碰存档代码，
## 也不用碰商店界面（商店是从这张表上排版出来的）。
##
## ## 三道约定
##
## 1. **买了不落盘**，只在内存里活一局（见 [member SaveData.run_items]）。金币是真的
##    扣了，所以购买必须发生在**按「出发」那一刻**，而不是在商店里勾选的时候 ——
##    勾了又退出，一分钱都不该花。
## 2. **每场每个最多用一次**（[method SaveData.use_item] 用掉就置位）。三个都带上
##    也只是各响一次，所以不存在「攒着连按」。
## 3. **防护罩没有按键。** 它是被动挂着的，第一次该判死的翻车自动顶掉（见
##    [method HillCar._on_head_body_entered]）。另外两个是主动按的，各有一个
##    InputMap 动作。

const NITRO := "nitro"
const SHIELD := "shield"
const FUEL := "fuel"

## 展示顺序 = 商店里的卡片顺序。
const IDS: Array[String] = [NITRO, SHIELD, FUEL]

## 三个道具一个价。想分价就把 [method cost_of] 改成查表。
##
## 500 是照「一局能捡多少」定的：地形平均 40 米刷一枚（见
## [constant Pickup.COIN_VALUES]），一枚的期望值**随里程涨**——出生点 62.5 块，
## 2 km 之后 150 块（见 [method Pickup.mean_value_at]）。一趟 1000 米平均下来
## 大约捡到 1710 块 —— 也就是**一件道具约等于三分之一趟**。一次最多带三件
## （1500），刚好是「想全带就得跑一趟半」的量级：带满是有代价的决定，不是随手就勾。
##
## （改金币曲线之前这里写的是 1560 块 / 62.5 一枚。远处的金币值钱了，但前 400 米
## 一点没变，所以这条定价不用跟着动 —— 一趟 1 km 只多了一成。）
const PRICE := 500

## 氮气持续多久（秒）。
const NITRO_TIME := 2.0

## 氮气期间马达力矩的倍率。
##
## **必须连带把力矩限幅一起放大。** [member HillCar.max_torque] 是个常驻限幅
## （见 car.gd 里的说明），只乘 `motor_strength` 的话，多出来的那一截会在
## `clampf` 那一步被原样削掉 —— 现象是「氮气好像没劲」，其实是力矩根本没加上去。
const NITRO_TORQUE := 1.9

## 氮气期间**轮子目标转速**的倍率。
##
## 少了这一项，氮气只是「加速更快」，顶不到更高的速度：马达是把轮子转速拉向
## `throttle × max_wheel_speed` 的，车一旦被推得比轮面线速度还快，两者之差变号，
## 马达就反过来当刹车 —— 推力和马达会当场对打，玩家感觉「按了没反应」。
## 把目标转速一起抬起来，轮子才跟得上。
const NITRO_SPEED := 1.25

## 氮气额外的向前推力，单位是**车重的倍数**（和重力一个量纲）。
##
## 光加力矩的话，后轮一离地氮气就完全没用了 —— 而这张图恰恰是飞起来的时候最想
## 加速。这一项直接推车壳，腾空时照样有效。0.35 g 推两秒大约能挣回 700 px/s，
## 和这个游戏的极速（700~800）是同一个量级：很猛，但没到「按一下就到终点」。
const NITRO_PUSH := 0.35

## 防护罩顶掉一次翻车之后，多少秒之内不再判「车手头着地」。
##
## 复活是**从地面上方掉下去落地的**（见 [constant SHIELD_LIFT]），落地、弹一下、
## 被落点旁边的坡顶一下，都在这一秒半里面 —— 没有这个窗口，玩家会看见「顶掉了
## 一次翻车」之后车当场又没了，而且那次死亡连信号都对不上（同一次接触不会再发
## 一次 `body_entered`）。
const SHIELD_GRACE := 1.5

## 扶正之后保留多少水平速度。留满等于这次翻车毫无惩罚，清零等于原地罚站
## 等着被后面的坡推回来，取中间。
const SHIELD_KEEP := 0.45

## 复活时整车离地面多高（像素）。车从这个高度掉下去落地 —— 和出生时一样，
## 落地那一下不算腾空（见 [member HillCar._has_landed]）。
const SHIELD_LIFT := 46.0

## 防护罩触发后，车在**死亡地右边多少米**复活。
##
## 这 50 米是防护罩真正在卖的东西。原地扶正只是把这一下翻车顶掉，车还卡在让它
## 翻的那段路里，接下来几秒常常是同一个坑把玩家再收一次 —— 花了 500 金币，买到
## 的是「多一次机会再翻一次」。挪到 50 米外的实地上，那个路障才真的过去了。
##
## 也没远到能当传送用：50 米是 0.6 个地形区块（[constant HillTerrain.CHUNK_WIDTH]
## 是 800），只够跨过一段坡或一个坑，不够跳过一整段路。
const SHIELD_RESPAWN_METERS := 50.0

## 临时油箱补多少，占油箱上限的比例。
##
## 按**比例**而不是按绝对值：四辆车的油箱上限差得很远（摩托小、巴士大），
## 一个绝对值在小车上是一整箱、在大车上是一口。
const FUEL_RATIO := 0.5

## 道具表。`action` 为空串的是**被动道具**（没有按键）；`key` / `pad` 只是画在
## HUD 上的提示文案，真正生效的是 InputMap 里同名的动作。
##
## `key` 文案和 project.godot 里的绑定是两份，会漂 —— `tests/shop` 里有一条
## 断言专门盯这个：主动道具的 `action` 必须在 InputMap 里真的存在。
const CATALOG := {
	NITRO: {
		"zh": "氮气加速", "en": "NITRO",
		"zh_note": "按一下，两秒内又推又转", "en_note": "two seconds of extra push and torque",
		"color": Color(0.36, 0.80, 1.0),
		"action": "use_nitro", "key": "1", "pad": "LB",
	},
	SHIELD: {
		"zh": "防护罩", "en": "SHIELD",
		"zh_note": "顶掉第一次翻车，前移 50 米", "en_note": "absorbs one crash, 50 m ahead",
		"color": Color(0.66, 0.94, 0.52),
		"action": "", "key": "—", "pad": "—",
	},
	FUEL: {
		"zh": "临时油箱", "en": "FUEL CAN",
		"zh_note": "按一下补半箱油", "en_note": "refills half a tank on demand",
		"color": Color(1.0, 0.72, 0.28),
		"action": "use_fuel", "key": "2", "pad": "RB",
	},
}


## 表里有没有这个道具。
static func has_item(id: String) -> bool:
	return CATALOG.has(id)


## 取一项的说明；id 不认识时退回氮气那一行（和 [method Maps.get_map] 一个路子：
## 界面上宁可显示错一项，也不要因为一个脏 id 整屏崩掉）。
static func get_item(id: String) -> Dictionary:
	if CATALOG.has(id):
		return CATALOG[id]
	return CATALOG[NITRO]


## 买这几件要多少钱。价格是统一的，所以就是单价 × 件数 ——
## 但**调用方一律走这个函数**，将来要分价只改这里一处。
##
## 先过 [method clean]，所以**重复的 id 只算一次**：这个函数回答的是「这份清单
## 值多少钱」，而清单里同一件写两遍和写一遍是同一份清单（每场每件本来就只有
## 一个，见 [method SaveData.use_item]）。不去重的话，将来哪个调用点忘了先
## `clean` 就会多收一份钱，而那是看不出来的 —— 收对了没人夸，收错了就是玩家的钱。
static func cost_of(ids: Array) -> int:
	return clean(ids).size() * PRICE


## 这件道具要不要按键。被动的那件返回空串。
static func action_of(id: String) -> String:
	return str(get_item(id)["action"])


## 过滤掉不认识的 id，并去重。商店勾选和读存档都过这一道。
##
## 去重是必须的：`{id: true}` 那种写法天然去重，但传进来的可能是个数组，
## 而「同一个道具买两遍」不该收两份钱、也不该给两次使用次数。
static func clean(ids: Array) -> Array:
	var out := []
	for id in ids:
		var s := str(id)
		if has_item(s) and not out.has(s):
			out.append(s)
	return out
