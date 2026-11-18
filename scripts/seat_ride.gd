class_name HillSeatRide
extends RefCounted
## 车上的人「坐在座位上」的弹簧-阻尼模型。**纯数学，不碰任何节点、不读不写物理。**
##
## 铁律（和 [code]scripts/effects.gd[/code] 开头同一条）：车上的人只**读**刚体状态。
## 车的物理一个字节都不动 —— [code]tests/driver[/code] 跑两遍同一局（开颠簸 / 关颠簸）
## 比较车的最终坐标，逐位相同才算过。
##
## [b]为什么不给车手挂一个真 RigidBody2D。[/b] Godot 的 2D 铰链没有角度弹簧，压住他得自己
## 写 [method RigidBody2D._integrate_forces] 里的力矩；而且他的质量和惯量会计入整车
## （越野车 174、推重比 1.005 都是量出来的数），铰链还是个软约束，会往车身里灌能量。
## 这个项目的爬坡角度、里程、惯量全是标定过的，动一分就全废。
##
## [b]受力项取的是座位那个点在世界坐标里的加速度[/b]（含角速度的离心项、角加速度的切向项），
## 取负就是惯性力 —— 这是载人模型的标准写法。于是刹车前扑、起飞上飘、碾过鼓包下压
## 全部自动出来，因为那正是「加速度」的物理含义，不是编的动画。
##
## 标定：[constant K] 定死后，[b]1 g 的加速度 = 2.76 像素的可见位移[/b]
## （980 / 355 = 2.76）。K 再小就飞出座位、再大就看不见了。
## [b]模型里没有任何重力常量[/b]：车稳稳停着时座位加速度为零（速度不变），所以静止就是
## 零位移、画出来的位置就是场景里写的那个位置，没有静态下沉；而自由落体时座位加速度
## 就是一个 g，人往上飘 —— 「车掉下去了、人还留在原地」。月球图（0.35 倍重力）自动跟上。

## 刚度 = ω²，ω = 2π × 3Hz（约三赫兹的上下颠）。
const K := 355.0
## 阻尼 = 2ζω，ζ = 0.5（颠两下就停，不会晃成弹簧门）。
const C := 18.85
## 位移限幅（像素）。= 1.8 g 的静态位移。人再多也不能画出座位，也不能离碰撞体太远。
const MAX_OFFSET := 5.0
## 横向位移 → 上身倾角（弧度／像素）。5 像素 = 5.7°，真人刹车前倾差不多就是这个量级。
const LEAN_PER_PX := 0.02
const MAX_LEAN := 0.12

## 相对座位的位移，**车身局部坐标**（+y 向下，和场景里那套一致）。
var offset := Vector2.ZERO
## 上身倾角（弧度），正数朝 +y 侧倒。由 [member offset] 的横向分量带出来：
## 原点在胯下，所以这就是「以胯为轴的前倾」。
var lean := 0.0

var _vel := Vector2.ZERO
var _prev_lin := Vector2.ZERO
var _prev_ang := 0.0
## 第一帧只记速度、不积分：进场的第一个物理帧速度会从 0 跳到「重力已经加上」，
## 那一跳不是真加速度，拿来当受力项会看到一个人凭空弹一下。
var _primed := false


## 采样座位那个点的加速度并推进一格。
## [param chassis] 车身刚体；[param seat_local] 座位在**车身局部坐标**里的位置（只用来采样，
## 不参与画什么）；[param dt] 物理帧长。
func step(chassis: RigidBody2D, seat_local: Vector2, dt: float) -> void:
	if _primed and dt > 0.0:
		var lin := chassis.linear_velocity
		var ang := chassis.angular_velocity
		var a_cm := (lin - _prev_lin) / dt
		var alpha := (ang - _prev_ang) / dt
		# 座位那个点相对**节点原点**的位矢。严格说该拿质心（center_of_mass）当极点，
		# 但 Godot 的自动质心只有物理服务器知道、节点上读不到；这个差别只影响旋转项
		# 的极点取哪儿，而旋转项本身就不到 1 像素，不值当去查服务器。
		var r := chassis.to_global(seat_local) - chassis.global_position
		# 切向项 alpha × r（2D 的叉积）+ 离心项 −ω²r。
		var a_seat := a_cm + Vector2(-alpha * r.y, alpha * r.x) - ang * ang * r
		integrate(chassis.global_transform.basis_xform_inv(a_seat), dt)
	_prev_lin = chassis.linear_velocity
	_prev_ang = chassis.angular_velocity
	_primed = true


## 推进一格。抽出来是为了 [code]tests/driver[/code] 能不开场景、直接喂加速度验模型。
func integrate(accel_local: Vector2, dt: float) -> void:
	var drive := -accel_local  # 惯性力：人往加速度的**反**方向倒
	_vel += (drive - K * offset - C * _vel) * dt
	offset = (offset + _vel * dt).limit_length(MAX_OFFSET)
	lean = clampf(offset.x * LEAN_PER_PX, -MAX_LEAN, MAX_LEAN)


## 回到「没在动」的样子。关掉颠簸的那一局用它，好和开着的那一局逐位对比。
func reset() -> void:
	offset = Vector2.ZERO
	lean = 0.0
	_vel = Vector2.ZERO
	_primed = false
