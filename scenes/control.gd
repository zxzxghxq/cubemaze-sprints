extends Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

func _draw() -> void:
	var center = Vector2.ZERO
	var color = Color.WHITE
	var width = 3.0
	
	draw_line(center + Vector2(0, 15), center, color, width)
	draw_line(center, center + Vector2(-8, 8), color, width)
	draw_line(center, center + Vector2(8, 8), color, width)
