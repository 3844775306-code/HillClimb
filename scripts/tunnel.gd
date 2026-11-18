extends HillFeature
## 隧道：从第 [constant Maps.TUNNEL_START_CHUNK] 块区块起**一路都在洞里**。
## 一块区块挨着一块区块盖满石头拱，中间不断（出生点那一段不盖 —— 开局就被压在
## 石头底下的话，玩家连「先开一段」都没有）。
## 地形那边不动（不挖坑、也不垫平，[constant Maps.FEATURE_TUNNEL] 里没有 `level`）。
## **司机碰到洞顶就是死**（[constant HillCar.REASON_CEILING]）。
##
## ## 洞顶是「另一个刚体」
##
## 地表是一条**单值折线**（[method HillTerrain.height_at] 一个 x 只给一个高度），
## 画不出「上面是石头、中间是空的、下面又是石头」。所以洞顶只能另摆一个刚体 ——
## 吊桥的桥面、冰湖的冰板都是同一个路子。
##
## ## 石头自己就是死亡区
##
## 早先的写法是「石拱 + 一条全透明的矩形死区」，因为把拱放进 `"ground"` 组会被
## 判成「翻车」（[method HillCar._on_head_body_entered] 只认那个组）。但洞顶是起伏的、
## 还带着石尖，一条矩形盖不住，于是换成更直接的做法：拱自己进
## [constant HillCar.CEILING_GROUP] 组，头碰到它判 [constant HillCar.REASON_CEILING]。
## 谁碰到石头谁死，形状怎么变都不用跟着改。
##
## ## 洞顶跟着**当地的真实地表**走
##
## 洞顶下沿 = `ground_at(x) − (车高 + 余量)`，所以山丘上的洞跟着拱起来、洼地里的洞
## 跟着压下去 —— 是「顺着山地挖的一条洞」，不是「一条水平的管子插在山里」。
##
## 余量（[constant HEAD_GAP_MIN]～[constant HEAD_GAP_MAX]）是**相对车顶**算的，
## 不是相对地面的：`HEAD_GAP_MIN` 60 的意思是「平地上正常开过去，车顶离石头
## 还剩 60 像素」。**这两个数是拿实测顶上去调的**，见 [constant HEAD_GAP_MIN]。
##
## **是 `ground_at(x)`，不是 `rim_y`。** `rim_y` 是**本块区块左沿**的高度，相邻两块
## 区块的 `rim_y` 差着一整段起伏，照着它画洞顶的话每 800 像素就错开一道台阶 ——
## 而用户要的正是「上壁的分布是连续的」。
##
## ## 「连续」= 相邻两块区块在共用的那条边界上算得一模一样
##
## 区块是一块一块建的（镜头滚过去才建），所以连续性只能靠**每一块自己算对**。
## 三条保证：
##
## 1. 洞顶的每个数都是**世界坐标的纯函数**（[method _ceiling_at] /
##    [method _thickness_at] / [method _bottom_at]），跟「这是哪一块、这一块的左沿
##    在哪」无关，于是两边在 `x = 边界` 上求值必然相等。
## 2. 拱盖满整块：`left`/`right` 就是区块的两端（[constant Maps.FEATURE_TUNNEL] 的
##    `inset` 0、`width` = 一个区块宽），不留「路在头上却露着天」的那一截。
##    两端接口那两条竖边两边完全重合，所以连起来是一条不断开的石头带。
## 3. **钟乳石摆在一条全局点阵上**（[method _spike_at_slot]）：第 k 根的横坐标只由
##    `k` 决定，不按区块边缘摆。骑在边界上的那一根，两块区块算出来是同一根针、
##    同一个长度、同一个尖。早先「每块自己撒一排」的写法会把一根针在边界上劈成
##    两半（一半长一半短）。
##
## 拱背厚度同理：早先用的是 `sin(PI × 段内比例)`，单个区块看是个漂亮的拱，连成
## 一整条隧道却会在每个边界**掐成 0 厚度**。现在是一条世界坐标的噪声曲线
## （[method _thickness_at]）。厚度**有多厚**则是另一件事：用户要的是
## 「上壁填满屏幕上半部分」，那个数是从镜头高度推出来的，见 [constant ROOF_MIN]。
##
## ## 洞顶离地面多远是**随机波动**的
##
## 整条洞顶一样高的话，车在里面开着永远碰不到，洞顶就只是个装饰。现在是一条平滑的
## 噪声曲线，车顶到洞顶的余量在 [constant HEAD_GAP_MIN]～[constant HEAD_GAP_MAX]
## 之间来回变。
##
## **最矮处也必须高于车高**，否则平地上正常开过去就会撞顶 —— 那是随机死亡，
## 不是难度。所以下限是 `车高 + HEAD_GAP_MIN`，不是一个随手定的数。
##
## 波动由 [FastNoiseLite] 直接从**世界坐标**算，种子写死，所以区块被回收重建之后
## 洞顶还是同一条曲线（用 `randf()` 的话，镜头滚一遍洞顶就换个形状）。
##
## ## 钟乳石
##
## 点阵上每隔 [constant SPIKE_PITCH] 像素有一个位置，按哈希空掉
## [constant SPIKE_SKIP] 那一部分，剩下的各长一根。长度上限
## [constant SPIKE_LEN_MAX]，但**还要按当地的余量再压一道**：石尖离车顶必须留够
## [constant SPIKE_SAFE]，压不到 [constant SPIKE_LEN_MIN] 就干脆不长。
## 于是洞顶高的地方钟乳石能长到 76 像素、洞顶矮的地方不长 ——
## 「平地上正常开过去碰不到」这条是**算出来的**，不是摆的时候东躲西躲躲出来的。
##
## 石尖是**洞顶轮廓的一部分**：碰撞体那一圈多边形在石尖处往下凸出一个三角，
## 所以碰石尖和碰洞顶走的是同一条判死路径、同一个死因、同一句话。


