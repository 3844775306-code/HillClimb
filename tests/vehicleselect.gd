extends Node
## 选车界面（单行轮播）的无头测试。
##
## 八节：
##   1. 光标   —— 开局停在哪、左右怎么绕、存档里是坏值时会不会崩
##   2. 命中   —— 哪个坐标算点中哪张卡（用 `_card_at` 判断，不真的点）
##   3. 版面   —— 摆出来的卡片不重叠、居中、在视口内
##   4. 轮播   —— 窗口怎么跟着光标滚、窗口外的卡点不到、箭头/滚轮怎么翻
##   5. 文案   —— 卡上六行字中英两份都不越出卡片
##   6. 预览   —— 卡片画的那辆车真的是场景里那辆车
##   7. 锁     —— 前两辆白送、其余每辆 100000，以及「点两下才买」这条手感
##   8. 车表   —— 每辆车的展示文案都齐
##
## **通了的卡一张都不点。** `_on_click()` / 回车都会走 `_pick()` →
## `change_scene_to_file()`，把测试场景本身换掉，测试当场就没了（后面
## `get_tree().quit()` 也不会跑到）。第 7 节能放心点的是**锁着的卡**：买不起就什么也
## 不发生，买下了也只是在原地解锁 —— 走通卡那条路交给 `tests/unlock`。
##
## 第 3~7 节**不挂进树**：无头视口是 1280×1280（README 坑 #7），挂进去量出来的尺寸
## 是假的。`_card_rect()` 只依赖 `size`，手工设定反而是真实窗口下的答案。
## 反过来第 1 节要跑 `_ready()`（它从存档里读光标），必须挂进树。
##
## 尺寸能写成硬断言，是因为 `stretch/mode = canvas_items` + `aspect = expand` + 基准
## 1280×720 意味着**虚拟尺寸两个方向都不会小于 1280×720**（窗口更宽时宽变大，更高时
## 高变大）。所以一屏四张时卡宽恒为 (1160 − 18×3) / 4 = 276.5，不是碰运气 ——
## **哪怕能选的车有八辆**，因为轮播一次也只摆四张（[constant HillVehicleSelect.VISIBLE]）。
## 这一条是「八辆车」那次改动里最容易失去的性质，所以第 3 节专门逐个张数量了一遍。

const SELECT := preload("res://scenes/vehicleselect.tscn")
const DESIGN := Vector2(1280.0, 720.0)
## 实际可能出现的虚拟尺寸：基准，以及各种宽高比被 `expand` 撑出来的结果。
const SIZES: Array[Vector2] = [
	Vector2(1280.0, 720.0),   # 16:9 基准
	Vector2(1280.0, 960.0),   # 4:3 窗口
	Vector2(1280.0, 1440.0),  # 竖屏
	Vector2(1720.0, 720.0),   # 21:9
	Vector2(2560.0, 1440.0),  # 2K
]
## 卡片左右各自留的空白（`_draw_card` 里文字从 +20 起画）。
const CARD_PAD := 20.0
## 量「两行字叠没叠上」时，一行字的**墨迹**（真的被涂上颜色的那部分）离基线有多远。
##
## **不能用 [method Font.get_ascent] / [method Font.get_descent]** —— 那两个数是字体的
## **行盒**（排版时留给这一行的整块高度，含行间空隙），比字真正占的地方大得多：中文字体
## 在 17 号下 ascent 就有 20 像素，于是完全正常的 21 像素行距也会被判成重叠。这两个比例
## 是字的实际墨迹范围（方块字上沿约 0.86 个字高，西文的上下伸部约 0.75 / 0.21），取
## 0.88 / 0.22 把中英两种都盖住。选图那一页的测试有同一条，那边还记着实测的过程。
const INK_UP := 0.88
const INK_DOWN := 0.22
## 「被底板切了一刀」的判据里，两头各留的余量（像素）。
const CUT_MIN := 2.0
## 锁卡底板上下沿，从 [HillLockBadge] 的常量推出来，不在这里抄数。
const PLATE_TOP := HillLockBadge.PLATE_TOP
const PLATE_BOTTOM := HillLockBadge.PLATE_TOP + HillLockBadge.PLATE_H

var _failures := 0


func _ready() -> void:
	SaveData.persist = false
	SaveData.reset_progress()
	await _test_cursor()
	print("")
	_test_hit()
	print("")
	_test_layout()
	print("")
	_test_carousel()
	print("")
	_test_preview()
	print("")
	_test_lock()
	print("")
	_test_table()
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


## 一张脱离场景树、尺寸按真实窗口设好的选车界面。
func _new_screen() -> HillVehicleSelect:
	var s: HillVehicleSelect = SELECT.instantiate()
	# 场景里锚点是「铺满父节点」，不挂进树时直接改 size 会被锚点盖回去。
	# 先把锚点拉平，警告也就没了（和选图那份一个道理）。
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = DESIGN
	# **要手动叫一次 `_ready()`。** 不挂进树它永远不会跑，于是 `_cjk` 还是 false
	# —— `_t()` 会一路返回英文，量出来的宽度全是英文的。这台机器上真跑起来用的是
	# 中文，量英文等于没量。
	s._ready()
	return s


# ---------------------------------------------------------------- 光标

