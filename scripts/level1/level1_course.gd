extends Node3D

@export_file("*.tscn") var next_level_path: String = "res://level2.tscn"
@export_range(0.0, 5.0, 0.1) var next_level_delay: float = 1.2

@onready var finish_area: Area3D = $FinishArea
@onready var checkpoints: Node3D = $Checkpoints
@onready var monster_director: Node = $MonsterDirector

var _finished: bool = false
var _checkpoint_position: Vector3 = Vector3(0, 0.5, 0)
var _resetting_player: bool = false


func _ready() -> void:
	add_to_group(&"level1_course")
	finish_area.body_entered.connect(_on_finish_area_body_entered)
	for child in checkpoints.get_children():
		if not child is Area3D:
			continue
		var area := child as Area3D
		var marker := area.get_node_or_null("Respawn") as Marker3D
		if marker != null:
			area.body_entered.connect(_on_checkpoint_entered.bind(area, marker))


func reset_player(body: Node3D) -> void:
	if _finished or _resetting_player or not body.is_in_group(&"player"):
		return
	_resetting_player = true
	if monster_director != null and monster_director.has_method("on_player_reset"):
		monster_director.call("on_player_reset")
	body.global_position = _checkpoint_position
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	await get_tree().physics_frame
	_resetting_player = false


func _on_checkpoint_entered(body: Node3D, area: Area3D, marker: Marker3D) -> void:
	if not body.is_in_group(&"player"):
		return
	_checkpoint_position = marker.global_position


func _on_finish_area_body_entered(body: Node3D) -> void:
	if _finished or not body.is_in_group(&"player"):
		return
	_finished = true
	if monster_director != null and monster_director.has_method("finish_level"):
		monster_director.call("finish_level")
	body.set_physics_process(false)
	body.set_process_unhandled_input(false)
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	await get_tree().create_timer(next_level_delay).timeout
	var change_error := get_tree().change_scene_to_file(next_level_path)
	if change_error != OK:
		push_error("Unable to open the next level. Error code: " + str(change_error))
