@tool
extends Node3D

const NEXT_SCENE_PATH: String = "res://scenes/mainscience.tscn"
const LEVEL_TRANSITION_DELAY: float = 2.0

const STATIONS := [
	{"name": "FOREST RELAY", "position": Vector2(-60.0, 50.0), "color": Color(0.2, 0.85, 0.42)},
	{"name": "ICE RELAY", "position": Vector2(18.0, 52.0), "color": Color(0.2, 0.72, 1.0)},
	{"name": "RIDGE RELAY", "position": Vector2(80.0, 76.0), "color": Color(1.0, 0.62, 0.18)},
]
const ROUTES := [
	[
		Vector2(-84.0, -80.0), Vector2(-68.0, -66.0), Vector2(-54.0, -49.0),
		Vector2(-48.0, -30.0), Vector2(-64.0, -8.0), Vector2(-82.0, 24.0),
		Vector2(-72.0, 42.0), Vector2(-60.0, 50.0),
	],
	[
		Vector2(-54.0, -49.0), Vector2(-31.0, -43.0), Vector2(-13.0, -24.0),
		Vector2(10.0, -29.0), Vector2(29.0, -8.0), Vector2(20.0, 18.0),
		Vector2(7.0, 37.0), Vector2(18.0, 52.0),
	],
	[
		Vector2(-60.0, 50.0), Vector2(-37.0, 61.0), Vector2(-12.0, 52.0),
		Vector2(18.0, 52.0), Vector2(39.0, 40.0), Vector2(60.0, 55.0),
		Vector2(80.0, 76.0), Vector2(95.0, 86.0), Vector2(104.0, 100.0),
	],
]
const ROUTE_NAMES := ["FOREST TRACK", "FROZEN RIVER", "RIDGE ROAD"]
const BASE_POSITION := Vector2(-84.0, -80.0)
const EXIT_POSITION := Vector2(104.0, 100.0)
const MONSTER_SPAWNS := [
	Vector2(-78.0, 34.0), Vector2(3.0, 39.0), Vector2(61.0, 60.0),
]

var _snow_level: Node3D
var _player: CharacterBody3D
var _atv: RigidBody3D
var _monster: CharacterBody3D
var _world: Node3D
var _station_nodes: Array[Node3D] = []
var _shelter_nodes: Array[Node3D] = []
var _active_stations: Array[bool] = [false, false, false]
var _has_energy_core: bool = false
var _checkpoint := Vector3.ZERO
var _resetting: bool = false
var _finished: bool = false
var _transition_started: bool = false
var _evacuation: bool = false
var _player_hidden: bool = false
var _charging_station: int = -1
var _charge_progress: float = 0.0
var _avalanche_distance: float = 0.0
var _message_time_left: float = 0.0

var _objective_label: Label
var _relay_label: Label
var _prompt_label: Label
var _message_label: Label
var _finish_panel: Control

var _snow_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _ice_material: StandardMaterial3D
var _metal_material: StandardMaterial3D
var _wood_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _safe_material: StandardMaterial3D
var _danger_material: StandardMaterial3D

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	_snow_level = get_parent() as Node3D
	_make_materials()
	_world = get_node_or_null("MissionWorld") as Node3D
	if _world == null:
		_world = Node3D.new()
		_world.name = "MissionWorld"
		add_child(_world)
		_build_mission_world()
	if Engine.is_editor_hint():
		_make_editor_world_editable(_world)
		return
	_cache_world_nodes()
	_player = _snow_level.get_node_or_null("Player") as CharacterBody3D
	_atv = _snow_level.get_node_or_null("SnowATV") as RigidBody3D
	_monster = _snow_level.get_node_or_null("SnowStalker") as CharacterBody3D
	if _player == null or _atv == null or _monster == null:
		push_error("Snow mission is missing Player, SnowATV, or SnowStalker.")
		return
	_checkpoint = _ground_position(BASE_POSITION) + Vector3(0.0, 0.7, 0.0)
	if _monster.has_signal("caught_player"):
		_monster.caught_player.connect(_on_monster_caught_player)
	_setup_hud()
	_update_hud()
	_show_message("Recover the emergency energy core beside the command tent.", 5.0)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _player == null or _finished:
		return
	if _message_time_left > 0.0:
		_message_time_left = maxf(_message_time_left - delta, 0.0)
		if _message_time_left <= 0.0 and _message_label != null:
			_message_label.text = ""
	if _evacuation and _subject_distance_to_exit() <= 7.0:
		_finish_mission()
		return
	_update_charging(delta)
	_update_shelter_state()
	_update_avalanche(delta)
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _finished or _resetting:
		return
	if not event.is_action_pressed(&"interact") or event.is_echo():
		return
	if _atv != null and _atv.has_method("is_driving") and bool(_atv.call("is_driving")):
		return
	if not _has_energy_core and _distance_to_point(BASE_POSITION) <= 4.2:
		_pick_up_energy_core()
		get_viewport().set_input_as_handled()
		return
	var station_index := _nearest_inactive_station()
	if station_index >= 0:
		_start_station_charge(station_index)
		get_viewport().set_input_as_handled()

