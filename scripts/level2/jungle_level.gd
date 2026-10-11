extends Node3D

const RUNE_ORDER: Array[String] = ["FROG", "LEAF", "MOON"]
const NEXT_LEVEL_PATH: String = "res://scenes/mainscience.tscn"

var player: CharacterBody3D
var stalker: JungleStalker
var cave_gate: StaticBody3D
var cave_gate_collider: CollisionShape3D
var exit_gate: StaticBody3D
var exit_gate_collider: CollisionShape3D
var heavy_box: StaticBody3D
var heavy_box_collider: CollisionShape3D
var pit_door: StaticBody3D
var pit_door_collider: CollisionShape3D
var exit_area: Area3D
var water_hazard: Area3D
var pit_hazard: Area3D
var start_spawn: Marker3D
var stalker_spawn_vine: Marker3D
var stalker_spawn_rune: Marker3D
var prompt_label: Label
var map_panel: PanelContainer
var map_title_label: Label
var map_text_label: Label
var damage_flash: ColorRect

var has_map: bool = false
var has_vine_key: bool = false
var has_obsidian_key: bool = false
var rune_progress: Array[String] = []
var sun_switch_on: bool = false
var river_switch_on: bool = false
var heavy_box_used: bool = false
var pit_lever_used: bool = false
var cave_gate_open: bool = false
var exit_gate_open: bool = false
var player_is_hidden: bool = false
var finished: bool = false
var _transition_started: bool = false
var _pit_active: bool = false
var _resetting_player: bool = false
var _current_checkpoint := Vector3(-105.0, 1.0, -105.0)
var _current_monster_spawn := Vector3(0.0, 1.0, -32.0)
var _stage_name: String = "EMERALD RUINS"
var _latest_note: String = "Find the jungle map in the middle of the main road."
var _map_hint_id: int = 0
var _saved_dash: bool = true
var _setup_done: bool = false

func _ready() -> void:
	add_to_group(&"jungle_course")
	# The maze is built by WorldBuilder on a deferred call; wait until it exists.
	await get_tree().process_frame
	await get_tree().process_frame
	_restore_interaction_groups()
	player = $Player
	stalker = $JungleStalker
	cave_gate = $Architecture/Gates/CaveGate
	cave_gate_collider = $Architecture/Gates/CaveGate/CollisionShape3D
	exit_gate = $Architecture/Gates/ExitGate
	exit_gate_collider = $Architecture/Gates/ExitGate/CollisionShape3D
	heavy_box = $Traps/HeavyBox
	heavy_box_collider = $Traps/HeavyBox/CollisionShape3D
	pit_door = $Traps/PitDoor
	pit_door_collider = $Traps/PitDoor/CollisionShape3D
	exit_area = $Gameplay/ExitArea
	water_hazard = $Gameplay/WaterHazard
	pit_hazard = $Gameplay/PitHazard
	start_spawn = $Gameplay/StartSpawn
	stalker_spawn_vine = $Gameplay/StalkerSpawnVine
	stalker_spawn_rune = $Gameplay/StalkerSpawnRune
	prompt_label = $HUD/PromptPanel/PromptMargin/PromptLabel
	map_panel = $HUD/MapPanel
	map_title_label = $HUD/MapPanel/MapMargin/MapRows/Title
	map_text_label = $HUD/MapPanel/MapMargin/MapRows/MapText
	damage_flash = $HUD/DamageFlash
	map_panel.visible = false
	damage_flash.visible = false
	prompt_label.text = "M  OPEN MAP"
	$HUD/PromptPanel.visible = false
	heavy_box_collider.disabled = true
	exit_area.body_entered.connect(_on_exit_area_body_entered)
	stalker.caught_player.connect(_on_stalker_caught_player)
	var grotto_cp: Area3D = $Gameplay/CheckpointGrotto
	var temple_cp: Area3D = $Gameplay/CheckpointTemple
	grotto_cp.body_entered.connect(_on_checkpoint_entered.bind(grotto_cp))
	temple_cp.body_entered.connect(_on_checkpoint_entered.bind(temple_cp))
	var map_pickup := get_node_or_null("Interactables/MapPickup") as Area3D
	if map_pickup != null:
		map_pickup.body_entered.connect(_on_map_pickup_body_entered.bind(map_pickup))
	_current_checkpoint = start_spawn.global_position
	_setup_done = true

