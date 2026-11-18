class_name HillPassengers
extends Node2D
## 巴士后排的乘客：一排「隔着车窗看见的头和肩」。
##
## **只有巴士有**（其余七辆车和 [code]car.tscn[/code] 里都没有这个节点，[code]tests/driver[/code]
## 会拦）。他们和车手同一套模型（[HillSeatRide]），差别只有两处：四个座位、每人一个弹簧；
## 画的是头+肩而不是整个人。
##
## 座位写死在常量里、不摆到场景里：四人一排是巴士独有的美术，写在一处比四个节点好读，
## 测试也能直接读 [constant SEATS] 对几何。
##
## 四个人的颠簸不必刻意编相位差 —— 座位离质心的距离各不相同，离心项和切向项就各不相同，
## 四个人自然不同步。这是模型自带的。

## 车窗带底边往上 1 像素，就是「胯」的高度。车身局部坐标。
##
## 车窗带是 y ∈ [−49, −25]（[code]bus.tscn[/code] 的 Windows），这套数字要把它撑满还留边：
## 头 [−47, −29]、肩膀 [−30, −26]，上下各留 2 / 1 像素。tests/driver 拿车窗多边形实读
## 一遍对，改车窗不改这里就会红。
##
## **颠簸最多再沉 5 像素**（[constant HillSeatRide.MAX_OFFSET]），那时肩膀会到窗线以下
## 一点点 —— 就那么画着，不做裁剪：裁剪要动车窗的透明度（它是车身唯一的玻璃色），
## 为了 5 像素去改一整块配色不值当。往上飘 5 像素则还在车窗和车顶之间，看不出来。
const SEAT_Y := -26.0
## 头的圆心相对座位，和半径。
const HEAD_DY := -12.0
const HEAD_R := 9.0
## 肩膀：下沿贴着座位，往上收一点，是个梯形。
const SHOULDER_DY := -4.0
const SHOULDER_BOT := 11.0
const SHOULDER_TOP := 8.0

## 四个座位（后半截，从车尾往前排）。间距 24 > 肩宽 22，不会挤在一起；
## 最后一排到 x = 20 就停 —— 司机在 44，中间留着驾驶室那一段空玻璃。
##
## 这几个是普通 [Array] 而不是 [PackedFloat32Array]：打包数组的构造**不是常量表达式**，
## GDScript 不收（`--import` 会当场报出来）。测试里取值的地方都显式转 float。
const SEATS := [-52.0, -28.0, -4.0, 20.0]

## 一人一档颜色，免得看着像复制粘贴。
const SKINS := [
	Color(0.98, 0.80, 0.62), Color(0.88, 0.68, 0.50), Color(0.72, 0.53, 0.36), Color(0.94, 0.74, 0.55),
]
const SUITS := [
	Color(0.85, 0.42, 0.38), Color(0.42, 0.62, 0.35), Color(0.55, 0.45, 0.72), Color(0.86, 0.68, 0.32),
]
## 头发。司机戴头盔，乘客画一圈头发 —— 一眼分得开。
const HAIRS := [
	Color(0.22, 0.16, 0.12), Color(0.12, 0.12, 0.14), Color(0.45, 0.32, 0.18), Color(0.30, 0.20, 0.14),
]
const EYE := Color(0.12, 0.12, 0.16)

## 和 [code]driver_visual.gd[/code] 的 [member enabled] 同义：关掉就是「还是原来的巴士」。
var enabled := true

## 一人一个弹簧。在 [method _init] 里建好，免得 [method _draw] 早于 [method _ready] 时是空的。
var rides: Array[HillSeatRide] = []


func _init() -> void:
	for i in SEATS.size():
		rides.append(HillSeatRide.new())


func _physics_process(delta: float) -> void:
	var chassis := get_parent() as RigidBody2D
	if chassis == null:
		return
	for i in rides.size():
		if enabled:
			rides[i].step(chassis, Vector2(float(SEATS[i]), SEAT_Y), delta)
		else:
			rides[i].reset()
	queue_redraw()


func _draw() -> void:
	for i in mini(SEATS.size(), rides.size()):
		var seat := Vector2(float(SEATS[i]), SEAT_Y)
		# 以胯为原点画：肩膀在原点附近、头在上方；倾斜自然就是「以胯为轴」。
		draw_set_transform(seat + rides[i].offset, rides[i].lean, Vector2.ONE)
		_draw_one(i)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_one(i: int) -> void:
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-SHOULDER_BOT, 0.0), Vector2(-SHOULDER_TOP, SHOULDER_DY),
			Vector2(SHOULDER_TOP, SHOULDER_DY), Vector2(SHOULDER_BOT, 0.0),
		]),
		SUITS[i % SUITS.size()] as Color
	)
	var head := Vector2(0.0, HEAD_DY)
	draw_circle(head, HEAD_R, SKINS[i % SKINS.size()] as Color)
	# 上半圆当头发，和车手那顶头盔同一个画法。
	draw_arc(head, HEAD_R + 0.5, PI, TAU, 16, HAIRS[i % HAIRS.size()] as Color, 5.0, true)
	draw_circle(head + Vector2(4.0, 1.0), 1.6, EYE)
