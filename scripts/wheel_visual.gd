extends Node2D
## 轮子的外观。挂在轮子刚体下面，所以会自动跟着刚体旋转。

@export var radius := 21.0
@export var tire_color := Color(0.13, 0.13, 0.16)
@export var rim_color := Color(0.85, 0.86, 0.90)
@export var hub_color := Color(0.45, 0.47, 0.55)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, tire_color)
	draw_circle(Vector2.ZERO, radius * 0.62, rim_color)
	draw_circle(Vector2.ZERO, radius * 0.20, hub_color)
	for i in 5:
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 5.0)
		draw_line(dir * radius * 0.22, dir * radius * 0.58, hub_color, 3.0)
	# 胎纹，转起来能看出轮子在动。
	for i in 12:
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 12.0)
		draw_line(dir * radius * 0.86, dir * radius, Color(0.04, 0.04, 0.06), 3.0)
