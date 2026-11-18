extends Node
## 选图界面（单行轮播 + 付费解锁）的无头测试。
##
## 六节：
##   1. 光标   —— 开局停在哪、左右怎么绕、存档里是坏值时会不会崩
##   2. 命中   —— 哪个坐标算点中哪张卡（用 `_card_at` 判断，不真的点）
##   3. 版面   —— 一屏四张卡：张数/卡宽/不重叠/居中/在视口内，五种尺寸各量一遍
##   4. 轮播   —— 窗口怎么跟着光标滚、窗口外的卡点不到
##   5. 文案   —— 卡上每行字中英两份都放得下，而且**不上下叠在一起**
##   6. 锁     —— 前四张白送、其余要钱，以及「点两下才买」这条手感
##
## **不点通了的卡。** 通了的卡被点第二下会走 `_pick()` →
## `change_scene_to_file()`，把测试场景本身换掉，测试当场就没了。
## 所以这一节能放心点的是**锁着的卡**：买不起就什么也不发生，买下了也只是在原地
## 解锁。换图和存档那一步交给 `tests/unlock` 和 `tests/save`。
##
## 版面那一节和车库一样**不挂进树**：无头视口是 1280×1280（README 坑 #7），挂进去
## 量出来的尺寸是假的。`_card_rect()` 只依赖 `size`，手工设定反而是真实窗口下的
## 答案。反过来第 1 节要跑 `_ready()`（它从存档里读光标），必须挂进树。
##
## 尺寸这一节能写成硬断言，是因为 `stretch/mode = canvas_items` + `aspect = expand`
## + 基准 1280×720 意味着**虚拟尺寸两个方向都不会小于 1280×720**（窗口更宽时宽
## 变大，更高时高变大）。所以卡宽恒为 (1160 − 18×3) / 4 = 276.5，不是碰运气 ——
## **哪怕一共十二张图**，因为轮播一次也只摆四张（[constant HillMapSelect.VISIBLE]）。

const SELECT := preload("res://scenes/mapselect.tscn")
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
## 量「两行字叠没叠上」时，一行字的墨迹（真的被涂上颜色的那部分）离基线有多远。
##
## **不能用 [method Font.get_ascent] / [method Font.get_descent]** —— 那两个数是
## 字体的**行盒**（排版时留给这一行的整块高度，含行间空隙），比字真正占的地方大得多：
## 中文字体在 17 号下 ascent 就有 20 像素，于是「17 号字行距 21」这种完全正常的排版
## 也会被判成重叠，任何一段两行文字都过不了。实测过：用行盒量，卡上 12 张图 ×
## 每一种情况全线报重叠。
##
## 这两个比例是**字的实际墨迹范围**：中文方块字上沿约在基线往上 0.86 个字高、下沿
## 略过基线一点点；西文的大写和上伸部（b d f h k l）约 0.75、下伸部（g p q y）
## 约 0.21。取 0.88 / 0.22 把两种都盖住，于是这一条量的是「中英两份都真的没叠上」。
const INK_UP := 0.88
const INK_DOWN := 0.22
## 「被底板切了一刀」的判据里，两头各留的余量（像素）。见 [method _measure]。
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
	_test_text()
	print("")
	_test_lock()
	print("")
	# **必须 await**：这一节里要用 `get_tree().process_frame` 等引擎把 `_draw()` 调完，
	# 不 await 的话协程挂在那儿，`_ready()` 直接往下跑完就 `quit()` 了 —— 那一条断言
	# 一次都不会执行，而输出里只看得出「=== 绘制 ===」下面少了一行。
	await _test_draw()
	print("")
	_feature_copy()
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


## 一张脱离场景树、尺寸按真实窗口设好的选图界面。
func _new_screen() -> HillMapSelect:
	var s: HillMapSelect = SELECT.instantiate()
	# 场景里锚点是「铺满父节点」，不挂进树时直接改 size 会被锚点盖回去。
	# 先把锚点拉平，警告也就没了（和车库那份一个道理）。
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = DESIGN
	# **要手动叫一次 `_ready()`。** 不挂进树它永远不会跑，于是 `_cjk` 还是 false
	# —— `_t()` 会一路返回英文，而 `_stats_line()` 内部也走 `_t()`，量出来的宽度
	# 全是英文的。这台机器上真跑起来用的是中文，量英文等于没量。
	s._ready()
	return s


## 同上，但**强制按「没有中文字体」那一份量**（Linux 发行版、以及这次修好之前的
## 安卓都是这个支）。返回的界面里 `_cjk` 为假、字体是主题默认字体。
func _new_english_screen() -> HillMapSelect:
	var s := _new_screen()
	s._cjk = false
	s._font = s.get_theme_default_font()
	return s


# ---------------------------------------------------------------- 光标

