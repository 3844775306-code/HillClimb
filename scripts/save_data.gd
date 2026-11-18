extends Node
## 跨局存档：各图历史最远里程 + 累计金币 + **各车各自的**升级等级 + 选中的地图和车。
##
## 作为 autoload 常驻，存在 user://save.cfg
## （Windows 下即 %APPDATA%\Godot\app_userdata\HillClimbRacing\save.cfg）。
##
## 金币是「实时入账」的：吃到一枚就写一次盘，所以中途 Alt+F4 也不会丢。
## 里程则要等这一局结束（翻车）才结算，因为途中一直在涨。
## 升级等级也是买了就写盘。

const SAVE_PATH := "user://save.cfg"
const SECTION := "record"
const UPGRADE_SECTION := "upgrades"
const MAP_SECTION := "maps"
const VEHICLE_SECTION := "vehicle"
const UNLOCK_SECTION := "unlocked"

## 关掉后所有写入都只留在内存里。测试用：跑一局自动机会开出上千公里的
## 「纪录」，不能让它污染玩家真正的存档。
var persist := true

## **平原**的最远里程，同时也是老存档的兼容字段。
##
## 四张地图的里程没有可比性（雪地打滑、火山费油），所以纪录是按图分开记的，
## 见 [member best_by_map]。这个字段留着是因为：它是加多地图之前唯一的纪录，
## 丢掉玩家的成绩不合适。装载时见 [method _migrate]。
var best_distance := 0
## 当前选中的地图 id。见 [member Maps.IDS]。
var selected_map := Maps.PLAINS
## 选图页那个模式开关：经典还是随机。见 [constant Maps.MODES]。
##
## **和道具相反，这个是落盘的。** 道具不落盘是因为它是消耗品（花没花出去、拿没拿到
## 必须同生共死，见 [member run_items]）；模式只是一个偏好 —— 上次选了随机，
## 下次打开选图页还是随机，那才叫「记住我选的」。
##
## 不是全局的成对字段，就一个字符串，认不出来的值一律退回经典
## （见 [method Maps.normalize_mode]），所以手改坏了存档也不会开出一张怪图。
var map_mode := Maps.MODE_CLASSIC
## 当前选中的车 id。见 [member Vehicles.IDS]。
##
## 和地图不同，**这里没有「老档兼容的价值判断」**：加多车之前只有一辆车，
## 就是默认那辆，所以老存档缺这一段时读回 [constant Vehicles.DEFAULT] 刚好就是
## 玩家原来开的那辆，不用迁移。
var selected_vehicle := Vehicles.DEFAULT
## 各图最远里程：{地图 id: 米}。
var best_by_map := {}
## 各图已经拿到手的成就**个数**：{地图 id: 个数}。见 [Achievements]。
##
## 存「拿到几个」而不是「拿到了哪些」：成就是按里程一个个依次达成的，
## 拿到第 3 个必然也拿到了前两个，一个整数就是完整的信息量。
var achieved_by_map := {}
## 累计金币，跨局累加。
var total_coins := 0
## 升级等级：**{车 id: {升级项 id: 等级}}**。升级项 id 见 [member Upgrades.IDS]。
##
## **按车分开算。** 加多车之前这里是一张平表（`{升级项: 等级}`），现在是每辆车
## 一张。理由和里程纪录不按车分的理由正好相反：
##
##  · 里程纪录不按车分（见 [method select_vehicle]）—— 纪录是「这张图你跑过最远的
##    一次」，按车分等于惩罚玩家换车。
##  · 升级按车分 —— 升级是「你给这台车投了多少钱」。四辆车的基数差着好几倍
##    （巴士 701、摩托 900、赛车 1254），同一套等级在不同车上根本不是一个意思。
##    共享的话，练满一辆车等于白送另外三辆，换车就成了「带着神装换个壳」。
##
## **别直接下标取值**，用 [method levels_of]：车表里新加的车在老存档里没有这一段，
## 直接下标会拿到 null 然后在别处炸。写盘和读盘都遍历 [member Vehicles.IDS]。
var levels := {}

