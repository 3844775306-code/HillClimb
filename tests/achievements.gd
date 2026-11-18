extends Node
## 里程成就（每张地图每 500 米一个、发 500 块）的验证。
##
## 这套的重点不是算术（那部分是纯函数，一眼能看出来），而是三件容易写歪的事：
##
##   * **一个档只发一次。** 按局发的话，跑 500 米就故意翻车、重开，一趟一趟刷，
##     比认真跑下去赚得快 —— 这个 bug 在测试里表现为「跨过 500 米两次，金币只该 +500」。
##   * **一次跨过好几个要全发。** 极速下 500 米约 5 秒，debug 传送更是一步一串，
##     `if` 写法和 `while` 写法在这一条上结果不同。
##   * **成就是按图分开的。** 雪地跑 500 米不该点亮平原的成就（这和里程纪录同一条规矩）。
##
## 存档相关的部分会**真的读写盘**（user://save.cfg），所以开头把整份存档文件
## 备份成字节、结束时原样贴回去 —— 按字段备份容易漏字段，而这个测试会碰
## 金币、纪录、成就三块数据。

const MAIN := preload("res://scenes/main.tscn")

var _failures := 0
var _saved_bytes := PackedByteArray()
var _had_save := false


func _ready() -> void:
	print("存档路径 %s" % ProjectSettings.globalize_path(SaveData.SAVE_PATH))
	_backup_file()

	_math()
	print("")
	_claim_semantics()
	print("")
	_per_map()
	print("")
	_multi_step()
	print("")
	await _persist()
	print("")
	await _game_wiring()

	_restore_file()
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _backup_file() -> void:
	_had_save = FileAccess.file_exists(SaveData.SAVE_PATH)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SaveData.SAVE_PATH)
	print("  备份现有存档：%s（%d 字节）" % ["有" if _had_save else "无", _saved_bytes.size()])


func _restore_file() -> void:
	print("")
	print("=== 还原存档 ===")
	if _had_save:
		var f := FileAccess.open(SaveData.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.SAVE_PATH))
	# 贴回文件之后还得让**内存里**的状态也回到盘上那份，否则这个测试进程留下的
	# 内存状态和文件不一致，谁在这个进程后面接着读存档谁就中招。
	SaveData.persist = true
	SaveData.load_data()
	print("  已还原，金币 %d" % SaveData.total_coins)


## 纯算术：里程 → 第几个成就。第 1 个成就是 500 米，不是 0 米。
func _math() -> void:
	print("=== 1. 里程碑换算 ===")
	_check("需求要的间隔是 500 米", Achievements.STEP_METERS, 500)
	_check("需求要的奖励是 500", Achievements.REWARD, 500)
	_check("0 米一个都没有", Achievements.index_at(0.0), 0)
	_check("499 米一个都没有", Achievements.index_at(499.0), 0)
	_check("整整 500 米拿到第 1 个", Achievements.index_at(500.0), 1)
	_check("501 米还是第 1 个", Achievements.index_at(501.0), 1)
	_check("999 米还是第 1 个", Achievements.index_at(999.0), 1)
	_check("1000 米是第 2 个", Achievements.index_at(1000.0), 2)
	_check("5000 米是第 10 个", Achievements.index_at(5000.0), 10)
	# 负数不该倒扣出负成就来（车速倒着开、或者里程还没起算的时候会传进来）
	_check("负里程当成 0 个", Achievements.index_at(-100.0), 0)
	_check("第 3 个成就对应 1500 米", Achievements.meters_of(3), 1500)
	_check("3 个成就发 1500 块", Achievements.reward_for(3), 1500)
	_check("0 个成就发 0 块", Achievements.reward_for(0), 0)
	_check("负数不发钱", Achievements.reward_for(-2), 0)


## 结算语义：过了才发、只发一次、发多少。
func _claim_semantics() -> void:
	print("=== 2. 结算：过了才发、只发一次 ===")
	SaveData.persist = false      # 这一节全靠内存，别去碰盘上的真存档
	SaveData.reset_progress()
	_check("新档 0 个成就", SaveData.achieved_of(Maps.PLAINS), 0)
	_check("499 米：没有可领的", SaveData.claim_achievements(499, Maps.PLAINS), 0)
	_check("499 米之后金币没动", SaveData.total_coins, 0)
	_check("正好 500 米：领到 1 个", SaveData.claim_achievements(500, Maps.PLAINS), 1)
	_check("金币 +500", SaveData.total_coins, Achievements.REWARD)
	_check("已领数变成 1", SaveData.achieved_of(Maps.PLAINS), 1)
	# 这一条就是「不能刷」：同一局里查第二次、或者下一局重新跑到 500 米，
	# 都不该再发。
	_check("同样 500 米再查：不发第二个", SaveData.claim_achievements(500, Maps.PLAINS), 0)
	_check("600 米也还是不发", SaveData.claim_achievements(600, Maps.PLAINS), 0)
	_check("金币还是 500", SaveData.total_coins, Achievements.REWARD)
	_check("跑到 1000 米：领到第 2 个", SaveData.claim_achievements(1000, Maps.PLAINS), 1)
	_check("金币 1000", SaveData.total_coins, Achievements.REWARD * 2)
	# 里程**倒退**（倒车开回起点、或者重开一局从头开）不该退成就、更不该补发
	_check("里程倒退不发也不退", SaveData.claim_achievements(200, Maps.PLAINS), 0)
	_check("已领数没退回去", SaveData.achieved_of(Maps.PLAINS), 2)


