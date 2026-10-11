@tool
extends Node3D
## Builds the winding jungle maze level at runtime.
## Puzzle flow: map -> vine key -> runes 3/3 ->
## stone gate -> two altars -> heavy box -> pit trap -> obsidian key ->
## exit gate -> finish.

const WALL_HEIGHT := 8.0
const WALL_THICK := 1.5
const JUNGLE_TREE := preload("res://scenes/level2/jungle_tree.tscn")
const GENERATED_ROOTS: Array[StringName] = [
	&"Architecture", &"Interactables", &"SafePlaces", &"Traps",
	&"Gameplay", &"ForestDecor", &"Ground", &"WorldBounds", &"GrassDetail",
]

## Generates an editable source world in the 3D editor viewport. Generated
## nodes are owned by level2.tscn, so transforms can be changed and saved.
@export var editor_preview_enabled := true

var _mats := {}

var _mesh_pedestal: Mesh
var _mesh_pillar: Mesh
var _mesh_gate: Mesh
var _mesh_spike: PackedScene

var _architecture: Node
var _gates: Node
var _interactables: Node
var _safe_places: Node
var _traps: Node
var _gameplay: Node
var _forest_decor: Node
var _vine_arches: Node
var _blade_xforms: Array[Transform3D] = []
var _patch_xforms: Array[Transform3D] = []
var _flower_xforms: Array[Transform3D] = []
var _build_started := false

func _ready() -> void:
	if Engine.is_editor_hint() and not editor_preview_enabled:
		return
	call_deferred("_build_all")

func _build_all() -> void:
	if _build_started or not is_inside_tree():
		return
	_build_started = true
	var root := get_parent()
	if _has_generated_world(root):
		_bind_existing_roots(root)
		# An editor-saved world contains all visible and interactive pieces. The
		# lightweight gameplay trigger layer remains runtime-generated.
		if not Engine.is_editor_hint():
			if _gameplay == null:
				_gameplay = _node(root, "Gameplay")
			if _gameplay.get_node_or_null("StartSpawn") == null:
				_build_gameplay()
		return
	_blade_xforms.clear()
	_patch_xforms.clear()
	_flower_xforms.clear()
	_make_materials()
	_make_shared_meshes()
	_architecture = _node(root, "Architecture")
	_gates = _node(_architecture, "Gates")
	_interactables = _node(root, "Interactables")
	_safe_places = _node(root, "SafePlaces")
	_traps = _node(root, "Traps")
	_gameplay = _node(root, "Gameplay")
	_forest_decor = _node(root, "ForestDecor")
	# Every playable room and corridor has its own floor. The former full-map
	# backing plane sat below those floors or behind 8-14 m walls, so it could
	# never be seen during play and only added meshes and collision bodies.
	_build_perimeter_walls()
	_build_start_room()
	_build_corridor_a()
	_build_corridor_a2()
	_build_grotto_room()
	_build_corridor_b()
	_build_corridor_c()
	_build_cave_room()
	_build_corridor_d()
	_build_temple_room()
	_build_corridor_e()
	_build_exit_gate()
	_line_passage_with_trees()
	_build_grass_detail()
	# Runtime-only trigger volumes and checkpoint markers are not useful in the
	# editor viewport. All visible puzzle props are built by the room functions.
	if not Engine.is_editor_hint():
		_build_gameplay()
	else:
		_make_editor_world_editable(root)

func _has_generated_world(root: Node) -> bool:
	return root.get_node_or_null("Architecture") != null \
		and root.get_node_or_null("ForestDecor") != null

func _bind_existing_roots(root: Node) -> void:
	_architecture = root.get_node_or_null("Architecture")
	_gates = root.get_node_or_null("Architecture/Gates")
	_interactables = root.get_node_or_null("Interactables")
	_safe_places = root.get_node_or_null("SafePlaces")
	_traps = root.get_node_or_null("Traps")
	_gameplay = root.get_node_or_null("Gameplay")
	_forest_decor = root.get_node_or_null("ForestDecor")

func _make_editor_world_editable(edited_root: Node) -> void:
	var editable_count := 0
	for node_name in GENERATED_ROOTS:
		var generated := edited_root.get_node_or_null(NodePath(node_name))
		if generated != null:
			editable_count += _claim_owner_recursive(generated, edited_root)
	print("LEVEL 2 EDITOR: ", editable_count, " generated nodes are editable and saveable")

func _claim_owner_recursive(node: Node, edited_root: Node) -> int:
	# Preserve ownership inside imported PackedScenes; only claim nodes created
	# procedurally by this level.
	var claimed := 0
	if node.owner == null:
		node.owner = edited_root
		claimed += 1
	for child in node.get_children():
		if child.owner == null:
			claimed += _claim_owner_recursive(child, edited_root)
	return claimed

func _make_materials() -> void:
	_mats.grass = _std(Color(0.17, 0.43, 0.14), 1.0)
	_mats.grass_alt = _std(Color(0.23, 0.50, 0.18), 1.0)
	_mats.path = _std(Color(0.19, 0.47, 0.17), 1.0)
	_mats.path_alt = _std(Color(0.23, 0.53, 0.20), 1.0)
	_mats.ruin = _std(Color(0.21, 0.50, 0.19), 1.0)
	_mats.vine_wall = _std(Color(0.15, 0.38, 0.18), 0.98)
	_mats.hedge = _std(Color(0.12, 0.34, 0.15), 0.98)
	_mats.moss = _std(Color(0.30, 0.42, 0.27), 0.93)
	_mats.dark = _std(Color(0.16, 0.19, 0.17), 0.9)
	_mats.cave_stone = _std(Color(0.16, 0.32, 0.18), 0.95)
	_mats.bush = _std(Color(0.10, 0.44, 0.15), 0.9)
	_mats.parchment = _std(Color(0.82, 0.72, 0.5), 0.85)
	_mats.parchment_dark = _std(Color(0.52, 0.42, 0.25), 0.9)
	_mats.stone_light = _std(Color(0.55, 0.52, 0.45), 0.9)
	_mats.bronze_green = _std(Color(0.42, 0.52, 0.38), 0.4)
	_mats.bronze_green.metallic = 0.6
	_mats.obsidian_metal = _std(Color(0.10, 0.06, 0.14), 0.25)
	_mats.obsidian_metal.metallic = 0.8
	_mats.obsidian_metal.emission_enabled = true
	_mats.obsidian_metal.emission = Color(0.4, 0.1, 0.7)
	_mats.obsidian_metal.emission_energy_multiplier = 1.4
	_mats.rune_stone = _std(Color(0.42, 0.46, 0.4), 0.92)
	_mats.frog_green = _std(Color(0.16, 0.52, 0.2), 0.7)
	_mats.leaf_green = _std(Color(0.15, 0.48, 0.16), 0.75)
	_mats.moon_white = _std(Color(0.92, 0.96, 1.0), 0.35)
	_mats.moon_white.emission_enabled = true
	_mats.moon_white.emission = Color(0.75, 0.85, 1.0)
	_mats.moon_white.emission_energy_multiplier = 1.3
	_mats.sun_gold = _std(Color(0.9, 0.65, 0.18), 0.3)
	_mats.sun_gold.metallic = 0.7
	_mats.sun_gold.emission_enabled = true
	_mats.sun_gold.emission = Color(0.95, 0.6, 0.15)
	_mats.sun_gold.emission_energy_multiplier = 1.6
	_mats.river_blue = _std(Color(0.1, 0.5, 0.55), 0.25)
	_mats.river_blue.metallic = 0.4
	_mats.river_blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats.river_blue.albedo_color.a = 0.85
	_mats.river_blue.emission_enabled = true
	_mats.river_blue.emission = Color(0.1, 0.55, 0.7)
	_mats.river_blue.emission_energy_multiplier = 1.4
	_mats.wood_handle = _std(Color(0.38, 0.24, 0.1), 0.85)
	_mats.red_knob = _std(Color(0.75, 0.12, 0.06), 0.5)
	_mats.red_knob.emission_enabled = true
	_mats.red_knob.emission = Color(0.6, 0.08, 0.04)
	_mats.red_knob.emission_energy_multiplier = 1.5
	_mats.bark = _std(Color(0.26, 0.15, 0.07), 0.9)
	_mats.hollow_dark = _std(Color(0.02, 0.02, 0.02), 1.0)
	_mats.vine = _std(Color(0.05, 0.18, 0.06), 0.9)
	_mats.vine_leaf = _std(Color(0.19, 0.51, 0.20), 0.85)
	_mats.grass_patch = _std(Color(0.27, 0.58, 0.22), 1.0)
	_mats.grass_blade = _std(Color(0.13, 0.42, 0.12), 0.9)
	_mats.grass_blade.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.flower = _std(Color(0.95, 0.82, 0.28), 0.7)
	# Procedural grass textures so the floors read as a lawn, not needles.
	_apply_grass_texture(_mats.grass, 11, Color(0.19, 0.47, 0.15), Color(0.11, 0.30, 0.10), Color(0.30, 0.62, 0.21), 24.0)
	_apply_grass_texture(_mats.path, 21, Color(0.20, 0.50, 0.17), Color(0.12, 0.32, 0.11), Color(0.31, 0.64, 0.22), 5.0)
	_apply_grass_texture(_mats.path_alt, 31, Color(0.23, 0.55, 0.19), Color(0.14, 0.36, 0.12), Color(0.35, 0.69, 0.24), 5.0)
	_apply_grass_texture(_mats.ruin, 41, Color(0.21, 0.52, 0.18), Color(0.13, 0.33, 0.11), Color(0.32, 0.66, 0.22), 6.0)
	_apply_grass_texture(_mats.cave_stone, 51, Color(0.13, 0.29, 0.15), Color(0.07, 0.18, 0.09), Color(0.21, 0.42, 0.20), 4.0)
	_mats.box_item = _std(Color(0.21, 0.09, 0.03), 0.85)
	_mats.pit_item = _std(Color(0.01, 0.01, 0.01), 1.0)
	_mats.gate_item = _std(Color(0.12, 0.16, 0.15), 0.9)
	_mats.ceiling = _std(Color(0.22, 0.25, 0.22), 0.98)

