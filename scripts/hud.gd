extends Control
class_name HillHud
## 抬头显示：里程 / 金币 / 油量，以及结束面板。
##
## 所有内容都用 [method CanvasItem.draw_string] 画，所以字体要自己准备 ——
## Godot 自带的默认字体没有中文字形，系统里找不到中文字体时整体回退成英文。
##
## ## 两套版面
##
## [member touch] 为真时改用手机版面：左下右下两个角让给
## [HillTouchControls] 的两个踏板，**底边那三样东西各自挪窝** ——
##
##  · 油条：从左下角挪到**底边正中**（两个踏板之间那条 300 像素的空档）。
##  · 道具栏：从右下角挪到油条**正上方**、横向居中（右下角是油门踏板）。
##  · 仪表盘：往上抬 [constant HillDashboard.BOTTOM_MARGIN_TOUCH]（同理由它自己管）。
##
## 结束面板另加四个能点的按钮（桌面版有键盘，不加）。**没有一处是靠「大概不会撞上」
## 摆的**：三样东西的位置都由纯函数给（[method fuel_rect] / [method items_rect] /
## [method HillDashboard.cluster_rect]），tests/mobile 拿这三个矩形和踏板对撞，撞上就红。

const PANEL_BG := Color(0.07, 0.09, 0.13, 0.55)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.97, 0.98, 1.0, 0.72)
const GOLD := Color(1.0, 0.84, 0.24)
const SKY := Color(0.62, 0.90, 1.0)

## 顶栏四列的列宽与字号。
const COL := 220.0
const LABEL_SIZE := 20
const VALUE_SIZE := 44
## 腾空奖励飘字停留多久。
const AIR_FLASH_TIME := 0.9
## 腾空奖励飘字的字号和上飘距离。
##
## **这条飘字画在屏幕正中央，和另外四条（左边那一列）不是一伙的** —— 用户原话：
## 「这种特殊奖励金币的词条改为显示在屏幕正中央」。所以它不该再跟着 [constant COL]
## 那一列排队，字也得比它们大：2.5 秒以上的滞空是这几条奖励里最难凑的，飘在
## 正中央、比空翻那条（34）还大一档，才看得出来「这次不一样」。
##
## 上飘只给 [constant AIR_FLASH_RISE]，比另外四条（34）小 —— 正中央那几个像素
## 一动，视线就跟着跑，而这条是要「一眼看到」的。
const AIR_FLASH_SIZE := 46
const AIR_FLASH_RISE := 22.0
## 正中央那行字的描边宽度和颜色。**不加描边读不出来**：这里是屏幕正中，背后
## 可能是亮天的雪地、也可能是黑掉的黑夜，金色压在雪地上几乎看不见。
const AIR_FLASH_OUTLINE := 7
const AIR_FLASH_SHADOW := Color(0.10, 0.08, 0.02, 0.85)
## 空翻飘字停留多久。比腾空那条长一些 —— 一次 300 块，值得看清楚。
const FLIP_FLASH_TIME := 1.2
## 成就飘字停留多久。最长的 —— 500 米才出一个，一条飘字要顶到 2 秒，
## 否则玩家低头看一眼油量就错过了。
const ACHIEVE_FLASH_TIME := 2.0
## 独轮飘字停留多久。和空翻一样长 —— 也是三位数（75 块）。
const WHEELIE_FLASH_TIME := 1.2
## 道具生效飘字停留多久。
const ITEM_FLASH_TIME := 1.4
## 右上角那行地图名的基线和字号。
##
## **提成常量是因为别人要拿它让位**：手机版面的暂停键挂在右上角，顶边必须落到
## 这行字下面（见 [constant HillTouchControls.PAUSE_BTN_Y]）。这两个数只活在
## [method _draw_stats] 里的话，那边就只能凭「大概不会撞上」写一个 74 ——
## 而 tests/mobile 也拿不到真东西比对。
const MAP_NAME_BASELINE := 50.0
const MAP_NAME_SIZE := 28
## 道具栏一格的大小和间距。
const ITEM_W := 150.0
const ITEM_H := 34.0
const ITEM_GAP := 10.0
## 手机版面上道具栏离屏幕底边的距离。要**让开正下方那条油条**：油条在
## `size.y - 46`（高 26，顶边 46+26=72），加它自己那行「燃油」小字再往上 12，
## 道具栏落在 120 那一行，中间还剩 20 像素。
const ITEM_LIFT_TOUCH := 120.0
## 车灯按钮那格的宽和高。高取 [constant HillHud.fuel_rect] 那个油条的 26 ——
## 手机版面上这两个是并排的一条线，高出半像素都看得出来。
const HEADLIGHT_W := 150.0
const HEADLIGHT_H := 26.0
## 手机版面上车灯按钮和油条之间的空档。
const HEADLIGHT_GAP := 12.0

