extends Control

const GRID_SIZE := 19
const CENTER := Vector2i(9, 9)
const START_ATTACK := 5
const START_DEFENSE := 3
const START_VISION := 4
const START_MOVE := 15
const TARGET_ENEMY_COUNT := 112
const MIN_ENEMY_COUNT := 100
const MAX_ENEMY_COUNT := 125
const ALTAR_COUNT := 12
const ALTAR_LOW_ENEMY_TARGET := 2
const SIDE_WIDTH := 420.0

const CELL_TYPE_NORMAL := "normal"
const CELL_TYPE_START := "start"
const CELL_TYPE_ALTAR := "altar"
const CELL_TYPE_TREASURE := "treasure"

const ENEMY_TYPES := [
	{"name": "Lesser Foe", "letter": "e", "min_power": 2, "max_power": 4, "min_reward": 1, "max_reward": 1, "color": Color(1.0, 0.42, 0.42)},
	{"name": "Foe", "letter": "E", "min_power": 5, "max_power": 7, "min_reward": 2, "max_reward": 2, "color": Color(0.92, 0.12, 0.12)},
	{"name": "Bandit", "letter": "B", "min_power": 8, "max_power": 10, "min_reward": 3, "max_reward": 3, "color": Color(0.95, 0.28, 0.08)},
	{"name": "Raider", "letter": "R", "min_power": 11, "max_power": 13, "min_reward": 5, "max_reward": 5, "color": Color(0.58, 0.03, 0.03)},
	{"name": "Armored Foe", "letter": "H", "min_power": 14, "max_power": 16, "min_reward": 7, "max_reward": 7, "color": Color(0.34, 0.0, 0.0)},
	{"name": "Elite Foe", "letter": "X", "min_power": 17, "max_power": 19, "min_reward": 9, "max_reward": 10, "color": Color(0.14, 0.0, 0.0)}
]
const ENEMY_ICON_SCRIPT := preload("res://scripts/enemy_icon.gd")

var grid: Array = []
var player_pos := CENTER
var treasure_pos := Vector2i.ZERO
var main_route: Array[Vector2i] = []
var altar_positions: Array[Vector2i] = []
var protected_cells := {}
var rng := RandomNumberGenerator.new()

var attack := START_ATTACK
var defense := START_DEFENSE
var vision := START_VISION
var movement_points := START_MOVE
var reward_points := 0
var earned_points_total := 0
var altar_exchange_pool := 0
var altar_last_valid_build := {}
var updating_altar_controls := false
var game_over := false
var game_won := false

var grid_origin := Vector2(24, 84)
var cell_size := 32.0

var side_panel: PanelContainer
var stats_label: Label
var message_label: RichTextLabel
var altar_panel: PanelContainer
var altar_state_label: Label
var attack_spin: SpinBox
var defense_spin: SpinBox
var vision_spin: SpinBox
var move_spin: SpinBox
var altar_budget_label: Label
var apply_button: Button


func _ready() -> void:
	rng.randomize()
	_build_ui()
	_new_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_ui()
		queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER:
			return
		if game_over or grid.is_empty():
			return
		if altar_panel.visible or _cell(player_pos).type == CELL_TYPE_ALTAR:
			_toggle_altar_panel()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_new_game()
			return
		if game_over:
			return
		if altar_panel.visible:
			return
		var direction := Vector2i.ZERO
		match event.keycode:
			KEY_UP, KEY_W:
				direction = Vector2i.UP
			KEY_DOWN, KEY_S:
				direction = Vector2i.DOWN
			KEY_LEFT, KEY_A:
				direction = Vector2i.LEFT
			KEY_RIGHT, KEY_D:
				direction = Vector2i.RIGHT
		if direction != Vector2i.ZERO:
			_try_move(player_pos + direction)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not game_over:
		if altar_panel.visible:
			return
		var cell := _screen_to_cell(event.position)
		if _is_inside(cell) and _manhattan(player_pos, cell) == 1:
			_try_move(cell)


