extends CharacterBody3D
class_name TarSlimeMonster

## Godot 4.6 black tar slime monster.
## Attach to: TarSlimeMonster (CharacterBody3D)

enum State {
	IDLE,
	CHASING,
	TRAPPED,
	RECOVERING,
	EMERGING,
	STUNNED,
	HAZARD_APPROACH,
	HAZARD_WAIT,
	HAZARD_CROSSING,
	HAZARD_RECOVERY,
	FINAL_DEFEAT,
}

signal trapped
signal state_changed(new_state: int)

@export_group("Player")
@export var player_path: NodePath
@export var player_group: StringName = &"player"
@export var player_base_speed_property: StringName = &"base_speed"
@export_range(1.0, 3.0, 0.01) var player_speed_multiplier: float = 1.10
@export var follow_player_current_speed: bool = true
@export_range(0.1, 30.0, 0.1) var fallback_player_speed: float = 7.0

@export_group("Vision")
@export_range(1.0, 100.0, 0.5) var detection_distance: float = 24.0
@export_range(1.0, 179.0, 1.0) var field_of_view_degrees: float = 115.0
@export_flags_3d_physics var vision_collision_mask: int = 1
@export_range(0.0, 5.0, 0.05) var eye_height: float = 1.05
@export_range(0.0, 5.0, 0.05) var player_target_height: float = 0.90
@export_range(0.0, 2.0, 0.05) var lost_sight_grace: float = 0.20

@export_group("Movement")
@export var use_navigation: bool = true
@export_range(0.0, 100.0, 0.5) var acceleration: float = 22.0
@export_range(0.0, 100.0, 0.5) var stopping_deceleration: float = 30.0
@export_range(0.0, 30.0, 0.1) var turn_speed: float = 7.0

@export_group("Hazard Awareness")
@export_range(4.0, 30.0, 0.5) var hazard_detection_distance: float = 18.0
@export_range(0.2, 3.0, 0.05) var hazard_prediction_seconds: float = 1.0
@export_range(0.5, 5.0, 0.1) var hazard_max_wait_seconds: float = 2.0
@export_range(5.0, 20.0, 0.5) var hazard_crossing_speed: float = 14.0
@export_range(0.5, 15.0, 0.5) var hazard_recovery_speed: float = 10.0
@export_range(0.5, 10.0, 0.5) var hazard_memory_seconds: float = 5.0
@export_range(0.5, 3.0, 0.05) var hazard_body_radius: float = 1.3
@export_range(0.1, 1.5, 0.05) var hazard_blade_margin: float = 0.5

@export_group("Visual Animation")
@export_range(0.0, 90.0, 1.0) var tentacle_wave_degrees: float = 18.0
@export_range(0.1, 10.0, 0.1) var tentacle_wave_speed: float = 2.6
@export_range(0.0, 0.20, 0.005) var body_pulse_amount: float = 0.035
@export_range(0.1, 10.0, 0.1) var body_pulse_speed: float = 1.8

var state: State = State.IDLE
var _player: CharacterBody3D
var _lost_sight_left: float = 0.0
var _animation_time: float = 0.0
var _tentacle_nodes: Array[Node3D] = []
var _tentacle_rest_rotations: Array[Vector3] = []
var _tentacle_phases: Array[float] = []
var _transition_id: int = 0
var _active_hazard: Node3D
var _last_crossed_hazard: Node3D
var _hazard_wait_position: Vector3
var _hazard_exit_position: Vector3
var _hazard_recovery_position: Vector3
var _hazard_wait_elapsed: float = 0.0
var _hazard_recovery_left: float = 0.0
var _hazard_memory_left: float = 0.0
var _hazard_using_bypass: bool = false

@onready var model_root: Node3D = $Visual
@onready var body_collider: CollisionShape3D = $BodyCollider
@onready var damage_area: Area3D = $DamageArea
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var burst_particles: CPUParticles3D = $BurstParticles


func _ready() -> void:
	add_to_group(&"tar_monster")
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	navigation_agent.path_desired_distance = 0.45
	navigation_agent.target_desired_distance = 0.90
	_find_player()
	_collect_tentacle_nodes()


