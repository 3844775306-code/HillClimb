extends Node2D
class_name HillNight
## 黑夜图的挡布：全屏一层黑，**场上唯一的光是车头那两颗车灯**。
##
## ## 层级就是需求本身
##
## 用户要的是「**只能看见车灯照到的地方**」。所以：
##
##  · 挡布画在 [constant Maps.NIGHT_Z] = 2 层 —— **比地形（0）、车（1）和金币油桶
##    （也是 0）都高**，盖得住这些；车灯那一圈是透亮的，所以锥形里的地形、车和金币
##    自己看得见，走出那一圈就沉进黑里。
##  · **金币和油桶不许抬到挡布之上。** 原来这里抬过（z = 3），满屏黑里金币照样亮着，
##    连车灯够不着的地方也一清二楚 —— 用户报的就是这条，地图自己写的
##    「只看得到车灯那一圈」也就不成立了。现在它们和地形一样是 0。
##  · HUD 在 CanvasLayer 上，不受影响。
##
## ## 车灯：一颗光池 + 一条锥形
##
## 用户原话：「添加车灯，按空格或点击按钮后打开车灯，照亮前方锥形区域（模拟真实车灯
## 效果），但耗油速度是前进速度的 0.5 倍，未被车灯照到的地方亮度改为白天的 0.05」。
##
## 第一版照字面做了，另外还在车周围留了个「洞」（车自己永远看得见，和开不开灯无关）。
## 用户看过之后补了三条：「**只有车灯才有灯光，车周围还是暗的**，且需要把车灯画出来，
## 且车灯灯光长度有限」。于是那个洞**整个删掉了**，光只剩两个来源：
##
##  · **光池**（[method car_light]）—— 车壳被自己的灯照亮一点（用户从「完全黑掉」和
##    「被自己的灯照亮一点」里选了后者）：翻车、翘头的时候车壳得看得清姿态。
##    峰值只有 [constant CAR_PEAK] = 0.40，比锥形暗得多，撒出车外一点就没了。
##  · **锥形**（[method cone_light]）—— 从**车头**往前铺 [constant CONE_REACH] 像素，
##    也就是用户要的「灯光长度有限」；而且**光强随距离衰减**（用户后来补的一条：
##    「光线的强度随距离衰减」）—— 灯口那一小段满亮，之后一路上暗，到照程尽头正好 0。
##
## 灯关着的时候两个都是 0：全屏只剩 [constant UNLIT_LIGHT] = 0.05 那条地板，
## **连车自己都只剩 5% 的亮度** —— 车周围是暗的，这正是用户要的。
##
## 屏幕上的亮度于是是这几个来源里最亮的那个，黑度是它的补数（见 [method screen_alpha]）。
## 那条地板也是为什么「没被灯照到」不等于纯黑：远处还剩一层轮廓。
##
## 车灯开关在 [method HillCar.toggle_headlights]（按键 / 按钮两条路都走那一个入口），
## 开着时按 [constant HillCar.HEADLIGHT_DRAIN] 额外烧油。挡布这边只**读**
## [member HillCar.headlights_on] 和 [method HillCar.headlight_lamps]（灯的摆法），
## 不自己存状态 —— 两处各存一份迟早会对不上。
##
## ## 挡布不用着色器，用一圈扇形
##
## 亮度那圈是一圈**三角带**：半径方向分几段，每段四个顶点，每个顶点的透明度按
## [method screen_alpha] 算出来。项目里所有自绘界面（mapselect / hud / garage /
## dashboard）都是 draw_* 画的，这里跟着来 —— 也就没有着色器编译这一层风险
## （改一行着色器报错是整个场景黑屏，而 draw_* 报错最多是这块画歪）。
##
## ## 光池的芯要**整个装下**车
##
## 池芯（[constant CAR_CORE]）是满亮的那一圈：车翻过来、镜头拉远，车的最远一角也不能
## 探出池芯 —— 探出去的话那一角比车壳别处暗一截，车上多出一块斜的暗斑。
## 车长约 180 像素，底盘轴心到最远一角约 92。
##
## 第一版这里的红线是「洞心必须整个装下车」（那时洞心是全透明的），同一条红线，
## 只是量法从洞心换成了池芯。**这是一条红线：CAR_CORE 不许再往小调，除非先量过车。**
## 各车底盘轴心到最远一角的距离由 [code]tests/shapes.gd[/code] 现量（不写死数字，
## 换车、改车壳都会重新量），断言它小于 CAR_CORE。**不要为了「车周围更暗」把池芯压到
## 车角以下**：压下去不会报错，只会在黑夜里看到车的一角发灰 —— 而那种「像是渲染坏了」
## 的观感正是用户上一版抱怨的东西。