func _build_ui() -> void:
	side_panel = PanelContainer.new()
	add_child(side_panel)

	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 12)
	side_margin.add_theme_constant_override("margin_top", 10)
	side_margin.add_theme_constant_override("margin_right", 12)
	side_margin.add_theme_constant_override("margin_bottom", 10)
	side_panel.add_child(side_margin)

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_margin.add_child(side_scroll)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 10)
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side_box)

	var title := Label.new()
	title.text = "Minesweeper RPG"
	title.add_theme_font_size_override("font_size", 24)
	side_box.add_child(title)

	stats_label = Label.new()
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(stats_label)

	var new_game_button := Button.new()
	new_game_button.text = "New Map (R)"
	new_game_button.pressed.connect(_new_game)
	side_box.add_child(new_game_button)

	message_label = RichTextLabel.new()
	message_label.bbcode_enabled = true
	message_label.fit_content = false
	message_label.custom_minimum_size = Vector2(0, 112)
	side_box.add_child(message_label)

	_build_enemy_legend(side_box)

	altar_panel = PanelContainer.new()
	side_box.add_child(altar_panel)
	var altar_box := VBoxContainer.new()
	altar_box.add_theme_constant_override("separation", 6)
	altar_panel.add_child(altar_box)

	var altar_title := Label.new()
	altar_title.text = "Altar: Reallocate Stats"
	altar_title.add_theme_font_size_override("font_size", 18)
	altar_box.add_child(altar_title)

	altar_state_label = Label.new()
	altar_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	altar_box.add_child(altar_state_label)

	attack_spin = _make_spin("Power", 0, 20, 1, altar_box)
	defense_spin = _make_spin("Defense", 0, 20, 1, altar_box)
	vision_spin = _make_spin("Vision", 4, 8, 1, altar_box)
	move_spin = _make_spin("Moves", 1, 50, 5, altar_box)

	altar_budget_label = Label.new()
	altar_budget_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	altar_box.add_child(altar_budget_label)

	var altar_buttons := HBoxContainer.new()
	altar_box.add_child(altar_buttons)
	apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(_apply_altar_build)
	altar_buttons.add_child(apply_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func() -> void: altar_panel.visible = false)
	altar_buttons.add_child(close_button)

	for spin in [attack_spin, defense_spin, vision_spin, move_spin]:
		spin.value_changed.connect(func(_value: float) -> void: _on_altar_spin_changed())

	_layout_ui()


func _build_enemy_legend(parent: VBoxContainer) -> void:
	var legend_panel := PanelContainer.new()
	parent.add_child(legend_panel)
	var legend_box := VBoxContainer.new()
	legend_box.add_theme_constant_override("separation", 5)
	legend_panel.add_child(legend_box)

	var legend_title := Label.new()
	legend_title.text = "Enemy Key"
	legend_title.add_theme_font_size_override("font_size", 16)
	legend_box.add_child(legend_title)

	for index in range(ENEMY_TYPES.size()):
		var template: Dictionary = ENEMY_TYPES[index]
		_add_enemy_legend_row(legend_box, index + 1, template.name, template.letter, template.color, "%d-%d" % [template.min_power, template.max_power], _reward_text(template))
	_add_enemy_legend_row(legend_box, 7, "Treasure Guard", "G", Color(0.02, 0.02, 0.02), "20", "0")


func _reward_text(template: Dictionary) -> String:
	if int(template.min_reward) == int(template.max_reward):
		return str(template.min_reward)
	return "%d-%d" % [template.min_reward, template.max_reward]


func _add_enemy_legend_row(parent: VBoxContainer, level: int, enemy_name: String, letter: String, color: Color, power_text: String, reward_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var icon := Control.new()
	icon.set_script(ENEMY_ICON_SCRIPT)
	icon.custom_minimum_size = Vector2(28, 28)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	icon.configure(level, letter, color)
	row.add_child(icon)

	var label := Label.new()
	label.text = "%s  Pwr %s  Reward %s" % [enemy_name, power_text, reward_text]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)


