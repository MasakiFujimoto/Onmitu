extends Node2D

# ----------------------------------------------------------------
# Hidden Escape MVP - core game scene.
# Map generation, FOV (Bresenham), sound propagation, enemy AI,
# rendering, UI, pause menu — all in one file for the MVP.
# ----------------------------------------------------------------

const TILE: int = 20
const PLAYER_VISION_RANGE: int = 6
const PLAYER_HALF_ANGLE: float = 0.39269908  # 22.5 deg

# Per-floor parameters (5 floors).
const FLOOR_DATA := [
	{"w":40,"h":30,"rmin":5,"rmax":6,"smin":4,"smax":8,"emin":2,"emax":3,"comp":"balanced_only"},
	{"w":50,"h":40,"rmin":7,"rmax":9,"smin":4,"smax":10,"emin":3,"emax":5,"comp":"mixed_start"},
	{"w":60,"h":45,"rmin":9,"rmax":11,"smin":5,"smax":12,"emin":5,"emax":7,"comp":"mixed"},
	{"w":70,"h":55,"rmin":11,"rmax":13,"smin":5,"smax":14,"emin":7,"emax":9,"comp":"spec_heavy"},
	{"w":80,"h":60,"rmin":13,"rmax":16,"smin":6,"smax":15,"emin":9,"emax":12,"comp":"spec_heavy"},
]

# ---- Enemy data (inner class) ----
class EnemyData extends RefCounted:
	var pos: Vector2
	var dir: Vector2 = Vector2(1, 0)
	var type: String = "balanced"     # visual / hearing / balanced
	var state: String = "patrol"      # patrol / alert / chase / search
	var is_stationary: bool = false
	var path: PackedVector2Array = PackedVector2Array()
	var path_idx: int = 0
	var wait_timer: float = 0.0
	var alert_timer: float = 0.0
	var search_timer: float = 0.0
	var scan_dir: float = 1.0
	var scan_base_angle: float = 0.0
	var last_known: Vector2i = Vector2i.ZERO
	var search_origin: Vector2i = Vector2i.ZERO

# ---- Map / state ----
var grid: Array = []          # grid[y][x] : 0=wall, 1=floor
var width: int
var height: int
var rooms: Array = []         # Array[Rect2i]
var astar: AStarGrid2D

var player_pos: Vector2
var player_dir: Vector2 = Vector2(1, 0)
var move_mode: String = "walk"
var noise_radius_now: int = 0
var visited: Dictionary = {}      # Vector2i -> true
var visible_now: Dictionary = {}  # Vector2i -> true

var stair_tile: Vector2i
var enemies: Array = []   # Array[EnemyData]

var paused: bool = false
var pause_menu: Control = null

var camera: Camera2D
var ui_layer: CanvasLayer
var floor_label: Label
var heartbeat_overlay: ColorRect

# Player movement speeds in px/sec.
const SPEED_WALK: float = 95.0
const SPEED_RUN: float = 165.0
const SPEED_SNEAK: float = 55.0

# ----------------------------------------------------------------
func _ready() -> void:
	randomize()
	_build_floor()
	_setup_camera_and_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func _process(delta: float) -> void:
	if paused:
		return
	_handle_player_input(delta)
	_compute_player_visibility()
	_update_enemies(delta)
	if _check_death():
		return
	if _check_stair():
		return
	_update_ui(delta)
	_update_camera()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if pause_menu == null:
				_open_pause()
			else:
				_close_pause()

# ================================================================
# Map generation
# ================================================================
func _build_floor() -> void:
	var data: Dictionary = FLOOR_DATA[GameState.current_floor - 1]
	width = int(data.w)
	height = int(data.h)
	_generate_map(data)
	_place_enemies(data)
	visited.clear()
	visible_now.clear()

