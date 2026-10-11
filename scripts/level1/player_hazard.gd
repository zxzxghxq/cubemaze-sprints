extends Area3D

@export var player_group: StringName = &"player"

var _cooldown: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _cooldown or not body.is_in_group(player_group):
		return
	_cooldown = true

	var course := get_tree().get_first_node_in_group(&"level1_course")
	if course != null and course.has_method("reset_player"):
		course.call_deferred("reset_player", body)
		await get_tree().create_timer(0.75).timeout
		_cooldown = false
		return

	var death_ui := get_tree().get_first_node_in_group(&"death_ui")
	if death_ui != null and death_ui.has_method("trigger_death"):
		death_ui.call("trigger_death", body)
		return

	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("The hazard could not reload the current level. Error code: " + str(reload_error))
	_cooldown = false
