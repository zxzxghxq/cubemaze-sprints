@tool
extends Node3D
## Scatters a dense jungle forest around the winding maze:
## big trees, bushes, rocks, plus drifting pollen for atmosphere.

const OPEN_FOREST: Array[Rect2] = [
	# Outer ring around the whole maze.
	Rect2(-142, -142, 372, 14),
	Rect2(-142, -128, 14, 326),
	Rect2(-142, 198, 372, 14),
	Rect2(224, -142, 10, 354),
	# Gaps between the serpentine corridors.
	Rect2(-88, -97, 50, 43),
	Rect2(-11, -54, 55, 12),
	Rect2(-12, -16, 50, 10),
	Rect2(34, 72, 18, 28),
	Rect2(36, 102, 44, 40),
	Rect2(100, 102, 24, 40),
	Rect2(120, 140, 84, 13),
	Rect2(120, 172, 84, 10),
	Rect2(206, 144, 18, 36),
]

static var _vine_mat: StandardMaterial3D
static var _trunk_mat: StandardMaterial3D
static var _leaf_mat_a: StandardMaterial3D
static var _leaf_mat_b: StandardMaterial3D
static var _bush_mat: StandardMaterial3D

func _ready() -> void:
	if get_child_count() > 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	_scatter_trees(rng, 110)
	# OPEN_FOREST is entirely outside the playable corridors. Tree crowns rise
	# above the walls and remain part of the visible skyline, but its low random
	# bushes and rocks stay below the 8-14 m walls and cannot be seen in play.
	# Intentional bushes and rocks beside the route are built by WorldBuilder
	# and are deliberately retained.
	_add_pollen(rng)
	if Engine.is_editor_hint():
		_claim_editor_children()

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

func _random_point(rng: RandomNumberGenerator) -> Vector3:
	var rect: Rect2 = OPEN_FOREST[rng.randi_range(0, OPEN_FOREST.size() - 1)]
	var x: float = rect.position.x + rng.randf() * rect.size.x
	var z: float = rect.position.y + rng.randf() * rect.size.y
	return Vector3(x, 0.0, z)