## 车壳被自己的灯照亮的那圈光池：**芯**（满亮）的半径。见类文档那条红线。
const CAR_CORE := 120.0
## 光池从满亮淡到 0 跨多远。芯装得下车就够了，这一圈是撒在车外地面上的散光 ——
## 压太窄像是车壳上贴了个圆盘，太宽则「车周围还是暗的」这条就不成立了。
const CAR_SOFT := 90.0
## 光池最亮处有多亮，也就是**车壳最亮处**（用户要的「微亮，看得清姿态」）。
##
## 取 0.40 是为了和锥形拉开档次：锥形心是 1.0（全亮），车壳只有它的四成 ——
## 一眼能看出「光照在路上，车上只是溅到一点」。调到 0.6 以上车壳就开始抢戏了。
const CAR_PEAK := 0.40
## 光池沿半径分几段插值。池子那 90 像素的渐晕只有几圈，多分纯属浪费四边形。
const CAR_RINGS := 4

## 挡布从车轴心往四个方向各铺多远。
##
## 要盖过镜头拉到最远时的整个可视范围：视口 1152 宽 ÷ 最小缩放 0.62 ≈ 1858 像素，
## 而镜头看向车前方 150 像素、还会滞后一点，所以车可以偏出屏幕中心两三百像素。
## 2600 的半径（直径 5200）对 1858 × 1160 的屏幕是压倒性的够。
const REACH := 2600.0
## 一圈分多少份。32 份是 11.25° 一片，锥形两侧那圈最外的半径是 290
## （[constant CAR_CORE] + [constant CAR_SOFT]），弦高误差 290 × (1 - cos 5.6°) ≈ 1.4
## 像素，在渐晕边缘看不出来。
const SECTORS := 32

## 没有车灯照到的地方剩多少亮度，= 白天的 0.05（用户原话）。
##
## 挡布于是从「纯黑」变成 α = 0.95 的黑。**别把它调成 0**：那正是用户报过的
## 「满屏黑」——现在远处至少还看得见天和地形的一层轮廓。
const UNLIT_LIGHT := 0.05
## 车灯锥的半角（度）。真实近光灯横向铺开 ±20°~25°，取 22° ——
## 再宽就不像灯、像天亮，再窄照不着路两边。
const CONE_HALF_DEG := 22.0
## 锥形两侧从全亮淡到全灭所跨的角度（度）。**不淡的话灯边是一条硬直线**，
## 真实车灯的边缘是糊的（灯碗和灯罩都不是理想的点光源）。
const CONE_SOFT_DEG := 9.0
## 车灯照多远。10 像素 = 1 米（[constant Maps.PIXELS_PER_METER]），所以是 82 米 ——
## 比真车灯远，但这是游戏：镜头拉到最远时可视宽度约 1858 像素，照 820 像素正好是
## 「看得见前面那个坡」，照满全屏就等于没有黑夜了。用户要求的「灯光长度有限」就是它。
## 这是**硬照程**：[method cone_light] 到这儿正好是 0，再往外只剩
## [constant UNLIT_LIGHT] 那条地板。不是「亮到 820 忽然没了」——见 [constant CONE_NEAR]。
const CONE_REACH := 820.0
## 锥形从灯口往前这一段满亮，之后**随距离一路淡到照程尽头（[constant CONE_REACH]）为 0**。
##
## 用户要求「光线的强度随距离衰减」：真实车灯照在路面上亮度就是随距离掉的 ——
## 点光源照度按 1/r² 掉，灯碗又把同一份光摊到越来越宽的一条带上。所以锥形不能是
## 一条平顶亮带：上一版「前三分之二满亮、最后一截才糊」看着像贴在路上一张亮纸，
## 而且「随距离衰减」这条根本无从量起（平顶带上前 547 像素的导数都是 0）。
##
## 取 120 是留一段满亮的近场：那儿正好接上 [constant CAR_CORE] 那圈光池的外沿，
## 两处亮度不断层。再往远的衰减率由 [constant CONE_REACH] 定（smoothstep：
## 半程剩下约 0.50，四分之三处约 0.16，尽头 0）。
const CONE_NEAR := 120.0
## 锥形沿距离分几段插值。光池那 [constant CAR_RINGS] 圈只管车周围，锥形那 820 像素里
## 一段都没有，不另分的话亮度在半径方向是线性插的。
##
## 整条锥形现在都在衰减（见 [constant CONE_NEAR]），比上一版那条平顶带更需要分细：
## 7 段是 117 像素一段，段内插成直线，对 smoothstep 的最大偏差约 2% 的 α ——
## 在 95% 的黑里看不出来；退回 5 段的话半程那段就会出现看得到的折角。
const CONE_RINGS := 7
## 锥形横向分几份。整圈那 [constant SECTORS] 份在 44° 里只放得下四份，
## 四条边会把车灯画成一个三角形；这里单独细分成 18 份（2.4° 一份）。
##
## 只补在锥形那一段，**不是把整圈加密**：整圈按这个精度要 150 份，
## 每帧多画四倍的四边形，而多出来的精度全花在没灯的那一圈上。
const CONE_SECTORS := 18

