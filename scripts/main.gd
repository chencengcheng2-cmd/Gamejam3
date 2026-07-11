extends Control

const GRID_SIZE := 25
const CENTER := Vector2i(12, 12)
const START_MOVES := 15
const START_VISION := 15
const START_DEFENSE := 3
const MINE_COUNT := 68
const ALTAR_COUNT := 16
const BONUS_COUNT := 20
const BONUS_MIN_POINTS := 1
const BONUS_MAX_POINTS := 3
const TREASURE_ARROW_CHANCE := 0.08
const SIDE_WIDTH := 420.0

const CELL_NORMAL := "normal"
const CELL_START := "start"
const CELL_ALTAR := "altar"
const CELL_TREASURE := "treasure"
const CELL_BONUS := "bonus"

var grid: Array = []
var player_pos := CENTER
var treasure_pos := Vector2i.ZERO
var altar_positions: Array[Vector2i] = []
var bonus_positions: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()

var moves := START_MOVES
var vision := START_VISION
var defense := START_DEFENSE
var unused_points := 0
var total_bonus_points := 0
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
var moves_spin: SpinBox
var vision_spin: SpinBox
var defense_spin: SpinBox
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
		if altar_panel.visible or _cell(player_pos).type == CELL_ALTAR:
			_toggle_altar_panel()
			get_viewport().set_input_as_handled()
		elif _cell(player_pos).type == CELL_BONUS and not _cell(player_pos).collected:
			_collect_bonus_treasure()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_new_game()
			return
		if game_over or altar_panel.visible:
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
		if not _is_inside(cell):
			return
		if not _cell(cell).revealed:
			_probe_cell(cell)
		elif _manhattan(player_pos, cell) == 1:
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
	title.text = "Minesweeper Treasure"
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
	message_label.custom_minimum_size = Vector2(0, 130)
	side_box.add_child(message_label)

	_build_symbol_key(side_box)
	_build_altar_panel(side_box)
	_layout_ui()


func _build_symbol_key(parent: VBoxContainer) -> void:
	var key_panel := PanelContainer.new()
	parent.add_child(key_panel)
	var key_box := VBoxContainer.new()
	key_box.add_theme_constant_override("separation", 5)
	key_panel.add_child(key_box)

	var key_title := Label.new()
	key_title.text = "Map Key"
	key_title.add_theme_font_size_override("font_size", 16)
	key_box.add_child(key_title)

	for row in [
		["P", "Player"],
		["A", "Altar, usable once"],
		["T", "Treasure, move here to win"],
		["B", "Bonus treasure, move here for points"],
		["M", "Mine, moving here costs defense"],
		["0-8", "Mine clue number"]
	]:
		var label := Label.new()
		label.text = "%s  %s" % [row[0], row[1]]
		key_box.add_child(label)


func _build_altar_panel(parent: VBoxContainer) -> void:
	altar_panel = PanelContainer.new()
	parent.add_child(altar_panel)
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

	moves_spin = _make_spin("Moves", 1, 50, 5, altar_box)
	vision_spin = _make_spin("Vision", 0, 50, 5, altar_box)
	defense_spin = _make_spin("Defense", 0, 20, 1, altar_box)

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

	for spin in [moves_spin, vision_spin, defense_spin]:
		spin.value_changed.connect(func(_value: float) -> void: _on_altar_spin_changed())


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
	moves = START_MOVES
	vision = START_VISION
	defense = START_DEFENSE
	unused_points = 0
	total_bonus_points = 0
	altar_exchange_pool = 0
	_generate_valid_map()
	_cell(player_pos).revealed = true
	altar_panel.visible = false
	_set_message("Explore with vision clicks, move carefully, collect bonuses, use each altar once, and reach the treasure.")
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
	altar_positions.clear()
	bonus_positions.clear()

	for y in range(GRID_SIZE):
		var row := []
		for x in range(GRID_SIZE):
			row.append({
				"type": CELL_NORMAL,
				"mine": false,
				"revealed": false,
				"number": 0,
				"treasure_arrow": "",
				"bonus_points": 0,
				"used": false,
				"collected": false
			})
		grid.append(row)

	_cell(CENTER).type = CELL_START
	treasure_pos = _random_treasure_cell()
	_cell(treasure_pos).type = CELL_TREASURE

	_place_altars()
	_place_bonus_treasures()
	_place_mines()
	_calculate_numbers()
	_calculate_treasure_arrows()


