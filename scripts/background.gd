extends Node2D
class_name HillBackground
## 远景：天上的白云 + 两层正弦叠加的视差山丘。
##
## 白云比山丘更远，所以横向视差更小（山丘按世界坐标 1:1 滚动，云只有 0.18），
## 车往前开时云会明显「跟不上」，纵深感就出来了。
##
## 纵向不这样处理：云的位置锁死在最远那层山的基准线上方固定高度，而不是
## 也乘一个独立的视差系数。因为任何小于山丘系数的纵向系数，在车爬到足够高
## 之后都会让云沉到山脊下面去 —— 这是个爬得越高越容易踩中的坑，直接锁死
## 就没有这个自由度，也就没有这个 bug。

const VIEW_HALF_WIDTH := 1400.0
const STEP := 24.0

## 最远那层山的参数。_draw() 里第一次 _draw_layer 调用必须与这里一致 ——
## 白云的纵向位置是相对它来定的。
const FAR_LAYER_BASE_Y := 300.0
const FAR_LAYER_Y_PARALLAX := -0.10
## 云比最远那层山的基准线还高这么多。最远那层的波峰最高约 128px，
## 所以 230 能保证云的底边永远压在山脊之上。
const CLOUD_RISE := 230.0

## 云的横向视差：0 = 完全不动，1 = 跟山丘一样快。越小显得越远。
const CLOUD_PARALLAX := 0.18
## 相邻两朵云在「云空间」里的间隔。
const CLOUD_PERIOD := 760.0
## 一朵云纵向散开的范围。
const CLOUD_SPREAD := 170.0

## 一朵云的形状：五个圆的相对位置与半径（云自身坐标系，单位 px）。
const CLOUD_BLOB_X := [-46.0, -24.0, 2.0, 26.0, 46.0]
const CLOUD_BLOB_Y := [3.0, -9.0, -14.0, -9.0, 2.0]
const CLOUD_BLOB_R := [17.0, 23.0, 26.0, 22.0, 16.0]

var _camera: Camera2D
## 当前地图 id，决定三层山和云的颜色。
var _map_id := Maps.PLAINS


func setup(camera: Camera2D, map_id: String = Maps.PLAINS) -> void:
	_camera = camera
	set_map(map_id)


func set_map(map_id: String) -> void:
	_map_id = map_id
	queue_redraw()


func _process(_delta: float) -> void:
	if _camera != null:
		queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	var cam := _camera.global_position
	var palette := Maps.get_map(_map_id)
	# 云先画，山丘后画 —— 这样山脊会盖住云的底边
	_draw_clouds(cam, palette["cloud"])
	_draw_layer(cam, 0.25, -0.10, 300.0, palette["far"], 620.0, 90.0)
	_draw_layer(cam, 0.45, -0.18, 360.0, palette["mid"], 420.0, 70.0)
	_draw_layer(cam, 0.68, -0.28, 420.0, palette["near"], 300.0, 55.0)


## 天上铺一层云。云在「云空间」里等距排布，每朵的高低、胖瘦、横向偏移由
## 序号哈希出来 —— 不用 RNG 对象，纯函数，所以任意位置重绘都是同一片天。
func _draw_clouds(cam: Vector2, color: Color) -> void:
	# 云空间的可见范围：把「画到屏幕上的 x」反解回云空间
	var scroll := cam.x * (1.0 + CLOUD_PARALLAX)
	var first := int(floor((scroll - VIEW_HALF_WIDTH) / CLOUD_PERIOD))
	var last := int(ceil((scroll + VIEW_HALF_WIDTH) / CLOUD_PERIOD))
	var baseline := cam.y * (1.0 + FAR_LAYER_Y_PARALLAX) + FAR_LAYER_BASE_Y - CLOUD_RISE
	var shift := cam.x * CLOUD_PARALLAX
	for i in range(first, last + 1):
		var jitter_x := _hash01(i * 3 + 1)
		var jitter_y := _hash01(i * 7 + 2)
		var jitter_scale := _hash01(i * 11 + 3)
		var cx := float(i) * CLOUD_PERIOD + jitter_x * CLOUD_PERIOD * 0.6 - shift
		var cy := baseline - jitter_y * CLOUD_SPREAD
		_draw_cloud(Vector2(cx, cy), 0.75 + jitter_scale * 0.6, color)


## 一朵云：五个圆叠出蓬松的上半部，再补一条平底。
##
## [param color] 是实心的，不要用半透明：几个半透明圆一叠加，交叠处会深一块
## 浅一块，很难看。卡通风格本来也是实心云。颜色由地图给（沙漠偏黄、火山偏灰）。
func _draw_cloud(center: Vector2, scale: float, color: Color) -> void:
	for i in CLOUD_BLOB_X.size():
		draw_circle(
				center + Vector2(CLOUD_BLOB_X[i], CLOUD_BLOB_Y[i]) * scale,
				CLOUD_BLOB_R[i] * scale, color)
	draw_rect(Rect2(center + Vector2(-44.0, 0.0) * scale,
			Vector2(90.0, 17.0) * scale), color)


## 整数 → [0, 1) 的确定性哈希。同一个序号永远得到同一个数，
## 所以云是「随机的」但每次运行、每个位置都一模一样。
func _hash01(n: int) -> float:
	var h := (n * 374761393 + 668265263) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h) / 2147483648.0


## [param parallax] 越小越远（表现为波长被拉长）；[param y_parallax] 控制垂直方向的跟随比例。
func _draw_layer(cam: Vector2, parallax: float, y_parallax: float, base_y: float, color: Color, wavelength: float, amplitude: float) -> void:
	var origin_y := cam.y * (1.0 + y_parallax) + base_y
	var points := PackedVector2Array()
	var x := cam.x - VIEW_HALF_WIDTH
	while x <= cam.x + VIEW_HALF_WIDTH:
		var px := x * parallax
		var h := sin(px / wavelength * TAU) * amplitude
		h += sin(px / (wavelength * 0.41) * TAU) * amplitude * 0.42
		points.append(Vector2(x, origin_y - h))
		x += STEP
	var bottom_left := Vector2(points[0].x, origin_y + 900.0)
	var bottom_right := Vector2(points[points.size() - 1].x, origin_y + 900.0)
	points.append(bottom_right)
	points.append(bottom_left)
	draw_colored_polygon(points, color)