func _test_cursor() -> void:
	print("=== 光标 ===")
	SaveData.select_map(Maps.VOLCANO)
	var s: HillMapSelect = SELECT.instantiate()
	add_child(s)
	await get_tree().process_frame
	var want := Maps.IDS.find(Maps.VOLCANO)
	_check("开局光标停在存档里那张图上", s._sel == want,
			"光标在第 %d 张，火山是第 %d 张" % [s._sel, want])

	# 左右首尾环绕，撞到头不会卡住
	s._sel = 0
	s._move(-1)
	_check("从第 0 张往左绕到最后一张", s._sel == Maps.IDS.size() - 1, "→ 第 %d 张" % s._sel)
	s._move(1)
	_check("再往右回到第 0 张", s._sel == 0, "→ 第 %d 张" % s._sel)
	s._sel = Maps.IDS.size() - 1
	s._move(1)
	_check("从最后一张往右绕回第 0 张", s._sel == 0, "→ 第 %d 张" % s._sel)

	# 手改过的配置里可能是个不认识的字符串。`Maps.IDS.find()` 那时返回 -1，
	# 光标不能跟着变成 -1 —— 那样按回车就是 `Maps.IDS[-1]`，GDScript 的负数索引
	# 会取到最后一张火山，看着「能用」，其实是巧合，换张图就穿帮。
	SaveData.selected_map = "atlantis"
	var s2: HillMapSelect = SELECT.instantiate()
	add_child(s2)
	await get_tree().process_frame
	_check("存档里是不认识的图时光标落在第 0 张", s2._sel == 0, "→ 第 %d 张" % s2._sel)

	s.queue_free()
	s2.queue_free()
	SaveData.reset_progress()


# ---------------------------------------------------------------- 命中