## 花钱买下来的地图：**{地图 id: true}**。见 [member Maps.IDS]。
##
## **只记买过的那些**，开局白送的那几张（[method Maps.is_free]）不往里写 ——
## 于是「往表里加一张免费图」这种改动，老存档自动就是解锁的，不用写迁移。
## 判「能不能开」一律走 [method map_unlocked]，别直接查这个字典。
var bought_maps := {}
## 花钱买下来的车：**{车 id: true}**。见 [member Vehicles.IDS]。规矩同上。
var bought_vehicles := {}

## 这一局带着的道具：**{道具 id: true}**。id 见 [member Items.IDS]。
##
## **故意不落盘。** 道具是消耗品，买了就为这一局服务 —— 写进 cfg 的话，
## 花 500 块买完直接 Alt+F4，钱扣了、道具还在档里，下次开局白送一件；
## 而如果不扣钱就写盘，那又变成「退出重进白拿道具」。两边都不对。
##
## 所以金币和道具**不写成一次盘**：购买发生在按「出发」那一刻（见
## [method buy_run_items]），扣钱和装载在内存里一起做完，**同一帧就跳场景**。
## 中途退出的唯一后果是这 500 块没花出去、道具也没拿到，谁都不吃亏。
##
## 道具活到这一局结束（[method HillGame._on_car_crashed] 里清掉）：翻车之后按 R
## 重开是**没有道具**的，因为上一局已经把它们用掉了。想再带就回商店重买。
var run_items := {}

## 这一局已经用掉的道具：**{道具 id: true}**。开局清空（见 [method begin_run]）。
##
## 和 [member run_items] 分开记，是因为「带了」和「用掉了」在界面上是两种样子：
## HUD 上要能看出哪件还没按、哪件已经响过了。
var used_items := {}


## 某辆车的升级等级表，缺的时候**现场建一份全 0 的**。
##
## 「读的时候顺手写」是有意的：这样每一个调用点都不必先问「这辆车有没有买过」，
## 也不会有人拿到 null。返回的是**引用**，改它就是改存档里那份（[method buy_upgrade]
## 靠这个落盘）。
func levels_of(vehicle_id: String) -> Dictionary:
	if not levels.has(vehicle_id) or not (levels[vehicle_id] is Dictionary):
		var fresh := {}
		for id in Upgrades.IDS:
			fresh[id] = 0
		levels[vehicle_id] = fresh
	return levels[vehicle_id]


## **当前选中那辆车**的等级表。车是照着 [member selected_vehicle] 造出来的
## （见 [method HillGame._enter_tree] 里的换车），所以这拿到的就是正在开的那辆车的。
func current_levels() -> Dictionary:
	return levels_of(selected_vehicle)


func _ready() -> void:
	load_data()


## 清空进度，回到全新档的状态（包括升级）。供调试和测试用。
func reset_progress() -> void:
	best_distance = 0
	best_by_map.clear()
	achieved_by_map.clear()
	for id in Maps.IDS:
		best_by_map[id] = 0
		achieved_by_map[id] = 0
	selected_map = Maps.PLAINS
	map_mode = Maps.MODE_CLASSIC
	selected_vehicle = Vehicles.DEFAULT
	total_coins = 0
	# 买过的图/车也一起清掉：全新档就是「前四张图 + 越野/摩托」。
	bought_maps.clear()
	bought_vehicles.clear()
	levels.clear()
	for v in Vehicles.IDS:
		levels_of(v)
	run_items.clear()
	used_items.clear()
	save_data()


