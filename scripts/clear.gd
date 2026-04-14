extends Control

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.04, 1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var l := Label.new()
	l.text = "脱出成功"
	l.add_theme_font_size_override("font_size", 72)
	l.add_theme_color_override("font_color", Color(0.5, 0.95, 0.5))
	l.position = Vector2(500, 200)
	add_child(l)

	var v := VBoxContainer.new()
	v.position = Vector2(540, 360)
	v.add_theme_constant_override("separation", 16)
	add_child(v)

	var b1 := Button.new()
	b1.text = "もう一度プレイ"
	b1.custom_minimum_size = Vector2(220, 48)
	b1.pressed.connect(_replay)
	v.add_child(b1)

	var b2 := Button.new()
	b2.text = "タイトルへ戻る"
	b2.custom_minimum_size = Vector2(220, 48)
	b2.pressed.connect(_to_title)
	v.add_child(b2)

func _replay() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _to_title() -> void:
	get_tree().change_scene_to_file("res://scenes/Title.tscn")