func _test_cursor() -> void:
	print("=== 光标 ===")
	# 用**车表里根本没有的 id**，不能用「还没做出来的车」——四辆车现在全都做出来了，
	# 拿 bus 当反例的话这条用例测的就变成了「bus 排在第几张」，恒等于 3 而不是 0，
	# 看着像失败其实什么也没验到。直接赋值绕过 select_vehicle 的校验，模拟坏档。
	SaveData.selected_vehicle = "hovercraft"
	var s: HillVehicleSelect = SELECT.instantiate()
	add_child(s)
	await get_tree().process_frame
	# 光标停在**真的能选的那些车**里的位置，不是 Vehicles.IDS 里的位置：坏档里那辆车
	# 不在 available() 里，find 给 -1，光标得退回第一张而不是变成 -1（那样按回车就是
	# `_ids[-1]`，GDScript 的负数索引会取到最后一张，看着「能用」，其实是巧合）。
	_check("存档里的车不认识时光标落在第 0 张", s._sel == 0,
			"存档选了 %s，能选的是 %s，光标在第 %d 张" % [
				SaveData.selected_vehicle, str(Vehicles.available()), s._sel])

	SaveData.select_vehicle(Vehicles.JEEP)
	var s2: HillVehicleSelect = SELECT.instantiate()
	add_child(s2)
	await get_tree().process_frame
	var want := Vehicles.available().find(Vehicles.JEEP)
	_check("开局光标停在存档里选的那辆车上", s2._sel == want,
			"光标在第 %d 张，越野车是第 %d 张" % [s2._sel, want])

	# 左右首尾环绕，撞到头不会卡住
	s2._sel = 0
	s2._move(-1)
	_check("从第 0 张往左绕到最后一张", s2._sel == s2._ids.size() - 1, "→ 第 %d 张" % s2._sel)
	s2._move(1)
	_check("再往右回到第 0 张", s2._sel == 0, "→ 第 %d 张" % s2._sel)

	# 一辆车都没有的极端情况（场景被删光）。`_move` / `_pick` 不能除零或越界。
	s2._ids.clear()
	s2._move(1)
	s2._pick(0)
	_check("一辆车都读不出来时光标和选择都不崩", s2._sel == 0, "光标仍是第 %d 张" % s2._sel)

	s.queue_free()
	s2.queue_free()
	print("  能选的车：%s（共 %d 辆，Vehicles.IDS 里有 %d 辆）" % [
		str(Vehicles.available()), Vehicles.available().size(), Vehicles.IDS.size()])


# ---------------------------------------------------------------- 命中

func _test_hit() -> void:
	print("=== 命中 ===")
	var s := _new_screen()
	# **只点摆出来的那些。** 现在能选的车有八辆，窗口外那几张的 `_card_rect()` 是空
	# 矩形、`get_center()` 恒为 (0,0)，把它们也塞进这一轮，等于在测「原点算不算点中
	# 第 5 张卡」。窗口外点不到那件事由第 4 节用正经的探针量。
	var vis := HillVehicleSelect.VISIBLE
	var shown: Array[int] = []
	for i in range(s._ids.size()):
		if s._card_rect(i).has_area():
			shown.append(i)

	var centers := PackedStringArray()
	var all_hit := true
	for i in shown:
		var r := s._card_rect(i)
		var hit := s._card_at(r.get_center())
		if hit != i:
			all_hit = false
		centers.append("卡%d→%d" % [i + 1, hit + 1])
	_check("摆出来的每张卡中心都命中自己（共 %d 张，一屏 %d）" % [shown.size(), vis],
			all_hit and shown.size() == mini(s._ids.size(), vis), "，".join(centers))

	# 卡外的地方一个都不该命中。**按节点坐标点，不是按画面坐标** —— 卡是从
	# CARD_TOP 往下的竖条，标题区和页脚都在它的上下，缝隙在它左右。
	var gap_x := s._card_rect(0).end.x + HillVehicleSelect.GAP * 0.5
	var mid_y := s._card_rect(0).get_center().y
	var probes := {
		"卡间缝隙": Vector2(gap_x, mid_y),
		"标题区": Vector2(DESIGN.x * 0.5, 100.0),
		"卡片上方": Vector2(DESIGN.x * 0.5, HillVehicleSelect.CARD_TOP - 10.0),
		"卡片下方": Vector2(DESIGN.x * 0.5,
				HillVehicleSelect.CARD_TOP + HillVehicleSelect.CARD_H + 10.0),
		"页脚": Vector2(DESIGN.x * 0.5, DESIGN.y - 10.0),
		"左边缘": Vector2(10.0, mid_y),
		"右边缘": Vector2(DESIGN.x - 10.0, mid_y),
	}
	var stray := PackedStringArray()
	for label: String in probes:
		var p: Vector2 = probes[label]
		var hit := s._card_at(p)
		if hit != -1:
			stray.append("%s(%.0f,%.0f)→卡%d" % [label, p.x, p.y, hit + 1])
	_check("卡外的地方都不算命中", stray.is_empty(),
			"试了 %d 处，误命中：%s" % [probes.size(),
			"无" if stray.is_empty() else "，".join(stray)])
	s.free()


# ---------------------------------------------------------------- 版面

func _test_layout() -> void:
	print("=== 版面 ===")
	var s := _new_screen()
	print("  能选 %d 辆，一屏 %d 张，卡宽 %.1f，文字可用 %.1f，中文字体：%s" % [
		s._ids.size(), HillVehicleSelect.VISIBLE, s._card_rect(0).size.x,
		s._card_rect(0).size.x - CARD_PAD * 2.0,
		"有" if s._cjk else "没有，按英文量"])

	# 先按**现在真能选的**车量一遍，再逐个数几个张数各量一遍。
	# **卡宽必须和「几辆」无关** —— 一屏摆四张时它是 276.5，这个数同时约束着车库、
	# 选图那两页的文案（那两页的注释就写着「都是 1160 面板里的 276.5」）。轮播一旦
	# 写成「按总张数分面板」，八辆车时卡宽会掉到 129.3，卡上那六行字统统放不下，
	# 而画出去是画到隔壁卡上，截图上只会看到两个字叠在一起。
	_geometry(s, s._ids, "现状")
	var one: Array[String] = [Vehicles.IDS[0]]
	_geometry(s, one, "一辆车时")
	_geometry(s, Vehicles.IDS.slice(0, 3), "三辆车时")
	_geometry(s, Vehicles.IDS, "八辆车时")
	_geometry(s, Vehicles.IDS.slice(0, 7), "七辆车时")

	s._ids = Vehicles.IDS.duplicate()
	s.size = DESIGN
	_text_fit(s)
	s.free()