func _std(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func _apply_grass_texture(mat: StandardMaterial3D, seed: int,
		base: Color, dark: Color, light: Color, uv_scale: float) -> void:
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = _make_grass_texture(seed, base, dark, light)
	mat.albedo_texture_force_srgb = true
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)

func _make_grass_texture(seed: int, base: Color, dark: Color, light: Color) -> ImageTexture:
	# Small noise + speckle texture that reads as a grass lawn.
	# This swatch is tiled across large floors. A compact texture preserves the
	# visible color variation while avoiding five large runtime-generated maps.
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.12
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y)
			var blade := rng.randf()
			var c := base
			if blade < 0.16:
				c = dark
			elif blade > 0.82:
				c = light
			var f := clampf((n + 1.0) * 0.5, 0.0, 1.0)
			c = c.lerp(dark if f < 0.5 else light, absf(f - 0.5) * 0.5)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_shared_meshes() -> void:
	_mesh_pedestal = _cyl(_mats.moss, 0.95, 1.25, 1.3, 10)
	_mesh_pillar = _cyl(_mats.moss, 1.15, 1.45, 8.0, 10)
	_mesh_gate = _box_mesh(_mats.gate_item, Vector3(18, 8, 1.5))
	_mesh_spike = load("res://material/kiler1.glb")