func load_data() -> void:
	levels.clear()
	for v in Vehicles.IDS:
		levels_of(v)
	# 道具不在文件里，所以「从盘上读一遍」就等于把它们清掉 —— 这正是想要的：
	# 函数名说的是「内存里的一切都以盘上那份为准」，盘上没有的就不该留着。
	run_items.clear()
	used_items.clear()
	best_by_map.clear()
	achieved_by_map.clear()
	for id in Maps.IDS:
		best_by_map[id] = 0
		achieved_by_map[id] = 0

	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_distance = int(cfg.get_value(SECTION, "best_distance", 0))
	total_coins = int(cfg.get_value(SECTION, "total_coins", 0))
	# 老存档没有 [upgrades] 段，get_value 会给回默认值 0，等于原厂车
	for v in Vehicles.IDS:
		var lv := levels_of(v)
		for id in Upgrades.IDS:
			lv[id] = clampi(int(cfg.get_value(
					UPGRADE_SECTION, upgrade_key(v, id), legacy_level(cfg, v, id)
			)), 0, Upgrades.MAX_LEVEL)
	selected_map = str(cfg.get_value(MAP_SECTION, "selected", Maps.PLAINS))
	if not Maps.has_map(selected_map):
		selected_map = Maps.PLAINS
	# 老存档没有这个键 → 读到经典，正是它本来就一直在玩的那个模式。
	map_mode = Maps.normalize_mode(str(cfg.get_value(MAP_SECTION, "mode", Maps.MODE_CLASSIC)))
	# 老存档没有 [vehicle] 段 → 读到默认值（就是原来那辆车）。
	# 校验用 has_vehicle 而不是 available()：available() 会去 load 场景资源，
	# 而**装档的时候不该碰场景树**。ids 表里有、场景却缺失，是打包缺文件，
	# 那种情况由 Vehicles.instantiate 的兜底去处理。
	selected_vehicle = str(cfg.get_value(VEHICLE_SECTION, "selected", Vehicles.DEFAULT))
	if not Vehicles.has_vehicle(selected_vehicle):
		selected_vehicle = Vehicles.DEFAULT
	for id in Maps.IDS:
		best_by_map[id] = int(cfg.get_value(MAP_SECTION, "best_" + id, 0))
		# 老存档没有这一段 → 读到 0，等于「还没拿过任何成就」。
		# **不回填**「按历史纪录本该拿到的那些」：回填要么白送一笔钱（如果发奖），
		# 要么给出一个永远领不到钱的成就（如果不发奖），两种都别扭。跑起来自然就会
		# 重新经过 500 / 1000 …… 一路领回来。
		achieved_by_map[id] = maxi(0, int(cfg.get_value(MAP_SECTION, "ach_" + id, 0)))
	# 买过的图/车：和道具一样，**先清空再读** —— 盘上没有的就是没买过。
	bought_maps.clear()
	bought_vehicles.clear()
	for id in Maps.IDS:
		if bool(cfg.get_value(UNLOCK_SECTION, "map_" + id, false)):
			bought_maps[id] = true
	for v in Vehicles.IDS:
		if bool(cfg.get_value(UNLOCK_SECTION, "car_" + v, false)):
			bought_vehicles[v] = true
	_migrate()
	_grandfather()
	_repair_locked_selection()


## 老存档（没有 [maps] 段）的处理。
##
## 那时候只有一个全局纪录，就把它算作平原的成绩 —— 平原本来就是当时的唯一地图，
## 这样玩家的最高分不会凭空蒸发。判据是「[maps] 段一个数都没有」，而不是
## 「best_by_map 全为 0」：后者在新档里也成立，但对新档做迁移是无害的空操作，
## 而对一个真的把平原跑到 0 米的档来说也没损失，所以两个判据都安全，
## 用前者只是为了少读一次盘。
func _migrate() -> void:
	var any := 0
	for id in Maps.IDS:
		any += int(best_by_map[id])
	if any > 0 or best_distance <= 0:
		return
	best_by_map[Maps.PLAINS] = best_distance


