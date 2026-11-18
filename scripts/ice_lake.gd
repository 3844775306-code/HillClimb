extends HillFeature
## 冰湖：湖面上盖着一层薄冰，车压上去 0.5 秒后冰面开裂，车掉进湖里淹死。
##
## 面朝上的那层冰**不是**靠「给冰面配一块很滑的物理材质」做出来的。
## 实测（tests/surface_probe）证明那条路走不通：车胎是 `rough = true`，此时地面
## 侧的材质完全被忽略 —— 有没有材质、friction 是 0.7 还是 0.06，车的表现逐位
## 相同（车速 813、轮面 813、打滑 1.00×、2 秒 1134 像素）。所以「冰面极易打滑」
## 只能像雪地那样去改**轮子自己**的摩擦，也就是 [member HillCar.surface_grip]。
##
## ## 计时一旦开始就不会撤销
##
## 需求是「车子在上方经过后延迟 0.5 秒冰面破裂」，所以踩上去的那一刻就定死了：
## 车倒回去、跳起来，都照样裂。做成「离开就重置」的话，玩家可以用反复点刹
## 把冰面无限期地拖住，那就不叫危险地形了。

## 冰面把抓地力压到地图倍率的几成。雪地本体是 0.12，乘上去约 0.04（μ≈0.11），
## 比雪地本身滑得多 —— 需求要的是「极易打滑」。
const ICE_GRIP := 0.35
## 踩上冰面后多久裂。
const BREAK_DELAY := 0.5
## 冰板厚度。**顶面要和岸齐平**，所以中心在 `rim_y + THICKNESS / 2`，
## 车从岸上滚上冰面不该有个台阶。
const THICKNESS := 10.0

const ICE_COLOR := Color(0.72, 0.86, 0.95, 0.80)
const ICE_BROKEN_COLOR := Color(0.55, 0.72, 0.86, 0.25)
const CRACK_COLOR := Color(0.95, 0.98, 1.00, 0.90)
const WATER_COLOR := Color(0.13, 0.35, 0.62, 0.72)
## 淹死区。湖底比吊桥浅，用蓝色表示水。
const DROWN_FILL := Color(0.10, 0.30, 0.60, 0.55)

var _ice: StaticBody2D
var _ice_visual: Polygon2D
var _cracks: Line2D
var _sense: Area2D
## -1 = 还没人踩上来。
var _timer := -1.0
var _broken := false
## 当前被压住抓地力的车，离开时要把它的 surface_grip 还回去。
var _grip_car: HillCar


func _build() -> void:
	var left := span.position.x
	var width := span.size.x
	if width <= 0.0:
		return

	_build_water(left, width)
	_build_ice(left, width)
	add_hazard(pit_hazard_rect(span.size.y), HillCar.REASON_DROWN, DROWN_FILL)


## 湖水。画在冰面之前，好让冰盖在上面。
func _build_water(left: float, width: float) -> void:
	var water := Polygon2D.new()
	water.name = "Water"
	water.color = WATER_COLOR
	water.polygon = PackedVector2Array([
		Vector2(left, rim_y + 6.0),
		Vector2(left + width, rim_y + 6.0),
		Vector2(left + width, rim_y + span.size.y + 24.0),
		Vector2(left, rim_y + span.size.y + 24.0),
	])
	add_child(water)


func _build_ice(left: float, width: float) -> void:
	var top := rim_y
	var mid := rim_y + THICKNESS * 0.5
	var half := THICKNESS * 0.5

	# 实体冰板：车就踩在它上面。层 2 = 地面、掩码 0，和地形一样。
	_ice = StaticBody2D.new()
	_ice.name = "Ice"
	_ice.position = Vector2(left + width * 0.5, mid)
	_ice.collision_layer = 2
	_ice.collision_mask = 0
	_ice.add_to_group("ground")
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, THICKNESS)
	cs.shape = box
	_ice.add_child(cs)
	add_child(_ice)

	_ice_visual = Polygon2D.new()
	_ice_visual.name = "IceVisual"
	_ice_visual.color = ICE_COLOR
	_ice_visual.polygon = PackedVector2Array([
		Vector2(left, top), Vector2(left + width, top),
		Vector2(left + width, top + THICKNESS), Vector2(left, top + THICKNESS),
	])
	add_child(_ice_visual)

	# 裂纹。一开始藏着，车一踩上来就显出来 —— 玩家得知道「已经开始了」。
	_cracks = Line2D.new()
	_cracks.name = "Cracks"
	_cracks.width = 2.0
	_cracks.default_color = CRACK_COLOR
	_cracks.visible = false
	var pts := PackedVector2Array()
	# 几条从冰面中间斜着岔开的折线，位置按宽度取比例，不写死像素。
	var fracs := [0.18, 0.38, 0.55, 0.72, 0.88]
	for i in range(fracs.size()):
		var cx := left + width * float(fracs[i])
		var dir := 1.0 if i % 2 == 0 else -1.0
		pts.append(Vector2(cx, mid))
		pts.append(Vector2(cx + dir * width * 0.05, mid - half * 0.7))
		pts.append(Vector2(cx, mid))
		pts.append(Vector2(cx + dir * width * 0.04, mid + half * 1.6))
	_cracks.points = pts
	add_child(_cracks)

	# 感知区。**不能用冰板自己的 get_colliding_bodies()** —— 那是 [RigidBody2D]
	# 才有的接触监听，静态体上没有。用 [Area2D] 探车，和死亡区同一套已验证的写法。
	_sense = Area2D.new()
	_sense.name = "Sense"
	_sense.collision_layer = 0
	_sense.collision_mask = 1
	var scs := CollisionShape2D.new()
	var sense_box := RectangleShape2D.new()
	sense_box.size = Vector2(width, 75.0)
	scs.shape = sense_box
	_sense.add_child(scs)
	_sense.position = Vector2(left + width * 0.5, rim_y - 32.5)
	add_child(_sense)


func _physics_process(delta: float) -> void:
	if _broken:
		return

	var car := _car_on_ice()
	if car != _grip_car:
		_release_grip()
		_grip_car = car
	if car != null:
		car.surface_grip = ICE_GRIP
		if _timer < 0.0:
			_timer = BREAK_DELAY
			_cracks.visible = true

	if _timer >= 0.0:
		_timer -= delta
		if _timer <= 0.0:
			_break()


## 踩在冰面上的那辆车，没人踩就是 null。
func _car_on_ice() -> HillCar:
	if _sense == null:
		return null
	for body in _sense.get_overlapping_bodies():
		var car := car_of(body)
		if car != null and car.alive:
			return car
	return null


func _break() -> void:
	_broken = true
	_release_grip()
	# 层归 0，车直接穿过去掉进水里。板子还在（只是不再挡路），画成半透明。
	_ice.collision_layer = 0
	_ice_visual.color = ICE_BROKEN_COLOR
	_cracks.width = 3.0


func _release_grip() -> void:
	if _grip_car != null and is_instance_valid(_grip_car):
		_grip_car.surface_grip = 1.0
	_grip_car = null
