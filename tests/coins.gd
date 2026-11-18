extends Node
## 金币面额（[constant PICKUP_SCRIPT.COIN_VALUES] /
## [constant PICKUP_SCRIPT.COIN_WEIGHTS] / [constant PICKUP_SCRIPT.COIN_WEIGHTS_FAR]）的验证。
##
## 分六组：
##
## A. **两张表本身** —— 四档的权重加起来正好 100、三个数组一样长。权重和不是 100
##    的话 [method Pickup._roll_coin_value] 会静默按「和」归一化，档位比例就悄悄
##    变了，而且从代码上看不出来。
## B. **近处的抽签结果对得上权重** —— 摆 4000 枚金币（同一个场景里实例化，不进树，
##    假位置），数每档出现了多少，和权重比对。**这是唯一能测到「概率写对了」的
##    办法** —— 只断言「抽出来的一定在四档里」的话，把权重写成 [1,1,1,1] 也能过。
## C. **越远越富** —— 用户要的规则是「里程越远出现大面值金币概率越高」。这一组
##    从两头夹：一头把 [method Pickup.weights_at] 沿着里程量一遍（端点必须精确等于
##    两张表、大面额占比必须只增不减），一头在**远处**再摆 4000 枚数一遍实际比例。
##    只测曲线不测抽签的话，「曲线对了但抽签没读它」会漏过去；只测抽签不测曲线的话，
##    只能拿两个孤立里程说话，中间的过渡是断的也看不出来。
## D. **同一局可复现** —— 面额只由位置决定，同一个位置抽两次必须是同一档
##    （存档/世界种子那套「同种子 = 同一局」靠这个成立）。
## E. **币面数字塞得下** —— 见下面 [method _case_fit] 的说明。这条是**画法**的
##    断言，headless 下 `_draw()` 根本不会被调用（没有渲染器），所以不能靠
##    「跑一遍看看有没有报错」，只能把字号和半径的关系算出来钉住。
## F. **场景里写死面额时不被抽签覆盖** —— 测试和特制关卡靠这个钉住金额。

const PICKUP := preload("res://scenes/pickup.tscn")
## 常量挂在脚本上。**pickup.gd 没有 `class_name`**，所以 `Pickup` 不是全局类型，
## 那些 `COIN_*` 只能从 preload 出来的这个脚本对象上读。
const PICKUP_SCRIPT := preload("res://scripts/pickup.gd")

## 抽签样本量。4000 枚下，最小的一档（5%）期望 200 枚，标准差约 14 ——
## 容差给 ±2 个百分点（80 枚）已经宽到不会偶发失败，又能抓住「权重写错」。
const SAMPLES := 4000
const TOL_PCT := 2.0

## 面额数字最多允许占掉可画区的多少。**不能放到 1.0** —— 100% 是「刚好贴着外圈」，
## 帧率、缩放、换个字体都会让它压出去。上限 0.88 是照实测配的
## （引擎默认字体下四档依次是 80% / 69% / 81% / 82%），卡在最小的那个余量上：
## 想把某档调大一号，这条会先响，而不是等到画面里数字压到圈上才发现。
const FILL_MAX := 0.88

## 近处 / 远处两批样本的 x 基准和间距（像素）。
##
## **靠 x 把样本圈在两头**，不是靠改常量：近处那一批要全部落在
## [constant PICKUP_SCRIPT.COIN_RICH_FROM]（400 米 = x 4200）之内，远处那一批要
## 全部落在 [constant PICKUP_SCRIPT.COIN_RICH_FULL]（2000 米 = x 20200）之外。
## 间距 0.5 px 是为了「同一列不能都用同一个 x」（种子就是 x），而 4000 枚铺开
## 只占 2000 px —— 整批都稳稳地在同一头，测出来的比例才对应得上单独一张表。
const NEAR_X0 := 1200.0
const FAR_X0 := 25000.0
const X_STEP := 0.5

var _failures := 0


func _ready() -> void:
	SaveData.persist = false
	_case_table()
	_case_weights()
	_case_rich()
	_case_stable()
	_case_fit()
	_case_override()
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _between(label: String, got: float, lo: float, hi: float) -> void:
	var ok := got >= lo and got <= hi
	if not ok:
		_failures += 1
	print("  %s %s = %.2f（期望 %.2f ~ %.2f）" % [
		"OK  " if ok else "FAIL", label, got, lo, hi,
	])


## 造一枚金币：**不进树**。面额只由 `position` 和常量决定，进了树反而要建区块、
## 挂物理体，白白慢几十倍。
func _coin(x: float, y := 0.0):
	var c = PICKUP.instantiate()
	c.position = Vector2(x, y)
	c._ready()      # 不进树就不会自动调 _ready()，手动叫一次
	return c