func _random_treasure_cell() -> Vector2i:
	var candidates := _candidate_cells(func(pos: Vector2i) -> bool:
		return pos != CENTER and _manhattan(pos, CENTER) >= 20
	)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _place_altars() -> void:
	var region_size := 5
	var region_origins: Array[Vector2i] = []
	for y in range(0, GRID_SIZE, region_size):
		for x in range(0, GRID_SIZE, region_size):
			region_origins.append(Vector2i(x, y))
	region_origins.shuffle()

	for origin in region_origins:
		if altar_positions.size() >= ALTAR_COUNT:
			return
		_try_place_altar_in_region(origin, region_size, 4)

	for origin in region_origins:
		if altar_positions.size() >= ALTAR_COUNT:
			return
		_try_place_altar_in_region(origin, region_size, 3)


func _try_place_altar_in_region(origin: Vector2i, region_size: int, min_distance: int) -> bool:
	var candidates: Array[Vector2i] = []
	for y in range(origin.y, mini(origin.y + region_size, GRID_SIZE)):
		for x in range(origin.x, mini(origin.x + region_size, GRID_SIZE)):
			var pos := Vector2i(x, y)
			if pos == CENTER or pos == treasure_pos:
				continue
			if _cell(pos).type != CELL_NORMAL:
				continue
			candidates.append(pos)
	candidates.shuffle()
	for pos in candidates:
		if _is_far_from_existing(pos, altar_positions, min_distance):
			_cell(pos).type = CELL_ALTAR
			_cell(pos).revealed = true
			altar_positions.append(pos)
			return true
	return false


func _place_bonus_treasures() -> void:
	var candidates := _candidate_cells(func(pos: Vector2i) -> bool: return _cell(pos).type == CELL_NORMAL and _manhattan(pos, CENTER) > 2)
	for pos in candidates:
		if bonus_positions.size() >= BONUS_COUNT:
			break
		_cell(pos).type = CELL_BONUS
		_cell(pos).bonus_points = rng.randi_range(BONUS_MIN_POINTS, BONUS_MAX_POINTS)
		bonus_positions.append(pos)


func _place_mines() -> void:
	var safe_route := _build_hidden_route(CENTER, treasure_pos)
	var route_lookup := {}
	for pos in safe_route:
		route_lookup[pos] = true

	var candidates: Array[Vector2i] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			if _can_have_mine(pos, route_lookup):
				candidates.append(pos)
	candidates.shuffle()

	for pos in _treasure_mine_candidates():
		if _mine_count() >= MINE_COUNT:
			return
		if _can_have_mine(pos, route_lookup) and not _cell(pos).mine:
			_cell(pos).mine = true

	for pos in candidates:
		if _mine_count() >= MINE_COUNT:
			break
		if not _cell(pos).mine:
			_cell(pos).mine = true


func _treasure_mine_candidates() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var pos := treasure_pos + Vector2i(dx, dy)
			if _is_inside(pos) and pos != treasure_pos:
				candidates.append(pos)
	candidates.shuffle()
	return candidates


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
		var chosen: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		current += chosen
		if _is_inside(current) and not route.has(current):
			route.append(current)
	return route


func _candidate_cells(rule: Callable) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			if rule.call(pos):
				candidates.append(pos)
	candidates.shuffle()
	return candidates


func _can_have_mine(pos: Vector2i, route_lookup: Dictionary) -> bool:
	if pos == CENTER or pos == treasure_pos:
		return false
	if _chebyshev(pos, CENTER) <= 1:
		return false
	if route_lookup.has(pos):
		return false
	if _cell(pos).type == CELL_ALTAR or _cell(pos).type == CELL_BONUS:
		return false
	return true


func _calculate_numbers() -> void:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			var count := 0
			for neighbor in _all_neighbors(pos):
				if _cell(neighbor).mine:
					count += 1
			_cell(pos).number = count


func _calculate_treasure_arrows() -> void:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			_cell(pos).treasure_arrow = ""
			if _cell(pos).type != CELL_NORMAL or _cell(pos).mine or int(_cell(pos).number) != 0:
				continue
			if rng.randf() > TREASURE_ARROW_CHANCE:
				continue
			var delta := treasure_pos - pos
			if abs(delta.x) >= abs(delta.y):
				_cell(pos).treasure_arrow = ">" if delta.x > 0 else "<"
			else:
				_cell(pos).treasure_arrow = "v" if delta.y > 0 else "^"