func _restore_interaction_groups() -> void:
	# Runtime-built groups are not retained when the generated scene is saved.
	# Restore them from the interaction metadata without recreating deleted visuals.
	for container_name in [&"Interactables", &"SafePlaces"]:
		var container := get_node_or_null(NodePath(container_name))
		if container == null:
			continue
		for child in container.get_children():
			if not child is Node3D or not child.has_meta("action"):
				continue
			var interactable := child as Node3D
			interactable.add_to_group(&"jungle_interactable")
			if str(interactable.get_meta("action")).begins_with("rune_"):
				interactable.add_to_group(&"jungle_rune")

func _process(delta: float) -> void:
	if not _setup_done or finished:
		return
	if _resetting_player:
		return
	_update_hazards()
	if map_panel.visible:
		_update_map_text()
	if player.global_position.y < -8.0:
		_reset_player("You fell into the jungle depths.")

func _unhandled_input(event: InputEvent) -> void:
	if not _setup_done or finished or _resetting_player or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_M:
		_toggle_map()
		get_viewport().set_input_as_handled()
	elif key.is_action_pressed(&"interact"):
		_interact()
		get_viewport().set_input_as_handled()

func _toggle_map() -> void:
	if not has_map:
		return
	_map_hint_id += 1
	$HUD/PromptPanel.visible = false
	map_panel.visible = not map_panel.visible
	if map_panel.visible:
		_update_map_text()

func _interact() -> void:
	if player_is_hidden:
		_leave_hiding_place()
		return
	var target := _nearest_interactable()
	if target == null:
		_show_message("Nothing to interact with here.", 1.2)
		return
	var action := str(target.get_meta("action", ""))
	match action:
		"pickup_map":
			_acquire_map(target)
		"pickup_vine_key":
			has_vine_key = true
			_consume_interactable(target)
			_show_message("Vine Key found! Something woke up behind you...", 4.0)
			stalker.activate(stalker_spawn_vine.global_position)
			_try_open_cave_gate()
		"pickup_obsidian_key":
			has_obsidian_key = true
			_consume_interactable(target)
			_show_message("Obsidian Key found! Head to the sealed exit.", 4.0)
			_try_open_exit_gate()
		"rune_frog":
			_press_rune("FROG", target)
		"rune_leaf":
			_press_rune("LEAF", target)
		"rune_moon":
			_press_rune("MOON", target)
		"sun_switch":
			if not sun_switch_on:
				sun_switch_on = true
				_mark_interactable_used(target, Color(0.95, 0.72, 0.18))
				_show_message("Sun altar activated!", 2.5)
				_try_open_exit_gate()
		"river_switch":
			if not river_switch_on:
				river_switch_on = true
				_mark_interactable_used(target, Color(0.1, 0.65, 0.95))
				_show_message("River altar activated!", 2.5)
				_try_open_exit_gate()
		"heavy_box_lever":
			_release_heavy_box(target)
		"pit_lever":
			_open_pit_trap(target)
		"safe_hide":
			_enter_hiding_place(target)

func _nearest_interactable() -> Node3D:
	var nearest: Node3D
	var nearest_distance := 4.25
	for candidate in get_tree().get_nodes_in_group(&"jungle_interactable"):
		if not candidate is Node3D:
			continue
		var node := candidate as Node3D
		if not node.visible or bool(node.get_meta("used", false)):
			continue
		var distance := player.global_position.distance_to(node.global_position)
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest

func _consume_interactable(node: Node3D) -> void:
	node.set_meta("used", true)
	node.visible = false

func _on_map_pickup_body_entered(body: Node3D, map_pickup: Area3D) -> void:
	if not _setup_done or has_map or not body.is_in_group(&"player"):
		return
	_acquire_map(map_pickup)

func _acquire_map(map_pickup: Node3D) -> void:
	if has_map or bool(map_pickup.get_meta("used", false)):
		return
	has_map = true
	_consume_interactable(map_pickup)
	_show_message("Map acquired. Press M to open it.", 5.0)
	_show_map_pickup_hint()

func _mark_interactable_used(node: Node3D, color: Color) -> void:
	node.set_meta("used", true)
	var light := node.get_node_or_null("Glow") as OmniLight3D
	if light != null:
		light.light_color = color
		light.light_energy = 3.0
	var mesh_container := node.get_node_or_null("Mesh")
	if mesh_container != null:
		var material := StandardMaterial3D.new()
		material.albedo_color = color.darkened(0.25)
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.5
		_apply_mesh_override(mesh_container, material)

func _press_rune(rune: String, node: Node3D) -> void:
	var expected := RUNE_ORDER[rune_progress.size()]
	if rune == expected:
		rune_progress.append(rune)
		_mark_interactable_used(node, Color(0.25, 1.0, 0.35))
		_show_message("Rune %d/3 correct: %s" % [rune_progress.size(), rune], 2.0)
		if rune_progress.size() == RUNE_ORDER.size():
			_show_message("All three runes resonate. The stone gate is unlocked!", 4.0)
			_try_open_cave_gate()
		return
	rune_progress.clear()
	for rune_node in get_tree().get_nodes_in_group(&"jungle_rune"):
		rune_node.set_meta("used", false)
		_reset_interactable_visual(rune_node)
	_show_message("Wrong rune order! The monster is enraged.", 4.0)
	stalker.enraged = true
	if not stalker.active:
		stalker.activate(stalker_spawn_rune.global_position, true)

func _reset_interactable_visual(node: Node) -> void:
	var mesh_container := node.get_node_or_null("Mesh")
	if mesh_container != null:
		_apply_mesh_override(mesh_container, null)
	var light := node.get_node_or_null("Glow") as OmniLight3D
	if light != null:
		light.light_color = Color(0.2, 0.65, 0.32)
		light.light_energy = 1.6

func _apply_mesh_override(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
		elif child is Node3D:
			_apply_mesh_override(child, material)

func _try_open_cave_gate() -> void:
	if cave_gate_open or not has_vine_key or rune_progress.size() != RUNE_ORDER.size():
		return
	cave_gate_open = true
	cave_gate_collider.set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cave_gate, "position:y", 8.5, 1.6)

func _try_open_exit_gate() -> void:
	if exit_gate_open or not has_obsidian_key or not sun_switch_on or not river_switch_on:
		return
	exit_gate_open = true
	exit_gate_collider.set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(exit_gate, "position:y", 9.5, 1.8)
	_show_message("Exit unsealed — RUN!", 5.0)
	stalker.enraged = true

func _enter_hiding_place(node: Node3D) -> void:
	player_is_hidden = true
	_saved_dash = bool(player.get("can_dash"))
	player.set("can_move", false)
	player.set("can_dash", false)
	player.velocity = Vector3.ZERO
	var marker := node.get_node_or_null("HideMarker") as Marker3D
	if marker != null:
		player.global_position = marker.global_position
	stalker.set_player_hidden(true)
	_show_message("You are hidden. Wait for the monster to pass, then press F.", 4.0)

func _leave_hiding_place() -> void:
	player_is_hidden = false
	player.set("can_move", true)
	player.set("can_dash", _saved_dash)
	stalker.set_player_hidden(false)
	player.global_position += Vector3(0.0, 0.0, 1.8)
	_show_message("You left the hiding place.", 1.5)