## 一个给定的车辆张数下，**摆出来的**那几张卡互相不压、整体居中、都在视口里、
## 上下都躲开文字，而且卡宽恒等于一屏四张的宽度。
##
## 只看摆出来的那些：轮播一屏摆 [constant HillVehicleSelect.VISIBLE] 张，其余的
## `_card_rect()` 返回空矩形。空矩形 `intersects()` / `has_point()` 都恒为假，混在
## 一起不会让下面几条判断失真，但**「一共摆出来几张」得单独数** —— 否则某辆车被窗口
## 挤到屏幕外的 bug 在这张表里是全绿的，因为那张卡压根没进比较。
func _geometry(s: HillVehicleSelect, ids: Array[String], tag: String) -> void:
	var real := s._ids
	var real_sel := s._sel
	var real_first := s._first
	s._ids = ids.duplicate()
	s._sel = 0
	s._first = 0

	var n := s._ids.size()
	var want := mini(n, HillVehicleSelect.VISIBLE)
	var overlap := PackedStringArray()
	var outside := PackedStringArray()
	var off_center := PackedStringArray()
	var tight := PackedStringArray()
	var wrong_count := PackedStringArray()
	var wrong_order := PackedStringArray()
	var wrong_w := PackedStringArray()
	var head := ""
	for sz: Vector2 in SIZES:
		s.size = sz
		var rects: Array[Rect2] = []
		var shown: Array[int] = []
		for i in range(n):
			var r := s._card_rect(i)
			if r.has_area():
				rects.append(r)
				shown.append(i)
		var size_tag := "%.0f×%.0f" % [sz.x, sz.y]
		if head.is_empty():
			head = "卡 1 %.0f..%.0f 宽 %.1f，卡底 %.0f" % [
				rects[0].position.x, rects[rects.size() - 1].end.x,
				rects[0].size.x, rects[rects.size() - 1].end.y]

		if rects.size() != want:
			wrong_count.append("%s 摆了 %d 张" % [size_tag, rects.size()])
		for k in range(shown.size()):
			if shown[k] != k:
				wrong_order.append("%s 第%d 格是第%d 辆" % [size_tag, k, shown[k]])
		for r: Rect2 in rects:
			if not is_equal_approx(r.size.x, 276.5):
				wrong_w.append("%s 宽 %.1f" % [size_tag, r.size.x])

		var first: Rect2 = rects[0]
		var last: Rect2 = rects[rects.size() - 1]
		for r: Rect2 in rects:
			if r.position.x < 0.0 or r.end.x > sz.x + 0.001 \
					or r.position.y < 0.0 or r.end.y > sz.y + 0.001:
				outside.append(size_tag)
				break
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				if (rects[i] as Rect2).intersects(rects[j]):
					overlap.append("%s 卡%d∩卡%d" % [size_tag, i + 1, j + 1])
		# 居中：左边距 = 右边距
		if not is_equal_approx(first.position.x, sz.x - last.end.x):
			off_center.append("%s 左%.0f/右%.0f" % [size_tag, first.position.x, sz.x - last.end.x])
		# 上下留白：卡顶要躲开副标题（基线 114），卡底要躲开页脚（基线 size.y − 26）
		if first.position.y < 130.0 or last.end.y > sz.y - 44.0:
			tight.append(size_tag)
		# 指示器那排圆点得落在卡底和页脚之间，压在卡上或压到页脚上都算版面坏了。
		if HillVehicleSelect.DOT_Y - HillVehicleSelect.DOT_R < last.end.y \
				or HillVehicleSelect.DOT_Y + HillVehicleSelect.DOT_R + 10.0 > sz.y - 44.0:
			tight.append("%s 圆点" % size_tag)

	s.size = DESIGN
	s._ids = real
	s._sel = real_sel
	s._first = real_first
	var at := "%d 辆" % n
	_check("%s：摆出来的正好 %d 张" % [tag, want], wrong_count.is_empty(),
			"%d 种尺寸都是 %d 张" % [SIZES.size(), want] if wrong_count.is_empty()
			else "，".join(wrong_count))
	_check("%s：卡片从左到右就是车表顺序" % tag, wrong_order.is_empty(),
			"第 0..%d 格依次是第 0..%d 辆" % [want - 1, want - 1] if wrong_order.is_empty()
			else "，".join(wrong_order))
	# 这一条是整节的重点，见函数头的注释。
	_check("%s：卡宽恒为 276.5（和总张数无关）" % tag, wrong_w.is_empty(),
			"%s，一屏 %d 张 → (1160 − 18×%d) / %d = 276.5" % [
				at, HillVehicleSelect.VISIBLE, HillVehicleSelect.VISIBLE - 1,
				HillVehicleSelect.VISIBLE] if wrong_w.is_empty()
			else "，".join(wrong_w))
	_check("%s：卡片两两不重叠" % tag, overlap.is_empty(),
			head if overlap.is_empty() else "，".join(overlap))
	_check("%s：卡片都在视口内" % tag, outside.is_empty(),
			"%s（%d 种尺寸）" % [head, SIZES.size()] if outside.is_empty()
			else "越界：%s" % "，".join(outside))
	_check("%s：卡片整体水平居中" % tag, off_center.is_empty(),
			"%s（%d 种尺寸都居中）" % [head, SIZES.size()] if off_center.is_empty()
			else "，".join(off_center))
	_check("%s：卡顶躲开标题、卡底躲开页脚和圆点" % tag, tight.is_empty(),
			"%s（%d 种尺寸）" % [head, SIZES.size()] if tight.is_empty()
			else "，".join(tight))


# ---------------------------------------------------------------- 轮播