func _box_mesh(mat: Material, size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.material = mat
	m.size = size
	return m

func _cyl(mat: Material, top: float, bottom: float, height: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.material = mat
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segs
	return m

func _torus(mat: Material, inner: float, outer: float, rings: int, segs: int) -> TorusMesh:
	var m := TorusMesh.new()
	m.material = mat
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = segs
	return m

func _sphere(mat: Material, radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.material = mat
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m

# --- Building helpers -------------------------------------------------------

func _node(parent: Node, name: String) -> Node:
	var n := Node.new()
	n.name = name
	parent.add_child(n)
	return n

func _static_box(parent: Node, name: String, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = _box_mesh(mat, size)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body

func _wall_x(parent: Node, name: String, x: float, z1: float, z2: float, mat: Material, height: float = WALL_HEIGHT) -> void:
	if is_equal_approx(z1, z2):
		return
	_static_box(parent, name, Vector3(x, height / 2.0, (z1 + z2) / 2.0),
		Vector3(WALL_THICK, height, absf(z2 - z1)), mat)

func _wall_z(parent: Node, name: String, z: float, x1: float, x2: float, mat: Material, height: float = WALL_HEIGHT) -> void:
	if is_equal_approx(x1, x2):
		return
	_static_box(parent, name, Vector3((x1 + x2) / 2.0, height / 2.0, z),
		Vector3(absf(x2 - x1), height, WALL_THICK), mat)

func _floor_rect(parent: Node, name: String, cx: float, cz: float, sx: float, sz: float, mat: Material) -> void:
	_static_box(parent, name, Vector3(cx, 0.0, cz), Vector3(sx, 0.2, sz), mat)

func _light(parent: Node, name: String, pos: Vector3, color: Color, energy: float, range: float = 10.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range
	l.shadow_enabled = false
	parent.add_child(l)
	return l

func _add_interactable(parent: Node, name: String, pos: Vector3, action: String, prompt: String,
		extra_groups: Array[String] = []) -> Area3D:
	var area := Area3D.new()
	area.name = name
	area.position = pos
	area.add_to_group("jungle_interactable")
	for g in extra_groups:
		area.add_to_group(g)
	area.set_meta("action", action)
	area.set_meta("prompt", prompt)
	parent.add_child(area)
	var container := Node3D.new()
	container.name = "Mesh"
	area.add_child(container)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	cs.shape = sphere
	area.add_child(cs)
	return area

func _add_pedestal(interactable: Area3D) -> void:
	var ped := StaticBody3D.new()
	ped.name = "Pedestal"
	ped.position = Vector3(0, -0.35 - interactable.position.y, 0)
	interactable.add_child(ped)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh_pedestal
	ped.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = 1.1
	shape.height = 1.3
	cs.shape = shape
	ped.add_child(cs)

func _add_safe_place(parent: Node, name: String, pos: Vector3, prompt: String) -> void:
	var area := Area3D.new()
	area.name = name
	area.position = pos
	area.add_to_group("jungle_interactable")
	area.set_meta("action", "safe_hide")
	area.set_meta("prompt", prompt)
	parent.add_child(area)
	var container := Node3D.new()
	container.name = "Mesh"
	area.add_child(container)
	_build_safe_item(container, area.position.y)
	var marker := Marker3D.new()
	marker.name = "HideMarker"
	marker.position = Vector3(0, -0.4, 0)
	area.add_child(marker)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	cs.shape = sphere
	area.add_child(cs)

func _add_part(parent: Node, name: String, mesh: Mesh, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _item_ground_y(area_y: float) -> float:
	return 0.1 - area_y

func _build_map_item(container: Node, area_y: float) -> void:
	var g := _item_ground_y(area_y)
	_add_part(container, "Stone", _cyl(_mats.stone_light, 0.22, 0.3, 0.5, 10),
		Vector3(0, g, 0))
	_add_part(container, "Scroll", _cyl(_mats.parchment, 0.13, 0.13, 0.8, 12),
		Vector3(0, g + 0.3, 0), Vector3(0, 0, PI / 2.0))
	_add_part(container, "CapA", _cyl(_mats.parchment_dark, 0.145, 0.145, 0.08, 12),
		Vector3(0.43, g + 0.3, 0), Vector3(0, 0, PI / 2.0))
	_add_part(container, "CapB", _cyl(_mats.parchment_dark, 0.145, 0.145, 0.08, 12),
		Vector3(-0.43, g + 0.3, 0), Vector3(0, 0, PI / 2.0))

func _build_key_item(container: Node, area_y: float, obsidian: bool) -> void:
	var g := _item_ground_y(area_y)
	var mat: Material = _mats.obsidian_metal if obsidian else _mats.bronze_green
	_add_part(container, "Stone", _cyl(_mats.stone_light, 0.26, 0.34, 0.5, 10),
		Vector3(0, g - 0.02, 0))
	_add_part(container, "Ring", _torus(mat, 0.1, 0.15, 16, 8),
		Vector3(0, g + 0.1, 0.3), Vector3(PI / 2.0, 0, 0))
	_add_part(container, "Shaft", _box_mesh(mat, Vector3(0.07, 0.07, 0.44)),
		Vector3(0, g + 0.1, -0.05))
	_add_part(container, "Tooth1", _box_mesh(mat, Vector3(0.07, 0.05, 0.14)),
		Vector3(0, g + 0.06, -0.2))
	_add_part(container, "Tooth2", _box_mesh(mat, Vector3(0.07, 0.06, 0.1)),
		Vector3(0, g + 0.02, -0.26))

func _build_rune_item(container: Node, area_y: float, rune_type: String) -> void:
	var g := _item_ground_y(area_y)
	_add_part(container, "Tablet", _box_mesh(_mats.rune_stone, Vector3(1.15, 1.5, 0.28)),
		Vector3(0, g + 0.95, 0))
	_add_part(container, "Base", _box_mesh(_mats.rune_stone, Vector3(1.35, 0.14, 0.55)),
		Vector3(0, g + 0.82, 0))
	var sy := g + 1.35
	match rune_type:
		"frog":
			_add_part(container, "FrogBody", _sphere(_mats.frog_green, 0.3),
				Vector3(0, sy + 0.05, 0.17))
			_add_part(container, "EyeL", _sphere(_mats.frog_green, 0.1),
				Vector3(-0.12, sy + 0.32, 0.23))
			_add_part(container, "EyeR", _sphere(_mats.frog_green, 0.1),
				Vector3(0.12, sy + 0.32, 0.23))
			_add_part(container, "PupilL", _sphere(_mats.moon_white, 0.045),
				Vector3(-0.12, sy + 0.32, 0.29))
			_add_part(container, "PupilR", _sphere(_mats.moon_white, 0.045),
				Vector3(0.12, sy + 0.32, 0.29))
		"leaf":
			_add_part(container, "Leaf", _sphere(_mats.leaf_green, 0.42),
				Vector3(0, sy + 0.15, 0.13), Vector3.ZERO, Vector3(1.6, 0.5, 0.55))
			_add_part(container, "Stem", _cyl(_mats.leaf_green, 0.035, 0.05, 0.5, 6),
				Vector3(0, sy - 0.15, 0.13))
		"moon":
			_add_part(container, "Moon", _sphere(_mats.moon_white, 0.3),
				Vector3(0.08, sy + 0.2, 0.14))
			_add_part(container, "Crescent", _sphere(_mats.rune_stone, 0.24),
				Vector3(-0.06, sy + 0.26, 0.24))

func _build_switch_item(container: Node, area_y: float, kind: String) -> void:
	var g := _item_ground_y(area_y)
	match kind:
		"sun":
			_add_part(container, "Dish", _cyl(_mats.stone_light, 0.5, 0.62, 0.28, 12),
				Vector3(0, g + 0.28, 0))
			_add_part(container, "SunDisc", _cyl(_mats.sun_gold, 0.34, 0.34, 0.1, 20),
				Vector3(0, g + 0.52, 0), Vector3(PI / 2.0, 0, 0))
			_add_part(container, "SunOrb", _sphere(_mats.sun_gold, 0.12),
				Vector3(0, g + 0.56, 0.12))
		"river":
			_add_part(container, "Basin", _cyl(_mats.stone_light, 0.55, 0.68, 0.34, 12),
				Vector3(0, g + 0.26, 0))
			_add_part(container, "Water", _cyl(_mats.river_blue, 0.42, 0.42, 0.14, 12),
				Vector3(0, g + 0.42, 0))
			_add_part(container, "Wave1", _sphere(_mats.river_blue, 0.13),
				Vector3(0.2, g + 0.5, 0))
			_add_part(container, "Wave2", _sphere(_mats.river_blue, 0.09),
				Vector3(-0.2, g + 0.46, 0))
		"lever":
			_add_part(container, "LeverBase", _box_mesh(_mats.wood_handle, Vector3(0.7, 0.35, 0.5)),
				Vector3(0, g + 0.28, 0))
			_add_part(container, "Pole", _cyl(_mats.wood_handle, 0.07, 0.09, 0.9, 10),
				Vector3(0, g + 0.75, 0))
			_add_part(container, "Knob", _sphere(_mats.red_knob, 0.11),
				Vector3(0, g + 1.3, 0))

func _build_safe_item(container: Node, area_y: float) -> void:
	var g := _item_ground_y(area_y)
	_add_part(container, "Outer", _cyl(_mats.bark, 1.7, 1.95, 2.6, 14),
		Vector3(0, g + 1.3, 0))
	_add_part(container, "Inner", _cyl(_mats.hollow_dark, 1.2, 1.3, 2.5, 14),
		Vector3(0, g + 1.25, 0))
	_add_part(container, "Rim", _torus(_mats.bark, 1.35, 1.75, 14, 10),
		Vector3(0, g + 2.55, 0), Vector3(PI / 2.0, 0, 0))

func _add_gate(parent: Node, name: String, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh_gate
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(18, 8, 1.5)
	cs.shape = box
	body.add_child(cs)
	return body

func _add_pillar(parent: Node, name: String, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh_pillar
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = 1.35
	shape.height = 8.0
	cs.shape = shape
	body.add_child(cs)

func _add_tree(parent: Node, name: String, pos: Vector3, scale: float, variety: int = 0) -> float:
	var tree := JUNGLE_TREE.instantiate() as StaticBody3D
	tree.name = name
	tree.position = pos
	tree.rotation.y = variety * 1.7 + fposmod(pos.x * 0.37 + pos.z * 0.13, TAU)
	tree.tree_scale = scale
	tree.generation_seed = int(fposmod(pos.x * 97.0 + pos.z * 31.0, 100000.0)) + variety * 17
	parent.add_child(tree)
	return 9.9 * scale

func _line_passage_with_trees() -> void:
	_vine_arches = _node(_forest_decor, "VineArches")
	# Corridor A: 6 pairs, plus diagonals between rows.
	_vine_web("A", [
		Vector3(-78, 0, -115), Vector3(-72, 0, -115), Vector3(-66, 0, -115),
		Vector3(-60, 0, -115), Vector3(-54, 0, -115), Vector3(-42, 0, -115),
	], [
		Vector3(-76, 0, -94), Vector3(-70, 0, -94), Vector3(-64, 0, -94),
		Vector3(-56, 0, -94), Vector3(-50, 0, -94), Vector3(-38, 0, -94),
	], [1.8, 1.6, 1.7, 1.7, 1.5, 1.8], [1.7, 1.8, 1.6, 1.8, 1.6, 1.7])
	# Corridor A2: 5 pairs.
	_vine_web("A2", [
		Vector3(-42, 0, -92), Vector3(-42, 0, -82), Vector3(-42, 0, -72),
		Vector3(-42, 0, -64), Vector3(-42, 0, -56),
	], [
		Vector3(-18, 0, -92), Vector3(-18, 0, -82), Vector3(-18, 0, -72),
		Vector3(-18, 0, -64), Vector3(-18, 0, -56),
	], [1.8, 1.5, 1.7, 1.6, 1.8], [1.7, 1.7, 1.8, 1.5, 1.7])
	# Corridor B: 7 pairs.
	_vine_web("B", [
		Vector3(-6, 0, -46), Vector3(-2, 0, -46), Vector3(8, 0, -46),
		Vector3(14, 0, -46), Vector3(22, 0, -46), Vector3(32, 0, -46), Vector3(38, 0, -46),
	], [
		Vector3(-6, 0, -24), Vector3(-2, 0, -24), Vector3(8, 0, -24),
		Vector3(12, 0, -24), Vector3(20, 0, -24), Vector3(30, 0, -24), Vector3(38, 0, -24),
	], [1.8, 1.6, 1.7, 1.7, 1.5, 1.8, 1.6], [1.7, 1.7, 1.8, 1.6, 1.8, 1.7, 1.5])
	# Corridor C (north-south): trees on the west side only (east is the cave).
	_add_tree(_forest_decor, "ExtraC1", Vector3(33, 0, -28), 1.8, 16)
	_add_tree(_forest_decor, "ExtraC2", Vector3(33, 0, -16), 1.7, 17)
	_add_tree(_forest_decor, "ExtraC3", Vector3(33, 0, 4), 1.8, 18)
	_add_tree(_forest_decor, "ExtraC4", Vector3(33, 0, 24), 1.6, 19)
	_add_tree(_forest_decor, "ExtraC5", Vector3(33, 0, 44), 1.7, 20)
	_add_tree(_forest_decor, "ExtraC6", Vector3(33, 0, 56), 1.5, 21)
	_add_tree(_forest_decor, "ExtraC7", Vector3(33, 0, 64), 1.8, 22)
	# Corridor D: 4 pairs.
	_vine_web("D", [
		Vector3(78, 0, 110), Vector3(78, 0, 118), Vector3(78, 0, 126), Vector3(78, 0, 134),
	], [
		Vector3(102, 0, 110), Vector3(102, 0, 118), Vector3(102, 0, 126), Vector3(102, 0, 134),
	], [1.8, 1.5, 1.7, 1.6], [1.7, 1.7, 1.8, 1.5])
	# Corridor E: 7 pairs.
	_vine_web("E", [
		Vector3(130, 0, 150), Vector3(140, 0, 150), Vector3(150, 0, 150), Vector3(156, 0, 150),
		Vector3(164, 0, 150), Vector3(178, 0, 150), Vector3(190, 0, 150),
	], [
		Vector3(130, 0, 174), Vector3(140, 0, 174), Vector3(150, 0, 174), Vector3(156, 0, 174),
		Vector3(164, 0, 174), Vector3(178, 0, 174), Vector3(190, 0, 174),
	], [1.6, 1.8, 1.5, 1.7, 1.7, 1.6, 1.8], [1.8, 1.7, 1.6, 1.8, 1.5, 1.7, 1.7])
	# Plaza extras.
	_add_tree(_forest_decor, "ExtraP1", Vector3(-102, 0, -116), 1.8, 33)
	_add_tree(_forest_decor, "ExtraP2", Vector3(-116, 0, -104), 1.6, 34)
	_add_tree(_forest_decor, "ExtraP3", Vector3(-42, 0, -48), 1.7, 35)
	_add_tree(_forest_decor, "ExtraP4", Vector3(116, 0, 147), 1.8, 36)
	_add_tree(_forest_decor, "ExtraP5", Vector3(64, 0, 177), 1.6, 37)
	_add_tree(_forest_decor, "ExtraP6", Vector3(168, 0, 174), 1.7, 38)

func _vine_web(name: String, row_a: Array[Vector3], row_b: Array[Vector3],
		scale_a: Array[float], scale_b: Array[float]) -> void:
	for i in row_a.size():
		var ha := _add_tree(_forest_decor, name + "N%d" % i, row_a[i], scale_a[i], 50 + i * 2)
		var hb := _add_tree(_forest_decor, name + "S%d" % i, row_b[i], scale_b[i], 51 + i * 2)
		var ay := (ha + hb) / 2.0 - 1.0
		# Direct arch across the passage.
		_add_vine_arch(_vine_arches, name + "D%d" % i,
			Vector3(row_a[i].x, ay, row_a[i].z), Vector3(row_b[i].x, ay, row_b[i].z))
		# A second, lower arch over the same span for density.
		_add_vine_arch(_vine_arches, name + "Db%d" % i,
			Vector3(row_a[i].x, ay - 2.6, row_a[i].z), Vector3(row_b[i].x, ay - 2.6, row_b[i].z),
			6, 2.6, 3, 0, 0.035)
		# Diagonal links between adjacent rows (different rows connected).
		if i < row_a.size() - 1:
			var hc := 9.9 * scale_a[i + 1]
			var hd := 9.9 * scale_b[i + 1]
			var ax := (ha + hd) / 2.0 - 1.0
			_add_vine_arch(_vine_arches, name + "X%d" % i,
				Vector3(row_a[i].x, ax, row_a[i].z), Vector3(row_b[i + 1].x, ax, row_b[i + 1].z),
				7, 4.4, 3, 1, 0.035)
			var ay2 := (hc + hb) / 2.0 - 1.0
			_add_vine_arch(_vine_arches, name + "Y%d" % i,
				Vector3(row_a[i + 1].x, ay2, row_a[i + 1].z), Vector3(row_b[i].x, ay2, row_b[i].z),
				7, 4.4, 3, 1, 0.035)

func _add_vine_arch(parent: Node, name: String, a: Vector3, b: Vector3,
		segments: int = 8, sag: float = 3.4, fringe_every: int = 2,
		long_strands: int = 1, radius: float = 0.045) -> void:
	var pts: Array[Vector3] = []
	for i in segments + 1:
		var t := float(i) / float(segments)
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	for i in segments:
		_add_vine_segment(parent, name + "_s%d" % i, pts[i], pts[i + 1], radius)
	# Dense hanging fringe along the whole arch.
	for i in segments + 1:
		if i % fringe_every == 0:
			var drop := 0.9 + float((i * 5) % 4) * 0.7
			_add_vine_segment(parent, name + "_f%d" % i, pts[i], pts[i] + Vector3(0, -drop, 0), 0.03)
	# A few longer strands from the middle.
	for i in long_strands:
		var idx := int(segments * (0.35 + i * 0.15))
		var drop := 1.8 + i * 0.8
		_add_vine_segment(parent, name + "_h%d" % i, pts[idx], pts[idx] + Vector3(0, -drop, 0), 0.035)

func _add_vine_segment(parent: Node, name: String, from: Vector3, to: Vector3, radius: float) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		return
	var m := CylinderMesh.new()
	m.material = _mats.vine
	m.top_radius = radius
	m.bottom_radius = radius * 1.3
	m.height = length
	m.radial_segments = 4
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = m
	mi.transform = Transform3D(_basis_from_y(dir), (from + to) / 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _basis_from_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _drape_wall(parent: Node, name: String, a: Vector3, b: Vector3) -> void:
	# Drapes hanging vines + leaf clusters over a wall's interior face.
	# a/b are the wall-top line, already offset toward the passage.
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(name.hash())
	var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var count := clampi(int(length / 7.0), 3, 14)
	_add_vine_segment(parent, name + "_top", a, b, 0.09)
	for i in count:
		var t := clampf((i + 0.5) / count + rng.randf_range(-0.12, 0.12), 0.05, 0.95)
		var top := a.lerp(b, t)
		top.y = rng.randf_range(6.6, 7.9)
		var hang := rng.randf_range(2.0, 5.5)
		_add_vine_segment(parent, name + "_v%d" % i, top, top + Vector3(0, -hang, 0), 0.08)
		var leaf_y := top.y - hang * 0.55
		_add_wall_leaf_cluster(parent, name + "_v%d_l" % i,
			Vector3(top.x, leaf_y, top.z), rng.randf_range(0.5, 0.85))
	# Scattered irregular clumps across the whole wall face.
	for i in maxi(2, count / 2):
		var t := rng.randf_range(0.03, 0.97)
		var pos := a.lerp(b, t)
		if absf(a.x - b.x) > 0.1:
			pos.x += rng.randf_range(-0.6, 0.6)
		else:
			pos.z += rng.randf_range(-0.6, 0.6)
		pos.y = rng.randf_range(1.8, 7.6)
		_add_wall_leaf_cluster(parent, name + "_w%d" % i, pos, rng.randf_range(0.4, 0.8))
	for i in 2:
		var leaf := a.lerp(b, rng.randf_range(0.05, 0.95))
		leaf.y = 8.0
		_add_wall_leaf_cluster(parent, name + "_t%d" % i, leaf, rng.randf_range(0.5, 0.9))

func _add_wall_leaf_cluster(parent: Node, name: String, pos: Vector3, size: float) -> void:
	# An irregular leafy clump made of several squashed, randomly rotated spheres.
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(name.hash())
	var parts := rng.randi_range(1, 2)
	for j in parts:
		var m := SphereMesh.new()
		m.material = _mats.vine_leaf
		m.radius = size * rng.randf_range(0.35, 0.7)
		m.height = m.radius * 2.0
		m.radial_segments = 6
		m.rings = 3
		var mi := MeshInstance3D.new()
		mi.name = name + "_%d" % j
		mi.mesh = m
		mi.position = pos + Vector3(
			rng.randf_range(-size * 0.6, size * 0.6),
			rng.randf_range(-size * 0.3, size * 0.3),
			rng.randf_range(-size * 0.4, size * 0.2))
		mi.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-PI, PI), rng.randf_range(-0.6, 0.6))
		mi.scale = Vector3(rng.randf_range(0.8, 1.5), rng.randf_range(0.5, 0.9), rng.randf_range(0.8, 1.5))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

func _grassify_floor(parent: Node, name: String, cx: float, cz: float, sx: float, sz: float,
		with_tufts: bool = true) -> void:
	# Collects grass blade / patch / flower transforms for a floor into the shared
	# MultiMesh buffers so even thousands of blades render in a single draw call.
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(name.hash())
	var area := sx * sz
	var patches := maxi(2, int(area / 11.0))
	for i in patches:
		var pos := Vector3(cx + rng.randf_range(-sx / 2.0, sx / 2.0),
			0.10, cz + rng.randf_range(-sz / 2.0, sz / 2.0))
		var s := rng.randf_range(0.8, 1.8)
		var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI))
		basis = basis.scaled(Vector3(s, 1.0, s))
		_patch_xforms.append(Transform3D(basis, pos))
	if not with_tufts:
		return
	var blades := maxi(3, int(area / 3.5))
	for i in blades:
		var pos := Vector3(cx + rng.randf_range(-sx / 2.0, sx / 2.0),
			0.0, cz + rng.randf_range(-sz / 2.0, sz / 2.0))
		var sy := rng.randf_range(0.35, 0.65)
		var sw := rng.randf_range(1.0, 1.5)
		var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI))
		basis = basis.rotated(Vector3.RIGHT, rng.randf_range(0.3, 0.7))
		basis = basis.scaled(Vector3(sw, sy, sw))
		var t := Transform3D(basis, Vector3(pos.x, 0.1, pos.z))
		var base_world := t * Vector3(0, -0.3, 0)
		t.origin.y = 0.1 - base_world.y
		_blade_xforms.append(t)
		if i % 18 == 0:
			var fb := Basis(Vector3.UP, rng.randf_range(-PI, PI))
			fb = fb.scaled(Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.3)))
			_flower_xforms.append(Transform3D(fb, Vector3(pos.x, 0.1 + 0.24 * sy, pos.z)))

func _build_grass_detail() -> void:
	var detail := _node(get_parent(), "GrassDetail")
	var blade_mesh := _make_cross_blade_mesh()
	_add_multimesh(detail, "Blades", blade_mesh, _blade_xforms)
	var patch_mesh := CylinderMesh.new()
	patch_mesh.material = _mats.grass_patch
	patch_mesh.top_radius = 1.0
	patch_mesh.bottom_radius = 1.0
	patch_mesh.height = 0.08
	patch_mesh.radial_segments = 6
	_add_multimesh(detail, "Patches", patch_mesh, _patch_xforms)
	var flower_mesh := SphereMesh.new()
	flower_mesh.material = _mats.flower
	flower_mesh.radius = 0.07
	flower_mesh.height = 0.14
	flower_mesh.radial_segments = 6
	flower_mesh.rings = 3
	_add_multimesh(detail, "Flowers", flower_mesh, _flower_xforms)

func _add_multimesh(parent: Node, name: String, mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _make_cross_blade_mesh() -> ArrayMesh:
	# Two crossed, double-sided quads remain readable from every direction and
	# use four triangles instead of a cylinder for every grass instance.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_mats.grass_blade)
	var planes: Array[PackedVector3Array] = [
		PackedVector3Array([
			Vector3(-0.045, -0.3, 0), Vector3(0.045, -0.3, 0),
			Vector3(0.045, 0.3, 0), Vector3(-0.045, 0.3, 0),
		]),
		PackedVector3Array([
			Vector3(0, -0.3, -0.045), Vector3(0, -0.3, 0.045),
			Vector3(0, 0.3, 0.045), Vector3(0, 0.3, -0.045),
		]),
	]
	for vertices in planes:
		for index in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(vertices[index])
	st.generate_normals()
	return st.commit()

func _add_bush(parent: Node, name: String, pos: Vector3, scale: float) -> void:
	var bush := StaticBody3D.new()
	bush.name = name
	bush.position = pos
	parent.add_child(bush)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _sphere(_mats.bush, 1.2 * scale)
	mi.position = Vector3(0, 0.8 * scale, 0)
	bush.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var shape := SphereShape3D.new()
	shape.radius = 0.9 * scale
	cs.position = Vector3(0, 0.7 * scale, 0)
	cs.shape = shape
	bush.add_child(cs)

func _add_rock(parent: Node, name: String, pos: Vector3, scale: float) -> void:
	var rock := load("res://models/simple_route_rock.glb").instantiate() as Node3D
	rock.name = name
	rock.position = pos
	rock.scale = Vector3.ONE * scale
	parent.add_child(rock)

# --- Level construction -----------------------------------------------------

func _build_ground() -> void:
	var ground := _node(get_parent(), "Ground")
	# The ground plane is split into pieces with real holes under the grotto pool
	# and the temple pit, so hazards are proper deep holes instead of 0.6 m pits.
	var xs: Array[float] = [-155.0, -44.0, -34.0, 85.0, 95.0, 235.0]
	var zs: Array[float] = [-153.0, -46.0, -24.0, 165.0, 175.0, 217.0]
	var holes: Array[Rect2] = [Rect2(-44.0, -46.0, 10.0, 22.0), Rect2(85.0, 165.0, 10.0, 10.0)]
	for zi in zs.size() - 1:
		for xi in xs.size() - 1:
			var rect := Rect2(xs[xi], zs[zi], xs[xi + 1] - xs[xi], zs[zi + 1] - zs[zi])
			var is_hole := false
			for hole in holes:
				if rect.intersects(hole):
					is_hole = true
					break
			if is_hole:
				continue
			_static_box(ground, "Grass_%d_%d" % [xi, zi],
				Vector3(rect.position.x + rect.size.x / 2.0, -0.6, rect.position.y + rect.size.y / 2.0),
				Vector3(rect.size.x, 0.2, rect.size.y), _mats.grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in 260:
		var pos := Vector3(rng.randf_range(-150, 220), -0.45, rng.randf_range(-150, 210))
		var p2 := Vector2(pos.x, pos.z)
		var in_hole := false
		for hole in holes:
			if hole.has_point(p2):
				in_hole = true
				break
		if in_hole:
			continue
		var patch := MeshInstance3D.new()
		patch.name = "GrassPatch%03d" % i
		patch.mesh = _sphere(_mats.grass_alt, rng.randf_range(1.2, 3.2))
		patch.position = pos
		patch.scale = Vector3(1.0, 0.12, 1.0)
		ground.add_child(patch)

func _build_perimeter_walls() -> void:
	var world := _node(get_parent(), "WorldBounds")
	_wall_x(world, "WallWest", -157, -155, 219, _mats.hedge, 14.0)
	_wall_x(world, "WallEast", 237, -155, 219, _mats.hedge, 14.0)
	_wall_z(world, "WallNorth", -155, -157, 237, _mats.hedge, 14.0)
	_wall_z(world, "WallSouth", 219, -157, 237, _mats.hedge, 14.0)

func _build_start_room() -> void:
	var room := _node(_architecture, "StartRoom")
	_floor_rect(room, "Floor", -105, -105, 30, 30, _mats.path)
	_grassify_floor(room, "GrassStart", -105, -105, 30, 30)
	_wall_z(room, "WallNorth", -90, -120, -90, _mats.vine_wall)
	_wall_x(room, "WallWest", -120, -120, -90, _mats.vine_wall)
	_wall_z(room, "WallSouth", -120, -120, -90, _mats.vine_wall)
	_wall_x(room, "WallEastN", -90, -120, -111, _mats.vine_wall)
	_wall_x(room, "WallEastS", -90, -99, -90, _mats.vine_wall)
	_drape_wall(room, "VineStartN", Vector3(-120, 8, -91.15), Vector3(-90, 8, -91.15))
	_drape_wall(room, "VineStartW", Vector3(-118.85, 8, -120), Vector3(-118.85, 8, -90))
	_drape_wall(room, "VineStartS", Vector3(-120, 8, -118.85), Vector3(-90, 8, -118.85))
	_drape_wall(room, "VineStartEN", Vector3(-91.15, 8, -120), Vector3(-91.15, 8, -111))
	_drape_wall(room, "VineStartES", Vector3(-91.15, 8, -99), Vector3(-91.15, 8, -90))
	_add_tree(_forest_decor, "StartTree1", Vector3(-114, 0, -114), 2.0, 0)
	_add_tree(_forest_decor, "StartTree2", Vector3(-114, 0, -96), 1.5, 1)
	_add_tree(_forest_decor, "StartTree3", Vector3(-96, 0, -114), 1.8, 2)
	_add_bush(_forest_decor, "StartBush1", Vector3(-110, 0, -100), 1.1)
	_add_bush(_forest_decor, "StartBush2", Vector3(-100, 0, -108), 0.9)
	_add_rock(_forest_decor, "StartRock", Vector3(-108, 0, -92), 1.2)
	# The map sits in the middle of the first main road.
	var map_item := _add_interactable(_interactables, "MapPickup",
		Vector3(-60, 1.0, -105), "pickup_map", "TAKE JUNGLE MAP")
	_build_map_item(map_item.get_node("Mesh"), map_item.position.y)

func _build_corridor_a() -> void:
	var corridor := _node(_architecture, "CorridorA")
	_floor_rect(corridor, "Floor", -60, -105, 60, 12, _mats.path_alt)
	_grassify_floor(corridor, "GrassA", -60, -105, 60, 12)
	_wall_z(corridor, "WallNorth", -99, -90, -30, _mats.hedge)
	_wall_z(corridor, "WallSouth", -111, -90, -24, _mats.hedge)
	_drape_wall(corridor, "VineAN", Vector3(-90, 8, -100.15), Vector3(-30, 8, -100.15))
	_drape_wall(corridor, "VineAS", Vector3(-90, 8, -109.85), Vector3(-24, 8, -109.85))
	_light(corridor, "PathLight1", Vector3(-75, 4.5, -105), Color(0.9, 0.95, 0.7), 1.4, 20.0)
	_light(corridor, "PathLight2", Vector3(-45, 4.5, -105), Color(0.9, 0.95, 0.7), 1.4, 20.0)
	_add_tree(_forest_decor, "CorridorATree1", Vector3(-60, 0, -94), 2.0, 0)
	_add_tree(_forest_decor, "CorridorATree2", Vector3(-75, 0, -116), 1.8, 1)
	_add_bush(_forest_decor, "CorridorABush", Vector3(-45, 0, -116), 1.0)

func _build_corridor_a2() -> void:
	var corridor := _node(_architecture, "CorridorA2")
	_floor_rect(corridor, "Floor", -30, -78.5, 12, 53, _mats.path_alt)
	_floor_rect(corridor, "CornerFill", -27, -108, 6, 6, _mats.path_alt)
	_grassify_floor(corridor, "GrassA2", -30, -78.5, 12, 53)
	_wall_x(corridor, "WallWest", -36, -99, -52, _mats.hedge)
	_wall_x(corridor, "WallEast", -24, -111, -52, _mats.hedge)
	_drape_wall(corridor, "VineA2W", Vector3(-34.85, 8, -105), Vector3(-34.85, 8, -52))
	_drape_wall(corridor, "VineA2E", Vector3(-25.15, 8, -105), Vector3(-25.15, 8, -52))
	_light(corridor, "PathLight", Vector3(-30, 4.5, -78), Color(0.9, 0.95, 0.7), 1.4, 20.0)
	_add_tree(_forest_decor, "CorridorA2Tree1", Vector3(-20, 0, -90), 2.1, 0)
	_add_tree(_forest_decor, "CorridorA2Tree2", Vector3(-40, 0, -68), 1.7, 1)
	_add_bush(_forest_decor, "CorridorA2Bush", Vector3(-20, 0, -60), 1.1)

func _build_grotto_room() -> void:
	var room := _node(_architecture, "GrottoRoom")
	# Floor pieces around the sunken pool (hole at x -44..-34, z -46..-24).
	_floor_rect(room, "FloorEast", -23.5, -35, 21, 34, _mats.path)
	_floor_rect(room, "FloorNW", -40.5, -49, 13, 6, _mats.path)
	_floor_rect(room, "FloorSW", -40.5, -21, 13, 6, _mats.path)
	_floor_rect(room, "FloorLedge", -45.5, -35, 3, 22, _mats.path)
	_static_box(room, "PoolBottom", Vector3(-39, -2.6, -35), Vector3(10, 0.4, 22), _mats.pit_item)
	_grassify_floor(room, "GrassGrottoE", -23.5, -35, 21, 34)
	_grassify_floor(room, "GrassGrottoNW", -40.5, -49, 13, 6)
	_grassify_floor(room, "GrassGrottoSW", -40.5, -21, 13, 6)
	# West wall (waterfall against it), south wall closed.
	_wall_x(room, "WallWest", -47, -52, -18, _mats.moss)
	_wall_z(room, "WallSouth", -18, -47, -13, _mats.moss)
	# North wall with the corridor A2 opening.
	_wall_z(room, "WallNorthW", -52, -47, -36, _mats.moss)
	_wall_z(room, "WallNorthE", -52, -24, -13, _mats.moss)
	# East wall with the corridor B opening.
	_wall_x(room, "WallEastN", -13, -52, -41, _mats.moss)
	_wall_x(room, "WallEastS", -13, -29, -18, _mats.moss)
	_drape_wall(room, "VineGrottoW", Vector3(-45.85, 8, -52), Vector3(-45.85, 8, -18))
	_drape_wall(room, "VineGrottoN", Vector3(-47, 8, -50.85), Vector3(-13, 8, -50.85))
	_drape_wall(room, "VineGrottoS", Vector3(-47, 8, -19.15), Vector3(-13, 8, -19.15))
	_drape_wall(room, "VineGrottoE1", Vector3(-14.15, 8, -52), Vector3(-14.15, 8, -41))
	_drape_wall(room, "VineGrottoE2", Vector3(-14.15, 8, -29), Vector3(-14.15, 8, -18))
	_build_waterfall(room)
	var pool := _node(room, "PoolRocks")
	var pool_rock_spots := [
		Vector3(-40, 0, -46.6), Vector3(-37, 0, -46.8),
	]
	for i in pool_rock_spots.size():
		_add_rock(pool, "PoolRock%d" % i, pool_rock_spots[i], 0.9)
	_light(room, "GrottoSun", Vector3(-30, 9, -35), Color(1.0, 0.9, 0.6), 1.9, 26.0)
	_add_tree(_forest_decor, "GrottoTree1", Vector3(-20, 0, -48), 2.2, 0)
	_add_tree(_forest_decor, "GrottoTree2", Vector3(-18, 0, -22), 1.9, 1)
	_add_bush(_forest_decor, "GrottoBush1", Vector3(-14, 0, -20), 1.2)
	_add_bush(_forest_decor, "GrottoBush2", Vector3(-14, 0, -46), 1.0)

func _build_waterfall(parent: Node) -> void:
	var water := _node(parent, "Waterfall")
	var cliff := _node(water, "Cliff")
	# One collision-backed cliff face plus a projecting crown replaces the old
	# overlapping boxes. The silhouette is clearer and there is no hidden
	# coplanar geometry behind the waterfall.
	_static_box(cliff, "CliffBack", Vector3(-47.25, 4.8, -35), Vector3(1.0, 9.6, 24), _mats.moss)
	_static_box(cliff, "CliffCrown", Vector3(-46.25, 9.35, -35), Vector3(3.0, 1.1, 24), _mats.moss)
	var rock_positions: Array[Vector3] = [
		Vector3(-46.55, 7.2, -43.2), Vector3(-46.5, 8.1, -39.0),
		Vector3(-46.55, 7.6, -31.0), Vector3(-46.5, 8.3, -26.8),
	]
	for i in rock_positions.size():
		var scene_path := "res://models/simple_route_rock.glb" if i % 2 == 0 \
			else "res://models/rectangular_route_rock.glb"
		var rock := load(scene_path).instantiate() as Node3D
		rock.name = "CliffRock%d" % i
		rock.position = rock_positions[i]
		rock.rotation = Vector3(0.0, i * 0.8, 0.0)
		rock.scale = Vector3.ONE * (1.55 + i * 0.12)
		cliff.add_child(rock)
	var pool := MeshInstance3D.new()
	pool.name = "PoolSurface"
	pool.position = Vector3(-39.0, -1.28, -35.0)
	var pool_mesh := PlaneMesh.new()
	pool_mesh.size = Vector2(10, 22)
	pool_mesh.material = _make_water_material()
	pool.mesh = pool_mesh
	water.add_child(pool)
	# Layered sheets create depth and broken edges using only six triangles.
	_add_waterfall_sheet(water, "Fall", Vector3(-44.62, 4.55, -35.0),
		Vector2(20.0, 9.1), Color(0.24, 0.70, 0.68, 0.72), 1.0, 0.0)
	_add_waterfall_sheet(water, "FallMid", Vector3(-44.50, 4.65, -34.7),
		Vector2(15.5, 8.8), Color(0.38, 0.82, 0.76, 0.44), 1.35, 1.7)
	_add_waterfall_sheet(water, "FallHighlight", Vector3(-44.38, 4.75, -35.8),
		Vector2(8.5, 8.5), Color(0.72, 0.94, 0.88, 0.30), 1.65, 3.1)
	var foam := MeshInstance3D.new()
	foam.name = "ImpactFoam"
	foam.position = Vector3(-43.25, -1.20, -35.0)
	var foam_mesh := PlaneMesh.new()
	foam_mesh.size = Vector2(2.2, 19.0)
	foam_mesh.material = _make_foam_material()
	foam.mesh = foam_mesh
	water.add_child(foam)
	var mist := CPUParticles3D.new()
	mist.name = "Mist"
	mist.position = Vector3(-43.8, -0.9, -35.0)
	mist.emitting = true
	mist.amount = 56
	mist.lifetime = 2.6
	mist.randomness = 0.8
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(0.5, 0.25, 9.0)
	mist.direction = Vector3(1, 0, 0)
	mist.spread = 60.0
	mist.gravity = Vector3(0, -0.5, 0)
	mist.initial_velocity_min = 1.2
	mist.initial_velocity_max = 2.6
	mist.scale_amount_min = 0.6
	mist.scale_amount_max = 1.4
	var mist_mat := StandardMaterial3D.new()
	mist_mat.albedo_color = Color(0.75, 0.95, 0.9, 0.25)
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mist_mesh := SphereMesh.new()
	mist_mesh.material = mist_mat
	mist_mesh.radius = 0.35
	mist_mesh.height = 0.7
	mist.mesh = mist_mesh
	water.add_child(mist)
	_light(water, "WaterfallLight", Vector3(-42.5, 2.5, -35), Color(0.35, 0.85, 0.8), 2.4, 14.0)
	# Vine key hidden behind the falling water.
	var vine_key := _add_interactable(_interactables, "VineKey",
		Vector3(-45.4, 1.0, -35.0), "pickup_vine_key", "TAKE VINE KEY")
	_build_key_item(vine_key.get_node("Mesh"), vine_key.position.y, false)

func _make_water_material() -> Material:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode blend_mix, cull_disabled;\nvoid fragment(){\n float r1 = sin(UV.x * 34.0 + TIME * 1.4) * 0.025;\n float r2 = sin(UV.y * 25.0 - TIME * 1.1) * 0.02;\n ALBEDO = vec3(0.08, 0.42, 0.39) + r1 + r2;\n ROUGHNESS = 0.16;\n METALLIC = 0.08;\n ALPHA = 0.80;\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _add_waterfall_sheet(parent: Node, name: String, pos: Vector3, size: Vector2,
		tint: Color, speed: float, phase: float) -> void:
	var sheet := MeshInstance3D.new()
	sheet.name = name
	sheet.position = pos
	sheet.rotation.y = PI / 2.0
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = _make_waterfall_material(tint, speed, phase)
	sheet.mesh = mesh
	parent.add_child(sheet)

func _make_waterfall_material(tint: Color, speed: float, phase: float) -> Material:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode blend_mix, unshaded, cull_disabled;\nuniform vec4 water_tint : source_color;\nuniform float flow_speed = 1.0;\nuniform float phase = 0.0;\nvoid vertex(){\n VERTEX.z += sin(UV.x * 20.0 + TIME * flow_speed + phase) * 0.035;\n}\nvoid fragment(){\n float fine_streak = sin(UV.x * 58.0 + TIME * 1.2 + phase) * 0.08;\n float falling = sin(UV.y * 42.0 - TIME * 7.0 * flow_speed + phase) * 0.10;\n float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(0.0, 0.08, 1.0 - UV.x);\n float foam = smoothstep(0.78, 1.0, UV.y) * 0.16 + smoothstep(0.88, 1.0, 1.0 - UV.y) * 0.22;\n ALBEDO = water_tint.rgb + fine_streak + falling + foam;\n ALPHA = clamp((water_tint.a + fine_streak * 0.35 + foam) * edge, 0.0, 0.92);\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("water_tint", tint)
	mat.set_shader_parameter("flow_speed", speed)
	mat.set_shader_parameter("phase", phase)
	return mat

func _make_foam_material() -> Material:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode blend_mix, unshaded, cull_disabled;\nvoid fragment(){\n float cells = sin(UV.x * 45.0 + TIME * 2.1) * sin(UV.y * 32.0 - TIME * 1.6);\n float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(0.0, 0.18, 1.0 - UV.x);\n ALBEDO = mix(vec3(0.45, 0.78, 0.70), vec3(0.88, 1.0, 0.94), cells * 0.5 + 0.5);\n ALPHA = (0.38 + cells * 0.16) * edge;\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _build_corridor_b() -> void:
	var corridor := _node(_architecture, "CorridorB")
	_floor_rect(corridor, "Floor", 16, -35, 58, 12, _mats.path_alt)
	_grassify_floor(corridor, "GrassB", 16, -35, 58, 12)
	_wall_z(corridor, "WallNorth", -29, -13, 39, _mats.hedge)
	_wall_z(corridor, "WallSouth", -41, -13, 45, _mats.hedge)
	_drape_wall(corridor, "VineBN", Vector3(-13, 8, -30.15), Vector3(39, 8, -30.15))
	_drape_wall(corridor, "VineBS", Vector3(-13, 8, -39.85), Vector3(45, 8, -39.85))
	_light(corridor, "PathLight1", Vector3(10, 4.5, -35), Color(0.9, 0.95, 0.7), 1.4, 20.0)
	_light(corridor, "PathLight2", Vector3(35, 4.5, -35), Color(0.9, 0.95, 0.7), 1.4, 20.0)
	_add_tree(_forest_decor, "CorridorBTree1", Vector3(10, 0, -24), 2.1, 0)
	_add_tree(_forest_decor, "CorridorBTree2", Vector3(30, 0, -46), 1.8, 1)

func _build_corridor_c() -> void:
	var corridor := _node(_architecture, "CorridorC")
	_floor_rect(corridor, "Floor", 47, 21, 16, 100, _mats.path_alt)
	_floor_rect(corridor, "CornerFill", 50, -35, 10, 12, _mats.path_alt)
	_grassify_floor(corridor, "GrassC", 47, 21, 16, 100)
	_wall_x(corridor, "WallWest", 39, -29, 71, _mats.hedge)
	_wall_x(corridor, "WallEast", 55, -29, 59, _mats.hedge)
	_wall_x(corridor, "WallEastFill", 55, -41, -29, _mats.hedge)
	_wall_z(corridor, "WallSouthFill", -41, 45, 55, _mats.hedge)
	_wall_z(corridor, "WallEnd", 71, 39, 55, _mats.hedge)
	_drape_wall(corridor, "VineCW", Vector3(40.15, 8, -29), Vector3(40.15, 8, 71))
	_drape_wall(corridor, "VineCE", Vector3(53.85, 8, -29), Vector3(53.85, 8, 59))
	_drape_wall(corridor, "VineCEnd", Vector3(39, 8, 69.85), Vector3(55, 8, 69.85))
	_light(corridor, "PathLight1", Vector3(47, 4.5, -5), Color(0.9, 0.95, 0.7), 1.4, 22.0)
	_light(corridor, "PathLight2", Vector3(47, 4.5, 35), Color(0.9, 0.95, 0.7), 1.4, 22.0)
	_light(corridor, "PathLight3", Vector3(47, 4.5, 55), Color(0.9, 0.95, 0.7), 1.4, 22.0)
	_add_tree(_forest_decor, "CorridorCTree1", Vector3(33, 0, 10), 2.2, 0)
	_add_tree(_forest_decor, "CorridorCTree2", Vector3(61, 0, 0), 1.9, 1)

func _build_cave_room() -> void:
	var room := _node(_architecture, "CaveRoom")
	_floor_rect(room, "Floor", 90, 65, 70, 70, _mats.cave_stone)
	_grassify_floor(room, "GrassCave", 90, 65, 70, 70)
	# Perimeter: south closed, east closed, west + north have openings.
	_wall_z(room, "WallSouth", 30, 55, 125, _mats.cave_stone)
	_wall_x(room, "WallEast", 125, 30, 100, _mats.cave_stone)
	_wall_x(room, "WallWestN", 55, 30, 59, _mats.cave_stone)
	_wall_x(room, "WallWestS", 55, 71, 100, _mats.cave_stone)
	_wall_z(room, "WallNorthW", 100, 55, 84, _mats.cave_stone)
	_wall_z(room, "WallNorthE", 100, 96, 125, _mats.cave_stone)
	# Main east-west corridor through the middle (z 59..71).
	_wall_z(room, "MainNorthW", 59, 55, 64, _mats.cave_stone)
	_wall_z(room, "MainNorthM1", 59, 76, 84, _mats.cave_stone)
	_wall_z(room, "MainNorthM2", 59, 96, 98, _mats.cave_stone)
	_wall_z(room, "MainNorthE", 59, 110, 125, _mats.cave_stone)
	_wall_z(room, "MainSouthW", 71, 55, 84, _mats.cave_stone)
	_wall_z(room, "MainSouthE", 71, 96, 125, _mats.cave_stone)
	# Frog chamber (opens into the corridor at z=59, x 64..76).
	_wall_z(room, "FrogWallN", 36, 64, 76, _mats.moss)
	_wall_x(room, "FrogWallW", 64, 36, 59, _mats.moss)
	_wall_x(room, "FrogWallE", 76, 36, 59, _mats.moss)
	# Leaf chamber (opens into the corridor at z=59, x 98..110).
	_wall_z(room, "LeafWallN", 36, 98, 110, _mats.moss)
	_wall_x(room, "LeafWallW", 98, 36, 59, _mats.moss)
	_wall_x(room, "LeafWallE", 110, 36, 59, _mats.moss)
	# Moon chamber (opens into the corridor at z=59, x 84..96).
	_wall_z(room, "MoonWallN", 36, 84, 96, _mats.moss)
	_wall_x(room, "MoonWallW", 84, 36, 59, _mats.moss)
	_wall_x(room, "MoonWallE", 96, 36, 59, _mats.moss)
	# Vertical corridor to the gate (x 84..96, z 71..100).
	# Openings: east wall z 74..80 -> side hide grotto, west wall z 80..86 -> hide grotto.
	_wall_x(room, "GateWallW1", 84, 71, 80, _mats.moss)
	_wall_x(room, "GateWallW2", 84, 86, 100, _mats.moss)
	_wall_x(room, "GateWallE1", 96, 71, 74, _mats.moss)
	_wall_x(room, "GateWallE2", 96, 80, 100, _mats.moss)
	# Big boulders in the open areas.
	for i in 10:
		var rock := load("res://models/simple_route_rock.glb").instantiate() as Node3D
		rock.name = "Boulder%d" % i
		var spot: Vector3
		match i:
			0: spot = Vector3(58, 0, 96)
			1: spot = Vector3(70, 0, 96)
			2: spot = Vector3(120, 0, 94)
			3: spot = Vector3(104, 0, 90)
			4: spot = Vector3(58, 0, 78)
			5: spot = Vector3(116, 0, 92)
			6: spot = Vector3(86, 0, 33)
			7: spot = Vector3(118, 0, 36)
			8: spot = Vector3(118, 0, 54)
			9: spot = Vector3(58, 0, 44)
		rock.position = spot
		rock.scale = Vector3.ONE * 2.4
		room.add_child(rock)
	# Partial stone ceiling slabs with light gaps.
	for i in 4:
		var z_center := 36.0 + i * 14.0
		_static_box(room, "Ceiling%02d" % i, Vector3(90, 8.45, z_center), Vector3(70, 0.9, 9), _mats.ceiling)
	# Cave glows.
	_light(room, "CaveGlow01", Vector3(70, 3.0, 50), Color(0.25, 0.75, 0.35), 1.5, 12.0)
	_light(room, "CaveGlow02", Vector3(104, 3.0, 50), Color(0.30, 0.55, 0.85), 1.4, 12.0)
	_light(room, "CaveGlow03", Vector3(60, 3.0, 88), Color(0.25, 0.75, 0.35), 1.5, 12.0)
	_light(room, "CaveGlow04", Vector3(114, 3.0, 80), Color(0.35, 0.6, 0.4), 1.4, 12.0)
	_light(room, "ShaftLight01", Vector3(70, 6.5, 65), Color(1.0, 0.95, 0.75), 1.7, 14.0)
	_light(room, "ShaftLight02", Vector3(105, 6.5, 65), Color(1.0, 0.95, 0.75), 1.7, 14.0)
	_light(room, "ShaftLight03", Vector3(90, 6.5, 85), Color(1.0, 0.95, 0.75), 1.9, 16.0)
	_light(room, "ShaftLight04", Vector3(90, 6.5, 48), Color(1.0, 0.95, 0.75), 1.9, 16.0)
	# Runes in the three chambers.
	var frog := _add_interactable(_interactables, "FrogRune", Vector3(70, 0.6, 45), "rune_frog",
		"PRESS FROG RUNE", ["jungle_rune"])
	_build_rune_item(frog.get_node("Mesh"), frog.position.y, "frog")
	_add_pedestal(frog)
	var leaf := _add_interactable(_interactables, "LeafRune", Vector3(104, 0.6, 45), "rune_leaf",
		"PRESS LEAF RUNE", ["jungle_rune"])
	_build_rune_item(leaf.get_node("Mesh"), leaf.position.y, "leaf")
	_add_pedestal(leaf)
	var moon := _add_interactable(_interactables, "MoonRune", Vector3(90, 0.6, 48), "rune_moon",
		"PRESS MOON RUNE", ["jungle_rune"])
	_build_rune_item(moon.get_node("Mesh"), moon.position.y, "moon")
	_add_pedestal(moon)
	# Stone gate across the north exit.
	_add_gate(_gates, "CaveGate", Vector3(90, 3.5, 99.2))
	_add_safe_place(_safe_places, "CaveHide01", Vector3(62, 1.4, 88), "HIDE IN ROCK CREVICE")
	_add_safe_place(_safe_places, "CaveHide02", Vector3(120, 1.4, 78), "HIDE IN ROCK CREVICE")
	_add_tree(_forest_decor, "CaveTree1", Vector3(40, 0, 80), 2.2, 0)

func _build_corridor_d() -> void:
	var corridor := _node(_architecture, "CorridorD")
	_floor_rect(corridor, "Floor", 90, 122, 12, 44, _mats.path_alt)
	_grassify_floor(corridor, "GrassD", 90, 122, 12, 44)
	_wall_x(corridor, "WallWest", 84, 100, 144, _mats.hedge)
	_wall_x(corridor, "WallEast", 96, 100, 144, _mats.hedge)
	_drape_wall(corridor, "VineDW", Vector3(85.15, 8, 100), Vector3(85.15, 8, 144))
	_drape_wall(corridor, "VineDE", Vector3(94.85, 8, 100), Vector3(94.85, 8, 144))
	_light(corridor, "PathLight", Vector3(90, 4.5, 120), Color(0.9, 0.95, 0.7), 1.4, 22.0)
	_add_tree(_forest_decor, "CorridorDTree1", Vector3(80, 0, 128), 2.0, 0)

func _build_temple_room() -> void:
	var room := _node(_architecture, "TempleRoom")
	_floor_rect(room, "Floor", 90, 162, 60, 36, _mats.ruin)
	# Grass around the temple floor, keeping the pit opening clear.
	_grassify_floor(room, "GrassTempleW", 72, 162, 24, 36)
	_grassify_floor(room, "GrassTempleE", 108, 162, 24, 36)
	_grassify_floor(room, "GrassTempleS", 90, 154, 12, 20)
	_grassify_floor(room, "GrassTempleN", 90, 178, 12, 4)
	_wall_z(room, "WallNorth", 180, 60, 120, _mats.moss)
	_wall_z(room, "WallSouthW", 144, 60, 84, _mats.moss)
	_wall_z(room, "WallSouthE", 144, 96, 120, _mats.moss)
	_wall_x(room, "WallWest", 60, 144, 180, _mats.moss)
	_wall_x(room, "WallEastN", 120, 144, 156, _mats.moss)
	_wall_x(room, "WallEastS", 120, 168, 180, _mats.moss)
	_drape_wall(room, "VineTempleN", Vector3(60, 8, 178.85), Vector3(120, 8, 178.85))
	_drape_wall(room, "VineTempleS1", Vector3(60, 8, 145.15), Vector3(84, 8, 145.15))
	_drape_wall(room, "VineTempleS2", Vector3(96, 8, 145.15), Vector3(120, 8, 145.15))
	_drape_wall(room, "VineTempleW", Vector3(61.15, 8, 144), Vector3(61.15, 8, 180))
	_drape_wall(room, "VineTempleE1", Vector3(118.85, 8, 144), Vector3(118.85, 8, 156))
	_drape_wall(room, "VineTempleE2", Vector3(118.85, 8, 168), Vector3(118.85, 8, 180))
	var pillars := _node(room, "Pillars")
	_add_pillar(pillars, "Pillar01", Vector3(70, 4, 150))
	_add_pillar(pillars, "Pillar02", Vector3(110, 4, 150))
	_add_pillar(pillars, "Pillar03", Vector3(70, 4, 174))
	_add_pillar(pillars, "Pillar04", Vector3(110, 4, 174))
	# Traps.
	var heavy := _static_box(_traps, "HeavyBox", Vector3(90, 14, 158), Vector3(14, 5, 4), _mats.box_item)
	heavy.get_node("CollisionShape3D").set_deferred("disabled", true)
	_static_box(_traps, "PitDoor", Vector3(90, -0.1, 170), Vector3(10, 0.2, 10), _mats.path_alt)
	_static_box(_traps, "PitBottom", Vector3(90, -4.5, 170), Vector3(10, 0.4, 10), _mats.pit_item)
	for i in 4:
		var spikes := _mesh_spike.instantiate() as Node3D
		spikes.name = "Spikes%02d" % i
		var sx := 86.0 if i % 2 == 0 else 94.0
		var sz := 168.0 if i < 2 else 172.0
		spikes.position = Vector3(sx, -4.2, sz)
		spikes.scale = Vector3.ONE * 1.8
		_traps.add_child(spikes)
	# Side bridges around the pit.
	_static_box(room, "PitLeftBridge", Vector3(81, 0, 170), Vector3(6, 0.2, 10), _mats.ruin)
	_static_box(room, "PitRightBridge", Vector3(99, 0, 170), Vector3(6, 0.2, 10), _mats.ruin)
	# Interactables.
	var sun := _add_interactable(_interactables, "SunSwitch", Vector3(78, 1, 154), "sun_switch",
		"ACTIVATE SUN ALTAR")
	_build_switch_item(sun.get_node("Mesh"), sun.position.y, "sun")
	_add_pedestal(sun)
	var river := _add_interactable(_interactables, "RiverSwitch", Vector3(102, 1, 154), "river_switch",
		"ACTIVATE RIVER ALTAR")
	_build_switch_item(river.get_node("Mesh"), river.position.y, "river")
	_add_pedestal(river)
	var lever := _add_interactable(_interactables, "HeavyBoxLever", Vector3(88, 1, 150), "heavy_box_lever",
		"RELEASE HEAVY BOX")
	_build_switch_item(lever.get_node("Mesh"), lever.position.y, "lever")
	_add_pedestal(lever)
	var pit_lever := _add_interactable(_interactables, "PitLever", Vector3(104, 1, 166), "pit_lever",
		"OPEN GROUND TRAP")
	_build_switch_item(pit_lever.get_node("Mesh"), pit_lever.position.y, "lever")
	_add_pedestal(pit_lever)
	var obsidian_key := _add_interactable(_interactables, "ObsidianKey",
		Vector3(90, 1.2, 177), "pickup_obsidian_key", "TAKE OBSIDIAN KEY")
	_build_key_item(obsidian_key.get_node("Mesh"), obsidian_key.position.y, true)
	_add_safe_place(_safe_places, "TempleHide01", Vector3(78, 1.4, 168), "HIDE BEHIND ALTAR")
	_add_safe_place(_safe_places, "TempleHide02", Vector3(102, 1.4, 174), "HIDE BEHIND ALTAR")
	_light(room, "TempleLight01", Vector3(90, 6, 152), Color(1.0, 0.85, 0.55), 2.0, 24.0)
	_light(room, "TempleLight02", Vector3(90, 6, 172), Color(1.0, 0.85, 0.55), 1.8, 24.0)
	_light(room, "ExitBeacon", Vector3(90, 4, 177), Color(0.35, 1.0, 0.5), 2.4, 16.0)
	_add_tree(_forest_decor, "TempleTree1", Vector3(64, 0, 147), 2.2, 0)
	_add_tree(_forest_decor, "TempleTree2", Vector3(116, 0, 177), 1.9, 1)
	_add_bush(_forest_decor, "TempleBush1", Vector3(114, 0, 148), 1.2)
	_add_bush(_forest_decor, "TempleBush2", Vector3(66, 0, 176), 1.0)

func _build_corridor_e() -> void:
	var corridor := _node(_architecture, "CorridorE")
	_floor_rect(corridor, "Floor", 162, 162, 84, 12, _mats.path_alt)
	_grassify_floor(corridor, "GrassE", 162, 162, 84, 12)
	_wall_z(corridor, "WallNorth", 156, 120, 204, _mats.hedge)
	_wall_z(corridor, "WallSouth", 168, 120, 204, _mats.hedge)
	_wall_x(corridor, "WallEnd", 204, 156, 168, _mats.hedge)
	_drape_wall(corridor, "VineEN", Vector3(120, 8, 157.15), Vector3(204, 8, 157.15))
	_drape_wall(corridor, "VineES", Vector3(120, 8, 166.85), Vector3(204, 8, 166.85))
	_drape_wall(corridor, "VineEEnd", Vector3(202.85, 8, 156), Vector3(202.85, 8, 168))
	_light(corridor, "PathLight1", Vector3(140, 4.5, 162), Color(0.9, 0.95, 0.7), 1.4, 22.0)
	_light(corridor, "PathLight2", Vector3(180, 4.5, 162), Color(0.9, 0.95, 0.7), 1.4, 22.0)
	_add_tree(_forest_decor, "CorridorETree1", Vector3(150, 0, 152), 2.1, 0)

func _build_exit_gate() -> void:
	_add_gate(_gates, "ExitGate", Vector3(190, 3.5, 162))
	var door := load("res://material/godot_door.glb").instantiate() as Node3D
	door.name = "ExitDoorVisual"
	door.position = Vector3(193, 0, 162)
	door.scale = Vector3(5.5, 3.4, 3.4)
	_architecture.add_child(door)
	_add_tree(_forest_decor, "ExitTree1", Vector3(176, 0, 152), 2.2, 0)
	_add_tree(_forest_decor, "ExitTree2", Vector3(184, 0, 172), 2.0, 1)
	_add_bush(_forest_decor, "ExitBush", Vector3(170, 0, 156), 1.1)

func _build_gameplay() -> void:
	var start_spawn := Marker3D.new()
	start_spawn.name = "StartSpawn"
	start_spawn.position = Vector3(-105, 1.0, -105)
	_gameplay.add_child(start_spawn)
	_add_checkpoint("CheckpointGrotto", Vector3(-20, 1.0, -35), Vector3(8, 4, 8),
		"MOONWATER GROTTO", Vector3(-20, 1.0, -35), Vector3(-10, 1.0, -32))
	_add_checkpoint("CheckpointTemple", Vector3(90, 1.0, 148), Vector3(10, 4, 10),
		"BLACKROOT TEMPLE", Vector3(90, 1.0, 148), Vector3(90, 1.0, 152))
	var vine_spawn := Marker3D.new()
	vine_spawn.name = "StalkerSpawnVine"
	vine_spawn.position = Vector3(0, 1.0, -32)
	_gameplay.add_child(vine_spawn)
	var rune_spawn := Marker3D.new()
	rune_spawn.name = "StalkerSpawnRune"
	rune_spawn.position = Vector3(90, 1.0, 60)
	_gameplay.add_child(rune_spawn)
	var exit_area := Area3D.new()
	exit_area.name = "ExitArea"
	exit_area.position = Vector3(200, 2.0, 162)
	exit_area.collision_layer = 0
	exit_area.monitorable = false
	_gameplay.add_child(exit_area)
	_add_area_shape(exit_area, Vector3(8, 5, 4))
	var water_hazard := Area3D.new()
	water_hazard.name = "WaterHazard"
	water_hazard.position = Vector3(-40, -1.15, -35)
	water_hazard.collision_mask = 3
	_gameplay.add_child(water_hazard)
	_add_area_shape(water_hazard, Vector3(10, 2.2, 22))
	var pit_hazard := Area3D.new()
	pit_hazard.name = "PitHazard"
	pit_hazard.position = Vector3(90, -2.0, 170)
	pit_hazard.collision_mask = 3
	_gameplay.add_child(pit_hazard)
	_add_area_shape(pit_hazard, Vector3(9, 11, 9))

func _add_checkpoint(name: String, pos: Vector3, size: Vector3, stage: String,
		respawn: Vector3, monster_spawn: Vector3) -> void:
	var area := Area3D.new()
	area.name = name
	area.position = pos
	area.set_meta("stage_name", stage)
	_gameplay.add_child(area)
	_add_area_shape(area, size)
	var resp := Marker3D.new()
	resp.name = "Respawn"
	# respawn/monster_spawn are expressed in level-local coordinates. These
	# markers are children of the checkpoint, so convert them to checkpoint-
	# local coordinates instead of applying the checkpoint offset twice.
	resp.position = respawn - pos
	area.add_child(resp)
	var monster := Marker3D.new()
	monster.name = "MonsterSpawn"
	monster.position = monster_spawn - pos
	area.add_child(monster)

func _add_area_shape(area: Area3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
