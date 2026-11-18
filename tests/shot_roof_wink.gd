extends Node
## 窗户动画的**画面证据**：同一栋房子、同一个镜头，隔十四拍拍两张，再逐像素比。
##
## 无头跑验不了 `_draw`（不发 `NOTIFICATION_DRAW`，见 tests/shapes.gd 的文件头），
## 所以「窗户到底有没有在屏幕上换脸」只有真渲染能回答。这里数出两个数：
##
##   · **翻面的像素**：两张图之间从亮窗色变成暗窗色（或反过来）的像素个数 —— 要够多，
##     少了就是「算式在动、画面没动」，用户报的正是这一种；
##   · **其它像素**：一个都不许变。这条是**前提**不是结论：场上是空的（不挂
##     main.tscn、不摆车、镜头钉死、区块也等加载完了），所以除了窗户没有东西该动 ——
##     它绿了才说明上面那个数真的是窗户翻面翻出来的。
##
## 数像素不用眼睛看，是因为**两种窗色是写死的两个常量**
## （[constant HillRooftopArt.WIN_LIT] / `WIN_DARK`，8 位里就是 (255,219,122) 和
## (26,28,38)），而这一屏里没有别的东西是这两个颜色 —— 于是「变的是不是窗户」可以判。
##
## 用法（会短暂弹出窗口，约 25 秒）：
##   godot --path . res://tests/shot_roof_wink.tscn
## 两张图留在 `.shots/wink_a.png` / `wink_b.png`，可以自己开来看同一个位置
## 「亮着的窗换了一批」。
##
## 两处踩过的坑：
##
## - **别想着「摁住 `Engine.time_scale = 0` 把车和镜头冻住」**：effects.gd 的尾气多边形
##   在 delta = 0 时会算出非有限的顶点（`Vector2 cannot be normalized`），画出一大片
##   垃圾，两张图的差别里就分不清哪块是窗户。所以现在是**干脆不摆车**。
## - **视口图的字节格式不能想当然**：`get_texture().get_image()` 的格式随渲染后端
##   （HDR 2D 下是半精度浮点），按 4 字节步进读会读串行，把三千多个像素误报成
##   「别处变了」。先显式 `convert(Image.FORMAT_RGBA8)`。

const OUT_DIR := "res://.shots"
## 看哪一栋房子（区块号）。0 号是出生直道那一片平顶，看不出东西，从 1 号
## （[constant Maps.SHAPE_START_CELL]）起才是真房子。
const AT_CHUNK := 3
## 两张之间隔多少秒。窗户最短 12 拍换一次脸（[constant HillRooftopArt.ACT_MIN]），
## 隔 14 拍保证每扇窗都至少掷过一次新脸。
const GAP_SECONDS := 14.0
## 翻面的像素至少要这么多才算「看得出来」。实测 8800 上下（十四拍里约一成窗换脸）。
const MIN_FLIPS := 1000

var _terrain: HillTerrain
var _failures := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveData.persist = false
	SaveData.reset_progress()

	var view_x := float(AT_CHUNK) * HillTerrain.CHUNK_WIDTH + HillTerrain.CHUNK_WIDTH * 0.5
	var world := Node2D.new()
	add_child(world)
	_terrain = HillTerrain.new()
	_terrain.world_seed = 1337
	_terrain.map_id = Maps.ROOFTOP
	world.add_child(_terrain)
	# 区块是围着目标节点 stream 的：不设目标就一块区块都不建，画师自然也没有。
	var probe := Node2D.new()
	probe.position = Vector2(view_x, 0.0)
	world.add_child(probe)
	_terrain.set_target(probe)

	var cam := Camera2D.new()
	cam.position = Vector2(view_x, 300.0)
	world.add_child(cam)
	cam.make_current()

	await _settle()
	var chunk := _terrain.get_node_or_null("Chunk%d" % AT_CHUNK)
	var art: HillRooftopArt = null
	if chunk != null:
		for child in chunk.get_children():
			if child is HillRooftopArt:
				art = child
	_check_true("看的那一栋有画师（不然下面量的是空画面）", art != null,
			"Chunk%d %s" % [AT_CHUNK, "有" if art != null else "没有"])

	var tick_a := HillRooftopArt.window_tick(HillRooftopArt.now())
	var img_a := await _capture("wink_a")
	await _wait_real(GAP_SECONDS)
	var tick_b := HillRooftopArt.window_tick(HillRooftopArt.now())
	var img_b := await _capture("wink_b")
	if img_a == null or img_b == null:
		_check_true("两张图都截到了", false, "有一张是空的")
		_finish()
		return

	img_a.convert(Image.FORMAT_RGBA8)
	img_b.convert(Image.FORMAT_RGBA8)
	var da := img_a.get_data()
	var db := img_b.get_data()
	var flips := 0
	var other := 0
	for i in range(0, mini(da.size(), db.size()), 4):
		if da[i] == db[i] and da[i + 1] == db[i + 1] and da[i + 2] == db[i + 2]:
			continue
		if _window_pair(da, i, db, i) or _window_pair(db, i, da, i):
			flips += 1
		else:
			other += 1
	_check_true("同一栋房子隔 %d 拍再看，窗户真的换了一批脸" % (tick_b - tick_a),
			flips >= MIN_FLIPS, "翻面 %d 个像素 / 下限 %d" % [flips, MIN_FLIPS])
	_check_true("除了窗户，画面上一像素都没动", other == 0, "别处变了 %d 个像素" % other)
	_finish()


## 等区块流式加载停下来。地形是一帧建一块的：早早就拍照的话，旁边那栋房子可能十四拍
## 之后才建出来，那张「新冒出来的立面」会被算进「别处变了」。
func _settle() -> void:
	var last := -1
	var stable := 0
	for i in 240:
		await get_tree().process_frame
		var n := _terrain.get_child_count()
		if n == last:
			stable += 1
			if stable >= 10:
				return
		else:
			stable = 0
			last = n
	push_warning("区块一直没停（%d 块），下面的「别处变了」可能不作数" % last)


## 这一对像素是不是「亮窗 ↔ 暗窗」。
func _window_pair(a: PackedByteArray, i: int, b: PackedByteArray, j: int) -> bool:
	return _near(a, i, 255, 219, 122) and _near(b, j, 26, 28, 38)


## 容差 20：抗锯齿在窗户边上会调出一圈中间色，那不算「别的颜色」。
func _near(d: PackedByteArray, i: int, r: int, g: int, bl: int) -> bool:
	return absi(d[i] - r) <= 20 and absi(d[i + 1] - g) <= 20 and absi(d[i + 2] - bl) <= 20


func _check_true(label: String, cond: bool, detail: String) -> void:
	if not cond:
		_failures += 1
	print("  %s %s（%s）" % ["OK  " if cond else "FAIL", label, detail])


func _finish() -> void:
	print("")
	print("失败 %d 项" % _failures)
	get_tree().quit()


## 真实秒数。拍子和钟都是真实时间，等物理帧没用。
func _wait_real(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await get_tree().process_frame


func _capture(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var err := image.save_png(path)
	print("  %s %s" % ["已保存" if err == OK else "**保存失败**", shot_name])
	return image if err == OK else null