func _scatter_trees(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var tree := _make_tree(rng.randf_range(1.5, 2.7), rng.randi_range(0, 3))
		tree.name = "BigTree%03d" % i
		tree.position = _random_point(rng)
		add_child(tree)

func _scatter_bushes(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var bush := _make_bush(rng.randf_range(0.7, 1.5))
		bush.name = "Bush%03d" % i
		bush.position = _random_point(rng)
		add_child(bush)

func _scatter_rocks(rng: RandomNumberGenerator, count: int) -> void:
	var rock_scene := load("res://models/simple_route_rock.glb")
	var rect_rock_scene := load("res://models/rectangular_route_rock.glb")
	for i in count:
		var rock := (rock_scene if i % 3 != 0 else rect_rock_scene).instantiate() as Node3D
		rock.name = "ForestRock%03d" % i
		rock.position = _random_point(rng)
		rock.rotation.y = rng.randf_range(-PI, PI)
		var s := rng.randf_range(0.8, 2.2)
		rock.scale = Vector3.ONE * s
		add_child(rock)

func _make_tree(scale: float, variety: int) -> StaticBody3D:
	var tree := StaticBody3D.new()
	var trunk_h := 6.0 * scale
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.material = _shared_trunk_material()
	trunk_mesh.top_radius = 0.38 * scale
	trunk_mesh.bottom_radius = 0.62 * scale
	trunk_mesh.height = trunk_h
	trunk_mesh.radial_segments = 8
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0, trunk_h / 2.0, 0)
	tree.add_child(trunk)
	var leaf_mat := _shared_leaf_material(variety % 2)
	var crown_mesh := SphereMesh.new()
	crown_mesh.material = leaf_mat
	crown_mesh.radius = 3.1 * scale
	crown_mesh.height = 6.2 * scale
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 4
	var crown := MeshInstance3D.new()
	crown.name = "Crown"
	crown.mesh = crown_mesh
	crown.position = Vector3(0, trunk_h + 1.0 * scale, 0)
	tree.add_child(crown)
	for i in 3:
		var side_mesh := SphereMesh.new()
		side_mesh.material = leaf_mat
		side_mesh.radius = 1.9 * scale
		side_mesh.height = 3.8 * scale
		side_mesh.radial_segments = 8
		side_mesh.rings = 4
		var side := MeshInstance3D.new()
		side.name = "CrownSide%d" % i
		side.mesh = side_mesh
		var angle := TAU * i / 3.0 + variety * 0.4
		side.position = Vector3(cos(angle) * 1.9 * scale, trunk_h + (0.4 + (i % 2) * 0.8) * scale, sin(angle) * 1.9 * scale)
		tree.add_child(side)
	# Hanging vines under the canopy.
	var vine_mat := _shared_vine_material()
	for i in 2:
		var vine_mesh := CylinderMesh.new()
		vine_mesh.material = vine_mat
		vine_mesh.top_radius = 0.035 * scale
		vine_mesh.bottom_radius = 0.06 * scale
		vine_mesh.height = (1.6 + float((i * 37) % 25) * 0.12) * scale
		vine_mesh.radial_segments = 4
		var vine := MeshInstance3D.new()
		vine.name = "Vine%d" % i
		vine.mesh = vine_mesh
		vine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := TAU * i / 2.0 + variety * 0.5
		var r := (0.7 + float((i * 13) % 20) * 0.08) * scale
		var top_y := trunk_h + (0.6 + float((i * 7) % 12) * 0.1) * scale
		vine.position = Vector3(cos(angle) * r, top_y - vine_mesh.height / 2.0, sin(angle) * r)
		tree.add_child(vine)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.55 * scale
	cylinder.height = trunk_h
	shape.position = Vector3(0, trunk_h / 2.0, 0)
	shape.shape = cylinder
	tree.add_child(shape)
	return tree

static func _shared_vine_material() -> StandardMaterial3D:
	if _vine_mat == null:
		_vine_mat = StandardMaterial3D.new()
		_vine_mat.albedo_color = Color(0.10, 0.36, 0.10)
		_vine_mat.roughness = 0.9
	return _vine_mat

func _make_bush(scale: float) -> StaticBody3D:
	var bush := StaticBody3D.new()
	var mat := _shared_bush_material()
	var mesh := SphereMesh.new()
	mesh.material = mat
	mesh.radius = 1.1 * scale
	mesh.height = 2.2 * scale
	mesh.radial_segments = 10
	mesh.rings = 5
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.position = Vector3(0, 0.75 * scale, 0)
	bush.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.85 * scale
	shape.position = Vector3(0, 0.7 * scale, 0)
	shape.shape = sphere
	bush.add_child(shape)
	return bush

static func _shared_trunk_material() -> StandardMaterial3D:
	if _trunk_mat == null:
		_trunk_mat = StandardMaterial3D.new()
		_trunk_mat.albedo_color = Color(0.24, 0.11, 0.04)
		_trunk_mat.roughness = 0.95
	return _trunk_mat

static func _shared_leaf_material(variety: int) -> StandardMaterial3D:
	if variety == 0:
		if _leaf_mat_a == null:
			_leaf_mat_a = StandardMaterial3D.new()
			_leaf_mat_a.albedo_color = Color(0.06, 0.38, 0.12)
			_leaf_mat_a.roughness = 0.9
		return _leaf_mat_a
	if _leaf_mat_b == null:
		_leaf_mat_b = StandardMaterial3D.new()
		_leaf_mat_b.albedo_color = Color(0.04, 0.28, 0.10)
		_leaf_mat_b.roughness = 0.9
	return _leaf_mat_b

static func _shared_bush_material() -> StandardMaterial3D:
	if _bush_mat == null:
		_bush_mat = StandardMaterial3D.new()
		_bush_mat.albedo_color = Color(0.09, 0.42, 0.14)
		_bush_mat.roughness = 0.9
	return _bush_mat

func _add_pollen(rng: RandomNumberGenerator) -> void:
	var pollen := CPUParticles3D.new()
	pollen.name = "Pollen"
	pollen.position = Vector3(42, 5.0, 30)
	pollen.emitting = true
	pollen.amount = 100
	pollen.lifetime = 7.0
	pollen.randomness = 0.6
	pollen.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pollen.emission_box_extents = Vector3(170, 6, 150)
	pollen.direction = Vector3(0, -1, 0)
	pollen.spread = 30.0
	pollen.gravity = Vector3(0, -0.12, 0)
	pollen.initial_velocity_min = 0.3
	pollen.initial_velocity_max = 0.9
	pollen.scale_amount_min = 0.4
	pollen.scale_amount_max = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.9, 0.45, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.material = mat
	mesh.radius = 0.06
	mesh.height = 0.12
	pollen.mesh = mesh
	add_child(pollen)
