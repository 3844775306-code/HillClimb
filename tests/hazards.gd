extends Node
## 四种特殊地形的实测。
##
## A. 剖面连续性 —— 纯函数。断崖是这类地形最容易出的错（坑挖好了，但坑沿比
##    旁边的地面高出一截，等于凭空多一堵墙），而且只有火山口的助跑坡会触发，
##    所以单独拉一节用采样把整条剖面扫一遍。
## B. 吊桥         —— 车能压着桥过去，而且桥会下沉（「软」是能量出来的）
## C. 冰湖         —— 冰面把抓地力压下去、踩上 0.5 秒后裂、车掉下去淹死
## D. 火山口       —— 掉进岩浆烧死
## E. 沙尘暴       —— 风确实把车往回推，而且**只推一次**（不是车壳轮子各推一次）
##
## ## 为什么地表要压平
##
## [FlatTerrain] 把地表钉在 [constant HillTerrain.GROUND_Y]。真地形的噪声起伏
## 会让「车到坑沿时还有多少速度」变成随机的：同一个坑，前面赶上上坡就冲不过去，
## 赶上下坡就飞过去了。压平之后测的才是特殊地形本身，而且是可复现的。
##
## ## 哪些是断言、哪些只是打印
##
## 断言只钉**机制**（冰面把抓地力压到几成、0.5 秒后裂、掉下去是什么死因、
## 风把车往回推了多少牛顿对应的加速度）。「全油门能不能跳过火山口」「多少速度
## 能压着冰过去」只打印不断言 —— 那取决于车的马力，而车的参数玩家还在编辑器里
## 调（见 car.gd 顶部），钉死了每次调参都会被打翻。要的门槛会打印出来。

const CAR := preload("res://scenes/car.tscn")
const BRIDGE := preload("res://scenes/rope_bridge.tscn")
const SANDSTORM := preload("res://scenes/sandstorm.tscn")
const LAKE := preload("res://scenes/ice_lake.tscn")
const CRATER := preload("res://scenes/crater.tscn")

const BRIDGE_SCRIPT := preload("res://scripts/rope_bridge.gd")
const SANDSTORM_SCRIPT := preload("res://scripts/sandstorm.gd")
const LAKE_SCRIPT := preload("res://scripts/ice_lake.gd")

const SEED := 1337
## 车出生点比地面高多少（和 scenes/main.tscn 里 Car 的摆位一致）。
const CAR_LIFT := 39.0
## 助跑距离。要够长才冲得起来，又要保证起点落在特殊地形**前一个区块**里 ——
## 起点在区块外的话，区块还没建出来车就已经到了。
const RUN_UP := 700.0
const SETTLE_FRAMES := 12
const DT := 1.0 / 60.0


## 测试专用地形：地表恒定。
class FlatTerrain extends HillTerrain:
	func _base_height(_x: float) -> float:
		return GROUND_Y


var _failures := 0
var _assertions := 0
var _world: Node2D
var _terrain: HillTerrain
var _car: HillCar


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()

	_section_a()
	await _section_f()
	await _section_b()
	await _section_c()
	await _section_d()
	await _section_e()

	print("")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


func _approx(label: String, got: float, want: float, tol: float = 0.001) -> void:
	_check(label, absf(got - want) <= tol, "%.4f（期望 %.4f ±%.4f）" % [got, want, tol])


## 相对误差断言。用在「量出来的东西应该等于某条公式」的地方。
func _within(label: String, got: float, want: float, rel: float) -> void:
	var ok := absf(got - want) <= absf(want) * rel
	_check(label, ok, "%.1f（期望 %.1f ±%.0f%%）" % [got, want, rel * 100.0])


# ---------------------------------------------------------------- A. 剖面

