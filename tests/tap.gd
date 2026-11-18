extends Node
## **一次点按 = 一次动作。**
##
## 安卓上手指按下会递进来**两个**事件：一个 [InputEventScreenTouch]，紧接着一个引擎合成的
## [InputEventMouseButton]（device = −1，来自 project.godot 的
## `input_devices/pointing/emulate_mouse_from_touch`）。四个界面原来两条分支都接，
## 于是同一个位置在同一次点按里跑了两遍 `_on_click`：
##
##   - 商店：勾上又取消 → 清单永远是空的，手机上**买不了装备**（用户报的就是这条）
##   - 车库：一碰就买两级（第二级钱够的话就真买走了）
##   - 选图 / 选车：擦过一张没选中的卡会连「选中」和「买下」一起走完
##
## 现在的规矩：**界面只认鼠标事件**，手指那一路交给引擎合成。于是每一页各测两个方向：
##
##   1. 「那一对」—— 按真实先后顺序推「真触摸 + 合成鼠标」，断言净效果**恰好一次动作**。
##      这就是安卓上的那一下，也是这个文件的核心。
##   2. 「只推触摸」—— 断言**什么都不发生**，同时断言那个触摸**确实递到了树上**。
##      界面不许再自己接手指事件；谁把那条分支加回来，一次点按就又变成两次。
##
## 两条都推 `get_viewport().push_input`，也就是平台真把事件递进来的那个入口。
##
## **这个文件是有牙齿的**：把老代码（`elif event is InputEventScreenTouch …: _on_click(…)`）
## 注回任意一页再跑，第 1 条会当场红 —— 商店「勾上的件数 0 件」正是用户报的那个症状，
## 车库「引擎的等级 2」、两页选单「金币一分没动 —— 0」也都会红，第 2 条同样会红。
##
## **点按坐标全部由界面自己算**（`_card_rect` / `_row_rect`），但版面按 1280×720 的真机
## 尺寸摆（无头视口是 1280×1280，直接挂进去量出来的版面是错的，README 坑 #7）。
##
## 用法：
##   godot --headless --path . res://tests/tap.tscn

const SHOP := preload("res://scenes/shop.tscn")
const GARAGE := preload("res://scenes/garage.tscn")
const MAPSELECT := preload("res://scenes/mapselect.tscn")
const VEHICLESELECT := preload("res://scenes/vehicleselect.tscn")

const DESIGN := Vector2(1280.0, 720.0)
## 安卓上那一下：真触摸 + 引擎合成的鼠标。
const PAIR := "那一对（真触摸 + 合成鼠标）"
## 只有真触摸。界面不该理它。
const RAW := "只推触摸"
const WAYS := [PAIR, RAW]


## 数一数 `_input` 到底收到了几个触摸，坐标对不对。用来证明下面「什么都不该发生」
## 那几条不是空跑 —— 触摸要是根本没递到树上，那几条断言谁也拦不住。
class TouchProbe extends Node:
	var positions: Array[Vector2] = []

	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			positions.append((event as InputEventScreenTouch).position)


var _screen: Control
var _probe: TouchProbe
var _assertions := 0
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false     # 别让这些点按写进玩家存档
	SaveData.reset_progress()
	print("一次点按 = 一次动作")
	_test_setting()
	_test_source()
	print("")
	await _test_touch_delivery()
	print("")
	await _test_shop()
	print("")
	await _test_garage()
	print("")
	await _test_mapselect()
	print("")
	await _test_vehicleselect()
	print("")
	# 一路点下来都不该把这一页换掉（换场景会把测试根节点自己 free 掉）。
	_check(is_inside_tree(), "全程没有哪个按钮把场景换走", "还在树上")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


# ---------------------------------------------------------------- 三条结构上的线

## 整套手机输入都压在 `emulate_mouse_from_touch` 上：界面只认鼠标事件，手指那一路全靠
## 引擎合成。谁把它关了，桌面上一点事没有、安卓上所有按钮全部失灵 —— 所以钉在这儿。
func _test_setting() -> void:
	print("=== 结构 ===")
	var on := bool(ProjectSettings.get_setting(
			"input_devices/pointing/emulate_mouse_from_touch", false))
	_check(on, "emulate_mouse_from_touch 是开着的（手机端点按全靠它合成鼠标事件）",
			"project.godot 里写着 true" if on else "没开！安卓上按钮会全部失灵")