## 加了付费解锁之前就存在的老档：**玩过的就算已解锁**（和玩家确认过的那条规则）。
##
##  · 图：这张图有纪录（[method best_of] > 0）就白送。玩家在上面跑过成绩，把成绩
##    锁在 50000 后面说不过去。
##  · 车：任何一项升级花过钱（等级 > 0），或者它**正是存档里选中那辆**，就白送。
##    后者单列是因为「选中但没升级」是可能的 —— 刚买来还没改就退出了。
##
## **幂等，所以不判「有没有 `[unlocked]` 段」**：全新档三项条件一个都不满足，跑一遍
## 是空操作；而判段存在与否反而要区分「老档」和「买了第一张图之后的新档」两种
## 情形，多一处会漂的判据。
##
## **这里只改内存、不写盘**（和 [method _migrate] 一样）：装档的时候不该有副作用，
## 而且这份判断每次装档重算一遍的结论都一样。要等下一次 [method save_data] 才落地。
func _grandfather() -> void:
	for id in Maps.IDS:
		if best_of(id) > 0:
			bought_maps[id] = true
	for v in Vehicles.IDS:
		if v == selected_vehicle:
			bought_vehicles[v] = true
			continue
		for id in Upgrades.IDS:
			if level_of(id, v) > 0:
				bought_vehicles[v] = true
				break


## 选中的图/车是锁着的时候，换回免费的默认那张/那辆。
##
## 什么时候会撞上：老档正好停在黑夜图上（它现在要 50000），或者手改过 cfg，
## 或者以后调整了 [constant Maps.FREE_COUNT]。不修的话玩家一按「继续」就开进
## 一张没解锁的图 —— 而那是**界面之外**的入口，选图界面拦不住它。
##
## 和 [method _grandfather] 一样只改内存不写盘。
func _repair_locked_selection() -> void:
	if not map_unlocked(selected_map):
		selected_map = Maps.PLAINS
	if not vehicle_unlocked(selected_vehicle):
		selected_vehicle = Vehicles.DEFAULT


func save_data() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "best_distance", best_distance)
	cfg.set_value(SECTION, "total_coins", total_coins)
	cfg.set_value(MAP_SECTION, "selected", selected_map)
	cfg.set_value(MAP_SECTION, "mode", map_mode)
	cfg.set_value(VEHICLE_SECTION, "selected", selected_vehicle)
	for id in Maps.IDS:
		cfg.set_value(MAP_SECTION, "best_" + id, int(best_by_map.get(id, 0)))
		cfg.set_value(MAP_SECTION, "ach_" + id, int(achieved_by_map.get(id, 0)))
	# 只写带车名前缀的新键。老的无前缀键（`engine=3`）**故意不写**：下次存盘它们就
	# 从文件里消失了，[method legacy_level] 那条兼容路径只用一次。
	for v in Vehicles.IDS:
		var lv := levels_of(v)
		for id in Upgrades.IDS:
			cfg.set_value(UPGRADE_SECTION, upgrade_key(v, id), int(lv.get(id, 0)))
	# 只写买过的：免费的靠 [method Maps.is_free] / [method Vehicles.is_free] 推出来，
	# 写进去的话「以后把某张图改成免费」就多一批要清理的旧键。
	for id in Maps.IDS:
		if bought_maps.has(id):
			cfg.set_value(UNLOCK_SECTION, "map_" + id, true)
	for v in Vehicles.IDS:
		if bought_vehicles.has(v):
			cfg.set_value(UNLOCK_SECTION, "car_" + v, true)
	cfg.save(SAVE_PATH)


## 某项升级在 `[upgrades]` 段里的键名。
##
## 用 `车id/升级项id` 而不是「一辆车一个 section」：section 名里带车 id 的话，
## 枚举「存档里有哪些车」得去读 section 列表，而这里固定遍历 [member Vehicles.IDS]
## 更省事，也和上面 `best_<地图>` 那套写法是一个路子。
##
## ConfigFile 的键名不解析 `/`，原样读写，不会被当成路径。
func upgrade_key(vehicle_id: String, id: String) -> String:
	return vehicle_id + "/" + id


## 老存档的兼容读法：加多车之前只有一辆车，就是默认那辆，所以 `[upgrades]` 里
## 那些**没有车名前缀**的键（`engine=3`）都是默认车的等级。
##
## 挂到默认车名下，玩家的升级不会凭空蒸发。别的车一律读 0（它们当时还不存在）。
## **这里只读不写**：新格式写盘之后这些键自然就没了，这条路径只会走一次。
func legacy_level(cfg: ConfigFile, vehicle_id: String, id: String) -> int:
	if vehicle_id != Vehicles.DEFAULT:
		return 0
	return int(cfg.get_value(UPGRADE_SECTION, id, 0))


