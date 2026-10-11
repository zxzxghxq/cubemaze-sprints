extends RigidBody3D

const WHEEL_NAMES: Array[StringName] = [
	&"Wheel_FL", &"Wheel_FR", &"Wheel_RL", &"Wheel_RR",
]

@export var player_path: NodePath = NodePath("../Player")
@export var interaction_distance: float = 4.2
@export var maximum_speed: float = 30.0
@export var engine_force: float = 6200.0
@export var brake_force: float = 7600.0
@export var steering_angle_degrees: float = 31.0
@export var suspension_rest_length: float = 0.65
@export var suspension_travel: float = 0.22
@export var suspension_stiffness: float = 36000.0
@export var suspension_damping: float = 3900.0
@export var lateral_tire_stiffness: float = 1250.0
@export var rolling_resistance: float = 12.0
@export var snow_friction: float = 1.15
@export var wheel_radius: float = 0.52

var _player: CharacterBody3D
var _driver: CharacterBody3D
var _saved_can_move: bool = true
var _saved_can_dash: bool = true
var _interaction_lock: float = 0.0
var _steering_input: float = 0.0
var _throttle_input: float = 0.0
var _braking: bool = false
var _wheel_nodes: Dictionary = {}
var _hub_nodes: Dictionary = {}
var _wheel_original_bases: Dictionary = {}
var _hub_original_bases: Dictionary = {}
var _wheel_spin_angles: Dictionary = {}
var _wheel_pivots: Dictionary = {}
var _suspension_rays: Dictionary = {}
var _player_visual: Node3D
var _player_visual_parent: Node
var _player_visual_transform: Transform3D

@onready var _vehicle_camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var _visual_root: Node3D = $VisualRoot
@onready var _rider_mount: Node3D = $VisualRoot/RiderMount
@onready var _prompt_label: Label = $VehicleHUD/PromptLabel

func _ready() -> void:
	add_to_group(&"snow_atv")
	contact_monitor = true
	max_contacts_reported = 16
	continuous_cd = true
	_player = get_node_or_null(player_path) as CharacterBody3D
	_suspension_rays = {
		&"Wheel_FL": $SuspensionRays/FrontLeft,
		&"Wheel_FR": $SuspensionRays/FrontRight,
		&"Wheel_RL": $SuspensionRays/RearLeft,
		&"Wheel_RR": $SuspensionRays/RearRight,
	}
	for ray: RayCast3D in _suspension_rays.values():
		ray.enabled = true
		ray.add_exception(self)
		_setup_wheel_pivots()
	_align_suspension_rays_to_wheels()
	_update_prompt()