func _make_materials() -> void:
	_snow_material = _material(Color(0.88, 0.94, 0.98), 0.94)
	_road_material = _material(Color(0.58, 0.66, 0.72), 0.98)
	_ice_material = _material(Color(0.22, 0.68, 0.9, 0.7), 0.26)
	_ice_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_metal_material = _material(Color(0.15, 0.19, 0.23), 0.42, 0.72)
	_wood_material = _material(Color(0.24, 0.12, 0.055), 0.98)
	_dark_material = _material(Color(0.025, 0.035, 0.052), 0.88)
	_safe_material = _emissive_material(Color(0.18, 0.9, 0.4), 2.4)
	_danger_material = _emissive_material(Color(1.0, 0.16, 0.08), 3.2)

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.45)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _build_mission_world() -> void:
	_build_routes()
	_build_base_camp()
	for index in range(STATIONS.size()):
		_build_relay_station(index)
	_build_exit_tunnel()
	_build_avalanche_front()

func _build_routes() -> void:
	for route_index in range(ROUTES.size()):
		var route_root := Node3D.new()
		route_root.name = ROUTE_NAMES[route_index].to_pascal_case().replace(" ", "")
		_world.add_child(route_root)
		var material := _ice_material if route_index == 1 else _road_material
		var width := 7.0 if route_index == 1 else 5.6
		var route: Array = ROUTES[route_index]
		for index in range(route.size() - 1):
			_add_route_segment(route_root, route[index], route[index + 1], width, material)
	_add_route_sign(Vector2(-55.0, -49.0), "FOREST  <    >  FROZEN RIVER")
	_add_route_sign(Vector2(18.0, 52.0), "FOREST LINK  <    >  RIDGE ROAD")
	_add_route_sign(Vector2(82.0, 77.0), "EVACUATION TUNNEL  >")

func _add_route_segment(parent: Node3D, start: Vector2, finish: Vector2, width: float,
		material: Material) -> void:
	var distance := start.distance_to(finish)
	var steps := maxi(1, int(ceil(distance / 3.2)))
	for step in range(steps):
		var ratio_a := float(step) / float(steps)
		var ratio_b := float(step + 1) / float(steps)
		var point_a := start.lerp(finish, ratio_a)
		var point_b := start.lerp(finish, ratio_b)
		var position_a := _ground_position(point_a) + Vector3.UP * 0.07
		var position_b := _ground_position(point_b) + Vector3.UP * 0.07
		var direction := position_b - position_a
		var slab := _visual_box(parent, "RouteSlab", (position_a + position_b) * 0.5,
			Vector3(width, 0.08, Vector2(direction.x, direction.z).length() + 0.35), material)
		slab.rotation.y = atan2(direction.x, direction.z)

func _build_base_camp() -> void:
	var camp := Node3D.new()
	camp.name = "BaseCamp"
	camp.position = _ground_position(BASE_POSITION)
	_world.add_child(camp)
	_add_box_body(camp, "CommandFloor", Vector3(0, 0.12, 0), Vector3(11, 0.24, 9), _road_material)
	_add_box_body(camp, "TentBack", Vector3(-3.8, 1.6, 1.5), Vector3(0.25, 3.2, 6), _dark_material)
	_add_box_body(camp, "TentRoof", Vector3(-1.8, 3.15, 1.5), Vector3(4.2, 0.22, 6), _dark_material)
	var core := Node3D.new()
	core.name = "EnergyCorePickup"
	core.position = Vector3(0.2, 1.0, 3.0)
	camp.add_child(core)
	_add_cylinder(core, "Core", Vector3.ZERO, 0.42, 1.2,
		_emissive_material(Color(0.15, 0.78, 1.0), 3.5), false)
	var core_light := OmniLight3D.new()
	core_light.name = "CoreLight"
	core_light.light_color = Color(0.15, 0.72, 1.0)
	core_light.light_energy = 2.2
	core_light.omni_range = 6.0
	core.add_child(core_light)
	_add_label(camp, "CommandLabel", Vector3(0, 3.8, -2.8), "MOUNTAIN RESCUE COMMAND")