func _test_hit() -> void:
	print("=== 命中 ===")
	var s := _new_screen()
	var vis := HillMapSelect.VISIBLE

	# 只对**窗口里那四张**要求「中心命中自己」。窗口外的（第 4 张起）命中不了，
	# 那是第 4 节的事。
	var centers := PackedStringArray()
	var all_hit := true
	for i in range(vis):
		var r := s._card_rect(i)
		var hit := s._card_at(r.get_center())
		if hit != i:
			all_hit = false
		centers.append("卡%d→%d" % [i + 1, hit + 1])
	_check("每张摆出来的卡中心都命中自己", all_hit, "，".join(centers))

	# 卡外的地方一个都不该命中。**按节点坐标点，不是按画面坐标** —— 卡是
	# 从 CARD_TOP 往下的竖条，标题区和页脚都在它的上下，缝隙在它左右。
	var gap_x := s._card_rect(0).end.x + HillMapSelect.GAP * 0.5
	var mid_y := s._card_rect(0).get_center().y
	var probes := {
		"卡间缝隙": Vector2(gap_x, mid_y),
		"标题区": Vector2(DESIGN.x * 0.5, 100.0),
		"卡片上方": Vector2(DESIGN.x * 0.5, HillMapSelect.CARD_TOP - 10.0),
		"卡片下方": Vector2(DESIGN.x * 0.5, HillMapSelect.CARD_TOP + HillMapSelect.CARD_H + 10.0),
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

	# 箭头那两块热区**不算卡片**（它在面板外侧的留白里）。两个函数分开写就是为了
	# 这条：合起来的话「点左边缘」会变成「点到了上一张卡」。
	var y := HillMapSelect.CARD_TOP + HillMapSelect.CARD_H * 0.5
	var arrow_hits := PackedStringArray()
	for dir in [-1, 1]:
		var p := Vector2(s._arrow_pos(dir).x, y)
		if s._card_at(p) != -1:
			arrow_hits.append("%s 箭头落到了卡上" % ("左" if dir < 0 else "右"))
	_check("箭头热区不压在卡片上", arrow_hits.is_empty(),
			"左右箭头都在面板外侧" if arrow_hits.is_empty() else "，".join(arrow_hits))
	s.free()


# ---------------------------------------------------------------- 版面

func _test_layout() -> void:
	print("=== 版面 ===")
	var s := _new_screen()
	var n := Maps.IDS.size()
	var vis := HillMapSelect.VISIBLE
	print("  一共 %d 张图，一屏 %d 张，卡宽 %.1f，文字可用 %.1f，中文字体：%s" % [
		n, vis, s._card_rect(0).size.x, s._card_rect(0).size.x - CARD_PAD * 2.0,
		"有" if s._cjk else "没有，按英文量"])

	var wrong_count := PackedStringArray()
	var wrong_order := PackedStringArray()
	var wrong_w := PackedStringArray()
	var overlap := PackedStringArray()
	var outside := PackedStringArray()
	var off_center := PackedStringArray()
	var tight := PackedStringArray()
	var head := ""
	for sz: Vector2 in SIZES:
		s.size = sz
		var tag := "%.0f×%.0f" % [sz.x, sz.y]
		# 窗口停在最左边：这时看得见的应该是第 0..vis−1 张，从左到右就是表里的顺序。
		s._sel = 0
		s._first = 0
		s._follow()
		var shown: Array[Rect2] = []
		var seen := PackedStringArray()
		for i in range(n):
			var r := s._card_rect(i)
			var slot := s._slot_of(i)
			if r.has_area() and slot >= 0 and slot < vis:
				shown.append(r)
				seen.append("%d" % i)
		if shown.size() != vis:
			wrong_count.append("%s 摆了 %d 张" % [tag, shown.size()])
		for k in range(shown.size()):
			if seen[k] != "%d" % k:
				wrong_order.append("%s 第%d格是第%s张" % [tag, k, seen[k]])
		if not shown.is_empty():
			var w := (shown[0] as Rect2).size.x
			if not is_equal_approx(w, 276.5):
				wrong_w.append("%s 卡宽 %.1f" % [tag, w])
		for i in range(shown.size()):
			var r: Rect2 = shown[i]
			if r.position.x < 0.0 or r.end.x > sz.x + 0.001 \
					or r.position.y < 0.0 or r.end.y > sz.y + 0.001:
				outside.append(tag)
				break
		for i in range(shown.size()):
			for j in range(i + 1, shown.size()):
				if (shown[i] as Rect2).intersects(shown[j]):
					overlap.append("%s 卡%d∩卡%d" % [tag, i + 1, j + 1])
		if shown.size() >= 2:
			var first: Rect2 = shown[0]
			var last: Rect2 = shown[shown.size() - 1]
			# 居中：左边距 = 右边距
			if not is_equal_approx(first.position.x, sz.x - last.end.x):
				off_center.append("%s 左%.0f/右%.0f" % [tag, first.position.x, sz.x - last.end.x])
			# 上下留白：卡顶要躲开副标题（基线 114）和页脚那两行（基线 size.y − 26）
			if first.position.y < 130.0 or last.end.y > sz.y - 70.0:
				tight.append(tag)
			if head.is_empty():
				head = "卡 1 %.0f..%.0f 宽 %.1f，卡底 %.0f" % [
					first.position.x, last.end.x, first.size.x, first.end.y]

	_check("一屏正好摆 %d 张" % vis, wrong_count.is_empty(),
			"%d 种尺寸都是 %d 张" % [SIZES.size(), vis] if wrong_count.is_empty()
			else "，".join(wrong_count))
	_check("卡片从左到右就是图鉴顺序", wrong_order.is_empty(),
			"第 0..%d 格依次是第 0..%d 张" % [vis - 1, vis - 1] if wrong_order.is_empty()
			else "，".join(wrong_order))
	# 这一条是整节的重点：卡宽**只由 VISIBLE 决定**，和一共几张图无关。
	_check("卡宽恒为 276.5（和总张数无关）", wrong_w.is_empty(),
			"一屏 %d 张 → (1160 − 18×%d) / %d = 276.5" % [
				vis, vis - 1, vis] if wrong_w.is_empty() else "，".join(wrong_w))
	_check("摆出来的卡两两不重叠", overlap.is_empty(),
			head if overlap.is_empty() else "，".join(overlap))
	_check("卡片都在视口内", outside.is_empty(),
			"%s（%d 种尺寸）" % [head, SIZES.size()] if outside.is_empty()
			else "越界：%s" % "，".join(outside))
	_check("卡片整体水平居中", off_center.is_empty(),
			"%s（%d 种尺寸都居中）" % [head, SIZES.size()] if off_center.is_empty()
			else "，".join(off_center))
	_check("卡顶躲开标题、卡底躲开页脚", tight.is_empty(),
			"%s（%d 种尺寸）" % [head, SIZES.size()] if tight.is_empty()
			else "，".join(tight))

	s.free()


# ---------------------------------------------------------------- 轮播

## 窗口怎么跟着光标滚。
##
## 四条性质，都是「卡一多就看不出来、但它错了会很难受」的：
##
## 1. **光标永远看得见**。滚窗口的所有逻辑都是为了这一条，它一旦不成立，玩家按方向
##    键会走到一张屏幕上没有的卡上 —— 回车进的是另一张图，看着像存档坏了。
## 2. **一次只滚一格**。要么不做要么跳一整屏的话，从第 3 张按右键跳到第 7 张，
##    中间几张玩家根本没看见，等于白做。
## 3. **走到窗口尽头才滚**。光标在窗口中间时窗口不动 —— 每按一次方向键整行都滑一下
##    会晕，而且卡上的字每帧都在重画。
## 4. **窗口外的卡点不到**。这是 `_card_rect()` 返回空矩形换来的，看着像白送，
##    但「空矩形的 `has_point()` 恒为假」是个容易被后来人「顺手改成
##    `Rect2(0,0,w,h)` 把下标的坐标固定下来」的前提，所以钉一条用例。
func _test_carousel() -> void:
	print("=== 轮播 ===")
	var s := _new_screen()
	var n := Maps.IDS.size()
	var vis := HillMapSelect.VISIBLE
	var slots := ""

	# 开局窗口停在最左边（存档里是平原 = 第 0 张）。
	s._sel = 0
	s._first = 0
	s._follow()
	_check("开局窗口不绕到后面去", s._first == 0, "窗口从第 %d 张起" % s._first)

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
			"第 %d..%d 张都看得见" % [n - vis + 1, n] if blind.is_empty() else "，".join(blind))
	_check("每次滚窗口都只滚一格", jumped.is_empty(),
			"滚了 %d 次：%s" % [moved_at.size(), "，".join(moved_at)] if jumped.is_empty()
			else "，".join(jumped))
	# 走完一整圈光标回到第 0 张，窗口**不会**跟着回到 0 —— 它是个滑动的窗口，不是
	# 「光标在第几张就把窗口摆到第几张开始」。一整圈前进 `n − VISIBLE + 1` 格：
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
				inside_miss.append("第%d张" % i)
			continue
		if r.has_area():
			outside_hit.append("第%d张还有矩形 %s" % [i, str(r)])
		# 第 slot 格（slot ≥ VISIBLE，在面板右边外面）
		for probe_slot in range(vis, vis + 2):
			var p := Vector2(left + float(probe_slot) * (w + HillMapSelect.GAP) + w * 0.5,
					HillMapSelect.CARD_TOP + HillMapSelect.CARD_H * 0.5)
			if s._card_at(p) != -1:
				outside_hit.append("第%d张在第%d格被点到" % [i, probe_slot])
	_check("窗口里的卡点得到", inside_miss.is_empty(),
			"窗口盖住第 0..%d 张，%d 张都命中自己" % [vis - 1, vis] if inside_miss.is_empty()
			else "，".join(inside_miss))
	_check("窗口外的卡既没矩形也点不到", outside_hit.is_empty(),
			"窗口盖住第 %d..%d 张，其余 %d 张都在外面" % [0, vis - 1, n - vis]
			if outside_hit.is_empty() else "，".join(outside_hit))

	# 2：绕回去那一格也只滚一格（第 0 张往左 → 最后一张）。
	s._sel = 0
	s._first = 0
	s._follow()
	s._move(-1)
	_check("从第 0 张往左绕：光标到最后一张、窗口只退一格",
			s._sel == n - 1 and s._first == n - 1,
			"光标 %d（期望 %d），窗口从第 %d 张起（期望 %d）" % [
				s._sel, n - 1, s._first, n - 1])
	s.free()