## 剖面是纯函数，所以这一节不需要物理也不需要场景。
func _section_a() -> void:
	print("=== A. 剖面连续性 ===")
	var cw := HillTerrain.CHUNK_WIDTH
	for kind in [Maps.FEATURE_BRIDGE, Maps.FEATURE_SANDSTORM, Maps.FEATURE_LAKE, Maps.FEATURE_CRATER]:
		var lay := Maps.feature_layout(kind)
		var depth := float(lay["depth"])
		var edge := float(lay["edge"])
		var ramp := float(lay["ramp_len"])
		var ramp_h := float(lay["ramp_h"])
		var back := float(lay["back_len"])

		if depth <= 0.0 and ramp_h <= 0.0:
			# 不挖地表的地形（沙尘暴）：整条剖面都得是 0，否则等于在图上乱挖。
			var dirtiest := 0.0
			var x := 0.0
			while x <= cw:
				dirtiest = maxf(dirtiest, absf(HillTerrain._carve_in_chunk(kind, x)))
				x += 5.0
			_approx("%s 一点土都不动" % kind, dirtiest, 0.0, 0.001)
			continue

		# 区块接缝处必须是 0：不为 0 的话，相邻区块的地表在这里对不上，
		# 而相邻区块是按同一张布局表各挖各的，接缝上是两条独立的折线。
		_approx("%s 左接缝贴齐" % kind, HillTerrain._carve_in_chunk(kind, 0.0), 0.0, 0.001)
		_approx("%s 右接缝贴齐" % kind, HillTerrain._carve_in_chunk(kind, cw), 0.0, 0.001)

		# 逐像素扫一遍，找最大单步跳变。断崖会表现为「一步跳几百像素」。
		var step := 0.0
		var lo := HillTerrain._carve_in_chunk(kind, 0.0)
		var hi := lo
		var prev := lo
		var sx := 1.0
		while sx <= cw:
			var v := HillTerrain._carve_in_chunk(kind, sx)
			step = maxf(step, absf(v - prev))
			lo = minf(lo, v)
			hi = maxf(hi, v)
			prev = v
			sx += 1.0

		# 解析上的最大斜率：余弦坑壁 depth·π/(2·edge)，助跑坡 smoothstep
		# 的最大斜率是 ramp_h·1.5/ramp_len。乘 1.6 留采样误差的余量。
		var slope := 0.0
		if depth > 0.0 and edge > 0.0:
			slope = maxf(slope, depth * PI / (2.0 * edge))
		if ramp > 0.0:
			slope = maxf(slope, ramp_h * 1.5 / ramp)
		var bound := slope * 1.6 + 1.0
		_check("%s 没有断崖" % kind, step <= bound,
				"最大单步 %.1f（上限 %.1f，斜率 %.1f/px）" % [step, bound, slope])

		# 挖到设计的深度、抬到设计的高度。火山口两个都要看：它的坑底是
		# 「抬起来 150 之后再挖 420」，所以最深处的绝对深度是 depth − ramp_h。
		_approx("%s 挖到设计深度" % kind, hi, depth - ramp_h, 0.5)
		_approx("%s 抬到设计高度" % kind, lo, -ramp_h, 0.5)

		# 挖/抬的整段必须落在同一个区块里。跨出去的话相邻区块不知道这边在挖，
		# 会在接缝上留一道半截的坑。
		_check("%s 整段都在本区块内" % kind,
				float(lay["inset"]) - ramp >= 0.0 and float(lay["inset"]) + float(lay["width"]) + back <= cw,
				"剖面 %.0f → %.0f（区块宽 %.0f）" % [
					float(lay["inset"]) - ramp,
					float(lay["inset"]) + float(lay["width"]) + back, cw])


# ---------------------------------------------------------------- 场景搭建

## 找出这个种子下、这张图上第一块有特殊地形的区块。
## 特殊地形的种类完全由地图决定（平原只会出吊桥），所以只要找「有没有」。
func _find_index(map_id: String) -> int:
	for i in range(Maps.FEATURE_MIN_CHUNK, Maps.FEATURE_MIN_CHUNK + 80):
		if Maps.feature_at(SEED, map_id, i) != Maps.FEATURE_NONE:
			return i
	return -1


## 铺一张只有这张图、这块地形的世界。返回特殊地形所在的区块序号。
func _setup(map_id: String) -> int:
	var index := _find_index(map_id)
	if index < 0:
		return -1
	if _world != null:
		_world.queue_free()
		_car = null
	_world = Node2D.new()
	add_child(_world)

	_terrain = FlatTerrain.new()
	_terrain.bridge_scene = BRIDGE
	_terrain.sandstorm_scene = SANDSTORM
	_terrain.lake_scene = LAKE
	_terrain.crater_scene = CRATER
	_world.add_child(_terrain)
	_terrain.world_seed = SEED
	_terrain.map_id = map_id
	# 不摆金币和油桶：这一节只关心地形，少两个会动的节点少两种干扰。
	return index


## 特殊地形在区块内的跨度（世界坐标）。`inset` 相对区块左沿。
func _span_of(map_id: String, index: int) -> Rect2:
	var kind: String = Maps.get_map(map_id)["feature"]
	var lay := Maps.feature_layout(kind)
	return Rect2(
		float(index) * HillTerrain.CHUNK_WIDTH + float(lay["inset"]),
		0.0,
		float(lay["width"]),
		float(lay["depth"]),
	)