func _validate_map() -> bool:
	if _mine_count() != MINE_COUNT:
		return false
	if altar_positions.size() < ALTAR_COUNT:
		return false
	if bonus_positions.size() < BONUS_COUNT:
		return false
	return _path_exists(CENTER, treasure_pos)


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
			if _cell(neighbor).mine:
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return false


func _probe_cell(pos: Vector2i) -> void:
	if vision <= 0:
		_set_message("No vision clicks left. Move to bonuses or use an altar.")
		return
	if _cell(pos).revealed:
		return
	vision -= 1

	if _cell(pos).mine:
		_cell(pos).revealed = true
		_set_message("Mine revealed at (%d, %d). Vision click does not cost defense." % [pos.x, pos.y])
	elif _cell(pos).number == 0 and _cell(pos).type == CELL_NORMAL:
		_flood_reveal(pos)
		_set_message("Opened a safe area from (%d, %d)." % [pos.x, pos.y])
	else:
		_cell(pos).revealed = true
		_set_message("Revealed (%d, %d)." % [pos.x, pos.y])

	if vision <= 0:
		_set_message(message_label.text + "\nNo vision clicks remain.")
	_update_ui()
	queue_redraw()


func _flood_reveal(start: Vector2i) -> void:
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		_cell(current).revealed = true
		if _cell(current).mine or _cell(current).number != 0:
			continue
		for neighbor in _all_neighbors(current):
			if visited.has(neighbor):
				continue
			if _cell(neighbor).mine:
				continue
			visited[neighbor] = true
			_cell(neighbor).revealed = true
			if _cell(neighbor).number == 0 and _cell(neighbor).type == CELL_NORMAL:
				queue.append(neighbor)


func _try_move(target: Vector2i) -> void:
	if not _is_inside(target) or _manhattan(player_pos, target) != 1:
		return
	if moves <= 0:
		_fail("You ran out of moves.")
		return

	moves -= 1
	player_pos = target
	_cell(player_pos).revealed = true

	if _cell(player_pos).mine:
		defense -= 1
		_cell(player_pos).mine = false
		_calculate_numbers()
		if defense < 0:
			_fail("You stepped on a mine and defense fell below 0.")
			return
		_set_message("Stepped on a mine. Defense -1.")
	else:
		_handle_current_cell()

	if moves <= 0 and not game_over and not game_won:
		_fail("You ran out of moves.")
		return
	_update_ui()
	queue_redraw()


func _handle_current_cell() -> void:
	var cell := _cell(player_pos)
	match cell.type:
		CELL_TREASURE:
			_win("You reached the treasure.")
		CELL_ALTAR:
			if cell.used:
				_set_message("This altar has already been used.")
			else:
				_set_message("You reached an unused altar. Press Enter to reallocate stats.")
		CELL_BONUS:
			if not cell.collected:
				_set_message("You found a bonus treasure. Press Enter to collect +%d unused point(s)." % cell.bonus_points)
			else:
				_set_message("This bonus treasure has already been collected.")
		_:
			_set_message("Moved to (%d, %d)." % [player_pos.x, player_pos.y])


func _collect_bonus_treasure() -> void:
	var cell := _cell(player_pos)
	if cell.type != CELL_BONUS or cell.collected:
		return
	unused_points += cell.bonus_points
	total_bonus_points += cell.bonus_points
	var gained_points: int = cell.bonus_points
	cell.collected = true
	cell.bonus_points = 0
	cell.type = CELL_NORMAL
	_calculate_numbers()
	_set_message("Collected bonus treasure: +%d unused point(s)." % gained_points)
	_update_ui()
	queue_redraw()


func _open_altar_panel() -> void:
	if _cell(player_pos).type != CELL_ALTAR or _cell(player_pos).used:
		return
	altar_panel.visible = true
	altar_exchange_pool = _current_exchange_pool()
	updating_altar_controls = true
	moves_spin.value = moves
	vision_spin.value = vision
	defense_spin.value = defense
	updating_altar_controls = false
	altar_last_valid_build = _capture_altar_build()
	_update_altar_state_label()
	_update_altar_budget()