## 越野车的高度（像素）。scenes/car.tscn 实测：车轮底 +39 到车手头顶 −77。
##
## **洞顶的上下限和钟乳石的长度上限全从这一个数推**，车改了高度这里跟着变。
## tests/features 会拿现量的车高回来对，对不上就红。
const CAR_HEIGHT := 116.0

## 平地上车顶到洞顶下沿的余量范围（像素）。洞顶在这两个数之间随机波动。
##
## 下限是**安全线**：再矮，正常开过去就会撞顶 —— 那是随机死亡，不是难度。
##
## 早先写的是 16 / 94，那是按「车摆在平地上笔直开过去」推算的。实测（tests/features
## 全油门开进洞里、跨 8 块区块）最紧的地方车顶离石尖只剩 **18.8 像素** —— 车会颠、
## 会被山丘抛起来，算出来的余量当场被吃掉一大半。用户看到的就是「正常开也会撞顶」。
##
## 于是整条洞顶上抬了两次：16 / 94 → 40 / 116 → **60 / 136**（本次）。
## 两次都是上下限一起抬，波动幅度一直是 76 —— **余量本身就是洞顶的形状**，
## 只抬下限的话这条噪声曲线会被削平，洞顶就成了一条几乎水平的管子。
## 实测最紧处：18.8 → 40.8 → **60 上下**（每次都是同一条断言量的）。
const HEAD_GAP_MIN := 60.0
const HEAD_GAP_MAX := 136.0

## 洞顶起伏的空间频率（1/像素）。0.0035 大约 285 像素一个来回：
## 一段 800 像素里看得出「忽高忽低」，又不会抖成锯齿。
const CEILING_FREQ := 0.0035
## 轮廓采样间隔（像素）。石尖的尖都落在网格点上（见 [method _spike_at_slot]），
## 所以这个数决定了石尖画出来有多准。区块宽是它的整数倍（800 = 160 × 5），
## 于是相邻两块区块的采样点也在同一条网格上，边界那一列两边都取得到。
const STEP := 5.0
## 起伏的噪声种子。写死的：洞顶的形状只由世界坐标决定。
const CEILING_SEED := 20240