func _spawn_car(map_id: String, x: float) -> HillCar:
	# 上一辆车要收掉。同一节里换起点再 spawn 一次的话，旧车会留在世界里继续
	# 跟着跑，两个车互相撞、还会各自触发死亡区。
	if _car != null and is_instance_valid(_car):
		_car.queue_free()
	var car := CAR.instantiate()
	car.position = Vector2(x, HillTerrain.GROUND_Y - CAR_LIFT)
	_world.add_child(car)
	# 地图要在进树之后套：apply_map 读的是 @onready 的轮子节点。
	# 关卡里由 game.gd 干这件事，这里手动补上。
	car.apply_map(map_id)
	car.fuel = 1.0e9
	_terrain.set_target(car.chassis)
	return car


## 区块节点。特殊地形挂在它下面，而 find_child 递归找到的可能是别的区块里的
## 同名节点，所以按区块名精确取。
func _chunk_node(index: int) -> Node:
	return _terrain.get_node_or_null("Chunk%d" % index)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle() -> void:
	await _frames(SETTLE_FRAMES)


## 一边踩油门一边每帧回调。`st` 是个字典 —— GDScript 的 lambda 捕获局部变量是
## **按值复制**的，往里写字符串/数字出不来，写字典里的键才能带出来。
func _drive(seconds: float, st: Dictionary, on_frame: Callable = Callable()) -> void:
	Input.action_press("drive_forward")
	var frames := int(round(seconds / DT))
	for i in frames:
		await get_tree().physics_frame
		if on_frame.is_valid():
			on_frame.call(st)
	Input.action_release("drive_forward")


## 死区**真正**盖住的矩形（世界坐标）。
##
## 不能拿 `hazard.position` 当左上角：形状是以节点为**中心**挂上去的，照
## position 直接算会得到一个往右下偏半个身位的矩形 —— 第一版就是这么算的，
## 于是「位置合理」的断言全过，车却掉进湖里不死（死区实际偏到了湖的左边一半）。
## 这里按「节点位置 ± 半个尺寸」反推，量的是碰撞体真实覆盖的范围。
func _hazard_rect(hazard: Node) -> Rect2:
	var cs := hazard.get_node("Shape") as CollisionShape2D
	var size: Vector2 = cs.shape.size
	var center: Vector2 = (hazard as Node2D).position + cs.position
	return Rect2(center - size * 0.5, size)


func _consts(script: GDScript) -> Dictionary:
	return script.get_script_constant_map()


## 多边形最上面那个点的世界 y。用来把「看得见的岩浆液面」和「烧死区的顶」
## 放在一起比 —— 两个数各写各的话迟早会漂开。
func _poly_top_y(node: Node) -> float:
	var top := INF
	var base: Vector2 = (node as Node2D).global_position
	for p: Vector2 in (node as Polygon2D).polygon:
		top = minf(top, base.y + p.y)
	return top


# ---------------------------------------------------------------- F. 风力的量级

## 风到底给了车多大的力。
##
## 单独拉一节：后面 E 节的 A/B 只能说明「有风比没风慢」，说明不了「力是设计值」
## —— 加三倍的风也一样是「更慢」。这里用一个没有重力也没有地面的小世界，唯一
## 作用在车上的力就是风，于是加速度可以直接量出来。
##
## 关键判据是**质量要取整辆车**：风只加在车壳上，轮子是被关节拖着走的，所以
## 稳态下整辆车（车壳 + 两个轮子）一起加速。要是把风挨个加在三个刚体上，
## 量出来的加速度会是设计值的三倍 —— 这一条就是为了拦住那个错。
func _section_f() -> void:
	print("=== F. 风力的量级 ===")
	var consts := _consts(SANDSTORM_SCRIPT)
	var force: float = consts["WIND_FORCE"]

	var world := Node2D.new()
	add_child(world)
	# 风区盖住车，地形本身不挖（沙尘暴不挖地表），所以不需要地面。
	var zone: Node2D = SANDSTORM.instantiate()
	world.add_child(zone)
	zone.call("setup", Rect2(0.0, 0.0, 1200.0, 800.0), 400.0)

	var car := CAR.instantiate()
	car.position = Vector2(600.0, 200.0)
	world.add_child(car)
	# 显式标 float：instantiate() 出来的是无类型的 Node，car.chassis.mass 一路
	# 推不出类型来，`:=` 会在编译期报「Cannot infer the type」。
	var mass: float = car.chassis.mass + car.rear_wheel.mass + car.front_wheel.mass
	for body: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
		body.gravity_scale = 0.0
		body.linear_damp = 0.0

	# 等两帧让风区把车认进来（Area2D 的重叠列表要过一帧才填）。
	await _frames(2)
	var v0: float = car.chassis.linear_velocity.x
	# 量 20 帧：关节把轮子拽起来需要几个求解步，只量两三帧会量到过渡段。
	var frames := 20
	await _frames(frames)
	var v1: float = car.chassis.linear_velocity.x

	var measured := (v1 - v0) / (float(frames) * DT)
	var want: float = -force / mass
	print("  整车质量 %.0f，风力 %.0f → 设计加速度 %.1f px/s²" % [mass, force, want])
	print("  实测 %.1f px/s²（%d 帧从 %.2f 到 %.2f）" % [measured, frames, v0, v1])
	_check("风把车往**后**推", measured < 0.0, "加速度 %.1f" % measured)
	_within("风力大小 = 设计值", measured, want, 0.25)
	world.queue_free()


