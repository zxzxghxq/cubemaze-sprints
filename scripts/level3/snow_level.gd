@tool
extends Node3D

const TERRAIN_SIZE: float = 240.0
const HALF_SIZE: float = TERRAIN_SIZE * 0.5
const GRID_RESOLUTION: int = 72
const TREE_COUNT: int = 76
const HILLS := [
	Vector4(-72.0, -34.0, 12.0, 27.0),
	Vector4(-25.0, 48.0, 16.0, 31.0),
	Vector4(34.0, -52.0, 11.0, 25.0),
	Vector4(70.0, 42.0, 18.0, 34.0),
	Vector4(4.0, 4.0, -5.0, 24.0),
	Vector4(-82.0, 78.0, 9.0, 22.0),
	Vector4(88.0, -82.0, 14.0, 29.0),
]
const ROUTE_PATHS := [
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
const MISSION_CLEARINGS := [
	Vector2(-84.0, -80.0), Vector2(-60.0, 50.0), Vector2(18.0, 52.0),
	Vector2(80.0, 76.0), Vector2(104.0, 100.0),
]

var _snow_material: StandardMaterial3D
var _pine_material: StandardMaterial3D
var _trunk_material: StandardMaterial3D
var _pine_snow_material: StandardMaterial3D

func _ready() -> void:
	call_deferred("_ensure_snowfield")

func _ensure_snowfield() -> void:
	var existing_world := get_node_or_null("GeneratedSnowWorld") as Node3D
	if existing_world != null:
		_ensure_existing_tree_collisions(existing_world)
		_place_player()
		_place_vehicle()
		return
	_make_materials()
	var generated := Node3D.new()
	generated.name = "GeneratedSnowWorld"
	add_child(generated)
	_build_terrain(generated)
	_build_boundary_colliders(generated)
	_build_pine_forest(generated)
	_build_snowfall(generated)
	_place_player()
	_place_vehicle()
	_make_editor_world_editable(generated)

func _make_materials() -> void:
	_snow_material = StandardMaterial3D.new()
	_snow_material.albedo_color = Color(0.9, 0.95, 0.98)
	_snow_material.roughness = 0.92
	_snow_material.vertex_color_use_as_albedo = true

	_pine_material = StandardMaterial3D.new()
	_pine_material.albedo_color = Color(0.055, 0.18, 0.13)
	_pine_material.roughness = 0.96

	_trunk_material = StandardMaterial3D.new()
	_trunk_material.albedo_color = Color(0.16, 0.085, 0.045)
	_trunk_material.roughness = 1.0

	_pine_snow_material = StandardMaterial3D.new()
	_pine_snow_material.albedo_color = Color(0.91, 0.95, 0.98)
	_pine_snow_material.roughness = 0.9

func _terrain_height_base(x: float, z: float) -> float:
	var height := sin(x * 0.042) * 1.8
	height += cos(z * 0.037) * 1.5
	height += sin((x + z) * 0.025) * 1.25
	height += sin(x * 0.09 - z * 0.055) * 0.55
	for hill in HILLS:
		var dx: float = x - hill.x
		var dz: float = z - hill.y
		var radius: float = hill.w
		height += hill.z * exp(-(dx * dx + dz * dz) / (2.0 * radius * radius))
	var edge := maxf(absf(x), absf(z)) / HALF_SIZE
	var ridge := clampf((edge - 0.68) / 0.32, 0.0, 1.0)
	ridge = ridge * ridge * (3.0 - 2.0 * ridge)
	var mountain_peaks := 38.0
	mountain_peaks += absf(sin(x * 0.071 + z * 0.029)) * 12.0
	mountain_peaks += absf(cos(z * 0.083 - x * 0.021)) * 8.0
	height += ridge * ridge * mountain_peaks
	return height

func _terrain_height(x: float, z: float) -> float:
	var base_height := _terrain_height_base(x, z)
	var nearest_distance := INF
	var route_height := base_height
	var point := Vector2(x, z)
	for route in ROUTE_PATHS:
		for index in range(route.size() - 1):
			var start: Vector2 = route[index]
			var finish: Vector2 = route[index + 1]
			var segment := finish - start
			var length_squared := segment.length_squared()
			var ratio := 0.0
			if length_squared > 0.001:
				ratio = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
			var closest := start + segment * ratio
			var distance := point.distance_to(closest)
			if distance >= nearest_distance:
				continue
			nearest_distance = distance
			route_height = lerpf(
				_route_anchor_height(start),
				_route_anchor_height(finish),
				ratio
			)
	if nearest_distance < 7.0:
		var blend := 1.0 - smoothstep(3.8, 7.0, nearest_distance)
		var driving_texture := sin(x * 0.31 + z * 0.19) * 0.12
		base_height = lerpf(base_height, route_height + driving_texture, blend)
	return base_height

func _route_anchor_height(point: Vector2) -> float:
	# The outer mountain ring is intentionally high, but the evacuation road
	# needs a carved pass that a wheeled vehicle can actually climb.
	if point.distance_to(Vector2(104.0, 100.0)) < 0.1:
		return 11.0
	if point.distance_to(Vector2(95.0, 86.0)) < 0.1:
		return 9.2
	return _terrain_height_base(point.x, point.y)

func _terrain_normal(x: float, z: float) -> Vector3:
	const SAMPLE_DISTANCE := 0.8
	return Vector3(
		_terrain_height(x - SAMPLE_DISTANCE, z) - _terrain_height(x + SAMPLE_DISTANCE, z),
		SAMPLE_DISTANCE * 2.0,
		_terrain_height(x, z - SAMPLE_DISTANCE) - _terrain_height(x, z + SAMPLE_DISTANCE)
	).normalized()

func _build_terrain(parent: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := TERRAIN_SIZE / float(GRID_RESOLUTION)
	for z_index in range(GRID_RESOLUTION + 1):
		var z := -HALF_SIZE + float(z_index) * step
		for x_index in range(GRID_RESOLUTION + 1):
			var x := -HALF_SIZE + float(x_index) * step
			var y := _terrain_height(x, z)
			var normal := _terrain_normal(x, z)
			var slope := 1.0 - normal.y
			var shade := clampf(0.9 + y * 0.006 - slope * 0.55, 0.7, 1.0)
			surface.set_normal(normal)
			surface.set_uv(Vector2(x, z) * 0.035)
			surface.set_color(Color(0.9 * shade, 0.95 * shade, 0.99 * shade, 1.0))
			surface.add_vertex(Vector3(x, y, z))
	var row_size := GRID_RESOLUTION + 1
	for z_index in range(GRID_RESOLUTION):
		for x_index in range(GRID_RESOLUTION):
			var a := z_index * row_size + x_index
			var b := a + 1
			var c := a + row_size
			var d := c + 1
			surface.add_index(a)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(d)
			surface.add_index(c)
	var terrain_mesh := surface.commit()
	terrain_mesh.surface_set_material(0, _snow_material)

	var body := StaticBody3D.new()
	body.name = "SnowTerrain"
	parent.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SnowSurface"
	mesh_instance.mesh = terrain_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = terrain_mesh.create_trimesh_shape()
	body.add_child(collider)

func _build_boundary_colliders(parent: Node3D) -> void:
	var boundaries := Node3D.new()
	boundaries.name = "OuterSafetyBoundaries"
	parent.add_child(boundaries)
	_add_boundary_wall(boundaries, "NorthBoundary", Vector3(0.0, 24.0, -119.0),
		Vector3(244.0, 82.0, 4.0))
	_add_boundary_wall(boundaries, "SouthBoundary", Vector3(0.0, 24.0, 119.0),
		Vector3(244.0, 82.0, 4.0))
	_add_boundary_wall(boundaries, "WestBoundary", Vector3(-119.0, 24.0, 0.0),
		Vector3(4.0, 82.0, 244.0))
	_add_boundary_wall(boundaries, "EastBoundary", Vector3(119.0, 24.0, 0.0),
		Vector3(4.0, 82.0, 244.0))

func _add_boundary_wall(parent: Node3D, wall_name: String, position: Vector3,
		size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.position = position
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)

func _build_pine_forest(parent: Node3D) -> void:
	var forest := Node3D.new()
	forest.name = "SnowPines"
	parent.add_child(forest)
	var rng := RandomNumberGenerator.new()
	rng.seed = 902_731
	var tree_transforms: Array[Transform3D] = []
	var attempts := 0
	while tree_transforms.size() < TREE_COUNT and attempts < TREE_COUNT * 18:
		attempts += 1
		var x := rng.randf_range(-108.0, 108.0)
		var z := rng.randf_range(-108.0, 108.0)
		if Vector2(x + 84.0, z + 80.0).length() < 18.0:
			continue
		if Vector2(x, z).length() < 13.0:
			continue
		if _inside_mission_clearance(Vector2(x, z)):
			continue
		var ground_y := _terrain_height(x, z)
		if _terrain_normal(x, z).y < 0.82:
			continue
		var scale := rng.randf_range(0.72, 1.38)
		var yaw := rng.randf_range(-PI, PI)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		tree_transforms.append(Transform3D(basis, Vector3(x, ground_y, z)))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.34
	trunk.bottom_radius = 0.48
	trunk.height = 5.0
	trunk.radial_segments = 8
	trunk.material = _trunk_material
	_add_tree_layer(forest, "Trunks", trunk, tree_transforms, 2.5)

	_add_tree_layer(forest, "LowerNeedles", _cone_mesh(2.9, 5.4, _pine_material), tree_transforms, 5.1)
	_add_tree_layer(forest, "MiddleNeedles", _cone_mesh(2.25, 4.7, _pine_material), tree_transforms, 7.15)
	_add_tree_layer(forest, "UpperNeedles", _cone_mesh(1.6, 4.0, _pine_material), tree_transforms, 9.05)
	_add_tree_layer(forest, "LowerSnow", _snow_cap_mesh(2.2, 2.1), tree_transforms, 6.72)
	_add_tree_layer(forest, "MiddleSnow", _snow_cap_mesh(1.7, 1.9), tree_transforms, 8.58)
	_add_tree_layer(forest, "UpperSnow", _snow_cap_mesh(1.22, 2.25), tree_transforms, 10.18)
	_build_pine_collisions(forest, tree_transforms)

func _inside_mission_clearance(point: Vector2) -> bool:
	for clearing in MISSION_CLEARINGS:
		if point.distance_to(clearing) < 11.0:
			return true
	for route in ROUTE_PATHS:
		for index in range(route.size() - 1):
			var start: Vector2 = route[index]
			var finish: Vector2 = route[index + 1]
			var segment := finish - start
			var length_squared := segment.length_squared()
			var ratio := 0.0
			if length_squared > 0.001:
				ratio = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
			if point.distance_to(start + segment * ratio) < 6.0:
				return true
	return false

func _ensure_existing_tree_collisions(generated_world: Node3D) -> void:
	var forest := generated_world.get_node_or_null("SnowPines") as Node3D
	if forest == null or forest.get_node_or_null("PineCollisions") != null:
		return
	var trunks := forest.get_node_or_null("Trunks") as MultiMeshInstance3D
	if trunks == null or trunks.multimesh == null:
		return
	var tree_transforms: Array[Transform3D] = []
	for index in range(trunks.multimesh.instance_count):
		tree_transforms.append(trunks.multimesh.get_instance_transform(index))
	var collisions := _build_pine_collisions(forest, tree_transforms)
	_make_editor_world_editable(collisions)

func _build_pine_collisions(parent: Node3D,
		trees: Array[Transform3D]) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "PineCollisions"
	parent.add_child(body)
	for index in range(trees.size()):
		var collider := CollisionShape3D.new()
		collider.name = "PineTrunk%02d" % index
		var shape := CylinderShape3D.new()
		shape.radius = 0.5
		shape.height = 5.2
		collider.shape = shape
		var trunk_offset := Transform3D(Basis.IDENTITY, Vector3(0.0, 2.6, 0.0))
		collider.transform = trees[index] * trunk_offset
		body.add_child(collider)
	return body

func _cone_mesh(radius: float, height: float, material: Material) -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 9
	cone.rings = 2
	cone.material = material
	return cone

func _snow_cap_mesh(radius: float, height: float) -> CylinderMesh:
	var cap := CylinderMesh.new()
	cap.top_radius = 0.05
	cap.bottom_radius = radius
	cap.height = height
	cap.radial_segments = 9
	cap.rings = 2
	cap.material = _pine_snow_material
	return cap

func _add_tree_layer(parent: Node3D, layer_name: String, mesh: Mesh,
		trees: Array[Transform3D], local_y: float) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = trees.size()
	for index in range(trees.size()):
		var local_offset := Transform3D(Basis.IDENTITY, Vector3(0.0, local_y, 0.0))
		multimesh.set_instance_transform(index, trees[index] * local_offset)
	var instance := MultiMeshInstance3D.new()
	instance.name = layer_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)

func _build_snowfall(parent: Node3D) -> void:
	var flakes_material := StandardMaterial3D.new()
	flakes_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flakes_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flakes_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flakes_material.albedo_color = Color(0.96, 0.985, 1.0, 0.88)
	var flake_mesh := QuadMesh.new()
	flake_mesh.size = Vector2(0.12, 0.12)
	flake_mesh.material = flakes_material

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(116.0, 7.0, 116.0)
	process.direction = Vector3(0.08, -1.0, 0.04)
	process.spread = 14.0
	process.gravity = Vector3(0.35, -0.75, 0.18)
	process.initial_velocity_min = 2.7
	process.initial_velocity_max = 4.6
	process.scale_min = 0.65
	process.scale_max = 1.5

	var snowfall := GPUParticles3D.new()
	snowfall.name = "Snowfall"
	snowfall.position = Vector3(0.0, 30.0, 0.0)
	snowfall.amount = 2400
	snowfall.lifetime = 8.0
	snowfall.randomness = 0.45
	snowfall.preprocess = 8.0
	snowfall.visibility_aabb = AABB(Vector3(-120.0, -45.0, -120.0), Vector3(240.0, 60.0, 240.0))
	snowfall.process_material = process
	snowfall.draw_pass_1 = flake_mesh
	snowfall.fixed_fps = 30
	parent.add_child(snowfall)

func _place_player() -> void:
	var player := get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var spawn_x := -84.0
	var spawn_z := -80.0
	player.position = Vector3(spawn_x, _terrain_height(spawn_x, spawn_z) + 0.35, spawn_z)
	player.rotation.y = -2.35

func _place_vehicle() -> void:
	var vehicle := get_node_or_null("SnowATV") as RigidBody3D
	if vehicle == null:
		return
	var spawn_x := -75.0
	var spawn_z := -80.0
	vehicle.position = Vector3(spawn_x, _terrain_height(spawn_x, spawn_z) + 0.08, spawn_z)
	vehicle.rotation.y = 0.62
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO

func _make_editor_world_editable(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var edited_root := get_tree().edited_scene_root
	if edited_root == null:
		return
	_set_owner_recursive(node, edited_root)

func _set_owner_recursive(node: Node, edited_root: Node) -> void:
	node.owner = edited_root
	for child in node.get_children():
		_set_owner_recursive(child, edited_root)