## 结束面板上那几行字的纵向位置（相对屏幕中心）。
##
## **两套各一份**：手机版面要整体上移，把底下 208 像素让给四个按钮
## （见 [method gameover_buttons]）。写成表而不是写死在各处，
## 是为了让「上移」只需要改这张表，正文那几行不用动。
const OVER_ROWS := {
	"title": -90.0,
	"stats": 0.0,
	"best": 60.0,
	"record": 120.0,
	"ach": 150.0,
	"hint": 180.0,
}
const OVER_ROWS_TOUCH := {
	"title": -150.0,
	"stats": -60.0,
	"best": -6.0,
	"record": 44.0,
	"ach": 74.0,
	# 手机版面不画这行字：键盘提示在手机上没意义，那四个按钮就是它的替代品。
	"hint": 0.0,
}
## 结束面板上四个按钮，2×2 摆，顺序 = 画出来的顺序。
const OVER_BUTTONS := [
	{"id": "restart", "zh": "再跑一局", "en": "RUN AGAIN"},
	{"id": "vehicle", "zh": "换车", "en": "CAR"},
	{"id": "map", "zh": "换地图", "en": "MAPS"},
	{"id": "garage", "zh": "回车库改装", "en": "GARAGE"},
]
const OVER_BTN_W := 300.0
const OVER_BTN_H := 74.0
const OVER_BTN_GAP := 20.0
const OVER_BTN_TEXT := 26
var _font: Font
var _cjk := false
## 手机版面：见文件头「两套版面」。
var _touch := false
var _car: HillCar
## 右下角的仪表盘。**子节点，不是画在这里** —— 表针每帧都在动，见 [HillDashboard]。
var _dashboard: HillDashboard
## 本局地图，只用来显示名字和取该图的纪录。
var _map_id := Maps.PLAINS
## 本局是不是随机模式（见 [constant Maps.MODES]）。随机模式**没有可比的最远纪录** ——
## 顶栏那一列和结束面板上那一行都要跟着改口，不然玩家会拿着经典模式的纪录去比一张
## 随手摇出来的地图（见 [method _draw_stats] 和 [method _draw_game_over]）。
var _random := false

var _coins := 0
var _distance := 0
var _over := false
var _reason := ""
var _new_record := false
## 腾空奖励飘字的剩余时间，以及飘的是多少。
var _air_flash := 0.0
var _air_amount := 0
## 空翻飘字的剩余时间、金额、以及是不是后空翻。
##
## **单开一份状态，不和腾空那条共用**：连翻的时候两条会同时出现（腾空的整拍
## 和第一圈往往就差几帧），共用的话后到的会盖掉先到的。画的位置也错开一行。
var _flip_flash := 0.0
var _flip_amount := 0
var _flip_back := true
## 成就飘字的剩余时间、飘的是哪个里程碑、以及发了多少。
##
## 同样**单开一份**，理由和空翻那条一样：一次跨过好几个成就时（见
## [method SaveData.claim_achievements]）两者会同时出现，共用状态会被盖掉。
var _ach_flash := 0.0
var _ach_meters := 0
var _ach_amount := 0
## 独轮飘字的剩余时间、金额、以及是不是后轮独走。
##
## **同样单开一份**：后轮独走紧接着一个空翻是常见连招，两者会同时出现。
var _wheelie_flash := 0.0
var _wheelie_amount := 0
var _wheelie_rear := true
## 道具生效飘字：剩余时间 + 是哪一件（见 [member Items.IDS]）。
var _item_flash := 0.0
var _item_id := ""
## 本局拿到了几个成就，只在结束面板上报。由 [method show_game_over] 传进来。
var _run_achievements := 0


