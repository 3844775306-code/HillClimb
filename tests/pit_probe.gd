extends Node
## 坑探针：车落进「坑」里之后到底停在哪、死区盖没盖到它。
##
## 起因：套件里「掉进火山口烧死」「掉进湖里淹死」两条在死区摆正之后双双挂了。
## 剖面、死区位置、碰撞多边形全都对，所以问题只能是**车没落到死区里**。
## 这个探针把地形照原样搭出来，把车摆在坑正上方，然后逐帧量：
##
##   1. 碰撞多边形在坑这一段的真实形状（车能踩到哪）
##   2. 车壳 / 两个轮子每一帧在哪
##   3. 死区真实盖住的矩形，以及三个刚体里有几个落在里面
##   4. 收尾时车底下到底压着谁（射线从形状内部出发会漏掉那个形状，所以还要
##      用点重叠查询再问一遍）
##
## 火山口和冰湖都跑一遍 —— 两个坑一起挂，很可能是一个原因。

const CAR := preload("res://scenes/car.tscn")
const CRATER := preload("res://scenes/crater.tscn")
const LAKE := preload("res://scenes/ice_lake.tscn")
const DT := 1.0 / 60.0
const SEED := 1337
const CAR_LIFT := 39.0
const WATCH_FRAMES := 360


class FlatTerrain extends HillTerrain:
	func _base_height(_x: float) -> float:
		return GROUND_Y


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	# 火山口：车直接落在坑正上方，看它掉不掉得进去。
	await _probe("火山口（空投）", Maps.VOLCANO, CRATER, false)
	# 冰湖：套件里 C 节是**开过去**的，空投反而不挂。照原样开一遍。
	await _probe("冰湖（开过去）", Maps.SNOW, LAKE, true)
	get_tree().quit()


