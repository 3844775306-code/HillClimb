extends Node
## 专查一件事：PhysicsServer2D.body_get_param(BODY_PARAM_INERTIA)
## 到底读不读得到 RigidBody2D 自动算出来的转动惯量。
##
## 背景：car.gd 的 inertia_scale 需要「自动值 × 倍率」，必须先读出来。
## 第一版测试里三个刚体一律读回 0.00，导致倍率静默失效。
## 这里逐个排除可能的原因：时机？形状没注册？getter 本身就不回写？

const CAR_SCENE := preload("res://scenes/car.tscn")


func _ready() -> void:
	await _case_timing()
	print("")
	await _case_manual_body()
	print("")
	await _case_set_then_get()
	print("")
	await _case_car_frames()
	get_tree().quit()


## 猜测一：读得太早，物理服务器还没算。
func _case_timing() -> void:
	print("=== 时机：手搓一个带形状的 RigidBody2D，逐帧读 ===")
	var body := RigidBody2D.new()
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 21.0
	cs.shape = circle
	body.add_child(cs)
	body.mass = 22.0
	add_child(body)
	for i in range(6):
		var got: float = PhysicsServer2D.body_get_param(
				body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)
		print("  第 %d 帧  惯量 %10.3f   形状数 %d" % [
			i, got, PhysicsServer2D.body_get_shape_count(body.get_rid()),
		])
		await get_tree().physics_frame
	# 解析对照：均匀圆盘 I = ½mr²
	print("  理论值 ½mr² = %.3f" % (0.5 * 22.0 * 21.0 * 21.0))
	body.queue_free()
	await get_tree().process_frame


## 猜测二：是不是 RigidBody2D 节点有什么条件没满足（比如没进场景树 / 没睡醒）。
func _case_manual_body() -> void:
	print("=== 对照：不设 inertia，等 30 帧后读 ===")
	var body := RigidBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(160.0, 30.0)
	cs.shape = rect
	body.add_child(cs)
	body.mass = 130.0
	add_child(body)
	for i in range(30):
		await get_tree().physics_frame
	var got: float = PhysicsServer2D.body_get_param(
			body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)
	print("  30 帧后惯量 %10.3f" % got)
	print("  理论值 m(w²+h²)/12 = %.3f" % (130.0 * (160.0 * 160.0 + 30.0 * 30.0) / 12.0))
	print("  RigidBody2D.inertia 属性读回 = %.3f" % body.inertia)
	body.queue_free()
	await get_tree().process_frame


## 猜测三：显式写一个正值，getter 能不能读回来？（验证通道本身是否通畅）
func _case_set_then_get() -> void:
	print("=== 通道：显式设 inertia = 12345.0 ===")
	var body := RigidBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(160.0, 30.0)
	cs.shape = rect
	body.add_child(cs)
	body.mass = 130.0
	add_child(body)
	await get_tree().physics_frame
	body.inertia = 12345.0
	await get_tree().physics_frame
	var got: float = PhysicsServer2D.body_get_param(
			body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)
	print("  设 12345.0  →  读回 %10.3f   %s" % [
		got, "通道通" if absf(got - 12345.0) < 1.0 else "!! 通道也不通",
	])
	body.queue_free()
	await get_tree().process_frame


## 真车：逐帧读三个刚体。
func _case_car_frames() -> void:
	print("=== 真车 car.tscn，逐帧读 ===")
	var car := CAR_SCENE.instantiate()
	car.inertia_scale = 1.0
	add_child(car)
	for i in range(6):
		var parts := [["车壳", car.chassis], ["后轮", car.rear_wheel], ["前轮", car.front_wheel]]
		var line := "  第 %d 帧 " % i
		for entry in parts:
			var body: RigidBody2D = entry[1]
			var got: float = PhysicsServer2D.body_get_param(
					body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)
			line += "%s %8.2f(形%d)  " % [entry[0], got,
					PhysicsServer2D.body_get_shape_count(body.get_rid())]
		print(line)
		await get_tree().physics_frame
	car.queue_free()