func _toggle_altar_panel() -> void:
	if _cell(player_pos).type != CELL_ALTAR:
		return
	if _cell(player_pos).used:
		_set_message("This altar has already been used.")
		return
	if altar_panel.visible:
		_apply_altar_build()
	else:
		_open_altar_panel()
		_set_message("Altar opened. Press Enter again or click Apply to consume this altar.")
	_update_ui()
	queue_redraw()


func _apply_altar_build() -> void:
	var build := _capture_altar_build()
	var validation_message := _validate_altar_build(build.moves, build.vision, build.defense)
	if not validation_message.is_empty():
		_set_message(validation_message)
		_update_altar_budget()
		return
	var cost := _build_cost(build.moves, build.vision, build.defense)
	var pool := _altar_budget_pool()
	if cost > pool:
		_set_message("Not enough budget to apply this build.")
		_update_altar_budget()
		return

	moves = build.moves
	vision = build.vision
	defense = build.defense
	unused_points = pool - cost
	_cell(player_pos).used = true
	altar_panel.visible = false
	_set_message("Stats reallocated. This altar is now used.")
	_update_ui()
	queue_redraw()


func _update_altar_budget() -> void:
	if altar_budget_label == null:
		return
	_update_altar_state_label()
	var build := _capture_altar_build()
	var cost := _build_cost(build.moves, build.vision, build.defense)
	var pool := _altar_budget_pool()
	var validation_message := _validate_altar_build(build.moves, build.vision, build.defense)
	var valid := validation_message.is_empty() and cost <= pool
	var status := "Ready" if valid else validation_message
	if cost > pool:
		status = "Not enough budget"
	altar_budget_label.text = "Build cost: %d / %d\nUnused points after apply: %d\nStatus: %s\nMoves: every 5 costs 1\nVision: every 5 costs 1\nDefense: +1 costs 1" % [cost, pool, max(0, pool - cost), status]
	apply_button.disabled = not valid


func _on_altar_spin_changed() -> void:
	if updating_altar_controls:
		return
	var build := _capture_altar_build()
	var cost := _build_cost(build.moves, build.vision, build.defense)
	var validation_message := _validate_altar_build(build.moves, build.vision, build.defense)
	if validation_message.is_empty() and cost <= _altar_budget_pool():
		altar_last_valid_build = build
		_update_altar_budget()
		return
	_restore_altar_build(altar_last_valid_build)
	_update_altar_budget()


func _capture_altar_build() -> Dictionary:
	return {
		"moves": int(moves_spin.value),
		"vision": int(vision_spin.value),
		"defense": int(defense_spin.value)
	}


func _restore_altar_build(build: Dictionary) -> void:
	if build.is_empty():
		return
	updating_altar_controls = true
	moves_spin.value = build.moves
	vision_spin.value = build.vision
	defense_spin.value = build.defense
	updating_altar_controls = false


func _validate_altar_build(build_moves: int, build_vision: int, build_defense: int) -> String:
	if build_moves < 1 or build_moves > 50:
		return "Moves must be between 1 and 50."
	if build_vision < 0 or build_vision > 50:
		return "Vision must be between 0 and 50."
	if build_defense < 0 or build_defense > 20:
		return "Defense must be between 0 and 20."
	return ""


func _update_altar_state_label() -> void:
	if altar_state_label == null:
		return
	altar_state_label.text = "Current Stats\nMoves: %d  Vision: %d  Defense: %d\nBonus points collected: %d\nUnused points: %d\nExchange budget: %d\nThis altar can be used once." % [
		moves,
		vision,
		defense,
		total_bonus_points,
		unused_points,
		_altar_budget_pool()
	]


func _build_cost(build_moves: int, build_vision: int, build_defense: int) -> int:
	return ceili(float(build_moves) / 5.0) + ceili(float(build_vision) / 5.0) + build_defense


func _current_exchange_pool() -> int:
	return _build_cost(moves, vision, defense) + unused_points


func _altar_budget_pool() -> int:
	if altar_panel != null and altar_panel.visible:
		return altar_exchange_pool
	return _current_exchange_pool()


func _draw() -> void:
	_draw_header()
	_draw_grid()