## 灯珠的半径 = 两颗灯的**间距** × 这个比例。
##
## 间距是车上量的（[method HillCar.headlight_lamps]），所以大巴的灯珠自然比摩托的大，
## 不用再开一个按车型调的旋钮。0.42 是量出来的：再大两颗灯就糊成一团，再小在
## 95% 的黑里只剩两个像素点。
const LAMP_RADIUS_RATIO := 0.42
## 灯珠外面那圈散光有多大（相对灯珠半径）。灯罩在夜里是一团糊光，不是一颗硬点。
const LAMP_GLOW := 2.6
## 灯光的颜色：暖白。真实卤素灯就这个色偏，也和白天的中性白拉开差别。
const LAMP_COLOR := Color(1.0, 0.96, 0.76)

const DARK := Color(0.0, 0.0, 0.0, 1.0)

var _target: Node2D


## 由 [method HillGame._ready] 调用。非黑夜图直接 `visible = false`：
## 挡布还在场上（节点没删），但**一个 `_draw` 都不会发生**，别的图逐像素不变。
func setup(car: Node2D, game_map_id: String) -> void:
	_target = car
	z_index = Maps.NIGHT_Z
	visible = Maps.is_night(game_map_id)


## 车自己的灯撒在**车壳**上的那圈光：`dist` 是离**车轴心**的距离，
## 返回值 0 ~ [constant CAR_PEAK]。
##
## 只跟距离有关，不分方向：这是「车壳被自己的灯照到一点」的近似 —— 近光灯本来也照不出
## 方向感，何况这是 2D 侧视，看成把车壳整体提亮一档就对了。
##
## [constant CAR_CORE] 以内满亮（**芯要整个装下车**，红线见类文档），往外
## [constant CAR_SOFT] 像素淡到 0，再外面交给 [constant UNLIT_LIGHT] 那条地板。
static func car_light(dist: float) -> float:
	return CAR_PEAK * _fade(dist, CAR_CORE, CAR_CORE + CAR_SOFT)