func _release_heavy_box(node: Node3D) -> void:
	if heavy_box_used:
		return
	heavy_box_used = true
	_mark_interactable_used(node, Color(0.9, 0.35, 0.08))
	_show_message("Heavy box released! It blocks the passage and can stun the monster.", 3.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(heavy_box, "position:y", 2.5, 0.75)
	await tween.finished
	heavy_box_collider.set_deferred("disabled", false)
	if stalker.global_position.distance_to(heavy_box.global_position) < 17.0:
		stalker.stun_for(7.0)
	await get_tree().create_timer(9.0).timeout
	heavy_box_collider.set_deferred("disabled", true)
	var lift := create_tween()
	lift.tween_property(heavy_box, "position:y", 14.0, 1.0)

func _open_pit_trap(node: Node3D) -> void:
	if pit_lever_used:
		return
	pit_lever_used = true
	_pit_active = true
	_mark_interactable_used(node, Color(0.75, 0.08, 0.04))
	pit_door_collider.set_deferred("disabled", true)
	pit_door.visible = false
	_show_message("Ground trap open! Lure the monster across, or cross on the side planks.", 4.0)
	await get_tree().create_timer(10.0).timeout
	_pit_active = false
	pit_door.visible = true
	pit_door_collider.set_deferred("disabled", false)

func _update_hazards() -> void:
	if water_hazard != null and water_hazard.overlaps_body(player):
		_reset_player("You fell into the pool.")
	if stalker.active and water_hazard.overlaps_body(stalker) and stalker.global_position.y < -1.0:
		stalker.global_position = _current_monster_spawn
		stalker.velocity = Vector3.ZERO
	# The player is only ever below floor level here when the pit is open.
	if pit_hazard.overlaps_body(player) and player.global_position.y < -1.0:
		_reset_player("You fell into your own trap!")
	if _pit_active and stalker.active and pit_hazard.overlaps_body(stalker) and stalker.global_position.y < -1.0:
		_pit_active = false
		stalker.trap_for(7.5, _current_monster_spawn)

func _on_checkpoint_entered(body: Node3D, checkpoint: Area3D) -> void:
	if not body.is_in_group(&"player"):
		return
	var stage := str(checkpoint.get_meta("stage_name", checkpoint.name))
	if stage == _stage_name:
		return
	_stage_name = stage
	var respawn := checkpoint.get_node_or_null("Respawn") as Marker3D
	if respawn != null:
		_current_checkpoint = respawn.global_position
	var monster_spawn := checkpoint.get_node_or_null("MonsterSpawn") as Marker3D
	if monster_spawn != null:
		_current_monster_spawn = monster_spawn.global_position
	_show_message("CHECKPOINT: %s" % _stage_name, 3.0)

func _reset_player(reason: String) -> void:
	if _resetting_player or finished:
		return
	_resetting_player = true
	var restore_dash := bool(player.get("can_dash"))
	if player_is_hidden:
		_leave_hiding_place()
	player.set("can_move", false)
	player.set("can_dash", false)
	if player.has_method("cancel_active_movement"):
		player.call("cancel_active_movement")
	else:
		player.velocity = Vector3.ZERO
	map_panel.visible = false
	_show_message(reason, 2.5)
	damage_flash.visible = true
	damage_flash.modulate.a = 0.75
	var fade := create_tween()
	fade.tween_property(damage_flash, "modulate:a", 0.0, 0.65)
	await get_tree().create_timer(0.45).timeout
	player.global_position = _current_checkpoint
	player.velocity = Vector3.ZERO
	if stalker.active or stalker.enraged:
		stalker.reset_chase(_current_monster_spawn, 1.6)
	else:
		# Keep the stalker dormant until the vine key wakes it.
		stalker.global_position = _current_monster_spawn
		stalker.velocity = Vector3.ZERO
	await get_tree().physics_frame
	player.set("can_move", true)
	player.set("can_dash", restore_dash)
	damage_flash.visible = false
	_resetting_player = false

func _on_stalker_caught_player() -> void:
	_reset_player("THE MONSTER FOUND YOU!")

func _on_exit_area_body_entered(body: Node3D) -> void:
	if finished or _transition_started or not body.is_in_group(&"player") or not exit_gate_open:
		return
	finished = true
	_transition_started = true
	stalker.deactivate()
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	get_tree().paused = false
	var change_error := get_tree().change_scene_to_file(NEXT_LEVEL_PATH)
	if change_error != OK:
		_transition_started = false
		push_error("Unable to return to the main scene. Error code: %s" % change_error)

func _objective_text() -> String:
	if not has_map:
		return "Find the jungle map in the middle of the main road"
	if not has_vine_key:
		return "Find the Vine Key behind the waterfall"
	if rune_progress.size() < RUNE_ORDER.size():
		return "Press the three cave runes in order (see map)"
	if not cave_gate_open:
		return "Open the cavern stone gate"
	if not sun_switch_on or not river_switch_on:
		return "Activate both temple altars (use traps and hiding spots)"
	if not has_obsidian_key:
		return "Cross the ground trap and find the Obsidian Key"
	if not exit_gate_open:
		return "Return to the sealed exit"
	return "RUN through the open exit!"

func _update_map_text() -> void:
	if map_text_label == null or stalker == null or player == null:
		return
	var nearby := "NONE"
	if player_is_hidden:
		nearby = "F — LEAVE HIDING PLACE"
	else:
		var target := _nearest_interactable()
		if target != null:
			nearby = "F — " + str(target.get_meta("prompt", "INTERACT"))
	var rune_text := "%d / 3" % rune_progress.size()
	if not rune_progress.is_empty():
		rune_text += "  [" + " > ".join(rune_progress) + "]"
	map_text_label.text = ("CURRENT AREA: %s\n"
		+ "OBJECTIVE: %s\n"
		+ "MONSTER: %s\n"
		+ "NEARBY: %s\n\n"
		+ "PROGRESS\n"
		+ "Map: %s  |  Vine Key: %s  |  Runes: %s\n"
		+ "Sun Altar: %s  |  River Altar: %s  |  Obsidian Key: %s\n\n"
		+ "ROUTE\n"
		+ "MAIN ROAD > WATERFALL > ROOT CAVERNS > BLACKROOT TEMPLE > SEALED EXIT\n\n"
		+ "CLUES\n"
		+ "Vine Key: behind the waterfall\n"
		+ "Rune order: FROG > LEAF > MOON\n"
		+ "Exit: activate both altars and take the Obsidian Key\n\n"
		+ "CONTROLS: F INTERACT  |  M CLOSE MAP\n"
		+ "LATEST NOTE: %s") % [
			_stage_name, _objective_text(), stalker.get_status(player), nearby,
			("FOUND" if has_map else "MISSING"), ("FOUND" if has_vine_key else "MISSING"), rune_text,
			("ON" if sun_switch_on else "OFF"), ("ON" if river_switch_on else "OFF"),
			("FOUND" if has_obsidian_key else "MISSING"), _latest_note,
		]

func _show_message(text: String, _duration: float) -> void:
	_latest_note = text
	if map_panel != null and map_panel.visible:
		_update_map_text()

func _show_map_pickup_hint() -> void:
	_map_hint_id += 1
	var hint_id := _map_hint_id
	var prompt_panel := $HUD/PromptPanel as PanelContainer
	prompt_label.text = "MAP ACQUIRED  ·  M  OPEN MAP"
	prompt_panel.modulate = Color.WHITE
	prompt_panel.move_to_front()
	prompt_panel.visible = true
	await get_tree().create_timer(5.0).timeout
	if hint_id == _map_hint_id:
		prompt_panel.visible = false