# ---------------------------------------------------------------- 文案

## 卡上每一行字，中英两份都量一遍：**放得下**，而且**不上下叠在一起**。
##
## 两种毛病都只有量了才知道：
##
##  · **横向撑出去**。卡宽 276.5，左右各留 20，剩 236.5。而 `draw_string` 的 width
##    传 -1 时**不裁不绕**，撑出去是画到**隔壁卡**上，两张卡的字叠在一起。无头跑图
##    看不出来，只有这一节量得出来。散文那两处现在会**折行**（[method
##    HillMapSelect.fit_lines]），单行那几处还是缩号（[method …fit_size]）。
##  · **上下叠在一起**。折行是新加的：说明折成两行之后，第二行落在哪儿是算出来的
##    （[constant …] 那两处 step），离下面那行的基线只剩二十来个像素。行数一多、或者
##    谁把某处字号调大了，两行就会糊成一团 —— 竖着的字叠在一起比横着的更难发现。
##
## 竖着那一条用的是 [constant INK_UP] / [constant INK_DOWN] 那套**墨迹**估计，不是
## 字体的行盒 —— 为什么不能直接用 `get_ascent()` 见那两个常量的注释。
func _test_text() -> void:
	print("=== 文案 ===")
	var s := _new_screen()
	var room := s._card_rect(0).size.x - CARD_PAD * 2.0
	var zh := _measure(s, room)
	# 英文那一屏量完就 free：它不挂进树，不管的话跟着它那个 `SystemFont` 一起留在
	# 内存里，退出时会报一串「RID allocations of ShapedTextData were leaked」——
	# 看着像出了事，其实只是没回收。
	var en_screen := _new_english_screen()
	var en := _measure(en_screen, room)
	en_screen.free()

	_check("每行字都放得下（中文）", zh["over"].is_empty(), zh["line"])
	print("  英文版（没有中文字体时用）：%s" % en["line"])
	_check("每行字都放得下（英文）", en["over"].is_empty(),
			en["line"] if en["over"].is_empty() else "，".join(en["over"]))
	# 折行有没有把字缩得读不出来：缩到 `MIN_FONT` 是底线，缩过头说明文案该改了。
	_check("折行之后字号还在可读范围", zh["tiny"].is_empty() and en["tiny"].is_empty(),
			"中英各 %d 处散文，最小的折到 %d / %d 号" % [
				zh["paras"], zh["min"], en["min"]]
			if zh["tiny"].is_empty() and en["tiny"].is_empty()
			else "，".join(zh["tiny"] + en["tiny"]))
	# 竖着不叠：每一张卡内部，相邻两行字的墨迹不许相交。
	_check("卡上相邻两行字不上下重叠（中文）", zh["stack"].is_empty(),
			"每张卡八行字都错开了" if zh["stack"].is_empty() else "，".join(zh["stack"]))
	_check("卡上相邻两行字不上下重叠（英文）", en["stack"].is_empty(),
			"每张卡八行字都错开了" if en["stack"].is_empty() else "，".join(en["stack"]))
	# 锁卡底板盖着卡片中段（价钱那两行字写在它上面）：被它压住的行只能整个进去或
	# 整个出来。底板是照卡片顶算的绝对坐标，卡上的行距一改就会对不上。
	_check("锁卡底板不把任何一行字从当中切开（中文）", zh["cut"].is_empty(),
			"底板 %d..%d，卡上每行都整个在里面或整个在外面" % [PLATE_TOP, PLATE_BOTTOM]
			if zh["cut"].is_empty() else "，".join(zh["cut"]))
	_check("锁卡底板不把任何一行字从当中切开（英文）", en["cut"].is_empty(),
			"底板 %d..%d" % [PLATE_TOP, PLATE_BOTTOM] if en["cut"].is_empty()
			else "，".join(en["cut"]))

	# 参数行是个**反推**出来的串，最多能有四项（起伏/抓地/阻力/油耗）。现存十二张图
	# 每张最多两项，所以上面那轮量不到四项的情形 —— 但哪天加一张「又颠又滑又费油还
	# 顶风」的图，它就会撑出去。这里把最坏情况量出来记在案：缩到 `MIN_FONT` 还放不下，
	# 就是那天的余量，缩号兜不住它（那一行是单行字，不折行）。
	var all_four := {"amp_scale": 1.5, "friction_scale": 0.5, "drag": 2.0, "fuel_scale": 3.0}
	var line: String = s._stats_line(all_four)
	var fit_all := HillMapSelect.fit_size(s._font, line, 16, room)
	var w_fit := s._font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fit_all).x
	print("  四项全非恒等时的参数行：%s（缩到 %d 号 %.0f / 可用 %.0f %s）" % [
		line, fit_all, w_fit, room, "放不下" if w_fit > room else "放得下"])

	# 折行本身：断点要么在空格上（西文按词断），要么在字与字之间（中文），
	# 而且**不许丢字**——丢掉的字玩家永远看不见。
	#
	# 这一句必须在 `s.free()` **之前**：`_wrap_checks` 要拿 `s._font` 和
	# `s._card_rect`。写反了不是报错，是**段错误**（用一个已经 free 掉的节点）。
	_wrap_checks(s)
	s.free()


