extends Node2D
class_name HillGame
## 关卡总控：串起地形、车、摄像机和 HUD，并处理结束与重开。
##
## 这一层是「组装厂」：地图（[Maps]）和存档（[SaveData]）在这里汇合，再分发给
## 地形、车、背景和 HUD。地形和车都不自己去读存档 —— 它们默认就是平原/无修正，
## 单独拿出来跑测试时行为不会因为玩家存档变了而变。

## 结束面板上按 G 就回这里改装。
const GARAGE_SCENE := "res://scenes/garage.tscn"
## 结束面板上按 M 来换地图。
const MAP_SCENE := "res://scenes/mapselect.tscn"
## 结束面板上按 V 来换车。和 M 一样先回选择界面，选完再选图 —— 换车和换图走同一条路，
## 少一套「记住从哪来的」状态。
const VEHICLE_SCENE := "res://scenes/vehicleselect.tscn"

## 镜头缩放的近端（慢）和远端（快）。
const ZOOM_NEAR := 1.05
const ZOOM_FAR := 0.62
## 对应上两端的车速（px/s）。低于 LO 就是最近，高于 HI 就是最远。
const ZOOM_SPEED_LO := 200.0
const ZOOM_SPEED_HI := 1500.0
## zoom 的平滑系数。和镜头位置一样用指数衰减，保证与帧率无关。
const ZOOM_SMOOTH := 4.0

## 镜头相对**车身中心**的偏移：往前看 [constant CAMERA_LOOK] 像素、往上抬
## [constant CAMERA_LIFT] 像素（屏幕 y 向下，所以「抬」是负的）。
##
## **提成常量是因为别人要拿它算数**：[HillTunnel] 的上壁厚度是从「镜头最多能
## 高过洞顶多少」推出来的（见 tunnel.gd 文件头「上壁必须盖住屏幕上半部分」），
## 那个差就是 `CAMERA_LIFT − 车手头顶高出车身多少`。写死在
## [method _camera_target] 里的话，那边只能抄一个 90 过去。
const CAMERA_LOOK := 150.0
const CAMERA_LIFT := 90.0

@onready var car: HillCar = $Car
@onready var terrain: HillTerrain = $Terrain
@onready var camera: Camera2D = $Camera2D
@onready var background: HillBackground = $Background
@onready var night: HillNight = $Night
@onready var hud: HillHud = $UILayer/HUD

## 手机操作层。桌面上它照样被建出来，只是整层不显示、不吃输入 ——
## 见 [method _setup_touch] 和 [method HillTouchControls.set_enabled]。
var touch: HillTouchControls
## 这台设备要不要手机版面。**存成成员**而不是每次现算：HUD 和它里面的仪表盘排版时
## 都要读它，各处现算一遍就等于有两个真相。
var _touch_device := false

var coins := 0
## 本局拿到了几个成就。**只在结束面板上报，不进存档** —— 存档里存的是
## 「这张图一共拿到过几个」（[member SaveData.achieved_by_map]），那是跨局的。
var run_achievements := 0
var game_over := false
## 本局地图 id。开局时定下来，中途不再变。
var map_id := Maps.PLAINS
## 本局的玩法模式（经典 / 随机）。见 [constant Maps.MODES]。
##
## 开局时定下来，中途不再变 —— 「随机」那一个种子也是开局摇一次就焊死在这一局上，
## 所以**暂停、翻车后重开（`reload_current_scene`）都会重新摇**，而这一局之内
## 地形一动不动。用户要的是「每次玩都不一样」，重开正是「再玩一次」。
var mode := Maps.MODE_CLASSIC
## 本局的车 id。同上。
var vehicle_id := Vehicles.DEFAULT