## [param touch] 为真时用手机版面（见文件头）。默认 false，所以老调用点
## （测试里那些 `hud.setup(car)`）一行都不用改，行为也和加手机版之前一致。
func setup(car: HillCar, map_id: String = Maps.PLAINS, touch: bool = false,
		random: bool = false) -> void:
	_car = car
	_map_id = map_id
	_touch = touch
	_random = random
	_font = UiFonts.load_cjk_font()
	_cjk = _font != null
	if not _cjk:
		_font = get_theme_default_font()
		push_warning("未找到中文字体，界面回退为英文。可在 scripts/ui_fonts.gd 里补充字体路径。")
	_setup_dashboard()


## 建/刷新右下角那个仪表盘。
##
## **建在代码里，没有对应的 .tscn**：它跟 HUD 是同生共死的（换车、重开一局都会重新
## `setup`），挂在场景里反而要 [HillGame] 多知道一个节点、多传一次车。
##
## 字体是从上面那份**传进去**的，不让它自己去 [`UiFonts.load_cjk_font`] ——
## 那个函数要读几 MB 的系统字体文件，一局里加载两遍纯属浪费。
func _setup_dashboard() -> void:
	if _dashboard == null:
		_dashboard = HillDashboard.new()
		_dashboard.name = "Dashboard"
		# 铺满整个视口：两个表盘是按 [member size] 从右下角往回排的，
		# 所以窗口一变形它自己就跟着挪，不用谁去通知。
		_dashboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# 它整块都是装饰，不能吃掉鼠标 —— 结束面板的「点一下再跑一局」还等着收点击。
		_dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_dashboard)
	_dashboard.setup(_car, _font, _cjk, _touch)
	_dashboard.visible = not _over


## 本层用的字体。给 [HillTouchControls] 复用，理由和上面传给仪表盘的一样：
## 那个字体文件几 MB，一层加载一遍纯属浪费。
func ui_font() -> Font:
	return _font


func ui_has_cjk() -> bool:
	return _cjk


## 仪表盘占的那块矩形。给版面测试用（见 tests/mobile 的「两套版面不许打架」）。
##
## **触屏版面三个角都让给了踏板，没有一处是靠「大概不会撞上」摆的** ——
## 这个函数就是把仪表盘也拉进那场比对里，而不是只在注释里说一句「它挪上去了」。
func dashboard_cluster() -> Rect2:
	if _dashboard == null:
		return Rect2()
	return _dashboard.cluster_rect()


## 腾空满一节时在屏幕正中央飘一下「+50 腾空」（金额见 [constant HillCar.AIR_BONUS_TIERS]）。
func flash_air_bonus(amount: int) -> void:
	_air_flash = AIR_FLASH_TIME
	_air_amount = amount
	queue_redraw()


## 转满一圈时飘一下「+300 后空翻」。
func flash_flip(amount: int, back: bool) -> void:
	_flip_flash = FLIP_FLASH_TIME
	_flip_amount = amount
	_flip_back = back
	queue_redraw()


## 拿到里程成就时飘一下「★ 500 米成就 +500」。`meters` 是刚跨过的那个里程碑。
func flash_achievement(meters: int, amount: int) -> void:
	_ach_flash = ACHIEVE_FLASH_TIME
	_ach_meters = meters
	_ach_amount = amount
	queue_redraw()


## 独轮行驶满一节时飘一下「+75 独轮」。
func flash_wheelie(amount: int, rear: bool) -> void:
	_wheelie_flash = WHEELIE_FLASH_TIME
	_wheelie_amount = amount
	_wheelie_rear = rear
	queue_redraw()


## 用掉一件道具时飘一下它的名字。
func flash_item(id: String) -> void:
	_item_flash = ITEM_FLASH_TIME
	_item_id = id
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	if _air_flash > 0.0:
		_air_flash = maxf(0.0, _air_flash - delta)
		dirty = true
	if _flip_flash > 0.0:
		_flip_flash = maxf(0.0, _flip_flash - delta)
		dirty = true
	if _ach_flash > 0.0:
		_ach_flash = maxf(0.0, _ach_flash - delta)
		dirty = true
	if _wheelie_flash > 0.0:
		_wheelie_flash = maxf(0.0, _wheelie_flash - delta)
		dirty = true
	if _item_flash > 0.0:
		_item_flash = maxf(0.0, _item_flash - delta)
		dirty = true
	if dirty:
		queue_redraw()


