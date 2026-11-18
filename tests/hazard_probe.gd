extends Node
## 死区探针：把车从高处丢下来穿过一片死区，逐帧打印「车在哪」和「死区认到了谁」。
##
## 起因是套件的「掉进湖里淹死 / 掉进火山口烧死」两条在修好死区偏移之后反而
## 挂了，而地形、剖面、区域位置全是对的 —— 那就把地形整个拿掉，只留车和死区，
## 看两件事：Area2D 到底有没有认出车壳、认出来之后有没有把车判死。
##
## 没有地面，车一路自由落体，所以它必然会穿过死区，不存在「没落到」的干扰。

const CAR := preload("res://scenes/car.tscn")
const HAZARD := preload("res://scenes/hazard_zone.tscn")
const DT := 1.0 / 60.0

## 死区在世界坐标里的位置。
const ZONE := Rect2(0.0, 100.0, 200.0, 120.0)


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false

	# 车的三个刚体分别是什么层、什么掩码 —— 死区只认 1 层。
	var car := CAR.instantiate()
	add_child(car)
	car.position = Vector2(ZONE.position.x + ZONE.size.x * 0.5, -400.0)
	var reason := {"r": ""}
	car.crashed.connect(func(r: String) -> void: reason["r"] = r)

	var zone: Area2D = HAZARD.instantiate()
	add_child(zone)
	zone.call("setup", ZONE, HillCar.REASON_BURN, Color(1.0, 0.3, 0.1, 0.4))

	print("=== 刚体层 / 掩码 ===")
	for body: RigidBody2D in [car.chassis, car.rear_wheel, car.front_wheel]:
		print("  %-11s 层 %d  掩码 %d" % [body.name, body.collision_layer, body.collision_mask])
	print("死区：层 %d  掩码 %d  位置 %s  形状 %s  尺寸 %s" % [
		zone.collision_layer, zone.collision_mask, zone.position,
		(zone.get_node("Shape") as CollisionShape2D).shape.get_class(),
		(zone.get_node("Shape") as CollisionShape2D).shape.size])

	print("=== 自由落体穿过死区 ===")
	var hit := 0
	var dead_at := -1.0
	var t := 0.0
	for i in 200:
		await get_tree().physics_frame
		t += DT
		var bodies := zone.get_overlapping_bodies()
		if bodies.size() > 0:
			hit += 1
			if hit == 1:
				var names := []
				for b in bodies:
					names.append(String((b as Node).name))
				print("  t=%.2f 第一次认到刚体：%s（车壳 y=%.1f）" % [
					t, ", ".join(names), car.chassis.global_position.y])
		if dead_at < 0.0 and not car.alive:
			dead_at = t
		if i % 20 == 0:
			print("  t=%.2f 车壳 y=%7.1f 区域内 %d 个  死因「%s」" % [
				t, car.chassis.global_position.y, bodies.size(), reason["r"]])

	print("结果：区域共认到刚体 %d 帧，判死时刻 %.2fs，死因「%s」" % [hit, dead_at, reason["r"]])
	get_tree().quit()
