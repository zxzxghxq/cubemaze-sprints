extends Node3D

@export_range(0.5, 5.0, 0.1) var emergence_delay: float = 2.0
@export_range(0.5, 5.0, 0.1) var reset_emergence_delay: float = 1.5

@onready var blade_spawn: Marker3D = $BladeSpawn
@onready var blade_start_trigger: Area3D = $BladeStartTrigger
@onready var blade_end_trigger: Area3D = $BladeEndTrigger
@onready var final_spawn: Marker3D = $FinalSpawn
@onready var final_start_trigger: Area3D = $FinalStartTrigger

var _monster: TarSlimeMonster
var _opening_spawn_transform: Transform3D
var _active_stage: int = 0
var _stage_running: bool = true
var _blade_started: bool = false
var _final_started: bool = false


func _ready() -> void:
	add_to_group(&"monster_director")
	_monster = get_tree().get_first_node_in_group(&"tar_monster") as TarSlimeMonster
	if _monster == null:
		push_error("MonsterDirector could not find the tar monster.")
		return

	_opening_spawn_transform = _monster.global_transform
	_monster.trapped.connect(_on_monster_trapped)
	blade_start_trigger.body_entered.connect(_on_blade_start_entered)
	blade_end_trigger.body_entered.connect(_on_blade_end_entered)
	final_start_trigger.body_entered.connect(_on_final_start_entered)


func on_player_reset() -> void:
	if _monster == null or not is_instance_valid(_monster) or not _stage_running:
		return

	match _active_stage:
		0:
			_monster.reappear_at(_opening_spawn_transform, reset_emergence_delay)
		1:
			_stage_running = false
			_blade_started = false
			_monster.withdraw_temporarily()
		2:
			_stage_running = false
			_final_started = false
			_monster.withdraw_temporarily()


func finish_level() -> void:
	_stage_running = false
	if _monster != null and is_instance_valid(_monster):
		_monster.final_defeat()


func _on_monster_trapped() -> void:
	_stage_running = false


func _on_blade_start_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player") or _blade_started:
		return
	_blade_started = true
	_active_stage = 1
	_stage_running = true
	_monster.reappear_at(blade_spawn.global_transform, emergence_delay)


func _on_blade_end_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player") or _active_stage != 1 or not _stage_running:
		return
	_stage_running = false
	_monster.withdraw_temporarily()


func _on_final_start_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player") or _final_started:
		return
	_final_started = true
	_active_stage = 2
	_stage_running = true
	_monster.reappear_at(final_spawn.global_transform, emergence_delay)