## 窗口怎么跟着光标滚。
##
## 四条性质，都是「卡一多就看不出来、但它错了会很难受」的：
##
## 1. **光标永远看得见**。滚窗口的所有逻辑都是为了这一条，它一旦不成立，玩家按方向
##    键会走到一张屏幕上没有的卡上 —— 回车进车库时开的是另一辆车，看着像存档坏了。
## 2. **一次只滚一格**。要么不做要么跳一整屏的话，从第 3 辆按右键跳到第 7 辆，
##    中间几辆玩家根本没看见，等于白做。
## 3. **走到窗口尽头才滚**。光标在窗口中间时窗口不动 —— 每按一次方向键整行都滑一下
##    会晕，而且卡上的字每帧都在重画。
## 4. **窗口外的卡点不到**。这是 `_card_rect()` 返回空矩形换来的，看着像白送，
##    但「空矩形的 `has_point()` 恒为假」是个容易被后来人「顺手改成
##    `Rect2(0,0,w,h)` 把下标的坐标固定下来」的前提，所以钉一条用例。
func _test_carousel() -> void:
	print("=== 轮播 ===")
	var s := _new_screen()
	s._ids = Vehicles.IDS.duplicate()
	var n := s._ids.size()
	var vis := HillVehicleSelect.VISIBLE
	var slots := ""

	# 开局窗口停在最左边（存档里是越野车 = 第 0 辆）。
	s._sel = 0
	s._first = 0
	s._follow()
	_check("开局窗口不绕到后面去", s._first == 0, "窗口从第 %d 辆起" % s._first)

	# 1 + 3：一路往右走完一整圈，每一步都要求光标可见，并且记下窗口什么时候动。
	var blind := PackedStringArray()
	var jumped := PackedStringArray()
	var moved_at := PackedStringArray()
	var prev := s._first
	for step in range(n):
		s._move(1)
		if s._slot_of(s._sel) >= vis or s._slot_of(s._sel) < 0:
			blind.append("第%d步 光标%d 窗口%d" % [step, s._sel, s._first])
		var d := wrapi(s._first - prev, 0, n)
		if d != 0 and d != 1:
			jumped.append("第%d步 窗口 %d→%d" % [step, prev, s._first])
		if d == 1:
			moved_at.append("第%d步" % step)
		prev = s._first
		if step < 12:
			slots += "%d" % s._sel
	_check("走一整圈光标始终在窗口里", blind.is_empty(),
			"第 %d..%d 辆都看得见" % [n - vis + 1, n] if blind.is_empty() else "，".join(blind))
	_check("每次滚窗口都只滚一格", jumped.is_empty(),
			"滚了 %d 次：%s" % [moved_at.size(), "，".join(moved_at)] if jumped.is_empty()
			else "，".join(jumped))
	# 走完一整圈光标回到第 0 辆，窗口**不会**跟着回到 0 —— 它是个滑动的窗口，不是
	# 「光标在第几辆就把窗口摆到第几辆开始」。一整圈前进 `n − VISIBLE + 1` 格：
	# 前 VISIBLE−1 步光标在窗口里走（窗口不动），之后每一步滚一格。
	#
	# 这两个数一起钉住才有意义：只钉光标的话，一个「光标回来了但窗口绕了半圈」
	# 的实现也全绿，而那种实现在玩家手里就是每圈都跳一下。
	var laps := n - vis + 1
	_check("走完一整圈光标回到出发点，窗口正好前进一圈应走的格数",
			s._sel == 0 and s._first == laps,
			"光标 %d（期望 0），窗口 %d（期望 %d）" % [s._sel, s._first, laps])

	# 4：窗口外的卡点不到，窗口里的点得到。
	#
	# 探针要探**它要是被画出来会在哪** —— 也就是「第 VISIBLE 格、第 VISIBLE+1 格…」
	# 那些格子的中心。写成「屏幕外随便一个点」等于什么都没验：任何实现都返回 −1。
	var outside_hit := PackedStringArray()
	var inside_miss := PackedStringArray()
	s._sel = 3
	s._first = 0
	var w := s._card_w()
	var left := s._row_left()
	for i in range(n):
		var r := s._card_rect(i)
		var slot := s._slot_of(i)
		if slot >= 0 and slot < vis:
			if not r.has_area() or s._card_at(r.get_center()) != i:
				inside_miss.append("第%d辆" % i)
			continue
		if r.has_area():
			outside_hit.append("第%d辆还有矩形 %s" % [i, str(r)])
		# 第 slot 格（slot ≥ VISIBLE，在面板右边外面）
		for probe_slot in range(vis, vis + 2):
			var p := Vector2(left + float(probe_slot) * (w + HillVehicleSelect.GAP) + w * 0.5,
					HillVehicleSelect.CARD_TOP + HillVehicleSelect.CARD_H * 0.5)
			if s._card_at(p) != -1:
				outside_hit.append("第%d辆在第%d格被点到" % [i, probe_slot])
	_check("窗口里的卡点得到", inside_miss.is_empty(),
			"窗口盖住第 0..%d 辆，%d 张都命中自己" % [vis - 1, vis] if inside_miss.is_empty()
			else "，".join(inside_miss))
	_check("窗口外的卡既没矩形也点不到", outside_hit.is_empty(),
			"窗口盖住第 %d..%d 辆，其余 %d 辆都在外面" % [0, vis - 1, n - vis]
			if outside_hit.is_empty() else "，".join(outside_hit))

	# 2：绕回去那一格也只滚一格（第 0 辆往左 → 最后一辆）。
	s._sel = 0
	s._first = 0
	s._follow()
	s._move(-1)
	_check("从第 0 辆往左绕：光标到最后一辆、窗口只退一格",
			s._sel == n - 1 and s._first == n - 1,
			"光标 %d（期望 %d），窗口从第 %d 辆起（期望 %d）" % [
				s._sel, n - 1, s._first, n - 1])
	# **绕过来的那辆填的是最左边那一格**，不是最右边：往左走，光标是从左边滑进来
	# 的，新露出来的那张卡就该出现在左端。落到最右边的话，玩家看到的是光标跳到了
	# 屏幕另一头 —— 而这时窗口其实没动，「一次只滚一格」也就自相矛盾了。
	_check("绕过去的那辆落在最左边那一格", s._slot_of(s._sel) == 0,
			"格位 %d（一屏 %d 格，最左是 0）" % [s._slot_of(s._sel), vis])

	# 反方向也得对称：从最后一辆往右绕回第 0 辆时，第 0 辆落在**最右边**那一格。
	s._sel = n - 1
	s._first = n - vis
	s._follow()
	s._move(1)
	_check("从最后一辆往右绕：光标到第 0 辆，落在最右边那一格",
			s._sel == 0 and s._slot_of(s._sel) == vis - 1 and s._first == n - vis + 1,
			"光标 %d，窗口从第 %d 辆起（期望 %d），格位 %d（期望 %d）" % [
				s._sel, s._first, n - vis + 1, s._slot_of(s._sel), vis - 1])

	# 存档里开着排在很后面的车（第 6 辆 = 坦克）时，开局窗口要一次滚到位。
	s._sel = n - 2
	s._first = 0
	s._follow()
	_check("存档里的车排在很后面时开局就看得见",
			s._slot_of(s._sel) >= 0 and s._slot_of(s._sel) < vis,
			"光标第 %d 辆，窗口从第 %d 辆起，落在第 %d 格" % [
				s._sel, s._first, s._slot_of(s._sel)])

	# 车比一屏少的话根本不该有窗口 —— 这时 `_slot_of` 走的是「照原顺序摆」那条支，
	# 不取模。取模的话 3 辆车时会算成 wrapi(3−0, 0, 3) = 0，第 3 辆会盖在第 0 辆上。
	s._ids = Vehicles.IDS.slice(0, 3)
	s._sel = 2
	s._first = 0
	s._follow()
	var deg := PackedStringArray()
	for i in range(3):
		deg.append("%d→格%d" % [i, s._slot_of(i)])
	_check("车比一屏少时不开窗口（不取模）", s._slot_of(2) == 2 and s._first == 0,
			"三辆车：%s" % "，".join(deg))

	# 箭头热区：只在真还有窗口外的车时才存在，而且不能压到卡片上。
	s._ids = Vehicles.IDS.duplicate()
	var left_arrow := s._row_left() - HillVehicleSelect.ARROW_OUT
	var mid_y := HillVehicleSelect.CARD_TOP + HillVehicleSelect.CARD_H * 0.5
	var arrow_bad := PackedStringArray()
	if s._arrow_at(Vector2(left_arrow, mid_y)) != -1:
		arrow_bad.append("左箭头没认出来")
	if s._arrow_at(Vector2(s.size.x - (left_arrow), mid_y)) != 1:
		arrow_bad.append("右箭头没认出来")
	if s._arrow_at(Vector2(s.size.x * 0.5, mid_y)) != 0:
		arrow_bad.append("屏幕中间被当成了箭头")
	var card0 := s._card_rect(0)
	if s._arrow_at(card0.get_center()) != 0:
		arrow_bad.append("卡片中心被当成了箭头")
	_check("箭头热区认得准，也不压卡片", arrow_bad.is_empty(),
			"左箭头 @%.0f、右箭头 @%.0f，卡片从 %.0f 起" % [
				left_arrow, s.size.x - left_arrow, card0.position.x]
			if arrow_bad.is_empty() else "，".join(arrow_bad))

	s._ids = Vehicles.IDS.slice(0, 2)
	_check("车比一屏少时没有箭头", s._arrow_at(Vector2(left_arrow, mid_y)) == 0,
			"两辆车，箭头不出现")
	s.free()