func _build_relay_station(index: int) -> void:
	var data: Dictionary = STATIONS[index]
	var station := Node3D.new()
	station.name = "RelayStation%d" % index
	station.position = _ground_position(data["position"])
	station.set_meta("station_index", index)
	_world.add_child(station)
	_add_box_body(station, "Platform", Vector3(0, 0.16, 0), Vector3(9, 0.32, 9), _road_material)
	_add_cylinder(station, "Tower", Vector3(0, 3.3, 0), 0.42, 6.4, _metal_material, true)
	_add_box_body(station, "AntennaCross", Vector3(0, 5.6, 0), Vector3(4.2, 0.14, 0.14), _metal_material)
	_add_box_body(station, "ControlBox", Vector3(1.7, 1.1, -1.2), Vector3(1.1, 2.0, 0.8), _metal_material)
	var lamp := _add_sphere(station, "StatusLamp", Vector3(0, 6.65, 0), 0.42, _danger_material)
	var light := OmniLight3D.new()
	light.name = "StatusLight"
	light.position = Vector3(0, 6.65, 0)
	light.light_color = Color(1.0, 0.1, 0.06)
	light.light_energy = 2.4
	light.omni_range = 11.0
	station.add_child(light)
	_add_label(station, "StationLabel", Vector3(0, 3.4, -2.4), data["name"])
	_build_shelter(index, data["position"] + Vector2(7.0, -2.0))

func _build_shelter(index: int, point: Vector2) -> void:
	var shelter := Node3D.new()
	shelter.name = "Shelter%d" % index
	shelter.position = _ground_position(point)
	shelter.set_meta("shelter_radius", 3.0)
	_world.add_child(shelter)
	_add_box_body(shelter, "Floor", Vector3.ZERO, Vector3(5.2, 0.22, 5.2), _road_material)
	_add_box_body(shelter, "BackWall", Vector3(0, 1.65, 2.45), Vector3(5.2, 3.3, 0.25), _wood_material)
	_add_box_body(shelter, "LeftWall", Vector3(-2.45, 1.65, 0), Vector3(0.25, 3.3, 5.2), _wood_material)
	_add_box_body(shelter, "RightWall", Vector3(2.45, 1.65, 0), Vector3(0.25, 3.3, 5.2), _wood_material)
	_add_box_body(shelter, "Roof", Vector3(0, 3.35, 0), Vector3(5.5, 0.3, 5.5), _snow_material)
	_add_label(shelter, "SafeLabel", Vector3(0, 2.4, -2.55), "SAFE SHELTER")

func _build_exit_tunnel() -> void:
	var tunnel := Node3D.new()
	tunnel.name = "EvacuationTunnel"
	tunnel.position = _ground_position(EXIT_POSITION)
	_world.add_child(tunnel)
	_add_box_body(tunnel, "LeftPillar", Vector3(-3.4, 3.2, 0), Vector3(1.3, 6.4, 5.5), _dark_material)
	_add_box_body(tunnel, "RightPillar", Vector3(3.4, 3.2, 0), Vector3(1.3, 6.4, 5.5), _dark_material)
	_add_box_body(tunnel, "Roof", Vector3(0, 6.1, 0), Vector3(8.0, 1.0, 5.5), _dark_material)
	_add_box_body(tunnel, "TunnelDarkness", Vector3(0, 3.0, 2.6), Vector3(5.6, 5.5, 0.25), _dark_material)
	_add_label(tunnel, "ExitLabel", Vector3(0, 5.0, -2.9), "EMERGENCY EVACUATION TUNNEL")

func _build_avalanche_front() -> void:
	var avalanche := Node3D.new()
	avalanche.name = "AvalancheFront"
	avalanche.visible = false
	_world.add_child(avalanche)
	var cloud_material := _material(Color(0.84, 0.92, 0.98, 0.88), 1.0)
	cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for x_index in range(-3, 4):
		for y_index in range(2):
			var cloud := _add_sphere(avalanche, "SnowCloud", Vector3(x_index * 2.4,
				float(y_index) * 2.0, sin(float(x_index) * 1.7) * 1.3), 2.2, cloud_material)
			cloud.scale = Vector3(1.45, 0.9, 1.25)

