extends Node
## 打印指定区间的地形剖面，用来查卡死点到底是个什么形状。

const FROM := 12600.0
const TO := 13550.0
const STEP := 25.0


func _ready() -> void:
	var terrain := HillTerrain.new()
	add_child(terrain)
	await get_tree().process_frame
	var prev: float = terrain.height_at(FROM)
	print("x=%.0f  y=%6.1f" % [FROM, prev])
	var x := FROM
	while x < TO:
		x += STEP
		var h: float = terrain.height_at(x)
		var slope := rad_to_deg(atan2(prev - h, STEP))
		print("x=%.0f  y=%6.1f   坡度 %s%.1f°" % [
			x, h, "+" if slope >= 0.0 else "", slope,
		])
		prev = h
	get_tree().quit()