# ---------------------------------------------------------------- 文案

## 卡片上那六行字逐个量宽，**中英两份都量**。
##
## 卡宽固定 276.5，左右各留 20，剩 **236.5** 给文字；文案一改（尤其中文说明句）就可能
## 悄悄撑出去 —— 而撑出去是画到**隔壁卡**上，不是被裁掉，无头跑图看不出来，只看得到
## 两张卡的字叠在一起。所以**缩号之后两份都必须放得下**，那条是断死的：
## `_draw_card` 里画的时候就是这么缩的（[method HillMapSelect.fit_size]）。
##
## **一律按四辆车的卡宽量，不按当前张数。** 现在只有越野车做出来了，界面上是一张
## 1160 宽的卡，那时文字可用 1120 —— 拿它量等于什么都没量（最宽的一行才 315）。
## 四张卡的 236.5 才是这页真正会遇到的宽度，而且车一辆辆做出来之后它不会变。
##
## 文案行（车名/定位/说明）四辆车的都量得到，它们只跟 `Vehicles.VEHICLES` 里的文案
## 走；数字行（车重/油箱/推重比）只量得到做出来的那些车，因为数字是从场景里读的。
##
## 行序和字号必须和 `_draw_card()` 里一致 —— 对不上就等于没量。
func _text_fit(s: HillVehicleSelect) -> void:
	var real := s._ids
	s._ids = Vehicles.IDS.duplicate()
	var room := s._card_rect(0).size.x - CARD_PAD * 2.0
	s._ids = real

	var zh := _measure(s, room)
	# 没有中文字体的机器（Linux 发行版常见，见 [UiFonts]）上显示的是英文那一份，
	# 字体也跟着换成主题默认字体。`_ready()` 里分的正是这个支，这里照着摆一遍
	# ——量到的才是那台机器上真正会画出来的字。
	var en_s := _new_screen()
	en_s._cjk = false
	en_s._font = en_s.get_theme_default_font()
	var en := _measure(en_s, room)
	en_s.free()

	print("  文字可用 %.1f（四辆车的卡宽 %.1f 减两侧留白）" % [
		room, room + CARD_PAD * 2.0])
	print("  中文版：%s" % zh["line"])
	print("  英文版（无中文字体时用）：%s" % en["line"])
	var bad := PackedStringArray()
	bad.append_array(zh["fitted_bad"])
	bad.append_array(en["fitted_bad"])
	var shrunk := PackedStringArray()
	shrunk.append_array(zh["shrunk"])
	shrunk.append_array(en["shrunk"])
	_check("六行字缩号之后都放得下（中英各一份）", bad.is_empty(),
			"缩过 %d 行：%s" % [shrunk.size(), "，".join(shrunk)] if bad.is_empty()
			else "，".join(bad))

	# 竖着两条和选图那一页一样，只是这里量的是**车的卡**：相邻两行字的墨迹不许相交，
	# 锁卡那块底板也不许从当中切开任何一行。两条都只在「知道每行基线落在哪儿」时才算
	# 得出来，而基线是从 [constant HillVehicleSelect.LINE_NAME] 那组常量读的。
	_check("卡上相邻两行字不上下重叠（中文）", zh["stack"].is_empty(),
			"每张卡七行字都错开了" if zh["stack"].is_empty() else "，".join(zh["stack"]))
	_check("卡上相邻两行字不上下重叠（英文）", en["stack"].is_empty(),
			"每张卡七行字都错开了" if en["stack"].is_empty() else "，".join(en["stack"]))
	_check("锁卡底板不把任何一行字从当中切开（中文）", zh["cut"].is_empty(),
			"底板 %d..%d，卡上每行都整个在里面或整个在外面" % [PLATE_TOP, PLATE_BOTTOM]
			if zh["cut"].is_empty() else "，".join(zh["cut"]))
	_check("锁卡底板不把任何一行字从当中切开（英文）", en["cut"].is_empty(),
			"底板 %d..%d" % [PLATE_TOP, PLATE_BOTTOM] if en["cut"].is_empty()
			else "，".join(en["cut"]))