func _process(delta: float) -> void:
	_interaction_lock = maxf(_interaction_lock - delta, 0.0)
	if _player == null:
		_player = get_node_or_null(player_path) as CharacterBody3D
	if _driver != null:
		_driver.global_position = global_position + global_transform.basis.y * 1.0
	_update_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if _interaction_lock > 0.0 or not event.is_action_pressed(&"interact") or event.is_echo():
		return
	if _driver != null:
		_exit_vehicle()
	elif _player != null and _player.global_position.distance_to(global_position) <= interaction_distance:
		_enter_vehicle()
	else:
		return
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	_update_steering_visuals(delta)
	_spin_wheels(delta)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.step
	if _driver != null:
		_throttle_input = Input.get_action_strength(&"move_up") - Input.get_action_strength(&"move_down")
		var steering_target := Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
		_steering_input = move_toward(_steering_input, steering_target, 4.0 * delta)
		_braking = Input.is_action_pressed(&"jump")
	else:
		_throttle_input = 0.0
		_steering_input = move_toward(_steering_input, 0.0, 3.0 * delta)
		_braking = true

	var horizontal_speed := Vector2(state.linear_velocity.x, state.linear_velocity.z).length()
	var speed_ratio := clampf(horizontal_speed / maximum_speed, 0.0, 1.0)
	var maximum_steer := deg_to_rad(lerpf(steering_angle_degrees, 11.0, speed_ratio))
	var steering_angle := _steering_input * maximum_steer
	for wheel_name in WHEEL_NAMES:
		var ray := _suspension_rays.get(wheel_name) as RayCast3D
		if ray == null:
			continue
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue
		var contact_point := ray.get_collision_point()
		var contact_normal := ray.get_collision_normal().normalized()
		var mount_position := ray.global_position
		var suspension_up := ray.global_transform.basis.y.normalized()
		var measured_length := mount_position.distance_to(contact_point) - wheel_radius
		var minimum_length := suspension_rest_length - suspension_travel
		var maximum_length := suspension_rest_length + suspension_travel
		var current_length := clampf(measured_length, minimum_length, maximum_length)
		var compression := suspension_rest_length - current_length
		var mount_offset := mount_position - state.transform.origin
		var mount_velocity := state.linear_velocity + state.angular_velocity.cross(mount_offset)
		var velocity_along_suspension := mount_velocity.dot(suspension_up)
		var spring_force := compression * suspension_stiffness \
			- velocity_along_suspension * suspension_damping
		var maximum_spring_force := mass * 9.81
		spring_force = clampf(spring_force, 0.0, maximum_spring_force)
		state.apply_force(suspension_up * spring_force, mount_offset)

		var contact_offset := contact_point - state.transform.origin
		var contact_velocity := state.linear_velocity + state.angular_velocity.cross(contact_offset)
		# The imported Blender ATV faces local +Z. Keep physics, steering,
		# camera and visuals on that same convention.
		var wheel_forward := state.transform.basis.z
		if wheel_name == &"Wheel_FL" or wheel_name == &"Wheel_FR":
			wheel_forward = wheel_forward.rotated(suspension_up, -steering_angle)
		wheel_forward = wheel_forward.slide(contact_normal).normalized()
		var wheel_right := contact_normal.cross(wheel_forward).normalized()
		var longitudinal_speed := contact_velocity.dot(wheel_forward)
		var lateral_speed := contact_velocity.dot(wheel_right)
		var traction_limit := maxf(spring_force * snow_friction, 120.0)
		var longitudinal_force := _throttle_input * engine_force * 0.25
		longitudinal_force -= longitudinal_speed * rolling_resistance
		if _braking and absf(longitudinal_speed) > 0.03:
			longitudinal_force -= signf(longitudinal_speed) * brake_force * 0.25
		if horizontal_speed > maximum_speed and signf(longitudinal_speed) == signf(_throttle_input):
			longitudinal_force = minf(longitudinal_force, 0.0)
		var lateral_force := -lateral_speed * lateral_tire_stiffness
		longitudinal_force = clampf(longitudinal_force, -traction_limit, traction_limit)
		lateral_force = clampf(lateral_force, -traction_limit, traction_limit)
		state.apply_force(
			wheel_forward * longitudinal_force + wheel_right * lateral_force,
			contact_offset
		)
	var planar_velocity := Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z)
	state.apply_central_force(-planar_velocity * planar_velocity.length() * 0.8)

func _setup_wheel_pivots() -> void:
	for found in _visual_root.find_children("Wheel_*", "Node3D", true, false):
		var wheel := found as Node3D
		var wheel_name := StringName(wheel.name)
		var wheel_parent := wheel.get_parent() as Node3D
		if wheel_parent == null:
			continue
		var original_position := wheel.position
		var original_basis := wheel.transform.basis
		var pivot := Node3D.new()
		pivot.name = String(wheel.name) + "Pivot"
		wheel_parent.add_child(pivot)
		pivot.position = original_position
		wheel.reparent(pivot, false)
		wheel.transform = Transform3D(original_basis, Vector3.ZERO)
		var hub_name := String(wheel.name).replace("Wheel_", "Hub_")
		var hub := _visual_root.find_child(hub_name, true, false) as Node3D
		var hub_basis := Basis.IDENTITY
		if hub != null:
			hub_basis = hub.transform.basis
			hub.reparent(pivot, false)
			hub.transform = Transform3D(hub_basis, Vector3.ZERO)
		_wheel_nodes[wheel_name] = wheel
		_wheel_original_bases[wheel_name] = original_basis
		_wheel_spin_angles[wheel_name] = 0.0
		if hub != null:
			_hub_nodes[wheel_name] = hub
			_hub_original_bases[wheel_name] = hub_basis
		_wheel_pivots[wheel_name] = pivot

func _align_suspension_rays_to_wheels() -> void:
	for wheel_name in WHEEL_NAMES:
		var pivot := _wheel_pivots.get(wheel_name) as Node3D
		var ray := _suspension_rays.get(wheel_name) as RayCast3D
		if pivot == null or ray == null:
			continue
		var wheel_local := to_local(pivot.global_position)
		ray.position.x = wheel_local.x
		ray.position.z = wheel_local.z

