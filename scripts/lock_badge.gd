extends RefCounted
class_name HillLockBadge
## 锁住的卡片长什么样：**一份实现，三屏共用**（选车 / 选图 / 以后的任何一屏）。
##
## 选车和选图两页的卡片几何是同一套（1160 面板里四张 276.5 宽的卡），锁卡要盖的
## 也正是这两页的卡。分头各写一份的话，两边的挂锁大小、压暗程度、文案断行迟早会
## 长得不一样，而「锁」这种东西玩家一眼就能看出两屏不是一个人画的。
##
## ## 为什么要压暗而不是不画
##
## 锁住的卡**照常把整张画完**（预览图、名字、说明、纪录），再盖一层半透明暗色。
## 玩家得能看见自己买的是什么 —— 看不见就只是个「莫名其妙点不动的黑框」。压暗
## 之后卡片退成背景，前面这层挂锁和价钱才是主角。
##
## ## 挂锁是拿图元拼的，不是 🔒
##
## 没有用 emoji：中文字体（[UiFonts] 挑出来的那个）不保证带 emoji 字形，英文那份
## 用的引擎默认字体更不保证 —— 一旦缺字形就是一个豆腐块，而且**只在部分机器上**
## 缺，本地测不出来。所以锁身是 [method CanvasItem.draw_rect] 摞出来的圆角矩形
## （一个横条 + 一个竖条 + 四个角圆），锁梁是 [method CanvasItem.draw_arc] 的半圆。
##
## 文案走 [method HillMapSelect.fit_size] 缩号：卡宽是死的，价钱和提示语是活的，
## 而 `draw_string` 不裁不绕，撑出去会画到隔壁卡上。

## 盖在锁卡上的那层暗色。**别调太黑** —— 压到看不清预览就等于没画。
const SCRIM := Color(0.03, 0.05, 0.09, 0.74)
## 锁身 / 锁梁。
const BODY := Color(0.86, 0.90, 0.96, 0.92)
const SHACKLE := Color(0.72, 0.78, 0.88, 0.88)
## 锁身上的钥匙孔（比锁身暗，等于挖空）。
const KEYHOLE := Color(0.05, 0.08, 0.13, 0.95)
## 价钱和提示那两行字的底板。**半透明**：叠在 [constant SCRIM] 上之后近乎不透明，
## 但还留着一丝卡片原本的明暗，不至于变成一块死板的黑条。
const PLATE := Color(0.04, 0.06, 0.10, 0.88)
## 价钱那行的金色（和金币总数同一个黄）。
const PRICE := Color(1.0, 0.84, 0.24)
## 买不起时的价钱色（和推重比超线用同一个红）。
const DENIED := Color(1.0, 0.42, 0.36)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.97, 0.98, 1.0, 0.62)

## 卡片里文字左右各自的留白。和两页界面里的同名常量取一个数，文案可用宽度才对齐。
const PAD := 20.0

## 挂锁的尺寸。**不随卡宽缩放**：两页的卡宽都是 276.5，没有第二个尺寸要适配；
## 真要适配也该在这里加一个 scale 参数，而不是让三个调用点各自算一遍。
const LOCK_W := 54.0
const LOCK_H := 42.0
const LOCK_R := 8.0
const SHACKLE_R := 16.0
const SHACKLE_W := 7.0

## 挂锁锁身**上沿**离卡片顶部的距离。
##
## 挑这个数是为了让整把锁落在卡片顶上那一条**预览图**里（两页的预览高都是 118）：
## 整把锁高 `SHACKLE_R + SHACKLE_W/2 + LOCK_H ≈ 61.5`，上下各留 28 正好居中，
## 于是锁占 28.5..90，整条都在 118 以内。
##
## **锁不能往卡片中段挪。** 中段全是字，而这两页的卡上每行字都是左对齐、宽的可到
## 236 像素 —— 挂锁是画在卡片正中的（横向 cx ± 27），压上去就会盖掉名字或参数行
## 当中的一个字。预览那一条里没有字，只有画面，锁盖在那儿最干净，而且「缩略图上
## 盖一把锁」本来就是锁卡的标准画法。
const LOCK_CY := 48.0

## 价钱那块底板：上下沿（相对卡片顶部）、左右内缩、圆角。
##
## **这块底板是必须的，不是装饰。** 卡上原有的文字（参数行、说明、推重比）和挂锁
## 那两行字都在卡片中段，`draw_string` 画的字下面没有底色，两层字会直接叠在一起。
## 底板的 alpha 加上 [constant SCRIM] 之后近乎不透明，压在下面的那几行就退成
## 隐约的痕迹 —— 预览图、名字、特性这些**露在底板外面**的还好好的，玩家照样看得见
## 自己买的是什么。
##
## 上下沿是**量出来的**，不是随手取的：两页的卡上每行字的基线都在各自界面里写死
## （选图的 `LINE_*`、选车的字面常量），底板要把中段那几行整个盖住、又不能从当中
## 切开任何一行。172..238 是两边都满足的那一段：
##
##   · 选图：名字（基线 162）露在上面，参数行（188）、说明两行（214 / 235）压在
##     底下，地形名（264）整个露在下面。
##   · 选车：车名（164）露在上面，整车（192）、满油（216）压在底下，定位那行（256）
##     露在下面。
##
## `tests/mapselect` 有一条用例就是量这件事：任何一行字要么整个在底板里，要么整个
## 在外面，**不许被从当中切开**（切一半的字看着像渲染坏了）。谁挪了卡上的行距，
## 那一条会当场报出来。
const PLATE_TOP := 172.0
const PLATE_H := 66.0
const PLATE_INSET := 12.0
const PLATE_R := 10.0


