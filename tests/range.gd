extends Node
## 真实地形上的续航对比。
##
## 同一个世界种子（terrain.world_seed = 1337），只改马达力度，全油门跑同样时间，
## 看跑多远、最长卡住多久。地形随距离变陡，所以「跑得越远」= 「越能爬」。
## 这是端到端指标，不受测试台架过渡形状的影响。

const MAIN := preload("res://scenes/main.tscn")
const DURATION := 45.0
const SAMPLE := 15.0
## com = 车身的自定义重心 y（null = 用自动算出来的、偏高的重心）。
## 重心越高，车身俯仰幅度越大 —— 翘头或扎头到一定程度车壳就会蹭地搁浅，
## 轮子悬空后再也出不来，这是目前跑不下去的主因。
const CONFIGS := [
	{"label": "惯量 ×1.0", "strength": 60000.0, "inertia": 1.0, "com": null},
	{"label": "惯量 ×2.0（默认）", "strength": 60000.0, "inertia": 2.0, "com": null},
]


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1，理由同 climb.gd
	# 自动机会开出上千公里，别让它覆盖玩家真正的存档。
	# reset_progress() 顺带把升级等级清零，否则玩家练满的车会混进续航对比里。
	SaveData.persist = false
	SaveData.reset_progress()
	for config in CONFIGS:
		await _run(config)
	get_tree().quit()


func _run(config: Dictionary) -> void:
	var main: HillGame = MAIN.instantiate()
	# inertia_scale 必须在车进场景树之前设好：car.gd 是在 _ready() 里异步
	# 应用这个倍率的，进树之后再改就晚了（那一刻 @onready 也还没赋值）。
	(main.get_node("Car") as HillCar).inertia_scale = config["inertia"]
	add_child(main)
	await get_tree().process_frame
	var car: HillCar = main.car
	car.motor_strength = config["strength"]
	if config["com"] != null:
		car.chassis.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
		car.chassis.center_of_mass = Vector2(0.0, config["com"])
	car.fuel_max = 1.0e9
	car.fuel = 1.0e9
	for part in [car.chassis, car.rear_wheel, car.front_wheel]:
		part.contact_monitor = true
		part.max_contacts_reported = 8

	Input.action_press("drive_forward")
	var t := 0.0
	var best_x: float = car.chassis.global_position.x
	var progressed_at := 0.0
	var worst_stall := 0.0
	var marks := PackedStringArray()
	var dumped := false
	while t < DURATION and car.alive:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		car.fuel = 1.0e9
		var x: float = car.chassis.global_position.x
		if x > best_x + 20.0:
			best_x = x
			progressed_at = t
		worst_stall = maxf(worst_stall, t - progressed_at)
		# 卡住超过 3 秒就抓一次现场：是抓不住地、还是车壳搁浅、还是地形太陡
		if not dumped and t - progressed_at > 3.0:
			dumped = true
			var h0: float = main.terrain.height_at(x - 60.0)
			var h1: float = main.terrain.height_at(x + 60.0)
			print("      卡住现场 t=%.1fs x=%.0f  坡度 %.1f°  俯仰 %.1f°  轮速 %.1f  触地 后%d前%d壳%d" % [
				t, x, rad_to_deg(atan2(h0 - h1, 120.0)), rad_to_deg(car.chassis.rotation),
				car.rear_wheel.angular_velocity,
				car.rear_wheel.get_colliding_bodies().size(),
				car.front_wheel.get_colliding_bodies().size(),
				car.chassis.get_colliding_bodies().size(),
			])
		if fmod(t, SAMPLE) < 0.01:
			marks.append("%.0fs:%.0fm" % [t, (x - 200.0) / 10.0])
	Input.action_release("drive_forward")

	print("%-18s →  里程 %6.1f m   最长卡住 %4.1fs   %s" % [
		config["label"], (best_x - 200.0) / 10.0, worst_stall, "  ".join(marks),
	])
	if not car.alive:
		print("       （中途翻车，t=%.1fs）" % t)
	main.queue_free()
