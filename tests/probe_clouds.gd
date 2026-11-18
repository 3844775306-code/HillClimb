extends Node
## 采样截图，把「云 / 山 / 天空」三分类画成 ASCII 图。
##
## 肉眼从 png 上看不出的东西（云有没有画出来、在山脊之上还是之下、边界干不干净）
## 用像素说话：
##   空格 = 天空   # = 白云   o = 山丘（含地面）
##
## 左上角那团 # 是 HUD 的文字，每张图都在同一位置，可以当作参照物。

const SHOTS := ["01_start", "02_hills", "03_far"]

const COLS := 78
const ROWS := 34
const SAMPLE_STEP := 3   ## 每格隔几个像素采一次，够用且快

## 天空底色是 project.godot 的 default_clear_color ≈ (135,199,235)。
const SKY := Color(0.53, 0.78, 0.92)
## 离天空底色多近算天空。
const SKY_TOL := 0.10
## 近白的判定阈值。云是纯白 (255,255,255)。
const WHITE_MIN := 0.93

## HUD 文字所在的方块（左上角）。统计云的时候要把这块排除掉，
## 否则「有没有云」会被 HUD 的白字顶成通过。
const HUD_W := 880.0
const HUD_H := 110.0


func _ready() -> void:
	for name in SHOTS:
		_probe(name)
	_probe_gameover()
	get_tree().quit()


## 结束面板：把「亮」的像素画成图。遮罩把背景压暗了，所以亮 = 文字，
## 一眼就能看出每条文案的位置、行距，以及有没有叠在一起。
func _probe_gameover() -> void:
	var image := Image.load_from_file(
			ProjectSettings.globalize_path("res://.shots/04_gameover.png"))
	if image == null:
		print("!! 读不到 04_gameover.png")
		return
	var w := image.get_width()
	var h := image.get_height()
	print("")
	print("=== 04_gameover 亮部（# = 文字）===")
	var cols := 78
	var rows := 40
	var cell_w := float(w) / float(cols)
	var cell_h := float(h) / float(rows)
	for row in range(rows):
		var line := ""
		for col in range(cols):
			var bright := 0
			var seen := 0
			for y in range(int(row * cell_h), int((row + 1) * cell_h), 3):
				for x in range(int(col * cell_w), int((col + 1) * cell_w), 3):
					seen += 1
					var c := image.get_pixel(x, y)
					# 感知亮度。遮罩之后背景很暗，文字很亮，0.45 能干净地分开
					if 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 0.45:
						bright += 1
			line += "#" if float(bright) / maxf(1.0, float(seen)) > 0.08 else " "
		print("%4d |%s|" % [int(row * cell_h), line])

	# 按颜色把每一行文字认出来。hud.gd 里四种颜色各不相同，正好用来确认
	# 「本次」「历史」「新纪录」是三条独立的、颜色正确的文案。
	const TARGETS := {
		"标题(红)": Color(1.0, 0.42, 0.32),
		"本次(白)": Color(0.97, 0.98, 1.0),
		"历史(天蓝)": Color(0.62, 0.90, 1.0),
		"新纪录(金)": Color(1.0, 0.84, 0.24),
	}
	print("  --- 按颜色定位 ---")
	for label in TARGETS:
		var target: Color = TARGETS[label]
		var bands: Array = []
		var run := 0
		for y in range(h):
			var hits := 0
			for x in range(0, w, 2):
				var c := image.get_pixel(x, y)
				if absf(c.r - target.r) + absf(c.g - target.g) + absf(c.b - target.b) < 0.12:
					hits += 1
			if hits >= 3:
				run += 1
			else:
				if run >= 4:
					bands.append("y%d-%d" % [y - run, y - 1])
				run = 0
		print("  %-12s %d 段  %s" % [label, bands.size(), ", ".join(bands)])


func _probe(shot: String) -> void:
	var path := "res://.shots/%s.png" % shot
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		print("!! 读不到 %s" % path)
		return
	var w := image.get_width()
	var h := image.get_height()
	print("")
	print("=== %s  (%dx%d)   空=天空  #=云  o=山 ===" % [shot, w, h])

	var cell_w := float(w) / float(COLS)
	var cell_h := float(h) / float(ROWS)
	var cloud_px := 0          ## HUD 之外的近白像素 = 云
	var cloud_top := h

	for row in range(ROWS):
		var line := ""
		for col in range(COLS):
			var white := 0
			var hill := 0
			var seen := 0
			var x1 := int((col + 1) * cell_w)
			var y1 := int((row + 1) * cell_h)
			for y in range(int(row * cell_h), y1, SAMPLE_STEP):
				for x in range(int(col * cell_w), x1, SAMPLE_STEP):
					seen += 1
					var c := image.get_pixel(x, y)
					if c.r >= WHITE_MIN and c.g >= WHITE_MIN and c.b >= WHITE_MIN:
						white += 1
						if x >= HUD_W or y >= HUD_H:
							cloud_px += 1
							if y < cloud_top:
								cloud_top = y
					elif absf(c.r - SKY.r) + absf(c.g - SKY.g) + absf(c.b - SKY.b) > SKY_TOL:
						hill += 1
			var fw := float(white) / maxf(1.0, float(seen))
			var fh := float(hill) / maxf(1.0, float(seen))
			if fw > 0.35:
				line += "#"
			elif fh > 0.5:
				line += "o"
			elif fh > 0.15:
				line += ":"
			elif fw > 0.05:
				line += "."
			else:
				line += " "
		print("%4d |%s|" % [int(row * cell_h), line])

	print("  云像素（已排除左上 HUD 方块）%d，最高出现在 y=%s" % [
		cloud_px, str(cloud_top) if cloud_px > 0 else "—",
	])
	print("  %s" % ("云已经画出来了" if cloud_px > 300 else "!! 云可能没画"))
