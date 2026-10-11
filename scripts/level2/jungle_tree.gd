@tool
extends StaticBody3D
## Procedurally builds a lush jungle tree: smooth tapered trunk with a flared
## base and roots, a few supporting branches and a dense multi-layer leaf canopy.
## Materials are shared between all trees for good batching.

@export var generation_seed: int = 1
@export var tree_scale: float = 1.0

static var _materials_ready := false
static var _bark: StandardMaterial3D
static var _bark_dark: StandardMaterial3D
static var _leaf_light: StandardMaterial3D
static var _leaf_mid: StandardMaterial3D
static var _leaf_dark: StandardMaterial3D

func _ready() -> void:
	_remove_saved_vines()
	if get_child_count() > 0:
		return
	_ensure_materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed
	var trunk_top := _build_trunk(rng)
	_build_roots(rng)
	_build_branches(rng, trunk_top)
	_build_canopy(rng, trunk_top)
	_add_trunk_collision(trunk_top)

static func _ensure_materials() -> void:
	if _materials_ready:
		return
	_materials_ready = true
	_bark = _make_mat(Color(0.34, 0.20, 0.11), 0.82)
	_bark_dark = _make_mat(Color(0.23, 0.13, 0.07), 0.9)
	_leaf_light = _make_mat(Color(0.24, 0.58, 0.18), 0.78)
	_leaf_mid = _make_mat(Color(0.13, 0.43, 0.14), 0.85)
	_leaf_dark = _make_mat(Color(0.07, 0.31, 0.11), 0.9)

func _remove_saved_vines() -> void:
	# Older saved Level 2 scenes contain the generated vine meshes as children.
	# Remove only meshes using the dedicated vine material; trunks, branches,
	# leaves and collision shapes are left untouched.
	const VINE_COLOR := Color(0.12, 0.36, 0.12, 1.0)
	for child in get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var material := mesh_instance.mesh.material as StandardMaterial3D
		if material != null and material.albedo_color.is_equal_approx(VINE_COLOR):
			mesh_instance.queue_free()

static func _make_mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

func _build_trunk(rng: RandomNumberGenerator) -> float:
	var s := tree_scale
	var base_h := 1.4 * s
	var main_h := 7.3 * s
	var base := CylinderMesh.new()
	base.material = _bark_dark
	base.top_radius = 0.78 * s
	base.bottom_radius = 1.05 * s
	base.height = base_h
	base.radial_segments = 8
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = base
	base_mi.position = Vector3(0, base_h / 2.0, 0)
	add_child(base_mi)
	var main := CylinderMesh.new()
	main.material = _bark
	main.top_radius = 0.28 * s
	main.bottom_radius = 0.78 * s
	main.height = main_h
	main.radial_segments = 10
	var main_mi := MeshInstance3D.new()
	main_mi.mesh = main
	main_mi.position = Vector3(0, base_h + main_h / 2.0, 0)
	add_child(main_mi)
	rotation.z = rng.randf_range(-0.025, 0.025)
	rotation.x = rng.randf_range(-0.025, 0.025)
	return base_h + main_h

func _build_roots(rng: RandomNumberGenerator) -> void:
	var s := tree_scale
	for i in 3:
		var angle := TAU * i / 3.0 + rng.randf_range(-0.25, 0.25)
		var m := CylinderMesh.new()
		m.material = _bark_dark
		m.top_radius = 0.07 * s
		m.bottom_radius = 0.24 * s
		m.height = 1.5 * s
		m.radial_segments = 5
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tilt := deg_to_rad(rng.randf_range(46, 58))
		var t := Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, tilt).rotated(Vector3.UP, angle),
			Vector3(cos(angle) * 0.62 * s, 0.42 * s, sin(angle) * 0.62 * s))
		mi.transform = t
		add_child(mi)

func _build_branches(rng: RandomNumberGenerator, trunk_top: float) -> void:
	var s := tree_scale
	for i in 2:
		var angle := TAU * i / 2.0 + rng.randf_range(-0.4, 0.4)
		var y_pos := trunk_top - rng.randf_range(1.6, 2.6) * s
		var length := rng.randf_range(1.2, 2.0) * s
		var tilt := deg_to_rad(rng.randf_range(28, 42))
		var m := CylinderMesh.new()
		m.material = _bark
		m.top_radius = 0.05 * s
		m.bottom_radius = 0.15 * s
		m.height = length
		m.radial_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t := Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, -tilt).rotated(Vector3.UP, angle),
			Vector3(cos(angle) * 0.28 * s, y_pos, sin(angle) * 0.28 * s))
		mi.transform = t
		add_child(mi)

func _build_canopy(rng: RandomNumberGenerator, trunk_top: float) -> void:
	var s := tree_scale
	var center_y := trunk_top + 1.2 * s
	var leaf_mats: Array[Material] = [_leaf_mid, _leaf_light, _leaf_dark]
	_add_leaf_clump(leaf_mats[rng.randi_range(0, 2)], center_y, 2.5 * s, 0.0, 0.0, 0.0, 1.0)
	for i in 5:
		var a1 := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(1.5, 2.5) * s
		var y := center_y + rng.randf_range(-0.9, 1.1) * s
		_add_leaf_clump(leaf_mats[rng.randi_range(0, 2)], y,
			rng.randf_range(1.25, 1.8) * s, a1, r, rng.randf_range(-0.4, 0.4),
			rng.randf_range(0.9, 1.15))

func _add_leaf_clump(mat: Material, y: float, radius: float, ang1: float,
		r: float = 0.0, ang2: float = 0.0, squish: float = 1.0) -> void:
	var m := SphereMesh.new()
	m.material = mat
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = Vector3(cos(ang1) * cos(ang2) * r, y, sin(ang1) * cos(ang2) * r)
	mi.scale = Vector3(squish, 0.82, squish)
	add_child(mi)

func _add_trunk_collision(trunk_top: float) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = 0.6 * tree_scale
	shape.height = trunk_top + 0.5 * tree_scale
	cs.position = Vector3(0, (trunk_top + 0.5 * tree_scale) / 2.0, 0)
	cs.shape = shape
	add_child(cs)
