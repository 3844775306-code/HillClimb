extends Node
## 「油箱供给随里程变稀」的验证。
##
## 需求是两句话：**越远油桶越少**，但**每桶补多少全图统一 50**。
## 前者衰减的是刷出来的概率（[method HillTerrain.fuel_chance]），不是桶里的量。
##
## 三节：
##
## A. 概率曲线本身 —— 纯函数，没有随机性，所以断言可以写得很死。
## B. 单桶的量 —— 在很近和很远的地方各捞一堆真油桶，逐个查是不是 50。
## C. **接线** —— 概率算了不等于有人用。这一节用一个把 fuel_chance 钉死成
##    0 或 1 的替身地形：钉成 0 就该一个油桶都不出，钉成 1 就该每个区块都出。
##    （本来想直接数「近处比远处多多少」，但这条曲线只降 2 倍、40 个区块就到底了，
##    两个样本的差距还不到 1 个标准差 —— 那种测试是掷骰子，不是测试。）

const PICKUP := preload("res://scenes/pickup.tscn")

## 把 [method HillTerrain.fuel_chance] 钉死的替身。
class ForcedTerrain extends HillTerrain:
	var force := -1.0
	func fuel_chance(_x: float) -> float:
		return force

const SWEEP_FIRST := 2
const SWEEP_LAST := 25   ## 24 个区块，够看出「全出」和「全不出」

var _failures := 0
## 断言计数。某节里冒出一个脚本错误时，协程会当场断掉，后面几句 _check 就静悄悄
## 不执行了 —— 最后照样打印「全部通过」。把条数报出来，掉了几条一眼能看见。
var _assertions := 0


func _ready() -> void:
	print("=== A. 补给概率曲线 ===")
	_curve()
	print("")
	print("=== B. 单桶补给量 ===")
	await _amount()
	print("")
	print("=== C. 接线：地形真的按这个概率刷油 ===")
	await _wiring()

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


# ------------------------------------------------------------ A. 曲线

## 到达下限的里程：(0.40 - 0.20) / 0.00006 ≈ 3333 m。
func _floor_meters() -> float:
	return (HillTerrain.FUEL_CHANCE_BASE - HillTerrain.FUEL_CHANCE_FLOOR) \
			/ HillTerrain.FUEL_CHANCE_PER_METER


func _curve() -> void:
	var t := HillTerrain.new()
	add_child(t)

	var start_x := Maps.START_OFFSET
	print("  起点 %.0f m 处 %.3f；%.0f m 处 %.3f；下限 %.3f 出现在 %.0f m" % [
		Maps.meters_at(start_x), t.fuel_chance(start_x),
		_floor_meters(), t.fuel_chance(start_x + _floor_meters() * Maps.PIXELS_PER_METER),
		HillTerrain.FUEL_CHANCE_FLOOR, _floor_meters(),
	])

	_approx("起点（0 m）就是基准概率", t.fuel_chance(start_x), HillTerrain.FUEL_CHANCE_BASE, 1e-6)
	# 出生点之前（x < START_OFFSET）里程按 0 算，不能出现「负数里程反而更高」
	_approx("出生点之前不高于基准", t.fuel_chance(0.0), HillTerrain.FUEL_CHANCE_BASE, 1e-6)
	_approx("1000 m 处", t.fuel_chance(start_x + 1000.0 * Maps.PIXELS_PER_METER),
			HillTerrain.FUEL_CHANCE_BASE - 1000.0 * HillTerrain.FUEL_CHANCE_PER_METER, 1e-6)

	# 单调不增 + 上下界，一路扫到 20 km
	var prev := t.fuel_chance(0.0)
	var monotone := true
	var in_bounds := true
	var below_floor := 0
	var above_base := 0
	for i in range(1, 401):
		var x := float(i) * 1000.0
		var c := t.fuel_chance(x)
		if c > prev + 1e-9:
			monotone = false
		if c < HillTerrain.FUEL_CHANCE_FLOOR:
			below_floor += 1
		if c > HillTerrain.FUEL_CHANCE_BASE:
			above_base += 1
		prev = c
	_check("一路单调不增（0 → 400 km）", monotone, true)
	_check("从不低于下限", below_floor, 0)
	_check("从不高于基准", above_base, 0)

	# 「越远越稀」要真的是**稀**，不能是平的一条线
	_approx("下限处的概率", t.fuel_chance(start_x + _floor_meters() * Maps.PIXELS_PER_METER + 1.0),
			HillTerrain.FUEL_CHANCE_FLOOR, 1e-6)
	_approx("到底之后就一直是最低", t.fuel_chance(9.0e7), HillTerrain.FUEL_CHANCE_FLOOR, 1e-6)
	_check("下限确实比基准稀（否则需求没实现）",
			HillTerrain.FUEL_CHANCE_FLOOR < HillTerrain.FUEL_CHANCE_BASE, true)
	t.queue_free()