# ---------------------------------------------------------------- B. 吊桥

func _section_b() -> void:
	print("=== B. 吊桥 ===")
	var index := _setup(Maps.PLAINS)
	_check("找得到一块有吊桥的区块", index >= 0, "区块 %d" % index)
	if index < 0:
		return

	var consts := _consts(BRIDGE_SCRIPT)
	var want_planks: int = consts["PLANKS"]
	var span := _span_of(Maps.PLAINS, index)
	print("  桥面 %.0f 宽，跨在 x %.0f → %.0f 的坑上" % [span.size.x, span.position.x, span.position.x + span.size.x])

	_car = _spawn_car(Maps.PLAINS, span.position.x - RUN_UP)
	var st := {"reason": "", "max_x": -1.0e9, "min_y": 1.0e9, "plank_y": -1.0e9}
	_car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	await _settle()

	var chunk := _chunk_node(index)
	var bridge: Node = chunk.get_node_or_null("RopeBridge") if chunk != null else null
	_check("桥上树了", bridge != null, "Chunk%d/RopeBridge" % index)
	if bridge == null:
		return

	var planks := 0
	var joints := 0
	for child in bridge.get_children():
		if child is RigidBody2D:
			planks += 1
		elif child is PinJoint2D:
			joints += 1
	_check("木板数 = PLANKS", planks == want_planks, "%d（期望 %d）" % [planks, want_planks])
	_check("关节数 = 木板数 + 1（板间 + 两端钉在岸上）", joints == want_planks + 1,
			"%d（期望 %d）" % [joints, want_planks + 1])

	# 中间那块板静止时的高度，用来量「车压上去之后沉了多少」。
	var mid := bridge.get_node_or_null("Plank%d" % (want_planks / 2))
	_check("找得到正中间的木板", mid != null, "Plank%d" % (want_planks / 2))
	var rest_y := (mid as Node2D).global_position.y if mid != null else 0.0

	# 桥底那片摔死区。三条都要看：盖住坑底（真掉下去必须死）、横向盖满整个坑
	# （歪出去的话掉在另一半就不死了）、上沿离桥面足够远（骑着被压低的桥不算掉）。
	var hazard := bridge.get_node_or_null("HazardZone")
	_check("桥底有摔死区", hazard != null, "HazardZone")
	if hazard != null:
		var rect := _hazard_rect(hazard)
		_check("摔死区横向盖满整个坑",
				rect.position.x <= span.position.x and rect.end.x >= span.position.x + span.size.x,
				"区 %.0f → %.0f，坑 %.0f → %.0f" % [
					rect.position.x, rect.end.x, span.position.x, span.position.x + span.size.x])
		_check("摔死区盖住坑底",
				rect.end.y >= HillTerrain.GROUND_Y + span.size.y,
				"区底 y=%.0f，坑底 y=%.0f" % [rect.end.y, HillTerrain.GROUND_Y + span.size.y])
		_check("摔死区离桥面还有余量（桥被压低不算掉下去）",
				rect.position.y > rest_y + 50.0,
				"区顶 y=%.0f，桥面静止 y=%.0f" % [rect.position.y, rest_y])

	await _drive(5.0, st, func(s: Dictionary) -> void:
		s["max_x"] = maxf(s["max_x"], _car.chassis.global_position.x)
		s["min_y"] = minf(s["min_y"], _car.chassis.global_position.y)
		if mid != null and is_instance_valid(mid):
			s["plank_y"] = maxf(s["plank_y"], (mid as Node2D).global_position.y))

	print("  静止时中板 y=%.1f，过车时最深 y=%.1f" % [rest_y, st["plank_y"]])
	print("  最远 x=%.0f（桥右沿 %.0f），最高 y=%.0f，死因「%s」" % [
		st["max_x"], span.position.x + span.size.x, st["min_y"], st["reason"]])
	_check("车没掉下桥", String(st["reason"]) == "", "死因「%s」" % st["reason"])
	_check("车开过了桥", float(st["max_x"]) > span.position.x + span.size.x,
			"最远 %.0f，桥右沿 %.0f" % [st["max_x"], span.position.x + span.size.x])
	_check("桥被压得下沉（是软的，不是块板）", float(st["plank_y"]) > rest_y + 4.0,
			"沉了 %.1f 像素" % [float(st["plank_y"]) - rest_y])