## 把整张卡压暗。调用方先照常画完整张卡，再叫这个，最后才 [method draw]。
static func dim(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(rect, SCRIM)


## 在压暗过的卡上画挂锁、价钱和一行提示。
##
## [param headline] 是主角（价钱 / 已锁定），[param sub] 是那句怎么办的提示。
## [param hot] 为真时（光标停在这张卡上）两行字都提亮，和选择界面里别的卡
## 「焦点更亮」是同一套反馈。[param accent] 是 [param headline] 的颜色，默认金色；
## 买不起时调用方传 [constant DENIED]。
static func draw(canvas: CanvasItem, font: Font, rect: Rect2, headline: String, sub: String,
		hot := false, accent := PRICE) -> void:
	if font == null:
		return
	var cx := rect.position.x + rect.size.x * 0.5
	_padlock(canvas, Vector2(cx, rect.position.y + LOCK_CY))

	# 底板盖住卡片中段原有的字（见 [constant PLATE_TOP]）。
	_round_rect(canvas,
			Rect2(rect.position.x + PLATE_INSET, rect.position.y + PLATE_TOP,
					rect.size.x - PLATE_INSET * 2.0, PLATE_H),
			PLATE_R, PLATE)

	# 两行字的基线：24 号那行上沿离底板 11 像素、15 号那行下沿离底边 7 像素，上下
	# 大致对称；两行之间留 6 像素，贴着但不相交。
	var room := rect.size.x - PAD * 2.0
	var head_size := HillMapSelect.fit_size(font, headline, 24, room)
	canvas.draw_string(font, Vector2(rect.position.x, rect.position.y + PLATE_TOP + 32.0), headline,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, head_size,
			accent if hot else accent.lerp(TEXT_DIM, 0.18))
	var sub_size := HillMapSelect.fit_size(font, sub, 15, room)
	canvas.draw_string(font, Vector2(rect.position.x, rect.position.y + PLATE_TOP + 56.0), sub,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, sub_size,
			TEXT if hot else TEXT_DIM)


## 挂锁本体，[param at] 是锁身的**上沿用**（锁梁挂在它上面）。
static func _padlock(canvas: CanvasItem, at: Vector2) -> void:
	# 锁梁：上半圆，两端正好落在锁身上沿，所以不用再补两条腿。
	canvas.draw_arc(at, SHACKLE_R, PI, TAU, 24, SHACKLE, SHACKLE_W, true)
	# 锁身。先画锁梁再画锁身，锁梁那两条下端就被压在锁身底下了。
	var r := Rect2(at.x - LOCK_W * 0.5, at.y, LOCK_W, LOCK_H)
	_round_rect(canvas, r, LOCK_R, BODY)
	# 钥匙孔：一个圆 + 一条向下的短柄，比锁身暗。
	var centre := r.get_center() + Vector2(0.0, -2.0)
	canvas.draw_circle(centre, 5.5, KEYHOLE)
	canvas.draw_rect(Rect2(centre.x - 2.0, centre.y, 4.0, 12.0), KEYHOLE)


## 实心圆角矩形。Godot 2D 没有现成的这个图元，用「一个横条 + 一个竖条 + 四个角圆」
## 摞出来 —— 四段 [method CanvasItem.draw_arc] 拼边框会在接缝处露白。
##
## [param radius] 超过短边一半时会被夹住，不然中间那个竖条会算成负宽度。
static func _round_rect(canvas: CanvasItem, rect: Rect2, radius: float, color: Color) -> void:
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	canvas.draw_rect(Rect2(rect.position.x, rect.position.y + r, rect.size.x, rect.size.y - r * 2.0), color)
	canvas.draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - r * 2.0, rect.size.y), color)
	for corner in [Vector2(rect.position.x + r, rect.position.y + r),
			Vector2(rect.end.x - r, rect.position.y + r),
			Vector2(rect.position.x + r, rect.end.y - r),
			Vector2(rect.end.x - r, rect.end.y - r)]:
		canvas.draw_circle(corner, r, color)


## 「多少钱」那行字，就是锁卡的主角。
##
## 中英两份文案**收在这一处**：选车和选图要说的是同一句话，将来也只会改一次。
## [param cjk] 由调用方传自己的 `_cjk`（「找到中文字体了没有」），三屏同源。
static func price_line(price: int, cjk: bool) -> String:
	return ("%d 金币解锁" if cjk else "%d COINS TO UNLOCK") % price


## 锁卡底下那行提示 —— **它得说实话**。
##
## 光标不在这张卡上时说「点一下选中」，在卡上时说「再点一下购买」：两段式买法的
## 第二下才是真花钱，不写出来的话玩家点一下没反应，会以为卡是坏的
## （见 [method SaveData.unlock_map] 上方的说明）。
##
## 买不起是**第三种话**，不能套上面那两句中的任何一句：钱不够的时候「再点一下购买」
## 是句假话，点了什么都不会发生。
static func hint_line(focused: bool, afford: bool, cjk: bool) -> String:
	if not afford:
		return "金币不够" if cjk else "NOT ENOUGH COINS"
	if focused:
		return "再点一下购买" if cjk else "TAP AGAIN TO BUY"
	return "点一下选中" if cjk else "TAP TO SELECT"
