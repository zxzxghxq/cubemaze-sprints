extends Node3D

@export_range(-360.0, 360.0, 5.0) var degrees_per_second: float = 90.0
@export var player_group: StringName = &"player"
@export var monster_group: StringName = &"tar_monster"
@export_range(0.5, 6.0, 0.1) var monster_recovery_seconds: float = 1.2
@export_range(3.0, 12.0, 0.1) var hazard_radius: float = 6.0
@export_range(1.5, 6.0, 0.1) var crossing_lane_offset: float = 3.4

var _player_cooldown: bool = false
var _monster_cooldown: bool = false


func _ready() -> void:
	add_to_group(&"rotating_hazard")
	for child in find_children("*", "Area3D", true, false):
		var area := child as Area3D
		area.body_entered.connect(_on_hazard_body_entered)


func _physics_process(delta: float) -> void:
	rotate_y(deg_to_rad(degrees_per_second) * delta)


func _on_hazard_body_entered(body: Node3D) -> void:
	if body.is_in_group(monster_group):
		_stun_monster(body)
		return
	if _player_cooldown or not body.is_in_group(player_group):
		return
	_player_cooldown = true

	var course := get_tree().get_first_node_in_group(&"level1_course")
	if course != null and course.has_method("reset_player"):
		course.call_deferred("reset_player", body)
		await get_tree().create_timer(0.75).timeout
		_player_cooldown = false
		return

	var death_ui := get_tree().get_first_node_in_group(&"death_ui")
	if death_ui != null and death_ui.has_method("trigger_death"):
		death_ui.call("trigger_death", body)
		return

	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		push_error("The rotating hazard could not reload the current level. Error code: " + str(reload_error))
	_player_cooldown = false


func _stun_monster(monster: Node3D) -> void:
	if _monster_cooldown:
		return
	_monster_cooldown = true
	if monster.has_method("hit_by_rotating_hazard"):
		monster.call_deferred("hit_by_rotating_hazard", self, monster_recovery_seconds)
	elif monster.has_method("stun"):
		monster.call_deferred("stun", monster_recovery_seconds)
	await get_tree().create_timer(monster_recovery_seconds + 2.0).timeout
	_monster_cooldown = false


func blocks_chase_path(start_position: Vector3, target_position: Vector3, body_radius: float) -> bool:
	var start := Vector2(start_position.x, start_position.z)
	var target := Vector2(target_position.x, target_position.z)
	var center := Vector2(global_position.x, global_position.z)
	var chase_segment := target - start
	if chase_segment.length_squared() <= 0.0001:
		return false
	var projection := (center - start).dot(chase_segment) / chase_segment.length_squared()
	if projection <= 0.0 or projection >= 1.0:
		return false
	return _distance_to_segment(center, start, target) <= hazard_radius + body_radius


func get_crossing_plan(
	start_position: Vector3,
	target_position: Vector3,
	body_radius: float,
	outer_bypass: bool = false
) -> Dictionary:
	var start := Vector2(start_position.x, start_position.z)
	var target := Vector2(target_position.x, target_position.z)
	var center := Vector2(global_position.x, global_position.z)
	var approach := (center - start).normalized()
	if approach.is_zero_approx():
		approach = (target - start).normalized()
	if approach.is_zero_approx():
		approach = Vector2(0.0, 1.0)

	var perpendicular := Vector2(-approach.y, approach.x)
	var target_lateral := (target - center).dot(perpendicular)
	if absf(target_lateral) < 0.1:
		target_lateral = (-center).dot(perpendicular)
	var side := 1.0 if target_lateral >= 0.0 else -1.0
	var lane_offset := crossing_lane_offset
	if outer_bypass:
		lane_offset = hazard_radius + body_radius + 0.8
		var positive_lane := center + perpendicular * lane_offset
		var negative_lane := center - perpendicular * lane_offset
		side = 1.0 if absf(positive_lane.x) <= absf(negative_lane.x) else -1.0
	var lane_center := center + perpendicular * lane_offset * side
	var longitudinal_extent := hazard_radius + body_radius + 0.8
	var wait_point := lane_center - approach * longitudinal_extent
	var exit_point := lane_center + approach * longitudinal_extent
	return {
		"wait_position": Vector3(wait_point.x, start_position.y, wait_point.y),
		"exit_position": Vector3(exit_point.x, start_position.y, exit_point.y),
	}


func get_safe_start_delay(
	start_position: Vector3,
	end_position: Vector3,
	crossing_speed: float,
	max_wait: float,
	clearance: float
) -> float:
	var delay := 0.0
	while delay <= max_wait + 0.001:
		if _crossing_is_safe(start_position, end_position, crossing_speed, delay, clearance):
			return delay
		delay += 0.05
	return max_wait


func _crossing_is_safe(
	start_position: Vector3,
	end_position: Vector3,
	crossing_speed: float,
	start_delay: float,
	clearance: float
) -> bool:
	var start := Vector2(start_position.x, start_position.z)
	var finish := Vector2(end_position.x, end_position.z)
	var center := Vector2(global_position.x, global_position.z)
	var distance := start.distance_to(finish)
	var travel_time := distance / maxf(crossing_speed, 0.1)
	var sample_count := maxi(1, ceili(travel_time / 0.04))
	var angular_speed := deg_to_rad(degrees_per_second)
	var starting_angle := global_rotation.y

	for index in range(sample_count + 1):
		var progress := float(index) / float(sample_count)
		var time := travel_time * progress
		var point := start.lerp(finish, progress)
		if point.distance_to(center) < 0.75 + clearance:
			return false

		var angle := starting_angle + angular_speed * (start_delay + time)
		var arm_x := Vector2(cos(angle), -sin(angle))
		var arm_z := Vector2(sin(angle), cos(angle))
		var x_start := center - arm_x * hazard_radius
		var x_end := center + arm_x * hazard_radius
		var z_start := center - arm_z * hazard_radius
		var z_end := center + arm_z * hazard_radius
		if (
			_distance_to_segment(point, x_start, x_end) < clearance
			or _distance_to_segment(point, z_start, z_end) < clearance
		):
			return false
	return true


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)