func _make_spin(label_text: String, min_value: int, max_value: int, step: int, parent: VBoxContainer) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(128, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _layout_ui() -> void:
	if side_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var panel_width: float = minf(SIDE_WIDTH, maxf(320.0, viewport_size.x - 24.0))
	side_panel.position = Vector2(viewport_size.x - panel_width - 12.0, 12.0)
	side_panel.size = Vector2(panel_width, viewport_size.y - 24.0)
	var available_width: float = maxf(280.0, viewport_size.x - panel_width - 70.0)
	var available_height: float = maxf(280.0, viewport_size.y - 112.0)
	cell_size = floor(min(available_width, available_height) / GRID_SIZE)
	grid_origin = Vector2(24, 84)


func _new_game() -> void:
	game_over = false
	game_won = false
	player_pos = CENTER
	attack = START_ATTACK
	defense = START_DEFENSE
	vision = START_VISION
	movement_points = START_MOVE
	reward_points = 0
	earned_points_total = 0
	altar_exchange_pool = 0
	_generate_valid_map()
	_reveal_from_player()
	altar_panel.visible = false
	_set_message("Start from the center. Use clue numbers to judge danger, find altars, and reach the edge treasure.")
	_update_ui()
	queue_redraw()


func _generate_valid_map() -> void:
	for attempt in range(80):
		_generate_map_once()
		if _validate_map():
			return
	push_warning("Map validation fallback used after repeated generation attempts.")


func _generate_map_once() -> void:
	grid.clear()
	main_route.clear()
	altar_positions.clear()
	protected_cells.clear()

	for y in range(GRID_SIZE):
		var row := []
		for x in range(GRID_SIZE):
			row.append({
				"type": CELL_TYPE_NORMAL,
				"enemy": null,
				"revealed": false,
				"number": 0
			})
		grid.append(row)

	_cell(CENTER).type = CELL_TYPE_START
	treasure_pos = _random_edge_cell()
	_cell(treasure_pos).type = CELL_TYPE_TREASURE
	_cell(treasure_pos).enemy = _make_guard()

	main_route = _build_hidden_route(CENTER, treasure_pos)
	for pos in main_route:
		protected_cells[pos] = true
	protected_cells[CENTER] = true

	_place_altars()
	_place_enemies()
	_calculate_numbers()


func _random_edge_cell() -> Vector2i:
	var edge := rng.randi_range(0, 3)
	match edge:
		0:
			return Vector2i(0, rng.randi_range(0, GRID_SIZE - 1))
		1:
			return Vector2i(GRID_SIZE - 1, rng.randi_range(0, GRID_SIZE - 1))
		2:
			return Vector2i(rng.randi_range(0, GRID_SIZE - 1), 0)
	return Vector2i(rng.randi_range(0, GRID_SIZE - 1), GRID_SIZE - 1)


func _build_hidden_route(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = [from_pos]
	var current := from_pos
	var guard := 0
	while current != to_pos and guard < 200:
		guard += 1
		var options: Array[Vector2i] = []
		if current.x != to_pos.x:
			options.append(Vector2i(signi(to_pos.x - current.x), 0))
		if current.y != to_pos.y:
			options.append(Vector2i(0, signi(to_pos.y - current.y)))
		if rng.randf() < 0.22:
			for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var next: Vector2i = current + direction
				if _is_inside(next) and _chebyshev(next, CENTER) >= 2 and _manhattan(next, to_pos) <= _manhattan(current, to_pos) + 1:
					options.append(direction)
		var chosen: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		var next_pos := current + chosen
		if _is_inside(next_pos):
			current = next_pos
			if not route.has(current):
				route.append(current)
	return route


func _place_altars() -> void:
	var altars: Array[Vector2i] = []
	_place_altars_for_rule(altars, 1, func(pos: Vector2i) -> bool: return _chebyshev(pos, treasure_pos) >= 3 and _chebyshev(pos, treasure_pos) <= 4)
	_place_altars_for_rule(altars, 3, func(pos: Vector2i) -> bool: return _manhattan(pos, CENTER) <= 6)
	_place_altars_for_rule(altars, 5, func(pos: Vector2i) -> bool: return _chebyshev(pos, CENTER) >= 4 and _chebyshev(pos, CENTER) <= 6)
	_place_altars_for_rule(altars, 3, func(pos: Vector2i) -> bool: return _chebyshev(pos, CENTER) >= 7 and _chebyshev(pos, CENTER) <= 8)
	_place_altars_for_rule(altars, ALTAR_COUNT - altars.size(), func(_pos: Vector2i) -> bool: return true)

	for altar in altars:
		_cell(altar).type = CELL_TYPE_ALTAR
		_cell(altar).revealed = true
		protected_cells[altar] = true
		for neighbor in _orthogonal_neighbors(altar):
			protected_cells[neighbor] = true
	altar_positions = altars.duplicate()


func _place_altars_for_rule(altars: Array[Vector2i], desired_count: int, rule: Callable) -> void:
	var placed := 0
	while placed < desired_count and altars.size() < ALTAR_COUNT:
		if not _try_place_altar_from_candidates(_candidate_cells(rule), altars):
			return
		placed += 1


func _candidate_cells(rule: Callable) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			if pos == CENTER or pos == treasure_pos:
				continue
			if _cell(pos).type != CELL_TYPE_NORMAL:
				continue
			if not rule.call(pos):
				continue
			candidates.append(pos)
	candidates.shuffle()
	return candidates


func _try_place_altar_from_candidates(candidates: Array[Vector2i], altars: Array[Vector2i]) -> bool:
	for pos in candidates:
		var far_enough := true
		for altar in altars:
			if _manhattan(pos, altar) < 4:
				far_enough = false
				break
		if far_enough:
			altars.append(pos)
			return true
	return false


func _place_enemies() -> void:
	_place_altar_low_enemies()

	var candidates: Array[Vector2i] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			if _can_have_enemy(pos):
				candidates.append(pos)
	candidates.shuffle()

	for pos in candidates:
		if _enemy_count() >= TARGET_ENEMY_COUNT:
			break
		var probability := _enemy_probability(pos)
		if rng.randf() <= probability:
			_cell(pos).enemy = _make_enemy(pos)

	candidates.shuffle()
	for pos in candidates:
		if _enemy_count() >= TARGET_ENEMY_COUNT:
			break
		if _cell(pos).enemy == null:
			_cell(pos).enemy = _make_enemy(pos)


func _place_altar_low_enemies() -> void:
	for altar in altar_positions:
		var candidates := _altar_enemy_candidates(altar)
		var placed := 0
		for pos in candidates:
			if placed >= ALTAR_LOW_ENEMY_TARGET:
				break
			if _cell(pos).enemy != null:
				continue
			_cell(pos).enemy = _make_enemy_at_level(1 if rng.randf() < 0.75 else 2)
			placed += 1


func _altar_enemy_candidates(altar: Vector2i) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var pos := altar + Vector2i(dx, dy)
			if not _is_inside(pos):
				continue
			if _chebyshev(pos, altar) > 2:
				continue
			if _can_have_enemy(pos):
				candidates.append(pos)
	candidates.shuffle()
	return candidates


func _can_have_enemy(pos: Vector2i) -> bool:
	if pos == CENTER or pos == treasure_pos:
		return false
	if _cell(pos).type != CELL_TYPE_NORMAL:
		return false
	return true


func _enemy_probability(pos: Vector2i) -> float:
	var radius := _chebyshev(pos, CENTER)
	var probability := 0.0
	if radius <= 1:
		probability = 0.0
	elif radius <= 3:
		probability = rng.randf_range(0.08, 0.12)
	elif radius == 4:
		probability = rng.randf_range(0.15, 0.18)
	elif radius <= 6:
		probability = rng.randf_range(0.22, 0.30)
	elif radius <= 8:
		probability = rng.randf_range(0.32, 0.40)
	else:
		probability = rng.randf_range(0.42, 0.50)
	if _chebyshev(pos, treasure_pos) <= 3:
		probability += 0.15
	return clampf(probability, 0.0, 0.75)


func _make_enemy(pos: Vector2i) -> Dictionary:
	if _is_low_level_only_cell(pos):
		return _make_enemy_at_level(1 if rng.randf() < 0.75 else 2)
	var radius := _chebyshev(pos, CENTER)
	var level := 1
	if radius <= 3:
		level = 1
	elif radius == 4:
		level = 2
	elif radius <= 6:
		level = 3
	elif radius <= 8:
		level = 4
	else:
		level = 5
	if _chebyshev(pos, treasure_pos) <= 3:
		level += 1
	var variation: int = [-1, 0, 0, 1][rng.randi_range(0, 3)]
	if level <= 3 and rng.randf() < 0.35:
		variation = -1
	level += variation
	level = clampi(level, 1, 6)
	return _make_enemy_at_level(level)


func _is_low_level_only_cell(pos: Vector2i) -> bool:
	return protected_cells.has(pos) or _chebyshev(pos, CENTER) <= 1


func _make_enemy_at_level(level: int) -> Dictionary:
	var template: Dictionary = ENEMY_TYPES[level - 1]
	return {
		"name": template.name,
		"letter": template.letter,
		"power": rng.randi_range(template.min_power, template.max_power),
		"reward": rng.randi_range(template.min_reward, template.max_reward),
		"level": level,
		"color": template.color
	}


func _make_guard() -> Dictionary:
	return {
		"name": "Treasure Guard",
		"letter": "G",
		"power": 20,
		"reward": 0,
		"level": 7,
		"color": Color(0.02, 0.02, 0.02)
	}


func _calculate_numbers() -> void:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			var count := 0
			for neighbor in _all_neighbors(pos):
				if _cell(neighbor).enemy != null:
					count += 1
			_cell(pos).number = count


func _validate_map() -> bool:
	if _enemy_count() < MIN_ENEMY_COUNT or _enemy_count() > MAX_ENEMY_COUNT:
		return false
	if _reachable_altars(5) < 1:
		return false
	if _reachable_altars(8) < 2:
		return false
	if not _path_exists(CENTER, treasure_pos):
		return false
	if _treasure_nearby_altars() < 1:
		return false
	return true


func _reachable_altars(limit: int) -> int:
	var visited := {CENTER: 0}
	var queue: Array[Vector2i] = [CENTER]
	var count := 0
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var distance: int = visited[current]
		if distance > limit:
			continue
		if _cell(current).type == CELL_TYPE_ALTAR:
			count += 1
		for neighbor in _orthogonal_neighbors(current):
			if visited.has(neighbor):
				continue
			if _cell(neighbor).enemy != null and int(_cell(neighbor).enemy.level) > 2:
				continue
			visited[neighbor] = distance + 1
			queue.append(neighbor)
	return count


func _path_exists(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	var visited := {from_pos: true}
	var queue: Array[Vector2i] = [from_pos]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to_pos:
			return true
		for neighbor in _orthogonal_neighbors(current):
			if visited.has(neighbor):
				continue
			if neighbor != to_pos and _cell(neighbor).enemy != null and int(_cell(neighbor).enemy.level) > 2:
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return false


func _treasure_nearby_altars() -> int:
	var count := 0
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			if _cell(pos).type == CELL_TYPE_ALTAR and _chebyshev(pos, treasure_pos) >= 3 and _chebyshev(pos, treasure_pos) <= 4:
				count += 1
	return count


func _try_move(target: Vector2i) -> void:
	if not _is_inside(target):
		return
	if _manhattan(player_pos, target) != 1:
		return
	movement_points -= 1
	player_pos = target
	_reveal_from_player()

	if _remaining_moves() <= 0:
		_fail("You ran out of moves.")
		return

	var cell := _cell(player_pos)
	if cell.enemy != null:
		_resolve_combat(cell.enemy)
		if game_over:
			return
		cell.enemy = null

	if cell.type == CELL_TYPE_TREASURE:
		_win("You defeated the Treasure Guard and claimed the treasure.")
	elif cell.type == CELL_TYPE_ALTAR:
		_set_message("You reached an altar. Press Enter to open it; press Enter again to apply and leave.")
	else:
		altar_panel.visible = false
		_set_message("Moved to (%d, %d). Read the clue numbers before choosing the next route." % [player_pos.x, player_pos.y])

	_update_ui()
	queue_redraw()


func _resolve_combat(enemy: Dictionary) -> void:
	if enemy.name == "Treasure Guard":
		if attack < enemy.power:
			_fail("The Treasure Guard has 20 power. Your power is too low.")
		return

	if attack < enemy.power:
		_fail("You encountered %s. Enemy power %d is higher than your power %d." % [enemy.name, enemy.power, attack])
		return

	reward_points += enemy.reward
	earned_points_total += enemy.reward
	defense -= 1
	if defense < 0:
		_fail("Defense fell below 0 after defeating %s." % enemy.name)
		return
	_set_message("Defeated %s: power %d, gained %d point(s), defense -1." % [enemy.name, enemy.power, enemy.reward])


func _open_altar_panel() -> void:
	altar_panel.visible = true
	altar_exchange_pool = _current_exchange_pool()
	updating_altar_controls = true
	attack_spin.value = attack
	defense_spin.value = defense
	vision_spin.value = vision
	move_spin.value = movement_points
	updating_altar_controls = false
	altar_last_valid_build = _capture_altar_build()
	_update_altar_state_label()
	_update_altar_budget()


func _toggle_altar_panel() -> void:
	if _cell(player_pos).type != CELL_TYPE_ALTAR:
		return
	if altar_panel.visible:
		_apply_altar_build()
	else:
		_open_altar_panel()
		_set_message("Altar opened. Adjust stats, then click Apply or press Enter again to apply and leave.")
	_update_ui()
	queue_redraw()


func _apply_altar_build() -> void:
	var new_attack := int(attack_spin.value)
	var new_defense := int(defense_spin.value)
	var new_vision := int(vision_spin.value)
	var new_moves := int(move_spin.value)
	var validation_message := _validate_altar_build(new_attack, new_defense, new_vision, new_moves)
	if not validation_message.is_empty():
		_set_message(validation_message)
		_update_altar_budget()
		return
	var cost := _build_cost(new_attack, new_defense, new_vision, new_moves)
	var pool := _altar_budget_pool()
	if cost > pool:
		_set_message("Not enough budget to apply this build.")
		_update_altar_budget()
		return

	attack = new_attack
	defense = new_defense
	vision = new_vision
	movement_points = new_moves
	reward_points = pool - cost
	_reveal_from_player()
	if _remaining_moves() <= 0:
		_fail("Move count fell below 1 after reallocation.")
		return
	altar_panel.visible = false
	_set_message("Stats reallocated. Current moves updated.")
	_update_ui()
	queue_redraw()


func _update_altar_budget() -> void:
	if altar_budget_label == null:
		return
	_update_altar_state_label()
	var build := _capture_altar_build()
	var build_attack: int = build.attack
	var build_defense: int = build.defense
	var build_vision: int = build.vision
	var build_moves: int = build.moves
	var cost := _build_cost(build_attack, build_defense, build_vision, build_moves)
	var pool := _altar_budget_pool()
	var validation_message := _validate_altar_build(build_attack, build_defense, build_vision, build_moves)
	var valid := validation_message.is_empty() and cost <= pool
	var status := "Ready" if valid else validation_message
	if cost > pool:
		status = "Not enough budget"
	altar_budget_label.text = "Build cost: %d / %d\nUnused points after apply: %d\nMoves after apply: %d\nStatus: %s\nVision: +1 costs 2\nMoves: every 5 costs 1" % [cost, pool, max(0, pool - cost), build_moves, status]
	apply_button.disabled = not valid


func _on_altar_spin_changed() -> void:
	if updating_altar_controls:
		return
	var build := _capture_altar_build()
	var cost := _build_cost(build.attack, build.defense, build.vision, build.moves)
	var validation_message := _validate_altar_build(build.attack, build.defense, build.vision, build.moves)
	if validation_message.is_empty() and cost <= _altar_budget_pool():
		altar_last_valid_build = build
		_update_altar_budget()
		return
	_restore_altar_build(altar_last_valid_build)
	_update_altar_budget()


func _capture_altar_build() -> Dictionary:
	return {
		"attack": int(attack_spin.value),
		"defense": int(defense_spin.value),
		"vision": int(vision_spin.value),
		"moves": int(move_spin.value)
	}


func _restore_altar_build(build: Dictionary) -> void:
	if build.is_empty():
		return
	updating_altar_controls = true
	attack_spin.value = build.attack
	defense_spin.value = build.defense
	vision_spin.value = build.vision
	move_spin.value = build.moves
	updating_altar_controls = false


func _validate_altar_build(build_attack: int, build_defense: int, build_vision: int, build_moves: int) -> String:
	if build_attack < 0 or build_attack > 20:
		return "Power must be between 0 and 20."
	if build_defense < 0 or build_defense > 20:
		return "Defense must be between 0 and 20."
	if build_vision < 4 or build_vision > 8:
		return "Vision must be between 4 and 8."
	if build_moves < 1 or build_moves > 50:
		return "Moves must be between 1 and 50."
	return ""


func _update_altar_state_label() -> void:
	if altar_state_label == null:
		return
	altar_state_label.text = "Current Stats\nPower: %d  Defense: %d  Vision: %d\nMoves: %d\nTotal earned points: %d\nUnused points: %d\nExchange budget: %d" % [
		attack,
		defense,
		vision,
		movement_points,
		earned_points_total,
		reward_points,
		_altar_budget_pool()
	]


func _build_cost(build_attack: int, build_defense: int, build_vision: int, build_moves: int) -> int:
	return build_attack + build_defense + (build_vision - 4) * 2 + ceili(float(build_moves) / 5.0)


func _current_exchange_pool() -> int:
	return _build_cost(attack, defense, vision, movement_points) + reward_points


func _altar_budget_pool() -> int:
	if altar_panel != null and altar_panel.visible:
		return altar_exchange_pool
	return _current_exchange_pool()


func _reveal_from_player() -> void:
	_cell(player_pos).revealed = true
	for offset in _vision_offsets():
		var pos := player_pos + offset
		if _is_inside(pos):
			_cell(pos).revealed = true


func _vision_offsets() -> Array[Vector2i]:
	var offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var diagonals: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	for index in range(clampi(vision - 4, 0, 4)):
		offsets.append(diagonals[index])
	return offsets


func _enemy_is_visible(enemy: Dictionary) -> bool:
	if enemy == null:
		return false
	return true


func _draw() -> void:
	_draw_header()
	_draw_grid()


func _draw_header() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(24, 38), "Arrow keys/WASD to move; click adjacent cells; R for a new map", HORIZONTAL_ALIGNMENT_LEFT, 800, 18, Color(0.9, 0.9, 0.9))


func _draw_grid() -> void:
	var font := get_theme_default_font()
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			var rect := Rect2(grid_origin + Vector2(x, y) * cell_size, Vector2(cell_size, cell_size))
			_draw_cell_background(rect, pos)
			_draw_cell_content(rect, pos, font)
			draw_rect(rect, Color(0.12, 0.12, 0.12), false, 1.0)


func _draw_cell_background(rect: Rect2, pos: Vector2i) -> void:
	var cell := _cell(pos)
	var color := Color(0.16, 0.16, 0.17)
	if cell.revealed or pos == player_pos or cell.type == CELL_TYPE_ALTAR:
		color = Color(0.72, 0.73, 0.72)
		if cell.type == CELL_TYPE_START:
			color = Color(0.28, 0.78, 0.82)
		elif cell.type == CELL_TYPE_ALTAR:
			color = Color(0.58, 0.40, 0.76)
		elif cell.type == CELL_TYPE_TREASURE:
			color = Color(0.94, 0.72, 0.18)
	draw_rect(rect.grow(-1), color, true)


func _draw_cell_content(rect: Rect2, pos: Vector2i, font: Font) -> void:
	var cell := _cell(pos)
	if pos == player_pos:
		draw_circle(rect.get_center(), cell_size * 0.32, Color(0.08, 0.34, 0.9))
		_draw_centered_text(font, rect, "P", 20, Color.WHITE)
		return
	if cell.type == CELL_TYPE_ALTAR:
		var center := rect.get_center()
		draw_colored_polygon([
			center + Vector2(0, -cell_size * 0.34),
			center + Vector2(cell_size * 0.34, 0),
			center + Vector2(0, cell_size * 0.34),
			center + Vector2(-cell_size * 0.34, 0)
		], Color(0.46, 0.12, 0.76))
		_draw_centered_text(font, rect, "A", 18, Color.WHITE)
		return
	if not cell.revealed:
		return
	if cell.type == CELL_TYPE_TREASURE:
		_draw_star(rect.get_center(), cell_size * 0.34, Color(1.0, 0.9, 0.1))
		_draw_centered_text(font, rect, "T", 18, Color(0.2, 0.12, 0.0))
		return
	if cell.enemy != null and _enemy_is_visible(cell.enemy):
		_draw_enemy(rect, cell.enemy, font)
		return
	var number: int = cell.number
	if number > 0:
		_draw_centered_text(font, rect, str(number), 18, _number_color(number))


func _draw_enemy(rect: Rect2, enemy: Dictionary, font: Font) -> void:
	var center := rect.get_center()
	var radius := cell_size * 0.28
	var color: Color = enemy.color
	match int(enemy.level):
		1:
			_draw_weak_enemy(center, radius, color)
		2:
			_draw_normal_enemy(center, radius, color)
		3:
			_draw_bandit_enemy(center, radius, color)
		4:
			_draw_raider_enemy(center, radius, color)
		5:
			_draw_armored_enemy(center, radius, color)
		6:
			_draw_elite_enemy(center, radius, color)
		_:
			_draw_guard_enemy(center, radius)
	_draw_centered_text_at(font, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.55)), enemy.letter, 13, Color.WHITE)
	_draw_centered_text_at(font, Rect2(rect.position + Vector2(0, rect.size.y * 0.48), Vector2(rect.size.x, rect.size.y * 0.5)), str(enemy.power), 12, Color.WHITE)


