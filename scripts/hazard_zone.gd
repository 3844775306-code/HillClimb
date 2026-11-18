extends Area2D
class_name HillHazard
## 一块「碰到就死」的区域，外加一层半透明色（水的蓝、岩浆的橙、坑底的暗）。
##
## 三种特殊地形共用这一个脚本：吊桥的沟底（摔下去）、冰湖的水（淹死）、
## 火山口的岩浆（烧死）。差别只有矩形、颜色和死因三个参数。

## 死因，见 [HillCar] 的 `REASON_*`。
@export var reason := HillCar.REASON_FALL
## 覆盖区域的半透明色。全透明就不画。
@export var fill := Color(0.0, 0.0, 0.0, 0.0)

@onready var shape_node: CollisionShape2D = $Shape


func _ready() -> void:
	# 只认车所在的层（1），不认地形层（2）：地形和自己的死区是重叠的，
	# 让它进来只会白跑一遍。
	collision_layer = 0
	collision_mask = 1


func setup(rect: Rect2, reason_id: String, color: Color) -> void:
	# **节点的原点是矩形的中心，不是左上角。** [RectangleShape2D] 是以自己为中心
	# 的，所以把它挂在这个节点上、节点放在 `rect.position` 的话，整片死区会往
	# 左上各偏半个身位 —— 而调用方（[method HillFeature.pit_hazard_rect]）给的
	# 是左上角 + 尺寸。这个偏差在窄而浅的坑上看着「碰巧也能触发」（车掉下去的
	# 过程中会从偏移后的区域里穿过），在宽的坑上就是「明明掉进去了却不死」。
	position = rect.position + rect.size * 0.5
	reason = reason_id
	fill = color
	# 形状是 .tscn 里的子资源，**默认在所有实例之间共享**，直接改 size 会把
	# 别的死亡区一起改掉。先 duplicate 再改。
	var box: RectangleShape2D = (shape_node.shape as RectangleShape2D).duplicate()
	box.size = rect.size
	shape_node.shape = box
	queue_redraw()


func _physics_process(_delta: float) -> void:
	# 每帧查重叠而不是只听 body_entered：区块是随机动车滚动、在车**已经**站在
	# 坑里的时候才建出来的，那种情况下 body_entered 不会响。
	for body in get_overlapping_bodies():
		var car := HillFeature.car_of(body)
		if car != null:
			car.die(reason)
			return


func _draw() -> void:
	if fill.a <= 0.0:
		return
	# 形状的局部坐标以节点原点为中心
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	draw_rect(Rect2(-size * 0.5, size), fill)