## 车灯照到 `offset` 这一点的亮度（0 = 照不到，1 = 正照在灯心）。
##
## `offset` 是**锥尖指向该点**的向量（不是绝对坐标），`heading` 是车头朝向的单位向量。
## 锥尖在车头那颗灯珠上（见 [method _draw]），不是车轴心。
##
## 衰减分两段，乘起来：
##
##  · 横向：和车头夹角超过 [constant CONE_HALF_DEG] 就完全照不到，再往外
##    [constant CONE_SOFT_DEG] 度之内从全亮淡到全灭（smoothstep）；
##  · 纵向：**随距离衰减**（用户原话「光线的强度随距离衰减」）——
##    [constant CONE_NEAR] 以内满亮，之后一路淡到 [constant CONE_REACH] 正好为 0。
##    所以「亮」和「照得到」不是一件事：400 像素处还有六成半亮，700 像素处只剩一点，
##    过了照程就一点都没有。
##
## 车底下（`offset` 和车头反向）自然落在半角之外，不用特判。
static func cone_light(offset: Vector2, heading: Vector2) -> float:
	var dist := offset.length()
	if dist < 0.001:
		# 正对着锥尖：方向没有意义，当作满亮。不特判的话下面 atan2 出的是
		# 一个任意角度，车一动灯心就闪。
		return 1.0
	if dist >= CONE_REACH:
		return 0.0
	var h := heading
	if h.length_squared() < 0.0001:
		return 0.0
	h = h.normalized()
	# 用 |夹角| 而不是点积：半角要能调，而 acos 出来的角度比点积直观得多
	# （点积那边半角是 cos，改一个数得先算反余弦）。
	var angle := absf(angle_difference(h.angle(), offset.angle()))
	var lateral := _fade(rad_to_deg(angle), CONE_HALF_DEG, CONE_HALF_DEG + CONE_SOFT_DEG)
	# 纵向就是 [constant CONE_NEAR] → [constant CONE_REACH] 那一段 smoothstep：
	# 灯口那儿斜率为 0（不会在近处亮成一块方糖），照程尽头斜率也是 0（不会切出横边），
	# 中间单调下降 —— 「随距离衰减」要的就是这条单调。
	var reach := _fade(dist, CONE_NEAR, CONE_REACH)
	return lateral * reach


## [param value] 涨到 [param full] 就开始淡、到 [param none] 全灭。
##
## `full >= none`（也就是一个没宽度的边）时退化成硬边，免得除零。
static func _fade(value: float, full: float, none: float) -> float:
	if value <= full:
		return 1.0
	if value >= none or none <= full:
		return 0.0
	var u := (value - full) / (none - full)
	return 1.0 - u * u * (3.0 - 2.0 * u)


## 屏幕上 `offset` 那一像素**最终的黑度**：光池、车灯锥、地板三者最亮那个的补数。
##
## `offset` 是**车轴心指向该点**的向量（不是绝对坐标），`heading` 是车头朝向的单位向量，
## `apex` 是**锥尖**（车头那颗灯珠）相对轴心的位置。车在屏幕上的位置和朝向每帧都在变，
## 挡布只认这几个量，所以这是个纯函数，能直接测。
##
## `apex` 默认在轴心上，只有测试会用到那个默认值 —— 在场上锥尖永远在车头
## （见 [method _draw]，以及类文档里「为什么不能从轴心射」那段）。
##
## `lamps` 是车灯开着吗。传布尔而不是自己去读车，是为了这个函数还是纯的、能直接测。
static func screen_alpha(offset: Vector2, heading: Vector2, lamps: bool,
		apex := Vector2.ZERO) -> float:
	var light := UNLIT_LIGHT
	if lamps:
		light = maxf(light, car_light(offset.length()))
		light = maxf(light, cone_light(offset - apex, heading))
	return 1.0 - light


## 挡布跟的那辆车。挂上来的是**车壳**（见 [method setup]），车节点是它的父节点，
## 和 [method HillFeature.car_of] 一个路子。单独抽出来是为了让「灯开着吗」只有
## 一处实现 —— 到处 `get_parent()` 的话，哪天车的节点结构变了会静默地全变成 false。
func _car() -> HillCar:
	if _target == null or not is_instance_valid(_target):
		return null
	return _target.get_parent() as HillCar


## 车灯开着吗。**状态存在车上**（见 [member HillCar.headlights_on]），
## 挡布只读不存 —— 两处各存一份迟早会对不上，于是「按钮亮着、路上没光」。
func _lamps_on() -> bool:
	var car := _car()
	return car != null and car.headlights_on


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## 这一帧的顶点颜色。`offset` 是**车轴心指向该顶点**的向量，和 [method screen_alpha] 同义。
func _vertex_color(offset: Vector2, heading: Vector2, lamps: bool, apex: Vector2) -> Color:
	return Color(DARK, screen_alpha(offset, heading, lamps, apex))