## 卡片上每行字的量宽量高结果。`fitted_bad` 是缩号之后仍撑出去的，`shrunk` 是缩过号的，
## `stack` 是上下叠在一起的，`cut` 是被锁卡底板从当中切开的，`line` 是给打印用的。
##
## 行序、字号、基线全部**从 [HillVehicleSelect] 的常量里读**，不在这里抄一份数：抄了就
## 一定会漂 —— 布局改了、量还是旧位置，两边都自认为对。选图那一页同一条。
func _measure(s: HillVehicleSelect, room: float) -> Dictionary:
	var fitted_bad := PackedStringArray()
	var shrunk := PackedStringArray()
	var stack := PackedStringArray()
	var cut := PackedStringArray()
	var worst := 0.0
	var what := ""
	var measured := 0
	var P := HillVehicleSelect.PREVIEW_H
	var H := HillVehicleSelect.CARD_H
	for id: String in Vehicles.IDS:
		var v: Dictionary = Vehicles.get_vehicle(id)
		# 文案行：四辆车都量。数字行只有在场景做出来之后才拼得出来（`stats()` 返回
		# 空表时那两行会是「—」），所以先按空表量一遍 —— 那是这辆车真做出来之前，
		# 万一它哪天真出现在卡片上会画出来的宽度。
		var st: Dictionary = Vehicles.stats(id)
		# 和 `_draw_card` 同序：[文字, 字号, 基线, 名字]
		var lines: Array = [
			[s._t(v["zh"], v["en"]), 36, P + HillVehicleSelect.LINE_NAME, "车名"],
			[s._t(v["zh_role"], v["en_role"]), 21, P + HillVehicleSelect.LINE_ROLE, "定位标签"],
			[s._t(v["zh_note"], v["en_note"]), 15, P + HillVehicleSelect.LINE_NOTE, "说明"],
			# 翘头线四辆车一样，但仍放在循环里 —— 量的是「卡片上真会画出来的那几行」，
			# 行序和 `_draw_card()` 对齐比省一次循环重要。
			[s._wheelie_line(), 15, H + HillVehicleSelect.LINE_WHEELIE, "翘头线"],
		]
		if not st.is_empty():
			measured += 1
			lines.append([s._size_line(st), 16, P + HillVehicleSelect.LINE_SIZE, "车重行"])
			lines.append([s._fuel_line(st), 16, P + HillVehicleSelect.LINE_FUEL, "油箱行"])
			lines.append([s._ratio_line(id), 18, H + HillVehicleSelect.LINE_RATIO, "推重比"])
		# 这一张卡上所有真会画出来的行：(基线, 字号, 文字, 出处)
		var drawn: Array = []
		for row: Array in lines:
			var text: String = row[0]
			var px: int = row[1]
			var where := "%s 的%s" % [v["zh"], row[3]]
			var w := s._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if w > worst:
				worst = w
				what = where
			var fit := HillMapSelect.fit_size(s._font, text, px, room)
			if fit < px:
				shrunk.append("%s %d→%d" % [where, px, fit])
			if s._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fit).x > room:
				fitted_bad.append("%s 缩到 %d 号仍放不下「%s」" % [where, fit, text])
			drawn.append([row[2], fit, text, where])

		# 竖着：按基线排序，相邻两行的墨迹不许相交（墨迹怎么算见 INK_UP / INK_DOWN）
		drawn.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for k in range(1, drawn.size()):
			var prev: Array = drawn[k - 1]
			var cur: Array = drawn[k]
			var bottom: float = prev[0] + INK_DOWN * float(prev[1])
			var top: float = cur[0] - INK_UP * float(cur[1])
			if bottom > top:
				stack.append("%s：「%s」压住「%s」（%.1f > %.1f）" % [
					v["zh"], prev[2], cur[2], bottom, top])

		# 被锁卡底板压住的那几行只能整个进去或整个出来（见 [HillLockBadge]）
		for row: Array in drawn:
			var ink_h := float(row[1]) * (INK_UP + INK_DOWN)
			var ink_top: float = row[0] - INK_UP * float(row[1])
			var ink_bottom: float = row[0] + INK_DOWN * float(row[1])
			var covered := minf(ink_bottom, PLATE_BOTTOM) - maxf(ink_top, PLATE_TOP)
			if covered > CUT_MIN and covered < ink_h - CUT_MIN:
				cut.append("%s：「%s」被底板切掉 %.1f 像素（墨迹 %.1f..%.1f）" % [
					v["zh"], row[2], covered, ink_top, ink_bottom])
	return {
		"fitted_bad": fitted_bad,
		"shrunk": shrunk,
		"stack": stack,
		"cut": cut,
		"line": "%d 辆车（其中 %d 辆有数字）最宽的是 %s = %.0f / 可用 %.0f" % [
			Vehicles.IDS.size(), measured, what, worst, room],
	}


# ---------------------------------------------------------------- 预览