## 四张图各算各的。
func _per_map() -> void:
	print("=== 3. 按图分开 ===")
	_check("雪地还没拿过", SaveData.achieved_of(Maps.SNOW), 0)
	_check("雪地 500 米：领到 1 个", SaveData.claim_achievements(500, Maps.SNOW), 1)
	_check("雪地有 1 个了", SaveData.achieved_of(Maps.SNOW), 1)
	_check("平原的个数没被雪地顶掉", SaveData.achieved_of(Maps.PLAINS), 2)
	_check("回头再查平原的 500 米还是不发", SaveData.claim_achievements(500, Maps.PLAINS), 0)
	_check("荒漠仍是 0", SaveData.achieved_of(Maps.DESERT), 0)
	_check("火山仍是 0", SaveData.achieved_of(Maps.VOLCANO), 0)


## 一次跨过好几个：全都要发。
func _multi_step() -> void:
	print("=== 4. 一步跨过好几个 ===")
	var before: int = SaveData.total_coins
	var got: int = SaveData.claim_achievements(5000, Maps.DESERT)
	# 5000 米 = 第 10 个，此前 0 个 → 一次补 10 个
	_check("一口气领到 10 个", got, 10)
	_check("已领数 = 10", SaveData.achieved_of(Maps.DESERT), 10)
	_check("金币 +5000", SaveData.total_coins - before, Achievements.reward_for(10))
	# 再往前一步跨两个（第 11、12 个），确认是**接着**补而不是重头补
	_check("再过一步补 2 个", SaveData.claim_achievements(6000, Maps.DESERT), 2)
	_check("已领数 = 12", SaveData.achieved_of(Maps.DESERT), 12)
	_check("金币累计对得上", SaveData.total_coins - before, Achievements.reward_for(12))


## 落盘：写下去 → 清内存 → 读回来。
func _persist() -> void:
	print("=== 5. 成就落盘 ===")
	SaveData.persist = true
	SaveData.reset_progress()
	SaveData.claim_achievements(1500, Maps.SNOW)
	var coins: int = SaveData.total_coins
	_check("雪地 1500 米领到 3 个", SaveData.achieved_of(Maps.SNOW), 3)

	# 清内存。**必须先关落盘**：reset_progress() 自己会写盘，会把刚写的数据冲掉。
	SaveData.persist = false
	SaveData.reset_progress()
	SaveData.persist = true
	SaveData.load_data()

	_check("读回来还是 3 个", SaveData.achieved_of(Maps.SNOW), 3)
	_check("别张图仍是 0", SaveData.achieved_of(Maps.PLAINS), 0)
	_check("金币也读回来了", SaveData.total_coins, coins)
	# 读回来之后不能**再发一次**：成就已经在盘上了，重开一局跑到 1500 米
	# 只该拿没有过的那些。
	_check("读回来之后再查 1500 米：不发", SaveData.claim_achievements(1500, Maps.SNOW), 0)
	_check("跑到 2000 米才发第 4 个", SaveData.claim_achievements(2000, Maps.SNOW), 1)
	await get_tree().process_frame


## 关卡接线：里程一涨，金币、本局计数、飘字都要跟上。
func _game_wiring() -> void:
	print("=== 6. 关卡接线 ===")
	SaveData.persist = false
	SaveData.reset_progress()
	SaveData.selected_map = Maps.PLAINS
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	_check("开局本局成就数为 0", main.run_achievements, 0)
	_check("开局金币为 0", main.coins, 0)

	main._check_achievements(500)
	_check("跨过 500 米：本局 +500", main.coins, Achievements.REWARD)
	_check("本局计数 +1", main.run_achievements, 1)
	_check("存档金币也 +500（即时入账）", SaveData.total_coins, Achievements.REWARD)
	_check("飘字画出来了", main.hud._ach_flash > 0.0, true)
	_check("飘的是 500 米这个里程碑", main.hud._ach_meters, 500)

	# 再来一次同一段里程：本局计数和金币都不许再动
	main._check_achievements(500)
	_check("同一段里程不再发", main.coins, Achievements.REWARD)
	_check("本局计数没涨", main.run_achievements, 1)

	# 结束面板那条统计也要走一遍：`_draw_game_over()` 平时没人调，
	# 中英两份文案的 `%` 配错了要等玩家真的达成成就才在画面上炸出来。
	main._on_car_crashed(HillCar.REASON_CRASH)
	await get_tree().process_frame
	_check("结束面板画出成就那一行（没有脚本报错）", main.hud._run_achievements, 1)
	main.queue_free()
	await get_tree().process_frame