## 折行的两条硬性质：不丢字、每行都放得下。
##
## 「不丢字」是把折回来的各行拼起来和原文比：空格会被吞掉（断在空格处时那个空格不
## 属于任何一行），所以比对时把两边的空格都去掉再比。
func _wrap_checks(s: HillMapSelect) -> void:
	var room := s._card_rect(0).size.x - CARD_PAD * 2.0
	var lost := PackedStringArray()
	var wide := PackedStringArray()
	for id: String in Maps.IDS:
		var m: Dictionary = Maps.get_map(id)
		var info: Dictionary = Maps.FEATURE_INFO[m["feature"]]
		for row: Array in [[m["zh_note"], 17, "说明"], [m["en_note"], 17, "英文说明"],
				[info["zh_note"], 15, "地形说明"], [info["en_note"], 15, "英文地形说明"]]:
			var text: String = row[0]
			var px: int = row[1]
			var lines := HillMapSelect.wrap_lines(s._font, text, px, room)
			var joined := ""
			for one in lines:
				joined += one
				if s._font.get_string_size(one, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
					wide.append("%s 的%s「%s」" % [m["zh"], row[2], one])
			if joined.replace(" ", "") != text.replace(" ", ""):
				lost.append("%s 的%s" % [m["zh"], row[2]])
	_check("折行不丢字、每行都不超宽", lost.is_empty() and wide.is_empty(),
			"12 张图 × 4 段说明，折了都拼得回原文" if lost.is_empty() and wide.is_empty()
			else "丢字：%s；超宽：%s" % ["、".join(lost), "、".join(wide)])


## 一张卡上每一行的量宽结果。
##
## `over` 是横向撑出去的，`tiny` 是折行之后字号掉到 `MIN_FONT` 的，`stack` 是上下
## 叠在一起的，`cut` 是被锁卡底板从当中切开的（只有它知道卡片真画出来时每行落在
## 哪儿，所以锁那件事也在这里量），`line` 是给打印用的一句话，`paras` 是量到了几处
## 散文、`min` 是它们折完之后最小的字号。
##
## 行序、字号、基线、行距全部**从 [HillMapSelect] 的常量里读**（`LINE_*` 那组），
## 不在这里抄一份数：抄了就一定会漂 —— 布局改了、量还是旧位置，两边都自认为对。
func _measure(s: HillMapSelect, room: float) -> Dictionary:
	var over := PackedStringArray()
	var tiny := PackedStringArray()
	var stack := PackedStringArray()
	var cut := PackedStringArray()
	var worst := 0.0
	var what := ""
	var paras := 0
	var min_size := 999
	var P := HillMapSelect.PREVIEW_H
	for id: String in Maps.IDS:
		var m: Dictionary = Maps.get_map(id)
		var info: Dictionary = Maps.FEATURE_INFO[m["feature"]]
		# 和 `_draw_card` 同序：[文字, 字号, 基线, 最多几行, 行距, 名字]
		var rows: Array = [
			[s._t(m["zh"], m["en"]), 36, P + HillMapSelect.LINE_NAME, 1, 0.0, "图名"],
			[s._stats_line(m), 16, P + HillMapSelect.LINE_STATS, 1, 0.0, "参数行"],
			[s._t(m["zh_note"], m["en_note"]), 17, P + HillMapSelect.LINE_NOTE, 2,
					HillMapSelect.NOTE_STEP, "说明"],
			["◆ " + s._t(info["zh"], info["en"]), 21, P + HillMapSelect.LINE_FEATURE, 1, 0.0,
					"地形名"],
			[s._t(info["zh_note"], info["en_note"]), 15, P + HillMapSelect.LINE_FEATURE_NOTE, 2,
					HillMapSelect.FEATURE_NOTE_STEP, "地形说明"],
			[s._t("本图最远 %d m", "BEST %d m") % SaveData.best_of(id), 18,
					HillMapSelect.CARD_H - HillMapSelect.LINE_RECORD, 1, 0.0, "纪录"],
		]
		# 这一张卡上所有真正会画出来的行：(基线 y, 字号, 文字, 出处)
		var drawn: Array = []
		for row: Array in rows:
			var text: String = row[0]
			var px: int = row[1]
			var base: float = row[2]
			var max_lines: int = row[3]
			var step: float = row[4]
			var where := "%s 的%s" % [m["zh"], row[5]]
			if max_lines > 1:
				paras += 1
				var fit := HillMapSelect.fit_lines(s._font, text, px, room, max_lines)
				var lines: PackedStringArray = fit["lines"]
				min_size = mini(min_size, int(fit["size"]))
				if fit["size"] <= HillMapSelect.MIN_FONT and lines.size() >= max_lines:
					tiny.append("%s 折到 %d 号还有 %d 行" % [where, fit["size"], lines.size()])
				for k in range(lines.size()):
					var w := s._font.get_string_size(lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1,
							fit["size"]).x
					if w > worst:
						worst = w
						what = "%s 第%d行" % [where, k + 1]
					if w > room:
						over.append("%s 第%d行「%s」%.0f>%.0f" % [
							where, k + 1, lines[k], w, room])
					drawn.append([base + float(k) * step, fit["size"], lines[k], where])
				continue
			var size := HillMapSelect.fit_size(s._font, text, px, room)
			var w1 := s._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if w1 > worst:
				worst = w1
				what = where
			if w1 > room:
				over.append("%s「%s」%.0f>%.0f" % [where, text, w1, room])
			drawn.append([base, size, text, where])

		# 竖着：按基线排序，相邻两行的墨迹不许相交（墨迹怎么算见 INK_UP / INK_DOWN）
		drawn.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for k in range(1, drawn.size()):
			var prev: Array = drawn[k - 1]
			var cur: Array = drawn[k]
			var bottom: float = prev[0] + INK_DOWN * float(prev[1])
			var top: float = cur[0] - INK_UP * float(cur[1])
			if bottom > top:
				stack.append("%s：「%s」压住「%s」（%.1f > %.1f，%s）" % [
					m["zh"], prev[2], cur[2], bottom, top, cur[3]])

		# 锁卡那块底板（[constant HillLockBadge.PLATE_TOP]）压着卡片中段。**被压住的
		# 那几行只能整个进去或整个出来**，不许被从当中切开：底板是不透明的，切一半的
		# 字看着不像「被盖住」，像渲染坏了。底板本身的上下沿也是照这个规矩定的。
		#
		# 两头各留 [constant CUT_MIN] 的余量：整个盖住时差一两个像素、或者只露一两个
		# 像素的边角，都算过 —— 为了那点像素把底板挪一挪，另一页就会真的切开一行。
		for row: Array in drawn:
			var ink_h := float(row[1]) * (INK_UP + INK_DOWN)
			var ink_top: float = row[0] - INK_UP * float(row[1])
			var ink_bottom: float = row[0] + INK_DOWN * float(row[1])
			var covered := minf(ink_bottom, PLATE_BOTTOM) - maxf(ink_top, PLATE_TOP)
			if covered > CUT_MIN and covered < ink_h - CUT_MIN:
				cut.append("%s：「%s」被底板切掉 %.1f 像素（墨迹 %.1f..%.1f）" % [
					m["zh"], row[2], covered, ink_top, ink_bottom])
	return {
		"over": over,
		"tiny": tiny,
		"stack": stack,
		"cut": cut,
		"paras": paras,
		"min": min_size,
		"line": "最宽的一行是 %s = %.0f / 可用 %.0f%s" % [what, worst, room,
				"" if over.is_empty() else "，撑出去的有：" + "，".join(over)],
	}


# ---------------------------------------------------------------- 锁

## 前 [constant Maps.FREE_COUNT] 张白送、其余标 [constant Maps.UNLOCK_PRICE]，
## 以及**点两下才买**这条手感。
##
## 两段式是这一节真正要保的东西：`_on_click` 里「点没选中的卡」和「点已经选中的卡」
## 必须是两条路 —— 合成一条的话，翻页时手指擦过一张 50000 的图就直接买下来了。
## 所以这里点两次：第一次只挪光标（钱一分不少），第二次才扣钱。
##
## **只点锁着的卡**：通了的卡点第二下会 `change_scene_to_file()`，测试场景会被换掉
## （见文件头）。
func _test_lock() -> void:
	print("=== 锁 ===")
	SaveData.reset_progress()
	var s := _new_screen()
	var n := Maps.IDS.size()
	SaveData.total_coins = 0

	# 白送的是前几张，收费的是其余，价钱一个数。
	var free_bad := PackedStringArray()
	var price_bad := PackedStringArray()
	for i in range(n):
		var id: String = Maps.IDS[i]
		if i < Maps.FREE_COUNT:
			if Maps.price_of(id) != 0 or not SaveData.map_unlocked(id):
				free_bad.append(id)
		else:
			if Maps.price_of(id) != Maps.UNLOCK_PRICE or SaveData.map_unlocked(id):
				price_bad.append(id)
	_check("前 %d 张白送" % Maps.FREE_COUNT, free_bad.is_empty(),
			"%s .. %s" % [Maps.IDS[0], Maps.IDS[Maps.FREE_COUNT - 1]] if free_bad.is_empty()
			else "，".join(free_bad))
	_check("其余每张 %d 金币" % Maps.UNLOCK_PRICE, price_bad.is_empty(),
			"第 %d..%d 张都要钱" % [Maps.FREE_COUNT, n - 1] if price_bad.is_empty()
			else "，".join(price_bad))

	# 光标停在第一张收费的图上，而且要**看得见**（它排在窗口外，得先滚过去）。
	var li := Maps.FREE_COUNT
	var lid: String = Maps.IDS[li]
	s._sel = li
	s._follow()
	if not s._card_rect(li).has_area():
		_check("第一张收费的图在窗口里", false, "第 %d 张摆在窗口外，点不到" % li)
		s.free()
		return

	# 第一下：点**没选中**的卡 —— 只挪光标，不花钱、不解锁、不换场景。
	#
	# 光标得挑一张**和 li 同时在窗口里**的卡：`_sel = 0` 的话窗口停在最左边，
	# `_card_rect(li)` 是空的，点在 (0,0) 上什么都不会发生 —— 那样这条用例就变成
	# 「点空白处没反应」，看着过了，其实什么都没验。
	s._sel = 1
	s._follow()
	if not s._card_rect(1).has_area():
		_check("第 1 张和第 %d 张同时在窗口里" % li, false, "窗口只盖住了一部分")
		s.free()
		SaveData.reset_progress()
		return
	SaveData.total_coins = Maps.UNLOCK_PRICE * 2
	var purse := SaveData.total_coins
	s._on_click(s._card_rect(li).get_center())
	_check("点一张没选中的卡：只挪光标，不花钱",
			s._sel == li and SaveData.total_coins == purse and not SaveData.map_unlocked(lid),
			"光标第 %d 张，金币 %d（原样 %d），还没解锁" % [s._sel, SaveData.total_coins, purse])

	# 第二下（同一张卡，钱不够）：什么也不发生 —— 钱不够的时候不能扣，也不能解锁。
	SaveData.total_coins = Maps.UNLOCK_PRICE - 1
	s._on_click(s._card_rect(li).get_center())
	_check("钱不够时再点也不会解锁、不扣钱",
			not SaveData.map_unlocked(lid) and SaveData.total_coins == Maps.UNLOCK_PRICE - 1,
			"金币 %d / 要 %d，仍然锁着" % [SaveData.total_coins, Maps.UNLOCK_PRICE])

	# 第二下（钱够）：扣钱 + 解锁，**仍然停在原地**（不顺手进图，玩家得先看见自己
	# 买到了什么，再按一下才出发）。
	SaveData.total_coins = Maps.UNLOCK_PRICE + 7
	s._on_click(s._card_rect(li).get_center())
	_check("钱够时再点一下就买下了", SaveData.map_unlocked(lid), "「%s」已解锁" % lid)
	_check("买下只扣标价，零头留着", SaveData.total_coins == 7,
			"金币 %d（期望 7）" % SaveData.total_coins)
	_check("买完停在原地，不自动进图", s._sel == li and SaveData.map_price(lid) == 0,
			"光标还在第 %d 张，这张的价钱归 0" % s._sel)

	# 锁卡上那两行字：中英各一份，而且**买不起和买得起说的话不一样**。
	var head_zh := HillLockBadge.price_line(Maps.UNLOCK_PRICE, true)
	var head_en := HillLockBadge.price_line(Maps.UNLOCK_PRICE, false)
	_check("锁卡上写着价钱", head_zh.contains("%d" % Maps.UNLOCK_PRICE)
			and head_en.contains("%d" % Maps.UNLOCK_PRICE),
			"「%s」/「%s」" % [head_zh, head_en])
	var hints := [
		HillLockBadge.hint_line(false, true, true), HillLockBadge.hint_line(true, true, true),
		HillLockBadge.hint_line(true, false, true)]
	_check("买不起说的话和「再点一下」不一样", hints[0] != hints[2] and hints[1] != hints[2],
			"未选中「%s」/ 选中「%s」/ 买不起「%s」" % [hints[0], hints[1], hints[2]])
	# 锁卡那块底板得整个待在卡里 —— 它是照卡片顶算的绝对坐标，卡片一矮就会画到
	# 卡片外面去（也就是压到页脚上）。
	_check("锁卡底板在卡片里", PLATE_BOTTOM < HillMapSelect.CARD_H,
			"底板 %d..%d，卡片高 %.0f" % [
				PLATE_TOP, PLATE_BOTTOM, HillMapSelect.CARD_H])
	# 挂锁整个落在顶上那条预览图里 —— 中段全是字，锁挪下去就会盖掉名字或参数行
	# 当中的一个字（见 [constant HillLockBadge.LOCK_CY]）。
	var lock_top := HillLockBadge.LOCK_CY - HillLockBadge.SHACKLE_R - HillLockBadge.SHACKLE_W * 0.5
	var lock_bottom := HillLockBadge.LOCK_CY + HillLockBadge.LOCK_H
	_check("挂锁整个在预览图那一条里（不压卡上的字）",
			lock_top >= 0.0 and lock_bottom <= HillMapSelect.PREVIEW_H,
			"锁 %.1f..%.1f，预览高 %.0f，卡上第一行字在基线 %.0f" % [
				lock_top, lock_bottom, HillMapSelect.PREVIEW_H,
				HillMapSelect.PREVIEW_H + HillMapSelect.LINE_NAME])

	s.free()
	SaveData.reset_progress()


# ---------------------------------------------------------------- 绘制

## 真的把卡画一遍。
##
## **`draw_*` 只能在「这个节点自己」的 `_draw()` 里叫。** 先试过「塞一个 Control 进去
## 当画布、由它转发 `screen._draw_card(i)`」，引擎当场顶回来：
## `Drawing is only allowed inside this node's '_draw()'` —— 判定看的是**被调用的那个
## 节点**，转发不算数。所以这里换成子类，让引擎自己调它的 `_draw()`。
##
## 于是锁卡那条路径（压暗、挂锁图元、底板、两行字）是**真的执行过一遍**的：字体是
## null、矩形算飞了之类的问题引擎会往日志里写 ERROR，而这份测试的输出是被 grep 着的。
## 这一节买的就是「这条路径跑得通」——像素对不对，无头看不出来。
func _test_draw() -> void:
	print("=== 绘制 ===")
	SaveData.reset_progress()
	var s := Watcher.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(s)
	await get_tree().process_frame
	SaveData.total_coins = 0                   # 买不起 → 价钱那行走 DENIED 那一支
	s.queue_redraw()
	await get_tree().process_frame
	var poor := s.frames
	SaveData.total_coins = Maps.UNLOCK_PRICE   # 买得起 → PRICE 那一支
	s.queue_redraw()
	await get_tree().process_frame
	_check("锁卡两种价钱色都画得出来", s.frames > poor and poor > 0,
			"画了 %d 帧（买不起 %d 帧 → 买得起 %d 帧）" % [s.frames, poor, s.frames])
	# `free()` 而不是 `queue_free()`：这一个是**挂进树里**的，还有一帧没画完。
	# 排队等下一帧再删的话，测试在删之前就 `quit()` 了，退出时会报一堆
	# 「N 个 RID 泄漏」—— 看着像出了事，其实只是没来得及回收。
	s.free()
	SaveData.reset_progress()


## 一个会数自己画了几帧的选图界面。**必须是子类**：转发 `draw_*` 会被引擎顶回来，
## 见 [method _test_draw]。
class Watcher extends HillMapSelect:
	var frames := 0

	func _draw() -> void:
		super._draw()
		frames += 1


# ---------------------------------------------------------------- 图鉴

## 每张图的地形都要有展示文案。
##
## `_draw_card()` 里是 `Maps.FEATURE_INFO[m["feature"]]` —— 直接下标，没有兜底。
## 哪天加了第十三张图、或者给某张图换了个新地形种类，忘了往 `FEATURE_INFO` 里
## 补一条，这里不会画出空白，而是**整帧绘制直接报错**。
func _feature_copy() -> void:
	var s := _new_screen()
	var missing := PackedStringArray()
	for id: String in Maps.IDS:
		var kind: String = Maps.get_map(id)["feature"]
		if not Maps.FEATURE_INFO.has(kind):
			missing.append("%s 的地形「%s」" % [id, kind])
	_check("每张图的地形都有展示文案", missing.is_empty(),
			"%d 张图都在" % Maps.IDS.size() if missing.is_empty() else "缺：%s" % "，".join(missing))
	s.free()
