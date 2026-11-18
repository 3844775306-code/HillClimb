extends Node
## 地面材质到底算不算数？
##
## 给地面挂一个 PhysicsMaterial 是「让这段路变滑」最自然的写法，但**轮子上写了
## `rough = true`**，而 Godot 的粗糙规则是「粗糙那一方的摩擦直接用，不做合成」。
## 双方都粗糙的时候谁说了算，源码里的分支不好猜，所以这里直接量：
##
##   地面材质           预期（如果地面说了算）
##   无材质             基准
##   rough = false      不滑（被轮子的 2.6 盖掉）
##   rough = true       很滑（0.06 生效）
##
## 量法：同一条平路全油门 2 秒，看车速和打滑。滑的话车速会明显低、轮子明显空转。

const CAR := preload("res://scenes/car.tscn")

const START_X := 120.0
const CAR_Y := -39.0
const RUN_TIME := 2.0
const SETTLE := 12
const GROUND_FRICTION := 0.06

var _world: Node2D


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()
	print("地面材质        车速   轮面速度   打滑   2s 里程")
	await _case("无材质", null)
	await _case("rough=false 0.06", _mat(false))
	await _case("rough=true  0.06", _mat(true))
	get_tree().quit()


func _mat(rough: bool) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = GROUND_FRICTION
	m.rough = rough
	return m


func _case(label: String, material: PhysicsMaterial) -> void:
	if _world != null:
		_world.queue_free()
	_world = Node2D.new()
	add_child(_world)

	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	if material != null:
		body.physics_material_override = material
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(20000.0, 0.0),
		Vector2(20000.0, 800.0), Vector2(-400.0, 800.0),
	])
	body.add_child(shape)
	_world.add_child(body)

	var car: HillCar = CAR.instantiate()
	car.position = Vector2(START_X, CAR_Y)
	_world.add_child(car)
	car.fuel = 1.0e9
	var x0 := car.chassis.global_position.x
	for i in SETTLE:
		await get_tree().physics_frame

	Input.action_press("drive_forward")
	for i in int(round(RUN_TIME * 60.0)):
		await get_tree().physics_frame
	Input.action_release("drive_forward")

	var speed := car.chassis.linear_velocity.x
	var surface := car.rear_wheel.angular_velocity * 21.0
	print("%-16s %6.0f   %8.0f   %5.2f×  %6.0f" % [
		label, speed, surface, surface / maxf(1.0, absf(speed)),
		car.chassis.global_position.x - x0,
	])