## 拱背厚度（像素）：最薄到最厚。**也是一条世界坐标的噪声曲线**，
## 不是「段内正弦」—— 后者在每块区块的两端厚度为 0，全图连起来就是一段段断开的拱。
##
## ## 为什么这么厚（用户原话：「隧道上壁的厚度应该能够填充屏幕上半部分」）
##
## 推导出来的，不是随手定的。三个现成的数：
##
##   · 镜头挂在车身中心**上方 [constant HillGame.CAMERA_LIFT] = 90** 像素处；
##   · 车手头顶在车身中心**上方 77** 像素处（`scenes/car.tscn` 现量的，
##     [constant CAR_HEIGHT] 116 = 轮底 39 + 头顶 77）；
##   · 头碰到洞顶就是死，所以**车身最高只到「洞顶下沿 + 77」**。
##
## 于是镜头最高只到 `洞顶下沿 + 77 − 90 = 洞顶下沿 − 13`，也就是
## **洞顶最多比屏幕正中（= 镜头所在的那条线）高 13 像素**。石头要盖住屏幕上半，
## 就得从洞顶下沿往上盖：
##
##     厚度 ≥ 13 + (画布高 / 2) / ZOOM_FAR
##
## 用**最远**的那一档缩放（[constant HillGame.ZOOM_FAR] = 0.62，车开最快的时候
## 看得最广、也就最需要厚），画布高按 `stretch/aspect = expand` 能出到的最大值算：
##
##     16:9 手机  720 → 13 + 580.6 = 593.6
##     3:2  手机  853 → 13 + 688.0 = 701.0
##     4:3  平板  960 → 13 + 774.2 = 787.2   ← 最紧的一档
##
## 取 820 / 920：最薄处也比 4:3 平板要求的多 33 像素。
## `tests/features` 的隧道一节拿**现量的车高**和 [constant HillGame.ZOOM_FAR]
## 把这条重算一遍，常量被改小了会红。
##
## **为什么不按运行时的视口现算**：厚度必须是 `x` 的纯函数（见文件头「连续」那节），
## 而视口尺寸在运行中会变 —— 拉伸一次窗口，边界两边的区块就按两个厚度盖，
## 正好在接缝处留一道台阶。用常量 + 一条「覆盖得住最矮支持画布」的断言，
## 两个问题一起解决。
##
## 代价：拱背的上沿从此永远在屏幕外，「石头忽厚忽薄」这条噪声在画面上看不出来了。
## 留着它只是因为「厚度必须是 x 的纯函数」这条要求还在，而且屏幕更小时它还有用。
const ROOF_MIN := 820.0
const ROOF_CROWN := 920.0
const ROOF_FREQ := 0.0016
const ROOF_SEED := 41107

