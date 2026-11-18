extends Node2D
## 车手的外观。头画在车厢上方露出来，好让玩家看清「头不能着地」这件事。
##
## 他会**跟着车颠**（[HillSeatRide] 那套弹簧-阻尼模型），但只看不碰：车的物理一个字节
## 都不动，见 [code]scripts/seat_ride.gd[/code] 开头那条铁律。
##
## **`Chassis/Head` 那个 Area2D 一动不动。** 它是翻车判据（「车手的头碰到地面」），跟着抖
## 就等于改了物理 —— 而那个判据是标定过的（头高 116 px 一类）。代价是画出来的头最多和
## 碰撞体差 5 像素（[constant HillSeatRide.MAX_OFFSET]），方向看当下是压下去还是飘起来。
## 15 像素半径上差 5 像素，看得出但不碍事；换来的是所有翻车测试一个字都不用改。

const SKIN := Color(0.98, 0.80, 0.62)
const HELMET := Color(0.16, 0.36, 0.72)
const SUIT := Color(0.20, 0.55, 0.85)

const HEAD_CENTER := Vector2(0.0, -36.0)

## 座位在车身局部坐标里的位置。**这个节点的原点就是胯**（场景里 Driver 的 position），
## 所以座位就是原点 —— 也正因为原点在胯下，[member HillSeatRide.lean] 才是「上身以胯为轴
## 前倾」而不是「脑袋自己转」。
const SEAT := Vector2.ZERO

## 关掉它就是「这辆车还是原来的样子」：不积分、位移归零。[code]tests/driver[/code] 拿它
## 跑对照局（开颠簸 / 关颠簸两遍比最终坐标），和 [code]scripts/effects.gd[/code] 的
## [member enabled] 一个路子。
var enabled := true

var ride := HillSeatRide.new()


func _physics_process(delta: float) -> void:
	var chassis := get_parent() as RigidBody2D
	if chassis == null:
		return
	if enabled:
		ride.step(chassis, SEAT, delta)
	else:
		ride.reset()
	queue_redraw()


func _draw() -> void:
	# 整个人平移到「座位 + 位移」、再绕胯倾一点。画完还原，免得影响这个节点上别的东西
	# （乘员节点是同一个路子）。
	draw_set_transform(ride.offset, ride.lean, Vector2.ONE)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-11.0, 4.0), Vector2(-8.0, -22.0), Vector2(8.0, -22.0), Vector2(12.0, 4.0),
		]),
		SUIT
	)
	draw_circle(HEAD_CENTER, 15.0, SKIN)
	# 上半圆当头盔。
	draw_arc(HEAD_CENTER, 15.5, PI, TAU, 24, HELMET, 10.0, true)
	draw_circle(HEAD_CENTER + Vector2(7.0, 1.0), 2.4, Color(0.12, 0.12, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
