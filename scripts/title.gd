extends Control

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06, 1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "隠密脱出 MVP"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.position = Vector2(440, 160)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "暗闇を抜け、5階層を踏破せよ"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	subtitle.position = Vector2(490, 240)
	add_child(subtitle)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(540, 330)
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)

	var b1 := Button.new()
	b1.text = "ゲーム開始"
	b1.custom_minimum_size = Vector2(220, 48)
	b1.pressed.connect(_on_start)
	vbox.add_child(b1)

	var b2 := Button.new()
	b2.text = "操作説明"
	b2.custom_minimum_size = Vector2(220, 48)
	b2.pressed.connect(_show_controls)
	vbox.add_child(b2)

	var b3 := Button.new()
	b3.text = "終了"
	b3.custom_minimum_size = Vector2(220, 48)
	b3.pressed.connect(_on_quit)
	vbox.add_child(b3)

	if not GameState.has_seen_controls:
		GameState.has_seen_controls = true
		call_deferred("_show_controls")

func _on_start() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_quit() -> void:
	get_tree().quit()

func _show_controls() -> void:
	var d := AcceptDialog.new()
	d.title = "操作説明"
	d.dialog_text = "■ 操作\n  WASD : 移動\n  マウス : 向き\n  左クリック(押下) : 走る\n  右クリック(押下) : 忍び足\n  Esc : ポーズ\n  階段/脱出口 : 接触で遷移\n\n■ 音の到達範囲 (聴覚型基準)\n  走る : 半径10タイル\n  歩く : 半径4タイル\n  忍び足 : 0 (無音)\n  ※ 壁1枚で -2 タイル\n\n■ 敵の縁取り\n  暗い : 未発見\n  黄   : 警戒\n  赤   : 発見"
	d.ok_button_text = "閉じる"
	add_child(d)
	d.popup_centered(Vector2i(520, 460))