func refresh(coins: int, distance: int) -> void:
	_coins = coins
	_distance = distance
	queue_redraw()


func show_game_over(reason: String, coins: int, distance: int, new_record: bool,
		achievements: int = 0) -> void:
	_over = true
	_reason = reason
	_coins = coins
	_distance = distance
	_new_record = new_record
	_run_achievements = achievements
	# 把仪表盘收起来。它是**子节点**，画在 HUD 自己后面（Godot 里孩子盖在父母之上），
	# 不收的话两个表针会浮在结束面板的遮罩上面，看着像没擦干净。
	if _dashboard != null:
		_dashboard.visible = false
	queue_redraw()


## 中文文案，找不到中文字体时退回英文。
func _t(zh: String, en: String) -> String:
	return zh if _cjk else en


func _draw() -> void:
	if _car == null:
		return
	_draw_stats()
	_draw_fuel()
	_draw_headlights()
	_draw_air_flash()
	_draw_flip_flash()
	_draw_wheelie_flash()
	_draw_achieve_flash()
	_draw_item_flash()
	if _over:
		_draw_game_over()
	else:
		# 道具栏**只在跑的时候画**：这一局结束会把道具收走
		# （见 [method SaveData.end_run]），画了也是空的。
		_draw_items()


## 顶栏四列：本次里程 / 本次金币 / 本图最远 / 累计金币。
## 后两项由存档提供（[SaveData] 是 autoload，直接读即可，不必逐层传参）。
##
## 纪录取的是**本图**的，不是全局的：雪地打滑、火山费油，四张图的里程没有可比性，
## 混着记会让雪地的成绩永远看不见天日。
func _draw_stats() -> void:
	var pos := Vector2(30.0, 52.0)
	var best := SaveData.best_of(_map_id)
	_stat(pos, 0, _t("里程", "DISTANCE"), "%d m" % _distance, TEXT)
	_stat(pos, 1, _t("金币", "COINS"), str(_coins), GOLD)
	# 破纪录的那一刻当场顶上去，不用等翻车结算。
	# 随机模式这一列改成明说「不记」：那一格的数（经典模式的纪录）和本局根本
	# 不是一回事，留着它等于摆一个玩家永远追不上的目标在那儿。
	if _random:
		_stat(pos, 2, _t("随机地形", "RANDOM"), _t("不记", "NO BEST"), TEXT_DIM)
	else:
		_stat(pos, 2, _t("本图记录", "BEST"), "%d m" % maxi(best, _distance), GOLD if _distance > best else SKY)
	_stat(pos, 3, _t("金币总数", "TOTAL COINS"), str(SaveData.total_coins), GOLD)

	# 右上角挂本局地图名。四列排到 x≈760 为止，右边是空的，不会撞上。
	var map := Maps.get_map(_map_id)
	draw_string(_font, Vector2(0.0, MAP_NAME_BASELINE), _t(map["zh"], map["en"]),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 30.0, MAP_NAME_SIZE, TEXT_DIM)


## 腾空奖励飘字：**屏幕正中央**，往上飘一点点就淡出。
##
## 位置是 [member Control.size] 的一半，不是写死的 640/360 —— 手机上那块屏幕是
## 竖的，写死会飘到屏幕外。y 要减掉半行字高：`draw_string` 的 y 是**基线**，
## 直接给中心点的话整行字会偏在中心下面小半行。
func _draw_air_flash() -> void:
	if _air_flash <= 0.0:
		return
	var fade := _air_flash / AIR_FLASH_TIME
	var rise := (1.0 - fade) * AIR_FLASH_RISE
	var text := _t("+%d 腾空", "+%d AIR") % _air_amount
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, AIR_FLASH_SIZE)
	var at := size * 0.5 + Vector2(-extent.x * 0.5, _font.get_ascent(AIR_FLASH_SIZE) * 0.5) - Vector2(0.0, rise)
	var color := GOLD
	color.a = fade
	var shadow := AIR_FLASH_SHADOW
	shadow.a *= fade
	# 先描边后填色：反过来描边会把填色的边啃掉一圈，字看着变细。
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			AIR_FLASH_SIZE, AIR_FLASH_OUTLINE, shadow)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, AIR_FLASH_SIZE, color)


