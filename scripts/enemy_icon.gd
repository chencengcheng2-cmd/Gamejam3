extends Control

var enemy_level := 1
var enemy_letter := "?"
var enemy_color := Color.RED


func configure(level: int, letter: String, color: Color) -> void:
	enemy_level = level
	enemy_letter = letter
	enemy_color = color
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.34
	match enemy_level:
		1:
			_draw_weak_enemy(center, radius)
		2:
			_draw_normal_enemy(center, radius)
		3:
			_draw_bandit_enemy(center, radius)
		4:
			_draw_raider_enemy(center, radius)
		5:
			_draw_armored_enemy(center, radius)
		6:
			_draw_elite_enemy(center, radius)
		_:
			_draw_guard_enemy(center, radius)
	_draw_centered_letter(center)


func _draw_weak_enemy(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.72, enemy_color)
	draw_circle(center + Vector2(-radius * 0.2, -radius * 0.2), radius * 0.18, Color(1.0, 0.78, 0.78))


func _draw_normal_enemy(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, enemy_color)
	draw_arc(center, radius * 0.62, 0.0, TAU, 32, Color.WHITE, 2.0)


func _draw_bandit_enemy(center: Vector2, radius: float) -> void:
	draw_colored_polygon([
		center + Vector2(0, -radius),
		center + Vector2(radius, radius),
		center + Vector2(-radius, radius)
	], enemy_color)
	draw_line(center + Vector2(-radius * 0.48, -radius * 0.05), center + Vector2(radius * 0.48, -radius * 0.05), Color.WHITE, 2.0)


func _draw_raider_enemy(center: Vector2, radius: float) -> void:
	draw_colored_polygon([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0)
	], enemy_color)
	draw_line(center + Vector2(-radius * 0.55, 0), center + Vector2(radius * 0.55, 0), Color.WHITE, 2.0)
	draw_line(center + Vector2(0, -radius * 0.55), center + Vector2(0, radius * 0.55), Color.WHITE, 2.0)


func _draw_armored_enemy(center: Vector2, radius: float) -> void:
	var rect := Rect2(center - Vector2(radius, radius), Vector2(radius * 2, radius * 2))
	draw_rect(rect, enemy_color, true)
	draw_rect(rect.grow(-radius * 0.22), Color(0.7, 0.08, 0.08), false, 2.0)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(0.95, 0.55, 0.55), 1.5)


func _draw_elite_enemy(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := -PI / 2.0 + index * TAU / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, enemy_color)
	draw_arc(center, radius * 0.58, 0.0, TAU, 32, Color(0.95, 0.18, 0.18), 2.0)


func _draw_guard_enemy(center: Vector2, radius: float) -> void:
	var base_y := center.y + radius * 0.55
	var crown := PackedVector2Array([
		center + Vector2(-radius, radius * 0.55),
		center + Vector2(-radius * 0.72, -radius * 0.72),
		center + Vector2(-radius * 0.25, -radius * 0.12),
		center + Vector2(0, -radius),
		center + Vector2(radius * 0.25, -radius * 0.12),
		center + Vector2(radius * 0.72, -radius * 0.72),
		center + Vector2(radius, radius * 0.55)
	])
	draw_colored_polygon(crown, enemy_color)
	draw_line(Vector2(center.x - radius, base_y), Vector2(center.x + radius, base_y), Color(1.0, 0.74, 0.12), 3.0)


func _draw_centered_letter(center: Vector2) -> void:
	var font := get_theme_default_font()
	var font_size := 13
	var text_size := font.get_string_size(enemy_letter, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var position := Vector2(0, center.y + text_size.y * 0.35)
	draw_string(font, position, enemy_letter, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color.WHITE)