## 换车和**摆出生点**都必须在这里做，不能等到 `_ready`。两个原因：
##
##  · [member car] 是 `@onready var car: HillCar = $Car`，它在 `_ready` 之前就绑好了。
##    在 `_ready` 里换掉 `$Car`，那个变量还指着已经被释放的旧节点。
##  · 车的两个 [PinJoint2D] 的锚点是在**进树那一刻**按两边刚体的当前位置算好、
##    交给物理服务器的（见 car.gd）。所以位置要在 `add_child` **之前**设好 ——
##    进树之后再摆车，等于给车装了个偏心的轴。
##
## 时机上没问题：`_enter_tree` 是在主节点的 `_enter_tree` 里跑的，那时它的孩子
## 已经**实例化**（所以 `$Car` 找得到）但还没进树；这里换完人，引擎接着按新的
## 孩子表往下传播，新车照常进树、照常收到 `_ready`。
func _enter_tree() -> void:
	vehicle_id = SaveData.selected_vehicle
	# 本局是哪张图。**在这里定而不是 `_ready`**：下面 [_spawn_position] 要用它，
	# 而出生点必须在车进树之前摆好（见上）。
	map_id = SaveData.selected_map
	# **必须写 `as Node2D`。** `get_node_or_null` 的静态类型是 `Node`，`Node` 上没有
	# `position`／`z_index`，下面 `var spawn := old.position` 于是推不出类型
	# ——「Cannot infer the type of "spawn" variable」，**整份 game.gd 直接解析失败**，
	# 主场景的脚本装不上。这个错只在**冷解析**（没命中编译缓存）时冒出来：跑起来的
	# 时候看不出，改过脚本、或者编辑器重新保存一次就会全盘炸掉，然后所有测试都报
	# 「Trying to assign value of type 'Node2D' to a variable of type 'game.gd'」。
	var old := get_node_or_null("Car") as Node2D
	if old == null:
		return
	# 出生点的高度按**这张图**的出生地面折一下，然后才轮到换不换车。
	old.position = _spawn_position(old.position)
	# 默认车不换：场景里摆好的那辆就是它（出生点上面已经摆好了），
	# 一个字节都不动，行为与加多车之前**完全一致**。
	if vehicle_id == Vehicles.DEFAULT:
		return
	var replacement := Vehicles.instantiate(vehicle_id)
	if replacement == null:
		# 场景文件缺失（打包漏了 / id 不认识）。`Vehicles.instantiate` 到这时已经
		# 退回默认车了，场景里也本来就是默认车，所以照样能开。
		push_warning("换车失败，继续开默认车：%s" % vehicle_id)
		vehicle_id = Vehicles.DEFAULT
		return

	# 这四样是从主场景的 Car 节点上抄过来的（见 scenes/main.tscn）：
	# 节点名、出生点位置、画在车身之上（z_index）、还有它在兄弟里的次序。
	#
	# **名字必须显式顶上。** [member car] 是 `@onready var car: HillCar = $Car`，
	# 它在 `_ready` 里才求值 —— 换进来的摩托节点自己叫 "Moto"，`$Car` 会找不到，
	# 于是 `car` 是 null，`_ready` 第 97 行 `car.apply_map()` 当场崩。这里的
	# `remove_child` 只是把 "Car" 这个名字**腾出来**，不会自动给新车改名。
	var spawn := old.position
	var z := old.z_index
	var index := old.get_index()
	var node_name := old.name
	remove_child(old)
	old.queue_free()
	replacement.name = node_name
	replacement.position = spawn
	replacement.z_index = z
	add_child(replacement)
	move_child(replacement, index)


## 出生点的位置：**高度跟着这张图的出生地面一起挪。**
##
## 场景里写的是 `position = Vector2(200, 340)`（见 scenes/main.tscn），那个 `y` 是
## 「**经典图**的地面（`GROUND_Y` = 420）之上 80 像素」—— 一个**绝对**高度。
## 别的图出生地面也在 `GROUND_Y` 上，所以照搬没事。
##
## **彩虹图的出生台面架在 `GROUND_Y + Maps.pad_dy()` 上（高 400 像素）**
## （理由见 [constant Maps.PAD_DY]），照搬 `340` 就是**把车摆进出生台的实心
## 多边形里**：车头那个传感器一进树就撞上地面（[method HillCar._on_head_body_entered]
## 直接发 `crashed`），**开局第一帧就死**。用户报的「刚开始时彩虹地图车就在云里
## 立即死亡」就是这个 —— 彩虹图那块平地的填色是 [method Maps.get_map] 的 `dirt`
## （`0.80, 0.84, 0.97`，一整块惨白），车嵌在里面看着就是「埋在云里」。
##
## 挪的量正好是 `Maps.pad_dy(map_id)`：场景给的 `y` 里已经含着「离地面 80 像素」，
## 而出生地面从 `GROUND_Y` 挪到 `GROUND_Y + pad_dy`，所以 `y` 跟着挪同一个数 ——
## **离地多高一个像素都没改**，车落地前那一小段照旧会掉（和
## [method HillCar._respawn_shift] 同一个观感）。
##
## [method Maps.pad_dy] 也被铺地块多边形那一处和 `height_at` 那一处问着：
## 三处只要有一处各算各的，车就会生在实心多边形里。
func _spawn_position(pos: Vector2) -> Vector2:
	return Vector2(pos.x, pos.y + Maps.pad_dy(map_id))