func _draw_weak_enemy(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius * 0.72, color)
	draw_circle(center + Vector2(-radius * 0.2, -radius * 0.2), radius * 0.18, Color(1.0, 0.78, 0.78))


func _draw_normal_enemy(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)
	draw_arc(center, radius * 0.62, 0.0, TAU, 32, Color.WHITE, 2.0)


func _draw_bandit_enemy(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon([
		center + Vector2(0, -radius),
		center + Vector2(radius, radius),
		center + Vector2(-radius, radius)
	], color)
	draw_line(center + Vector2(-radius * 0.48, -radius * 0.05), center + Vector2(radius * 0.48, -radius * 0.05), Color.WHITE, 2.0)


func _draw_raider_enemy(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0)
	], color)
	draw_line(center + Vector2(-radius * 0.55, 0), center + Vector2(radius * 0.55, 0), Color.WHITE, 2.0)
	draw_line(center + Vector2(0, -radius * 0.55), center + Vector2(0, radius * 0.55), Color.WHITE, 2.0)


func _draw_armored_enemy(center: Vector2, radius: float, color: Color) -> void:
	var rect := Rect2(center - Vector2(radius, radius), Vector2(radius * 2, radius * 2))
	draw_rect(rect, color, true)
	draw_rect(rect.grow(-radius * 0.22), Color(0.7, 0.08, 0.08), false, 2.0)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(0.95, 0.55, 0.55), 1.5)


