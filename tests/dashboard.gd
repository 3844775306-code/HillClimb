extends Node
## 仪表盘（[HillDashboard]）的验证。分四组：
##
## A. **换算** —— km/h 和 rpm 两个纯函数，外加「比例 → 指针角度」的几何。
##    这几条是纯算术，最容易在改动里悄悄歪掉（比如把 TAU 写成 PI）。
## B. **量程** —— 量程必须**跟着车走**：四辆车的轮径不同（21 / 20 / 23），
##    [Upgrades] 的极速一项还会把 `max_wheel_speed` 乘到 1.263 倍。写死一个数
##    在这三种情况下都会顶表，所以这里拿真车、真升级表去量。
## C. **实机** —— 开一段，看**表盘够不够用**。这是这个文件存在的主要理由：
##    B 组只验了「量程是这么算出来的」，验不到「算出来的量程够不够」。
##    真正的判据是「跑起来表针落在哪」，那只有开一圈才知道。
## D. **版面** —— 表盘占的矩形不能压在油条、道具栏和顶栏上，也不能跑出屏幕。
##
## headless 下 `_draw()` **根本不会被调用**（没有渲染器），所以四组全是**算出来的**
## 断言，不是「跑一遍看看有没有报错」。画得对不对（刻度线是不是歪的、针是不是反的）
## 这里验不到，只能保证几何关系成立 —— 指针方向那条在 [method _case_convert] 里，
## 靠 [method HillDashboard.tip_of] 的返回值钉住。

const MAIN := preload("res://scenes/main.tscn")
const CAR := preload("res://scenes/car.tscn")
## 实机那一段开多久（模拟秒）。**不是随便定的**：默认车全油门大约 6 秒就会扎头翻车
## （见 [tests/vehicles_drive]），再开下去量到的只是翻滚中的速度。8 秒够跑完那段加速，
## 又不至于把时间全花在追一台已经死掉的车。
const DRIVE_SECONDS := 8.0
## 起点 x，和 [constant tests/vehicles_drive.START_X] 一致。
const START_X := 200.0
## 指针允许落在量程的哪一段。下限防「表盘大得没边」（针永远贴着 0 也白搭），
## 上限防「顶表」（顶到头就分不出 250 和 280 了）。
const RATIO_MIN := 0.25
const RATIO_MAX := 0.85
## 道具栏最多几格。按最宽的情况算版面 —— 道具再多一格就会先在这里响，
## 而不是等跑到游戏里才发现表压着道具栏。
const ITEM_COUNT := 3
## 版面按哪个窗口算。取 project.godot 里那对真实值，理由见 [method _case_layout]。
const VIEW := Vector2(1280.0, 720.0)

var _failures := 0


func _ready() -> void:
	SaveData.persist = false
	SaveData.reset_progress()
	_case_convert()
	_case_dial_range()
	await _case_live()
	await _case_layout()
	print("")
	if _failures == 0:
		print("全部通过")
	else:
		print("!! %d 项不通过" % _failures)
	get_tree().quit()


# ------------------------------------------------------------ A 换算

