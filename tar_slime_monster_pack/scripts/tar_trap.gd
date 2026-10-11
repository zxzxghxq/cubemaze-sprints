extends Area3D
class_name TarMonsterTrap

## Place this Area3D at the bottom of a trap.
## When the monster enters, fall_into_trap() stops it and emits black particles.

@export var one_use: bool = true
@export var monster_group: StringName = &"tar_monster"

var _used: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _used and one_use:
		return
	if not body.is_in_group(monster_group):
		return
	if not body.has_method("fall_into_trap"):
		return

	_used = true
	body.call_deferred("fall_into_trap")
