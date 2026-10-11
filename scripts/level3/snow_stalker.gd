extends CharacterBody3D
class_name SnowStalker

signal caught_player

@export var player_path: NodePath = NodePath("../Player")
@export var chase_speed: float = 7.8
@export var enraged_speed: float = 10.2
@export var acceleration: float = 22.0
@export var catch_distance: float = 2.0
@export var tracking_distance: float = 115.0

var active: bool = false
var enraged: bool = false
var player_hidden: bool = false
var disabled_by_trap: bool = false
var _target: CharacterBody3D
var _last_known_position := Vector3.ZERO
var _spawn_position := Vector3.ZERO
var _state_sequence: int = 0
var _stuck_time: float = 0.0
var _steer_time: float = 0.0
var _steer_sign: float = 1.0
var _safe_zone_center := Vector3.ZERO
var _safe_zone_radius: float = 0.0

@onready var visual: Node3D = $Visual
@onready var collider: CollisionShape3D = $Collider
@onready var warning_light: OmniLight3D = $WarningLight
@onready var trap_particles: CPUParticles3D = $TrapParticles

func _ready() -> void:
	add_to_group(&"snow_monster")
	_target = get_node_or_null(player_path) as CharacterBody3D
	_spawn_position = global_position
	_apply_frost_material()
	deactivate()

func _physics_process(delta: float) -> void:
	if not active or disabled_by_trap:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(&"player") as CharacterBody3D
	if not is_instance_valid(_target):
		return
	if _target_inside_safe_zone():
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	var destination := _target.global_position
	if player_hidden:
		destination = _last_known_position
	else:
		_last_known_position = destination
	var flat_distance := Vector2(global_position.x, global_position.z).distance_to(
		Vector2(destination.x, destination.z)
	)
	if flat_distance <= tracking_distance:
		_steer_toward(destination, enraged_speed if enraged else chase_speed, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

	_apply_gravity(delta)
	var before_move := global_position
	move_and_slide()
	_update_stuck_recovery(before_move, delta)
	if not player_hidden and global_position.distance_to(_target.global_position) <= catch_distance:
		active = false
		caught_player.emit()

func _steer_toward(destination: Vector3, speed: float, delta: float) -> void:
	var direction := destination - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	direction = direction.normalized()
	if _steer_time > 0.0:
		_steer_time = maxf(_steer_time - delta, 0.0)
		var side := Vector3(-direction.z, 0.0, direction.x) * _steer_sign
		direction = (direction * 0.3 + side).normalized()
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(7.0 * delta, 1.0))

func _update_stuck_recovery(before_move: Vector3, delta: float) -> void:
	var moved := Vector2(global_position.x - before_move.x,
		global_position.z - before_move.z).length()
	if Vector2(velocity.x, velocity.z).length() > 1.0 and moved < 0.018:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
	if _stuck_time >= 0.32:
		_stuck_time = 0.0
		_steer_sign *= -1.0
		_steer_time = 0.9

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

func activate(spawn_position: Vector3, make_enraged: bool = false) -> void:
	_state_sequence += 1
	_spawn_position = spawn_position
	global_position = spawn_position
	velocity = Vector3.ZERO
	enraged = make_enraged
	disabled_by_trap = false
	active = true
	visible = true
	collider.set_deferred("disabled", false)
	warning_light.visible = true
	if is_instance_valid(_target):
		_last_known_position = _target.global_position

func reset_chase(spawn_position: Vector3, delay: float = 1.0) -> void:
	_state_sequence += 1
	var sequence := _state_sequence
	active = false
	disabled_by_trap = false
	velocity = Vector3.ZERO
	visible = false
	collider.set_deferred("disabled", true)
	global_position = spawn_position
	await get_tree().create_timer(maxf(delay, 0.05)).timeout
	if sequence != _state_sequence:
		return
	activate(spawn_position, enraged)

func deactivate() -> void:
	_state_sequence += 1
	active = false
	disabled_by_trap = false
	velocity = Vector3.ZERO
	visible = false
	if collider != null:
		collider.set_deferred("disabled", true)
	if warning_light != null:
		warning_light.visible = false

func set_player_hidden(hidden: bool) -> void:
	if hidden and not player_hidden and is_instance_valid(_target):
		_last_known_position = _target.global_position
	player_hidden = hidden

func set_safe_zone(center: Vector3, radius: float) -> void:
	_safe_zone_center = center
	_safe_zone_radius = maxf(radius, 0.0)

func _target_inside_safe_zone() -> bool:
	if _safe_zone_radius <= 0.0 or not is_instance_valid(_target):
		return false
	return Vector2(_target.global_position.x, _target.global_position.z).distance_to(
		Vector2(_safe_zone_center.x, _safe_zone_center.z)
	) <= _safe_zone_radius

func stun_for(duration: float) -> void:
	if disabled_by_trap or not active:
		return
	_state_sequence += 1
	var sequence := _state_sequence
	disabled_by_trap = true
	velocity = Vector3.ZERO
	trap_particles.restart()
	trap_particles.emitting = true
	await get_tree().create_timer(maxf(duration, 0.25)).timeout
	if sequence != _state_sequence:
		return
	disabled_by_trap = false
	active = true

func trap_for(duration: float, respawn_position: Vector3) -> void:
	if disabled_by_trap or not active:
		return
	_state_sequence += 1
	var sequence := _state_sequence
	disabled_by_trap = true
	active = false
	velocity = Vector3.ZERO
	trap_particles.restart()
	trap_particles.emitting = true
	var sink := create_tween()
	sink.tween_property(visual, "position:y", -2.2, 0.5)
	await get_tree().create_timer(maxf(duration, 0.5)).timeout
	if sequence != _state_sequence:
		return
	global_position = respawn_position
	visual.position.y = 0.0
	disabled_by_trap = false
	active = true

func get_status() -> String:
	if not active:
		return "FROST STALKER: QUIET"
	if disabled_by_trap:
		return "FROST STALKER: BLOCKED"
	if player_hidden:
		return "FROST STALKER: SEARCHING"
	if is_instance_valid(_target):
		return "FROST STALKER: HUNTING  %.0f m" % global_position.distance_to(_target.global_position)
	return "FROST STALKER: HUNTING"

func _apply_frost_material() -> void:
	var frost := StandardMaterial3D.new()
	frost.albedo_color = Color(0.055, 0.085, 0.13)
	frost.metallic = 0.15
	frost.roughness = 0.66
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = frost