func _case_convert() -> void:
	print("=== 换算 ===")
	# 100 px/s ÷ 10 px/m = 10 m/s = 36 km/h
	_approx("100 px/s = 36 km/h", HillDashboard.speed_kmh_of(Vector2(100.0, 0.0)), 36.0, 0.01)
	# 取**大小**：竖直方向和反方向都是同一个数
	_approx("竖直 100 px/s 也是 36", HillDashboard.speed_kmh_of(Vector2(0.0, -100.0)), 36.0, 0.01)
	_approx("倒着开 100 px/s 也是 36", HillDashboard.speed_kmh_of(Vector2(-100.0, 0.0)), 36.0, 0.01)
	_approx("停着是 0", HillDashboard.speed_kmh_of(Vector2.ZERO), 0.0, 0.01)

	# 一圈 = TAU 弧度/秒 = 60 rpm
	_approx("TAU rad/s = 60 rpm", HillDashboard.rpm_of(TAU), 60.0, 0.01)
	_approx("50 rad/s = 477.5 rpm", HillDashboard.rpm_of(50.0), 50.0 * 60.0 / TAU, 0.01)
	_approx("不转 = 0 rpm", HillDashboard.rpm_of(0.0), 0.0, 0.01)

	# 指针几何：屏幕坐标 y 朝下，所以 0 → 左下、0.5 → 正上、1 → 右下。
	# **这几条是「正角度是顺时针」那个约定的看门狗** —— 哪天有人把符号改反了，
	# 表针会整个镜像过来（0 跑到右下、1 跑到左下），只有这里会响。
	var c := Vector2(100.0, 100.0)
	var lo := HillDashboard.tip_of(c, 100.0, 0.0)
	var mid := HillDashboard.tip_of(c, 100.0, 0.5)
	var hi := HillDashboard.tip_of(c, 100.0, 1.0)
	_check("0 的针在圆心的左下", lo.x < c.x and lo.y > c.y, true)
	_check("1 的针在圆心的右下", hi.x > c.x and hi.y > c.y, true)
	_check("0.5 的针在圆心正上方", mid.y < c.y and absf(mid.x - c.x) < 0.01, true)
	_approx("0.5 的针正好指向正上（270°）", rad_to_deg(HillDashboard.angle_for(0.5)), 270.0, 0.01)
	_approx("0 和 1 之间就是整个扫角",
			rad_to_deg(HillDashboard.angle_for(1.0) - HillDashboard.angle_for(0.0)),
			HillDashboard.SWEEP_DEG, 0.01)
	# 超量程要**钉住**，不能绕圈 —— 绕回 0 看着像车停了
	_check("超过 1 钉在 1 上", HillDashboard.angle_for(1.8), HillDashboard.angle_for(1.0))
	_check("小于 0 钉在 0 上", HillDashboard.angle_for(-0.5), HillDashboard.angle_for(0.0))
	# 顺带把扫角本身钉住：240° 是「下半圈敞口」那个设计的数字，
	# 改小了数字读数会被针扫到，改大了指针会挤成一条。
	_check("扫角就是 240°", HillDashboard.SWEEP_DEG, 240.0)


# ------------------------------------------------------------ B 量程

func _case_dial_range() -> void:
	print("=== 量程 ===")
	# [method HillDashboard.dial_max] 只负责「向上取整到整格」，不负责判断合不合理
	_check("472.5 取整到 500", HillDashboard.dial_max(472.5, 100.0), 500.0)
	_check("596.8 取整到 600", HillDashboard.dial_max(596.8, 100.0), 600.0)
	_check("正好整格就不动", HillDashboard.dial_max(600.0, 200.0), 600.0)
	# 兜底：算出来不到一格时给一格，否则量程是 0 —— 下面每一处除法都会变成 inf/NaN
	_check("不到一格时给一格", HillDashboard.dial_max(0.4, 100.0), 100.0)

	# 轮半径读的是**碰撞形状**，不是导出变量。四辆车的轮径各不相同，这条是它的看门狗
	# —— 哪辆车换了轮子而轮速表没跟着变，这里会响。
	for id in Vehicles.IDS:
		var v = Vehicles.instantiate(id)
		_check("%s 的轮半径取自碰撞形状" % id, HillDashboard.wheel_radius_of(v),
				float(Vehicles.stats(id)["radius"]))
		v.free()

	# **不进树**：`_measure_dials` 只要 `max_wheel_speed` 和轮子的碰撞形状，
	# 而进了树 `car._ready()` 就会再 `Upgrades.apply` 一遍存档里的等级，
	# 「Lv0」这个前提就没了。顺带也躲开 `_apply_inertia_scale` 那个跨帧的 await。
	var car = CAR.instantiate()
	var dash := HillDashboard.new()
	dash.setup(car, ThemeDB.fallback_font, false)
	_check("默认车 Lv0 的车速表量程", dash._dial_speed, 500.0)
	_check("默认车 Lv0 的轮速表量程", dash._dial_rpm, 600.0)

	# 极速满级（×1.263）之后量程要跟着涨，否则满级车一起步表针就顶死了
	Upgrades.apply(car, {"speed": Upgrades.MAX_LEVEL})
	dash.setup(car, ThemeDB.fallback_font, false)
	_check("极速满级后的车速表量程", dash._dial_speed, 600.0)
	_check("极速满级后的轮速表量程", dash._dial_rpm, 800.0)
	dash.free()
	car.free()


