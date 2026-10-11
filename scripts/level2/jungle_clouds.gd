@tool
extends Node3D
## Drifting puffy clouds high above the jungle maze. Each cloud is a cluster of
## flattened spheres; they slowly drift east and wrap around so the sky is
## always dotted with clouds.

const X_MIN := -260.0
const X_MAX := 380.0

var _mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _clouds: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 20260807
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.96, 0.98, 1.0, 0.94)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if get_child_count() == 0:
		for i in 30:
			var cloud := _make_cloud()
			cloud.name = "Cloud%02d" % i
			cloud.position = Vector3(
				_rng.randf_range(X_MIN, X_MAX),
				_rng.randf_range(75, 120),
				_rng.randf_range(-260, 380))
			add_child(cloud)
			_clouds.append({"node": cloud, "speed": _rng.randf_range(1.0, 2.6)})
		if Engine.is_editor_hint():
			_claim_editor_children()
	else:
		for child in get_children():
			if child is Node3D:
				_clouds.append({"node": child, "speed": _rng.randf_range(1.0, 2.6)})
	set_process(not Engine.is_editor_hint())

func _claim_editor_children() -> void:
	var edited_root := get_tree().edited_scene_root
	if edited_root == null:
		return
	for child in get_children():
		_claim_owner_recursive(child, edited_root)

func _claim_owner_recursive(node: Node, edited_root: Node) -> void:
	if node.owner == null:
		node.owner = edited_root
	for child in node.get_children():
		if child.owner == null:
			_claim_owner_recursive(child, edited_root)

func _process(delta: float) -> void:
	for entry in _clouds:
		var cloud: Node3D = entry.node
		cloud.position.x += entry.speed * delta
		if cloud.position.x > X_MAX:
			cloud.position.x = X_MIN
			cloud.position.z = _rng.randf_range(-260, 380)
			cloud.position.y = _rng.randf_range(75, 120)

func _make_cloud() -> Node3D:
	var cloud := Node3D.new()
	var count := _rng.randi_range(5, 8)
	for j in count:
		var radius := _rng.randf_range(7.0, 16.0)
		var m := SphereMesh.new()
		m.material = _mat
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 10
		m.rings = 5
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = Vector3(
			_rng.randf_range(-24, 24),
			_rng.randf_range(-2, 4),
			_rng.randf_range(-14, 14))
		mi.scale = Vector3(1.25, 0.55, 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.add_child(mi)
	return cloud