func _case_table() -> void:
	print("=== A. 面额表 ===")
	_check("档数和面额档数一样", PICKUP_SCRIPT.COIN_WEIGHTS.size(), PICKUP_SCRIPT.COIN_VALUES.size())
	_check("远处那张表的档数也一样",
			PICKUP_SCRIPT.COIN_WEIGHTS_FAR.size(), PICKUP_SCRIPT.COIN_VALUES.size())
	_check("画法档数也一样", PICKUP_SCRIPT.COIN_STYLE.size(), PICKUP_SCRIPT.COIN_VALUES.size())
	_check("四档面额", PICKUP_SCRIPT.COIN_VALUES.size(), 4)
	for pair in [["近处", PICKUP_SCRIPT.COIN_WEIGHTS], ["远处", PICKUP_SCRIPT.COIN_WEIGHTS_FAR]]:
		var total := 0.0
		for w in pair[1]:
			total += w
		_between("%s的权重之和（不是 100 的话下面全是按比例缩过的）" % pair[0], total, 100.0, 100.0)
	var pct := PackedStringArray()
	for i in PICKUP_SCRIPT.COIN_VALUES.size():
		pct.append("%d→%.0f/%.0f" % [PICKUP_SCRIPT.COIN_VALUES[i],
				PICKUP_SCRIPT.COIN_WEIGHTS[i], PICKUP_SCRIPT.COIN_WEIGHTS_FAR[i]])
	print("  %s（近处/远处）" % "  ".join(pct))
	print("  一枚的期望值：近处 %.1f 块，远处 %.1f 块" % [
		PICKUP_SCRIPT.mean_value_at(0.0), PICKUP_SCRIPT.mean_value_at(1.0e9)])


## 在某一头摆 [constant SAMPLES] 枚金币，数每档出现了多少，和给定那张表比对。
##
## [param x0] 由调用方给（见 [constant NEAR_X0] / [constant FAR_X0]），
## 这样近处和远处两批样本走的是同一段抽样代码，两边的容差也一样。
func _count_tiers(x0: float, want: Array, tag: String) -> void:
	var count := {}
	for v in PICKUP_SCRIPT.COIN_VALUES:
		count[v] = 0
	for i in SAMPLES:
		# 位置铺开：种子就是 x，同一列不能都用同一个 x
		var c = _coin(x0 + float(i) * X_STEP)
		count[c.coin_value] = int(count[c.coin_value]) + 1
		c.free()

	var seen := 0
	var mean := 0.0
	var line := PackedStringArray()
	for i in PICKUP_SCRIPT.COIN_VALUES.size():
		var v: int = PICKUP_SCRIPT.COIN_VALUES[i]
		var n: int = count[v]
		seen += n
		mean += float(v) * float(n)
		var got := 100.0 * float(n) / float(SAMPLES)
		var expect := float(want[i])
		line.append("%d：%d 枚 = %.2f%%（表上 %.0f%%）" % [v, n, got, expect])
		_between("%s %d 的占比" % [tag, v], got, expect - TOL_PCT, expect + TOL_PCT)
	print("  " + "   ".join(line))
	_check("%s 每一枚都落在四档里（没有漏抽的）" % tag, seen, SAMPLES)
	print("  %s 实测一枚平均 %.1f 块" % [tag, mean / float(SAMPLES)])


func _case_weights() -> void:
	print("=== B. 近处的抽签比例 ===")
	_count_tiers(NEAR_X0, PICKUP_SCRIPT.COIN_WEIGHTS, "近处")


## 用户要的规则：「里程越远出现大面值金币概率越高」。
##
## 分三段测，缺一段都留着漏洞：
##
##  · **端点精确** —— 起点和终点必须**逐位等于**那两张表，不是「差不多」。允许
##    端点上有插值误差的话，把曲线整体平移一下（比如起点写成 500 米）也照样过。
##  · **单调** —— 沿着里程量一遍，大面额（≥100）的占比只许涨不许跌。这是这条规则
##    本身，比任何具体数字都重要；写成 [20,30,30,20] 还是 [30,40,20,10] 是手感，
##    但「越远越小」一定是写错了。
##  · **两个孤立里程上的实测比例** —— 见 [method _count_tiers] 的说明：曲线对了
##    不等于抽签读了它。
func _case_rich() -> void:
	print("=== C. 越远越富 ===")
	_check("0 米就是近处那张表",
			PICKUP_SCRIPT.weights_at(0.0), PICKUP_SCRIPT.COIN_WEIGHTS)
	_check("起富里程上还是近处那张表（400 米之前一点没变）",
			PICKUP_SCRIPT.weights_at(PICKUP_SCRIPT.COIN_RICH_FROM),
			PICKUP_SCRIPT.COIN_WEIGHTS)
	_check("涨满里程上就是远处那张表",
			PICKUP_SCRIPT.weights_at(PICKUP_SCRIPT.COIN_RICH_FULL),
			PICKUP_SCRIPT.COIN_WEIGHTS_FAR)
	_check("再远也不会比远处那张表更富（没有外推）",
			PICKUP_SCRIPT.weights_at(1.0e9), PICKUP_SCRIPT.COIN_WEIGHTS_FAR)

	var prev := -1.0
	var ladder := PackedStringArray()
	var drops := 0
	for m in [0.0, 100.0, 400.0, 600.0, 800.0, 1000.0, 1200.0, 1500.0, 1800.0,
			2000.0, 2600.0, 4000.0]:
		var w := PICKUP_SCRIPT.weights_at(m)
		# 大面额 = 100 和 500 那两档（下标 2、3，和 COIN_VALUES 一一对应）
		var share := float(w[2]) + float(w[3])
		ladder.append("%.0fm %.0f%%" % [m, share])
		if share < prev - 1.0e-6:
			drops += 1
		prev = share
	print("  大面额（100/500）占比：%s" % "  ".join(ladder))
	_check("沿里程只涨不跌（跌了几次）", drops, 0)
	_between("100 米处的期望值（起富之前，应当还是 62.5）",
			PICKUP_SCRIPT.mean_value_at(100.0), 62.4, 62.6)
	_between("2 公里处的期望值（涨满，应当就是 150）",
			PICKUP_SCRIPT.mean_value_at(2000.0), 149.9, 150.1)
	var near_mean := PICKUP_SCRIPT.mean_value_at(0.0)
	var far_mean := PICKUP_SCRIPT.mean_value_at(4000.0)
	_between("远处一枚是近处的几倍", far_mean / near_mean, 2.0, 3.0)

	_count_tiers(FAR_X0, PICKUP_SCRIPT.COIN_WEIGHTS_FAR, "远处")


