extends Node
## 地块几何：**地表底下永远有实心土**。
##
## 用户原话：「注意增加地块的厚度避免地面在地块以下使得车子掉下去」。
##
## ## 这是个什么错
##
## 区块的碰撞体是个闭合多边形：沿地表从左到右，再绕到底部闭合。底边早先写的是
## 一个**固定的世界高度** `GROUND_Y + DEPTH`，而地表是**相对**的 —— 起伏随里程
## 往下长（长波层、坑、环形山都是往下挖的）。当地表某处跑到那条固定底边**以下**，
## 收口的那两条边就翻到了地表上方，多边形自己交叠，碰撞体等于没有：
## 车从那儿直接掉出世界，而且**只在很远的里程上才出现**。
##
## 修法不是把 DEPTH 加大（那只是把翻车的里程往后推），而是让底边跟着本区块
## 最深的那一处地表走（见 [method HillTerrain._build_chunk]）：于是「地块比地面厚
## DEPTH」成了每一个区块上都成立的**局部**保证。
##
## ## 这一节量什么
##
## A. 直接量**建出来的碰撞多边形**：本区块每一个地表顶点的下方，到底边还有多少
##    实心土。这是「车会不会掉下去」的直接几何量，不是复述那条公式 ——
##    顶点是从 `CollisionPolygon2D.polygon` 里读回来的。
## B. 走一段真实物理：把车摆在**最深的那类区块**里开一段，看它会不会掉出世界。
##    几何对了物理不一定对（比如区块被回收重建的瞬间），所以这一节留着。
##
## 覆盖的是**最深的那几张图 + 很远的里程**：错只在那儿出，前面的平地永远是对的。

const DT := 1.0 / 60.0
## 每张图扫到多远（像素），用来找**最深的那一块**。起伏随里程长，最深的凹地在
## 十几到三十几公里上（实测：竞技场 14.9 km、平原 16.8 km、火山 34.0 km），
## 所以窗口要开到 40 km。5 像素一步：凹地的底是尖的，步长太粗会跳过去。
const SCAN_TO := 400000.0
const SCAN_STEP := 5.0
## 每张图额外量的几个近处区块（除了最深的那一块之外）。广度用：凹地深处当然要量，
## 但**每一块**都得成立，不能只顾着最深的那一块。
const SPOT_CHUNKS := [3, 7, 19, 41]
## 深度最猛的几张图。竞技场排第一：`amp_scale` 2.2，实测最深的地方就是它
## （y=1302，比老底边低了 282 像素）。形状地图（屋顶/彩虹）也在里面 ——
## 它们的深是**挖出来的缝**（`GROUND_Y + GAP_DEPTH`），和噪声不是一回事。
const MAP_IDS := [Maps.ARENA, Maps.PLAINS, Maps.VOLCANO, Maps.MOUNTAIN,
		Maps.MOON, Maps.TUNNEL, Maps.DESERT, Maps.ROOFTOP]

## 摆车/开车的世界种子。和别处一样钉死，可复现。
const SEED := 1337

var _assertions := 0
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()

	await _section_a()
	print("")
	await _section_b()

	print("")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


# ---------------------------------------------------------------- A. 几何

## 建出真的区块，从碰撞多边形里读回顶点，量每个地表顶点下方的实心厚度。
##
## **每张图都先找出它最深的那一块**（扫一遍 `height_at`），再量那一块 ——
## 错只出在最深的地方，随机挑区块是碰不上的（实测：平原只有 0.16% 的采样点
## 深过老底边，竞技场 1.7%）。
func _section_a() -> void:
	print("=== A. 每个区块的厚度 ≥ %.0f px ===" % HillTerrain.DEPTH)
	# 固定底边那条老公式：`GROUND_Y + DEPTH`。扫到的地形有没有深到**会**翻过去，
	# 决定这一节有没有真的覆盖到那个错。
	var old_bottom := HillTerrain.GROUND_Y + HillTerrain.DEPTH
	var old_worst := -INF
	var worst := INF
	var worst_where := ""

	for map_id in MAP_IDS:
		var terrain := HillTerrain.new()
		terrain.world_seed = SEED
		terrain.map_id = map_id
		add_child(terrain)
		await get_tree().process_frame

		var deep := _deepest(terrain)
		old_worst = maxf(old_worst, float(deep["y"]))
		var indices: Array = SPOT_CHUNKS.duplicate()
		indices.append(int(deep["index"]))
		print("  %s：最深的一块是第 %d 块（x=%.0f，地表 y=%.0f）" % [
			map_id, int(deep["index"]), float(deep["x"]), float(deep["y"])])

		for index in indices:
			var polygon := await _chunk_polygon(terrain, int(index))
			if polygon.is_empty():
				continue
			# 多边形的底边 = 最低的那两个顶点（收口那两个）。
			var bottom := -INF
			for p in polygon:
				bottom = maxf(bottom, p.y)
			# 地表顶点 = 除了收口那两个以外的全部。
			var surface := polygon.slice(0, polygon.size() - 2)
			for p in surface:
				var thickness: float = bottom - p.y
				if thickness < worst:
					worst = thickness
					worst_where = "%s 第 %d 块（x=%.0f）" % [map_id, index, p.x]

		terrain.queue_free()
		await get_tree().process_frame

	_check("处处都够厚", worst >= HillTerrain.DEPTH - 0.001,
			"最薄的一处 %.1f px（%s）" % [worst, worst_where])
	# **覆盖断言**：扫到的地形得真的深过那条老底边，否则这一节等于没测到那个错
	# ——「全绿」和「没测」在输出上是同一个样子，所以这条必须钉住。
	# 它红了不代表代码坏了，代表地形整体变浅了、这个测试该重新瞄准了。
	_check("扫描确实碰到了会让老公式翻车的地形", old_worst > old_bottom,
			"最深的地表 y=%.0f，老底边 y=%.0f（低了 %.0f px）" % [
				old_worst, old_bottom, old_worst - old_bottom])