## 空翻飘字：画在腾空飘字**下面一行**（飘起来之后也刚好不撞上，见 [constant FLIP_FLASH_TIME]）。
## 字号比腾空大一档 —— 300 块比 25 块值得显眼。
func _draw_flip_flash() -> void:
	if _flip_flash <= 0.0:
		return
	var fade := _flip_flash / FLIP_FLASH_TIME
	var rise := (1.0 - fade) * 34.0
	var at := Vector2(30.0 + COL, 182.0 - rise)
	var color := GOLD
	color.a = fade
	var zh := "+%d 后空翻" if _flip_back else "+%d 前空翻"
	var en := "+%d BACKFLIP" if _flip_back else "+%d FRONTFLIP"
	draw_string(_font, at, _t(zh, en) % _flip_amount,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, color)


## 成就飘字：画在空翻飘字下面一行，字号最大、颜色最亮 —— 这是三条飘字里最难得的一条。
func _draw_achieve_flash() -> void:
	if _ach_flash <= 0.0:
		return
	var fade := _ach_flash / ACHIEVE_FLASH_TIME
	var rise := (1.0 - fade) * 34.0
	var at := Vector2(30.0 + COL, 226.0 - rise)
	var color := GOLD
	color.a = fade
	draw_string(_font, at,
			_t("★ %d 米成就  +%d" % [_ach_meters, _ach_amount],
				"★ %d m ACHIEVED  +%d" % [_ach_meters, _ach_amount]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, color)


## 独轮飘字：画在空翻飘字**下面一行**，字号和空翻一样（也是三位数）。
func _draw_wheelie_flash() -> void:
	if _wheelie_flash <= 0.0:
		return
	var fade := _wheelie_flash / WHEELIE_FLASH_TIME
	var rise := (1.0 - fade) * 34.0
	var at := Vector2(30.0 + COL, 270.0 - rise)
	var color := GOLD
	color.a = fade
	var zh := "+%d 后轮独走" if _wheelie_rear else "+%d 前轮独走"
	var en := "+%d WHEELIE" if _wheelie_rear else "+%d NOSE RIDE"
	draw_string(_font, at, _t(zh, en) % _wheelie_amount,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, color)


## 道具生效飘字：画在最下面一行，**用道具自己的颜色** —— 三条奖励都是金色，
## 这一条要是也金色就分不出「挣了钱」和「花了钱的东西响了」。
func _draw_item_flash() -> void:
	if _item_flash <= 0.0:
		return
	var it := Items.get_item(_item_id)
	var fade := _item_flash / ITEM_FLASH_TIME
	var rise := (1.0 - fade) * 34.0
	var at := Vector2(30.0 + COL, 314.0 - rise)
	var color: Color = it["color"]
	color.a = fade
	draw_string(_font, at, "▸ " + _t(str(it["zh"]), str(it["en"])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 32, color)


## 道具栏：右下角横排，一格一件。
##
## **顺序走 [method SaveData.run_item_ids]，不走 `run_items.keys()`**：字典的键序
## 是插入序，勾选先后会改变这里的排列 —— 同一个背包换个画法，看着像出了 bug。
##
## 被动的防护罩也给一格（按键位显示「—」）：它虽然不用按，但玩家得知道
## 自己身上有一层罩子，不然那 500 块花得无声无息。
## 道具栏整排的矩形。**纯函数**，理由同 [method fuel_rect]。
## 一件道具都没有时返回零矩形（测试里要跳过比对）。
##
## 办公桌版面在右下角，手机版面挪到油条正上方、横向居中（右下角是油门踏板）。
func items_rect() -> Rect2:
	var ids := SaveData.run_item_ids()
	if ids.is_empty():
		return Rect2()
	var n := ids.size()
	var w := float(n) * ITEM_W + float(n - 1) * ITEM_GAP
	var y := size.y - 54.0 if not _touch else size.y - ITEM_LIFT_TOUCH
	var x := size.x - 30.0 - w if not _touch else (size.x - w) * 0.5
	return Rect2(Vector2(x, y), Vector2(w, ITEM_H))


func _draw_items() -> void:
	var ids := SaveData.run_item_ids()
	if ids.is_empty():
		return
	var n := ids.size()
	var row := items_rect()
	var x0 := row.position.x
	var y := row.position.y
	draw_string(_font, Vector2(x0, y - 12.0), _t("道具", "ITEMS"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_DIM)
	for i in n:
		var id: String = ids[i]
		var it := Items.get_item(id)
		var used := SaveData.item_used(id)
		var col: Color = it["color"]
		var r := Rect2(Vector2(x0 + float(i) * (ITEM_W + ITEM_GAP), y), Vector2(ITEM_W, ITEM_H))
		# 用掉的那一格压低透明度：还能看见，但一眼就知道是空的。
		draw_rect(r, Color(col.r, col.g, col.b, 0.08 if used else 0.20))
		draw_rect(r, Color(col.r, col.g, col.b, 0.25 if used else 0.85), false, 2.0)

		draw_string(_font, r.position + Vector2(9.0, 24.0), str(it["key"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 19, TEXT_DIM if used else col)
		var label := _t("已用", "USED") if used else _t(str(it["zh"]), str(it["en"]))
		draw_string(_font, r.position + Vector2(36.0, 24.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT_DIM if used else TEXT)


func _stat(pos: Vector2, col: int, label: String, value: String, color: Color) -> void:
	var at := pos + Vector2(COL * float(col), 0.0)
	draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, TEXT_DIM)
	draw_string(_font, at + Vector2(0.0, 40.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_SIZE, color)


## 油条的矩形。**纯函数**：画它的人、和测试「踏板有没有压到它」的人，
## 读的是同一份坐标（见文件头「两套版面」）。
##
## 办公桌版面在左下角（原来就在那儿），手机版面挪到**底边正中**：左下右下两个角
## 都被踏板占了，中间那条 300 像素的空档正好放下它。
func fuel_rect() -> Rect2:
	var bar := Vector2(300.0, 26.0)
	if _touch:
		return Rect2(Vector2((size.x - bar.x) * 0.5, size.y - 46.0), bar)
	return Rect2(Vector2(30.0, size.y - 60.0), bar)


func _draw_fuel() -> void:
	var pos := fuel_rect().position
	var bar := fuel_rect().size
	var ratio := clampf(_car.fuel / _car.fuel_max, 0.0, 1.0)

	draw_rect(Rect2(pos + Vector2(4.0, 4.0), bar), Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(Rect2(pos, bar), PANEL_BG)

	var color := Color(0.26, 0.86, 0.38)
	if ratio < 0.3:
		color = Color(0.96, 0.68, 0.16)
	if ratio < 0.15:
		color = Color(0.93, 0.24, 0.20)
	draw_rect(Rect2(pos + Vector2(4.0, 4.0), Vector2((bar.x - 8.0) * ratio, bar.y - 8.0)), color)
	draw_rect(Rect2(pos, bar), Color(1.0, 1.0, 1.0, 0.32), false, 2.0)

	draw_string(_font, pos + Vector2(0.0, -10.0), _t("燃油", "FUEL"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_DIM)
	draw_string(_font, pos + Vector2(bar.x + 16.0, 20.0), "%d%%" % int(round(ratio * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_DIM)

	# 键盘提示只在桌面版面画：手机上这两个键根本不存在，那行字只会占掉踏板的位置。
	if not _touch:
		draw_string(
			_font,
			Vector2(30.0, size.y - 96.0),
			_t("→ / D 前进    ← / A 倒车", "RIGHT / D  gas    LEFT / A  brake"),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			20,
			TEXT_DIM
		)


## 车灯开关那格的矩形。**纯函数**，理由同 [method fuel_rect]。
##
## **不是黑夜图、或者这一局已经结束，就返回零矩形**，于是不画、也点不着。
## 后者不只是好看：结束面板上「随便点哪儿都是再跑一局」，按钮留在那儿的话，
## 右上角那一片点下去会变成开灯 —— 玩家以为自己在重开，其实只把灯关了。
##
## 测试那边的 `_overlaps` 本来就会跳过零矩形（见 [code]tests/mobile.gd[/code]），
## 「这张图用不上」不用特判。
##
## 桌面版面在**右上角、地图名下面**：四列统计排到 x≈800 就没了，那一块是空的
## （引擎默认视口 1152 时按钮左沿 972，还空着一百多像素）。不挂在油条旁边是因为
## 那一行右边紧接着就是那个百分数（`bar.x + 16`），摆过去会压字。
##
## 手机版面**并排贴在油条左边**：右下角是油门踏板、左下角是刹车，中间那条空档
## 放得下（视口 1280 时按钮 328~478，左踏板到 204 为止；引擎默认 1152 时按钮
## 264~414，左踏板还是到 204，还有 60 像素）。**坐标从油条推出来**，不各写一份：
## 油条挪了位置，车灯得跟着走，否则两个就散了。
func headlight_rect() -> Rect2:
	if _over or not Maps.is_night(_map_id):
		return Rect2()
	var box := Vector2(HEADLIGHT_W, HEADLIGHT_H)
	if _touch:
		var bar := fuel_rect()
		var right := bar.position.x - HEADLIGHT_GAP
		return Rect2(Vector2(right - box.x, bar.position.y), box)
	return Rect2(Vector2(size.x - 30.0 - box.x, 74.0), box)


## 点在这格车灯按钮上吗。给 [method HillGame._unhandled_input] 用。
##
## 手机上没有键盘，这一格**就是**手机上唯一的车灯开关；
## 桌面上空格和它走同一个入口（[method HillCar.toggle_headlights]），
## 所以两条路不会各自跑偏。
func headlight_button_at(pos: Vector2) -> bool:
	var r := headlight_rect()
	return r.size.x > 0.0 and r.has_point(pos)


## 车灯那格：左边是状态（开 / 关），右边（桌面版面）是键位提示。
##
## **状态从车上读**（[member HillCar.headlights_on]），不在这儿存一份 ——
## 存两份的话，按空格开灯、这一格还写着「关」，下一帧玩家就会以为自己看错了。
func _draw_headlights() -> void:
	var r := headlight_rect()
	if r.size.x <= 0.0:
		return
	var on := _car.headlights_on
	var tint := Color(0.99, 0.93, 0.58)
	draw_rect(r, Color(tint.r, tint.g, tint.b, 0.26 if on else 0.07))
	draw_rect(r, Color(tint.r, tint.g, tint.b, 0.90 if on else 0.34), false, 2.0)
	draw_string(_font, r.position + Vector2(9.0, 20.0),
			_t("车灯 开", "LIGHTS ON") if on else _t("车灯 关", "LIGHTS OFF"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, tint if on else TEXT_DIM)
	# 键位提示只在桌面版面画：手机上那一格本身就是按钮，写「空格」没有人按得到。
	if not _touch:
		draw_string(_font, r.position + Vector2(9.0, 20.0), _t("空格", "SPACE"),
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 18.0, 16, TEXT_DIM)


func _draw_game_over() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.09, 0.62))

	var center := size * 0.5
	var title := _t("结束了", "GAME OVER")
	if _reason == HillCar.REASON_CRASH:
		title = _t("翻车了！", "NECK BROKEN!")
	elif _reason == HillCar.REASON_FUEL:
		title = _t("没油了！", "OUT OF FUEL!")
	elif _reason == HillCar.REASON_DROWN:
		title = _t("淹死了！", "DROWNED!")
	elif _reason == HillCar.REASON_BURN:
		title = _t("烧死了！", "BURNED ALIVE!")
	elif _reason == HillCar.REASON_FALL:
		title = _t("摔下去了！", "FELL TO THE BOTTOM!")
	elif _reason == HillCar.REASON_CEILING:
		title = _t("撞到洞顶了！", "HIT THE CEILING!")

	var map := Maps.get_map(_map_id)
	var map_name := _t(map["zh"], map["en"])
	# 两套版面只差这张纵向位置表（见 [constant OVER_ROWS_TOUCH]）。
	var rows := OVER_ROWS_TOUCH if _touch else OVER_ROWS
	_center_text(Vector2(0.0, center.y + float(rows["title"])), title, 60, Color(1.0, 0.42, 0.32))
	_center_text(Vector2(0.0, center.y + float(rows["stats"])),
			_t("本次里程 %d m      金币 %d" % [_distance, _coins],
				"DISTANCE %d m      COINS %d" % [_distance, _coins]), 34, TEXT)
	# 随机模式这一行不报纪录（那一局的里程没写进存档，见 [method HillGame._on_car_crashed]），
	# 改成明说「这一局不计成绩」—— 玩家得知道自己刚才那一趟为什么没上纪录榜。
	if _random:
		_center_text(Vector2(0.0, center.y + float(rows["best"])),
				_t("%s 随机地形 · 本局不计纪录      金币总数 %d" % [map_name, SaveData.total_coins],
					"%s RANDOM MAP - THIS RUN DOES NOT COUNT      TOTAL COINS %d"
							% [map_name, SaveData.total_coins]),
				30, TEXT_DIM)
	else:
		_center_text(Vector2(0.0, center.y + float(rows["best"])),
				_t("%s 记录 %d m      金币总数 %d" % [map_name, SaveData.best_of(_map_id), SaveData.total_coins],
					"%s BEST %d m      TOTAL COINS %d" % [map_name, SaveData.best_of(_map_id), SaveData.total_coins]),
				30, SKY)
	# 位置固定，不因为要不要显示新纪录而让下面的提示跳来跳去
	if _new_record:
		_center_text(Vector2(0.0, center.y + float(rows["record"])), _t("新纪录！", "NEW RECORD!"), 34, GOLD)
	# 本局的成就数（跨局的总数在顶栏那一列里看不到，这里补一句这一局挣了多少）。
	# 空着的行不画，也不占位：下面那句提示的位置本来就是固定的。
	if _run_achievements > 0:
		_center_text(Vector2(0.0, center.y + float(rows["ach"])),
				_t("本局达成成就 %d 个  +%d" % [_run_achievements, Achievements.reward_for(_run_achievements)],
					"%d ACHIEVEMENTS THIS RUN  +%d" % [_run_achievements, Achievements.reward_for(_run_achievements)]),
				28, GOLD)
	if _touch:
		# 手机上没键盘，那三件事（换车 / 换地图 / 回车库）**只能**靠能点的按钮。
		_draw_over_buttons()
	else:
		_center_text(Vector2(0.0, center.y + float(rows["hint"])),
				_t("R / 点击  再跑一局    V  换车    M  换地图    G  回车库改装",
					"R / CLICK  RUN AGAIN   V  CAR   M  MAPS   G  GARAGE"), 26, TEXT_DIM)


## 结束面板上那四个按钮的矩形。**纯函数**：画的、命中测试的、测试里比对踏板有没有
## 压到它的，读的都是这一份。2×2 摆在底边上方，整体离底 40 像素。
##
## 桌面版面返回空数组 —— 那边有键盘，多摆四个按钮只会把画面压得更满，
## 于是 game.gd 收点击那条路也自动退回老行为（点哪儿都是再跑一局）。
func gameover_buttons() -> Array:
	if not _touch or not _over:
		return []
	var total := Vector2(OVER_BTN_W * 2.0 + OVER_BTN_GAP, OVER_BTN_H * 2.0 + OVER_BTN_GAP)
	var x := (size.x - total.x) * 0.5
	var y := size.y - 40.0 - total.y
	var out := []
	for i in OVER_BUTTONS.size():
		var col := i % 2
		var row := 0 if i < 2 else 1
		out.append({
			"id": String(OVER_BUTTONS[i]["id"]),
			"rect": Rect2(x + float(col) * (OVER_BTN_W + OVER_BTN_GAP),
					y + float(row) * (OVER_BTN_H + OVER_BTN_GAP), OVER_BTN_W, OVER_BTN_H),
		})
	return out


## 这个位置上是不是某个结束面板按钮。返回 id，没命中返回 ""。
func gameover_button_at(pos: Vector2) -> String:
	for item in gameover_buttons():
		if (item["rect"] as Rect2).has_point(pos):
			return String(item["id"])
	return ""


func _draw_over_buttons() -> void:
	# 两份数组的次序是同一个（[constant OVER_BUTTONS] 和 [method gameover_buttons]
	# 都按它的顺序生成），所以按下标取名字就行。
	var rects := gameover_buttons()
	for i in rects.size():
		var r := rects[i]["rect"] as Rect2
		draw_rect(r, Color(0.07, 0.09, 0.13, 0.90))
		draw_rect(r, Color(1.0, 1.0, 1.0, 0.30), false, 3.0)
		draw_string(_font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 10.0),
				_t(String(OVER_BUTTONS[i]["zh"]), String(OVER_BUTTONS[i]["en"])),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, OVER_BTN_TEXT, TEXT)


func _center_text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
