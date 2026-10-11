extends CanvasLayer
class_name PlayerDeathUI

## Shows a red DIE screen when the monster catches the player, then reloads the level.

@export_range(0.1, 10.0, 0.1) var reload_delay: float = 3.0

var _dying: bool = false

@onready var overlay: Control = $Overlay


func _ready() -> void:
	add_to_group(&"death_ui")
	overlay.visible = false


func trigger_death(player: Node3D = null) -> void:
	if _dying:
		return
	_dying = true
	overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if player != null:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

	await get_tree().create_timer(reload_delay, true, false, true).timeout
	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("Unable to reload the current level. Error code: " + str(reload_error))