## 某张地图的最远纪录。
func best_of(map_id: String) -> int:
	return int(best_by_map.get(map_id, 0))


## 结算一局的里程，返回是否破了该图的纪录。
##
## 必须带地图 id：四张图的里程不可比，混着记会让雪地的成绩永远看不见天日。
func submit_distance(meters: int, map_id: String) -> bool:
	if meters <= best_of(map_id):
		return false
	best_by_map[map_id] = meters
	if map_id == Maps.PLAINS:
		# 兼容字段跟着平原走，老版本的存档读出来还是对的
		best_distance = maxi(best_distance, meters)
	save_data()
	return true


## 某张地图已经拿到手的成就个数。见 [Achievements]。
func achieved_of(map_id: String) -> int:
	return int(achieved_by_map.get(map_id, 0))


## 里程到了就把新达成的成就**一次结算掉**：标记已领 + 发钱，返回这一趟新拿到几个。
##
## 判据用的是**传进来的里程**，不是 `best_by_map`。纪录要等这一局翻车才结算
## （见 [method submit_distance]），而成就得在跑过 500 米那一刻当场发 —— 玩家
## 正是为了那一瞬间的飘字才继续往前开的。地图 id 同理必须显式传：
## 四张图的成就各算各的，雪地跑 500 米不该把平原的成就顶掉。
##
## 两个要点：
##
##  · **一次跨过好几个也照发**（`while` 那样一个个补，而不是只看当前这一个）。
##    极速下 500 米大约 5 秒，一帧跨过一个不奇怪；debug 传送更是一次跨一串。
##  · 标记和金币**在同一次写盘里落地**。分两次写（先标记、再发钱）中间崩掉，
##    玩家就是「成就点亮了、钱没到」；反过来先发钱再标记，崩一次就能反复领。
##    和 [method buy_upgrade] 同一条规矩：内存里一起改完，最后只写一次盘。
##
## 返回新拿到的**个数**；钱已经进了 [member total_coins]，调用方不要再补一次。
func claim_achievements(meters: int, map_id: String) -> int:
	var want := Achievements.index_at(float(meters))
	var got := achieved_of(map_id)
	if want <= got:
		return 0
	achieved_by_map[map_id] = want
	total_coins += Achievements.reward_for(want - got)
	save_data()
	return want - got


## 换地图。选中状态是存档的一部分，下次开局还是这张图。
func select_map(map_id: String) -> void:
	if not Maps.has_map(map_id) or map_id == selected_map:
		return
	selected_map = map_id
	save_data()


## 换车。和 [method select_map] 一样，选中状态是存档的一部分。
##
## 里程纪录**不按车分**：纪录是「这张图你跑过最远的一次」，和开什么车无关
## （按车分的话，换一辆没开过的车，纪录就归零了，那是惩罚玩家换车）。
func select_vehicle(vehicle_id: String) -> void:
	if not Vehicles.has_vehicle(vehicle_id) or vehicle_id == selected_vehicle:
		return
	selected_vehicle = vehicle_id
	save_data()


## 换玩法模式（经典 / 随机）。和 [method select_map] 一样是存档的一部分。
##
## **认不出来的值退回经典而不是拒绝写入**：这个函数唯一的调用方是选图页那两格，
## 传进来的一定是 [member Maps.MODES] 里的值；万一哪天不是了，玩家该看到的是
## 「回到经典」，而不是一个按了没反应的开关。
func set_map_mode(mode: String) -> void:
	mode = Maps.normalize_mode(mode)
	if mode == map_mode:
		return
	map_mode = mode
	save_data()