func _process(delta: float) -> void:
	if state == State.TRAPPED or state == State.RECOVERING or state == State.EMERGING or state == State.FINAL_DEFEAT:
		return
	_animation_time += delta
	_animate_body()
	_animate_tentacles()


func _physics_process(delta: float) -> void:
	if (
		state == State.TRAPPED
		or state == State.RECOVERING
		or state == State.EMERGING
		or state == State.STUNNED
		or state == State.FINAL_DEFEAT
	):
		velocity = Vector3.ZERO
		return

	if not is_instance_valid(_player):
		_find_player()
	_hazard_memory_left = maxf(_hazard_memory_left - delta, 0.0)
	if _hazard_memory_left <= 0.0:
		_last_crossed_hazard = null

	if state == State.HAZARD_RECOVERY:
		_update_hazard_recovery(delta)
		_apply_gravity_and_move(delta)
		return

	var sees_player := is_instance_valid(_player) and _can_see_player()
	if sees_player:
		_lost_sight_left = lost_sight_grace
	else:
		_lost_sight_left = maxf(_lost_sight_left - delta, 0.0)

	if is_instance_valid(_player) and (sees_player or _lost_sight_left > 0.0):
		if _update_hazard_avoidance(delta):
			_apply_gravity_and_move(delta)
			return
		_set_state(State.CHASING)
		_chase_player(delta)
	else:
		_set_state(State.IDLE)
		_slow_to_stop(delta)

	_apply_gravity_and_move(delta)


func _find_player() -> void:
	_player = null
	if not player_path.is_empty():
		var path_node := get_node_or_null(player_path)
		if path_node is CharacterBody3D:
			_player = path_node as CharacterBody3D
			return

	var group_node := get_tree().get_first_node_in_group(player_group)
	if group_node is CharacterBody3D:
		_player = group_node as CharacterBody3D


func _can_see_player() -> bool:
	var eye_position := global_position + Vector3.UP * eye_height
	var target_position := _player.global_position + Vector3.UP * player_target_height
	var to_player := target_position - eye_position
	if to_player.length_squared() > detection_distance * detection_distance:
		return false

	var flat_direction := Vector3(to_player.x, 0.0, to_player.z)
	if not flat_direction.is_zero_approx():
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var minimum_dot := cos(deg_to_rad(field_of_view_degrees * 0.5))
		if forward.dot(flat_direction.normalized()) < minimum_dot:
			return false

	var query := PhysicsRayQueryParameters3D.create(
		eye_position,
		target_position,
		vision_collision_mask,
		[get_rid()]
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider := hit.get("collider") as Node
	while collider != null:
		if collider == _player:
			return true
		collider = collider.get_parent()
	return false


func _chase_player(delta: float) -> void:
	var target_position := _player.global_position
	navigation_agent.target_position = target_position

	var next_position := target_position
	if use_navigation and not navigation_agent.is_navigation_finished():
		next_position = navigation_agent.get_next_path_position()

	var direction := next_position - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		_slow_to_stop(delta)
		return
	direction = direction.normalized()

	var chase_speed := _get_player_reference_speed() * player_speed_multiplier
	navigation_agent.max_speed = chase_speed
	velocity.x = move_toward(velocity.x, direction.x * chase_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * chase_speed, acceleration * delta)

	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))


func _update_hazard_avoidance(delta: float) -> bool:
	if _active_hazard == null or not is_instance_valid(_active_hazard):
		_active_hazard = _find_blocking_rotating_hazard()
		if _active_hazard == null:
			return false
		_set_hazard_plan(true)

	if state == State.HAZARD_CROSSING:
		_move_direct_toward_position(_hazard_exit_position, hazard_crossing_speed, delta)
		if _flat_distance_to(_hazard_exit_position) <= 1.0:
			_last_crossed_hazard = _active_hazard
			_hazard_memory_left = hazard_memory_seconds
			_active_hazard = null
			_hazard_using_bypass = false
			_set_state(State.CHASING)
		return true

	if _flat_distance_to(_hazard_wait_position) > 0.8:
		_set_state(State.HAZARD_APPROACH)
		var approach_speed := maxf(
			_get_player_reference_speed() * player_speed_multiplier,
			hazard_crossing_speed
		)
		_move_direct_toward_position(_hazard_wait_position, approach_speed, delta)
		return true

	_set_state(State.HAZARD_CROSSING)
	return true

