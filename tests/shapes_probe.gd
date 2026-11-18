extends Node
## **屋顶**地图的 ASCII 剖面：缝右侧是不是真的低一截、钢梯爬多高、拱脚离地多少。
##
## 窗口里看不到的东西（折线是不是真的右低左高、坡度是不是真的到了 55°）用字符看。
## 每一列是一个采样点（[constant HillTerrain.POINT_SPACING] 像素一列），
## 一行 8 像素，`-` 是 GROUND_Y 那条基准线。
##
## 只读地形折线，不摆车、不跑物理 —— 秒级。
##
## **彩虹不在这里了。** 彩虹曾经也是「连续地形上的拱」，靠 `Maps.span_at` /
## `arches_at` / `HillTerrain.shape_rise` 这几条造出来；改版之后它是一整片散在空中的
## 平台（[constant Maps.SHAPE_ARCHES]，见 [method Maps.platforms_in_column]），
## 地表函数不再是它的形状来源 —— 上面那几条 API 也一起删了。
## 彩虹那张图现在跑 [code]tests/shapes.gd[/code] 里的 ASCII **平台场**图，
## 那个画的是「哪儿有平台」，跟这里画「地表折线」不是一回事。

const SEED := 1337
## 画几个区块。
const CHUNKS := 4
const ROW_PX := 8.0
## 画多高：从 GROUND_Y 往上 150 到往下 90。
const TOP_OFF := 150.0
const BOT_OFF := 90.0

var _terrain: HillTerrain
var _world: Node2D


func _ready() -> void:
	_world = Node2D.new()
	add_child(_world)
	_terrain = HillTerrain.new()
	_world.add_child(_terrain)
	_terrain.world_seed = SEED
	_terrain.map_id = Maps.ROOFTOP
	_draw("屋顶 ROOFTOP")
	_rims()
	_heights()
	get_tree().quit()


## 从第 1 块到第 CHUNKS 块的地表剖面。
func _draw(title: String) -> void:
	print("")
	print("=== %s（种子 %d，每列 %d 像素） ===" % [
			title, SEED, int(HillTerrain.POINT_SPACING)])
	var rows := int((TOP_OFF + BOT_OFF) / ROW_PX)
	var total := CHUNKS * HillTerrain.CHUNK_POINTS + 1
	var grid: Array = []
	for r in rows:
		grid.append(_line(total))
	for c in total:
		var x := float(Maps.SHAPE_START_CELL) * HillTerrain.CHUNK_WIDTH \
				+ float(c) * HillTerrain.POINT_SPACING
		var y := _terrain.height_at(x)
		var off := y - HillTerrain.GROUND_Y            # 正数 = 比基准低
		if off > BOT_OFF or off < -TOP_OFF:
			continue
		var r := int((off + TOP_OFF) / ROW_PX)
		if r < 0 or r >= rows:
			continue
		grid[r] = _put(grid[r], c)
	# 基准线：GROUND_Y 那一行画 `|`，其余位置留给地面。
	var base_row := int(TOP_OFF / ROW_PX)
	grid[base_row] = _baseline(grid[base_row], total)
	for r in rows:
		var label := "        " if r != base_row else "GROUND  "
		print("%s%s" % [label, grid[r]])
	# 每栋房子一行小注：几段钢梯 / 爬多高 / 这条缝的落差。
	var note := ""
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + CHUNKS):
		var prof: Dictionary = _terrain.roof_profile(i)
		var dice: Dictionary = Maps.roof_dice(SEED, i)
		note += "%d:%d段 爬%+.0f 落差%.0f  " % [i, int(dice["ladders"]),
				float(prof["y0"]) - float(prof["y1"]), Maps.drop_at(SEED, i)]
	print("        " + note)


func _line(n: int) -> String:
	return " ".repeat(n)


func _put(s: String, i: int) -> String:
	if i <= 0 or i > s.length():
		return s
	return s.substr(0, i - 1) + "#" + s.substr(i)


## 基准线只在还没有地面的列上画，免得把剖面盖掉。
func _baseline(s: String, n: int) -> String:
	var out := ""
	for i in n:
		out += "-" if s[i] == " " else s[i]
	return out


## 每条缝左右两沿的高度和落差。
func _rims() -> void:
	print("")
	print("=== 缝：左沿 / 右沿 / 落差（正数 = 右边更低） ===")
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + 12):
		var left_x := float(i) * HillTerrain.CHUNK_WIDTH + Maps.span_at(SEED, i)
		var right_x := float(i + 1) * HillTerrain.CHUNK_WIDTH
		var l := _terrain.height_at(left_x - 0.5)
		var r := _terrain.height_at(right_x + 0.5)
		var dice: Dictionary = Maps.roof_dice(SEED, i)
		print("  缝 %2d  宽 %5.1f  左沿 %7.2f  右沿 %7.2f  右低 %6.2f  （掷出来 %.2f，左边那栋 %d 段）" % [
				i, Maps.gap_at(SEED, i), l, r, r - l, Maps.drop_at(SEED, i), int(dice["ladders"])])


## 扫一大段，打印最陡坡度 —— 钢梯中段（理论 1.5 / LADDER_RUN ≈ 55°）/ 拱脚。
##
## **只扫屋顶（拱）那一段**，不含缝壁：缝壁本来就是 84° 的墙，扫进去只会得到
## 一个 88° 的「最陡坡度」，什么也说明不了。
func _heights() -> void:
	var steep := 0.0
	var at := 0.0
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + 300):
		var left := float(i) * HillTerrain.CHUNK_WIDTH
		var x := left + 1.0
		while x < left + Maps.span_at(SEED, i) - 1.0:
			var d := (_terrain.height_at(x + 1.0) - _terrain.height_at(x - 1.0)) * 0.5
			if absf(d) > steep:
				steep = absf(d)
				at = x
			x += 1.0
	print("")
	print("=== 屋顶最陡坡度（不含缝壁）：%.3f（%.1f°），x = %.0f（第 %d 块） ===" % [
			steep, rad_to_deg(atan(steep)), at, int(at / HillTerrain.CHUNK_WIDTH)])
	for d in [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]:
		print("    x = %.0f  高度 %.2f" % [at + d, _terrain.height_at(at + d)])
	var kinds := {}
	for i in range(Maps.SHAPE_START_CELL, Maps.SHAPE_START_CELL + 300):
		var d: Dictionary = Maps.roof_dice(SEED, i)
		kinds[int(d["ladders"])] = int(kinds.get(int(d["ladders"]), 0)) + 1
	print("  300 栋的钢梯段数分布：%s" % [kinds])