## 一圈的角度边界，**按两段给**：锥形那一段（细）和其余整圈（粗）。
##
## 分两段而不是「在一个整圈网格里把锥形那截补细」，是为了躲开跨 0 / TAU 的麻烦：
## 锥形的两条边落在哪个象限都有可能，一个排好序的整圈网格要么得处理回绕、要么会
## 切出一条被涂了两次的窄缝。**涂两次不是「黑一点」那么简单**：α 0.95 叠两层是
## 1 - 0.05² = 0.9975，在 95% 的黑里是一条肉眼可见的深色接缝。
##
## 两段各自**均匀**、合起来正好一整圈、互不重叠，所以每个像素只被涂一次。
## 灯关着时只有一整圈粗扇片：没有锥形要描边，省下一半四边形（但**不能少铺那一段**，
## 少铺就是没涂过的透明区，见下面那条注释）。
func _angles(heading: Vector2, lamps: bool) -> Array[PackedFloat32Array]:
	var mid := heading.angle() if heading.length_squared() > 0.0001 else 0.0
	# 细扇片要盖住的是**半角 + 过渡角**，不只是半角：过渡那 9° 里的光是从满亮淡到 0 的，
	# 留给 11.25° 一片的粗扇片去画，整段过渡就退化成「一个顶点满亮、下一个顶点全灭」的
	# 一条折线，灯的边缘成了多边形。粗扇片从过渡角**外沿**起步，那儿的光正好是 0。
	var edge := deg_to_rad(CONE_HALF_DEG + CONE_SOFT_DEG)
	if not lamps:
		# 灯关着整圈同色（都是 [constant UNLIT_LIGHT] 那条地板），一圈均匀的粗扇片就够
		# —— 但**必须是整圈**：只铺「锥形以外那一圈」的话，车头前会留一块压根没涂过的
		# 透明区，看着就是黑夜里亮着一块白天。
		var ring := PackedFloat32Array()
		for s in SECTORS + 1:
			ring.append(mid + TAU * float(s) / float(SECTORS))
		var only: Array[PackedFloat32Array] = [ring]
		return only
	var coarse := PackedFloat32Array()
	for s in SECTORS + 1:
		# 从锥形右沿（含过渡）出发、绕一圈回到左沿：这一段是整圈减掉锥形那 62°。
		coarse.append(mid + edge + (TAU - 2.0 * edge) * float(s) / float(SECTORS))
	var fine := PackedFloat32Array()
	for s in CONE_SECTORS + 1:
		fine.append(mid - edge + 2.0 * edge * float(s) / float(CONE_SECTORS))
	var out: Array[PackedFloat32Array] = [coarse, fine]
	return out


## 半径方向的圈，从小到大，**最里面那圈是 0**。
##
## 从 0 开始是必须的：池芯不透明（灯开着时那儿 α = 1 - [constant CAR_PEAK]），
## 从 [constant CAR_CORE] 才开始铺的话，车周围会留一块**根本没涂过**的地方
## —— 画布上没画过的地方是透明的，看起来就是「车所在的那块还是白天」。
##
## 开着灯：光池的几圈 + 锥形的几圈并起来，并完**排一次序、去一次重** —— 两个都是
## 纯函数算出来的，重了会切出一圈高度为 0 的四边形，白画。最后一个半径直接甩到
## [constant REACH]：外面那一大片（α 0.95）由这一圈盖上，不用再补四块矩形。
##
## 关着灯只有 0 和 [constant REACH] 两圈：整块挡布一个颜色，32 片扇片足够。
func _radii(lamps: bool) -> PackedFloat32Array:
	var raw := PackedFloat32Array([0.0])
	if lamps:
		for r in CAR_RINGS + 1:
			raw.append(CAR_CORE + CAR_SOFT * float(r) / float(CAR_RINGS))
		for r in CONE_RINGS:
			raw.append(CONE_REACH * float(r + 1) / float(CONE_RINGS))
	raw.append(REACH)
	raw.sort()
	var out := PackedFloat32Array()
	for r in raw:
		if out.is_empty() or r - out[out.size() - 1] > 0.5:
			out.append(r)
	return out


