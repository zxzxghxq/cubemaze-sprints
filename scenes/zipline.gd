extends Area3D

@export var end_point: Marker3D
@export var speed: float = 15.0
@export var rope_radius: float = 0.03

var current_player: CharacterBody3D = null
var is_sliding: bool = false
var rope_mesh_instance: MeshInstance3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	generate_rope()

func _on_body_entered(body: Node3D) -> void:
	if (
		body is CharacterBody3D
		and (body.is_in_group("player") or body.name == "ProtoController")
	):
		current_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == current_player and not is_sliding:
		current_player = null

func _process(delta: float) -> void:
	if current_player and Input.is_action_just_pressed("interact") and not is_sliding:
		is_sliding = true
		if current_player.has_method("set_zipline_state"):
			current_player.set_zipline_state(true)

	if is_sliding and current_player and end_point:
		var target_pos = end_point.global_position
		current_player.global_position = current_player.global_position.move_toward(target_pos, speed * delta)
		
		if current_player.global_position.distance_to(target_pos) < 0.2:
			is_sliding = false
			if current_player.has_method("set_zipline_state"):
				current_player.set_zipline_state(false)
			current_player = null

func generate_rope() -> void:
	if not end_point:
		return
		
	var start_pos = global_position
	var end_pos = end_point.global_position
	var distance = start_pos.distance_to(end_pos)
	
	rope_mesh_instance = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	
	cylinder.top_radius = rope_radius
	cylinder.bottom_radius = rope_radius
	cylinder.height = distance
	cylinder.radial_segments = 6
	
	rope_mesh_instance.mesh = cylinder
	add_child(rope_mesh_instance)
	
	rope_mesh_instance.global_position = start_pos.lerp(end_pos, 0.5)
	rope_mesh_instance.look_at(end_pos, Vector3.UP)
	rope_mesh_instance.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
