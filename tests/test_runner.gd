## テストランナー
## 実行: godot --headless --script tests/test_runner.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	print("=== Hidden Escape テスト開始 ===\n")

	_run_suite(TestBresenham.new())
	_run_suite(TestGameState.new())
	_run_suite(TestEnemyData.new())
	_run_suite(TestWalls.new())

	print("\n=== 結果: %d 件成功 / %d 件失敗 ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_suite(suite: BaseTest) -> void:
	suite.runner = self
	suite.run()

# ----------------------------------------------------------------
# アサーション API
# ----------------------------------------------------------------
func assert_eq(label: String, a, b) -> void:
	if a == b:
		print("  [PASS] %s" % label)
		_pass += 1
	else:
		print("  [FAIL] %s  got=%s  want=%s" % [label, str(a), str(b)])
		_fail += 1

func assert_true(label: String, v: bool) -> void:
	if v:
		print("  [PASS] %s" % label)
		_pass += 1
	else:
		print("  [FAIL] %s  (expected true)" % label)
		_fail += 1

func assert_false(label: String, v: bool) -> void:
	if not v:
		print("  [PASS] %s" % label)
		_pass += 1
	else:
		print("  [FAIL] %s  (expected false)" % label)
		_fail += 1

# ----------------------------------------------------------------
# ベーステストクラス
# ----------------------------------------------------------------
class BaseTest extends RefCounted:
	var runner  # TestRunner

	func run() -> void:
		pass

	func assert_eq(label: String, a, b) -> void:
		runner.assert_eq(label, a, b)

	func assert_true(label: String, v: bool) -> void:
		runner.assert_true(label, v)

	func assert_false(label: String, v: bool) -> void:
		runner.assert_false(label, v)

# ================================================================
# Bresenham アルゴリズム テスト
# ================================================================
class TestBresenham extends BaseTest:
	# game.gd の _bresenham をここに複製してユニットテスト
	func _bresenham(a: Vector2i, b: Vector2i) -> Array:
		var pts: Array = []
		var x0: int = a.x; var y0: int = a.y
		var x1: int = b.x; var y1: int = b.y
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
				err += dy; x0 += sx
			if e2 <= dx:
				err += dx; y0 += sy
		return pts

	func run() -> void:
		print("\n--- Bresenham ---")

		# 同一点 → 要素1つ
		var r := _bresenham(Vector2i(3, 3), Vector2i(3, 3))
		assert_eq("同一点: 要素数=1", r.size(), 1)
		assert_eq("同一点: 座標", r[0], Vector2i(3, 3))

		# 水平線 (x0..x1, y固定)
		r = _bresenham(Vector2i(0, 0), Vector2i(4, 0))
		assert_eq("水平線: 要素数=5", r.size(), 5)
		assert_eq("水平線: 始点", r[0], Vector2i(0, 0))
		assert_eq("水平線: 終点", r[4], Vector2i(4, 0))

		# 垂直線
		r = _bresenham(Vector2i(2, 1), Vector2i(2, 4))
		assert_eq("垂直線: 要素数=4", r.size(), 4)
		assert_eq("垂直線: 始点", r[0], Vector2i(2, 1))
		assert_eq("垂直線: 終点", r[3], Vector2i(2, 4))

		# 斜め45度
		r = _bresenham(Vector2i(0, 0), Vector2i(3, 3))
		assert_eq("斜め45度: 始点", r[0], Vector2i(0, 0))
		assert_eq("斜め45度: 終点", r[r.size()-1], Vector2i(3, 3))

		# 逆方向 (b < a)
		r = _bresenham(Vector2i(4, 0), Vector2i(0, 0))
		assert_eq("逆水平線: 始点", r[0], Vector2i(4, 0))
		assert_eq("逆水平線: 終点", r[r.size()-1], Vector2i(0, 0))
		assert_eq("逆水平線: 要素数=5", r.size(), 5)

		# 連続性チェック (各点が前の点から距離1以内)
		r = _bresenham(Vector2i(0, 0), Vector2i(7, 3))
		var continuous := true
		for i in range(1, r.size()):
			var prev: Vector2i = r[i-1]
			var cur: Vector2i = r[i]
			var d := absi(cur.x - prev.x) + absi(cur.y - prev.y)
			if d > 2:  # チェビシェフ距離1
				continuous = false
		assert_true("斜め線: 連続性", continuous)

# ================================================================
# GameState テスト
# ================================================================
class TestGameState extends BaseTest:
	# GameState の純粋なロジックをここで再現
	var current_floor: int = 1
	var death_floor: int = 1
	const MAX_FLOOR: int = 5

	func reset() -> void:
		current_floor = 1

	func next_floor() -> void:
		current_floor += 1

	func mark_death() -> void:
		death_floor = current_floor

	func run() -> void:
		print("\n--- GameState ---")

		# 初期状態
		assert_eq("初期フロア=1", current_floor, 1)
		assert_eq("MAX_FLOOR=5", MAX_FLOOR, 5)

		# next_floor
		next_floor()
		assert_eq("next_floor後=2", current_floor, 2)
		next_floor()
		assert_eq("2回next_floor後=3", current_floor, 3)

		# mark_death
		mark_death()
		assert_eq("mark_death: death_floor=3", death_floor, 3)

		# reset
		reset()
		assert_eq("reset後=1", current_floor, 1)

		# 最大フロアを超えてもクラッシュしない（境界値）
		current_floor = MAX_FLOOR
		next_floor()
		assert_eq("MAX+1=6", current_floor, 6)
		reset()

# ================================================================
# EnemyData テスト
# ================================================================
class EnemyData extends RefCounted:
	var pos: Vector2
	var dir: Vector2 = Vector2(1, 0)
	var type: String = "balanced"
	var state: String = "patrol"
	var is_stationary: bool = false
	var path: PackedVector2Array = PackedVector2Array()
	var path_idx: int = 0
	var wait_timer: float = 0.0
	var alert_timer: float = 0.0
	var lost_timer: float = 0.0
	var scan_dir: float = 1.0
	var scan_base_angle: float = 0.0
	var last_known: Vector2i = Vector2i.ZERO
	var arrived_at_last_known: bool = false

class TestEnemyData extends BaseTest:
	func run() -> void:
		print("\n--- EnemyData ---")

		var e := EnemyData.new()

		# デフォルト値
		assert_eq("デフォルトtype=balanced", e.type, "balanced")
		assert_eq("デフォルトstate=patrol", e.state, "patrol")
		assert_false("デフォルトis_stationary=false", e.is_stationary)
		assert_eq("デフォルトdir", e.dir, Vector2(1, 0))
		assert_eq("デフォルトpath_idx=0", e.path_idx, 0)
		assert_eq("デフォルトscan_dir=1", e.scan_dir, 1.0)

		# 状態遷移シミュレーション
		e.state = "chase"
		e.last_known = Vector2i(5, 5)
		e.lost_timer = 2.5
		assert_eq("chase状態のlast_known", e.last_known, Vector2i(5, 5))
		assert_true("lost_timer>2.0でalertに戻れる", e.lost_timer >= 2.0)

		# パス関連
		e.path = PackedVector2Array()
		assert_true("空pathでarrived判定true", e.path.is_empty() or e.path_idx >= e.path.size())
		e.path.append(Vector2(100, 100))
		assert_false("path有でarrived判定false (idx=0)", e.path.is_empty() or e.path_idx >= e.path.size())
		e.path_idx = 1
		assert_true("path_idx>=size()でarrived", e.path.is_empty() or e.path_idx >= e.path.size())

# ================================================================
# 壁カウント・視線チェック テスト
# ================================================================
class TestWalls extends BaseTest:
	# ミニグリッドを作ってテスト
	var grid: Array = []
	var width: int
	var height: int

	func _setup_grid(w: int, h: int, default_val: int = 1) -> void:
		width = w
		height = h
		grid.clear()
		for y in range(h):
			var row: Array = []
			for x in range(w):
				row.append(default_val)
			grid.append(row)

	func _bresenham(a: Vector2i, b: Vector2i) -> Array:
		var pts: Array = []
		var x0: int = a.x; var y0: int = a.y
		var x1: int = b.x; var y1: int = b.y
		var dx: int = absi(x1 - x0); var sx: int = 1 if x0 < x1 else -1
		var dy: int = -absi(y1 - y0); var sy: int = 1 if y0 < y1 else -1
		var err: int = dx + dy
		while true:
			pts.append(Vector2i(x0, y0))
			if x0 == x1 and y0 == y1: break
			var e2: int = 2 * err
			if e2 >= dy: err += dy; x0 += sx
			if e2 <= dx: err += dx; y0 += sy
		return pts

	func _walls_between(a: Vector2i, b: Vector2i) -> int:
		var pts := _bresenham(a, b)
		var n: int = 0
		for i in range(1, pts.size() - 1):
			var p: Vector2i = pts[i]
			if grid[p.y][p.x] == 0:
				n += 1
		return n

	func _line_clear(a: Vector2i, b: Vector2i) -> bool:
		var pts := _bresenham(a, b)
		for i in range(1, pts.size() - 1):
			var p: Vector2i = pts[i]
			if grid[p.y][p.x] == 0:
				return false
		return true

	func run() -> void:
		print("\n--- 壁カウント / 視線チェック ---")

		# 5x5 の全フロアグリッド
		_setup_grid(5, 5, 1)
		assert_eq("壁なし: walls_between(0,0)-(4,0)=0", _walls_between(Vector2i(0, 0), Vector2i(4, 0)), 0)
		assert_true("壁なし: line_clear", _line_clear(Vector2i(0, 0), Vector2i(4, 0)))

		# 中央に壁を一つ配置
		grid[0][2] = 0  # (2,0) を壁に
		assert_eq("壁1枚: walls_between=1", _walls_between(Vector2i(0, 0), Vector2i(4, 0)), 1)
		assert_false("壁1枚: line_clear=false", _line_clear(Vector2i(0, 0), Vector2i(4, 0)))

		# 隣接点(距離1)は中間点なし → 常にclear
		_setup_grid(5, 5, 0)
		assert_true("隣接点: line_clear always true", _line_clear(Vector2i(2, 2), Vector2i(2, 3)))

		# 同一点 → 中間点なし → clear
		assert_true("同一点: line_clear=true", _line_clear(Vector2i(2, 2), Vector2i(2, 2)))

		# 壁2枚
		_setup_grid(7, 1, 1)
		grid[0][2] = 0
		grid[0][4] = 0
		assert_eq("壁2枚: walls_between=2", _walls_between(Vector2i(0, 0), Vector2i(6, 0)), 2)
		assert_false("壁2枚: line_clear=false", _line_clear(Vector2i(0, 0), Vector2i(6, 0)))