func _ready() -> void:
	# `map_id` 已经在 `_enter_tree` 里定好了（出生点要用它，而出生点只能在车进树
	# 之前摆 —— 见那里）；这里只补上玩法模式。
	mode = SaveData.map_mode
	var palette := Maps.get_map(map_id)

	# **种子要在 `terrain.map_id` 和 set_target 之前定。** 下面那句 `set_target` 会当场把出生点
	# 附近的区块建出来，而区块是按种子建的 —— 设晚了会先按上一个种子建一轮、
	# 再被 setter 里的 `_rebuild()` 全部拆掉重建（白跑一遍，而且第一帧的
	# `height_at` 给的是旧地形）。
	#
	# 经典模式写死 [constant Maps.CLASSIC_SEED]（**显式写，不靠场景里的默认值**：
	# 纪录榜上那些数字长在哪个地形上，必须是这个脚本说了算），随机模式每局现摇一个。
	terrain.world_seed = (Maps.CLASSIC_SEED if mode == Maps.MODE_CLASSIC
			else Maps.random_seed())

	# 地形和车都得在第一个物理帧之前拿到地图。地形的 map_id 要在 set_target 之前
	# 设好 —— 区块是按地图的噪声和配色建的，设晚了会先按平原建一轮再全部拆掉重建。
	terrain.map_id = map_id
	RenderingServer.set_default_clear_color(palette["sky"])
	car.apply_map(map_id)

	# 先给地形一个跟随目标，它才会立刻把出生点附近的区块建出来。
	terrain.set_target(car.chassis)
	terrain.pickup_collected.connect(_on_pickup_collected)
	car.crashed.connect(_on_car_crashed)
	car.air_bonus.connect(_on_air_bonus)
	car.flip_bonus.connect(_on_flip_bonus)
	car.wheelie_bonus.connect(_on_wheelie_bonus)
	car.item_used.connect(_on_item_used)
	# 开局。道具是**这一局**的：把「已经用掉」的标记清掉，道具本身留着 ——
	# 它们正是为这一局买的（见 [method SaveData.begin_run]）。
	SaveData.begin_run()
	background.setup(camera, map_id)
	# 手机版面得在 HUD 排版**之前**定下来：HUD 自己（油条、道具栏、结束面板）和它里面
	# 的仪表盘都要按这个布尔量选择摆法（见 hud.gd 文件头「两套版面」）。
	_touch_device = HillTouchControls.is_touch_device()
	hud.setup(car, map_id, _touch_device, mode == Maps.MODE_RANDOM)
	_setup_touch()
	# 黑夜图的挡布：跟着**车壳**走（和 [method HillTerrain.set_target] 同一个节点），
	# 非黑夜图它自己会 `visible = false`。这一行漏掉的话，黑夜图什么都不挡 ——
	# 挡布的 `_draw` 只在 `visible` 为真时才跑（见 scripts/night.gd）。
	night.setup(car.chassis, map_id)
	camera.global_position = _camera_target()
	camera.zoom = Vector2.ONE * _zoom_target()
	_refresh_hud()


## 建手机操作层。**建在代码里，没有对应的 .tscn**，理由和 HUD 里的仪表盘一样
## （见 [method HillHud._setup_dashboard]）：它跟这一局同生共死，挂在场景里反而要
## [HillGame] 多知道一个节点。
##
## 挂在 UILayer 上、**排在 HUD 后面**：Control 是按树的次序画的，后加的画在上面，
## 于是两个踏板盖在 HUD 的边角之上，而不是被它压住。
func _setup_touch() -> void:
	touch = HillTouchControls.new()
	touch.name = "Touch"
	hud.get_parent().add_child(touch)
	touch.setup(hud.ui_font(), hud.ui_has_cjk(), _touch_device)
	touch.pause_action.connect(_on_pause_action)


## 暂停菜单里点了「重开」/「返回选图」。那两条路径本来就归这一层管（见顶上三个常量），
## 操作层不认识它们。**解暂停它自己已经先做过了**（见 [method HillTouchControls._request]），
## 这里只管换场景。
func _on_pause_action(id: String) -> void:
	match id:
		HillTouchControls.ACTION_RESTART:
			get_tree().reload_current_scene()
		HillTouchControls.ACTION_MAP:
			get_tree().change_scene_to_file(MAP_SCENE)