func _probe(title: String, map_id: String, feature_scene: PackedScene, drive: bool) -> void:
	print("")
	print("================ %s（%s） ================" % [title, map_id])
	var index := -1
	for i in range(Maps.FEATURE_MIN_CHUNK, Maps.FEATURE_MIN_CHUNK + 80):
		if Maps.feature_at(SEED, map_id, i) != Maps.FEATURE_NONE:
			index = i
			break
	if index < 0:
		print("这个种子下没有特殊地形")
		return

	var world := Node2D.new()
	add_child(world)
	var terrain: HillTerrain = FlatTerrain.new()
	terrain.crater_scene = CRATER
	terrain.lake_scene = LAKE
	terrain.bridge_scene = preload("res://scenes/rope_bridge.tscn")
	terrain.sandstorm_scene = preload("res://scenes/sandstorm.tscn")
	world.add_child(terrain)
	terrain.world_seed = SEED
	terrain.map_id = map_id

	var kind: String = Maps.get_map(map_id)["feature"]
	var lay := Maps.feature_layout(kind)
	var span := Rect2(float(index) * HillTerrain.CHUNK_WIDTH + float(lay["inset"]),
			0.0, float(lay["width"]), float(lay["depth"]))
	var drop_x := span.position.x + span.size.x * 0.5
	print("第 %d 块，%s 跨度 x %.0f → %.0f（宽 %.0f 深 %.0f），车摆在 x=%.0f" % [
		index, kind, span.position.x, span.position.x + span.size.x,
		span.size.x, span.size.y, drop_x])

	# 车先建：区块要等 set_target 之后才建出来。
	var car := CAR.instantiate()
	var start_x := span.position.x - 700.0 if drive else drop_x
	car.position = Vector2(start_x, HillTerrain.GROUND_Y - CAR_LIFT)
	world.add_child(car)
	car.apply_map(map_id)
	car.fuel = 1.0e9
	var reason := {"r": ""}
	car.crashed.connect(func(r: String) -> void: reason["r"] = r)
	terrain.set_target(car.chassis)

	var chunk := terrain.get_node_or_null("Chunk%d" % index)
	if chunk == null:
		print("区块没建出来")
		return
	var collider: CollisionPolygon2D = null
	for child in chunk.get_node("Ground").get_children():
		if child is CollisionPolygon2D:
			collider = child
			break
	print("碰撞多边形的剖面（跨度内每 20 像素一个采样点）：")
	var line := ""
	for p in collider.polygon:
		if p.x >= span.position.x - 40.0 and p.x <= span.position.x + span.size.x + 40.0:
			line += "%.0f:%.0f  " % [p.x, p.y]
	print("  " + line)

	# 特殊地形节点：区块下除了 Ground 之外的那个。
	var feature: Node = null
	for child in chunk.get_children():
		if child != chunk.get_node("Ground"):
			feature = child
	var hazard: Node = feature.get_node_or_null("HazardZone") if feature != null else null
	var hrect := Rect2(0.0, 0.0, 0.0, 0.0)
	if hazard != null:
		var cs := hazard.get_node("Shape") as CollisionShape2D
		var size: Vector2 = cs.shape.size
		hrect = Rect2((hazard as Node2D).position + cs.position - size * 0.5, size)
		print("死区 x %.0f → %.0f，y %.0f → %.0f（地表 %.0f，坑底 %.0f）" % [
			hrect.position.x, hrect.end.x, hrect.position.y, hrect.end.y,
			HillTerrain.GROUND_Y, HillTerrain.GROUND_Y + span.size.y])
	else:
		print("特殊地形节点 %s 底下没有 HazardZone" % ("(缺)" if feature == null else feature.name))

	var whole := {"inside": []}
	if drive:
		Input.action_press("drive_forward")
	for i in WATCH_FRAMES + 1:
		var parts := {"壳": car.chassis, "后": car.rear_wheel, "前": car.front_wheel}
		var inside := []
		var desc := ""
		for k in parts.keys():
			var b: RigidBody2D = parts[k]
			if hrect.has_point(b.global_position):
				inside.append(k)
			desc += "%s x=%7.1f y=%7.1f  " % [k, b.global_position.x, b.global_position.y]
		if not inside.is_empty():
			whole["inside"].append("%.2fs:%s" % [float(i) * DT, ",".join(inside)])
		if i % 30 == 0 or i == WATCH_FRAMES:
			var extra := ""
			if feature != null and feature.has_node("Ice"):
				extra = "冰层=%d " % (feature.get_node("Ice") as StaticBody2D).collision_layer
			print("  t=%4.2f %s%svx=%6.1f 死区里 %s  活=%s 死因「%s」" % [
				float(i) * DT, desc, extra, car.chassis.linear_velocity.x,
				("—" if inside.is_empty() else ",".join(inside)), car.alive, reason["r"]])
		await get_tree().physics_frame
	Input.action_release("drive_forward")

	if whole["inside"].is_empty():
		print("→ 三个刚体**从头到尾**都没进过死区")
	else:
		print("→ 进过死区的时刻：%s" % ", ".join(whole["inside"].slice(0, 6)))

	# 收尾：车底下压着谁？
	var space: PhysicsDirectSpaceState2D = car.chassis.get_world_2d().direct_space_state
	var tiny := CircleShape2D.new()
	tiny.radius = 1.0
	var shape_q := PhysicsShapeQueryParameters2D.new()
	shape_q.shape = tiny
	shape_q.collide_with_areas = true
	shape_q.collide_with_bodies = true
	shape_q.collision_mask = 0xFFFFFFFF
	shape_q.exclude = [car.chassis.get_rid(), car.rear_wheel.get_rid(), car.front_wheel.get_rid()]
	var parts2 := {"壳": car.chassis, "后轮": car.rear_wheel, "前轮": car.front_wheel}
	for k in parts2.keys():
		var b: RigidBody2D = parts2[k]
		shape_q.transform = Transform2D(0.0, b.global_position)
		var found: Array[Dictionary] = space.intersect_shape(shape_q, 16)
		var names := []
		for f in found:
			names.append(String((f["collider"] as Node).name))
		var q := PhysicsRayQueryParameters2D.create(
				b.global_position, b.global_position + Vector2(0.0, 500.0))
		q.collision_mask = 0xFFFFFFFF
		var hit: Dictionary = space.intersect_ray(q)
		print("  %s：压着 [%s]，正下方撞到 %s y=%.1f（自身 y=%.1f）" % [
			k, ", ".join(names),
			("空" if hit.is_empty() else String((hit["collider"] as Node).name)),
			(-1.0 if hit.is_empty() else (hit["position"] as Vector2).y), b.global_position.y])
	print("  车壳转角 %.2f 度" % rad_to_deg(car.chassis.rotation))
	world.queue_free()
	await get_tree().process_frame