## 这张图上最深的那一块：返回 `{index, x, y}`。
func _deepest(terrain: HillTerrain) -> Dictionary:
	var best := {"index": 0, "x": 0.0, "y": -INF}
	var x := HillTerrain.CHUNK_WIDTH
	while x < SCAN_TO:
		var y: float = terrain.height_at(x)
		if y > float(best["y"]):
			best = {"index": int(floor(x / HillTerrain.CHUNK_WIDTH)), "x": x, "y": y}
		x += SCAN_STEP
	return best


## 把第 `index` 块的碰撞多边形要出来。区块是**随镜头滚动**建的，所以这里把
## 观察点直接放到那一块上，等它建出来，再从 `Ground` 的 `CollisionPolygon2D` 读。
func _chunk_polygon(terrain: HillTerrain, index: int) -> PackedVector2Array:
	var probe := Node2D.new()
	probe.global_position = Vector2(
			(float(index) + 0.5) * HillTerrain.CHUNK_WIDTH, HillTerrain.GROUND_Y)
	add_child(probe)
	terrain.set_target(probe)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var chunk := terrain.get_node_or_null("Chunk%d" % index)
	if chunk == null:
		probe.queue_free()
		return PackedVector2Array()
	# `find_child` 是递归的，而特殊地形也可能挂着同名的子节点，所以按路径精确取。
	var ground := chunk.get_node_or_null("Ground")
	if ground == null:
		probe.queue_free()
		return PackedVector2Array()
	for child in ground.get_children():
		var collider := child as CollisionPolygon2D
		if collider != null:
			var polygon := collider.polygon
			probe.queue_free()
			return polygon
	probe.queue_free()
	return PackedVector2Array()


# ---------------------------------------------------------------- B. 实机

## 把车摆在最深的那一块里开一段，看它会不会掉出世界。
##
## 判据用的是**车到底边的距离**，不是「车没死」：掉出世界的车不会立刻判死
## （下面是空的，它只是一直往下掉），所以只断言「活着」是抓不住的。
func _section_b() -> void:
	print("=== B. 最深的地形里开一段 ===")
	# 竞技场：实测最深的一张图（y=1302），而且它是一张**正常能玩到的图**，
	# 不是专门造出来压测的。
	var map_id := Maps.ARENA
	var terrain := HillTerrain.new()
	terrain.world_seed = SEED
	terrain.map_id = map_id
	add_child(terrain)
	await get_tree().process_frame

	var deep := _deepest(terrain)
	var target := int(deep["index"])
	var polygon := await _chunk_polygon(terrain, target)
	var bottom := -INF
	for p in polygon:
		bottom = maxf(bottom, p.y)
	var spawn_x := float(deep["x"])

	var car := load("res://scenes/car.tscn").instantiate() as HillCar
	add_child(car)
	car.apply_map(map_id)
	car.global_position = Vector2(spawn_x, terrain.height_at(spawn_x) - 60.0)

	var lowest := -INF
	Input.action_press("drive_forward")
	var t := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		lowest = maxf(lowest, car.chassis.global_position.y)
		t += DT
	Input.action_release("drive_forward")

	_check("车没有掉出地块底边", lowest < bottom,
			"车最深到了 y=%.0f，地块底边 y=%.0f（余 %.0f px）" % [
				lowest, bottom, bottom - lowest])
	# **穿地**的判据：车壳不能跑到地表以下。只断言「没掉出世界」是不够的 ——
	# 多边形交叠之后车是先穿进土里、再穿过底边掉出去的，前半截才是现场。
	# 只卡一侧：飞到天上去不是错（那是被坡抛起来的），沉到地下才是。
	var ground_y: float = terrain.height_at(car.chassis.global_position.x)
	_check("车没有沉到地表以下", car.chassis.global_position.y - ground_y < 60.0,
			"车壳比地表低 %.0f px（x=%.0f）" % [
				car.chassis.global_position.y - ground_y, car.chassis.global_position.x])
	print("  最深的那一块：第 %d 块（x=%.0f），地表 y=%.0f，地块底边 y=%.0f" % [
		target, float(deep["x"]), float(deep["y"]), bottom])