func _update_steering_visuals(delta: float) -> void:
	var visual_response := clampf(20.0 * delta, 0.0, 1.0)
	var speed_ratio := clampf(linear_velocity.length() / maximum_speed, 0.0, 1.0)
	var visual_steer := _steering_input * deg_to_rad(lerpf(steering_angle_degrees, 11.0, speed_ratio))
	for wheel_name in [&"Wheel_FL", &"Wheel_FR"]:
		var pivot := _wheel_pivots.get(wheel_name) as Node3D
		if pivot == null:
			continue
		pivot.rotation.y = lerp_angle(pivot.rotation.y, -visual_steer, visual_response)

func _spin_wheels(delta: float) -> void:
	var forward_speed := linear_velocity.dot(global_transform.basis.z)
	if absf(forward_speed) < 0.02:
		return
	var spin := forward_speed * delta / wheel_radius
	for wheel_name in WHEEL_NAMES:
		var wheel := _wheel_nodes.get(wheel_name) as Node3D
		if wheel == null:
			continue
		var spin_angle := wrapf(float(_wheel_spin_angles.get(wheel_name, 0.0)) + spin, -PI, PI)
		_wheel_spin_angles[wheel_name] = spin_angle
		var roll_basis := Basis(Vector3.RIGHT, spin_angle)
		var wheel_original_basis: Basis = _wheel_original_bases[wheel_name]
		wheel.transform.basis = roll_basis * wheel_original_basis
		var hub := _hub_nodes.get(wheel_name) as Node3D
		if hub != null and _hub_original_bases.has(wheel_name):
			var hub_original_basis: Basis = _hub_original_bases[wheel_name]
			hub.transform.basis = roll_basis * hub_original_basis

func _enter_vehicle() -> void:
	if _player == null or _driver != null:
		return
	_driver = _player
	_saved_can_move = bool(_driver.get("can_move"))
	_saved_can_dash = bool(_driver.get("can_dash"))
	_driver.set("can_move", false)
	_driver.set("can_dash", false)
	_driver.velocity = Vector3.ZERO
	_driver.set_physics_process(false)
	var player_collider := _driver.get_node_or_null("Collider") as CollisionShape3D
	if player_collider != null:
		player_collider.disabled = true
	_player_visual = _driver.get_node_or_null("VisualRoot") as Node3D
	if _player_visual != null:
		_player_visual_parent = _player_visual.get_parent()
		_player_visual_transform = _player_visual.transform
		_player_visual.reparent(_rider_mount, false)
		var seated_basis := Basis.from_euler(Vector3(deg_to_rad(-12.0), 0.0, 0.0))
		seated_basis = seated_basis.scaled(Vector3.ONE * 0.9)
		_player_visual.transform = Transform3D(seated_basis, Vector3(0.0, -0.8, 0.08))
		_player_visual.visible = true
	var player_camera := _driver.get_node_or_null("Head/Camera3D") as Camera3D
	if player_camera != null:
		player_camera.current = false
	_vehicle_camera.current = true
	sleeping = false
	_interaction_lock = 0.35

func _exit_vehicle() -> void:
	if _driver == null:
		return
	var exiting_player := _driver
	_driver = null
	exiting_player.global_position = global_position + global_transform.basis.x * 2.4 + Vector3.UP * 0.65
	exiting_player.velocity = Vector3.ZERO
	var player_collider := exiting_player.get_node_or_null("Collider") as CollisionShape3D
	if player_collider != null:
		player_collider.disabled = false
	if _player_visual != null and _player_visual_parent != null:
		_player_visual.reparent(_player_visual_parent, false)
		_player_visual.transform = _player_visual_transform
		_player_visual.visible = true
	exiting_player.set("can_move", _saved_can_move)
	exiting_player.set("can_dash", _saved_can_dash)
	exiting_player.set_physics_process(true)
	var player_camera := exiting_player.get_node_or_null("Head/Camera3D") as Camera3D
	if player_camera != null:
		player_camera.current = true
	_interaction_lock = 0.35

func _update_prompt() -> void:
	if _driver != null:
		_prompt_label.visible = true
		_prompt_label.text = "W/S DRIVE  ·  A/D STEER  ·  SPACE BRAKE  ·  F EXIT"
	elif _player != null and _player.global_position.distance_to(global_position) <= interaction_distance:
		_prompt_label.visible = true
		_prompt_label.text = "F  ENTER ALL-TERRAIN VEHICLE"
	else:
		_prompt_label.visible = false

func is_driving() -> bool:
	return _driver != null
