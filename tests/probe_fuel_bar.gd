extends Node
## 读回截图里燃油条那一行的像素，确认「填充宽度」和「配色」都符合油量比例。

const ROW := 673
const SAMPLES := [40, 80, 120, 160, 200, 240, 280, 320]
const SHOTS := ["01_start", "02_hills", "03_far", "04_gameover"]


func _ready() -> void:
	for shot in SHOTS:
		_probe(shot)
	get_tree().quit()


func _probe(shot: String) -> void:
	var path := ProjectSettings.globalize_path("res://.shots/%s.png" % shot)
	var image := Image.load_from_file(path)
	if image == null:
		print("%s: 载入失败" % shot)
		return
	var parts := PackedStringArray()
	for x in SAMPLES:
		var c := image.get_pixel(x, ROW)
		parts.append("%d=#%02X%02X%02X" % [x, roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)])
	print("%s  %s" % [shot, "  ".join(parts)])