## 卡片上那辆车必须是**场景里那辆车**。
##
## 预览是照 [method Vehicles.silhouette] 画的多边形现画的，所以「卡片画得对不对」
## 就等于「读出来的东西对不对」。这里量三件事：
##
## 1. 读得出来，而且车架多边形就是本车 `.tscn` 里 `Chassis/Body` 那个形状；
## 2. 包围盒真的把车架和两个轮子都圈住了 —— 卡片按包围盒缩放，漏一个顶点就会有
##    一部分画到框外，而这种越界在截图上很不起眼；
## 3. **缩放之后放得进预览框**，用的是 `_draw_preview()` 里那条同样的 `minf`。
##    这一条是这一节的重点：`minf` 里任何一项写反（比如用 `maxf`、或者把 room 的
##    宽高对调）都会让车冲出卡片，而 `_draw` 里的越界不会报错，只会画出去。
##
## 预览框按**四辆车**的卡宽算，不按当前张数：卡越少越宽、越好放，所以四张卡的
## 276.5 才是这页真正会遇到的窄case，而且车一辆辆做出来之后它不会变。
func _test_preview() -> void:
	print("=== 预览 ===")
	var s := _new_screen()
	var ids := s._ids
	var missing := PackedStringArray()
	var not_contained := PackedStringArray()
	var overflow := PackedStringArray()
	var head := ""

	var real := s._ids
	s._ids = Vehicles.IDS.duplicate()
	var room := Vector2(s._card_rect(0).size.x - HillVehicleSelect.PREVIEW_PAD * 2.0,
			HillVehicleSelect.PREVIEW_H - HillVehicleSelect.PREVIEW_PAD * 2.0)
	s._ids = real

	for id: String in ids:
		var sil: Dictionary = Vehicles.silhouette(id)
		if sil.is_empty():
			missing.append(id)
			continue
		var box: Rect2 = sil["box"]
		var points: PackedVector2Array = sil["body"]

		# 1. 多边形就是场景里那个。直接开一次场景对一遍，不走缓存。
		var car := Vehicles.instantiate(id)
		var live_body := car.get_node("Chassis/Body") as CollisionShape2D
		var live: PackedVector2Array = (live_body.shape as ConvexPolygonShape2D).points
		var same := live.size() == points.size()
		if same:
			for i in range(live.size()):
				if not live[i].is_equal_approx(points[i]):
					same = false
					break
		if not same:
			missing.append("%s 的车架多边形对不上" % id)
		var expect_layers := 0
		for child in car.get_node("Chassis").get_children():
			if child is Polygon2D:
				expect_layers += 1
		car.free()
		if (sil["layers"] as Array).size() != expect_layers:
			missing.append("%s 的车壳图层数对不上" % id)

		# 2. 包围盒圈住了车架和两个轮子。
		# 放宽 0.01 是必须的：车架最边上那几个顶点**正好落在包围盒的边上**，而
		# `Rect2.has_point()` 是半开的（右/下边算在外面），不放宽就会误报。
		var loose := box.grow(0.01)
		for p in points:
			if not loose.has_point(p):
				not_contained.append("%s 车架顶点 %s" % [id, str(p)])
		for w in sil["wheels"]:
			var c: Vector2 = w["pos"]
			var rr: float = w["radius"]
			if not loose.encloses(Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0)):
				not_contained.append("%s 轮子 @%s r%.0f" % [id, str(c), rr])
		# 车壳上的每一层（车架、驾驶室、车窗、尾翼…）也都要在盒子里。装饰件最容易
		# 越界 —— 比如给赛车加个伸出车尾的尾翼，物理上什么都没变，卡片上却画到了框外。
		for layer in sil["layers"]:
			for p in (layer["polygon"] as PackedVector2Array):
				if not loose.has_point(p):
					not_contained.append("%s 车壳装饰顶点 %s" % [id, str(p)])

		# 3. 缩放之后放得进预览框 —— 和 `_draw_preview()` 里一模一样的算法
		var scale := minf(room.x / maxf(box.size.x, 1.0), room.y / maxf(box.size.y, 1.0))
		var drawn := box.size * scale
		if drawn.x > room.x + 0.001 or drawn.y > room.y + 0.001:
			overflow.append("%s 缩放后 %.0f×%.0f > 可用 %.0f×%.0f" % [
				id, drawn.x, drawn.y, room.x, room.y])
		if head.is_empty():
			head = "%s：车盒 %.0f×%.0f，缩放 %.3f → 画出来 %.0f×%.0f，可用 %.0f×%.0f" % [
				id, box.size.x, box.size.y, scale, drawn.x, drawn.y, room.x, room.y]

	_check("每辆能选的车都读得出来，且就是场景里那辆车", missing.is_empty(),
			head if missing.is_empty() else "，".join(missing))
	_check("包围盒圈住了车架和两个轮子", not_contained.is_empty(),
			"无" if not_contained.is_empty() else "，".join(not_contained))
	_check("缩放之后放得进卡片预览框", overflow.is_empty(),
			head if overflow.is_empty() else "，".join(overflow))
	s.free()


# ---------------------------------------------------------------- 锁