## 面额只由位置决定 —— 世界种子那套「同种子 = 同一局」要求这个。
func _case_stable() -> void:
	print("=== D. 同位置必得同档 ===")
	var mismatch := 0
	for i in 200:
		var x := float(i) * 13.0 + 1.0
		var a = _coin(x)
		var b = _coin(x)
		if a.coin_value != b.coin_value:
			mismatch += 1
		a.free()
		b.free()
	_check("200 个位置各抽两遍，档位不同的次数", mismatch, 0)


## 币面上的数字必须**装得进内盘**，不然三位数（500）会压到外圈甚至漏出去。
##
## headless 下没有渲染器，`_draw()` 根本不会被调用 —— 所以「跑一遍没报错」
## 在这里等于什么都没测。改成把 `_font` 请出来，用真字体量一遍字串，
## 和 [constant PICKUP_SCRIPT.COIN_STYLE] 里的半径比大小。
func _case_fit() -> void:
	print("=== E. 面额数字装得进币面 ===")
	var probe = _coin(11.0)
	_check("拿到字体了（拿不到的话币面上什么都不会画）", probe._font != null, true)
	if probe._font == null:
		probe.free()
		return

	# 从 0 起算，不是 1 —— 初值给 1 的话下面那行「最大填充率」永远打 100%，
	# 看着像已经贴边了，其实四档里最挤的才 82%。
	var worst := 0.0
	for i in PICKUP_SCRIPT.COIN_VALUES.size():
		var style: Dictionary = PICKUP_SCRIPT.COIN_STYLE[i]
		var r: float = style["r"]
		var size: int = style["size"]
		var text := str(PICKUP_SCRIPT.COIN_VALUES[i])
		var extent: Vector2 = probe._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		# 内盘半径 = r − 4（和 _draw_coin 里一致），留 1 px 余量
		var room := 2.0 * (r - 4.0) - 2.0
		var fill := maxf(extent.x, extent.y) / room
		worst = maxf(worst, fill)
		print("  %-3d 半径 %.0f 字号 %d：字串 %.1f×%.1f，可画区 %.1f —— 占 %.0f%%" % [
			PICKUP_SCRIPT.COIN_VALUES[i], r, size, extent.x, extent.y, room, fill * 100.0,
		])
		_between("%d 的填充率" % PICKUP_SCRIPT.COIN_VALUES[i], fill, 0.0, FILL_MAX)
	print("  （最大填充率 %.0f%%，换字体之后跑一下这条，超 100%% 就是数字压到外圈了）"
			% (worst * 100.0))
	probe.free()


## 场景里写死面额时不能被抽签覆盖（测试和特制关卡靠这个钉住金额）。
func _case_override() -> void:
	print("=== F. 写死的面额 ===")
	for v in [7, 25, 100, 500, 9999]:
		var c = _coin(3.0)
		c.coin_value = v
		c._roll_coin_value()
		var tier := 0
		for i in PICKUP_SCRIPT.COIN_VALUES.size():
			if PICKUP_SCRIPT.COIN_VALUES[i] == v:
				tier = i
		_check("写死 %d：值原样保留" % v, c.coin_value, v)
		_between("写死 %d：档位落在表内" % v, float(c._tier), 0.0,
				float(PICKUP_SCRIPT.COIN_VALUES.size() - 1))
		if tier > 0:
			_check("写死 %d：档位就是它的下标" % v, c._tier, tier)
		c.free()