# ---------------------------------------------------------------- 解锁
#
# 图：前 [constant Maps.FREE_COUNT] 张白送，其余每张 [constant Maps.UNLOCK_PRICE]
# 金币。车：前 [constant Vehicles.FREE_COUNT] 辆白送，其余每辆
# [constant Vehicles.UNLOCK_PRICE]。价格表在 [Maps] / [Vehicles] 里，**不在这里** ——
# 那边是「这张图/这辆车值多少」，这边只管收钱。
#
# ## 界面上的买法是两下
#
# 第一下只是**把光标挪到这张卡上**，第二下才真扣钱。一次点中就买的话，翻页浏览的
# 时候手指擦过一张 50000 的图就没了。所以界面那边（选图 / 选车）的点击处理是一条
# 三段式：点箭头 → 翻页；点没选中的卡 → 选中；点**已经选中的锁卡** → 才 [method
# unlock_map]。这里这几个函数本身不管光标，只回答「买不买得起」。
#
# 钱和标记**一次写盘**，和 [method buy_upgrade] 同一条规矩。


## 这张图能开吗（免费的算能开）。
##
## **判「能不能开」只走这里**，不要直接查 [member bought_maps] —— 那个字典里只有
## 花钱买的那些，免费图不在里面。
func map_unlocked(map_id: String) -> bool:
	return Maps.is_free(map_id) or bought_maps.has(map_id)


func vehicle_unlocked(vehicle_id: String) -> bool:
	return Vehicles.is_free(vehicle_id) or bought_vehicles.has(vehicle_id)


## 解锁这张图要花多少；**已经解锁的返回 0**。
##
## 和 [method Maps.price_of]（「这张图标价多少」）分开：界面要的是「还得掏多少」，
## 而已解锁的图上不该再显价钱。返回 0 同时也就成了「这张卡是通的」的判据，
## 界面那边一句 `if price > 0` 就够，不用再问一遍 [method map_unlocked]。
func map_price(map_id: String) -> int:
	return 0 if map_unlocked(map_id) else Maps.price_of(map_id)


func vehicle_price(vehicle_id: String) -> int:
	return 0 if vehicle_unlocked(vehicle_id) else Vehicles.price_of(vehicle_id)


## 买下一张图。买不起、已经解锁、不认识的 id 都返回 false。
##
## 和 [method buy_upgrade] 同一条规矩：**标记和扣钱在内存里一起改完，最后只写一次盘**。
## 拆成两次写（先扣钱再标记）中间崩掉，玩家就是「钱没了、图还锁着」。
##
## **不顺手改 [member selected_map]**：买和选是两件事，选哪张由界面决定
## （玩家点的那张卡本来就已经是光标所在的那张）。
func unlock_map(map_id: String) -> bool:
	if not Maps.has_map(map_id) or map_unlocked(map_id):
		return false
	if total_coins < Maps.price_of(map_id):
		return false
	total_coins -= Maps.price_of(map_id)
	bought_maps[map_id] = true
	save_data()
	return true


func unlock_vehicle(vehicle_id: String) -> bool:
	if not Vehicles.has_vehicle(vehicle_id) or vehicle_unlocked(vehicle_id):
		return false
	if total_coins < Vehicles.price_of(vehicle_id):
		return false
	total_coins -= Vehicles.price_of(vehicle_id)
	bought_vehicles[vehicle_id] = true
	save_data()
	return true


## 金币入账（可为负）。升级扣费不走这里，见 [method buy_upgrade]。
func add_coins(amount: int) -> void:
	if amount == 0:
		return
	total_coins += amount
	save_data()


## 下面四个都带一个可省的 `vehicle_id`：**空字符串 = 当前选中的那辆车**。
##
## 车库面板只操作选中那辆车，所以它一个参数都不传；测试要摆弄别的车时才传。
## 空串而不是把 `selected_vehicle` 写成默认值 —— GDScript 的默认值必须是常量
## 表达式，读不到成员变量。
func which(vehicle_id: String) -> String:
	return vehicle_id if vehicle_id != "" else selected_vehicle


func level_of(id: String, vehicle_id: String = "") -> int:
	return Upgrades.level_of(levels_of(which(vehicle_id)), id)


## 下一级的花销；已满级返回 0。
func upgrade_cost(id: String, vehicle_id: String = "") -> int:
	return Upgrades.cost(level_of(id, vehicle_id))


