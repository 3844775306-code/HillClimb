extends Node
## 手机版：触屏操作层、两套版面、以及「手指按住真的能开走」。
##
## 用户原话：「现在我想把它导出成手机版，请你实现」。
##
## ## 这一份测什么
##
## A. **哪台设备该出触屏层**（[method HillTouchControls.wants_touch_controls]）。
## B. **踏板喂的是动作**：合成真的触摸事件推进视口，看
##    `drive_forward` / `drive_back` 有没有被按下、抬起。多指那几种情况
##    （两根手指踩两个踏板、两根手指踩同一个踏板、指头从一个踏板滑到另一个）各归各的。
## C. **暂停**：暂停键 ↔ `SceneTree.paused`；暂停时踏板不响应；菜单三个按钮各自干什么。
## D. **收尾**：[method Input.action_press] 是**全局状态**，不像按键松开就没了。
##    车翻了、指头抬了、切场景、切后台，四处都必须把它放开 ——
##    漏一处就是「下一局一开局车自己窜出去」。
## E. **两套版面不许打架**：踏板、暂停键、油条、道具栏、仪表盘，几个矩形两两不重叠，
##    而且都在屏幕里。三个画布尺寸各量一遍（16:9 / 宽屏手机 / 平板）。
## F. **端到端**：在真场景里用合成触摸踩油门，看车是不是真的往前开了 ——
##    前面几节测的是「动作按下去了」，这一节测的是「按下去了真的有用」。
##
## ## 为什么合成事件，而不是直接调 `_press`
##
## 操作层是在 [`Node._input`] 里收事件的（不是 `_gui_input`），而「事件到底进不进得来」
## 正是最容易坏的那一段（`process_mode`、`mouse_filter`、有没有被上层吃掉）。
## 直接调 `_press` 等于把整段跳过去测，测了个假的。
##
## 走的是 [method Viewport.push_input] —— 平台层把事件递进来的那个入口。没用
## [method Input.parse_input_event] 是因为后者要先过 [Input] 的缓冲和累积，
## 无头模式下多一层不该由这层代码负责的不确定。
##
## **`in_local_coords` 必须传 true。** 传 false 时引擎会拿 `final_transform` 的逆
## 把屏幕坐标映射回画布坐标 —— 那是真机上「手指位置 → 画布位置」那一步，引擎自己的活。
## 可无头模式下根本没有真窗口：`window.size` 是 64×64，`final_transform` 缩到 0.05，
## 于是 (1166, 606) 被映射成 (23320, 12120)，一个踏板都命中不了。
## 传 true 表示「事件已经是画布坐标了」，正是真机上变换完之后 [`Node._input`]
## 实际收到的东西 —— 下面所有矩形也都是画布坐标，两边同一套。

const MAIN := preload("res://scenes/main.tscn")
const CAR := preload("res://scenes/car.tscn")
const DT := 1.0 / 60.0
## 三个真实画布尺寸。`stretch/aspect = expand` 下，画布高度最少是 720
## （比 16:9 更宽的手机保持 720、两侧多出来），窄一些的平板会更高。
const CANVASES := [Vector2(1280.0, 720.0), Vector2(1600.0, 720.0), Vector2(1280.0, 960.0)]

var _assertions := 0
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()

	_section_a()
	print("")
	await _section_b()
	print("")
	await _section_c()
	print("")
	await _section_d()
	print("")
	await _section_e()
	print("")
	await _section_f()

	print("")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


# ---------------------------------------------------------------- 工具