## 钟乳石点阵的间距（像素）。第 k 个位置落在 `[k × PITCH, (k+1) × PITCH)` 里。
##
## 比 [constant SPIKE_BASE_MAX] 宽得多，所以一根针最多只压到相邻那一格 ——
## [method _bottom_at] 只要看 `k0 − 1 … k0 + 1` 三格就够，不用扫全图。
const SPIKE_PITCH := 150.0
## 点阵空掉一格的概率。用户要的是「**每隔一段距离**有一些钟乳石」，
## 每格都长就成了均匀的梳子。
const SPIKE_SKIP := 0.4
## 钟乳石的长度范围。上限 76 是「洞顶最高时能挂多长」，实际还要按当地余量压一道。
const SPIKE_LEN_MIN := 20.0
const SPIKE_LEN_MAX := 76.0
## 石尖和车顶之间至少留多少像素。**这是钟乳石那条安全线的全部依据。**
##
## 和 [constant HEAD_GAP_MIN] 取同一个数：洞顶最矮也就矮到 HEAD_GAP_MIN，
## 「正常开过去碰不到」这条在石尖上也该是同一个数。
##
## 早先这里写的是 18 —— **比 HEAD_GAP_MIN 还小，于是整条隧道的实际余量是由石尖
## 定的，不是由洞顶定的**：实测（tests/features 全油门跨 8 块区块）车顶离石尖最近
## 18.8 像素；把洞顶从 16 抬到 40 之后，这个数**纹丝不动**（还是 18～20）——
## 因为石尖是按这一行往下长的，洞顶抬高多少它就长多少，尖永远停在离车顶 18 的地方。
##
## 代价是洞顶矮的地方不再长钟乳石（长度压不到 [constant SPIKE_LEN_MIN] 就不长）——
## 那正是「洞顶高的地方才挂得住钟乳石」的意思。
const SPIKE_SAFE := HEAD_GAP_MIN
## 钟乳石贴顶那一头的宽度范围。
const SPIKE_BASE_MIN := 20.0
const SPIKE_BASE_MAX := 30.0

const STONE_COLOR := Color(0.36, 0.35, 0.34)
const SEAM_COLOR := Color(0.24, 0.23, 0.22)
## 拱底那一层暗色：洞里面比外面暗。不加这一层，石头看着像浮在半空。
const UNDER_COLOR := Color(0.20, 0.19, 0.19)
## 洞底那层暗色的粗细。
const UNDER_WIDTH := 9.0

var _noise := FastNoiseLite.new()
## 拱背厚度用第二条噪声：和起伏的频率差着三倍多，两条不会同步，
## 于是「洞顶忽高忽低」和「石头忽厚忽薄」看着是两回事。
var _roof_noise := FastNoiseLite.new()


func _build() -> void:
	# 盖满整块：不留 [constant MOUTH] 那种内缩，一块区块就是一段隧道。
	# 端点和区块边界重合（见文件头第 2 条），相邻两块在边界上完全重合。
	var left := span.position.x
	var right := span.position.x + span.size.x
	if right - left <= STEP:
		return

	_configure_noise()
	# **只算一遍下沿**：碰撞体、暗色带、砌缝都读这一份。
	# 早先是各算各的，而现在每个采样点都要问一次 `ground_at`（地形噪声）
	# 加三格石尖的哈希，一算三遍纯属白烧。
	var bottom := _bottom_profile(left, right)
	var arch := _arch_points(bottom)

	# 实体拱。层 2 = 地面（车壳和轮子的掩码都是 3，撞得到），掩码 0 谁都看不见。
	# **进 CEILING_GROUP 组**：车手的头碰到它就判「撞到洞顶」，见文件头。
	var body := StaticBody2D.new()
	body.name = "Arch"
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group(HillCar.CEILING_GROUP)
	var cs := CollisionPolygon2D.new()
	cs.name = "Shape"
	cs.polygon = arch
	# **是 BUILD_SOLIDS，带 S。** Godot 的 BuildMode 枚举复数是 `BUILD_SOLIDS`，
	# 写成单数的 `BUILD_SOLID` 是个**解析错误**（不是运行时错误），整个脚本加载不了 ——
	# 现象是隧道图整段功能消失，而且只在控制台留一行 "Failed to load script"。
	cs.build_mode = CollisionPolygon2D.BUILD_SOLIDS
	body.add_child(cs)
	add_child(body)

	var vis := Polygon2D.new()
	vis.name = "ArchVisual"
	vis.color = STONE_COLOR
	vis.polygon = arch
	add_child(vis)

	add_child(_underside(bottom))
	add_child(_seams(left, right))