func _cache_world_nodes() -> void:
	_station_nodes.clear()
	_shelter_nodes.clear()
	for index in range(STATIONS.size()):
		_station_nodes.append(_world.get_node("RelayStation%d" % index) as Node3D)
		_shelter_nodes.append(_world.get_node("Shelter%d" % index) as Node3D)

func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "SnowMissionHUD"
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(390, 0)
	hud.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	margin.add_child(rows)
	_objective_label = _hud_label(rows, 22, Color.WHITE)
	_relay_label = _hud_label(rows, 18, Color(0.65, 0.88, 1.0))

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 24)
	_prompt_label.add_theme_color_override("font_color", Color.WHITE)
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07))
	_prompt_label.add_theme_constant_override("outline_size", 7)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-430, -120)
	_prompt_label.size = Vector2(860, 48)
	hud.add_child(_prompt_label)

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 23)
	_message_label.add_theme_color_override("font_color", Color(0.78, 0.93, 1.0))
	_message_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07))
	_message_label.add_theme_constant_override("outline_size", 7)
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.position = Vector2(-500, 90)
	_message_label.size = Vector2(1000, 54)
	hud.add_child(_message_label)
	_build_finish_panel(hud)

func _hud_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _build_finish_panel(hud: CanvasLayer) -> void:
	_finish_panel = ColorRect.new()
	_finish_panel.color = Color(0.015, 0.035, 0.06, 0.9)
	_finish_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_panel.visible = false
	hud.add_child(_finish_panel)
	var title := Label.new()
	title.text = "MOUNTAIN RELAY RESTORED\nEVACUATION COMPLETE\n\nAll three rescue channels are online.\nReturning to the main area..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.7, 0.94, 1.0))
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_panel.add_child(title)

func _update_hud() -> void:
	if _objective_label == null:
		return
	var relay_count := _count_active_stations()
	if not _has_energy_core:
		_objective_label.text = "OBJECTIVE: RECOVER THE ENERGY CORE"
	elif not _evacuation:
		_objective_label.text = "OBJECTIVE: RESTORE ALL MOUNTAIN RELAYS"
	else:
		_objective_label.text = "OBJECTIVE: REACH THE EVACUATION TUNNEL"
	_relay_label.text = "RELAYS ONLINE: %d / 3" % relay_count
	_prompt_label.text = _current_prompt()

func _current_prompt() -> String:
	if _atv != null and _atv.has_method("is_driving") and bool(_atv.call("is_driving")):
		return ""
	if not _has_energy_core and _distance_to_point(BASE_POSITION) <= 4.2:
		return "F  LOAD EMERGENCY ENERGY CORE"
	if _charging_station >= 0:
		return "CHARGING RELAY... %d%%" % int((_charge_progress / 3.5) * 100.0)
	var station_index := _nearest_inactive_station()
	if station_index >= 0:
		return "F  CONNECT ENERGY CORE TO %s" % STATIONS[station_index]["name"]
	if _evacuation and _subject_distance_to_exit() <= 14.0:
		return "ENTER THE TUNNEL - SAFE ZONE AHEAD"
	return ""

func _pick_up_energy_core() -> void:
	_has_energy_core = true
	var pickup := _world.get_node_or_null("BaseCamp/EnergyCorePickup") as Node3D
	if pickup != null:
		pickup.visible = false
	var cargo := Node3D.new()
	cargo.name = "MountedEnergyCore"
	cargo.position = Vector3(0.0, 1.7, 0.75)
	_atv.add_child(cargo)
	_add_cylinder(cargo, "EnergyCell", Vector3.ZERO, 0.32, 1.05,
		_emissive_material(Color(0.12, 0.72, 1.0), 3.0), false, Vector3(90, 0, 0))
	_show_message("Core secured. Restore all three relay stations.", 4.0)

func _nearest_inactive_station() -> int:
	if not _has_energy_core or _player == null:
		return -1
	for index in range(STATIONS.size()):
		if not _active_stations[index] and _distance_to_point(STATIONS[index]["position"]) <= 4.8:
			return index
	return -1

func _start_station_charge(index: int) -> void:
	if _charging_station >= 0:
		return
	_charging_station = index
	_charge_progress = 0.0
	_show_message("Stay near the control box while the relay charges.", 3.0)

