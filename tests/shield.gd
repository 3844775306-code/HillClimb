extends Node
## 防护罩复活的落点：顶掉一次翻车之后，车要出现在**死亡地右边 50 米、并且站在
## 那儿的地面上**。
##
## 验三件事，缺一不可：
##
## 1. **真的往右挪了 50 米。** 这是防护罩现在真正在卖的东西；只断言「车还活着」
##    的话，改回「原地扶正」那一版照样能过。
## 2. **落点的高度是当场重新量的。** 世界搭成一个台阶：死在 y=0 那一段，落点在
##    y=300 那一段。照搬死亡点高度的实现会把车放在台阶上方 300 px 的空中 ——
##    这条断言专门钉死它。
## 3. **一局只有一次。** 同一个 run 里第二次翻车照样得死，否则 500 金币买的是
##    无限复活。
##
## 外加两条兜底：没带罩时照死不误；射线打不到地面时**原地不动**（宁可这次买亏，
## 也不能把车塞进山体里）。
##
## 世界是手搭的，不用 [HillTerrain]：地形是噪声驱动的，落点高低不可控，而这里
## 要的恰恰是「死亡点和落点**高度差得足够大**」这一条。搭好之后射线问的是物理
## 引擎，走的是和实机同一条路。

const CAR := preload("res://scenes/car.tscn")

## 台阶的转折点。左半段顶面 y = LOW_Y，右半段顶面 y = HIGH_Y。
const STEP_X := 600.0
const LOW_Y := 0.0
const HIGH_Y := 300.0
## 车的出生点。轮心在车原点下方 18、轮半径 21，所以这个 y 让轮子**正好贴地**
## （和 tests/air.gd 的 START_X / CAR_Y 同一个来历，那边也是 -39）。
const START_X := 200.0
const CAR_Y := -39.0
## 生成后等车坐稳的物理帧数。
const SETTLE := 12
## 复活落地的等待帧数。落点离地 25 px（SHIELD_LIFT 46 减掉轮半径 21），自由落体
## 大约 14 帧到底，再留一半给落地后的弹跳收敛。
const LAND := 60

var _world: Node2D
var _car: HillCar
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1：它会直接放大物理步长
	# 车库里练满级的车和攒下来的金币会改这次的行为，测试不碰玩家的存档。
	SaveData.persist = false
	SaveData.reset_progress()

	await _case_no_shield()
	print("")
	await _case_respawn()
	print("")
	await _case_once_per_run()
	print("")
	await _case_no_ground()
	print("")
	await _case_real_terrain()

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)

	# 收尾：手搭的世界自己拆掉，否则退出时会刷一堆 RID/ObjectDB 泄漏，
	# 把真正的泄漏淹掉。
	if _world != null:
		_world.queue_free()
		_world = null
		await get_tree().process_frame
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _approx(label: String, got: float, want: float, tol: float) -> void:
	var ok := absf(got - want) <= tol
	if not ok:
		_failures += 1
	print("  %s %s = %.2f（期望 %.2f ±%.2f）" % [
		"OK  " if ok else "FAIL", label, got, want, tol,
	])


# ---------------------------------------------------------------- 场景搭建

func _new_world() -> void:
	if _world != null:
		_world.queue_free()
	_world = Node2D.new()
	add_child(_world)