func _find_blocking_rotating_hazard() -> Node3D:
	if not is_instance_valid(_player):
		return null
	var nearest: Node3D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group(&"rotating_hazard"):
		if not candidate is Node3D:
			continue
		var hazard := candidate as Node3D
		if hazard == _last_crossed_hazard and _hazard_memory_left > 0.0:
			continue
		var distance := _flat_distance_between(global_position, hazard.global_position)
		if distance > hazard_detection_distance or distance >= nearest_distance:
			continue
		if not hazard.has_method("blocks_chase_path"):
			continue
		if not bool(hazard.call("blocks_chase_path", global_position, _player.global_position, hazard_body_radius)):
			continue
		nearest = hazard
		nearest_distance = distance
	return nearest


func _set_hazard_plan(outer_bypass: bool) -> void:
	if _active_hazard == null or not is_instance_valid(_active_hazard):
		return
	var plan: Dictionary = _active_hazard.call(
		"get_crossing_plan",
		global_position,
		_player.global_position,
		hazard_body_radius,
		outer_bypass
	)
	if not plan.has("wait_position") or not plan.has("exit_position"):
		_active_hazard = null
		return
	_hazard_wait_position = plan["wait_position"]
	_hazard_exit_position = plan["exit_position"]
	_hazard_wait_elapsed = 0.0
	_hazard_using_bypass = outer_bypass