## 车顶到洞顶下沿的余量（像素，去掉石尖）。`HEAD_GAP_MIN`～`HEAD_GAP_MAX` 之间。
##
## 洞顶的上下限全从它推：下限必须 > 0，否则平地上开过去就撞顶。
func _clearance_at(x: float) -> float:
	# get_noise_1d 的值域大约是 [−1, 1]，映射到 [HEAD_GAP_MIN, HEAD_GAP_MAX]。
	var t := clampf(0.5 + 0.5 * _noise.get_noise_1d(x), 0.0, 1.0)
	return lerpf(HEAD_GAP_MIN, HEAD_GAP_MAX, t)


## 洞顶下沿**去掉石尖**的那条平滑曲线（世界坐标 y）。
##
## 跟着**当地地表**走：山丘上拱起来，洼地里压下来。
func _ceiling_at(x: float) -> float:
	return ground_at(x) - (CAR_HEIGHT + _clearance_at(x))


## 洞顶下沿**含石尖**的 y。测试和砌缝都用它，别处不要自己再算一遍。
##
## 只看 `k0 − 1 … k0 + 1` 三格：点阵间距比一根针的半宽大得多，
## 再远的针够不到这个 x。
func _bottom_at(x: float) -> float:
	var y := _ceiling_at(x)
	var k0 := int(floor(x / SPIKE_PITCH))
	for k in range(k0 - 1, k0 + 2):
		var spike := _spike_at_slot(k)
		if spike.is_empty():
			continue
		var half := float(spike["half"])
		var d := absf(x - float(spike["x"]))
		if d < half:
			# 三角尖：贴着根是 0，正下方是满长。
			y += float(spike["len"]) * (1.0 - d / half)
	return y


## 拱背厚度（像素）。**`x` 的纯函数**：相邻区块在边界上取到同一个厚度，
## 拱才是连着的（见文件头）。
func _thickness_at(x: float) -> float:
	var t := clampf(0.5 + 0.5 * _roof_noise.get_noise_1d(x), 0.0, 1.0)
	return lerpf(ROOF_MIN, ROOF_CROWN, t)


## 点阵第 `k` 格上的那根钟乳石：`{x, half, len}`，空字典 = 这一格没有。
##
## **只由 `k` 决定**（位置、胖瘦、长度全是 `k` 的哈希），所以同一根针在任何一块
## 区块里算出来都一样 —— 这是「上壁连续」在钟乳石上的那一条。长度还要按当地的
## 车顶余量再压一道：石尖离车顶留够 [constant SPIKE_SAFE]，压不到
## [constant SPIKE_LEN_MIN] 就干脆不长。
func _spike_at_slot(k: int) -> Dictionary:
	if k < 0:
		return {}
	if Maps._hash01(k * 104729 + 5) < SPIKE_SKIP:
		return {}
	# 抖动限制在中段 [0.15, 0.85]：留出余量，免得相邻两格的针挤在一起。
	var jitter := 0.15 + 0.7 * Maps._hash01(k * 7919 + 11)
	# 石尖要**落在采样网格点上**：`_bottom_at` 只在采样点上取得到真正的尖，
	# 落在两个采样点之间的话画出来会比 `len` 短一截，而长度是卡着安全线算出来的
	# —— 短一截就意味着「安全线没管住画出来的东西」。网格是**世界坐标**的
	# （`x / STEP` 没有减去任何区块左沿），所以相邻区块用的是同一条网格。
	#
	# **`roundf` 不是 `round`。** `round()` 是能收 float 也能收 Vector2 的多态全局
	# 函数，返回类型是 Variant，所以 `var sx := round(...)` 推不出类型 ——
	# 那是个**解析错误**（整个 tunnel.gd 加载不了，隧道图整段消失，控制台只留一行
	# "Failed to load script"）。和上面 `BUILD_SOLIDS` 那个坑同一个性质：
	# 解析错误会让**整份脚本**失效，不是只坏这一行。
	var x := roundf((float(k) * SPIKE_PITCH + jitter * SPIKE_PITCH) / STEP) * STEP
	var half := lerpf(SPIKE_BASE_MIN, SPIKE_BASE_MAX,
			Maps._hash01(k * 2654435761 + 17)) * 0.5
	var want := lerpf(SPIKE_LEN_MIN, SPIKE_LEN_MAX, Maps._hash01(k * 40503 + 23))
	var room := _clearance_at(x) - SPIKE_SAFE
	if want > room:
		want = room
	if want < SPIKE_LEN_MIN:
		return {}
	return {"x": x, "half": half, "len": want}


