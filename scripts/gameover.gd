extends Control

func _ready() -> void:
	# headlessモードなら即リトライ
	if DisplayServer.get_name() == "headless":
		print("[AUTO] game over → retrying...")
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.02, 1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var l := Label.new()
	l.text = "死亡"
	l.add_theme_font_size_override("font_size", 72)
	l.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
	l.position = Vector2(560, 180)
	add_child(l)

	var l2 := Label.new()
	l2.text = "%d 階で力尽きた" % GameState.death_floor
	l2.add_theme_font_size_override("font_size", 24)
	l2.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	l2.position = Vector2(540, 290)
	add_child(l2)

	var v := VBoxContainer.new()
	v.position = Vector2(540, 360)
	v.add_theme_constant_override("separation", 16)
	add_child(v)

	var b1 := Button.new()
	b1.text = "再挑戦 (1層から)"
	b1.custom_minimum_size = Vector2(220, 48)
	b1.pressed.connect(_retry)
	v.add_child(b1)

	var b2 := Button.new()
	b2.text = "タイトルへ戻る"
	b2.custom_minimum_size = Vector2(220, 48)
	b2.pressed.connect(_to_title)
	v.add_child(b2)

func _retry() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _to_title() -> void:
	get_tree().change_scene_to_file("res://scenes/Title.tscn")