# ---------------------------------------------------------------- C. 冰湖

func _section_c() -> void:
	print("=== C. 冰湖 ===")
	var index := _setup(Maps.SNOW)
	_check("找得到一块有冰湖的区块", index >= 0, "区块 %d" % index)
	if index < 0:
		return

	var consts := _consts(LAKE_SCRIPT)
	var grip: float = consts["ICE_GRIP"]
	var delay: float = consts["BREAK_DELAY"]
	var span := _span_of(Maps.SNOW, index)
	var need_speed := span.size.x / delay
	print("  湖面 %.0f 宽，冰面 %.1f 秒后裂 → 过湖需要 %.0f px/s" % [span.size.x, delay, need_speed])

	# ---- 车停在冰面上：抓地力被压下去、冰裂、车掉进水里淹死 ----
	#
	# **这一条必须「车还在冰上时冰裂」才算掉进湖里**，所以车是**摆**在冰面正中
	# 的，不是开过去的。第一版是「全油门开 6 秒然后断言淹死」—— 那条断言钉错了
	# 场景：车开过去的时候冰是在**它身后**裂的（实测冰裂时车已经到 x=2953、
	# 湖右沿 2820），车根本没掉进去，当然不会淹死。过湖是另一回事，见最后一段。
	_car = _spawn_car(Maps.SNOW, span.position.x + span.size.x * 0.5)
	var st := {
		"reason": "", "friction": 0.0, "grip": 1.0,
		"touched": -1.0, "broke": -1.0, "t": 0.0,
	}
	_car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	# 雪地本体摩擦的基准。**要在第一帧之前读**：这一帧冰湖还没把 surface_grip
	# 写进来，轮子上还是「雪地 × 地图倍率」的原值。读晚了拿到的已经是压过的数，
	# 后面拿它反推基准就变成自己除自己了。
	st["friction"] = _car.rear_wheel.physics_material_override.friction

	# ---- 地形结构 ----
	#
	# **这几条必须排在 _spawn_car 之后。** 区块是 set_target 的时候才建的，
	# 上面没车就一个区块都没有，这里查 IceLake/Ice 只会查到 null，然后整节
	# 从 return 溜走 —— 后面那些行为断言一条都不会跑。（原来这段在前头，是因为
	# 原来先 spawn 再查；重排之后忘了跟着挪，于是 46 条里就少了 6 条。）
	var chunk := _chunk_node(index)
	var ice: Node = chunk.get_node_or_null("IceLake/Ice") if chunk != null else null
	_check("冰板上树了", ice != null, "Chunk%d/IceLake/Ice" % index)
	if ice == null:
		return
	_check("冰板是实心的（能站人）", ice.collision_layer == 2, "层 %d" % ice.collision_layer)

	# 湖底那片淹死区。**横向必须盖满整个湖面**：死区是以节点为中心挂的，
	# 偏移半个身位的话会变成「只有湖的左半边淹得死人」，车从右半边掉下去不死。
	var hazard: Node = chunk.get_node_or_null("IceLake/HazardZone")
	_check("湖底有淹死区", hazard != null, "Chunk%d/IceLake/HazardZone" % index)
	if hazard != null:
		var hrect := _hazard_rect(hazard)
		_check("淹死区横向盖满湖面",
				hrect.position.x <= span.position.x and hrect.end.x >= span.position.x + span.size.x,
				"区 %.0f → %.0f，湖 %.0f → %.0f" % [
					hrect.position.x, hrect.end.x, span.position.x, span.position.x + span.size.x])
		_check("淹死区盖到湖底",
				hrect.end.y >= HillTerrain.GROUND_Y + span.size.y,
				"区底 y=%.0f，湖底 y=%.0f" % [hrect.end.y, HillTerrain.GROUND_Y + span.size.y])
		_check("淹死区不碰冰面（站上去不该死）", hrect.position.y > HillTerrain.GROUND_Y + 20.0,
				"区顶 y=%.0f，冰面 y=%.0f" % [hrect.position.y, HillTerrain.GROUND_Y])
	# **不要先 settle。** 车是精确摆在冰面上的（381 = 420 − 39），不需要落地；
	# 而计时从「踩上冰」算起，先跑 12 帧等于把 0.5 秒的引线偷偷烧掉 0.2 秒。

	# 采样期间区块可能被回收，那时候 ice 变成已释放实例，读属性会直接报错。
	# 所以每帧先验尸。
	for i in int(round(2.5 / DT)):
		await get_tree().physics_frame
		st["t"] = float(st["t"]) + DT
		var g: float = _car.surface_grip
		if g < 0.999:
			st["grip"] = minf(float(st["grip"]), g)
			st["friction"] = minf(float(st["friction"]),
					_car.rear_wheel.physics_material_override.friction)
			if float(st["touched"]) < 0.0:
				st["touched"] = float(st["t"])
		if float(st["touched"]) > 0.0 and float(st["broke"]) < 0.0 \
				and is_instance_valid(ice) and ice.collision_layer == 0:
			st["broke"] = float(st["t"]) - float(st["touched"])

	print("  冰上抓地倍率 %.3f（期望 %.3f），轮子摩擦 %.4f → %.4f" % [
		st["grip"], grip, st["friction"] / grip if grip > 0.0 else 0.0, st["friction"]])
	print("  第 %.2fs 踩上冰，踩上 %.2fs 后裂开（期望 %.2fs），死因「%s」" % [
		st["touched"], st["broke"], delay, st["reason"]])

	_check("踩上冰面", float(st["touched"]) > 0.0, "第 %.2fs 踩上" % st["touched"])
	_approx("冰面把抓地倍率压到 ICE_GRIP", float(st["grip"]), grip, 0.01)
	# 雪地本体摩擦 × 冰面倍率。两个数都是现取的，没写死。
	var snow_friction: float = float(st["friction"]) / grip
	_check("轮子摩擦真的被改了（不是只改了个字段）",
			float(st["friction"]) < snow_friction * 0.999,
			"%.4f → %.4f" % [snow_friction, st["friction"]])
	_approx("1 秒内冰面破开（0.5s 计时）", float(st["broke"]), delay, 0.12)
	_check("掉进湖里淹死", String(st["reason"]) == HillCar.REASON_DROWN,
			"死因「%s」" % st["reason"])

	# ---- 全油门开过去：只打印，不断言 ----
	#
	# 能不能开过湖取决于车的马力，而车的参数玩家还在编辑器里调（见 car.gd 顶部），
	# 钉死了每次调参都会被打翻。门槛是「湖宽 / 0.5 秒」，但车的轴距（110 像素）
	# 替它多买了半个身位 —— 前轮踩上冰就开始计时，等后轮离湖时车头已经过去一截，
	# 所以实测过湖速度会比门槛低一截。这条只是把「湖是可以过的」记在案上。
	#
	# **要先重建一次世界。** 上一条把车摆在冰上，冰已经裂了、车已经沉了；不重建
	# 就直接开过去，开到的是个已经破了的洞 —— 打印出来的「冰 0.02 秒就裂、没过湖」
	# 是上一条的残局，不是过湖能力的结论。（第一版就是这样，那条打印等于在骗人。）
	# 重建之后冰是完整的，这一条量的才是「全油门能不能抢在 0.5 秒里冲过 300 像素」。
	var again := _setup(Maps.SNOW)
	if again != index:
		print("  重建后区块号变了（%d → %d），这条跳过" % [index, again])
		return
	_car = _spawn_car(Maps.SNOW, span.position.x - RUN_UP)
	var ice2: Node = _terrain.get_node_or_null("Chunk%d/IceLake/Ice" % index)
	var st2 := {"reason": "", "max_x": -1.0e9, "cleared": -1.0, "broke_at": -1.0, "t": 0.0}
	_car.crashed.connect(func(r: String) -> void: st2["reason"] = r)
	await _settle()
	await _drive(6.0, st2, func(s: Dictionary) -> void:
		s["t"] = float(s["t"]) + DT
		var cx: float = _car.chassis.global_position.x
		s["max_x"] = maxf(s["max_x"], cx)
		if float(s["broke_at"]) < 0.0 and is_instance_valid(ice2) and ice2.collision_layer == 0:
			s["broke_at"] = float(s["t"])
		if float(s["cleared"]) < 0.0 and cx > lake_far_edge(span):
			s["cleared"] = _car.chassis.linear_velocity.x)
	var how := ""
	if float(st2["cleared"]) > 0.0:
		how = "以 %.0f px/s 过湖（门槛 %.0f）" % [st2["cleared"], need_speed]
	else:
		how = "没过去，最远 x=%.0f（湖右沿 %.0f）" % [st2["max_x"], span.position.x + span.size.x]
	print("  全油门开过去：冰在 %.2fs 裂开，%s，死因「%s」" % [
		st2["broke_at"], how, st2["reason"]])