func _update_charging(delta: float) -> void:
	if _charging_station < 0:
		return
	if _distance_to_point(STATIONS[_charging_station]["position"]) > 5.2:
		_show_message("Relay connection lost. Return to the control box.", 2.5)
		_charging_station = -1
		_charge_progress = 0.0
		return
	_charge_progress += delta
	if _charge_progress >= 3.5:
		_complete_station(_charging_station)
		_charging_station = -1
		_charge_progress = 0.0

func _complete_station(index: int) -> void:
	if _active_stations[index]:
		return
	_active_stations[index] = true
	var station := _station_nodes[index]
	var lamp := station.get_node_or_null("StatusLamp") as MeshInstance3D
	if lamp != null:
		lamp.material_override = _safe_material
	var light := station.get_node_or_null("StatusLight") as OmniLight3D
	if light != null:
		light.light_color = Color(0.15, 1.0, 0.4)
	_checkpoint = station.global_position + Vector3(0.0, 0.8, -4.5)
	_show_message("%s ONLINE. Checkpoint updated." % STATIONS[index]["name"], 4.0)
	var spawn := _ground_position(MONSTER_SPAWNS[index]) + Vector3.UP * 0.5
	if _count_active_stations() == 1:
		_monster.call("activate", spawn, false)
	elif _monster != null and not bool(_monster.get("active")):
		_monster.call("activate", spawn, false)
	if _count_active_stations() == STATIONS.size():
		_begin_evacuation()

func _count_active_stations() -> int:
	var count := 0
	for active in _active_stations:
		if active:
			count += 1
	return count

func _update_shelter_state() -> void:
	var hidden := false
	if not bool(_atv.call("is_driving")):
		for shelter in _shelter_nodes:
			var flat_distance := Vector2(_player.global_position.x, _player.global_position.z).distance_to(
				Vector2(shelter.global_position.x, shelter.global_position.z)
			)
			if flat_distance <= float(shelter.get_meta("shelter_radius", 3.0)):
				hidden = true
				break
	if hidden != _player_hidden:
		_player_hidden = hidden
		_monster.call("set_player_hidden", hidden)
		if hidden:
			_show_message("Hidden. The Frost Stalker is searching your last position.", 3.0)

func _begin_evacuation() -> void:
	_evacuation = true
	_monster.set("enraged", true)
	if _monster.has_method("set_safe_zone"):
		_monster.call("set_safe_zone", _ground_position(EXIT_POSITION), 8.0)
	var avalanche := _world.get_node_or_null("AvalancheFront") as Node3D
	if avalanche != null:
		avalanche.visible = true
		avalanche.global_position = _ground_position(Vector2(66.0, 62.0)) + Vector3.UP * 2.0
	_avalanche_distance = 0.0
	var world_environment := _snow_level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment != null and world_environment.environment != null:
		world_environment.environment = world_environment.environment.duplicate()
		world_environment.environment.fog_density = 0.015
	var snowfall := _snow_level.get_node_or_null("GeneratedSnowWorld/Snowfall") as GPUParticles3D
	if snowfall != null:
		snowfall.amount = 4200
	_show_message("AVALANCHE WARNING! Drive to the evacuation tunnel!", 6.0)

func _update_avalanche(delta: float) -> void:
	if not _evacuation:
		return
	if _subject_distance_to_exit() <= 8.0:
		return
	var avalanche := _world.get_node_or_null("AvalancheFront") as Node3D
	if avalanche == null:
		return
	var target := _ground_position(EXIT_POSITION) + Vector3.UP * 2.0
	var direction := target - avalanche.global_position
	if direction.length() > 1.0:
		avalanche.global_position += direction.normalized() * 7.2 * delta
		avalanche.rotate_y(delta * 0.18)
	var subject := _atv as Node3D if bool(_atv.call("is_driving")) else _player as Node3D
	if avalanche.global_position.distance_to(subject.global_position) <= 6.0:
		_reset_after_failure("CAUGHT BY THE AVALANCHE")

func _on_monster_caught_player() -> void:
	_reset_after_failure("CAUGHT BY THE FROST STALKER")

