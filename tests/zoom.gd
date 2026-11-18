extends Node
## 镜头随车速伸缩的验证。
##
## 需求一句话：「车速越低，离车越近」。在 Godot 里 zoom **越大画面越大**，
## 所以近端是个大数（1.05）、远端是个小数（0.62）—— 这一节特意把「近」
## 换算成**看得见的世界宽度**（视口宽 / zoom）来断言，免得哪天有人把两个
## 常量对调了，测试还照着「zoom 变小了」一路点 OK。
##
## 两节：
## A. 映射本身 —— 直接把车速塞进刚体再调 `_zoom_target()`，中间不跑物理，
##    所以是确定的，断言可以写死。
## B. 真的开一段 —— 从静止到全油门，断言画面**确实**在往外拉，而且插值
##    确实收敛到了目标值（只测映射不测收敛的话，平滑系数写错也看不出来）。

const MAIN := preload("res://scenes/main.tscn")

var _failures := 0
var _assertions := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()

	print("=== A. 车速 → zoom 的映射 ===")
	await _mapping()
	print("")
	print("=== B. 真的开一段：画面确实在往外拉 ===")
	await _drive()

	print("")
	print("共 %d 项断言" % _assertions)
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	_assertions += 1
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _approx(label: String, got: float, want: float, tol: float) -> void:
	_assertions += 1
	var ok := absf(got - want) <= tol
	if not ok:
		_failures += 1
	print("  %s %s = %.4f（期望 %.4f ±%.4f）" % [
		"OK  " if ok else "FAIL", label, got, want, tol,
	])


## 把车速直接塞进刚体，取这一刻的 zoom 目标值。
func _zoom_at(main: HillGame, speed: float) -> float:
	main.car.chassis.linear_velocity = Vector2(speed, 0.0)
	return main._zoom_target()


func _mapping() -> void:
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame

	var vp := get_viewport().get_visible_rect().size.x
	var near_w := vp / HillGame.ZOOM_NEAR
	var far_w := vp / HillGame.ZOOM_FAR
	print("  视口宽 %.0f：最近时看得见 %.0f 宽的世界，最远时 %.0f" % [vp, near_w, far_w])
	print("  静止 %.3f   200 %.3f   800 %.3f   1500 %.3f   3000 %.3f" % [
		_zoom_at(main, 0.0), _zoom_at(main, HillGame.ZOOM_SPEED_LO),
		_zoom_at(main, 800.0), _zoom_at(main, HillGame.ZOOM_SPEED_HI),
		_zoom_at(main, 3000.0),
	])

	# 「近」= zoom 大 = 看得见的世界窄。这是需求的本体，先说清楚。
	_check("慢的时候看得见的世界更窄（这才是「离车近」）", near_w < far_w, true)

	_approx("静止时就是最近端", _zoom_at(main, 0.0), HillGame.ZOOM_NEAR, 1e-6)
	_approx("低速端边界（LO）仍是最近", _zoom_at(main, HillGame.ZOOM_SPEED_LO),
			HillGame.ZOOM_NEAR, 1e-6)
	_approx("高速端边界（HI）已到最远", _zoom_at(main, HillGame.ZOOM_SPEED_HI),
			HillGame.ZOOM_FAR, 1e-6)
	_approx("再快也不会更远（钳位）", _zoom_at(main, 3000.0), HillGame.ZOOM_FAR, 1e-6)
	_approx("中点的车速取中间值",
			_zoom_at(main, (HillGame.ZOOM_SPEED_LO + HillGame.ZOOM_SPEED_HI) * 0.5),
			(HillGame.ZOOM_NEAR + HillGame.ZOOM_FAR) * 0.5, 1e-6)

	# 单调：车速涨，zoom 只能跌，不能有回头路
	var prev := 1e9
	var monotone := true
	for i in range(0, 201):
		var speed := float(i) * 20.0
		var z := _zoom_at(main, speed)
		if z > prev + 1e-9:
			monotone = false
		prev = z
	_check("0 → 4000 px/s 全程单调（车速涨，镜头只会拉远）", monotone, true)
	_check("两端确实是不同的距离（否则需求是句空话）",
			HillGame.ZOOM_NEAR > HillGame.ZOOM_FAR, true)

	main.queue_free()
	await get_tree().process_frame