## 湖右沿再过去一点，用来判断「过没过湖」。
func lake_far_edge(span: Rect2) -> float:
	return span.position.x + span.size.x + 40.0


# ---------------------------------------------------------------- D. 火山口

func _section_d() -> void:
	print("=== D. 火山口 ===")
	var index := _setup(Maps.VOLCANO)
	_check("找得到一块有火山口的区块", index >= 0, "区块 %d" % index)
	if index < 0:
		return

	var lay := Maps.feature_layout(Maps.FEATURE_CRATER)
	var ramp_h := float(lay["ramp_h"])
	var ramp_len := float(lay["ramp_len"])
	var span := _span_of(Maps.VOLCANO, index)
	# 助跑坡顶：平坦地形下坑沿比原地表高 ramp_h。
	var rim := HillTerrain.GROUND_Y - ramp_h
	print("  坑 %.0f 宽 %.0f 深，坑沿在 y=%.0f（地表 %.0f，坡长 %.0f）" % [
		span.size.x, span.size.y, rim, HillTerrain.GROUND_Y, ramp_len])

	# 直接摆在坑正上方，让它自己掉进去 —— 这一条测的是「掉进去会怎样」。
	#
	# **车不一定落得到坑底。** 车壳比后轮还往后伸 26 像素（形状 -78…90，轮子
	# 在 -52/+58），这条尾巴会卡在 84° 的坑壁上，整辆车吊着不掉（实测车壳
	# y=439、两个轮心 y=450/463，坑底在 690）。所以死区顶必须高到把吊着的车
	# 也圈进去 —— 这就是 crater.gd 把 LAVA_LEVEL 抬到 0.35（y=417）的原因。
	_car = _spawn_car(Maps.VOLCANO, span.position.x + span.size.x * 0.5)
	var st := {"reason": ""}
	_car.crashed.connect(func(r: String) -> void: st["reason"] = r)
	await _frames(90)
	var chunk := _chunk_node(index)
	var crater: Node = chunk.get_node_or_null("Crater") if chunk != null else null
	_check("火山口上树了", crater != null, "Chunk%d/Crater" % index)
	var hrect := Rect2()
	if crater != null:
		var lava: Node = crater.get_node_or_null("Lava")
		_check("岩浆画出来了", lava != null, "Crater/Lava")
		var hazard: Node = crater.get_node_or_null("HazardZone")
		_check("坑底有烧死区", hazard != null, "Crater/HazardZone")
		if hazard != null:
			# 和冰湖同一个理由：死区横向要盖满整个坑，否则只有半边烧得死人。
			hrect = _hazard_rect(hazard)
			_check("烧死区横向盖满整个坑",
					hrect.position.x <= span.position.x and hrect.end.x >= span.position.x + span.size.x,
					"区 %.0f → %.0f，坑 %.0f → %.0f" % [
						hrect.position.x, hrect.end.x, span.position.x, span.position.x + span.size.x])
			_check("烧死区盖住坑底", hrect.end.y >= rim + span.size.y,
					"区底 y=%.0f，坑底 y=%.0f" % [hrect.end.y, rim + span.size.y])
			_check("烧死区顶在坑沿之下（站在坑沿上不该死）", hrect.position.y > rim,
					"区顶 y=%.0f，坑沿 y=%.0f" % [hrect.position.y, rim])
		if lava != null:
			# 浆面和死区顶必须同一个高度：**看得见的岩浆就是会死的地方**。
			# 两个数分开写的话迟早会漂开 —— 原来浆面 0.5、死区 0.55，就已经差了
			# 21 像素（车吊着的时候 21 像素就是生死之别）。
			_check("烧死区顶＝岩浆液面",
					absf(_poly_top_y(lava) - hrect.position.y) <= 1.0,
					"浆面 y=%.0f，区顶 y=%.0f" % [_poly_top_y(lava), hrect.position.y])
	print("  车最后停在：车壳 y=%.0f，后轮 y=%.0f，前轮 y=%.0f；死区 y=%.0f → %.0f，坑底 y=%.0f" % [
		_car.chassis.global_position.y, _car.rear_wheel.global_position.y,
		_car.front_wheel.global_position.y, hrect.position.y, hrect.end.y, rim + span.size.y])
	_check("掉进火山口烧死", String(st["reason"]) == HillCar.REASON_BURN,
			"死因「%s」" % st["reason"])

	# 再跑一次全油门，看它跳不跳得过去。只打印，不断言 —— 跳不跳得过取决于
	# 车的马力，而车的参数是活的（见 car.gd 顶部）。
	_car = _spawn_car(Maps.VOLCANO, span.position.x - ramp_len - RUN_UP)
	var st2 := {"reason": "", "max_x": -1.0e9, "lip_speed": 0.0, "min_y": 1.0e9}
	_car.crashed.connect(func(r: String) -> void: st2["reason"] = r)
	await _settle()
	await _drive(6.0, st2, func(s: Dictionary) -> void:
		var p: Vector2 = _car.chassis.global_position
		s["max_x"] = maxf(s["max_x"], p.x)
		s["min_y"] = minf(s["min_y"], p.y)
		if p.x <= span.position.x:
			s["lip_speed"] = _car.chassis.linear_velocity.x)
	var far_edge := span.position.x + span.size.x
	print("  全油门：到坑沿时 %.0f px/s，最高 y=%.0f，最远 x=%.0f，死因「%s」" % [
		st2["lip_speed"], st2["min_y"], st2["max_x"], st2["reason"]])
	if String(st2["reason"]) == "" and float(st2["max_x"]) > far_edge:
		print("  → 跳过去了")
	else:
		print("  → 没跳过去（坑宽 %.0f，可以调 ramp_h 或坑宽）" % span.size.x)