func _process(delta: float) -> void:
	if not game_over:
		# 指数衰减插值，与帧率无关。
		camera.global_position = camera.global_position.lerp(_camera_target(), 1.0 - exp(-6.0 * delta))
		var zoom := _zoom_target()
		camera.zoom = camera.zoom.lerp(Vector2.ONE * zoom, 1.0 - exp(-ZOOM_SMOOTH * delta))
	# 成就检查**不放在 `not game_over` 里面**：车正好在跨过 500 米那一帧翻车时，
	# 这一帧的里程已经定格，漏掉就永远少一个成就。翻车之后里程不再涨，
	# 多检查几帧也只是白看两眼（已领过的会立刻返回）。
	_check_achievements(distance_meters())
	_refresh_hud()


## 摄像机看向车头前方，并限制在地面以上，免得冲下坡时镜头钻到地里。
##
## 地面高度用 [method HillTerrain.skyline_at] 而不是 `height_at`：沟和火山口上方
## 它给的是坑沿高度，否则镜头会跟着坑底往下掉，跳之前看不见对岸。
##
## **彩虹图不做这个钳位。** 那张图里「头顶上的那块天花板」随时可能是车上方两百米的
## 一块平台；照它钳位的话，车在低处跑、镜头被顶到带子最上面那块平台上面去，
## 屏幕里只剩天空和车底下一小截 —— 而这恰恰是一张「往下看才知道落在哪」的图。
## 那张图的相机就老实跟着车走。
func _camera_target() -> Vector2:
	var target := car.chassis.global_position + Vector2(CAMERA_LOOK, -CAMERA_LIFT)
	if Maps.shape_of(map_id) != Maps.SHAPE_ARCHES:
		target.y = minf(target.y, terrain.skyline_at(target.x) - 130.0)
	return target


## 车速越慢镜头越近，越快拉得越远：慢的时候看得清车和细节，快的时候看得见
## 前面的坡，不至于一头撞上去才知道。
func _zoom_target() -> float:
	var speed := car.chassis.linear_velocity.length()
	var t := clampf((speed - ZOOM_SPEED_LO) / (ZOOM_SPEED_HI - ZOOM_SPEED_LO), 0.0, 1.0)
	return lerpf(ZOOM_NEAR, ZOOM_FAR, t)


func _refresh_hud() -> void:
	hud.refresh(coins, distance_meters())


func distance_meters() -> int:
	return int(Maps.meters_at(car.max_distance))


func _on_pickup_collected(kind: String, amount: float) -> void:
	if kind == "fuel":
		car.add_fuel(amount)
	else:
		_award(int(round(amount)))


## 腾空奖励：飞满 2.5 秒之后每 0.5 秒发一节，越久越值钱 —— 50 / 100 / 200，
## 超过 8 秒停发（档位表见 [constant HillCar.AIR_BONUS_TIERS]，金额已经由金币
## 那边算好了，这里只管入账和飘字）。
##
## 飘字走的是屏幕正中央那条，和空翻 / 独轮 / 成就那几条挤在左边一列的不一样
## （见 [method HillHud.flash_air_bonus]）。
func _on_air_bonus(bonus: int) -> void:
	_award(bonus)
	hud.flash_air_bonus(bonus)


## 空翻奖励：空中转满一圈 300 块。
func _on_flip_bonus(bonus: int, back: bool) -> void:
	_award(bonus)
	hud.flash_flip(bonus, back)


## 独轮奖励：一个轮子独自着地骑满 2 秒 75 块。
func _on_wheelie_bonus(bonus: int, rear: bool) -> void:
	_award(bonus)
	hud.flash_wheelie(bonus, rear)


## 用掉了一件道具。**不发钱也不扣钱** —— 钱在商店里买的时候就付过了
## （见 [method SaveData.buy_run_items]），这里只让 HUD 飘一条字告诉玩家
## 「这件响了」，顺便让它把道具栏那一格画成已用。
func _on_item_used(id: String) -> void:
	hud.flash_item(id)


## 里程成就：每张地图每 500 米一个，一个档只领一次（见 [SaveData.claim_achievements]）。
##
## 钱是在存档那边**和「已领取」一起**写盘的，一次落地、不会只落一半，
## 所以这里只把本局计数器补上，**不能再调 [method _award]** —— 那会发第二遍。
##
## **随机模式一个都不领**（见 [constant Maps.MODES]）：成就是「这张图你跑到了 500 米」
## 的意思，而随机模式每局的地形都不一样 —— 在一张随手摇出来的图上领走「黑夜 3000 米」，
## 和那张图就没关系了。金币照收（[method _award] 不经过这里）。
func _check_achievements(meters: int) -> void:
	if mode != Maps.MODE_CLASSIC:
		return
	var got := SaveData.claim_achievements(meters, map_id)
	if got <= 0:
		return
	coins += Achievements.reward_for(got)
	run_achievements += got
	hud.flash_achievement(meters, Achievements.reward_for(got))


