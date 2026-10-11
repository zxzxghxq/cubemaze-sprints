extends Area3D

@export_range(1.0, 40.0, 0.5) var bounce_velocity: float = 14.0
@export var player_group: StringName = &"player"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(player_group):
		return
	if body is CharacterBody3D:
		var player := body as CharacterBody3D
		if player.velocity.y <= 1.0:
			player.velocity.y = bounce_velocity