## `scripts/` 下除了 [code]touch_controls.gd[/code]，谁的**代码行**里都不该再出现
## [InputEventScreenTouch]。
##
## 注释里出现不算 —— 那几个文件的开头正好写着「不接 InputEventScreenTouch」。只扫
## `scripts/`：`tests/mobile.gd` 是**故意**在合成触摸的，它拿它去踩踏板、暂停和菜单，
## 那是 [code]touch_controls[/code] 的正经输入。
func _test_source() -> void:
	var offenders := PackedStringArray()
	var dir := DirAccess.open("res://scripts")
	var names: PackedStringArray = dir.get_files() if dir != null else PackedStringArray()
	for name in names:
		if not String(name).ends_with(".gd") or String(name) == "touch_controls.gd":
			continue
		var f := FileAccess.open("res://scripts/%s" % name, FileAccess.READ)
		if f == null:
			offenders.append("%s 打不开" % name)
			continue
		var line_no := 0
		while not f.eof_reached():
			line_no += 1
			var text := f.get_line().strip_edges()
			if text.begins_with("#") or not text.contains("InputEventScreenTouch"):
				continue
			offenders.append("%s:%d" % [name, line_no])
		f.close()
	_check(offenders.is_empty(), "scripts/ 下只有 touch_controls.gd 处理手指事件",
			"只有它" if offenders.is_empty() else "；".join(offenders))


## 探针挂上去，量一量触摸到底递到了哪里。探针一直留着：下面每一条「只推触摸」都顺手
## 断言一下触摸真的到了树上，那几条才站得住。
func _test_touch_delivery() -> void:
	print("=== 触摸真的递得到树上 ===")
	_probe = TouchProbe.new()
	add_child(_probe)

	var pos := Vector2(400.0, 300.0)
	_probe.positions.clear()
	_push_touch(pos, true)
	await get_tree().process_frame
	_check(_probe.positions == [pos], "push_input 递进来的触摸，坐标原样到达 _input",
			"%s" % str(_probe.positions))

	# 平台真喂事件走的也是 push_input 这条路，超不出上面那一条。这里把
	# [Input.parse_input_event] 那条入口也量一下 —— **只打印，不断言**：它是递到了
	# `_input`，但坐标被窗口的拉伸系数放大了（实测给 (400,300)、收到 (8000,6000)），
	# 拿它当输入源会点到别的地方去，测出假的绿。
	_probe.positions.clear()
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame
	print("      （附注，不作断言）Input.parse_input_event 递进来 %d 个触摸，坐标 %s（我们给的 %s）" % [
			_probe.positions.size(), str(_probe.positions), str(pos)])


# ---------------------------------------------------------------- 四个界面

func _test_shop() -> void:
	print("=== 商店：点一下正好勾上一件 ===")
	for how in WAYS:
		SaveData.reset_progress()
		SaveData.total_coins = Items.PRICE * 3
		var s: HillShop = await _mount(SHOP)
		s._sel = 0                       # 故意挑第 1 张卡（光标本来在第 0 张）
		var want: int = 1 if how == PAIR else 0
		await _tap(s._card_rect(1).get_center(), how)
		# 改之前「那一对」在这里是 0 件：勾上又取消，手机上永远攒不出清单。
		_check(s._chosen.size() == want, "%s：勾上的件数" % how, "%d 件" % s._chosen.size())
		_check(s._sel == (1 if how == PAIR else 0), "%s：光标" % how, "%d" % s._sel)
		_check(s._total() == want * Items.PRICE, "%s：合计" % how, "%d" % s._total())


func _test_garage() -> void:
	print("=== 车库：点一下只升一级 ===")
	for how in WAYS:
		SaveData.reset_progress()
		# 钱刚好够**两级**：改之前跑两遍会把两级一起买走。
		SaveData.total_coins = Upgrades.cost(0) + Upgrades.cost(1)
		var g: HillGarage = await _mount(GARAGE)
		g._sel = 3                       # 故意挑第 0 行（光标本来在第 3 行）
		var want: int = 1 if how == PAIR else 0
		await _tap(g._row_rect(0).get_center(), how)
		_check(SaveData.level_of("engine") == want, "%s：引擎的等级" % how,
				"%d" % SaveData.level_of("engine"))
		_check(SaveData.total_coins == Upgrades.cost(0) + Upgrades.cost(1) - want * Upgrades.cost(0),
				"%s：剩下的钱" % how, "%d" % SaveData.total_coins)
		_check(g._sel == (0 if how == PAIR else 3), "%s：光标" % how, "%d" % g._sel)


