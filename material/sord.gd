extends Node3D

@export var rotation_speed : float = 8.0
@export var is_active : bool = true

func _physics_process(delta : float) -> void:
	if is_active:
		rotate_x(rotation_speed * delta)

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "ProtoController":
		get_tree().reload_current_scene()
