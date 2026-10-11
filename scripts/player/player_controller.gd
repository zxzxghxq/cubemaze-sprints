extends CharacterBody3D

## Godot 4.6 first-person and free-fly player controller.
## Suggested path: res://scripts/player/player_controller.gd
## Attach to: Player (CharacterBody3D)

const MAX_PITCH: float = PI * 85.0 / 180.0

@export_group("Features")
@export var can_move: bool = true
@export var has_gravity: bool = true
@export var can_jump: bool = true
@export var can_sprint: bool = false
@export var can_freefly: bool = false
@export var can_dash: bool = true
@export var allow_air_dash: bool = false
@export var capture_mouse_on_start: bool = false
@export var create_default_dash_action: bool = true

@export_group("Speed")
@export_range(0.0001, 0.02, 0.0001) var look_speed: float = 0.002
@export_range(0.0, 30.0, 0.1) var base_speed: float = 7.0
@export_range(0.0, 30.0, 0.1) var sprint_speed: float = 10.0
@export_range(0.0, 50.0, 0.1) var freefly_speed: float = 25.0
@export_range(0.0, 20.0, 0.1) var jump_velocity: float = 4.5
@export_range(0.0, 100.0, 0.5) var ground_acceleration: float = 32.0
@export_range(0.0, 100.0, 0.5) var ground_deceleration: float = 40.0
@export_range(0.0, 100.0, 0.5) var air_acceleration: float = 10.0

@export_group("Dash")
@export_range(0.0, 100.0, 0.5) var dash_speed: float = 24.0
@export_range(0.01, 1.0, 0.01) var dash_duration: float = 0.18
@export_range(0.0, 5.0, 0.05) var dash_cooldown: float = 0.45

@export_group("Input Actions")
@export var input_left: StringName = &"move_left"
@export var input_right: StringName = &"move_right"
@export var input_forward: StringName = &"move_up"
@export var input_back: StringName = &"move_down"
@export var input_jump: StringName = &"jump"
@export var input_sprint: StringName = &"sprint"
@export var input_freefly: StringName = &"freefly"
@export var input_dash: StringName = &"dash"

var mouse_captured: bool = false
var is_on_zipline: bool = false

var _look_rotation: Vector2 = Vector2.ZERO
var _freeflying: bool = false
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

@onready var head: Node3D = get_node_or_null("Head") as Node3D
@onready var collider: CollisionShape3D = get_node_or_null("Collider") as CollisionShape3D


func _ready() -> void:
	if head == null:
		push_error("Player is missing Head (Node3D). The player controller has been disabled.")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return

	if collider == null:
		push_error("Player is missing Collider (CollisionShape3D). Free-fly mode is unavailable.")
		can_freefly = false

	if create_default_dash_action:
		_ensure_default_dash_action()
	_check_input_mappings()

	_look_rotation = Vector2(head.rotation.x, rotation.y)
	if capture_mouse_on_start:
		capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			capture_mouse()

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE and key_event.pressed and not key_event.echo:
			release_mouse()

	if mouse_captured and event is InputEventMouseMotion:
		_rotate_look((event as InputEventMouseMotion).relative)

	if (
		can_freefly
		and event.is_action_pressed(input_freefly)
		and not event.is_echo()
	):
		if _freeflying:
			disable_freefly()
		else:
			enable_freefly()


