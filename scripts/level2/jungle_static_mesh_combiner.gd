@tool
extends Node3D
## Merges every static MeshInstance3D in the level into combined ArrayMeshes
## grouped by material. The visuals are identical (world transforms are baked
## in), but the whole level renders in a fraction of the draw calls.
## Dynamic / functional nodes are left completely untouched.

const EXCLUDED_NODE_NAMES: Array[String] = [
	"Player", "JungleStalker", "Interactables", "Traps", "SafePlaces",
	"Gates", "Clouds", "HUD",
]

var _parts_by_material := {}
var _shadows_by_material := {}
var _originals: Array[MeshInstance3D] = []
var _part_count := 0

func _ready() -> void:
	# Keep source objects separate and selectable while editing. They are only
	# merged in the running game for rendering performance.
	if Engine.is_editor_hint():
		return
	call_deferred("_combine_all")

func _combine_all() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var previous := get_node_or_null("StaticBaked")
	if previous != null:
		previous.free()
	_parts_by_material.clear()
	_shadows_by_material.clear()
	_originals.clear()
	_part_count = 0
	_scan(get_parent())
	if _part_count == 0:
		return
	var baked := Node3D.new()
	baked.name = "StaticBaked"
	baked.visible = false
	add_child(baked)
	var merged := 0
	for key in _parts_by_material:
		var mat: Material = key
		var parts: Array = _parts_by_material[key]
		if parts.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in parts:
			st.append_from(part.mesh, 0, part.xform)
		st.set_material(mat)
		var combined := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Baked_%d" % mat.get_instance_id()
		mi.mesh = combined
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if _shadows_by_material.has(key) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		baked.add_child(mi)
		merged += 1
	# Swap the source meshes and combined meshes atomically. Previously the
	# baked meshes became visible one frame before queue_free removed the source
	# meshes, so identical surfaces overlapped and flashed at level startup.
	for original in _originals:
		original.visible = false
	baked.visible = true
	for original in _originals:
		original.queue_free()
	print("STATIC BAKE: ", _part_count, " parts -> ", merged, " combined meshes")

func _scan(node: Node) -> void:
	if node is MeshInstance3D:
		_collect(node as MeshInstance3D)
	for child in node.get_children():
		if _excluded(child):
			continue
		_scan(child)

func _collect(mi: MeshInstance3D) -> void:
	if mi.mesh == null or mi.mesh.get_surface_count() != 1:
		return
	var mat := mi.mesh.surface_get_material(0)
	if mat == null or mat is ShaderMaterial:
		return
	var key: Material = mat
	if not _parts_by_material.has(key):
		_parts_by_material[key] = []
	_parts_by_material[key].append({"mesh": mi.mesh, "xform": mi.global_transform})
	if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_shadows_by_material[key] = true
	_originals.append(mi)
	_part_count += 1

func _excluded(node: Node) -> bool:
	var name := node.name as String
	for excluded in EXCLUDED_NODE_NAMES:
		if name == excluded:
			return true
	return false