func _draw_header() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(24, 38), "Click hidden cells to spend Vision; WASD/arrow keys move; click revealed adjacent cells to move; R restarts", HORIZONTAL_ALIGNMENT_LEFT, 1000, 16, Color(0.9, 0.9, 0.9))


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
	if cell.revealed or pos == player_pos:
		color = Color(0.72, 0.73, 0.72)
		if cell.type == CELL_START:
			color = Color(0.28, 0.78, 0.82)
		elif cell.type == CELL_ALTAR:
			color = Color(0.58, 0.40, 0.76) if not cell.used else Color(0.34, 0.27, 0.42)
		elif cell.type == CELL_TREASURE:
			color = Color(0.94, 0.72, 0.18)
		elif cell.type == CELL_BONUS:
			color = Color(0.24, 0.62, 0.34) if not cell.collected else Color(0.32, 0.42, 0.34)
	draw_rect(rect.grow(-1), color, true)


func _draw_cell_content(rect: Rect2, pos: Vector2i, font: Font) -> void:
	var cell := _cell(pos)
	if pos == player_pos:
		draw_circle(rect.get_center(), cell_size * 0.32, Color(0.08, 0.34, 0.9))
		_draw_centered_text(font, rect, "P", 20, Color.WHITE)
		return
	if not cell.revealed:
		return
	if cell.mine:
		_draw_mine(rect.get_center(), cell_size * 0.23)
		_draw_centered_text(font, rect, "M", 15, Color.WHITE)
		return
	match cell.type:
		CELL_ALTAR:
			_draw_diamond(rect.get_center(), cell_size * 0.34, Color(0.46, 0.12, 0.76))
			_draw_centered_text(font, rect, "A", 18, Color.WHITE)
		CELL_TREASURE:
			_draw_star(rect.get_center(), cell_size * 0.34, Color(1.0, 0.9, 0.1))
			_draw_centered_text(font, rect, "T", 18, Color(0.2, 0.12, 0.0))
		CELL_BONUS:
			draw_circle(rect.get_center(), cell_size * 0.28, Color(0.1, 0.72, 0.24))
			_draw_centered_text_at(font, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.55)), "B", 13, Color.WHITE)
			var bonus_text := str(cell.bonus_points) if not cell.collected else ""
			if not bonus_text.is_empty():
				_draw_centered_text_at(font, Rect2(rect.position + Vector2(0, rect.size.y * 0.48), Vector2(rect.size.x, rect.size.y * 0.5)), bonus_text, 12, Color.WHITE)
		_:
			var number: int = cell.number
			if number > 0:
				_draw_centered_text(font, rect, str(number), 18, _number_color(number))
			elif not String(cell.treasure_arrow).is_empty():
				_draw_centered_text(font, rect, String(cell.treasure_arrow), 18, Color(0.1, 0.55, 0.22))


func _draw_mine(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color(0.05, 0.05, 0.05))
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]:
		draw_line(center, center + direction * radius * 1.45, Color(0.05, 0.05, 0.05), 2.0)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0)
	], color)


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
	stats_label.text = "Moves: %d\nVision clicks: %d\nDefense: %d\nUnused points: %d\nBonus points collected: %d\nMines: %d\nTreasure: (%d, %d)" % [
		moves,
		vision,
		defense,
		unused_points,
		total_bonus_points,
		_mine_count(),
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
	_reveal_endgame_map()
	_set_message("[color=#d03030]Defeat: %s[/color]\nPress R to restart." % reason)
	_update_ui()
	queue_redraw()


func _win(reason: String) -> void:
	game_over = true
	game_won = true
	altar_panel.visible = false
	_reveal_endgame_map()
	_set_message("[color=#2c9f45]Victory: %s[/color]\nPress R to restart." % reason)
	_update_ui()
	queue_redraw()


func _reveal_endgame_map() -> void:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var pos := Vector2i(x, y)
			if _cell(pos).mine or _cell(pos).type in [CELL_ALTAR, CELL_TREASURE, CELL_BONUS]:
				_cell(pos).revealed = true


func _mine_count() -> int:
	var count := 0
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if _cell(Vector2i(x, y)).mine:
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


func _is_far_from_existing(pos: Vector2i, existing: Array[Vector2i], distance: int) -> bool:
	for other in existing:
		if _manhattan(pos, other) < distance:
			return false
	return true


func signi(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0