func _generate_map(data: Dictionary) -> void:
	grid.clear()
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(0)
		grid.append(row)

	rooms.clear()
	var target_rooms: int = randi_range(int(data.rmin), int(data.rmax))
	var attempts: int = 0
	while rooms.size() < target_rooms and attempts < 400:
		attempts += 1
		var rw: int = randi_range(int(data.smin), int(data.smax))
		var rh: int = randi_range(int(data.smin), int(data.smax))
		var rx: int = randi_range(2, width - rw - 3)
		var ry: int = randi_range(2, height - rh - 3)
		var r := Rect2i(rx, ry, rw, rh)
		var ok: bool = true
		for other in rooms:
			var ex := Rect2i(other.position.x - 1, other.position.y - 1, other.size.x + 2, other.size.y + 2)
			if ex.intersects(r):
				ok = false
				break
		if ok:
			rooms.append(r)

	for r in rooms:
		for y in range(r.position.y, r.position.y + r.size.y):
			for x in range(r.position.x, r.position.x + r.size.x):
				grid[y][x] = 1

	# MST connection
	var connected: Array = [0]
	var unconnected: Array = []
	for i in range(1, rooms.size()):
		unconnected.append(i)
	while unconnected.size() > 0:
		var best_a: int = -1
		var best_b: int = -1
		var best_d: float = INF
		for a in connected:
			for b in unconnected:
				var d: float = Vector2(rooms[a].get_center() - rooms[b].get_center()).length()
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		_carve_corridor(rooms[best_a].get_center(), rooms[best_b].get_center())
		connected.append(best_b)
		unconnected.erase(best_b)

	# extra loops (~20%)
	var extras: int = int(rooms.size() * 0.2)
	for i in range(extras):
		var a: int = randi() % rooms.size()
		var b: int = randi() % rooms.size()
		if a != b:
			_carve_corridor(rooms[a].get_center(), rooms[b].get_center())

	# A*
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in range(height):
		for x in range(width):
			astar.set_point_solid(Vector2i(x, y), grid[y][x] == 0)

	# spawn
	var spawn_tile: Vector2i = rooms[0].get_center()
	if grid[spawn_tile.y][spawn_tile.x] == 0:
		spawn_tile = _find_floor_near(spawn_tile)
	player_pos = Vector2(spawn_tile.x + 0.5, spawn_tile.y + 0.5) * TILE

	# stair = farthest reachable room center
	var best_room: int = 1 if rooms.size() > 1 else 0
	var best_len: int = 0
	for i in range(1, rooms.size()):
		var c: Vector2i = rooms[i].get_center()
		if grid[c.y][c.x] == 0:
			c = _find_floor_near(c)
		var p := astar.get_id_path(spawn_tile, c)
		if p.size() > best_len:
			best_len = p.size()
			best_room = i
	stair_tile = rooms[best_room].get_center()
	if grid[stair_tile.y][stair_tile.x] == 0:
		stair_tile = _find_floor_near(stair_tile)

func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	var x: int = a.x
	var y: int = a.y
	if randi() % 2 == 0:
		while x != b.x:
			grid[y][x] = 1
			x += 1 if b.x > x else -1
		while y != b.y:
			grid[y][x] = 1
			y += 1 if b.y > y else -1
	else:
		while y != b.y:
			grid[y][x] = 1
			y += 1 if b.y > y else -1
		while x != b.x:
			grid[y][x] = 1
			x += 1 if b.x > x else -1
	grid[b.y][b.x] = 1

