extends CharacterBody3D
class_name JungleStalker

signal caught_player
signal state_changed(label: String)

@export var player_path: NodePath
@export_range(1.0, 20.0, 0.1) var chase_speed: float = 9.6
@export_range(1.0, 24.0, 0.1) var enraged_speed: float = 11.4
@export_range(1.0, 100.0, 0.5) var acceleration: float = 42.0
@export_range(0.5, 5.0, 0.1) var catch_distance: float = 1.45
@export_range(5.0, 150.0, 1.0) var tracking_distance: float = 95.0

const AVOID_RECTS: Array[Rect2] = [Rect2(-44.0, -46.0, 10.0, 22.0)]

var active: bool = false
var player_hidden: bool = false
var trapped: bool = false
var enraged: bool = false
var _target: CharacterBody3D
var _last_known_position: Vector3
var _search_position: Vector3
var _reported_state: String = "DORMANT"
var _reset_position: Vector3
var _state_sequence: int = 0
var _resetting: bool = false
var _stuck_time: float = 0.0
var _steer_time: float = 0.0
var _steer_sign: float = 1.0

@onready var visual: Node3D = $Visual
@onready var collider: CollisionShape3D = $Collider
@onready var warning_light: OmniLight3D = $WarningLight
@onready var trap_particles: CPUParticles3D = $TrapParticles

func _ready() -> void:
	add_to_group(&"jungle_monster")
	_find_player()
	_reset_position = global_position
	visual.visible = false
	warning_light.visible = false

func _physics_process(delta: float) -> void:
	if _resetting:
		velocity = Vector3.ZERO
		return
	if not active or trapped:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	if not is_instance_valid(_target):
		_find_player()
	if not is_instance_valid(_target):
		return

	var target_position := _target.global_position
	var current_target := target_position
	if player_hidden:
		current_target = _search_position
		_set_reported_state("SEARCHING")
	else:
		_last_known_position = target_position
		_search_position = _last_known_position + Vector3(0.0, 0.0, 16.0)
		_set_reported_state("HUNTING")

	var flat_distance := Vector2(global_position.x, global_position.z).distance_to(Vector2(current_target.x, current_target.z))
	if flat_distance > tracking_distance and not player_hidden:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	else:
		_move_toward(current_target, enraged_speed if enraged else chase_speed, delta)

	_apply_gravity(delta)
	var before_move := global_position
	move_and_slide()
	_update_stuck_recovery(before_move, delta)
	if not player_hidden and global_position.distance_to(_target.global_position) <= catch_distance:
		active = false
		_set_reported_state("CAUGHT YOU")
		caught_player.emit()

func _find_player() -> void:
	_target = null
	if not player_path.is_empty():
		var candidate := get_node_or_null(player_path)
		if candidate is CharacterBody3D:
			_target = candidate
			return
	var group_player := get_tree().get_first_node_in_group(&"player")
	if group_player is CharacterBody3D:
		_target = group_player

func _move_toward(target_position: Vector3, speed: float, delta: float) -> void:
	var from := Vector2(global_position.x, global_position.z)
	var to := Vector2(target_position.x, target_position.z)
	var waypoint := _waypoint_around_obstacles(from, to)
	var direction := Vector3(waypoint.x - from.x, 0.0, waypoint.y - from.y)
	if direction.is_zero_approx():
		return
	direction = direction.normalized()
	if _steer_time > 0.0:
		_steer_time = maxf(_steer_time - delta, 0.0)
		var side := Vector3(-direction.z, 0.0, direction.x) * _steer_sign
		direction = (direction * 0.25 + side).normalized()
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(8.0 * delta, 1.0))

func _update_stuck_recovery(before_move: Vector3, delta: float) -> void:
	var moved := Vector2(global_position.x - before_move.x, global_position.z - before_move.z).length()
	var requested_speed := Vector2(velocity.x, velocity.z).length()
	if requested_speed > 1.0 and moved < 0.015:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
	if _stuck_time >= 0.35:
		_stuck_time = 0.0
		_steer_sign *= -1.0
		_steer_time = 0.85

