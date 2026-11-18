extends Node
## 「金币每次玩都会累加、最远里程会存档」的端到端验证。
##
## 跑两次真实关卡（main.tscn），每次跑到翻车/没油，然后跨局断言：
##   - 第一次：纪录被这一局刷新，金币总数 == 这一局吃到的
##   - 第二次：金币总数 == 两次之和（这才是「累加」，不是「覆盖」）
##            纪录 == 两次里更远的那个
##
## 全程 persist = false，不碰玩家存档；但内存里的累加逻辑与联机路径完全一致，
## 而「写盘 → 读回」那一段由 tests/save.tscn 单独覆盖。

const MAIN := preload("res://scenes/main.tscn")
const RUN := 8.0

var _failures := 0


func _ready() -> void:
	SaveData.persist = false
	SaveData.reset_progress()

	var a := await _session("第一次")
	print("")
	var b := await _session("第二次")

	print("")
	print("=== 跨局断言 ===")
	# 第一次：纪录从 0 开始，这一局必定刷新
	_check("第一次翻车后 game_over", a["over"], true)
	_check("第一次纪录 = 本局里程", a["best"], a["meters"])
	_check("第一次金币总数 = 本局金币", a["total"], a["coins"])
	_check("第一次确实吃到了金币（否则下面的累加是空跑）", a["coins"] > 0, true)

	# 第二次：金币必须累加，纪录取两次里更远的
	_check("第二次翻车后 game_over", b["over"], true)
	_check("金币跨局累加", b["total"], a["coins"] + b["coins"])
	_check("纪录取更远的那个", b["best"], maxi(a["meters"], b["meters"]))
	print("  （第一次 %d m / %d 币，第二次 %d m / %d 币）" % [
		a["meters"], a["coins"], b["meters"], b["coins"],
	])

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _session(label: String) -> Dictionary:
	print("=== %s ===" % label)
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame

	main.car.fuel_max = 1.0e9     # 别在半路没油，先跑满 RUN 秒
	main.car.fuel = 1.0e9
	Input.action_press("drive_forward")
	var t := 0.0
	while t < RUN:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	Input.action_release("drive_forward")

	# 路上大概率能吃到金币，但不保证；补三枚把路径钉死，
	# 否则「累加」断言可能因为一粒都没吃到而退化成 0 == 0 的空跑。
	# 金额得跟着给：补给信号现在带数量（油桶按桶算、金币按面值），
	# 这里给 1.0 就是测试场景里金币的面值。
	for i in range(3):
		main._on_pickup_collected("coin", 1.0)

	var coins: int = main.coins
	var meters: int = main.distance_meters()
	print("  跑完 %0.1fs：%d m，%d 枚金币（内存里累计 %d）" % [RUN, meters, coins, SaveData.total_coins])

	# 强制结束：把油抽干，下一物理帧 _burn_fuel 就会判定「没油了」
	main.car.fuel = 0.0
	for i in range(3):
		await get_tree().physics_frame

	var out := {
		"coins": coins,
		"meters": meters,
		"over": main.game_over,
		"total": SaveData.total_coins,
		"best": SaveData.best_distance,
	}
	print("  结算后：纪录 %d m，金币总数 %d" % [out["best"], out["total"]])
	main.queue_free()
	await get_tree().process_frame
	return out