func _drive() -> void:
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	for i in 30:
		await get_tree().physics_frame

	var rest_speed: float = main.car.chassis.linear_velocity.length()
	var rest_zoom: float = main.camera.zoom.x
	print("  静止：车速 %.0f，镜头 %.3f" % [rest_speed, rest_zoom])
	_check("起步前车确实是停着的（否则下面无从对比）", rest_speed < 100.0, true)
	_approx("停着的时候镜头在最近端", rest_zoom, HillGame.ZOOM_NEAR, 0.02)

	# 收敛测试要在**目标一动不动**的时候做，否则量到的是「落后」不是「收敛」。
	# 车停着就是最干净的不动目标：把镜头硬拽到远端，看它自己走不走得回来。
	# 1.5s ≈ 6 个时间常数（系数 4），残差 exp(-6) ≈ 0.2%。
	main.camera.zoom = Vector2.ONE * HillGame.ZOOM_FAR
	for i in 90:
		await get_tree().physics_frame
	_approx("车不动时镜头自己走回最近端（插值真的在收敛）",
			main.camera.zoom.x, HillGame.ZOOM_NEAR, 0.005)

	# 真开一段，记下**峰值车速那一帧**的镜头值。
	#
	# 这里不逐帧断言「车速涨则镜头跌」：镜头是滞后跟随的，车速在地形上有起伏，
	# 一次「先减速、镜头往回缩、再加速刷新最高速」的抖动会让新最高速那一刻的
	# 镜头反而更近。那是滞后的正常表现，不是 bug —— 单调性只属于**目标值**
	# （见 A 节），不属于滞后跟随的实际值。
	var zoom_at_top := rest_zoom
	var want_at_top := HillGame.ZOOM_NEAR
	var top_speed := 0.0
	Input.action_press("drive_forward")
	for i in 240:   # 4 秒
		await get_tree().physics_frame
		var speed: float = main.car.chassis.linear_velocity.length()
		if speed > top_speed:
			top_speed = speed
			zoom_at_top = main.camera.zoom.x
			want_at_top = main._zoom_target()
	Input.action_release("drive_forward")

	var zoom: float = main.camera.zoom.x
	var want: float = main._zoom_target()
	# 收尾位置和那里的挖坑量：滞后有多大量的是**车速掉得多快**，而车速掉得多快
	# 取决于车开到了什么地方。收尾那一帧正好压在某个特殊地形的过渡段上，还是
	# 在普通地形上，这两件事得分开看。
	var end_x: float = main.car.chassis.global_position.x
	print("  全油门 4s：峰值车速 %.0f（此刻镜头 %.3f，目标 %.3f），收尾车速 %.0f，镜头 %.3f（目标 %.3f）" % [
		top_speed, zoom_at_top, want_at_top,
		main.car.chassis.linear_velocity.length(), zoom, want,
	])
	print("  收尾位置 x=%.0f（第 %d 区块），那里挖坑 -%.1f" % [
		end_x, int(floor(end_x / HillTerrain.CHUNK_WIDTH)), -main.terrain._carve(end_x),
	])
	print("  镜头走过 %.3f → %.3f，看得见的世界 %.0f → %.0f 宽" % [
		rest_zoom, zoom_at_top,
		get_viewport().get_visible_rect().size.x / rest_zoom,
		get_viewport().get_visible_rect().size.x / zoom_at_top,
	])

	_check("确实开起来了（峰值车速 > 500，否则下面两条是空跑）", top_speed > 500.0, true)
	_check("镜头明显拉远了（比静止时远 0.1 以上）",
			zoom_at_top < rest_zoom - 0.1, true)
	# 峰值那一帧车速变化最慢，滞后也最小，这里可以卡得紧一点。
	_approx("峰值车速时镜头已经贴住目标（滞后 < 0.05）",
			zoom_at_top, want_at_top, 0.05)
	# **不在这里断「收尾那一帧的落后量」** —— 那条量的是车速掉得多快，而车速掉得多快
	# 取决于车当时压在地形的什么地方，不是镜头的行为。实测（同一条测试连跑三次）：
	# 收尾位置在 x=2520 / 2566 / 2663 之间飘，车速 196 / 722 / 753；x=2520 那次车正好
	# 停在坑沿上（那里挖坑量 0），车速一路回落到两百，目标值随即走回近端 → 落后量
	# 0.109，超过原来那个 0.10 的阈值就红了。而「镜头卡住」这件事实测也不是这个量：
	# 卡住的镜头在**峰值车速那一帧**就已经贴不住目标了（上面那条 ±0.05 会红），
	# 再加上「车停着时镜头自己走回最近端」那条，机制两头都钉住了。
	#
	# 顺带记一笔：这段发散**和特殊地形无关**。三次跑在 t=1s 就已经差了 7.5 像素
	# （545.7 vs 538.2，那里是 x≈540 的普通地形，前面一千八百像素内没有任何特殊地形），
	# 四秒里放大到一百多像素。所以上面那个阈值本来就断不住 —— 它是条会随机红的断言。
	_check("全程停在近端和远端之间",
			zoom_at_top > HillGame.ZOOM_FAR and zoom_at_top < HillGame.ZOOM_NEAR, true)

	main.queue_free()
	await get_tree().process_frame