# ---------------------------------------------------------------- E. 沙尘暴

func _section_e() -> void:
	print("=== E. 沙尘暴 ===")
	# 同一段路跑两次，唯一区别是风开不开。起点、油门、终点全都一样，
	# 所以速度差就是风造成的 —— 直接对比风力常量或者断言「变慢了 N%」都不如
	# 这个诚实：前者只是把常量抄一遍，后者会把地形起伏也算进去。
	var speeds := {}
	for wind_on in [true, false]:
		var index := _setup(Maps.DESERT)
		if index < 0:
			_check("找得到一块有沙尘暴的区块", false, "区块 %d" % index)
			return
		var span := _span_of(Maps.DESERT, index)
		var exit_x := span.position.x + span.size.x
		_car = _spawn_car(Maps.DESERT, span.position.x - RUN_UP)
		var st := {"reason": "", "speed": 0.0, "time": 0.0, "t": 0.0}
		_car.crashed.connect(func(r: String) -> void: st["reason"] = r)
		await _settle()
		var zone: Node = (_chunk_node(index) as Node).get_node_or_null("Sandstorm") if _chunk_node(index) != null else null
		if zone == null:
			_check("沙尘暴上树了", false, "Chunk%d/Sandstorm" % index)
			return
		# 关风 = 把这个节点自己的物理帧关掉，别的什么都不改。
		zone.set_physics_process(wind_on)

		Input.action_press("drive_forward")
		var frames := int(round(12.0 / DT))
		for i in frames:
			await get_tree().physics_frame
			st["t"] = float(st["t"]) + DT
			if _car.chassis.global_position.x >= exit_x:
				break
		# 记录**同一位置**（风区右沿）的速度，而不是同一时刻的：有风的那次
		# 跑得慢，同一时刻它还在风区里，比出来的是距离不是受力。
		st["speed"] = _car.chassis.linear_velocity.x
		st["time"] = st["t"]
		Input.action_release("drive_forward")
		speeds[wind_on] = st
		print("  %s：到风区右沿时 %.0f px/s，用时 %.2fs，死因「%s」" % [
			"开风" if wind_on else "关风", st["speed"], st["time"], st["reason"]])

	var on: Dictionary = speeds[true]
	var off: Dictionary = speeds[false]
	_check("两次都没死在路上", String(on["reason"]) == "" and String(off["reason"]) == "",
			"开风「%s」/ 关风「%s」" % [on["reason"], off["reason"]])
	_check("有风时到同一位置更慢", float(on["speed"]) < float(off["speed"]) * 0.95,
			"开风 %.0f vs 关风 %.0f（慢 %.0f%%）" % [
				on["speed"], off["speed"],
				(1.0 - float(on["speed"]) / maxf(1.0, float(off["speed"]))) * 100.0])