func _find_floor_near(c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := c + Vector2i(dx, dy)
				if t.x >= 0 and t.y >= 0 and t.x < width and t.y < height:
					if grid[t.y][t.x] == 1:
						return t
	return c

# ================================================================
# Enemy spawning
# ================================================================
func _place_enemies(data: Dictionary) -> void:
	enemies.clear()
	var count: int = randi_range(int(data.emin), int(data.emax))
	var spawn_center: Vector2i = rooms[0].get_center()
	var pool: Array = []
	for i in range(1, rooms.size()):
		var c: Vector2i = rooms[i].get_center()
		if Vector2(c - spawn_center).length() > 6.0:
			pool.append(i)
	if pool.is_empty():
		for i in range(1, rooms.size()):
			pool.append(i)
	pool.shuffle()

	var type_table: Array
	match String(data.comp):
		"balanced_only":
			type_table = ["balanced"]
		"mixed_start":
			type_table = ["balanced", "balanced", "visual", "hearing"]
		"mixed":
			type_table = ["balanced", "visual", "hearing", "visual", "hearing"]
		"spec_heavy":
			type_table = ["visual", "hearing", "visual", "hearing", "balanced"]
		_:
			type_table = ["balanced"]

	for i in range(count):
		var e := EnemyData.new()
		var room_i: int = pool[i % pool.size()]
		var c2: Vector2i = rooms[room_i].get_center()
		if grid[c2.y][c2.x] == 0:
			c2 = _find_floor_near(c2)
		e.pos = Vector2(c2.x + 0.5, c2.y + 0.5) * TILE
		e.type = type_table[i % type_table.size()]
		# stationary chance — biased toward visual
		if e.type == "visual":
			e.is_stationary = randf() < 0.5
		else:
			e.is_stationary = randf() < 0.2
		e.scan_base_angle = e.dir.angle()
		enemies.append(e)

# ================================================================
# Player
# ================================================================
func _handle_player_input(delta: float) -> void:
	var input_vec := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_vec.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_vec.y += 1
	if Input.is_key_pressed(KEY_A):
		input_vec.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_vec.x += 1
	if input_vec.length() > 0:
		input_vec = input_vec.normalized()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		move_mode = "run"
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		move_mode = "sneak"
	else:
		move_mode = "walk"

	var sp: float
	var noise: int
	match move_mode:
		"run":
			sp = SPEED_RUN
			noise = 10
		"sneak":
			sp = SPEED_SNEAK
			noise = 0
		_:
			sp = SPEED_WALK
			noise = 4

	if input_vec.length() == 0:
		noise_radius_now = 0
	else:
		noise_radius_now = noise
		var step: Vector2 = input_vec * sp * delta
		var target := player_pos + step
		if _can_walk_pos(target):
			player_pos = target
		else:
			var tx := player_pos + Vector2(step.x, 0)
			if _can_walk_pos(tx):
				player_pos = tx
			var ty := player_pos + Vector2(0, step.y)
			if _can_walk_pos(ty):
				player_pos = ty

	# face cursor
	var mp := get_global_mouse_position()
	var diff := mp - player_pos
	if diff.length() > 2.0:
		player_dir = diff.normalized()

func _can_walk_pos(p: Vector2) -> bool:
	var r: float = TILE * 0.32
	var corners: Array[Vector2] = [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]
	for c in corners:
		var q := p + c
		var t := Vector2i(int(floor(q.x / TILE)), int(floor(q.y / TILE)))
		if t.x < 0 or t.y < 0 or t.x >= width or t.y >= height:
			return false
		if grid[t.y][t.x] == 0:
			return false
	return true

func _player_tile() -> Vector2i:
	return Vector2i(int(player_pos.x / TILE), int(player_pos.y / TILE))

# ================================================================
# Visibility / FOV
# ================================================================
func _compute_player_visibility() -> void:
	visible_now.clear()
	var origin := _player_tile()
	visible_now[origin] = true
	visited[origin] = true
	for dy in range(-PLAYER_VISION_RANGE, PLAYER_VISION_RANGE + 1):
		for dx in range(-PLAYER_VISION_RANGE, PLAYER_VISION_RANGE + 1):
			var t := origin + Vector2i(dx, dy)
			if t.x < 0 or t.y < 0 or t.x >= width or t.y >= height:
				continue
			var off := Vector2(dx, dy)
			if off.length() > float(PLAYER_VISION_RANGE):
				continue
			if off.length() > 0.001:
				var ang: float = absf(off.normalized().angle_to(player_dir))
				if ang > PLAYER_HALF_ANGLE:
					continue
			if _line_clear(origin, t):
				visible_now[t] = true
				visited[t] = true

func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	# True if no wall blocks between a (exclusive) and b (inclusive at end, walls along intermediate).
	var pts := _bresenham(a, b)
	# allow endpoints to be on floor cells; check intermediate cells only.
	for i in range(1, pts.size() - 1):
		var p: Vector2i = pts[i]
		if grid[p.y][p.x] == 0:
			return false
	return true

func _bresenham(a: Vector2i, b: Vector2i) -> Array:
	var pts: Array = []
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y
	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		pts.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return pts

func _walls_between(a: Vector2i, b: Vector2i) -> int:
	var pts := _bresenham(a, b)
	var n: int = 0
	for i in range(1, pts.size() - 1):
		var p: Vector2i = pts[i]
		if grid[p.y][p.x] == 0:
			n += 1
	return n

# ================================================================
# Enemies
# ================================================================
func _update_enemies(delta: float) -> void:
	var pt := _player_tile()
	for e in enemies:
		_update_enemy(e, delta, pt)

func _update_enemy(e: EnemyData, delta: float, pt: Vector2i) -> void:
	var et: Vector2i = Vector2i(int(e.pos.x / TILE), int(e.pos.y / TILE))

	# ---- detection: vision ----
	var detect_kind: String = ""
	var detect_ratio: float = 1.0  # fraction of effective range (smaller = closer)

	if e.type != "hearing":
		var range_t: float
		var half_a: float
		if e.type == "visual":
			range_t = 12.0
			half_a = 0.65449847  # 37.5°
		else:
			range_t = 7.0
			half_a = 0.52359878  # 30°
		if e.state == "chase" or e.state == "search":
			range_t *= 1.2
		var off := Vector2(pt - et)
		var d: float = off.length()
		if d <= range_t:
			var ang_ok: bool = true
			if d > 0.01:
				var ang: float = absf(off.normalized().angle_to(e.dir))
				if ang > half_a:
					ang_ok = false
			if ang_ok and _line_clear(et, pt):
				detect_kind = "vision"
				detect_ratio = d / range_t

	# ---- detection: hearing ----
	if e.type != "visual" and noise_radius_now > 0:
		var base: float = 0.0
		if e.type == "hearing":
			base = float(noise_radius_now)
		elif e.type == "balanced":
			match move_mode:
				"run":
					base = 7.0
				"walk":
					base = 3.0
				_:
					base = 0.0
		if e.state == "chase" or e.state == "search":
			base *= 1.2
		if base > 0.0:
			var walls: int = _walls_between(et, pt)
			var eff: float = base - float(walls) * 2.0
			var d2: float = Vector2(pt - et).length()
			if eff > 0.0 and d2 <= eff:
				if detect_kind == "" or (d2 / eff) < detect_ratio:
					detect_kind = "audio"
					detect_ratio = d2 / eff

	# ---- apply detection -> state transitions ----
	if detect_kind != "":
		if detect_ratio < 0.8:
			# direct chase
			_enter_chase(e, pt)
		else:
			# alert tier — but if already alert, escalate
			if e.state == "alert":
				_enter_chase(e, pt)
			elif e.state == "patrol":
				e.state = "alert"
				e.alert_timer = 10.0
				var dv := Vector2(pt - et)
				if dv.length() > 0.01:
					e.dir = dv.normalized()

	# ---- behavior per state ----
	match e.state:
		"patrol":
			_do_patrol(e, delta)
		"alert":
			e.alert_timer -= delta
			if e.alert_timer <= 0.0:
				e.state = "patrol"
				e.path = PackedVector2Array()
				e.wait_timer = 0.0
		"chase":
			e.last_known = pt
			_chase_toward(e, pt, delta)
			if et == pt:
				# adjacent kill check is in _check_death
				pass
			elif _arrived_at_path_end(e):
				_enter_search(e, e.last_known)
		"search":
			e.search_timer -= delta
			if e.search_timer <= 0.0:
				e.state = "alert"
				e.alert_timer = 10.0
				e.path = PackedVector2Array()
			else:
				if e.path.is_empty() or _arrived_at_path_end(e):
					var t := _random_floor_around(e.search_origin, 5)
					_request_path(e, t)
				_walk_path(e, delta, 1.0)

func _do_patrol(e: EnemyData, delta: float) -> void:
	if e.is_stationary:
		# slow scanning back and forth
		var ang: float = e.dir.angle()
		ang += e.scan_dir * 0.6 * delta
		var off: float = ang - e.scan_base_angle
		if off > 0.9:
			e.scan_dir = -1.0
		elif off < -0.9:
			e.scan_dir = 1.0
		e.dir = Vector2(cos(ang), sin(ang))
		return

	if e.path.is_empty() or e.path_idx >= e.path.size():
		e.wait_timer -= delta
		if e.wait_timer <= 0.0:
			var ri: int = randi() % rooms.size()
			var c: Vector2i = rooms[ri].get_center()
			if grid[c.y][c.x] == 0:
				c = _find_floor_near(c)
			_request_path(e, c)
			e.wait_timer = randf_range(0.8, 2.0)
	else:
		_walk_path(e, delta, 1.0)

func _enter_chase(e: EnemyData, pt: Vector2i) -> void:
	e.state = "chase"
	e.last_known = pt
	e.path = PackedVector2Array()
	e.path_idx = 0

func _enter_search(e: EnemyData, origin: Vector2i) -> void:
	e.state = "search"
	e.search_origin = origin
	e.search_timer = 8.0
	e.path = PackedVector2Array()
	e.path_idx = 0

func _request_path(e: EnemyData, target: Vector2i) -> void:
	var from := Vector2i(int(e.pos.x / TILE), int(e.pos.y / TILE))
	if target.x < 0 or target.y < 0 or target.x >= width or target.y >= height:
		return
	if grid[target.y][target.x] == 0:
		target = _find_floor_near(target)
	if grid[from.y][from.x] == 0:
		return
	var p := astar.get_id_path(from, target)
	e.path = PackedVector2Array()
	for v in p:
		e.path.append(Vector2(v.x + 0.5, v.y + 0.5) * TILE)
	e.path_idx = 0

func _walk_path(e: EnemyData, delta: float, speed_mult: float) -> void:
	if e.path.is_empty() or e.path_idx >= e.path.size():
		return
	var target: Vector2 = e.path[e.path_idx]
	var sp: float = 60.0 * speed_mult
	var diff: Vector2 = target - e.pos
	var step: float = sp * delta
	if diff.length() <= step:
		e.pos = target
		e.path_idx += 1
	else:
		var nd: Vector2 = diff.normalized()
		e.pos += nd * step
		e.dir = nd

func _chase_toward(e: EnemyData, target: Vector2i, delta: float) -> void:
	var end_tile: Vector2i = _path_end_tile(e)
	if e.path.is_empty() or end_tile != target:
		_request_path(e, target)
	_walk_path(e, delta, 1.5)

func _arrived_at_path_end(e: EnemyData) -> bool:
	return e.path.is_empty() or e.path_idx >= e.path.size()

func _path_end_tile(e: EnemyData) -> Vector2i:
	if e.path.is_empty():
		return Vector2i(-1, -1)
	var p: Vector2 = e.path[e.path.size() - 1]
	return Vector2i(int(p.x / TILE), int(p.y / TILE))

func _random_floor_around(center: Vector2i, radius: int) -> Vector2i:
	for tries in range(20):
		var dx: int = randi_range(-radius, radius)
		var dy: int = randi_range(-radius, radius)
		var t := center + Vector2i(dx, dy)
		if t.x >= 0 and t.y >= 0 and t.x < width and t.y < height and grid[t.y][t.x] == 1:
			return t
	return center

# ================================================================
# Death / stair
# ================================================================
func _check_death() -> bool:
	var pt := _player_tile()
	for e in enemies:
		if e.state != "chase":
			continue
		var et := Vector2i(int(e.pos.x / TILE), int(e.pos.y / TILE))
		var d := et - pt
		if absi(d.x) <= 1 and absi(d.y) <= 1:
			GameState.mark_death()
			GameState.reset()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_tree().change_scene_to_file("res://scenes/GameOver.tscn")
			return true
	return false

func _check_stair() -> bool:
	var pt := _player_tile()
	if pt == stair_tile:
		if GameState.current_floor >= GameState.MAX_FLOOR:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_tree().change_scene_to_file("res://scenes/Clear.tscn")
		else:
			GameState.next_floor()
			get_tree().reload_current_scene()
		return true
	return false

# ================================================================
# Camera / UI / pause
# ================================================================
func _setup_camera_and_ui() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(1.6, 1.6)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 12.0
	camera.position = player_pos
	add_child(camera)

	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	floor_label = Label.new()
	floor_label.position = Vector2(16, 12)
	floor_label.add_theme_font_size_override("font_size", 22)
	floor_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	floor_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	floor_label.add_theme_constant_override("outline_size", 4)
	ui_layer.add_child(floor_label)

	heartbeat_overlay = ColorRect.new()
	heartbeat_overlay.anchor_right = 1.0
	heartbeat_overlay.anchor_bottom = 1.0
	heartbeat_overlay.color = Color(0.6, 0, 0, 0)
	heartbeat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(heartbeat_overlay)

func _update_camera() -> void:
	camera.position = player_pos

func _update_ui(_delta: float) -> void:
	floor_label.text = "Floor %d / %d   [%s]" % [
		GameState.current_floor, GameState.MAX_FLOOR, _mode_label()
	]

	# heartbeat
	var pt := _player_tile()
	var best: float = INF
	for e in enemies:
		var et := Vector2i(int(e.pos.x / TILE), int(e.pos.y / TILE))
		var d: float = Vector2(et - pt).length()
		if d < best:
			best = d
	var alpha: float = 0.0
	var t: float = float(Time.get_ticks_msec()) * 0.001
	if best <= 5.0:
		alpha = 0.32 + 0.18 * sin(t * 9.0)
	elif best <= 8.0:
		alpha = 0.18 + 0.10 * sin(t * 5.5)
	elif best <= 12.0:
		alpha = 0.08 + 0.05 * sin(t * 3.0)
	heartbeat_overlay.color = Color(0.6, 0, 0, max(0.0, alpha))

func _mode_label() -> String:
	match move_mode:
		"run":
			return "走"
		"sneak":
			return "忍"
		_:
			return "歩"

func _open_pause() -> void:
	paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	pause_menu = Control.new()
	pause_menu.anchor_right = 1.0
	pause_menu.anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu.add_child(bg)

	var title := Label.new()
	title.text = "ポーズ"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.position = Vector2(560, 200)
	pause_menu.add_child(title)

	var v := VBoxContainer.new()
	v.position = Vector2(540, 290)
	v.add_theme_constant_override("separation", 14)
	pause_menu.add_child(v)

	var b1 := Button.new()
	b1.text = "再開"
	b1.custom_minimum_size = Vector2(220, 44)
	b1.pressed.connect(_close_pause)
	v.add_child(b1)

	var b2 := Button.new()
	b2.text = "操作説明"
	b2.custom_minimum_size = Vector2(220, 44)
	b2.pressed.connect(_show_controls_dialog)
	v.add_child(b2)

	var b3 := Button.new()
	b3.text = "タイトルへ戻る"
	b3.custom_minimum_size = Vector2(220, 44)
	b3.pressed.connect(_to_title)
	v.add_child(b3)

	ui_layer.add_child(pause_menu)

func _close_pause() -> void:
	paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	if pause_menu != null:
		pause_menu.queue_free()
		pause_menu = null

func _show_controls_dialog() -> void:
	var d := AcceptDialog.new()
	d.title = "操作説明"
	d.dialog_text = "■ 操作\n  WASD : 移動\n  マウス : 向き\n  左クリック(押下) : 走る\n  右クリック(押下) : 忍び足\n  Esc : ポーズ\n\n■ 音の到達範囲 (聴覚型基準)\n  走る : 半径10タイル\n  歩く : 半径4タイル\n  忍び足 : 0 (無音)\n  ※ 壁1枚で -2 タイル"
	d.ok_button_text = "閉じる"
	ui_layer.add_child(d)
	d.popup_centered(Vector2i(520, 420))

func _to_title() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/Title.tscn")

# ================================================================
# Drawing
# ================================================================
func _draw() -> void:
	# tiles
	for y in range(height):
		for x in range(width):
			var t := Vector2i(x, y)
			var rect := Rect2(x * TILE, y * TILE, TILE, TILE)
			var is_floor: bool = grid[y][x] == 1
			if visible_now.has(t):
				if is_floor:
					draw_rect(rect, Color(0.55, 0.50, 0.44))
				else:
					draw_rect(rect, Color(0.20, 0.18, 0.18))
			elif visited.has(t):
				if is_floor:
					draw_rect(rect, Color(0.18, 0.18, 0.20))
				else:
					draw_rect(rect, Color(0.07, 0.07, 0.08))
			else:
				draw_rect(rect, Color(0, 0, 0))

	# stair
	if visited.has(stair_tile) or visible_now.has(stair_tile):
		var sc := Vector2(stair_tile.x + 0.5, stair_tile.y + 0.5) * TILE
		var col := Color(0.35, 0.95, 0.45) if visible_now.has(stair_tile) else Color(0.18, 0.40, 0.22)
		draw_circle(sc, TILE * 0.42, col)
		var inner := Color(0.05, 0.05, 0.05)
		draw_circle(sc, TILE * 0.18, inner)

	# enemies + cones (only currently visible)
	for e in enemies:
		var et := Vector2i(int(e.pos.x / TILE), int(e.pos.y / TILE))
		if not visible_now.has(et):
			continue
		# vision cone
		if e.type != "hearing":
			var range_t: float
			var half_a: float
			if e.type == "visual":
				range_t = 12.0
				half_a = 0.65449847
			else:
				range_t = 7.0
				half_a = 0.52359878
			if e.state == "chase" or e.state == "search":
				range_t *= 1.2
			var cone_col: Color
			if e.state == "patrol":
				cone_col = Color(1, 1, 1, 0.15)
			elif e.state == "alert":
				cone_col = Color(1, 0.9, 0.2, 0.25)
			else:
				cone_col = Color(1, 0.3, 0.2, 0.35)
			var pts := PackedVector2Array()
			pts.append(e.pos)
			var steps: int = 18
			for i in range(steps + 1):
				var tt: float = float(i) / float(steps)
				var a: float = e.dir.angle() + lerp(-half_a, half_a, tt)
				pts.append(e.pos + Vector2(cos(a), sin(a)) * range_t * float(TILE))
			draw_colored_polygon(pts, cone_col)

		# body + ring
		var ring_col: Color
		if e.state == "patrol":
			ring_col = Color(0.55, 0.55, 0.55, 0.7)
		elif e.state == "alert":
			ring_col = Color(1, 0.9, 0.2, 0.95)
		else:
			ring_col = Color(1, 0.25, 0.2, 1.0)
		var body_col: Color
		match e.type:
			"visual":
				body_col = Color(0.30, 0.30, 0.55)
			"hearing":
				body_col = Color(0.45, 0.30, 0.50)
			_:
				body_col = Color(0.36, 0.28, 0.26)
		draw_circle(e.pos, TILE * 0.44, ring_col)
		draw_circle(e.pos, TILE * 0.36, body_col)

	# player
	# faint vision cone
	var p_pts := PackedVector2Array()
	p_pts.append(player_pos)
	var psteps: int = 16
	for i in range(psteps + 1):
		var tt2: float = float(i) / float(psteps)
		var a2: float = player_dir.angle() + lerp(-PLAYER_HALF_ANGLE, PLAYER_HALF_ANGLE, tt2)
		p_pts.append(player_pos + Vector2(cos(a2), sin(a2)) * float(PLAYER_VISION_RANGE) * float(TILE))
	draw_colored_polygon(p_pts, Color(1, 1, 0.7, 0.05))

	draw_circle(player_pos, TILE * 0.36, Color(0.95, 0.95, 0.95))
	draw_line(player_pos, player_pos + player_dir * float(TILE) * 0.55, Color(1, 1, 0.6), 2.0)

	# custom mouse cursor
	var mp := get_global_mouse_position()
	var cs: float = 6.0
	draw_line(mp + Vector2(-cs, 0), mp + Vector2(cs, 0), Color(1, 1, 1, 0.9), 1.5)
	draw_line(mp + Vector2(0, -cs), mp + Vector2(0, cs), Color(1, 1, 1, 0.9), 1.5)
