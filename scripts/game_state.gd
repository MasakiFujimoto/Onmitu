extends Node

const MAX_FLOOR: int = 5

var current_floor: int = 1
var death_floor: int = 1
var has_seen_controls: bool = false
var debug_mode: bool = false

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic",
		"Meiryo", "Noto Sans CJK JP", "Arial Unicode MS", "sans-serif"
	])
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = 16

func reset() -> void:
	current_floor = 1

func next_floor() -> void:
	current_floor += 1

func mark_death() -> void:
	death_floor = current_floor