## 合成一次触摸。[param index] 是第几根手指 —— **多指全靠它区分**。
func _tap(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	get_viewport().push_input(ev, true)
	await get_tree().process_frame


## 合成一次拖动（手指按着不放、位置变了）。
func _drag_to(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	get_viewport().push_input(ev, true)
	await get_tree().process_frame


## 一个铺好尺寸的 Control，当视口用。
##
## 操作层和 HUD 都是**铺满视口**用的（`set_anchors_and_offsets_preset(FULL_RECT)`），
## 裸挂在测试节点下面时「父矩形」就是视口、改不了尺寸；套一层 Control 才量得出
## 那三个画布尺寸。
func _box(canvas: Vector2) -> Control:
	var box := Control.new()
	box.size = canvas
	add_child(box)
	return box


## 建一层操作层，铺满给定的画布。
func _make_layer(canvas: Vector2 = CANVASES[0]) -> HillTouchControls:
	var box := _box(canvas)
	var t := HillTouchControls.new()
	box.add_child(t)
	# 字体用引擎兜底那份就够了：这一份测的是命中和动作，不是字形。
	t.setup(ThemeDB.fallback_font, false, true)
	return t


## 两个动作此刻的真实状态。**detail 一律报实测量的**，
## 不写死一句「按下去了」—— 断言挂了的时候那句话只会误导人。
func _acts() -> String:
	return "forward=%s back=%s" % [
		str(Input.is_action_pressed("drive_forward")),
		str(Input.is_action_pressed("drive_back"))]


func _overlaps(a: Rect2, b: Rect2) -> bool:
	if a.size.x <= 0.0 or a.size.y <= 0.0 or b.size.x <= 0.0 or b.size.y <= 0.0:
		return false
	return a.intersects(b)


# ------------------------------------------------- A. 哪台设备该出触屏层

func _section_a() -> void:
	print("A. 设备判定")
	_check("手机（有 mobile 特性）出触屏层",
			HillTouchControls.wants_touch_controls(true, false), "mobile=true")
	_check("带触摸屏的电脑也出（否则触屏笔记本没法玩）",
			HillTouchControls.wants_touch_controls(false, true), "mobile=false, 触摸屏=true")
	_check("普通键鼠电脑不出（桌面版行为和加这一层之前一模一样）",
			not HillTouchControls.wants_touch_controls(false, false), "两者都 false")
	# 本机跑测试时它必须是 false，否则别的地方会莫名其妙多出一层踏板。
	_check("本机（无头 PC）判定为不出触屏层",
			not HillTouchControls.is_touch_device(),
			"is_touch_device()=%s" % str(HillTouchControls.is_touch_device()))


# ------------------------------------------------- B. 踏板喂的是动作

func _section_b() -> void:
	print("B. 踏板 → 输入动作（合成真事件）")
	var t := _make_layer()
	var rects := t.pedal_rects()
	var brake := rects["brake"] as Rect2
	var gas := rects["gas"] as Rect2
	var screen := Rect2(Vector2.ZERO, t.size)

	_check("两个踏板都在屏幕里",
			screen.encloses(gas) and screen.encloses(brake),
			"刹车 %s  油门 %s" % [str(brake), str(gas)])
	_check("刹车在左、油门在右",
			brake.get_center().x < t.size.x * 0.5 and gas.get_center().x > t.size.x * 0.5,
			"刹车 x=%.0f  油门 x=%.0f（中线 %.0f）" % [
				brake.get_center().x, gas.get_center().x, t.size.x * 0.5])
	_check("两个踏板不重叠", not _overlaps(brake, gas), "刹车 %s 油门 %s" % [str(brake), str(gas)])

	# 一根手指踩油门。
	await _tap(0, gas.get_center(), true)
	_check("手指按在油门踏板上 = 按下 drive_forward",
			Input.is_action_pressed("drive_forward"), _acts())
	_check("这时候没碰倒车", not Input.is_action_pressed("drive_back"), _acts())
	await _tap(0, gas.get_center(), false)
	_check("手指抬起来 = 放开 drive_forward",
			not Input.is_action_pressed("drive_forward"), _acts())

	# 一根手指踩刹车。
	await _tap(1, brake.get_center(), true)
	_check("手指按在刹车踏板上 = 按下 drive_back",
			Input.is_action_pressed("drive_back"), _acts())
	await _tap(1, brake.get_center(), false)

	# 多指：两根手指同时踩两个踏板（登月车的「双键起飞」就是这一条）。
	await _tap(0, brake.get_center(), true)
	await _tap(1, gas.get_center(), true)
	_check("两根手指同时踩两个踏板 = 两个动作同时按下（登月车的起飞条件）",
			Input.is_action_pressed("drive_forward") and Input.is_action_pressed("drive_back"),
			_acts())
	# 先抬起一根，另一根还踩着 —— 这一条正是靠 `_hold` 计数保住的。
	await _tap(0, brake.get_center(), false)
	_check("先抬起的那一根不会把另一根踩着的那一脚也放掉",
			Input.is_action_pressed("drive_forward") and not Input.is_action_pressed("drive_back"),
			_acts())
	await _tap(1, gas.get_center(), false)

	# 两根手指踩同一个踏板，先抬起一根。
	await _tap(0, gas.get_center(), true)
	await _tap(1, gas.get_center(), true)
	await _tap(0, gas.get_center(), false)
	_check("两根手指踩同一个踏板时，抬起一根不会松开油门",
			Input.is_action_pressed("drive_forward"), _acts())
	await _tap(1, gas.get_center(), false)
	_check("两根都抬起来才真松开",
			not Input.is_action_pressed("drive_forward"), _acts())

	# 手指从一个踏板滑到另一个踏板：换过去，不是一直踩着原来那个。
	await _tap(0, gas.get_center(), true)
	await _drag_to(0, brake.get_center())
	_check("手指从油门滑到刹车 = 换成刹车（油门松开）",
			Input.is_action_pressed("drive_back") and not Input.is_action_pressed("drive_forward"),
			_acts())
	# 滑到空白处（屏幕正中间）就该松开。
	await _drag_to(0, t.size * 0.5)
	_check("手指滑到空白处 = 两个动作都松开",
			not Input.is_action_pressed("drive_forward") and not Input.is_action_pressed("drive_back"),
			_acts())
	await _tap(0, t.size * 0.5, false)

	# 关掉整层（桌面版）之后，同样的触摸不该做任何事。
	t.set_enabled(false)
	await _tap(0, gas.get_center(), true)
	_check("整层关掉之后（桌面版），踩踏板什么也不做",
			not Input.is_action_pressed("drive_forward"), "桌面版不受影响")
	await _tap(0, gas.get_center(), false)
	t.get_parent().queue_free()
	await get_tree().process_frame


# ------------------------------------------------- C. 暂停

func _section_c() -> void:
	print("C. 暂停键与暂停菜单")
	var t := _make_layer()
	var pause := t.pause_rect()
	_check("暂停键在屏幕右上角",
			pause.get_center().x > t.size.x * 0.5 and pause.position.y < t.size.y * 0.5,
			"暂停键 %s" % str(pause))
	# 右上角挂着本局地图名（[constant HillHud.MAP_NAME_BASELINE] 基线、字号
	# [constant HillHud.MAP_NAME_SIZE]）。**拿真字体量出下缘**再比，不是拿一个「大概」。
	var band_bottom := HillHud.MAP_NAME_BASELINE \
			+ t.get_theme_default_font().get_descent(HillHud.MAP_NAME_SIZE)
	_check("暂停键不压住右上角那行地图名", pause.position.y >= band_bottom,
			"暂停键顶边 y=%.0f，地图名下缘 y=%.1f" % [pause.position.y, band_bottom])

	await _tap(0, pause.get_center(), true)
	await _tap(0, pause.get_center(), false)
	_check("点暂停键 = 整棵场景树暂停",
			get_tree().paused and t.is_paused(), "paused=%s" % str(get_tree().paused))

	var menus := t.menu_rects()
	_check("暂停菜单三个按钮（继续 / 重开 / 返回选图）",
			menus.map(func(m): return String(m["id"])) == ["resume", "restart", "map"],
			"ids=%s" % str(menus.map(func(m): return m["id"])))
	_check("暂停时三个按钮都在屏幕里",
			menus.all(func(m): return Rect2(Vector2.ZERO, t.size).encloses(m["rect"] as Rect2)),
			"菜单顶边 y=%.0f 底边 y=%.0f（画布高 %.0f）" % [
				(menus[0]["rect"] as Rect2).position.y,
				(menus[2]["rect"] as Rect2).end.y, t.size.y])

	# 暂停时踩踏板不该有任何反应（否则解暂停那一刻车会窜出去）。
	await _tap(1, (t.pedal_rects()["gas"] as Rect2).get_center(), true)
	_check("暂停时踩油门不响应", not Input.is_action_pressed("drive_forward"), "动作没按下")
	await _tap(1, (t.pedal_rects()["gas"] as Rect2).get_center(), false)

	# 三个按钮各自干什么。
	var seen := []
	var probe := func(id: String) -> void: seen.append(id)
	t.pause_action.connect(probe)
	await _tap(2, (menus[1]["rect"] as Rect2).get_center(), true)
	await _tap(2, (menus[1]["rect"] as Rect2).get_center(), false)
	_check("点「重开」= 先解暂停再喊话",
			seen == [HillTouchControls.ACTION_RESTART] and not get_tree().paused and not t.is_paused(),
			"收到的信号=%s  paused=%s" % [str(seen), str(get_tree().paused)])

	await _tap(0, pause.get_center(), true)
	await _tap(0, pause.get_center(), false)
	_check("再点一次暂停键又能暂停", get_tree().paused, "paused=true")
	await _tap(3, (menus[2]["rect"] as Rect2).get_center(), true)
	await _tap(3, (menus[2]["rect"] as Rect2).get_center(), false)
	_check("点「返回选图」= 先解暂停再喊话",
			seen.size() == 2 and seen[1] == HillTouchControls.ACTION_MAP and not get_tree().paused,
			"收到的信号=%s  paused=%s" % [str(seen), str(get_tree().paused)])

	await _tap(0, pause.get_center(), true)
	await _tap(0, pause.get_center(), false)
	await _tap(4, (menus[0]["rect"] as Rect2).get_center(), true)
	await _tap(4, (menus[0]["rect"] as Rect2).get_center(), false)
	_check("点「继续」= 就地解暂停，不喊人",
			not get_tree().paused and seen.size() == 2,
			"paused=%s 信号数=%d" % [str(get_tree().paused), seen.size()])

	# 暂停键和菜单按钮是「点一下」语义。按在空白处再把手指滑到按钮上，
	# 按钮**不许**响应 —— 不然手指一抖就点掉了「返回选图」。
	await _tap(0, pause.get_center(), true)
	await _tap(0, pause.get_center(), false)
	var blank := Vector2(100.0, t.size.y * 0.5)
	_check("（前置）用来起手的空白处不在任何区域里", t.zone_at(blank) == "", "zone=\"\"")
	await _tap(5, blank, true)
	await _drag_to(5, (menus[2]["rect"] as Rect2).get_center())
	_check("按在空白处再滑到按钮上，按钮不响应（「点一下」语义）",
			get_tree().paused and seen.size() == 2,
			"paused=%s 信号数=%d" % [str(get_tree().paused), seen.size()])
	await _tap(5, (menus[2]["rect"] as Rect2).get_center(), false)

	# 收尾：这一节不能把暂停状态留给下一节。
	t.set_paused(false)
	_check("C 节收尾：没有把暂停状态留给下一节", not get_tree().paused, "paused=false")
	t.get_parent().queue_free()
	await get_tree().process_frame


# ------------------------------------------------- D. 收尾：动作必须放开

func _section_d() -> void:
	print("D. 收尾（动作是全局状态，漏一处就是下一局自己窜出去）")
	var t := _make_layer()
	var gas := (t.pedal_rects()["gas"] as Rect2).get_center()

	# 车翻了：锁住整层，同时把脚下的油门松开。
	await _tap(0, gas, true)
	_check("（前置）手指还踩着油门", Input.is_action_pressed("drive_forward"), _acts())
	t.set_locked(true)
	_check("车翻了之后踏板动作立刻放开",
			not Input.is_action_pressed("drive_forward"), _acts())
	await _tap(1, gas, true)
	_check("车翻了之后踩踏板不再有反应",
			not Input.is_action_pressed("drive_forward"), _acts())
	await _tap(1, gas, false)

	# 解锁之后要能重新踩上。
	t.set_locked(false)
	await _tap(0, gas, true)
	_check("重开一局（解锁）之后踏板又能用了",
			Input.is_action_pressed("drive_forward"), _acts())

	# 退出场景（切图 / 重开）：动作必须放开。**这条不是锦上添花** ——
	# 带着按死的动作换场景，新场景的车一进去就自己窜出去，而且没有任何输入能停下它。
	t.get_parent().queue_free()
	await get_tree().process_frame
	_check("退出场景时动作全部放开",
			not Input.is_action_pressed("drive_forward"), _acts())

	# 切到后台：`NOTIFICATION_APPLICATION_FOCUS_OUT`（来电、Home 键、切窗口）。
	# 这时候指头永远不会再发抬起事件了。
	var t2 := _make_layer()
	await _tap(0, (t2.pedal_rects()["gas"] as Rect2).get_center(), true)
	_check("（前置）第二层：手指踩着油门", Input.is_action_pressed("drive_forward"), _acts())
	t2.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("切到后台（来电 / Home 键）时动作全部放开",
			not Input.is_action_pressed("drive_forward"), _acts())
	t2.get_parent().queue_free()
	await get_tree().process_frame


# ------------------------------------------------- E. 两套版面不许打架

func _section_e() -> void:
	print("E. 两套版面（踏板 / 暂停键 / 油条 / 车灯 / 道具栏 / 仪表盘 两两不许重叠）")
	var car := CAR.instantiate() as HillCar
	add_child(car)
	var box := _box(CANVASES[0])
	var hud := HillHud.new()
	box.add_child(hud)
	var t := HillTouchControls.new()
	box.add_child(t)
	hud.setup(car, Maps.PLAINS, true)
	t.setup(ThemeDB.fallback_font, false, true)

	# 道具栏只在「这一局带了道具」时才画，所以这里先装上两件。
	SaveData.run_items = {Items.IDS[0]: true, Items.IDS[1]: true}

	for canvas in CANVASES:
		box.size = canvas
		hud.size = canvas
		await get_tree().process_frame
		var named := {
			"刹车踏板": (t.pedal_rects()["brake"] as Rect2),
			"油门踏板": (t.pedal_rects()["gas"] as Rect2),
			"暂停键": t.pause_rect(),
			"油条": hud.fuel_rect(),
			"道具栏": hud.items_rect(),
			"仪表盘": hud.dashboard_cluster(),
			# 平原图上这一格是零矩形（车灯只有黑夜图有，见 [method HillHud.headlight_rect]），
			# 而 [_overlaps] 和下面那条「在屏幕里」都跳过零矩形 —— 「这张图用不上」
			# 不用在测试里特判，正是 [method HillHud.headlight_rect] 返回零矩形的理由。
			"车灯": hud.headlight_rect(),
		}
		var keys := named.keys()
		var clashes := []
		var outside := []
		for i in keys.size():
			if not Rect2(Vector2.ZERO, canvas).encloses(named[keys[i]]):
				outside.append("%s %s" % [keys[i], str(named[keys[i]])])
			for j in range(i + 1, keys.size()):
				if _overlaps(named[keys[i]], named[keys[j]]):
					clashes.append("%s×%s" % [keys[i], keys[j]])
		_check("画布 %s：%d 个矩形两两不重叠" % [str(canvas), keys.size()], clashes.is_empty(),
				"撞上的：%s" % ("没有" if clashes.is_empty() else str(clashes)))
		_check("画布 %s：%d 个矩形都在屏幕里" % [str(canvas), keys.size()], outside.is_empty(),
				"出界的：%s" % ("没有" if outside.is_empty() else str(outside)))

	# 桌面版面（不在手机上）也要量：油条和道具栏回的是**老坐标**，
	# 一个数都没动 —— 手机版不许顺手把桌面版重排了。
	hud.setup(car, Maps.PLAINS, false)
	hud.size = CANVASES[0]
	await get_tree().process_frame
	_check("桌面版面：油条回到左下角（老坐标一个数没动）",
			hud.fuel_rect().position == Vector2(30.0, CANVASES[0].y - 60.0),
			"油条 %s" % str(hud.fuel_rect()))
	_check("桌面版面：道具栏回到右下角",
			is_equal_approx(hud.items_rect().end.x, CANVASES[0].x - 30.0),
			"道具栏 %s" % str(hud.items_rect()))
	_check("桌面版面：结束面板没有那四个按钮（有键盘，不加）",
			hud.gameover_buttons().is_empty(), "按钮数=%d" % hud.gameover_buttons().size())

	# ---- 车灯那格（只在黑夜图上有）----
	#
	# 手机上没有键盘，这一格是**手机上唯一的车灯开关**（见 [method HillCar.toggle_headlights]），
	# 所以它必须点得中，而且两套版面里都不许压到别的东西：手机版并排贴在油条左边，
	# 桌面版在右上角（那一块是四列统计够不着的地方）。
	for canvas in CANVASES:
		hud.setup(car, Maps.NIGHT, true)
		hud.size = canvas
		await get_tree().process_frame
		var spot := hud.headlight_rect()
		_check("手机版 %s：黑夜图上摆出车灯那格" % str(canvas), spot.size.x > 0.0, str(spot))
		_check("手机版 %s：车灯那格在屏幕里" % str(canvas),
				Rect2(Vector2.ZERO, canvas).encloses(spot), str(spot))
		_check("手机版 %s：车灯那格点得中" % str(canvas),
				hud.headlight_button_at(spot.get_center()), "中心 %s" % str(spot.get_center()))
		# 它和油条是并排的**两格**：既不许叠上，也不许离得太远（离远了看着像两件事）。
		var gap := hud.fuel_rect().position.x - spot.end.x
		_check("手机版 %s：车灯那格贴在油条左边，中间留 %.0f 像素" % [str(canvas), gap],
				gap >= 4.0 and gap <= 40.0,
				"车灯 %s，油条 %s" % [str(spot), str(hud.fuel_rect())])
		_check("手机版 %s：车灯那格没有伸到刹车踏板上" % str(canvas),
				not _overlaps(spot, t.pedal_rects()["brake"] as Rect2),
				"车灯 %s，刹车 %s" % [str(spot), str(t.pedal_rects()["brake"])])

	hud.setup(car, Maps.NIGHT, false)
	hud.size = CANVASES[0]
	await get_tree().process_frame
	var desk := hud.headlight_rect()
	_check("桌面版：黑夜图上车灯在右上角、和地图名对齐右边",
			desk.size.x > 0.0 and is_equal_approx(desk.end.x, CANVASES[0].x - 30.0)
			and desk.position.y < CANVASES[0].y * 0.25,
			str(desk))
	_check("桌面版：车灯不压到四列统计上（1280 宽时统计排到 x≈800 为止）",
			desk.position.x > 900.0, "车灯从 x=%.0f 起" % desk.position.x)
	hud.setup(car, Maps.PLAINS, false)
	hud.size = CANVASES[0]
	await get_tree().process_frame
	_check("平原图上没有车灯那格（零矩形 → 不画、也点不着）",
			hud.headlight_rect().size == Vector2.ZERO
			and not hud.headlight_button_at(Vector2(CANVASES[0].x - 100.0, 90.0)),
			str(hud.headlight_rect()))

	# 手机版面：结束面板那四个按钮要真的点得中，而且指向四件不同的事。
	hud.setup(car, Maps.PLAINS, true)
	hud.size = CANVASES[0]
	await get_tree().process_frame
	hud.show_game_over(HillCar.REASON_CRASH, 0, 0, false, 0)
	var buttons := hud.gameover_buttons()
	var ids := []
	var hit := 0
	var in_screen := true
	for b in buttons:
		var r := b["rect"] as Rect2
		ids.append(String(b["id"]))
		if hud.gameover_button_at(r.get_center()) == String(b["id"]):
			hit += 1
		if not Rect2(Vector2.ZERO, hud.size).encloses(r):
			in_screen = false
	_check("手机版面：结束面板摆出四个按钮", buttons.size() == 4, "ids=%s" % str(ids))
	_check("四个按钮各自都点得中（中心点命中自己）", hit == buttons.size(),
			"命中 %d / %d" % [hit, buttons.size()])
	var uniq := {}
	for id in ids:
		uniq[id] = true
	_check("四个按钮是四件不同的事", uniq.size() == ids.size(),
			"ids=%s（去重后 %d 个）" % [str(ids), uniq.size()])
	_check("四个按钮都在屏幕里", in_screen, "画布 %s" % str(hud.size))
	_check("按钮之外的地方点不中任何按钮（点哪儿都还是「再跑一局」）",
			hud.gameover_button_at(Vector2(hud.size.x * 0.5, 40.0)) == "",
			"顶部中央 = 空")
	# 结束面板**会把车灯那格收起来**（见 [method HillHud.headlight_rect]）：面板上
	# 「随便点哪儿都是再跑一局」，那格留着的话，右上角点下去会变成开灯 ——
	# 玩家以为在重开，其实只是把灯关了。这里**换回黑夜图再问一次**，
	# 免得「收起来了」其实是「地图不是黑夜」蒙对的。
	hud.setup(car, Maps.NIGHT, true)
	hud.size = CANVASES[0]
	await get_tree().process_frame
	_check("结束面板上那格收起来了（黑夜图上也不留）",
			hud.headlight_rect().size == Vector2.ZERO and hud.gameover_buttons().size() == 4,
			str(hud.headlight_rect()))

	SaveData.run_items = {}
	box.queue_free()
	car.queue_free()
	await get_tree().process_frame


# ------------------------------------------------- F. 端到端：真的能开走

func _section_f() -> void:
	print("F. 端到端：合成触摸踩油门，车真的开走了")
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	var car: HillCar = main.car
	# 加满油：续航会把这一段跑歪，而这里要测的是「油门通不通」。
	car.fuel_max = 1.0e9
	car.fuel = 1.0e9
	# 本机（PC）判定为不出触屏层，这里手动打开 —— 测的正是打开之后那条路。
	main.touch.set_enabled(true)
	_check("场景里的操作层存在，并且能被点开",
			main.touch.enabled and main.touch.visible, "enabled=true")

	var gas := (main.touch.pedal_rects()["gas"] as Rect2).get_center()
	var x0: float = car.chassis.global_position.x
	var wheel0: float = car.rear_wheel.angular_velocity
	await _tap(0, gas, true)
	# **等两个物理帧再读 `throttle`，不能只等一个。** 两个理由叠在一起：
	#   · `_tap` 只等了一个**处理帧**，而 `throttle` 是 [method HillCar._read_throttle]
	#     每个**物理帧**重算的，处理帧比物理帧快得多（headless 下尤其）；
	#   · `physics_frame` 信号是在**这一步开始之前**发出来的（Godot 主循环先发信号、
	#     再调各节点的 `_physics_process`），所以等一个只是「等到了这一步的开头」，
	#     车还没算过 —— 那时 `throttle` 还是陈值 0.00。
	# 等到第二个时才保证「有一次完整的物理步是在油门按下的状态下跑完的」。
	# 两帧里车走的距离忽略不计（下面那条阈值是 150 像素、实测 1500 上下）。
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("（前置）油门动作已经按下", Input.is_action_pressed("drive_forward"), _acts())
	_check("（前置）车这边读到的油门也是满的", car.throttle > 0.99,
			"throttle=%.2f" % car.throttle)

	var t := 0.0
	while t < 3.0 and car.alive:
		await get_tree().physics_frame
		car.fuel = 1.0e9
		t += DT
	var dx: float = car.chassis.global_position.x - x0
	_check("按住油门 3 秒，车真的往前开走了", dx > 150.0,
			"前进 %.1f 像素（%.1f 米），车还活着=%s" % [
				dx, dx / Maps.PIXELS_PER_METER, str(car.alive)])
	_check("轮子是真的在转（不是被推着滑过去的）",
			absf(car.rear_wheel.angular_velocity) > absf(wheel0) + 1.0,
			"后轮角速度 %.2f rad/s（起步时 %.2f）" % [car.rear_wheel.angular_velocity, wheel0])

	# 抬起手指：油门要真的归零。
	await _tap(0, gas, false)
	await get_tree().physics_frame
	_check("抬起手指之后油门真的松了",
			not Input.is_action_pressed("drive_forward") and absf(car.throttle) < 0.01,
			"动作放开了，throttle=%.2f" % car.throttle)

	# 暂停之后车必须停住（暂停键的意义就在这儿）。
	main.touch.set_paused(true)
	var p0: Vector2 = car.chassis.global_position
	for i in int(0.5 / DT):
		await get_tree().physics_frame
	var moved: float = car.chassis.global_position.distance_to(p0)
	_check("暂停之后车停在原地", moved < 1.0, "暂停 0.5 秒里挪了 %.3f 像素" % moved)
	main.touch.set_paused(false)
	_check("解暂停之后没有把暂停状态留下", not get_tree().paused, "paused=false")

	main.queue_free()
	await get_tree().process_frame