func _draw() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var focus := to_local(_target.global_position)
	# 车壳自己的两个轴：局部 +x 就是车头方向。锥尖和两颗灯珠都得按它换算到屏幕上。
	var heading := _target.global_transform.x
	var up := _target.global_transform.y
	var car := _car()
	var lamps := car != null and car.headlights_on
	var cells := PackedVector2Array()
	if car != null:
		cells = car.headlight_lamps()
	var apex := Vector2.ZERO
	if cells.size() >= 2:
		# 锥尖在**靠前**那颗灯珠上（局部 +x 大的那颗），不在车轴心上：从轴心射的话
		# 车壳自己的前半截会落在锥形里，被一条亮楔子切成「前亮后暗」两截。
		var muzzle: Vector2 = cells[0] if cells[0].x > cells[1].x else cells[1]
		apex = heading * muzzle.x + up * muzzle.y
	var radii := _radii(lamps)
	for angles: PackedFloat32Array in _angles(heading, lamps):
		_fill(focus, angles, radii, heading, lamps, apex)
	_draw_lamps(focus, heading, up, cells)


## 把 `angles` 这一段扇形铺满，从 `radii[0]` 一直到 `radii` 的最后一个。
##
## 每个四边形四个顶点各算一遍颜色（[method screen_alpha]），所以光池的渐晕、锥形、
## 地板三样东西都是**逐顶点插值**出来的，不用写着色器。
func _fill(focus: Vector2, angles: PackedFloat32Array, radii: PackedFloat32Array,
		heading: Vector2, lamps: bool, apex: Vector2) -> void:
	for s in angles.size() - 1:
		var d0 := Vector2(cos(angles[s]), sin(angles[s]))
		var d1 := Vector2(cos(angles[s + 1]), sin(angles[s + 1]))
		for r in radii.size() - 1:
			var r0 := radii[r]
			var r1 := radii[r + 1]
			var quad := PackedVector2Array()
			var colors := PackedColorArray()
			if r0 <= 0.001:
				# 最里面那圈退化成一个点（[method _radii] 从 0 开始），给三角形：
				# 给「两个顶点重合的四边形」的话，三角化还得处理重复顶点。
				var at := _vertex_color(Vector2.ZERO, heading, lamps, apex)
				quad = PackedVector2Array([focus, focus + d0 * r1, focus + d1 * r1])
				colors = PackedColorArray([at, _vertex_color(d0 * r1, heading, lamps, apex),
						_vertex_color(d1 * r1, heading, lamps, apex)])
			else:
				quad = PackedVector2Array([
					focus + d0 * r0, focus + d1 * r0,
					focus + d1 * r1, focus + d0 * r1,
				])
				colors = PackedColorArray([
					_vertex_color(d0 * r0, heading, lamps, apex),
					_vertex_color(d1 * r0, heading, lamps, apex),
					_vertex_color(d1 * r1, heading, lamps, apex),
					_vertex_color(d0 * r1, heading, lamps, apex),
				])
			draw_polygon(quad, colors)


## 车头那两颗灯珠（用户原话：「需要把车灯画出来」）。位置是车上量的
## （[method HillCar.headlight_lamps]），不是这里写死的偏移。
##
## **只在灯开着的时候画。** 关着的时候整辆车都在 95% 的暗里，单画两个灯碗会变成
## 两个悬空的黑点，比不画还怪。
##
## 画在扇形之后、同一个 [CanvasItem] 里 —— 挡布是 z = [constant Maps.NIGHT_Z] 的一层，
## 这两颗灯珠自然压在它上面，不用另开一层（也就不会碰「挡布之上什么都没有」那条）。
func _draw_lamps(focus: Vector2, heading: Vector2, up: Vector2,
		cells: PackedVector2Array) -> void:
	if cells.size() < 2 or not _lamps_on():
		return
	# 灯珠半径按两颗灯的**间距**取（理由见 [constant LAMP_RADIUS_RATIO]）。
	var radius := (cells[1] - cells[0]).length() * LAMP_RADIUS_RATIO
	for cell: Vector2 in cells:
		var at := focus + heading * cell.x + up * cell.y
		draw_circle(at, radius * LAMP_GLOW, Color(LAMP_COLOR, 0.16))
		draw_circle(at, radius, Color(LAMP_COLOR, 0.95))
		draw_circle(at, radius * 0.45, Color(1.0, 1.0, 0.95, 0.95))