# ------------------------------------------------------------ C 实机

func _case_live() -> void:
	print("=== 实机（开 %.0f 秒，平原，默认车 Lv0）===" % DRIVE_SECONDS)
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	for i in range(3):
		await get_tree().process_frame
	var car: HillCar = main.car
	var dash: HillDashboard = main.hud._dashboard
	_check("HUD 建出了仪表盘", dash != null, true)
	if dash == null:
		return

	var peak_kmh := 0.0
	var peak_rpm := 0.0
	var peak_speed_ratio := 0.0
	var peak_rpm_ratio := 0.0
	Input.action_press("drive_forward")
	for i in int(DRIVE_SECONDS * 60.0):
		await get_tree().physics_frame
		peak_kmh = maxf(peak_kmh, HillDashboard.speed_kmh_of(car.chassis.linear_velocity))
		peak_rpm = maxf(peak_rpm, HillDashboard.rpm_of(absf(car.rear_wheel.angular_velocity)))
		peak_speed_ratio = maxf(peak_speed_ratio, dash.speed_ratio())
		peak_rpm_ratio = maxf(peak_rpm_ratio, dash.rpm_ratio())
	Input.action_release("drive_forward")
	print("  跑了 %.0f m，最高 %.1f km/h / %.0f rpm；表针最高到 %.0f%% / %.0f%%" % [
		(car.chassis.global_position.x - START_X) / Maps.PIXELS_PER_METER,
		peak_kmh, peak_rpm, peak_speed_ratio * 100.0, peak_rpm_ratio * 100.0,
	])

	# **这一组的正题**：量程要盖得住实机读数，又不能大得没边
	_between("车速表针的最高位置", peak_speed_ratio, RATIO_MIN, RATIO_MAX)
	_between("轮速表针的最高位置", peak_rpm_ratio, RATIO_MIN, RATIO_MAX)
	# 比例是 0~1 的数，任何情况下都不该越界（`clampf` 兜着，但兜底本身也可能是错的）
	_between("车速比例在 0~1 之间", dash.speed_ratio(), 0.0, 1.0)
	_between("轮速比例在 0~1 之间", dash.rpm_ratio(), 0.0, 1.0)

	# 结束面板要把它收起来：它是 HUD 的子节点，Godot 里孩子盖在父母之上，
	# 不收的话表针会浮在遮罩上面，看着像没擦干净。
	main.hud.show_game_over(HillCar.REASON_CRASH, 0, 100, false, 0)
	_check("结束面板弹出后仪表盘收起", dash.visible, false)
	main.queue_free()


# ------------------------------------------------------------ D 版面