func _move_toward_position(target: Vector3, speed: float, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		_slow_to_stop(delta)
		return
	direction = direction.normalized()
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

func _move_direct_toward_position(target: Vector3, speed: float, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		_slow_to_stop(delta)
		return
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

func _update_hazard_recovery(delta: float) -> void:
	_hazard_recovery_left = maxf(_hazard_recovery_left - delta, 0.0)
	_move_direct_toward_position(_hazard_recovery_position, hazard_recovery_speed, delta)
	if _hazard_recovery_left > 0.0 or _flat_distance_to(_hazard_recovery_position) > 0.8:
		return
	damage_area.set_deferred("monitoring", true)
	_set_hazard_plan(true)
	_set_state(State.HAZARD_APPROACH)

func _apply_gravity_and_move(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()


func _flat_distance_to(target: Vector3) -> float:
	return _flat_distance_between(global_position, target)


func _flat_distance_between(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))


func _get_player_reference_speed() -> float:
	var reference_speed := fallback_player_speed
	for property_info in _player.get_property_list():
		if StringName(property_info.name) == player_base_speed_property:
			var value: Variant = _player.get(player_base_speed_property)
			if value is float or value is int:
				reference_speed = maxf(float(value), 0.1)
			break

	if follow_player_current_speed:
		var horizontal_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		reference_speed = maxf(reference_speed, horizontal_speed)
	return reference_speed


func _slow_to_stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, stopping_deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, stopping_deceleration * delta)


func _collect_tentacle_nodes() -> void:
	_tentacle_nodes.clear()
	_tentacle_rest_rotations.clear()
	_tentacle_phases.clear()

	var candidates := model_root.find_children("*", "Node3D", true, false)
	for candidate in candidates:
		if not candidate is Node3D:
			continue
		var node := candidate as Node3D
		var node_name := String(node.name)
		if node_name.begins_with("TentaclePivot_") or node_name.begins_with("TentacleJoint_"):
			_tentacle_nodes.append(node)
			_tentacle_rest_rotations.append(node.rotation)
			_tentacle_phases.append(float(_tentacle_nodes.size() - 1) * 0.73)


func _animate_body() -> void:
	var pulse := sin(_animation_time * body_pulse_speed) * body_pulse_amount
	model_root.scale = Vector3(1.0 + pulse, 1.0 - pulse * 0.55, 1.0 + pulse)


func _animate_tentacles() -> void:
	var amplitude := deg_to_rad(tentacle_wave_degrees)
	for index in range(_tentacle_nodes.size()):
		var node := _tentacle_nodes[index]
		var rest := _tentacle_rest_rotations[index]
		var phase := _tentacle_phases[index]
		var wave := sin(_animation_time * tentacle_wave_speed + phase)
		var secondary := cos(_animation_time * tentacle_wave_speed * 0.73 + phase * 1.4)
		node.rotation.x = rest.x + wave * amplitude * 0.62
		node.rotation.y = rest.y + secondary * amplitude
		node.rotation.z = rest.z


func _on_damage_area_body_entered(body: Node3D) -> void:
	if (
		state == State.TRAPPED
		or state == State.RECOVERING
		or state == State.EMERGING
		or state == State.STUNNED
		or state == State.HAZARD_RECOVERY
		or state == State.FINAL_DEFEAT
	):
		return
	if body == _player or body.is_in_group(player_group):
		_trigger_player_death(body)


func _trigger_player_death(player_body: Node3D) -> void:
	var course := get_tree().get_first_node_in_group(&"level1_course")
	if course != null and course.has_method("reset_player"):
		course.call_deferred("reset_player", player_body)
		return

	var death_ui := get_tree().get_first_node_in_group(&"death_ui")
	if death_ui == null or not death_ui.has_method("trigger_death"):
		push_error(
			"PlayerDeathUI was not found. Add scenes/player_death_ui.tscn to the current level."
		)
		return
	death_ui.call("trigger_death", player_body)


func fall_into_trap() -> void:
	if state == State.TRAPPED or state == State.RECOVERING or state == State.FINAL_DEFEAT:
		return
	_transition_id += 1
	_clear_hazard_tracking()
	var transition := _transition_id
	_set_state(State.TRAPPED)
	velocity = Vector3.ZERO
	damage_area.set_deferred("monitoring", false)
	body_collider.set_deferred("disabled", true)
	trapped.emit()

	var collapse := create_tween()
	collapse.set_trans(Tween.TRANS_QUAD)
	collapse.set_ease(Tween.EASE_IN)
	collapse.tween_property(model_root, "scale", Vector3(0.72, 0.12, 0.72), 0.16)
	await collapse.finished
	if transition != _transition_id:
		return

	model_root.visible = false
	burst_particles.emitting = true
	await get_tree().create_timer(burst_particles.lifetime + 0.25).timeout
	if transition == _transition_id:
		_set_state(State.RECOVERING)


func reappear_at(spawn_transform: Transform3D, grace_seconds: float = 2.0) -> void:
	if state == State.FINAL_DEFEAT:
		return
	_transition_id += 1
	_clear_hazard_tracking()
	var transition := _transition_id
	_set_state(State.EMERGING)
	velocity = Vector3.ZERO
	global_transform = spawn_transform
	if not is_instance_valid(_player):
		_find_player()
	if is_instance_valid(_player) and not global_position.is_equal_approx(_player.global_position):
		look_at(_player.global_position, Vector3.UP)

	body_collider.set_deferred("disabled", true)
	damage_area.set_deferred("monitoring", false)
	model_root.visible = false
	model_root.scale = Vector3.ONE
	burst_particles.restart()
	burst_particles.emitting = true

	var emergence_duration := minf(0.35, maxf(grace_seconds, 0.05))
	var warning_duration := maxf(grace_seconds - emergence_duration, 0.0)
	if warning_duration > 0.0:
		await get_tree().create_timer(warning_duration).timeout
	if transition != _transition_id:
		return

	model_root.visible = true
	model_root.scale = Vector3(0.18, 0.05, 0.18)
	var emerge := create_tween()
	emerge.set_trans(Tween.TRANS_BACK)
	emerge.set_ease(Tween.EASE_OUT)
	emerge.tween_property(model_root, "scale", Vector3.ONE, emergence_duration)
	await emerge.finished
	if transition != _transition_id:
		return

	body_collider.set_deferred("disabled", false)
	damage_area.set_deferred("monitoring", true)
	_set_state(State.IDLE)


func withdraw_temporarily() -> void:
	if state == State.RECOVERING or state == State.FINAL_DEFEAT:
		return
	_transition_id += 1
	_clear_hazard_tracking()
	_set_state(State.RECOVERING)
	velocity = Vector3.ZERO
	damage_area.set_deferred("monitoring", false)
	body_collider.set_deferred("disabled", true)
	model_root.visible = false
	model_root.scale = Vector3.ONE
	burst_particles.restart()
	burst_particles.emitting = true


func stun(duration: float = 2.5) -> void:
	if state != State.IDLE and state != State.CHASING:
		return
	_transition_id += 1
	var transition := _transition_id
	_set_state(State.STUNNED)
	velocity = Vector3.ZERO
	damage_area.set_deferred("monitoring", false)
	burst_particles.restart()
	burst_particles.emitting = true
	await get_tree().create_timer(maxf(duration, 0.1)).timeout
	if transition != _transition_id or state == State.FINAL_DEFEAT:
		return
	damage_area.set_deferred("monitoring", true)
	_set_state(State.IDLE)


func hit_by_rotating_hazard(hazard: Node3D, recovery_seconds: float = 1.2) -> void:
	if (
		state == State.TRAPPED
		or state == State.RECOVERING
		or state == State.EMERGING
		or state == State.STUNNED
		or state == State.HAZARD_RECOVERY
		or state == State.FINAL_DEFEAT
	):
		return
	if hazard == null or not is_instance_valid(hazard) or not hazard.has_method("get_crossing_plan"):
		stun(recovery_seconds)
		return

	_transition_id += 1
	_active_hazard = hazard
	_hazard_using_bypass = true
	_hazard_wait_elapsed = 0.0
	_hazard_recovery_left = maxf(recovery_seconds, 0.1)
	if not is_instance_valid(_player):
		_find_player()
	if not is_instance_valid(_player):
		stun(recovery_seconds)
		return
	_set_hazard_plan(true)
	_hazard_recovery_position = _hazard_wait_position
	_set_state(State.HAZARD_RECOVERY)
	velocity = Vector3.ZERO
	damage_area.set_deferred("monitoring", false)
	burst_particles.restart()
	burst_particles.emitting = true


func final_defeat() -> void:
	_transition_id += 1
	_clear_hazard_tracking()
	_set_state(State.FINAL_DEFEAT)
	velocity = Vector3.ZERO
	damage_area.set_deferred("monitoring", false)
	burst_particles.restart()
	burst_particles.emitting = true


func get_hud_status(player_node: Node3D) -> String:
	match state:
		State.TRAPPED:
			return "MONSTER: TEMPORARILY TRAPPED"
		State.RECOVERING:
			return "MONSTER: RECOVERING"
		State.EMERGING:
			return "MONSTER: RETURNING"
		State.STUNNED:
			return "MONSTER: STUNNED"
		State.HAZARD_APPROACH:
			return "MONSTER: ANALYZING HAZARD"
		State.HAZARD_WAIT:
			return "MONSTER: WAITING FOR OPENING"
		State.HAZARD_CROSSING:
			return "MONSTER: CROSSING HAZARD"
		State.HAZARD_RECOVERY:
			return "MONSTER: KNOCKED BACK"
		State.FINAL_DEFEAT:
			return "MONSTER: STOPPED"
		_:
			if player_node != null:
				var distance := global_position.distance_to(player_node.global_position)
				return "MONSTER: CHASING (%.0f m)" % distance
			return "MONSTER: CHASING"


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(int(state))


func _clear_hazard_tracking() -> void:
	_active_hazard = null
	_last_crossed_hazard = null
	_hazard_wait_elapsed = 0.0
	_hazard_recovery_left = 0.0
	_hazard_memory_left = 0.0
	_hazard_using_bypass = false