func can_afford(id: String, vehicle_id: String = "") -> bool:
	var price := upgrade_cost(id, vehicle_id)
	return price > 0 and total_coins >= price


## 买一级。买不起或已满级返回 false。
##
## 等级和金币在内存里一起改完，**最后只写一次盘**。要是拆成「先扣钱存盘、
## 再升级存盘」，中间崩掉就会留下钱扣了、等级没给的坏档。
##
## 钱是共用的（[member total_coins] 不按车分），等级是按车的 —— 换车之后
## 金币带得走，投进去的改装带不走。这正是「换车 = 换一台车重新练」的意思。
func buy_upgrade(id: String, vehicle_id: String = "") -> bool:
	if not can_afford(id, vehicle_id):
		return false
	var price := upgrade_cost(id, vehicle_id)
	var v := which(vehicle_id)
	levels_of(v)[id] = level_of(id, v) + 1
	total_coins -= price
	save_data()
	return true


# ---------------------------------------------------------------- 道具

## 这一局带了哪些道具（数组，按 [member Items.IDS] 的顺序）。
##
## **按 [member Items.IDS] 的顺序**而不是 `run_items.keys()` 的顺序：字典的键序
## 是插入序，勾选的先后会改变 HUD 上道具栏的排列 —— 同一个背包，勾选顺序不同
## 就换个画法，看着像出了 bug。
func run_item_ids() -> Array:
	var out := []
	for id in Items.IDS:
		if run_items.has(id):
			out.append(id)
	return out


## 这一局带着这件道具吗（不管用没用掉）。
func has_item(id: String) -> bool:
	return run_items.has(id)


## 这件道具**这一局已经用掉了**吗。
func item_used(id: String) -> bool:
	return used_items.has(id)


## 花掉这一局的一次使用机会。**带没带、用没用过，全在这里判**。
##
## 返回 true 表示「这次真的用出去了」，调用方才该产生效果。三个道具（含被动的
## 防护罩）都走这一个入口，所以「每场每个最多一次」这条规则只有一份实现 ——
## 三个地方各判一遍的话，早晚有一个忘了判。
func use_item(id: String) -> bool:
	if not run_items.has(id) or used_items.has(id):
		return false
	used_items[id] = true
	return true


## 开局。清掉「已用掉」的标记，道具本身留着 —— 它们就是为这一局买的。
##
## 必须由关卡在开局时调，**不能放在 [method buy_run_items] 里**：翻车之后按 R
## 重开走的是 `reload_current_scene()`，不经过商店，那时 [member run_items] 已经
## 被清空了（见 [method end_run]），再清一次 used 也不会凭空变出道具来。
func begin_run() -> void:
	used_items.clear()


## 一局结束。道具是用掉的消耗品，这局完了就没了。
##
## 在 [method HillGame._on_car_crashed] 里调。**顺序要紧**：结束面板要显示这一局
## 带了什么，所以 HUD 得先拿到数据（它每帧从 [member run_items] 读，不缓存），
## 于是这里清完，面板上那一条也就跟着消失了 —— 这是有意的，道具栏和「这一局结束」
## 一起收摊，玩家一眼就知道东西没了。
func end_run() -> void:
	run_items.clear()
	used_items.clear()


## 结算一次购买：把这几件道具装进这一局，并**当场扣钱**。
##
## 买不起（或一件都没勾）返回 false，什么都不改。
##
## 扣钱和装载在内存里一起做完，**最后只写一次盘** —— 和 [method buy_upgrade] 同一条
## 规矩。拆成「先扣钱存盘、再装道具」的话，中间崩掉就是钱没了、道具也没了。
##
## 重复的 id 会被 [method Items.clean] 去掉：同一个道具勾两遍不该收两份钱，
## 反正「每场最多用一次」也让它没有意义。
func buy_run_items(ids: Array) -> bool:
	var want := Items.clean(ids)
	if want.is_empty():
		return false
	var price := Items.cost_of(want)
	if total_coins < price:
		return false
	run_items.clear()
	for id in want:
		run_items[id] = true
	used_items.clear()
	total_coins -= price
	save_data()
	return true