## 前 [constant Vehicles.FREE_COUNT] 辆白送、其余每辆 [constant Vehicles.UNLOCK_PRICE]，
## 以及**点两下才买**这条手感。
##
## 和选图那一页是同一条规矩（那边的用例长得多，价钱表和落盘往返在 `tests/unlock`）：
## 第一下只把光标挪过来，第二下才真扣钱 —— 合成一下的话，翻页时手指擦过一辆 100000
## 的车就直接买下来了。这一节只钉「选车这一页确实照这条规矩接上了」，因为两页的
## `_on_click` / `_activate` 是各写一份的。
##
## **只点锁着的卡**：通了的卡点第二下会 `change_scene_to_file()`（见文件头）。
func _test_lock() -> void:
	print("=== 锁 ===")
	SaveData.reset_progress()
	var s := _new_screen()
	var lid: String = Vehicles.IDS[Vehicles.FREE_COUNT]
	var li := s._ids.find(lid)
	SaveData.total_coins = 0

	var price_bad := PackedStringArray()
	for i in range(Vehicles.IDS.size()):
		var id: String = Vehicles.IDS[i]
		if i < Vehicles.FREE_COUNT:
			if Vehicles.price_of(id) != 0 or not SaveData.vehicle_unlocked(id):
				price_bad.append("%s 应当白送" % id)
		elif Vehicles.price_of(id) != Vehicles.UNLOCK_PRICE or SaveData.vehicle_unlocked(id):
			price_bad.append("%s 应当标 %d" % [id, Vehicles.UNLOCK_PRICE])
	_check("前 %d 辆白送、其余每辆 %d" % [Vehicles.FREE_COUNT, Vehicles.UNLOCK_PRICE],
			price_bad.is_empty(),
			"%s .. %s 白送，%s 起要钱" % [Vehicles.IDS[0], Vehicles.IDS[Vehicles.FREE_COUNT - 1],
				lid] if price_bad.is_empty() else "，".join(price_bad))

	# 光标得停在一张**和收费那张同时在窗口里**的卡上：不然 `_card_rect(li)` 是空的，
	# 点在 (0,0) 上什么都不会发生 —— 那样这条用例就变成「点空白处没反应」，看着过了，
	# 其实什么都没验（选图那边的测试踩过这个坑）。
	s._sel = 0
	s._follow()
	if li < 0 or not s._card_rect(li).has_area() or not s._card_rect(0).has_area():
		_check("收费的车和它前一辆同时在窗口里", false,
				"%s 在第 %d 张，窗口从第 %d 张起" % [lid, li, s._first])
		s.free()
		SaveData.reset_progress()
		return

	SaveData.total_coins = Vehicles.UNLOCK_PRICE * 2
	var purse := SaveData.total_coins
	s._on_click(s._card_rect(li).get_center())
	_check("点一辆没选中的车：只挪光标，不花钱",
			s._sel == li and SaveData.total_coins == purse
			and not SaveData.vehicle_unlocked(lid),
			"光标第 %d 张，金币 %d（原样 %d），还没解锁" % [s._sel, SaveData.total_coins, purse])

	SaveData.total_coins = Vehicles.UNLOCK_PRICE - 1
	s._on_click(s._card_rect(li).get_center())
	_check("钱不够时再点也不会解锁、不扣钱",
			not SaveData.vehicle_unlocked(lid)
			and SaveData.total_coins == Vehicles.UNLOCK_PRICE - 1,
			"金币 %d / 要 %d，仍然锁着" % [SaveData.total_coins, Vehicles.UNLOCK_PRICE])

	SaveData.total_coins = Vehicles.UNLOCK_PRICE + 7
	s._on_click(s._card_rect(li).get_center())
	_check("钱够时再点一下就买下了", SaveData.vehicle_unlocked(lid), "「%s」已解锁" % lid)
	_check("买下只扣标价，零头留着", SaveData.total_coins == 7,
			"金币 %d（期望 7）" % SaveData.total_coins)
	_check("买完停在原地，不自动进车库", s._sel == li and SaveData.vehicle_price(lid) == 0,
			"光标还在第 %d 张，这辆的价钱归 0" % s._sel)

	# 锁卡上那两行字和底板的位置：画法和选图共用一份（[HillLockBadge]），但**两页的卡
	# 上文字位置不一样**，所以这里也要量一遍（底板会不会切开某行字由上一节量）。
	_check("锁卡底板在卡片里", PLATE_BOTTOM < HillVehicleSelect.CARD_H,
			"底板 %d..%d，卡片高 %.0f" % [
				PLATE_TOP, PLATE_BOTTOM, HillVehicleSelect.CARD_H])
	var lock_top := HillLockBadge.LOCK_CY - HillLockBadge.SHACKLE_R - HillLockBadge.SHACKLE_W * 0.5
	var lock_bottom := HillLockBadge.LOCK_CY + HillLockBadge.LOCK_H
	_check("挂锁整个在预览图那一条里（不压卡上的字）",
			lock_top >= 0.0 and lock_bottom <= HillVehicleSelect.PREVIEW_H,
			"锁 %.1f..%.1f，预览高 %.0f，卡上第一行字在基线 %.0f" % [
				lock_top, lock_bottom, HillVehicleSelect.PREVIEW_H,
				HillVehicleSelect.PREVIEW_H + HillVehicleSelect.LINE_NAME])

	# 页脚那行「怎么买」只在还有锁着的车时可画。全新档有 %d 辆锁着。
	_check("还有锁着的车时页脚会多一行提示", s._locked_count() > 0,
			"锁着 %d 辆 / 共 %d 辆" % [s._locked_count(), s._ids.size()])
	var all: Array[String] = []
	for id: String in s._ids:
		if not SaveData.vehicle_unlocked(id):
			SaveData.total_coins += Vehicles.UNLOCK_PRICE
			SaveData.unlock_vehicle(id)
		all.append(id)
	_check("全买下来之后页脚那行就没了", s._locked_count() == 0,
			"锁着 0 辆，金币花掉 %d" % (Vehicles.UNLOCK_PRICE * (all.size() - Vehicles.FREE_COUNT)))

	s.free()
	SaveData.reset_progress()


# ---------------------------------------------------------------- 车表

## 卡片上直接下标读的那几个键，`Vehicles.VEHICLES` 里必须都有。
##
## `_draw_card()` 里是 `v["zh_role"]` 这样的直接下标，没有兜底。哪天加了第五辆车、
## 或者给某辆车换了个写法，忘了补一个键，这里不会画出空白，而是**整帧绘制直接报错**。
## 另外 `DEFAULT` 必须是 `IDS` 的第一个：存档里没有 `[vehicle]` 段的老玩家靠它回落，
## 排到后面就等于「一更新发现自己的车换了」。
func _test_table() -> void:
	print("=== 车表 ===")
	var keys: Array[String] = ["zh", "en", "zh_role", "en_role", "zh_note", "en_note", "scene"]
	var missing := PackedStringArray()
	for id: String in Vehicles.IDS:
		if not Vehicles.VEHICLES.has(id):
			missing.append("%s 不在 VEHICLES 里" % id)
			continue
		var v: Dictionary = Vehicles.VEHICLES[id]
		for k in keys:
			if not v.has(k) or str(v[k]).is_empty():
				missing.append("%s 缺 %s" % [id, k])
	_check("每辆车都有卡片要用的那几个键", missing.is_empty(),
			"%d 辆都在" % Vehicles.IDS.size() if missing.is_empty()
			else "缺：%s" % "，".join(missing))
	_check("DEFAULT 是 IDS 的第一个", Vehicles.IDS[0] == Vehicles.DEFAULT,
			"IDS[0] = %s，DEFAULT = %s" % [Vehicles.IDS[0], Vehicles.DEFAULT])

	# 场景路径唯一：两辆车指向同一个 `.tscn` 时，选车界面会摆出两张一模一样的卡，
	# 而玩家以为自己换了一辆车。测试期最容易犯 —— 复制一辆车的场景忘了改路径。
	var seen := {}
	var dup := PackedStringArray()
	for id: String in Vehicles.IDS:
		var path := Vehicles.scene_path(id)
		if seen.has(path):
			dup.append("%s 和 %s 都指向 %s" % [seen[path], id, path])
		else:
			seen[path] = id
	_check("每辆车有自己的场景文件", dup.is_empty(),
			"%d 条路径都不同" % Vehicles.IDS.size() if dup.is_empty() else "，".join(dup))

	# 还没做出来的车也报一下：`available()` 只给做出来的，界面上就只摆这些。
	var pending := PackedStringArray()
	for id: String in Vehicles.IDS:
		if not Vehicles.available().has(id):
			pending.append("%s（%s）" % [id, Vehicles.scene_path(id)])
	print("  能选的 %d 辆：%s" % [Vehicles.available().size(), str(Vehicles.available())])
	print("  还没做的 %d 辆：%s" % [pending.size(),
			"无" if pending.is_empty() else "，".join(pending)])