func _physics_process(delta: float) -> void:
	if is_on_zipline:
		velocity = Vector3.ZERO
		return

	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)

	if _freeflying:
		_update_freefly(delta)
		return

	if _dash_time_left > 0.0:
		_update_dash(delta)
		return

	if _try_start_dash():
		_update_dash(delta)
		return

	_apply_gravity(delta)
	_try_jump()
	_update_ground_movement(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta


func _try_jump() -> void:
	if (
		can_jump
		and is_on_floor()
		and Input.is_action_just_pressed(input_jump)
	):
		velocity.y = jump_velocity


func _update_ground_movement(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if can_move:
		input_vector = Input.get_vector(
			input_left,
			input_right,
			input_forward,
			input_back
		)

	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var move_direction := (global_transform.basis * local_direction)
	move_direction.y = 0.0
	move_direction = move_direction.normalized()

	var target_speed := base_speed
	if can_sprint and Input.is_action_pressed(input_sprint):
		target_speed = sprint_speed

	var target_velocity := move_direction * target_speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	if input_vector.is_zero_approx():
		acceleration = ground_deceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)


func _try_start_dash() -> bool:
	if not can_dash or _dash_cooldown_left > 0.0:
		return false
	if not Input.is_action_just_pressed(input_dash):
		return false
	if not allow_air_dash and not is_on_floor():
		return false

	var input_vector := Input.get_vector(
		input_left,
		input_right,
		input_forward,
		input_back
	)
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	_dash_direction = global_transform.basis * local_direction
	_dash_direction.y = 0.0

	# Dash forward when no movement direction is held.
	if _dash_direction.is_zero_approx():
		_dash_direction = -global_transform.basis.z
		_dash_direction.y = 0.0

	_dash_direction = _dash_direction.normalized()
	_dash_time_left = dash_duration
	# Include dash time in the cooldown so the full cooldown remains afterward.
	_dash_cooldown_left = dash_duration + dash_cooldown
	return true


func _update_dash(delta: float) -> void:
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)
	velocity.x = _dash_direction.x * dash_speed
	velocity.z = _dash_direction.z * dash_speed

	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	# Dash returns early from _physics_process, so it owns this frame's move.
	move_and_slide()


func cancel_active_movement() -> void:
	## Used by checkpoints/death handling so a dash cannot continue after a
	## teleport and push the player away from the intended respawn point.
	_dash_time_left = 0.0
	velocity = Vector3.ZERO


func _update_freefly(delta: float) -> void:
	var input_vector := Input.get_vector(
		input_left,
		input_right,
		input_forward,
		input_back
	)
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var camera_basis := head.global_transform.basis.orthonormalized()
	var direction := camera_basis * local_direction

	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	# Free-fly disables collision, so direct position changes are intentional.
	global_position += direction * freefly_speed * delta
	velocity = Vector3.ZERO


func _rotate_look(relative_motion: Vector2) -> void:
	_look_rotation.x -= relative_motion.y * look_speed
	_look_rotation.x = clampf(_look_rotation.x, -MAX_PITCH, MAX_PITCH)
	_look_rotation.y -= relative_motion.x * look_speed

	# Change only the required axes to preserve the remaining transform.
	rotation.y = _look_rotation.y
	head.rotation.x = _look_rotation.x


func set_zipline_state(state: bool) -> void:
	is_on_zipline = state
	_dash_time_left = 0.0
	if state:
		if _freeflying:
			disable_freefly()
		velocity = Vector3.ZERO


func enable_freefly() -> void:
	if collider == null:
		push_error("Cannot enable free-fly mode: the Collider node is missing.")
		return
	collider.set_deferred("disabled", true)
	_freeflying = true
	_dash_time_left = 0.0
	velocity = Vector3.ZERO


func disable_freefly() -> void:
	if collider != null:
		collider.set_deferred("disabled", false)
	_freeflying = false
	velocity = Vector3.ZERO


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false


func _ensure_default_dash_action() -> void:
	if InputMap.has_action(input_dash):
		return

	InputMap.add_action(input_dash)
	var dash_key := InputEventKey.new()
	dash_key.physical_keycode = KEY_E
	InputMap.action_add_event(input_dash, dash_key)
	print("Created the dash action at runtime. Default key: E.")


func _check_input_mappings() -> void:
	if can_move:
		var movement_actions: Array[StringName] = [
			input_left,
			input_right,
			input_forward,
			input_back,
		]
		if not _actions_exist(movement_actions, "Movement"):
			can_move = false

	if can_jump and not _action_exists(input_jump, "Jump"):
		can_jump = false
	if can_sprint and not _action_exists(input_sprint, "Sprint"):
		can_sprint = false
	if can_freefly and not _action_exists(input_freefly, "Free-fly"):
		can_freefly = false
	if can_dash and not _action_exists(input_dash, "Dash"):
		can_dash = false


func _actions_exist(actions: Array[StringName], system_name: String) -> bool:
	var valid := true
	for action in actions:
		if not _action_exists(action, system_name):
			valid = false
	return valid


func _action_exists(action: StringName, system_name: String) -> bool:
	if InputMap.has_action(action):
		return true
	push_error("%s disabled: Input Action '%s' was not found." % [system_name, action])
	return false