## 金币入账。和捡金币一样**立刻写盘**：这一局的里程要等翻车才结算，但金币是
## 即时累计的，半路 Alt+F4 也不会丢。
func _award(amount: int) -> void:
	if amount == 0:
		return
	coins += amount
	SaveData.add_coins(amount)


func _on_car_crashed(reason: String) -> void:
	game_over = true
	# 收起踏板：**必须先松开动作**（`Input.action_press` 是全局的，不像按键松开就没了），
	# 否则玩家死的时候手指还踩着油门，重开那一局车自己就窜出去了。
	# 顺带把底下的点击让给结束面板。
	if touch != null:
		touch.set_locked(true)
	var meters := distance_meters()
	# **随机模式不写纪录**（见 [constant Maps.MODES]）：纪录榜上每一行都是经典模式
	# 那座固定地形上的成绩，两边混着记的话，榜上就变成「谁摇到的地图最平」。
	# 这里连 `submit_distance` 都不调 —— 它顺带把「破纪录」也判了，两个一起拦。
	var record := false
	if mode == Maps.MODE_CLASSIC:
		record = SaveData.submit_distance(meters, map_id)
	hud.show_game_over(reason, coins, meters, record, run_achievements)
	# 道具是**这一局**的消耗品，这一局完了就没了。
	#
	# 结束面板上那一条道具栏也跟着消失（HUD 只在 `not _over` 时画它）——
	# 这是有意的：玩家一眼就看出东西收走了，想再带就回商店重买。
	# 按 R 重开走的是 `reload_current_scene()`，不经过商店，所以重开那一局是
	# **裸车**，和「消耗品」这个设定对得上。
	SaveData.end_run()


func _unhandled_input(event: InputEvent) -> void:
	# 车灯那格**要排在最前面**：它是跑着的时候按的，而下面那道 `game_over` 闸后面
	# 全是「这一局已经结束」的处理（回车库 / 换地图 / 再跑一局），跑着的时候一次都
	# 进不去。钥匙和按钮走同一个入口（见 [method HillCar.toggle_headlights]）。
	if hud.headlight_button_at(_event_pos(event)):
		car.toggle_headlights()
		return
	if not game_over:
		return
	# 回车库/换地图/换车得排在前面：这三个是这一局结束后的主要去处，
	# 而「重开」的触发条件太宽（任意点击都算），不先拦下来就会被它吃掉。
	if event.is_action_pressed("garage"):
		get_tree().change_scene_to_file(GARAGE_SCENE)
		return
	if event.is_action_pressed("map"):
		get_tree().change_scene_to_file(MAP_SCENE)
		return
	if event.is_action_pressed("vehicle"):
		get_tree().change_scene_to_file(VEHICLE_SCENE)
		return
	# 手机版面底边那四个按钮（再跑一局 / 换车 / 换地图 / 回车库改装）。
	#
	# **桌面版面自动退回老行为**：那边 [method HillHud.gameover_buttons] 返回空数组，
	# 于是这段一次也不进 `match` 的任何一个分支，点哪儿都还是「再跑一局」。
	#
	# 排在下面「重开」那条**前面**：重开的触发条件太宽（任意点击都算），
	# 不先拦下来就会被它吃掉 —— 和顶上 G / M / V 靠前是同一个理由。
	match hud.gameover_button_at(_event_pos(event)):
		"vehicle":
			get_tree().change_scene_to_file(VEHICLE_SCENE)
			return
		"map":
			get_tree().change_scene_to_file(MAP_SCENE)
			return
		"garage":
			get_tree().change_scene_to_file(GARAGE_SCENE)
			return
		"restart":
			get_tree().reload_current_scene()
			return

	var restart_pressed := event.is_action_pressed("restart") or event.is_action_pressed("drive_forward")
	# 只认鼠标事件：手指那边引擎会补一个合成的（project.godot 的
	# emulate_mouse_from_touch），两边都认的话一次点按会重开两遍。这里重开是幂等的，
	# 所以原来也没坏，但没必要留两条路径 —— 见 tests/tap。
	var clicked := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if restart_pressed or clicked:
		get_tree().reload_current_scene()


## 点击事件的位置（画布坐标），别的输入给 (−1, −1)。
##
## 画布坐标和 HUD 里那些 [member Control.size] 是同一套：`canvas_items` 拉伸下，
## 事件进 `_input`／`_unhandled_input` 之前已经被视口按拉伸比例换算过了，
## 所以可以直接拿去和 [method HillHud.gameover_buttons] 的矩形比。
func _event_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	return Vector2(-1.0, -1.0)