func _test_mapselect() -> void:
	print("=== 选图：点一下只挪光标，不掏钱 ===")
	for how in WAYS:
		SaveData.reset_progress()
		SaveData.select_map(Maps.IDS[0])            # 光标停在第 0 张（白送的平原）
		SaveData.total_coins = Maps.UNLOCK_PRICE
		var s: HillMapSelect = await _mount(MAPSELECT)
		# 前四张白送，所以第 4 张起都要买。VISIBLE = 4，把窗口滚过去它才点得到。
		var id: String = s._ids[4]
		s._sel = 0
		s._first = 4
		_check(not SaveData.map_unlocked(id), "%s：（前提）第 4 张是锁着的" % how, id)
		await _tap(s._card_rect(4).get_center(), how)
		_check(s._sel == (4 if how == PAIR else 0), "%s：光标" % how, "%d" % s._sel)
		_check(SaveData.total_coins == Maps.UNLOCK_PRICE, "%s：金币一分没动" % how,
				"%d（期望 %d）" % [SaveData.total_coins, Maps.UNLOCK_PRICE])
		_check(not SaveData.map_unlocked(id), "%s：还是锁着的" % how, id)


func _test_vehicleselect() -> void:
	print("=== 选车：点一下只挪光标，不掏钱 ===")
	for how in WAYS:
		SaveData.reset_progress()
		SaveData.select_vehicle(Vehicles.IDS[0])     # 光标停在第 0 辆（白送的越野车）
		SaveData.total_coins = Vehicles.UNLOCK_PRICE
		var s: HillVehicleSelect = await _mount(VEHICLESELECT)
		# 前两辆白送，所以第 2 张（赛车）就是第一辆要买的；VISIBLE = 4，它本来就在窗口里。
		var id: String = s._ids[2]
		_check(not SaveData.vehicle_unlocked(id), "%s：（前提）第 2 辆是锁着的" % how, id)
		_check(s._sel == 0, "%s：（前提）光标从越野车起步" % how, "%d" % s._sel)
		await _tap(s._card_rect(2).get_center(), how)
		_check(s._sel == (2 if how == PAIR else 0), "%s：光标" % how, "%d" % s._sel)
		_check(SaveData.total_coins == Vehicles.UNLOCK_PRICE, "%s：金币一分没动" % how,
				"%d（期望 %d）" % [SaveData.total_coins, Vehicles.UNLOCK_PRICE])
		_check(not SaveData.vehicle_unlocked(id), "%s：还是锁着的" % how, id)


# ---------------------------------------------------------------- 工具

## 挂一页界面上去，按**真机版面**（1280×720）摆好。
##
## 锚点要先拉平再设尺寸，不然 Godot 会警告说 `_ready()` 之后尺寸会被锚点覆盖。
func _mount(scene: PackedScene) -> Control:
	if _screen != null:
		_screen.queue_free()
		# 等一帧，确认上一页真的从树上撤走了 —— 不然这一下会同时点两页。
		await get_tree().process_frame
	var s: Control = scene.instantiate()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = DESIGN
	add_child(s)
	await get_tree().process_frame
	_screen = s
	return s


## 点一下。[param how] 决定这一下推什么。
##
## 「只推触摸」那一支顺手验一验触摸真的到了树上：探针多收一个、坐标就是要点的那个位置。
## 不然「什么都不该发生」有可能只是事件没递到，白绿一场。
func _tap(pos: Vector2, how: String) -> void:
	if how == PAIR:
		# 真实的先后顺序：先真触摸，再引擎合成的鼠标。
		_push_touch(pos, true)
		_push_mouse(pos, true)
		_push_touch(pos, false)
		_push_mouse(pos, false)
	else:
		var seen := _probe.positions.size()
		_push_touch(pos, true)
		_push_touch(pos, false)
		await get_tree().process_frame
		_check(_probe.positions.size() == seen + 1 and _probe.positions[-1] == pos,
				"%s：（前提）触摸递到了树上" % how,
				"%d 个，最后一个在 %s" % [_probe.positions.size() - seen,
						str(_probe.positions[-1]) if _probe.positions.size() > seen else "—"])


func _push_touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	get_viewport().push_input(ev, true)


func _push_mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.pressed = pressed
	# 引擎合成的事件带的就是这个 device（−1）。
	ev.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(ev, true)


func _check(ok: bool, label: String, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])