func _draw_elite_enemy(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := -PI / 2.0 + index * TAU / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
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
	draw_colored_polygon(crown, Color(0.03, 0.03, 0.03))
	draw_line(Vector2(center.x - radius, base_y), Vector2(center.x + radius, base_y), Color(1.0, 0.74, 0.12), 3.0)


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(10):
		var angle := -PI / 2.0 + index * PI / 5.0
		var current_radius := radius if index % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * current_radius)
	draw_colored_polygon(points, color)


func _draw_centered_text(font: Font, rect: Rect2, text: String, font_size: int, color: Color) -> void:
	_draw_centered_text_at(font, rect, text, font_size, color)


func _draw_centered_text_at(font: Font, rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_position := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + text_size.y * 0.35)
	draw_string(font, text_position, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)


func _number_color(number: int) -> Color:
	if number == 1:
		return Color(0.05, 0.22, 0.95)
	if number == 2:
		return Color(0.78, 0.58, 0.02)
	if number == 3:
		return Color(0.95, 0.32, 0.02)
	return Color(0.82, 0.02, 0.02)


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var local := screen_pos - grid_origin
	return Vector2i(floori(local.x / cell_size), floori(local.y / cell_size))


func _update_ui() -> void:
	stats_label.text = "Power: %d / 20\nDefense: %d / 20\nVision: %d / 8\nMoves: %d\nTotal earned points: %d\nUnused points: %d\nExchange budget: %d\nEnemy count: %d\nTreasure: (%d, %d)" % [
		attack,
		defense,
		vision,
		_remaining_moves(),
		earned_points_total,
		reward_points,
		_current_exchange_pool(),
		_enemy_count(),
		treasure_pos.x,
		treasure_pos.y
	]
	if altar_panel.visible:
		_update_altar_budget()


func _set_message(message: String) -> void:
	message_label.text = message


func _fail(reason: String) -> void:
	game_over = true
	game_won = false
	altar_panel.visible = false
	_set_message("[color=#d03030]Defeat: %s[/color]\nPress R to restart." % reason)
	_update_ui()
	queue_redraw()


func _win(reason: String) -> void:
	game_over = true
	game_won = true
	altar_panel.visible = false
	_set_message("[color=#2c9f45]Victory: %s[/color]\nPress R to restart." % reason)
	_update_ui()
	queue_redraw()


func _remaining_moves() -> int:
	return movement_points


func _enemy_count() -> int:
	var count := 0
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if Vector2i(x, y) == treasure_pos:
				continue
			if _cell(Vector2i(x, y)).enemy != null:
				count += 1
	return count


func _cell(pos: Vector2i) -> Dictionary:
	return grid[pos.y][pos.x]


func _is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < GRID_SIZE and pos.y < GRID_SIZE


func _orthogonal_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = pos + direction
		if _is_inside(neighbor):
			result.append(neighbor)
	return result


func _all_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor := pos + Vector2i(dx, dy)
			if _is_inside(neighbor):
				result.append(neighbor)
	return result


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))


func signi(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0