func _case_layout() -> void:
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	for i in range(3):
		await get_tree().process_frame
	var dash: HillDashboard = main.hud._dashboard
	# 它得**跟着 HUD 走**：四个锚点全钉在边上，窗口一变形表盘自己就挪。
	_check("仪表盘四边跟着 HUD", [dash.anchor_right, dash.anchor_bottom], [1.0, 1.0])

	# **不能用 headless 的视口尺寸**：没有真窗口时 dummy 显示服务器给的是
	# 1280×1280（见 tests/hud_rect 的实测输出），真实窗口是 project.godot 里那对
	# 1280×720。[method HillDashboard.center_of] / [method HillDashboard.cluster_rect]
	# 全是 `size` 的纯函数，所以直接改 size 再算 —— 下面到打印为止**一帧都不 await**，
	# 锚点来不及把它改回去。
	dash.size = VIEW
	print("=== 版面（按真实窗口 %.0f×%.0f 计算）===" % [VIEW.x, VIEW.y])

	var block := dash.cluster_rect()
	print("  仪表盘占 x %.0f..%.0f，y %.0f..%.0f（宽 %.0f）" % [
		block.position.x, block.end.x, block.position.y, block.end.y, block.size.x,
	])
	_check("整块仪表盘在视口内", Rect2(Vector2.ZERO, VIEW).encloses(block), true)

	# 两个表盘自己不能叠在一起
	var a := Rect2(dash.center_of(0) - Vector2.ONE * HillDashboard.RADIUS,
			Vector2.ONE * HillDashboard.RADIUS * 2.0)
	var b := Rect2(dash.center_of(1) - Vector2.ONE * HillDashboard.RADIUS,
			Vector2.ONE * HillDashboard.RADIUS * 2.0)
	_check("两个表盘不重叠", a.intersects(b), false)
	_between("两个表盘之间的缝隙", b.position.x - a.end.x, 1.0, 80.0)

	# 左下角：油条 + 百分比 + 操作提示，都在 x 30 那一带
	var fuel := Rect2(Vector2(30.0, VIEW.y - 116.0), Vector2(360.0, 116.0))
	_check("不压到左下角的油条", block.intersects(fuel), false)

	# 右下角：道具栏（标签在 size.y - 66 那一条，格子从 size.y - 54 起）
	var item_w := float(ITEM_COUNT) * HillHud.ITEM_W
	item_w += float(ITEM_COUNT - 1) * HillHud.ITEM_GAP
	var items := Rect2(Vector2(VIEW.x - 30.0 - item_w, VIEW.y - 86.0),
			Vector2(item_w, 86.0))
	_check("不压到右下角的道具栏", block.intersects(items), false)
	print("  道具栏从 y %.0f 起，仪表盘底 %.0f，中间留了 %.0f" % [
		items.position.y, block.end.y, items.position.y - block.end.y,
	])

	# 左上角：顶栏四列。格子到 `30 + 3×COL` 为止，但列里真正画出来的文字没那么宽，
	# 所以拿**真实字体**把会画上去的字串量一遍，取最宽的那条 —— 直接拿 COL 当边界
	# 会得到「只剩 2 px」的假结论。
	var widest := 0.0
	if dash._font != null:
		for t in ["里程", "金币", "本图记录", "金币总数", "DISTANCE", "COINS", "BEST",
				"TOTAL COINS"]:
			widest = maxf(widest, dash._font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT,
					-1, HillHud.LABEL_SIZE).x)
		for t in ["12345 m", "19850"]:
			widest = maxf(widest, dash._font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT,
					-1, HillHud.VALUE_SIZE).x)
	var stats_right := 30.0 + 3.0 * HillHud.COL + widest
	print("  顶栏文字最宽 %.0f，占到 x %.0f；仪表盘从 %.0f 起，留了 %.0f" % [
		widest, stats_right, block.position.x, block.position.x - stats_right,
	])
	_check("不压到左边的顶栏", block.position.x > stats_right, true)
	main.queue_free()


# ------------------------------------------------------------ 工具

func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _approx(label: String, got: float, want: float, tol: float) -> void:
	var ok := absf(got - want) <= tol
	if not ok:
		_failures += 1
	print("  %s %s = %.4f（期望 %.4f ±%.4f）" % ["OK  " if ok else "FAIL", label, got, want, tol])


func _between(label: String, got: float, lo: float, hi: float) -> void:
	var ok := got >= lo and got <= hi
	if not ok:
		_failures += 1
	print("  %s %s = %.2f（期望 %.2f ~ %.2f）" % [
		"OK  " if ok else "FAIL", label, got, lo, hi,
	])
