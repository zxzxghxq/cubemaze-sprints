extends Area3D

@export_file("*.tscn") var target_scene: String = "res://level1.tscn"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "ProtoController":
		get_tree().change_scene_to_file(target_scene)

func _on_area_shape_entered(area_rid: RID, area: Area3D, area_shape_index: int, local_shape_index: int) -> void:
	pass # Replace with function body.
