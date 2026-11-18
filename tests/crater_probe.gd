extends Node
## 火山口探针：把车从坑正上方丢下去，量三样东西 ——
##
##   1. 地块的**碰撞多边形**在坑这一段的真实高度（车能落在哪，只有这个说了算）
##   2. 车壳每一帧落在哪
##   3. 烧死区真实盖住的矩形，以及车最后在不在里面
##
## 起因：套件里「掉进火山口烧死」在死区摆正之后反而挂了。地形、剖面、死区位置
## 本身全都是对的（A 节的断言都过），所以只能是把车丢下去之后它**没到**死区里。
## 与其猜是「卡在坑壁上了」还是「落在坑沿上了」，不如把多边形顶点打出来看。

const CAR := preload("res://scenes/car.tscn")
const CRATER := preload("res://scenes/crater.tscn")
const DT := 1.0 / 60.0
const SEED := 1337
const CAR_LIFT := 39.0


class FlatTerrain extends HillTerrain:
	func _base_height(_x: float) -> float:
		return GROUND_Y


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false

	var index := -1
	for i in range(Maps.FEATURE_MIN_CHUNK, Maps.FEATURE_MIN_CHUNK + 80):
		if Maps.feature_at(SEED, Maps.VOLCANO, i) != Maps.FEATURE_NONE:
			index = i
			break
	if index < 0:
		print("这个种子下火山图没有火山口")
		get_tree().quit()
		return

	var world := Node2D.new()
	add_child(world)
	var terrain: HillTerrain = FlatTerrain.new()
	terrain.crater_scene = CRATER
	world.add_child(terrain)
	terrain.world_seed = SEED
	terrain.map_id = Maps.VOLCANO

	var lay := Maps.feature_layout(Maps.FEATURE_CRATER)
	var span := Rect2(float(index) * HillTerrain.CHUNK_WIDTH + float(lay["inset"]),
			0.0, float(lay["width"]), float(lay["depth"]))
	var drop_x := span.position.x + span.size.x * 0.5
	print("火山口在第 %d 块，坑 x %.0f → %.0f（宽 %.0f 深 %.0f）" % [
		index, span.position.x, span.position.x + span.size.x, span.size.x, span.size.y])

	var car := CAR.instantiate()
	car.position = Vector2(drop_x, HillTerrain.GROUND_Y - CAR_LIFT)
	world.add_child(car)
	car.apply_map(Maps.VOLCANO)
	car.fuel = 1.0e9
	var reason := {"r": ""}
	car.crashed.connect(func(r: String) -> void: reason["r"] = r)
	# 进树 + 定好目标之后区块才会建，所以多边形要等这一步之后才读得到。
	terrain.set_target(car.chassis)

	# ---- 1. 碰撞多边形：车**真正**能落在哪 ----
	var chunk := terrain.get_node_or_null("Chunk%d" % index)
	if chunk == null:
		print("Chunk%d 没建出来" % index)
		get_tree().quit()
		return
	# 碰撞多边形那个节点没有显式命名，别按名字取 —— 遍历找。
	var collider: CollisionPolygon2D = null
	for child in chunk.get_node("Ground").get_children():
		if child is CollisionPolygon2D:
			collider = child
			break
	if collider == null:
		print("Ground 底下没有 CollisionPolygon2D")
		get_tree().quit()
		return
	var poly: PackedVector2Array = collider.polygon
	print("碰撞多边形共 %d 个顶点，构建模式 %d（0=SOLIDS 1=SEGMENTS）：" % [
		poly.size(), collider.build_mode])
	for i in poly.size():
		print("  [%2d] x=%7.1f  y=%7.1f" % [i, poly[i].x, poly[i].y])

	# ---- 2. 车落到哪 ----
	print("车丢在 x=%.0f, y=%.1f" % [drop_x, HillTerrain.GROUND_Y - CAR_LIFT])
	var crater: Node = chunk.get_node_or_null("Crater")
	var hazard: Node = crater.get_node_or_null("HazardZone") if crater != null else null
	var hrect := Rect2()
	if hazard != null:
		var cs := hazard.get_node("Shape") as CollisionShape2D
		var size: Vector2 = cs.shape.size
		var center: Vector2 = (hazard as Node2D).position + cs.position
		hrect = Rect2(center - size * 0.5, size)
		print("烧死区 x %.0f → %.0f，y %.0f → %.0f（Crater.rim_y=%.1f）" % [
			hrect.position.x, hrect.end.x, hrect.position.y, hrect.end.y, crater.rim_y])
	else:
		print("坑底没有烧死区")

	for i in 121:
		if i % 10 == 0 or i == 120:
			var rigid := [car.chassis, car.rear_wheel, car.front_wheel]
			var inside := 0
			for b: RigidBody2D in rigid:
				if hrect.has_point(b.global_position):
					inside += 1
			print("  t=%4.2f 车壳 x=%7.1f y=%7.1f vy=%7.1f  后轮 x=%7.1f y=%7.1f  在死区里的刚体 %d/3  活=%s 死因「%s」" % [
				float(i) * DT, car.chassis.global_position.x, car.chassis.global_position.y,
				car.chassis.linear_velocity.y, car.rear_wheel.global_position.x,
				car.rear_wheel.global_position.y, inside, car.alive, reason["r"]])
		await get_tree().physics_frame

	print("结论：车壳停在 y=%.1f，死区 y %.0f → %.0f，死因「%s」" % [
		car.chassis.global_position.y, hrect.position.y, hrect.end.y, reason["r"]])

	# ---- 车架在什么上面？往下打一条射线，再把区块里所有节点列出来 ----
	var space: PhysicsDirectSpaceState2D = car.chassis.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(
			car.chassis.global_position, car.chassis.global_position + Vector2(0.0, 600.0))
	q.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		print("车壳正下方 600 像素内什么都没有")
	else:
		print("车壳正下方先撞到：%s（%s），y=%.1f，法线 %s" % [
			(hit["collider"] as Node).name, str(hit["collider"].get_path()),
			(hit["position"] as Vector2).y, str(hit["normal"])])
	# 轮子底下各自打一条射线 —— 车壳中心那条打不到的东西，可能正好在轮子下面。
	for label in [["后轮", car.rear_wheel], ["前轮", car.front_wheel]]:
		var w: RigidBody2D = label[1]
		var wq := PhysicsRayQueryParameters2D.create(
				w.global_position, w.global_position + Vector2(0.0, 400.0))
		wq.collision_mask = 0xFFFFFFFF
		var wh: Dictionary = space.intersect_ray(wq)
		if wh.is_empty():
			print("%s 正下方 400 像素内什么都没有（轮心 y=%.1f）" % [label[0], w.global_position.y])
		else:
			print("%s 正下方先撞到 %s，y=%.1f（轮心 y=%.1f）" % [
				label[0], (wh["collider"] as Node).name,
				(wh["position"] as Vector2).y, w.global_position.y])

	# 车所在的位置上到底压着谁？射线从形状**内部**出发时会跳过那个形状，所以
	# 射线量不到的东西，用「点重叠查询」直接列出来 —— 排除掉车自己的三个刚体。
	var tiny := CircleShape2D.new()
	tiny.radius = 1.0
	var shape_q := PhysicsShapeQueryParameters2D.new()
	shape_q.shape = tiny
	shape_q.collide_with_areas = true
	shape_q.collide_with_bodies = true
	shape_q.collision_mask = 0xFFFFFFFF
	shape_q.exclude = [car.chassis.get_rid(), car.rear_wheel.get_rid(), car.front_wheel.get_rid()]
	for label in [["车壳", car.chassis], ["后轮", car.rear_wheel], ["前轮", car.front_wheel]]:
		var b: RigidBody2D = label[1]
		shape_q.transform = Transform2D(0.0, b.global_position)
		var found: Array[Dictionary] = space.intersect_shape(shape_q, 16)
		if found.is_empty():
			print("%s 的位置上什么都没压着（y=%.1f）" % [label[0], b.global_position.y])
		for f in found:
			var c: Node = f["collider"]
			print("%s 的位置上压着：%s（%s）层 %d" % [
				label[0], c.name, str(c.get_path()),
				(c as CollisionObject2D).collision_layer])

	print("刚体状态：")
	for b: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
		print("  %-11s 睡=%s 冻结=%s 阻尼=%.3f 重力=%.2f 质量=%.1f 速度=%s" % [
			b.name, b.sleeping, b.freeze, b.linear_damp, b.gravity_scale, b.mass,
			str(b.linear_velocity)])
	print("火山图 drag=%.3f，车壳 alive=%s throttle=%.2f" % [
		float(Maps.get_map(Maps.VOLCANO)["drag"]), car.alive, car.throttle])

	print("区块 %d 里的节点：" % index)
	_dump(chunk, "")
	print("两个轮子：后 y=%.1f 前 y=%.1f，车壳转角 %.2f 度" % [
		car.rear_wheel.global_position.y, car.front_wheel.global_position.y,
		rad_to_deg(car.chassis.rotation)])
	get_tree().quit()


func _dump(node: Node, indent: String) -> void:
	for child in node.get_children():
		var pos := ""
		if child is Node2D:
			pos = " 位置 %s" % str((child as Node2D).position)
		var layer := ""
		if child is CollisionObject2D:
			layer = " 层 %d 掩码 %d" % [(child as CollisionObject2D).collision_layer,
					(child as CollisionObject2D).collision_mask]
		print("  %s%s (%s)%s%s" % [indent, child.name, child.get_class(), pos, layer])
		_dump(child, indent + "  ")