# ------------------------------------------------------------ B. 单桶的量

func _make_terrain(script_owner: HillTerrain = null) -> HillTerrain:
	var t: HillTerrain = script_owner if script_owner != null else HillTerrain.new()
	t.coin_scene = PICKUP
	t.fuel_scene = PICKUP
	add_child(t)
	return t


## 扫过一段区块，收集沿途刷出来的油桶**单桶补给量**。
##
## 返回的是数值不是节点引用：区块一滚出视野就被 queue_free 了，油桶是它的孩子，
## 跟着一起消失。攒一堆引用回来再读，读到的全是「previously freed」。
func _sweep(t: HillTerrain, first: int, last: int) -> Array:
	var dummy := Node2D.new()
	add_child(dummy)
	var amounts := []
	for i in range(first, last + 1):
		dummy.global_position = Vector2(
			float(i) * HillTerrain.CHUNK_WIDTH + HillTerrain.CHUNK_WIDTH * 0.5, 0.0)
		t.set_target(dummy)
		await get_tree().process_frame
		var chunk: Node = t.get_node_or_null("Chunk%d" % i)
		if chunk == null:
			continue
		for child in chunk.get_children():
			if child.get("kind") == "fuel":
				amounts.append(child.fuel_amount)   # 趁活着读出来
	dummy.queue_free()
	return amounts


func _amount() -> void:
	var t := _make_terrain()
	# 近处：区块 2 起，概率接近基准；远处：区块 400 起，已经到底
	var near := await _sweep(t, 2, 30)
	var far := await _sweep(t, 400, 440)
	print("  近处（区块 2-30，约 %.0f-%.0f m）刷出 %d 桶" % [
		Maps.meters_at(2.0 * HillTerrain.CHUNK_WIDTH),
		Maps.meters_at(30.0 * HillTerrain.CHUNK_WIDTH), near.size(),
	])
	print("  远处（区块 400-440，约 %.0f m 起）刷出 %d 桶" % [
		Maps.meters_at(400.0 * HillTerrain.CHUNK_WIDTH), far.size(),
	])
	_check("近处有油桶（否则下面两条是空跑）", near.size() > 0, true)
	_check("远处也有油桶（下限保证了这一点）", far.size() > 0, true)

	var bad_near := 0
	var bad_far := 0
	for amount in near:
		if not is_equal_approx(amount, 50.0):
			bad_near += 1
	for amount in far:
		if not is_equal_approx(amount, 50.0):
			bad_far += 1
	_check("近处每桶都是 50", bad_near, 0)
	_check("远处每桶也是 50（量不随距离变，只有频率变）", bad_far, 0)
	_check("两个取样点的概率确实不同（否则这条断言在比较两个一样的东西）",
			t.fuel_chance(30.0 * HillTerrain.CHUNK_WIDTH)
				< t.fuel_chance(2.0 * HillTerrain.CHUNK_WIDTH), true)
	t.queue_free()


# ------------------------------------------------------------ C. 接线

func _wiring() -> void:
	var never := _make_terrain(ForcedTerrain.new())
	(never as ForcedTerrain).force = 0.0
	var none := await _sweep(never, SWEEP_FIRST, SWEEP_LAST)
	_check("概率钉成 0 → 一个油桶都不出（说明地形真的读了它）", none.size(), 0)
	never.queue_free()

	var always := _make_terrain(ForcedTerrain.new())
	(always as ForcedTerrain).force = 1.0
	var all := await _sweep(always, SWEEP_FIRST, SWEEP_LAST)
	_check("概率钉成 1 → 每个区块都出（且每块恰好一桶）",
			all.size(), SWEEP_LAST - SWEEP_FIRST + 1)
	always.queue_free()

	# 钉死成 0 时金币还得照刷 —— 别把「没油」写成「没道具」
	var t := _make_terrain(ForcedTerrain.new())
	(t as ForcedTerrain).force = 0.0
	var dummy := Node2D.new()
	add_child(dummy)
	dummy.global_position = Vector2(10.0 * HillTerrain.CHUNK_WIDTH, 0.0)
	t.set_target(dummy)
	await get_tree().process_frame
	var coins := 0
	for i in range(SWEEP_FIRST, SWEEP_LAST):
		var chunk: Node = t.get_node_or_null("Chunk%d" % i)
		if chunk == null:
			continue
		for child in chunk.get_children():
			if child.get("kind") == "coin":
				coins += 1
	_check("油桶归零时金币照旧（两者是独立的）", coins > 0, true)
	dummy.queue_free()
	t.queue_free()