func _reset_after_failure(reason: String) -> void:
	if _resetting or _finished:
		return
	_resetting = true
	_show_message(reason + " - RETURNING TO CHECKPOINT", 3.0)
	if bool(_atv.call("is_driving")):
		_atv.call("_exit_vehicle")
	if _player.has_method("cancel_active_movement"):
		_player.call("cancel_active_movement")
	_player.global_position = _checkpoint
	_player.velocity = Vector3.ZERO
	_atv.global_position = _checkpoint + Vector3(4.0, 1.0, 0.0)
	_atv.linear_velocity = Vector3.ZERO
	_atv.angular_velocity = Vector3.ZERO
	_atv.rotation = Vector3(0.0, 0.62, 0.0)
	var monster_spawn_2d := Vector2(_checkpoint.x - 20.0, _checkpoint.z - 16.0)
	var monster_spawn := _ground_position(monster_spawn_2d) + Vector3.UP * 0.5
	_monster.call("reset_chase", monster_spawn, 1.7)
	if _evacuation:
		var avalanche := _world.get_node_or_null("AvalancheFront") as Node3D
		if avalanche != null:
			avalanche.global_position = _ground_position(Vector2(66.0, 62.0)) + Vector3.UP * 2.0
	await get_tree().create_timer(1.0).timeout
	_resetting = false

func _finish_mission() -> void:
	if _finished or _transition_started:
		return
	_finished = true
	_transition_started = true
	if bool(_atv.call("is_driving")):
		_atv.call("_exit_vehicle")
	_player.set("can_move", false)
	_player.set("can_dash", false)
	_atv.freeze = true
	_monster.call("deactivate")
	var avalanche := _world.get_node_or_null("AvalancheFront") as Node3D
	if avalanche != null:
		avalanche.visible = false
	_finish_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_return_to_main_scene.call_deferred()

func _return_to_main_scene() -> void:
	await get_tree().create_timer(LEVEL_TRANSITION_DELAY).timeout
	get_tree().paused = false
	var change_error := get_tree().change_scene_to_file(NEXT_SCENE_PATH)
	if change_error != OK:
		_transition_started = false
		push_error("Unable to return to the main scene. Error code: %s" % change_error)

func _show_message(message: String, duration: float) -> void:
	if _message_label == null:
		return
	_message_label.text = message
	_message_time_left = maxf(duration, 0.0)

func _distance_to_point(point: Vector2) -> float:
	if _player == null:
		return INF
	return Vector2(_player.global_position.x, _player.global_position.z).distance_to(point)

func _subject_distance_to_exit() -> float:
	if _player == null or _atv == null:
		return INF
	var subject := _atv as Node3D if bool(_atv.call("is_driving")) else _player as Node3D
	return Vector2(subject.global_position.x, subject.global_position.z).distance_to(EXIT_POSITION)

func _ground_position(point: Vector2) -> Vector3:
	var height := 0.0
	if _snow_level != null and _snow_level.has_method("_terrain_height"):
		height = float(_snow_level.call("_terrain_height", point.x, point.y))
	return Vector3(point.x, height, point.y)

func _visual_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	parent.add_child(instance)
	return instance

func _add_box_body(parent: Node3D, node_name: String, position: Vector3, size: Vector3,
		material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	parent.add_child(body)
	_visual_box(body, "Mesh", Vector3.ZERO, size, material)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	return body

func _add_cylinder(parent: Node3D, node_name: String, position: Vector3, radius: float,
		height: float, material: Material, collision: bool,
		rotation_degrees_value: Vector3 = Vector3.ZERO) -> Node3D:
	var root := StaticBody3D.new() if collision else Node3D.new()
	root.name = node_name
	root.position = position
	root.rotation_degrees = rotation_degrees_value
	parent.add_child(root)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	root.add_child(instance)
	if collision:
		var collider := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collider.shape = shape
		root.add_child(collider)
	return root

func _add_sphere(parent: Node3D, node_name: String, position: Vector3, radius: float,
		material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	parent.add_child(instance)
	return instance

func _add_label(parent: Node3D, node_name: String, position: Vector3, text: String) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.position = position
	label.text = text
	label.font_size = 42
	label.outline_size = 8
	label.modulate = Color(0.82, 0.94, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _add_route_sign(point: Vector2, text: String) -> void:
	var position := _ground_position(point)
	_add_cylinder(_world, "SignPole", position + Vector3.UP * 1.5, 0.08, 3.0,
		_wood_material, true)
	_add_label(_world, "RouteSign", position + Vector3.UP * 3.15, text)

func _make_editor_world_editable(node: Node) -> void:
	var edited_root := get_tree().edited_scene_root
	if edited_root == null:
		return
	_set_owner_recursive(node, edited_root)

func _set_owner_recursive(node: Node, edited_root: Node) -> void:
	node.owner = edited_root
	for child in node.get_children():
		_set_owner_recursive(child, edited_root)