## 洞顶的轮廓。下沿是一条**起伏的曲线**、中间有几处往下凸的三角石尖；拱背是同一批
## x 上再往上抬一截厚度的曲线。
##
## 顶点顺序：从左端沿下沿一路往右（含石尖），再从右端沿拱背回到左边。
## 最后收口的那条边落在左端的竖直面上。
func _arch_points(bottom: PackedVector2Array) -> PackedVector2Array:
	var top := PackedVector2Array()
	for i in bottom.size():
		var x := bottom[i].x
		top.append(Vector2(x, bottom[i].y - _thickness_at(x)))
	top.reverse()

	var pts := bottom.duplicate()
	pts.append_array(top)
	return pts


## 洞顶下沿的采样点（含石尖）。碰撞体、暗色带都从这一份算，
## 所以「看见的石头」和「碰得到的石头」永远是同一条曲线。
func _bottom_profile(left: float, right: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := int(ceil((right - left) / STEP))
	for i in range(n + 1):
		var x := left + float(i) * STEP
		pts.append(Vector2(x, _bottom_at(x)))
	# 最后一个采样点**正好压在右端上**：差一点点就在边界留一道台阶，
	# 而「拱盖满整块」「两边在边界上重合」这两条是照着端点量的。
	pts[pts.size() - 1] = Vector2(right, _bottom_at(right))
	return pts


## 洞顶下沿一条暗色带，让洞里看着比外面暗。**跟着下沿的形状走**，所以是一条
## 折线而不是一个矩形 —— 洞顶是起伏的，还有石尖，矩形盖不住。
func _underside(bottom: PackedVector2Array) -> Line2D:
	var line := Line2D.new()
	line.name = "Underside"
	line.width = UNDER_WIDTH
	line.default_color = UNDER_COLOR
	line.points = bottom
	return line


## 砌缝：拱背上几条竖线，看着像一块块石头垒的。落在石尖上的跳过 ——
## 石尖本来就是一根针，再画一条竖线看着像裂了。
func _seams(left: float, right: float) -> Node2D:
	var node := Node2D.new()
	node.name = "Seams"
	var count := 7
	for i in range(1, count):
		var u := float(i) / float(count)
		var x := lerpf(left, right, u)
		if _bottom_at(x) - _ceiling_at(x) > 1.0:
			continue
		var line := Line2D.new()
		line.name = "Seam%d" % i
		line.width = 2.0
		line.default_color = SEAM_COLOR
		line.points = PackedVector2Array([
			Vector2(x, _bottom_at(x) + 2.0),
			Vector2(x, _ceiling_at(x) - _thickness_at(x)),
		])
		node.add_child(line)
	return node


func _configure_noise() -> void:
	_noise.seed = CEILING_SEED
	_noise.frequency = CEILING_FREQ
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	# 两个八度：一层大起伏 + 一点点碎石头的感觉。再多就成锯齿了。
	_noise.fractal_octaves = 2
	_noise.fractal_gain = 0.4
	# 厚度那条更慢、更散：一块石头的厚薄不该跟着洞顶的起伏一起抖。
	_roof_noise.seed = ROOF_SEED
	_roof_noise.frequency = ROOF_FREQ
	_roof_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_roof_noise.fractal_octaves = 2
	_roof_noise.fractal_gain = 0.5
