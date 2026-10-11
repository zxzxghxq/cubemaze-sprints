extends Area3D

@export var target_destination: Node3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if target_destination and body.name == "ProtoController":
		body.global_position = target_destination.global_position
		
		if "velocity" in body:
			body.velocity = Vector3.ZERO