## 一块实心地面。collision_layer = 2 是「能站人」那一层，组名 "ground" 是车的
## 触地判据 —— 和 [HillTerrain] 建出来的地面同一个规格（隧道、吊桥、树也一样，
## 见 [constant HillCar.GROUND_LAYER]）。
func _solid(pts: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = pts
	body.add_child(shape)
	_world.add_child(body)


## 搭一个左低右高的台阶，在左半段把车放下来。
##
## `with_right` 为假时**右半段是空的** —— 那是「射线打不到地面」那一条用的：
## 50 米外没有地面，车应该原地不动。实机跑不出这个局面（地形在车前方两个区块内
## 都是建好的，而 50 米只有 0.6 个区块），但兜底不能只写在注释里。
func _build_step(with_right: bool) -> void:
	_new_world()
	_solid(PackedVector2Array([
		Vector2(-400.0, LOW_Y), Vector2(STEP_X, LOW_Y),
		Vector2(STEP_X, LOW_Y + 800.0), Vector2(-400.0, LOW_Y + 800.0),
	]))
	if with_right:
		_solid(PackedVector2Array([
			Vector2(STEP_X, HIGH_Y), Vector2(4000.0, HIGH_Y),
			Vector2(4000.0, HIGH_Y + 800.0), Vector2(STEP_X, HIGH_Y + 800.0),
		]))
	_car = CAR.instantiate()
	_car.position = Vector2(START_X, CAR_Y)
	_world.add_child(_car)


func _settle(frames: int = SETTLE) -> void:
	for i in frames:
		await get_tree().physics_frame


## 带上防护罩（`true`）或者空手（`false`），把这一局的道具账目摆好。
func _arm(shield: bool) -> void:
	SaveData.run_items = {Items.SHIELD: true} if shield else {}
	SaveData.used_items.clear()


## 撞一次「车手头着地」。传进去的东西只要在 "ground" 组里就行 ——
## [method HillCar._on_head_body_entered] 判的是组名，不是具体哪个刚体，
## 所以这里**按组去找**，不能图省事拿 `_world.get_child(0)`：真实地形那一节
## 第 0 个孩子是 [HillTerrain] 本身，它不在组里，于是整次翻车被静默忽略，
## 车没死、也没挪窝，测出来是一片「通过」。
func _crash() -> void:
	_car._on_head_body_entered(get_tree().get_first_node_in_group("ground"))


## 车现在在哪儿：车壳中心的 x，和三个刚体里最靠下的那个的 y。
## 扶正并且停稳之后，后者就是轮心的 y。
func _snap() -> Dictionary:
	return {
		"x": _car.chassis.global_position.x,
		"lowest_y": _car._lowest_body_y(),
	}


## 轮子最下面的那个点的 y。**轮半径从场景里读**，不抄一份数字 —— 编辑器里调了
## 轮径的话，抄出来的断言会悄悄用过期值（和 car.gd 读轮子摩擦同一个理由）。
func _wheel_bottom() -> float:
	var lowest := _car._lowest_body_y()
	for child in _car.rear_wheel.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is CircleShape2D:
			return lowest + ((child as CollisionShape2D).shape as CircleShape2D).radius
	return lowest


# ---------------------------------------------------------------- 1. 没带罩

func _case_no_shield() -> void:
	print("=== 1. 没带防护罩：照死不误 ===")
	_build_step(true)
	_arm(false)
	await _settle()

	var before := _snap()
	_crash()
	_check("没带罩，翻车就是死", _car.alive, false)
	_approx("死了就不该挪窝", _snap()["x"], before["x"], 0.01)


# ---------------------------------------------------------------- 2. 复活

func _case_respawn() -> void:
	print("=== 2. 带上防护罩：挪到右边 50 米的台阶上 ===")
	_build_step(true)
	_arm(true)
	await _settle()

	var radius := _wheel_bottom() - _car._lowest_body_y()
	print("  台阶转折在 x=%.0f，地面从 y=%.0f 跳到 y=%.0f" % [STEP_X, LOW_Y, HIGH_Y])

	var before := _snap()
	_crash()

	_check("顶掉了，车还活着", _car.alive, true)
	_check("道具记成用过了", SaveData.used_items.has(Items.SHIELD), true)

	var after := _snap()
	_approx("往右挪了 50 米",
			after["x"] - before["x"],
			Maps.PIXELS_PER_METER * Items.SHIELD_RESPAWN_METERS, 0.01)

	# 落点高度必须是**在那儿重新量的**。照搬死亡点高度（y≈0）的话，这里算出来的
	# 轮底会停在 y≈-46，比台阶顶面高 346 px —— 下面第一条会直接红。
	var dropped := _wheel_bottom()
	_approx("复活瞬间悬在台阶顶面上方",
			dropped, HIGH_Y - (Items.SHIELD_LIFT - radius), 1.0)
	_check("没有塞进台阶里", dropped <= HIGH_Y, true)

	await _settle(LAND)
	_check("落地之后还活着", _car.alive, true)
	_approx("落地之后坐在台阶顶面上", _wheel_bottom(), HIGH_Y, 3.0)


# ---------------------------------------------------------------- 3. 一局一次

func _case_once_per_run() -> void:
	print("=== 3. 同一个 run 里只有一次 ===")
	# 接着第 2 局的世界跑：罩子那一份已经用掉了。免死窗口是给落地用的，这里要测
	# 的是「第二次判死」，所以先把它清掉 —— 否则车会靠窗口躲过这一次，
	# 测出来的是窗口而不是「一局一次」。
	_car.shield_grace = 0.0
	var before := _snap()
	_crash()
	_check("第二次翻车照样死", _car.alive, false)
	_approx("死了就不该挪窝", _snap()["x"], before["x"], 0.01)


# ---------------------------------------------------------------- 4. 没落点

func _case_no_ground() -> void:
	print("=== 4. 50 米外没有地面：原地不动，只抬一下 ===")
	_build_step(false)   # 右半段是空的
	_arm(true)
	await _settle()

	var before := _snap()
	_crash()
	_check("这次翻车照样顶掉", _car.alive, true)
	_approx("没有落点就不挪窝", _snap()["x"], before["x"], 0.01)
	_approx("只往上抬了 SHIELD_LIFT",
			_snap()["lowest_y"] - before["lowest_y"], -Items.SHIELD_LIFT, 0.01)


# ---------------------------------------------------------------- 5. 真实地形

## 前四条用的是手搭的两块矩形地面。那证明的是「重新量高度、再挪过去」串逻辑对，
## 但**没证明射线打得到真实地形** —— 真地面是 [HillTerrain] 每
## [constant HillTerrain.CHUNK_WIDTH] 像素建一块的 [CollisionPolygon2D] 折线，
## 还是跟着镜头现建现拆的。这一条把它补上：在真图上、真起伏里翻一次。
##
## 车直接**摆到远处有起伏的地方**再翻，不是开过去：开 6 秒全油门有相当的概率在
## 石头或陡坡上先翻一次，那测的就不是这里要测的东西了。射线不关心车是动的还是停
## 的，所以停着翻一样能验。
func _case_real_terrain() -> void:
	print("=== 5. 真实地形：射线够得着 [HillTerrain] 建出来的地面 ===")
	_new_world()
	var terrain := HillTerrain.new()
	_world.add_child(terrain)
	terrain.world_seed = 20261001
	terrain.map_id = Maps.MOUNTAIN

	# 4000 px 处起伏已经拉满（[constant HillTerrain.BLEND_LENGTH] 是 800，
	# 出生点平地只有 700），不是出生点那块一马平川。
	const AT_X := 4000.0
	_car = CAR.instantiate()
	_car.position = Vector2(AT_X, terrain.height_at(AT_X) + CAR_Y)
	_world.add_child(_car)
	_car.apply_map(Maps.MOUNTAIN)
	_car.fuel = 1.0e9
	terrain.set_target(_car.chassis)
	_arm(true)
	await _settle()

	var before := _snap()
	_crash()
	_check("在真图上同样顶掉", _car.alive, true)

	var after := _snap()
	_approx("挪了 50 米", after["x"] - before["x"],
			Maps.PIXELS_PER_METER * Items.SHIELD_RESPAWN_METERS, 0.01)

	# **这一节的要害。** 落点高度要是照搬死亡点的，下面第一个 `_check` 会红。
	var here := terrain.height_at(before["x"])
	var there := terrain.height_at(after["x"])
	var bottom := _wheel_bottom()
	print("  死亡点 x=%.0f 地表 y=%.0f → 落点 x=%.0f 地表 y=%.0f，轮底 y=%.0f" % [
		before["x"], here, after["x"], there, bottom])
	_check("两点地表高度确实差得足够远（否则这节测不出东西）",
			absf(there - here) > 5.0, true)
	_check("落在真图的地面上（没塞进坡里）", bottom <= there, true)
	_check("也没悬在半空", bottom >= there - Items.SHIELD_LIFT, true)