func _waypoint_around_obstacles(from: Vector2, to: Vector2) -> Vector2:
	for rect in AVOID_RECTS:
		if rect.has_point(from) or rect.has_point(to):
			continue
		if not _segment_hits_rect(from, to, rect):
			continue
		# Route around the rect's north or south side (whichever the monster is on).
		var center_z := rect.position.y + rect.size.y / 2.0
		var go_north := from.y < center_z
		var edge_z := rect.position.y - 3.0 if go_north else rect.position.y + rect.size.y + 3.0
		if (go_north and from.y <= edge_z + 0.5) or (not go_north and from.y >= edge_z - 0.5):
			# Already on the safe side: move along the safe lane to the target's x.
			return Vector2(to.x, edge_z)
		# First move straight out of the rect's z-band before turning.
		return Vector2(from.x, edge_z)
	return to

func _segment_hits_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var steps := 12
	for i in steps + 1:
		var t := float(i) / float(steps)
		if rect.has_point(from.lerp(to, t)):
			return true
	return false

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

func activate(spawn_position: Vector3, make_enraged: bool = false) -> void:
	_state_sequence += 1
	_activate_now(spawn_position, make_enraged)

func _activate_now(spawn_position: Vector3, make_enraged: bool) -> void:
	_reset_position = spawn_position
	_resetting = false
	global_position = spawn_position
	velocity = Vector3.ZERO
	_stuck_time = 0.0
	_steer_time = 0.0
	enraged = make_enraged
	trapped = false
	active = true
	visual.visible = true
	warning_light.visible = true
	collider.set_deferred("disabled", false)
	if is_instance_valid(_target):
		_last_known_position = _target.global_position
		_search_position = _last_known_position + Vector3(0.0, 0.0, 16.0)
	_set_reported_state("HUNTING")

func reset_chase(spawn_position: Vector3, delay: float = 1.2) -> void:
	_state_sequence += 1
	var sequence := _state_sequence
	_resetting = true
	active = false
	trapped = false
	velocity = Vector3.ZERO
	visual.visible = false
	warning_light.visible = false
	collider.set_deferred("disabled", true)
	visual.position.y = 0.0
	global_position = spawn_position
	await get_tree().create_timer(maxf(delay, 0.05)).timeout
	if sequence != _state_sequence or trapped:
		return
	_activate_now(spawn_position, enraged)

func deactivate() -> void:
	_state_sequence += 1
	_resetting = false
	active = false
	trapped = false
	velocity = Vector3.ZERO
	visual.position.y = 0.0
	visual.visible = false
	warning_light.visible = false
	collider.set_deferred("disabled", true)
	_set_reported_state("DORMANT")

func set_player_hidden(hidden: bool) -> void:
	player_hidden = hidden
	if hidden:
		_search_position = _last_known_position + Vector3(0.0, 0.0, 18.0)

func trap_for(duration: float, respawn_position: Vector3) -> void:
	if trapped:
		return
	_state_sequence += 1
	var sequence := _state_sequence
	_resetting = false
	trapped = true
	active = false
	velocity = Vector3.ZERO
	_set_reported_state("TRAPPED")
	trap_particles.restart()
	trap_particles.emitting = true
	var sink := create_tween()
	sink.tween_property(visual, "position:y", -2.8, 0.55)
	await get_tree().create_timer(maxf(duration, 0.5)).timeout
	if sequence != _state_sequence:
		return
	global_position = respawn_position
	visual.position.y = 0.0
	visual.visible = false
	warning_light.visible = false
	trapped = false
	await get_tree().create_timer(1.0).timeout
	if sequence != _state_sequence:
		return
	_activate_now(respawn_position, enraged)

func stun_for(duration: float) -> void:
	if trapped:
		return
	_state_sequence += 1
	var sequence := _state_sequence
	trapped = true
	velocity = Vector3.ZERO
	_set_reported_state("BLOCKED")
	trap_particles.restart()
	trap_particles.emitting = true
	await get_tree().create_timer(maxf(duration, 0.25)).timeout
	if sequence != _state_sequence:
		return
	trapped = false
	active = true
	_set_reported_state("HUNTING")

func get_status(player: Node3D) -> String:
	if _resetting:
		return "MONSTER: RECOVERING"
	if trapped:
		return "MONSTER: " + _reported_state
	if not active:
		return "MONSTER: QUIET"
	if player != null:
		var distance := global_position.distance_to(player.global_position)
		return "MONSTER: %s (%.0f m)" % [_reported_state, distance]
	return "MONSTER: " + _reported_state

func _set_reported_state(value: String) -> void:
	if _reported_state == value:
		return
	_reported_state = value
	state_changed.emit(value)
