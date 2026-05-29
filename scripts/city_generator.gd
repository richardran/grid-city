extends Node3D

const BarcelonaBlockGenerator = preload("res://scripts/barcelona_block_generator.gd")
const BuildingAPI = preload("res://scripts/building_api.gd")

const DISTRICT_CIVIC_CORE := "civic_core"
const DISTRICT_MARKET_SPINE := "market_spine"
const DISTRICT_CULTURAL_CROSS := "cultural_cross"
const DISTRICT_GARDEN_QUARTER := "garden_quarter"
const DISTRICT_HILLSIDE_QUARTER := "hillside_quarter"

@export var grid_size: Vector2i = Vector2i(8, 8)
@export var block_size: float = 18.0
@export var street_width: float = 6.0
@export var min_floors: int = 2
@export var max_floors: int = 4
@export var floor_height: float = 2.8
@export var seed_value: int = 0
@export var regenerate_on_ready: bool = true
@export var city_base_margin: float = 12.0

@export_group("Block Styles")
@export var use_barcelona_block_mix: bool = true
@export_range(0.0, 1.0, 0.05) var barcelona_block_chance: float = 0.35
@export var barcelona_block_min_floors: int = 3
@export var barcelona_block_max_floors: int = 6
@export var barcelona_block_gap_size: float = 0.6
@export var barcelona_block_corner_size: float = 5.2
@export var barcelona_block_bridge_depth: float = 3.2

@export_group("Terrain Heights")
@export var terrain_height: float = 11.5
@export var terrain_frequency: float = 0.0195

@export_group("Road Steps")
@export var road_surface_thickness: float = 0.22
@export var stair_trigger_height: float = 1.1
@export var stair_step_rise: float = 0.17
@export var global_height_quantum: float = 0.17
@export var stair_step_tread: float = 0.30
@export var stair_landing_length: float = 1.2
@export var road_step_run: float = 0.35

@export_group("Edge Planters")
@export var railing_height_threshold: float = 0.9
@export var railing_height: float = 1.0
@export var railing_thickness: float = 0.12
@export var planter_height: float = 0.55
@export var planter_thickness: float = 0.45
@export var vine_thickness: float = 0.18

@export_group("Cheap Night Lighting")
@export var enable_fake_street_lamps: bool = true
@export_range(0.1, 1.0, 0.05) var residential_window_fill_ratio: float = 0.62
@export_range(0.1, 1.0, 0.05) var mixed_use_window_fill_ratio: float = 0.86

const FLOWER_ASSET_PATHS: Array[String] = [
	"res://assets/foliage/kenney/flower_yellowA.glb",
	"res://assets/foliage/kenney/flower_redB.glb",
	"res://assets/foliage/kenney/flower_purpleC.glb"
]
const VENUE_DISPLAY_NAMES := {
	"coffee_shop": "Roastery",
	"bookstore": "Books & Paper",
	"bakery": "Bakery"
}

const VENUE_STYLE_PRESETS := {
	"coffee_shop": {
		"sign_color": Color(0.28, 0.18, 0.14),
		"stripe_color": Color(0.77, 0.61, 0.44),
		"stripe_alt": Color(0.93, 0.84, 0.71),
		"window_glow": Color(1.0, 0.82, 0.58),
		"lamp_glow": Color(1.0, 0.76, 0.54),
		"accent_color": Color(0.54, 0.34, 0.23),
		"planter_color": Color(0.32, 0.40, 0.24),
		"decor": "cafe"
	},
	"bookstore": {
		"sign_color": Color(0.16, 0.22, 0.30),
		"stripe_color": Color(0.73, 0.76, 0.82),
		"stripe_alt": Color(0.92, 0.92, 0.89),
		"window_glow": Color(0.88, 0.92, 1.0),
		"lamp_glow": Color(0.96, 0.88, 0.72),
		"accent_color": Color(0.30, 0.34, 0.43),
		"planter_color": Color(0.26, 0.35, 0.29),
		"decor": "books"
	},
	"bakery": {
		"sign_color": Color(0.43, 0.25, 0.17),
		"stripe_color": Color(0.86, 0.69, 0.52),
		"stripe_alt": Color(0.97, 0.88, 0.76),
		"window_glow": Color(1.0, 0.85, 0.70),
		"lamp_glow": Color(1.0, 0.80, 0.62),
		"accent_color": Color(0.55, 0.31, 0.20),
		"planter_color": Color(0.42, 0.36, 0.22),
		"decor": "bread"
	}
}
const PLANTER_BUSH_ASSET_PATH := "res://assets/foliage/kenney/plant_bushSmall.glb"
const CASCADE_PLANT_ASSET_PATH := "res://assets/foliage/kenney/grass_leafsLarge.glb"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _terrain_noise: FastNoiseLite
var _generated_root: Node3D
var _street_heights: Dictionary = {}
var _walk_areas: Array = []
var _walk_area_spatial_index: Dictionary = {}
var _walk_area_index_cell_size: float = 24.0
var _building_slots: Array = []
var _city_base_y: float = -12.0
var _main_avenue_x: int = 0
var _signature_cross_z: int = 0

var _road_material: StandardMaterial3D
var _stair_material: StandardMaterial3D
var _foundation_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _house_trim_material: StandardMaterial3D
var _roof_tile_material: StandardMaterial3D
var _house_body_materials: Array[StandardMaterial3D] = []
var _track_material: StandardMaterial3D
var _railing_material: StandardMaterial3D
var _planter_material: StandardMaterial3D
var _foliage_material: StandardMaterial3D
var _vine_material: StandardMaterial3D
var _lamp_post_material: StandardMaterial3D
var _flower_materials: Array[StandardMaterial3D] = []
var _bush_material: StandardMaterial3D
var _flower_scenes: Array[PackedScene] = []
var _planter_bush_scene: PackedScene
var _cascade_plant_scene: PackedScene
var _missing_optional_assets: Dictionary = {}
var _emissive_material_profiles: Array = []
var _lighting_state: Dictionary = {}

func _ready() -> void:
	_setup_materials()
	_setup_foliage_assets()
	if regenerate_on_ready:
		generate_city()

func generate_city() -> void:
	if _house_body_materials.is_empty():
		_setup_materials()
	if _flower_materials.is_empty():
		_setup_foliage_assets()
	_ensure_runtime_seed()
	_rng.seed = seed_value
	_main_avenue_x = _pick_city_axis_index(grid_size.x, seed_value * 17 + 5)
	_signature_cross_z = _pick_city_axis_index(grid_size.y, seed_value * 31 + 11)
	_setup_noise()
	_compute_street_heights()
	_compute_city_base_height()
	_walk_areas.clear()
	_walk_area_spatial_index.clear()
	_walk_area_index_cell_size = maxf(1.0, block_size + street_width)
	_building_slots.clear()
	_emissive_material_profiles.clear()

	if is_instance_valid(_generated_root):
		_generated_root.queue_free()

	_generated_root = Node3D.new()
	_generated_root.name = "GeneratedCity"
	add_child(_generated_root)

	_create_city_base()
	_create_roads()
	_create_blocks()
	_create_street_lamps()
	_create_cube_trees()
	apply_lighting_state(_default_lighting_state())


func _merge_meshes_by_material() -> void:
	## Groups all MeshInstance3D under _generated_root by material,
	## merges their vertex data into one ArrayMesh per material,
	## then replaces the individual instances with the merged mesh.
	if _generated_root == null or not is_instance_valid(_generated_root):
		return

	# Collect all MeshInstance3D grouped by material
	var by_material: Dictionary = {}  # Material -> Array[MeshInstance3D]
	var all_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(_generated_root, by_material, all_instances)

	if all_instances.is_empty():
		return

	var total_before: int = all_instances.size()
	var merged_count: int = 0

	for mat in by_material:
		var instances: Array = by_material[mat]
		if instances.size() < 3:
			# Don't bother merging if fewer than 3 instances — overhead not worth it
			continue

		var mat_ref: Material = mat as Material
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		var merged_any: bool = false
		for mi in instances:
			var mi_node: MeshInstance3D = mi as MeshInstance3D
			if mi_node == null or not is_instance_valid(mi_node):
				continue
			var mesh: Mesh = mi_node.mesh
			if mesh == null:
				continue
			# Get the global transform for vertex positioning
			var xform: Transform3D = mi_node.global_transform
			# Append mesh surfaces
			for surf_idx in mesh.get_surface_count():
				var arr: Array = mesh.surface_get_arrays(surf_idx)
				if arr.is_empty():
					continue
				# Apply transform to vertices
				var verts: Array = arr[Mesh.ARRAY_VERTEX]
				for vi in range(verts.size()):
					verts[vi] = xform * (verts[vi] as Vector3)
				st.append_from(mesh, surf_idx, xform)
				merged_any = true

		if not merged_any:
			continue

		# Generate merged mesh
		st.index()
		var merged_mesh: ArrayMesh = st.commit()
		if merged_mesh == null:
			continue

		# Create a single MeshInstance3D for this material
		var merged_node := MeshInstance3D.new()
		merged_node.mesh = merged_mesh
		merged_node.material_override = mat_ref
		merged_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_generated_root.add_child(merged_node)

		# Hide originals (keep them to maintain scene tree structure for other code)
		for mi in instances:
			var mi_node: MeshInstance3D = mi as MeshInstance3D
			if mi_node != null and is_instance_valid(mi_node):
				mi_node.visible = false

		merged_count += instances.size()

	var kept: int = total_before - merged_count
	print("Mesh merge: %d -> %d group meshes + %d unmerged = %d total (%.0f%% reduction)" % [
		total_before, by_material.size(), kept, by_material.size() + kept,
		100.0 * (1.0 - float(by_material.size() + kept) / float(maxi(1, total_before)))
	])


func _collect_mesh_instances(node: Node, by_material: Dictionary, all: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		all.append(mi)
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.mesh.surface_get_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
		if mat != null:
			if not by_material.has(mat):
				by_material[mat] = []
			by_material[mat].append(mi)
	for child in node.get_children():
		_collect_mesh_instances(child, by_material, all)


func _ensure_runtime_seed() -> void:
	if seed_value != 0:
		return
	var ticks: int = Time.get_ticks_usec()
	var unix_time: int = Time.get_unix_time_from_system()
	seed_value = int(abs((ticks ^ unix_time ^ int(get_instance_id())) % 2147483647))
	if seed_value == 0:
		seed_value = 1


func _pick_city_axis_index(span: int, salt: int) -> int:
	if span <= 2:
		return maxi(1, int(span / 2))
	var min_index: int = 1
	var max_index: int = span - 1
	if span >= 6:
		var edge_margin: int = maxi(1, int(floor(float(span) * 0.2)))
		min_index = mini(max_index, edge_margin)
		max_index = maxi(min_index, span - edge_margin)
	return min_index + _positive_modulo(salt, max_index - min_index + 1)

func _setup_noise() -> void:
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = seed_value
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = terrain_frequency
	_terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_terrain_noise.fractal_octaves = 3
	_terrain_noise.fractal_gain = 0.58
	_terrain_noise.fractal_lacunarity = 2.0

func _setup_materials() -> void:
	_road_material = StandardMaterial3D.new()
	_road_material.albedo_color = Color(0.80, 0.75, 0.68)
	_road_material.roughness = 1.0

	_stair_material = StandardMaterial3D.new()
	_stair_material.albedo_color = Color(0.74, 0.70, 0.64)
	_stair_material.roughness = 1.0

	_foundation_material = StandardMaterial3D.new()
	_foundation_material.albedo_color = Color(0.60, 0.60, 0.62)
	_foundation_material.roughness = 0.95

	_wall_material = StandardMaterial3D.new()
	_wall_material.albedo_color = Color(0.52, 0.50, 0.48)
	_wall_material.roughness = 0.94

	_house_trim_material = StandardMaterial3D.new()
	_house_trim_material.albedo_color = Color(0.93, 0.89, 0.82)
	_house_trim_material.roughness = 0.9

	# Roof tile material — warm terracotta (Minecraft style)
	_roof_tile_material = StandardMaterial3D.new()
	_roof_tile_material.albedo_color = Color(0.72, 0.38, 0.22)
	_roof_tile_material.roughness = 0.9

	_house_body_materials.clear()
	# Warm Minecraft-inspired palette: terracotta, ochre, brick, cream, slate blue, sage
	for color in [
		Color(0.77, 0.45, 0.35),  # terracotta
		Color(0.86, 0.65, 0.42),  # warm ochre
		Color(0.58, 0.68, 0.78),  # slate blue
		Color(0.90, 0.84, 0.72),  # cream/beige
		Color(0.65, 0.55, 0.72),  # mauve
		Color(0.62, 0.72, 0.58),  # sage green
	]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.84
		_house_body_materials.append(mat)

	_track_material = StandardMaterial3D.new()
	_track_material.albedo_color = Color(0.24, 0.20, 0.18)
	_track_material.metallic = 0.45
	_track_material.roughness = 0.55

	_railing_material = StandardMaterial3D.new()
	_railing_material.albedo_color = Color(0.56, 0.60, 0.64)
	_railing_material.metallic = 0.22
	_railing_material.roughness = 0.72

	_planter_material = StandardMaterial3D.new()
	_planter_material.albedo_color = Color(0.68, 0.50, 0.38)
	_planter_material.roughness = 0.9

	_foliage_material = StandardMaterial3D.new()
	_foliage_material.albedo_color = Color(0.44, 0.63, 0.34)
	_foliage_material.roughness = 0.95

	_vine_material = StandardMaterial3D.new()
	_vine_material.albedo_color = Color(0.31, 0.54, 0.28)
	_vine_material.roughness = 1.0

	_lamp_post_material = StandardMaterial3D.new()
	_lamp_post_material.albedo_color = Color(0.22, 0.23, 0.27)
	_lamp_post_material.metallic = 0.34
	_lamp_post_material.roughness = 0.44

func _setup_foliage_assets() -> void:
	# No GLB assets — use procedural cubes for all foliage
	_flower_scenes.clear()
	_planter_bush_scene = null
	_cascade_plant_scene = null
	_bush_material = null

	# Create shared flower materials (6 colors)
	if _flower_materials.is_empty():
		for flower_color in [Color(0.95, 0.75, 0.20), Color(0.85, 0.30, 0.25), Color(0.85, 0.35, 0.80), Color(0.90, 0.50, 0.30), Color(0.70, 0.40, 0.90), Color(0.95, 0.85, 0.40)]:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = flower_color
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_flower_materials.append(mat)

	# Bush material
	if _bush_material == null:
		_bush_material = StandardMaterial3D.new()
		_bush_material.albedo_color = Color(0.22, 0.45, 0.18)
		_bush_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _default_lighting_state() -> Dictionary:
	return {
		"daylight": 1.0,
		"night": 0.0,
		"blue_hour": 0.0,
		"warm_hour": 0.0,
		"window_strength": 0.06,
		"storefront_strength": 0.0,
		"lamp_strength": 0.0,
		"window_color_bias": Color(0.98, 0.84, 0.66)
	}


func apply_lighting_state(state: Dictionary) -> void:
	_lighting_state = state.duplicate(true)
	BuildingAPI.apply_lighting_state(_lighting_state)
	for profile in _emissive_material_profiles:
		var material := profile.get("material") as StandardMaterial3D
		if material == null:
			continue
		_apply_emissive_profile(material, profile, _lighting_state)


func get_lighting_debug_snapshot() -> Dictionary:
	var lamp_count: int = 0
	var storefront_count: int = 0
	var window_count: int = 0
	for profile in _emissive_material_profiles:
		match String(profile.get("category", "")):
			"lamp_bulb":
				lamp_count += 1
			"storefront_window":
				storefront_count += 1
			"house_window":
				window_count += 1
	return {
		"emissive_profiles": _emissive_material_profiles.size(),
		"house_windows": window_count,
		"storefront_windows": storefront_count,
		"street_lamps": lamp_count,
		"lighting_state": _lighting_state.duplicate(true)
	}


func _register_emissive_material(material: StandardMaterial3D, category: String, base_color: Color, seed: int, strength: float = 1.0, occupied: float = 1.0, cool_color: Color = Color(0.66, 0.80, 0.92)) -> StandardMaterial3D:
	var profile := {
		"material": material,
		"category": category,
		"base_color": base_color,
		"seed": seed,
		"strength": strength,
		"occupied": occupied,
		"cool_color": cool_color
	}
	_emissive_material_profiles.append(profile)
	_apply_emissive_profile(material, profile, _lighting_state if not _lighting_state.is_empty() else _default_lighting_state())
	return material


func _apply_emissive_profile(material: StandardMaterial3D, profile: Dictionary, state: Dictionary) -> void:
	var category: String = str(profile.get("category", "house_window"))
	var base_color: Color = Color(profile.get("base_color", Color(1.0, 0.84, 0.66)))
	var cool_color: Color = Color(profile.get("cool_color", Color(0.66, 0.80, 0.92)))
	var strength: float = float(profile.get("strength", 1.0))
	var occupied: float = float(profile.get("occupied", 1.0))
	var daylight: float = float(state.get("daylight", 1.0))
	var night: float = float(state.get("night", 0.0))
	var blue_hour: float = float(state.get("blue_hour", 0.0))
	var warm_hour: float = float(state.get("warm_hour", 0.0))
	var window_strength: float = float(state.get("window_strength", 0.05))
	var storefront_strength: float = float(state.get("storefront_strength", 0.0))
	var lamp_strength: float = float(state.get("lamp_strength", 0.0))
	match category:
		"storefront_window":
			var storefront_mix: float = clampf(storefront_strength * occupied, 0.0, 1.0)
			material.albedo_color = cool_color.lerp(base_color, 0.68 + warm_hour * 0.24)
			material.emission_enabled = true
			material.emission = cool_color.lerp(base_color, 0.58 + warm_hour * 0.32)
			material.emission_energy_multiplier = 0.08 + storefront_mix * (0.42 + strength * 0.96)
		"storefront_pool":
			var pool_mix: float = clampf(storefront_strength * strength, 0.0, 1.0)
			material.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.03 + pool_mix * 0.13)
			material.emission_enabled = true
			material.emission = base_color
			material.emission_energy_multiplier = pool_mix * 1.08
		"lamp_bulb":
			var bulb_mix: float = clampf(lamp_strength * (0.86 + occupied * 0.14), 0.0, 1.0)
			material.albedo_color = base_color.lerp(Color(1.0, 0.97, 0.88), 0.28)
			material.emission_enabled = true
			material.emission = base_color
			material.emission_energy_multiplier = 0.06 + bulb_mix * (1.1 + strength * 0.45)
		"lamp_pool":
			var lamp_pool_mix: float = clampf(lamp_strength * strength, 0.0, 1.0)
			material.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.02 + lamp_pool_mix * 0.12)
			material.emission_enabled = true
			material.emission = base_color
			material.emission_energy_multiplier = lamp_pool_mix * 0.92
		_:
			var window_mix: float = clampf((window_strength * occupied) + blue_hour * 0.08 * occupied, 0.0, 1.0)
			material.albedo_color = Color(0.60, 0.76, 0.90, 0.46).lerp(base_color, clampf(window_mix * 0.72, 0.0, 1.0))
			material.emission_enabled = true
			material.emission = cool_color.lerp(base_color, clampf(0.44 + warm_hour * 0.42 + night * 0.18, 0.0, 1.0))
			material.emission_energy_multiplier = lerpf(0.02, 0.12, daylight * 0.16 + blue_hour * 0.24) + window_mix * (0.22 + strength * 0.64)


func _make_window_glow_material(base_color: Color, category: String, seed: int, strength: float = 1.0, occupied: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic = 0.04
	material.roughness = 0.08
	return _register_emissive_material(material, category, base_color, seed, strength, occupied)


func _make_glow_pool_material(base_color: Color, category: String, seed: int, strength: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.roughness = 1.0
	return _register_emissive_material(material, category, base_color, seed, strength, 1.0)


func _window_fill_for_slot(is_mixed_use: bool, district: String, seed: int) -> float:
	var base_ratio: float = mixed_use_window_fill_ratio if is_mixed_use else residential_window_fill_ratio
	match district:
		DISTRICT_CIVIC_CORE:
			base_ratio += 0.08
		DISTRICT_MARKET_SPINE:
			base_ratio += 0.10
		DISTRICT_GARDEN_QUARTER:
			base_ratio -= 0.08
		DISTRICT_HILLSIDE_QUARTER:
			base_ratio -= 0.12
	var roll: float = float(_positive_modulo(seed * 37 + 19, 100)) / 100.0
	if roll > clampf(base_ratio, 0.08, 0.98):
		return 0.18 + float(_positive_modulo(seed * 17 + 5, 20)) / 100.0
	return 0.62 + float(_positive_modulo(seed * 13 + 7, 36)) / 100.0


func _window_glow_for_house(district: String, venue_type: String = "") -> Color:
	if venue_type != "":
		return Color(VENUE_STYLE_PRESETS.get(venue_type, {}).get("window_glow", Color(1.0, 0.84, 0.66)))
	match district:
		DISTRICT_CIVIC_CORE:
			return Color(0.98, 0.88, 0.72)
		DISTRICT_MARKET_SPINE:
			return Color(1.0, 0.82, 0.58)
		DISTRICT_CULTURAL_CROSS:
			return Color(0.92, 0.88, 1.0)
		DISTRICT_GARDEN_QUARTER:
			return Color(0.97, 0.86, 0.70)
		_:
			return Color(0.94, 0.82, 0.66)


func _load_optional_packed_scene(asset_path: String) -> PackedScene:
	if not _has_ready_import(asset_path):
		_warn_missing_optional_asset(asset_path)
		return null
	var resource: Resource = ResourceLoader.load(asset_path)
	if resource is PackedScene:
		return resource as PackedScene
	_warn_missing_optional_asset(asset_path)
	return null


func _warn_missing_optional_asset(asset_path: String) -> void:
	if _missing_optional_assets.has(asset_path):
		return
	_missing_optional_assets[asset_path] = true
	push_warning("Optional foliage asset unavailable, using procedural fallback: %s" % asset_path)


func _has_ready_import(asset_path: String) -> bool:
	var import_path := "%s.import" % asset_path
	if not FileAccess.file_exists(import_path):
		return false
	var remap := ConfigFile.new()
	if remap.load(import_path) != OK:
		return false
	var imported_path: String = str(remap.get_value("remap", "path", ""))
	return imported_path != "" and FileAccess.file_exists(imported_path)

func _compute_street_heights() -> void:
	_street_heights.clear()
	for ix in range(grid_size.x + 1):
		for iz in range(grid_size.y + 1):
			var x: float = _road_center_x(ix)
			var z: float = _road_center_z(iz)
			_street_heights[Vector2i(ix, iz)] = _terrain_height(x, z)

	for _pass in range(5):
		var next_heights: Dictionary = {}
		for ix in range(grid_size.x + 1):
			for iz in range(grid_size.y + 1):
				var key := Vector2i(ix, iz)
				var self_height: float = _street_heights[key]
				var total: float = self_height
				var count: float = 1.0
				for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var neighbor: Vector2i = key + offset
					if _street_heights.has(neighbor):
						total += _street_heights[neighbor]
						count += 1.0
				var avg: float = total / count
				var preserve: float = 0.55 if ix == _main_avenue_x or iz == _signature_cross_z else 0.35
				next_heights[key] = lerpf(avg, self_height, preserve)
		_street_heights = next_heights

	_quantize_street_heights()
	_limit_street_height_deltas()
	_quantize_street_heights()

func _quantize_street_heights() -> void:
	for key in _street_heights.keys():
		_street_heights[key] = _quantize_height(_street_heights[key])

func _quantize_height(value: float) -> float:
	var quantum: float = maxf(0.001, global_height_quantum)
	return round(value / quantum) * quantum

func _limit_street_height_deltas() -> void:
	var max_vertical_delta: float = _max_supported_delta(block_size)
	var max_horizontal_delta: float = _max_supported_delta(block_size)
	for _pass in range(8):
		for ix in range(grid_size.x + 1):
			for iz in range(grid_size.y + 1):
				var key := Vector2i(ix, iz)
				var base_h: float = _street_heights[key]
				for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var neighbor: Vector2i = key + offset
					if not _street_heights.has(neighbor):
						continue
					var max_delta: float = max_vertical_delta if offset == Vector2i.DOWN else max_horizontal_delta
					var other_h: float = _street_heights[neighbor]
					var diff: float = other_h - base_h
					if absf(diff) > max_delta:
						var target: float = base_h + sign(diff) * max_delta
						_street_heights[neighbor] = _quantize_height(target)

func _max_supported_delta(run_length: float) -> float:
	var max_steps: int = maxi(1, int(floor(run_length / maxf(0.001, stair_step_tread))))
	return float(max_steps) * stair_step_rise

func _compute_city_base_height() -> void:
	var min_height: float = INF
	for value in _street_heights.values():
		min_height = minf(min_height, value)
	_city_base_y = min_height - city_base_margin

func _create_city_base() -> void:
	var base := MeshInstance3D.new()
	base.name = "CityBase"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_total_width(), 2.0, _total_depth())
	base.mesh = mesh
	base.material_override = _wall_material
	base.position = Vector3(0.0, _city_base_y - 1.0, 0.0)
	_generated_root.add_child(base)

func _create_roads() -> void:
	for ix in range(grid_size.x + 1):
		for iz in range(grid_size.y + 1):
			_create_intersection(ix, iz)

	for ix in range(grid_size.x + 1):
		for gz in range(grid_size.y):
			_create_vertical_road(ix, gz, ix == _main_avenue_x)

	for gx in range(grid_size.x):
		for iz in range(grid_size.y + 1):
			_create_horizontal_road(gx, iz, iz == _signature_cross_z)


func _create_street_lamps() -> void:
	if not enable_fake_street_lamps:
		return
	var seen: Dictionary = {}
	var main_x_band: Vector2 = _road_band_x(_main_avenue_x)
	var signature_z_band: Vector2 = _road_band_z(_signature_cross_z)
	for gz in range(grid_size.y):
		if gz % 2 != 0:
			continue
		var z_band: Vector2 = _block_band_z(gz)
		var z: float = (z_band.x + z_band.y) * 0.5
		_register_street_lamp_site(Vector3(main_x_band.x + street_width * 0.22, 0.0, z), seen)
		_register_street_lamp_site(Vector3(main_x_band.y - street_width * 0.22, 0.0, z), seen)
	for gx in range(grid_size.x):
		if gx % 2 != 0:
			continue
		var x_band: Vector2 = _block_band_x(gx)
		var x: float = (x_band.x + x_band.y) * 0.5
		_register_street_lamp_site(Vector3(x, 0.0, signature_z_band.x + street_width * 0.22), seen)
		_register_street_lamp_site(Vector3(x, 0.0, signature_z_band.y - street_width * 0.22), seen)
	for slot in _building_slots:
		var kind: String = str(slot.get("kind", ""))
		if kind != "plaza" and kind != "civic_landmark":
			continue
		for raw_point in Array(slot.get("entry_points", [])):
			var point: Vector3 = Vector3(raw_point)
			var center: Vector3 = Vector3(slot.get("center", point))
			var direction := Vector2(point.x - center.x, point.z - center.z)
			if direction.length() < 0.05:
				direction = Vector2(0.0, -1.0)
			else:
				direction = direction.normalized()
			_register_street_lamp_site(Vector3(point.x + direction.x * 0.9, 0.0, point.z + direction.y * 0.9), seen)


func _register_street_lamp_site(position: Vector3, seen: Dictionary) -> void:
	var key: String = "%d|%d" % [int(round(position.x * 2.0)), int(round(position.z * 2.0))]
	if seen.has(key):
		return
	seen[key] = true
	_add_street_lamp(position)


func _add_street_lamp(position: Vector3) -> void:
	var snapped: Vector3 = get_nearest_walk_ground_point(position)
	var pole_height: float = 3.6
	var lamp_root := Node3D.new()
	lamp_root.name = "StreetLamp_%d_%d" % [int(round(position.x * 10.0)), int(round(position.z * 10.0))]
	lamp_root.position = Vector3(snapped.x, snapped.y, snapped.z)
	_generated_root.add_child(lamp_root)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = pole_height
	pole.mesh = pole_mesh
	pole.material_override = _lamp_post_material
	pole.position = Vector3(0.0, pole_height * 0.5, 0.0)
	lamp_root.add_child(pole)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.14, 0.10, 0.68)
	arm.mesh = arm_mesh
	arm.material_override = _lamp_post_material
	arm.position = Vector3(0.0, pole_height - 0.24, -0.28)
	lamp_root.add_child(arm)

	var bulb_color := Color(1.0, 0.88, 0.68)
	var bulb_seed: int = abs(seed_value * 79 + int(round(position.x * 11.0)) * 13 + int(round(position.z * 11.0)) * 17)
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.12
	bulb_mesh.height = 0.24
	bulb.mesh = bulb_mesh
	var bulb_material := _make_glow_pool_material(bulb_color, "lamp_bulb", bulb_seed, 1.0)
	bulb.material_override = bulb_material
	bulb.position = Vector3(0.0, pole_height - 0.34, -0.46)
	lamp_root.add_child(bulb)

	var pool := MeshInstance3D.new()
	var pool_mesh := CylinderMesh.new()
	pool_mesh.top_radius = 1.55
	pool_mesh.bottom_radius = 1.35
	pool_mesh.height = 0.03
	pool.mesh = pool_mesh
	pool.material_override = _make_glow_pool_material(Color(0.98, 0.84, 0.58), "lamp_pool", bulb_seed + 11, 1.0)
	pool.position = Vector3(0.0, 0.035, -0.34)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp_root.add_child(pool)


func _create_cube_trees() -> void:
	# Minecraft-style cube trees at plaza block corners
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.24, 0.16, 0.10)
	trunk_mat.roughness = 0.95
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.22, 0.52, 0.18)
	leaf_mat.roughness = 0.95
	var seen: Dictionary = {}
	for slot in _building_slots:
		var kind: String = str(slot.get("kind", ""))
		if kind != "plaza" and kind != "civic_landmark":
			continue
		var center: Vector3 = Vector3(slot.get("center", Vector3.ZERO))
		var top_y: float = float(slot.get("top_y", center.y))
		for offset in [Vector3(-2.0, 0.0, -2.0), Vector3(2.0, 0.0, -2.0)]:
			var pos: Vector3 = center + offset
			var snapped: Vector3 = get_nearest_walk_ground_point(Vector3(pos.x, top_y, pos.z))
			var key: String = "%d|%d" % [int(round(snapped.x * 2.0)), int(round(snapped.z * 2.0))]
			if seen.has(key): continue
			seen[key] = true
			_add_cube_tree(snapped, trunk_mat, leaf_mat)


func _add_cube_tree(pos: Vector3, trunk_mat: Material, leaf_mat: Material) -> void:
	var tree_root := Node3D.new()
	tree_root.name = "CubeTree_%d_%d" % [int(round(pos.x * 10.0)), int(round(pos.z * 10.0))]
	tree_root.position = pos
	_generated_root.add_child(tree_root)
	var trunk := MeshInstance3D.new()
	var trunk_msh := BoxMesh.new()
	trunk_msh.size = Vector3(0.16, 1.4, 0.16)
	trunk.mesh = trunk_msh
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0.0, 0.7, 0.0)
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree_root.add_child(trunk)
	for tier in range(3):
		var canopy := MeshInstance3D.new()
		var leaf_msh := BoxMesh.new()
		var sz: float = 1.6 - float(tier) * 0.3
		leaf_msh.size = Vector3(sz, 0.6, sz)
		canopy.mesh = leaf_msh
		canopy.material_override = leaf_mat
		canopy.position = Vector3(0.0, 1.8 + float(tier) * 0.5, 0.0)
		canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tree_root.add_child(canopy)

func _create_intersection(ix: int, iz: int) -> void:
	var x_band: Vector2 = _road_band_x(ix)
	var z_band: Vector2 = _road_band_z(iz)
	var top_y: float = _street_heights[Vector2i(ix, iz)] + road_surface_thickness
	_add_top_prism(x_band, z_band, top_y, _road_material)
	_register_walk_area(x_band, z_band, top_y)

func _create_vertical_road(ix: int, gz: int, is_main: bool) -> void:
	var x_band: Vector2 = _road_band_x(ix)
	var z_band: Vector2 = _block_band_z(gz)
	var start_h: float = _street_heights[Vector2i(ix, gz)]
	var end_h: float = _street_heights[Vector2i(ix, gz + 1)]
	_fill_road_strip(x_band, z_band, start_h, end_h, false, is_main)

func _create_horizontal_road(gx: int, iz: int, is_signature: bool) -> void:
	var x_band: Vector2 = _block_band_x(gx)
	var z_band: Vector2 = _road_band_z(iz)
	var start_h: float = _street_heights[Vector2i(gx, iz)]
	var end_h: float = _street_heights[Vector2i(gx + 1, iz)]
	_fill_road_strip(x_band, z_band, start_h, end_h, true, is_signature)

func _fill_road_strip(x_band: Vector2, z_band: Vector2, start_h: float, end_h: float, along_x: bool, add_tracks: bool) -> void:
	var run_length: float = (x_band.y - x_band.x) if along_x else (z_band.y - z_band.x)
	for section in _road_sections(start_h, end_h, run_length):
		_add_road_sub_band(x_band, z_band, section["from_run"], section["to_run"], along_x, section["top_y"], section["material"])
		if add_tracks and section["material"] == _road_material:
			if along_x:
				var xs := Vector2(lerpf(x_band.x, x_band.y, section["from_run"] / run_length), lerpf(x_band.x, x_band.y, section["to_run"] / run_length))
				_add_track_strip(xs, z_band, true)
			else:
				var zs := Vector2(lerpf(z_band.x, z_band.y, section["from_run"] / run_length), lerpf(z_band.x, z_band.y, section["to_run"] / run_length))
				_add_track_strip(x_band, zs, false)

func _road_sections(start_h: float, end_h: float, run_length: float) -> Array:
	var sections: Array = []
	var quantum: float = maxf(0.001, global_height_quantum)
	var start_step: int = int(round(start_h / quantum))
	var end_step: int = int(round(end_h / quantum))
	var step_diff: int = end_step - start_step

	if step_diff == 0:
		sections.append({
			"from_run": 0.0,
			"to_run": run_length,
			"top_y": start_h + road_surface_thickness,
			"material": _road_material
		})
		return sections

	var step_count: int = abs(step_diff)
	var required_step_run: float = float(step_count) * stair_step_tread
	var landing_each: float = maxf(0.0, minf(stair_landing_length, (run_length - required_step_run) * 0.5))
	var remaining_run: float = run_length - landing_each * 2.0
	if remaining_run < required_step_run - 0.001:
		landing_each = 0.0
		remaining_run = run_length
	if remaining_run < required_step_run - 0.001:
		var fitted_tread: float = run_length / float(step_count)
		for i in range(step_count):
			var from_run_fit: float = float(i) * fitted_tread
			var to_run_fit: float = float(i + 1) * fitted_tread
			var step_index_fit: int = start_step + int(sign(step_diff)) * (i + 1)
			sections.append({
				"from_run": from_run_fit,
				"to_run": to_run_fit,
				"top_y": float(step_index_fit) * quantum + road_surface_thickness,
				"material": _stair_material
			})
		return sections

	var cursor: float = 0.0
	if landing_each > 0.01:
		sections.append({
			"from_run": cursor,
			"to_run": cursor + landing_each,
			"top_y": start_h + road_surface_thickness,
			"material": _road_material
		})
		cursor += landing_each

	for i in range(step_count):
		var next_cursor: float = cursor + stair_step_tread
		var step_index: int = start_step + int(sign(step_diff)) * (i + 1)
		sections.append({
			"from_run": cursor,
			"to_run": next_cursor,
			"top_y": float(step_index) * quantum + road_surface_thickness,
			"material": _stair_material
		})
		cursor = next_cursor

	if cursor < run_length - 0.01:
		sections.append({
			"from_run": cursor,
			"to_run": run_length,
			"top_y": end_h + road_surface_thickness,
			"material": _road_material
		})
	return sections

func _add_road_sub_band(x_band: Vector2, z_band: Vector2, from_run: float, to_run: float, along_x: bool, top_y: float, material: Material) -> void:
	if to_run <= from_run:
		return
	var total_run: float = (x_band.y - x_band.x) if along_x else (z_band.y - z_band.x)
	var t0: float = from_run / total_run
	var t1: float = to_run / total_run
	if along_x:
		var xs := Vector2(lerpf(x_band.x, x_band.y, t0), lerpf(x_band.x, x_band.y, t1))
		_add_top_prism(xs, z_band, top_y, material)
		_register_walk_area(xs, z_band, top_y)
	else:
		var zs := Vector2(lerpf(z_band.x, z_band.y, t0), lerpf(z_band.x, z_band.y, t1))
		_add_top_prism(x_band, zs, top_y, material)
		_register_walk_area(x_band, zs, top_y)

func _add_track_strip(x_band: Vector2, z_band: Vector2, along_x: bool) -> void:
	var rail_offset: float = street_width * 0.18
	if along_x:
		var mid_z: float = (z_band.x + z_band.y) * 0.5
		var rail_a := Vector2(mid_z - rail_offset - 0.06, mid_z - rail_offset + 0.06)
		var rail_b := Vector2(mid_z + rail_offset - 0.06, mid_z + rail_offset + 0.06)
		_add_top_prism(x_band, rail_a, _city_base_y + 0.32, _track_material)
		_add_top_prism(x_band, rail_b, _city_base_y + 0.32, _track_material)
	else:
		var mid_x: float = (x_band.x + x_band.y) * 0.5
		var rail_x_a := Vector2(mid_x - rail_offset - 0.06, mid_x - rail_offset + 0.06)
		var rail_x_b := Vector2(mid_x + rail_offset - 0.06, mid_x + rail_offset + 0.06)
		_add_top_prism(rail_x_a, z_band, _city_base_y + 0.32, _track_material)
		_add_top_prism(rail_x_b, z_band, _city_base_y + 0.32, _track_material)

func _create_blocks() -> void:
	for gx in range(grid_size.x):
		for gz in range(grid_size.y):
			_create_block(gx, gz)

func _create_block(gx: int, gz: int) -> void:
	var x_band: Vector2 = _block_band_x(gx)
	var z_band: Vector2 = _block_band_z(gz)
	var block_top: float = _block_top_height(gx, gz)
	var district: String = _district_kind_for_block(gx, gz)
	_add_top_prism(x_band, z_band, block_top, _foundation_material)
	if _is_plaza_block(gx, gz, district):
		_create_civic_plaza(x_band, z_band, block_top, gx, gz, district, _is_landmark_block(gx, gz, district))
		return
	if _should_use_barcelona_block(gx, gz, district):
		_create_barcelona_block(x_band, z_band, block_top, gx, gz, district)
		return
	_add_block_railings(x_band, z_band, block_top, gx, gz)
	_create_block_houses(x_band, z_band, block_top, gx, gz, district)


func _district_kind_for_block(gx: int, gz: int) -> String:
	if gx == _main_avenue_x and gz == _signature_cross_z:
		return DISTRICT_CIVIC_CORE
	if abs(gx - _main_avenue_x) <= 1:
		return DISTRICT_MARKET_SPINE
	if abs(gz - _signature_cross_z) <= 1:
		return DISTRICT_CULTURAL_CROSS
	var x_ratio: float = float(gx) / maxf(1.0, float(maxi(1, grid_size.x - 1)))
	var z_ratio: float = float(gz) / maxf(1.0, float(maxi(1, grid_size.y - 1)))
	return DISTRICT_GARDEN_QUARTER if x_ratio + z_ratio < 0.95 else DISTRICT_HILLSIDE_QUARTER


func _is_plaza_block(gx: int, gz: int, district: String) -> bool:
	if district == DISTRICT_CIVIC_CORE:
		return true
	if district == DISTRICT_CULTURAL_CROSS and abs(gx - _main_avenue_x) >= 1:
		return _positive_modulo(gx * 19 + gz * 31 + seed_value * 7, 4) == 0
	return false


func _is_landmark_block(gx: int, gz: int, district: String) -> bool:
	return district == DISTRICT_CIVIC_CORE and gx == _main_avenue_x and gz == _signature_cross_z


func _create_civic_plaza(x_band: Vector2, z_band: Vector2, block_top: float, gx: int, gz: int, district: String, is_landmark: bool) -> void:
	var inset: float = minf(1.45, minf(x_band.y - x_band.x, z_band.y - z_band.x) * 0.16)
	var plaza_x := Vector2(x_band.x + inset, x_band.y - inset)
	var plaza_z := Vector2(z_band.x + inset, z_band.y - inset)
	var plaza_top: float = block_top + 0.08
	_add_prism_between(plaza_x, plaza_z, block_top, plaza_top, _road_material)
	var square_walk: Dictionary = _create_walkable_square_network(x_band, z_band, plaza_x, plaza_z, block_top, plaza_top)
	var center_x: Vector2 = square_walk.get("center_x", Vector2(lerpf(plaza_x.x, plaza_x.y, 0.40), lerpf(plaza_x.x, plaza_x.y, 0.60)))
	var center_z: Vector2 = square_walk.get("center_z", Vector2(lerpf(plaza_z.x, plaza_z.y, 0.40), lerpf(plaza_z.x, plaza_z.y, 0.60)))
	var entry_points: Array = square_walk.get("entry_points", [])
	var gathering_points: Array = square_walk.get("gathering_points", [])

	var strip_depth: float = 0.72
	_add_prism_between(Vector2(plaza_x.x, plaza_x.y), Vector2(plaza_z.x, plaza_z.x + strip_depth), plaza_top, plaza_top + 0.08, _house_trim_material)
	_add_prism_between(Vector2(plaza_x.x, plaza_x.y), Vector2(plaza_z.y - strip_depth, plaza_z.y), plaza_top, plaza_top + 0.08, _house_trim_material)
	_add_prism_between(Vector2(plaza_x.x, plaza_x.x + strip_depth), Vector2(plaza_z.x, plaza_z.y), plaza_top, plaza_top + 0.08, _house_trim_material)
	_add_prism_between(Vector2(plaza_x.y - strip_depth, plaza_x.y), Vector2(plaza_z.x, plaza_z.y), plaza_top, plaza_top + 0.08, _house_trim_material)

	var planter_length_x: float = maxf(1.4, (plaza_x.y - plaza_x.x) * 0.24)
	var planter_length_z: float = maxf(1.4, (plaza_z.y - plaza_z.x) * 0.24)
	_add_planter_segment(Vector3(plaza_x.x + planter_length_x * 0.5, plaza_top + planter_height * 0.5, plaza_z.x + planter_thickness * 0.55), Vector3(planter_length_x, planter_height, planter_thickness), Vector3(0.0, 0.0, -1.0), 0.8)
	_add_planter_segment(Vector3(plaza_x.y - planter_length_x * 0.5, plaza_top + planter_height * 0.5, plaza_z.x + planter_thickness * 0.55), Vector3(planter_length_x, planter_height, planter_thickness), Vector3(0.0, 0.0, -1.0), 0.8)
	_add_planter_segment(Vector3(plaza_x.x + planter_length_x * 0.5, plaza_top + planter_height * 0.5, plaza_z.y - planter_thickness * 0.55), Vector3(planter_length_x, planter_height, planter_thickness), Vector3(0.0, 0.0, 1.0), 0.8)
	_add_planter_segment(Vector3(plaza_x.y - planter_length_x * 0.5, plaza_top + planter_height * 0.5, plaza_z.y - planter_thickness * 0.55), Vector3(planter_length_x, planter_height, planter_thickness), Vector3(0.0, 0.0, 1.0), 0.8)
	_add_planter_segment(Vector3(plaza_x.x + planter_thickness * 0.55, plaza_top + planter_height * 0.5, plaza_z.x + planter_length_z * 0.5), Vector3(planter_thickness, planter_height, planter_length_z), Vector3(-1.0, 0.0, 0.0), 0.8)
	_add_planter_segment(Vector3(plaza_x.x + planter_thickness * 0.55, plaza_top + planter_height * 0.5, plaza_z.y - planter_length_z * 0.5), Vector3(planter_thickness, planter_height, planter_length_z), Vector3(-1.0, 0.0, 0.0), 0.8)
	_add_planter_segment(Vector3(plaza_x.y - planter_thickness * 0.55, plaza_top + planter_height * 0.5, plaza_z.x + planter_length_z * 0.5), Vector3(planter_thickness, planter_height, planter_length_z), Vector3(1.0, 0.0, 0.0), 0.8)
	_add_planter_segment(Vector3(plaza_x.y - planter_thickness * 0.55, plaza_top + planter_height * 0.5, plaza_z.y - planter_length_z * 0.5), Vector3(planter_thickness, planter_height, planter_length_z), Vector3(1.0, 0.0, 0.0), 0.8)

	_add_prism_between(center_x, center_z, plaza_top, plaza_top + 0.34, _house_trim_material)
	# Procedural bushes at plaza corners (cubes)
	for corner in [
		Vector3(lerpf(plaza_x.x, plaza_x.y, 0.30), plaza_top + 0.18, lerpf(plaza_z.x, plaza_z.y, 0.30)),
		Vector3(lerpf(plaza_x.x, plaza_x.y, 0.70), plaza_top + 0.18, lerpf(plaza_z.x, plaza_z.y, 0.30)),
		Vector3(lerpf(plaza_x.x, plaza_x.y, 0.30), plaza_top + 0.18, lerpf(plaza_z.x, plaza_z.y, 0.70)),
		Vector3(lerpf(plaza_x.x, plaza_x.y, 0.70), plaza_top + 0.18, lerpf(plaza_z.x, plaza_z.y, 0.70))
	]:
		_add_procedural_bush(corner, Vector3(0.52, 0.42, 0.52))
	# Procedural flowers (flat tiles)
	for bloom in [
		Vector3((plaza_x.x + plaza_x.y) * 0.5, plaza_top + 0.12, lerpf(plaza_z.x, plaza_z.y, 0.24)),
		Vector3((plaza_x.x + plaza_x.y) * 0.5, plaza_top + 0.12, lerpf(plaza_z.x, plaza_z.y, 0.76))
	]:
		var fi: int = _positive_modulo(int(absf(bloom.z) * 10.0), maxi(1, _flower_materials.size()))
		_add_procedural_flower(bloom, fi, 0.10)
	if is_landmark:
		var shaft_x := Vector2(lerpf(plaza_x.x, plaza_x.y, 0.455), lerpf(plaza_x.x, plaza_x.y, 0.545))
		var shaft_z := Vector2(lerpf(plaza_z.x, plaza_z.y, 0.455), lerpf(plaza_z.x, plaza_z.y, 0.545))
		var tower_top: float = plaza_top + 7.6
		_add_prism_between(shaft_x, shaft_z, plaza_top + 0.34, tower_top, _house_body_materials[1])
		_add_prism_between(Vector2(shaft_x.x - 0.24, shaft_x.y + 0.24), Vector2(shaft_z.x - 0.24, shaft_z.y + 0.24), tower_top, tower_top + 0.42, _house_trim_material)
		_register_building_slot({
			"id": "landmark_%d_%d" % [gx, gz],
			"kind": "civic_landmark",
			"district": district,
			"gx": gx,
			"gz": gz,
			"x_band": plaza_x,
			"z_band": plaza_z,
			"center": Vector3((plaza_x.x + plaza_x.y) * 0.5, plaza_top, (plaza_z.x + plaza_z.y) * 0.5),
			"entry": Vector3((plaza_x.x + plaza_x.y) * 0.5, plaza_top, plaza_z.x + 0.95),
			"entry_points": entry_points.duplicate(true),
			"gathering_points": gathering_points.duplicate(true),
			"top_y": plaza_top,
			"roof_y": tower_top + 0.42,
			"capacity": 18,
			"work_capacity": 12,
			"label": "Civic Landmark %d-%d" % [gx, gz]
		})
	else:
		_register_building_slot({
			"id": "plaza_%d_%d" % [gx, gz],
			"kind": "plaza",
			"district": district,
			"gx": gx,
			"gz": gz,
			"x_band": plaza_x,
			"z_band": plaza_z,
			"center": Vector3((plaza_x.x + plaza_x.y) * 0.5, plaza_top, (plaza_z.x + plaza_z.y) * 0.5),
			"entry": Vector3((plaza_x.x + plaza_x.y) * 0.5, plaza_top, plaza_z.x + 0.95),
			"entry_points": entry_points.duplicate(true),
			"gathering_points": gathering_points.duplicate(true),
			"top_y": plaza_top,
			"roof_y": plaza_top + 0.34,
			"capacity": 0,
			"work_capacity": 0,
			"label": "Plaza %d-%d" % [gx, gz]
		})


func _create_walkable_square_network(x_band: Vector2, z_band: Vector2, plaza_x: Vector2, plaza_z: Vector2, block_top: float, plaza_top: float) -> Dictionary:
	var center_x := Vector2(lerpf(plaza_x.x, plaza_x.y, 0.40), lerpf(plaza_x.x, plaza_x.y, 0.60))
	var center_z := Vector2(lerpf(plaza_z.x, plaza_z.y, 0.40), lerpf(plaza_z.x, plaza_z.y, 0.60))
	var promenade_bands := [
		{"x": _inset_band(plaza_x, 0.10), "z": _inset_band(Vector2(plaza_z.x, center_z.x), 0.10), "kind": "square"},
		{"x": _inset_band(plaza_x, 0.10), "z": _inset_band(Vector2(center_z.y, plaza_z.y), 0.10), "kind": "square"},
		{"x": _inset_band(Vector2(plaza_x.x, center_x.x), 0.10), "z": _inset_band(Vector2(center_z.x, center_z.y), 0.10), "kind": "square"},
		{"x": _inset_band(Vector2(center_x.y, plaza_x.y), 0.10), "z": _inset_band(Vector2(center_z.x, center_z.y), 0.10), "kind": "square"}
	]
	for band in promenade_bands:
		_register_walk_area(band["x"], band["z"], plaza_top, str(band.get("kind", "square")), 1.45)

	var entry_half_span: float = minf(1.8, maxf(1.15, street_width * 0.34))
	var north_entry_x := _inset_band(Vector2((plaza_x.x + plaza_x.y) * 0.5 - entry_half_span, (plaza_x.x + plaza_x.y) * 0.5 + entry_half_span), 0.04)
	var south_entry_x := north_entry_x
	var west_entry_z := _inset_band(Vector2((plaza_z.x + plaza_z.y) * 0.5 - entry_half_span, (plaza_z.x + plaza_z.y) * 0.5 + entry_half_span), 0.04)
	var east_entry_z := west_entry_z
	var north_entry_z := _inset_band(Vector2(z_band.x, plaza_z.x + 0.24), 0.04)
	var south_entry_z := _inset_band(Vector2(plaza_z.y - 0.24, z_band.y), 0.04)
	var west_entry_x := _inset_band(Vector2(x_band.x, plaza_x.x + 0.24), 0.04)
	var east_entry_x := _inset_band(Vector2(plaza_x.y - 0.24, x_band.y), 0.04)
	for apron in [
		{"x": north_entry_x, "z": north_entry_z},
		{"x": south_entry_x, "z": south_entry_z},
		{"x": west_entry_x, "z": west_entry_z},
		{"x": east_entry_x, "z": east_entry_z}
	]:
		_add_prism_between(apron["x"], apron["z"], block_top, plaza_top, _stair_material)
		_register_walk_area(apron["x"], apron["z"], plaza_top, "square_entry", 1.2)

	var entry_points: Array = [
		Vector3((north_entry_x.x + north_entry_x.y) * 0.5, plaza_top, plaza_z.x + 0.34),
		Vector3((south_entry_x.x + south_entry_x.y) * 0.5, plaza_top, plaza_z.y - 0.34),
		Vector3(plaza_x.x + 0.34, plaza_top, (west_entry_z.x + west_entry_z.y) * 0.5),
		Vector3(plaza_x.y - 0.34, plaza_top, (east_entry_z.x + east_entry_z.y) * 0.5)
	]
	var gathering_points: Array = [
		Vector3((plaza_x.x + center_x.x) * 0.5, plaza_top, (plaza_z.x + center_z.x) * 0.5),
		Vector3((center_x.y + plaza_x.y) * 0.5, plaza_top, (plaza_z.x + center_z.x) * 0.5),
		Vector3((plaza_x.x + center_x.x) * 0.5, plaza_top, (center_z.y + plaza_z.y) * 0.5),
		Vector3((center_x.y + plaza_x.y) * 0.5, plaza_top, (center_z.y + plaza_z.y) * 0.5)
	]
	return {
		"center_x": center_x,
		"center_z": center_z,
		"entry_points": entry_points,
		"gathering_points": gathering_points
	}


func _add_block_railings(x_band: Vector2, z_band: Vector2, block_top: float, gx: int, gz: int) -> void:
	for section in _edge_flat_road_sections("north", gx, gz):
		var drop_n: float = absf(block_top - float(section["top_y"]))
		if drop_n >= railing_height_threshold:
			var edge_x_n: Vector2 = _run_sub_band(x_band, float(section["from"]), float(section["to"]))
			edge_x_n = _inset_band(edge_x_n, 0.04)
			_add_planter_segment(Vector3((edge_x_n.x + edge_x_n.y) * 0.5, block_top + planter_height * 0.5, z_band.x + planter_thickness * 0.5), Vector3(maxf(0.18, edge_x_n.y - edge_x_n.x), planter_height, planter_thickness), Vector3(0.0, 0.0, -1.0), drop_n)
	for section in _edge_flat_road_sections("south", gx, gz):
		var drop_s: float = absf(block_top - float(section["top_y"]))
		if drop_s >= railing_height_threshold:
			var edge_x_s: Vector2 = _run_sub_band(x_band, float(section["from"]), float(section["to"]))
			edge_x_s = _inset_band(edge_x_s, 0.04)
			_add_planter_segment(Vector3((edge_x_s.x + edge_x_s.y) * 0.5, block_top + planter_height * 0.5, z_band.y - planter_thickness * 0.5), Vector3(maxf(0.18, edge_x_s.y - edge_x_s.x), planter_height, planter_thickness), Vector3(0.0, 0.0, 1.0), drop_s)
	for section in _edge_flat_road_sections("west", gx, gz):
		var drop_w: float = absf(block_top - float(section["top_y"]))
		if drop_w >= railing_height_threshold:
			var edge_z_w: Vector2 = _run_sub_band(z_band, float(section["from"]), float(section["to"]))
			edge_z_w = _inset_band(edge_z_w, 0.04)
			_add_planter_segment(Vector3(x_band.x + planter_thickness * 0.5, block_top + planter_height * 0.5, (edge_z_w.x + edge_z_w.y) * 0.5), Vector3(planter_thickness, planter_height, maxf(0.18, edge_z_w.y - edge_z_w.x)), Vector3(-1.0, 0.0, 0.0), drop_w)
	for section in _edge_flat_road_sections("east", gx, gz):
		var drop_e: float = absf(block_top - float(section["top_y"]))
		if drop_e >= railing_height_threshold:
			var edge_z_e: Vector2 = _run_sub_band(z_band, float(section["from"]), float(section["to"]))
			edge_z_e = _inset_band(edge_z_e, 0.04)
			_add_planter_segment(Vector3(x_band.y - planter_thickness * 0.5, block_top + planter_height * 0.5, (edge_z_e.x + edge_z_e.y) * 0.5), Vector3(planter_thickness, planter_height, maxf(0.18, edge_z_e.y - edge_z_e.x)), Vector3(1.0, 0.0, 0.0), drop_e)

func _add_planter_segment(center: Vector3, size: Vector3, outward: Vector3, drop: float) -> void:
	var planter := MeshInstance3D.new()
	var planter_mesh := BoxMesh.new()
	planter_mesh.size = size
	planter.mesh = planter_mesh
	planter.material_override = _planter_material
	planter.position = center
	_generated_root.add_child(planter)

	var soil := MeshInstance3D.new()
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(maxf(0.14, size.x * 0.9), 0.12, maxf(0.14, size.z * 0.9))
	soil.mesh = soil_mesh
	soil.material_override = _foliage_material
	soil.position = center + Vector3(0.0, size.y * 0.5 - 0.06, 0.0)
	_generated_root.add_child(soil)

	_add_planter_greenery(center, size, outward, drop)

func _add_planter_greenery(center: Vector3, size: Vector3, outward: Vector3, drop: float) -> void:
	var primary_length: float = size.x if size.x > size.z else size.z
	var along_x: bool = size.x > size.z

	# Procedural bush cubes in planter
	var bush_count: int = clampi(int(round(primary_length / 1.8)), 2, 5)
	for i in range(bush_count):
		var bush_t: float = 0.5 if bush_count == 1 else float(i) / float(bush_count - 1)
		var bush_pos := center + Vector3(0.0, size.y * 0.5 + 0.02, 0.0)
		if along_x:
			bush_pos.x = lerpf(center.x - size.x * 0.30, center.x + size.x * 0.30, bush_t)
			bush_pos.z += _rng.randf_range(-0.04, 0.04)
		else:
			bush_pos.z = lerpf(center.z - size.z * 0.30, center.z + size.z * 0.30, bush_t)
			bush_pos.x += _rng.randf_range(-0.04, 0.04)
		var bush_scale := Vector3(
			_rng.randf_range(0.42, 0.62),
			_rng.randf_range(0.32, 0.50),
			_rng.randf_range(0.42, 0.62)
		)
		_add_procedural_bush(bush_pos, bush_scale)

	# Procedural flower tiles in planter
	var flower_count: int = clampi(int(round(primary_length / 1.5)), 2, 6)
	for i in range(flower_count):
		var t: float = 0.5 if flower_count == 1 else float(i) / float(flower_count - 1)
		var pos := center + Vector3(0.0, size.y * 0.5 + 0.05, 0.0)
		if along_x:
			pos.x = lerpf(center.x - size.x * 0.34, center.x + size.x * 0.34, t)
			pos.z += _rng.randf_range(-0.06, 0.06)
		else:
			pos.z = lerpf(center.z - size.z * 0.34, center.z + size.z * 0.34, t)
			pos.x += _rng.randf_range(-0.06, 0.06)
		_add_procedural_flower(pos, (i + int(absf(center.x + center.z))) % maxi(1, _flower_materials.size()), 0.10)

	# Cascading vines — still procedural mesh
	var cascade_count: int = clampi(int(round(primary_length / 2.8)), 1, 3)
	for i in range(cascade_count):
		var t2: float = 0.5 if cascade_count == 1 else float(i) / float(cascade_count - 1)
		var lip := center + outward * (size.x * 0.5 if not along_x else size.z * 0.5)
		if along_x:
			lip.x = lerpf(center.x - size.x * 0.26, center.x + size.x * 0.26, t2)
		else:
			lip.z = lerpf(center.z - size.z * 0.26, center.z + size.z * 0.26, t2)
		lip.y = center.y + size.y * 0.5 - minf(0.05, size.y * 0.2)
		var spill_scale := Vector3(0.34, clampf(drop * 0.34, 0.48, 1.05), 0.34)
		_add_procedural_bush(lip, spill_scale)
		var vine_height: float = maxf(0.28, drop - 0.28)
		var vine_depth: float = vine_thickness * 0.7
		var vine_size := Vector3(maxf(0.12, size.x * 0.20), vine_height, vine_depth) if along_x else Vector3(vine_depth, vine_height, maxf(0.12, size.z * 0.20))
		var vine_center := lip + outward * (vine_depth * 0.5) + Vector3(0.0, -vine_height * 0.5, 0.0)
		var vine := MeshInstance3D.new()
		var vine_mesh := BoxMesh.new()
		vine_mesh.size = vine_size
		vine.mesh = vine_mesh
		vine.material_override = _vine_material
		vine.position = vine_center
		_generated_root.add_child(vine)

func _add_scene_instance(scene: PackedScene, position: Vector3, scale_value: Vector3, rotation_value: Vector3 = Vector3.ZERO) -> void:
	if scene == null:
		return
	var instance := scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	var node := instance as Node3D
	node.position = position
	node.scale = scale_value
	node.rotation = rotation_value
	_generated_root.add_child(node)

func _run_sub_band(band: Vector2, from_run: float, to_run: float) -> Vector2:
	var total_run: float = maxf(0.001, band.y - band.x)
	return Vector2(
		lerpf(band.x, band.y, clampf(from_run / total_run, 0.0, 1.0)),
		lerpf(band.x, band.y, clampf(to_run / total_run, 0.0, 1.0))
	)

func _inset_band(band: Vector2, amount: float) -> Vector2:
	var max_inset: float = maxf(0.0, (band.y - band.x) * 0.5 - 0.09)
	var inset: float = minf(amount, max_inset)
	return Vector2(band.x + inset, band.y - inset)

func _create_barcelona_block(x_band: Vector2, z_band: Vector2, block_top: float, gx: int, gz: int, district: String) -> void:
	var request: Dictionary = _make_barcelona_block_request(x_band, z_band, block_top, gx, gz, district)
	var node: Node3D = BarcelonaBlockGenerator.build_block_from_request(request)
	_generated_root.add_child(node)
	_register_building_slot({
		"id": "barcelona_%d_%d" % [gx, gz],
		"kind": "mixed_use",
		"district": district,
		"gx": gx,
		"gz": gz,
		"x_band": x_band,
		"z_band": z_band,
		"center": Vector3((x_band.x + x_band.y) * 0.5, block_top, (z_band.x + z_band.y) * 0.5),
		"entry": Vector3((x_band.x + x_band.y) * 0.5, block_top, z_band.x + 0.9),
		"top_y": block_top,
		"roof_y": block_top + float(request.get("floor_count", 4)) * floor_height + 0.8,
		"capacity": maxi(8, request.get("floor_count", 4) * 4),
		"work_capacity": maxi(6, request.get("floor_count", 4) * 3),
		"label": "Barcelona Block %d-%d" % [gx, gz]
	})


func _make_barcelona_block_request(x_band: Vector2, z_band: Vector2, block_top: float, gx: int, gz: int, district: String = "") -> Dictionary:
	var block_center := Vector3((x_band.x + x_band.y) * 0.5, block_top, (z_band.x + z_band.y) * 0.5)
	var block_width: float = x_band.y - x_band.x
	var block_depth: float = z_band.y - z_band.x
	var min_side: float = minf(block_width, block_depth)
	var block_rng := RandomNumberGenerator.new()
	block_rng.seed = int(abs(seed_value * 13007 + gx * 92821 + gz * 68917 + 97))
	var effective_district: String = district if district != "" else _district_kind_for_block(gx, gz)
	var floor_min: int = barcelona_block_min_floors
	var floor_max: int = barcelona_block_max_floors
	match effective_district:
		DISTRICT_CIVIC_CORE:
			floor_min += 2
			floor_max += 2
		DISTRICT_MARKET_SPINE:
			floor_min += 1
			floor_max += 1
		DISTRICT_GARDEN_QUARTER:
			floor_min = maxi(2, floor_min - 1)
			floor_max = maxi(floor_min, floor_max - 1)
		DISTRICT_HILLSIDE_QUARTER:
			floor_max = maxi(floor_min, floor_max - 1)
	var floor_count: int = block_rng.randi_range(floor_min, floor_max)
	floor_count = clampi(floor_count, 2, 4)
	var gap_size: float = 0.0 if block_rng.randf() < 0.6 else minf(barcelona_block_gap_size, min_side * 0.1)
	return {
		"module_id": 100,
		"module_ids": _select_barcelona_module_ids(block_rng),
		"block_width": block_width,
		"block_depth": block_depth,
		"corner_size": minf(barcelona_block_corner_size, min_side * 0.45),
		"bridge_depth": minf(barcelona_block_bridge_depth, min_side * 0.28),
		"gap_size": gap_size,
		"floor_count": floor_count,
		"roof_type": "flat",
		"passage_side": _select_barcelona_passage_side(gx, gz, block_top),
		"position": block_center,
		"name": "BarcelonaBlock_%d_%d" % [gx, gz]
	}


func _select_barcelona_module_ids(block_rng: RandomNumberGenerator) -> Array:
	var pool: Array = [100, 101, 102, 103]
	for i in range(pool.size() - 1, 0, -1):
		var j: int = block_rng.randi_range(0, i)
		var swap_value: int = int(pool[i])
		pool[i] = pool[j]
		pool[j] = swap_value
	var palette_size: int = block_rng.randi_range(2, 4)
	var result: Array = []
	for i in range(palette_size):
		result.append(pool[i])
	if not result.has(100):
		result[0] = 100
	return result


func _select_barcelona_passage_side(gx: int, gz: int, block_top: float) -> String:
	var ranked_sides: Array[Dictionary] = []
	var ordered_sides := ["north", "east", "south", "west"]
	for side in ordered_sides:
		var edge_sections: Array = _edge_sections(side, gx, gz)
		var flat_sections: Array = _edge_flat_road_sections(side, gx, gz)
		var flat_drop: float = INF
		var any_drop: float = INF
		var flat_run: float = 0.0
		for section in edge_sections:
			any_drop = minf(any_drop, absf(block_top - float(section["top_y"])))
		for section in flat_sections:
			flat_drop = minf(flat_drop, absf(block_top - float(section["top_y"])))
			flat_run = maxf(flat_run, float(section["to"]) - float(section["from"]))
		ranked_sides.append({
			"side": side,
			"has_level_flat": flat_drop <= 0.06,
			"has_flat": not flat_sections.is_empty(),
			"score_drop": flat_drop if not flat_sections.is_empty() else any_drop,
			"flat_run": flat_run,
			"order": ranked_sides.size()
		})
	ranked_sides.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["has_level_flat"]) != bool(b["has_level_flat"]):
			return bool(a["has_level_flat"])
		if bool(a["has_flat"]) != bool(b["has_flat"]):
			return bool(a["has_flat"])
		if not is_equal_approx(float(a["score_drop"]), float(b["score_drop"])):
			return float(a["score_drop"]) < float(b["score_drop"])
		if not is_equal_approx(float(a["flat_run"]), float(b["flat_run"])):
			return float(a["flat_run"]) > float(b["flat_run"])
		return int(a["order"]) < int(b["order"])
	)
	return str(ranked_sides[0]["side"])


func _should_use_barcelona_block(gx: int, gz: int, district: String = "") -> bool:
	if not use_barcelona_block_mix:
		return false
	if block_size < 14.0:
		return false
	var effective_district: String = district if district != "" else _district_kind_for_block(gx, gz)
	var chance: float = barcelona_block_chance
	match effective_district:
		DISTRICT_CIVIC_CORE:
			chance = maxf(chance, 0.82)
		DISTRICT_MARKET_SPINE:
			chance = minf(1.0, chance + 0.24)
		DISTRICT_CULTURAL_CROSS:
			chance = minf(1.0, chance + 0.10)
		DISTRICT_GARDEN_QUARTER:
			chance *= 0.22
		DISTRICT_HILLSIDE_QUARTER:
			chance *= 0.45
	var roll_seed: int = int(abs(gx * 92821 + gz * 68917 + seed_value * 13))
	var chooser := RandomNumberGenerator.new()
	chooser.seed = roll_seed
	return chooser.randf() < chance


func _create_block_houses(x_band: Vector2, z_band: Vector2, block_top: float, gx: int, gz: int, district: String) -> void:
	var margin: float = 1.0
	var foundation_inset_x := Vector2(x_band.x + margin, x_band.y - margin)
	var foundation_inset_z := Vector2(z_band.x + margin, z_band.y - margin)
	var inner_width: float = foundation_inset_x.y - foundation_inset_x.x
	var inner_depth: float = foundation_inset_z.y - foundation_inset_z.x
	if inner_width <= 2.0 or inner_depth <= 2.0:
		return

	var along_x: bool = ((gx + gz) % 2) == 0
	var lane_gap: float = 3.6
	if along_x:
		var house_depth: float = (inner_depth - lane_gap) * 0.5
		if house_depth <= 1.8:
			return
		var houses_per_row: int = maxi(3, int(floor(inner_width / 4.2)))
		var cell_w: float = inner_width / float(houses_per_row)
		for row in range(2):
			var z_center: float = foundation_inset_z.x + house_depth * 0.5 if row == 0 else foundation_inset_z.y - house_depth * 0.5
			for i in range(houses_per_row):
				var x0: float = foundation_inset_x.x + float(i) * cell_w + 0.14
				var x1: float = foundation_inset_x.x + float(i + 1) * cell_w - 0.14
				_create_house_mass(Vector2(x0, x1), Vector2(z_center - house_depth * 0.5 + 0.12, z_center + house_depth * 0.5 - 0.12), block_top, gx, gz, i, district)
	else:
		var house_width: float = (inner_width - lane_gap) * 0.5
		if house_width <= 1.8:
			return
		var houses_per_col: int = maxi(3, int(floor(inner_depth / 4.2)))
		var cell_d: float = inner_depth / float(houses_per_col)
		for col in range(2):
			var x_center: float = foundation_inset_x.x + house_width * 0.5 if col == 0 else foundation_inset_x.y - house_width * 0.5
			for i in range(houses_per_col):
				var z0: float = foundation_inset_z.x + float(i) * cell_d + 0.14
				var z1: float = foundation_inset_z.x + float(i + 1) * cell_d - 0.14
				_create_house_mass(Vector2(x_center - house_width * 0.5 + 0.12, x_center + house_width * 0.5 - 0.12), Vector2(z0, z1), block_top, gx, gz, i, district)

func _create_house_mass(x_band: Vector2, z_band: Vector2, block_top: float, gx: int, gz: int, index: int, district: String) -> void:
	var floors: int = _rng.randi_range(min_floors, max_floors)
	if index % 4 == 0:
		floors += 1
	match district:
		DISTRICT_CIVIC_CORE:
			floors += 2
		DISTRICT_MARKET_SPINE:
			floors += 1
		DISTRICT_CULTURAL_CROSS:
			if index % 3 == 0:
				floors += 1
		DISTRICT_GARDEN_QUARTER:
			floors = maxi(min_floors, floors - 1)
		DISTRICT_HILLSIDE_QUARTER:
			if index % 3 != 0:
				floors = maxi(min_floors, floors - 1)
	# Cap at max 4 stories so buildings don't tower over the street
	floors = clampi(floors, 1, 4)
	var body_height: float = float(floors) * floor_height
	var basement_height: float = 1.4
	var top_y: float = block_top + basement_height + body_height
	var material_index: int = abs(gx * 7 + gz * 11 + index)
	match district:
		DISTRICT_CIVIC_CORE:
			material_index += 1
		DISTRICT_MARKET_SPINE:
			material_index += 4
		DISTRICT_CULTURAL_CROSS:
			material_index += 3
		DISTRICT_GARDEN_QUARTER:
			material_index += 2
		DISTRICT_HILLSIDE_QUARTER:
			material_index += 0
	material_index %= _house_body_materials.size()

	_add_prism_between(x_band, z_band, block_top, block_top + basement_height, _wall_material)
	_add_prism_between(x_band, z_band, block_top + basement_height, top_y, _house_body_materials[material_index])
	# Roof — terracotta slab (Minecraft style), thicker than old trim
	var roof_thickness: float = 0.28
	var roof_overhang: float = 0.10
	_add_prism_between(Vector2(x_band.x - roof_overhang, x_band.y + roof_overhang), Vector2(z_band.x - roof_overhang, z_band.y + roof_overhang), top_y, top_y + roof_thickness, _roof_tile_material)
	# Chimney on 1 in 4 buildings
	if index % 4 == 1 and floors >= 2:
		var chimney_x: float = lerpf(x_band.x, x_band.y, 0.72 if index % 2 == 0 else 0.28)
		var chimney_z: float = z_band.y - 0.30
		var chimney := MeshInstance3D.new()
		var chimney_mesh := BoxMesh.new()
		chimney_mesh.size = Vector3(0.22, 0.5 + 0.08 * floors, 0.22)
		chimney.mesh = chimney_mesh
		chimney.material_override = _wall_material
		chimney.position = Vector3(chimney_x, top_y + roof_thickness + 0.25 + 0.04 * floors, chimney_z)
		_generated_root.add_child(chimney)

	var front_x: Vector2 = Vector2(lerpf(x_band.x, x_band.y, 0.38), lerpf(x_band.x, x_band.y, 0.62))
	var front_z: Vector2 = Vector2(z_band.x - 0.08, z_band.x + 0.04)
	_add_prism_between(front_x, front_z, block_top + 0.05, block_top + minf(1.95, basement_height * 0.85), _house_trim_material)

	var bay_x: Vector2 = Vector2(lerpf(x_band.x, x_band.y, 0.28), lerpf(x_band.x, x_band.y, 0.72))
	var bay_z: Vector2 = Vector2(z_band.x - 0.22, z_band.x + 0.42)
	if district == DISTRICT_MARKET_SPINE or district == DISTRICT_CULTURAL_CROSS:
		var awning_y: float = block_top + minf(1.55, basement_height * 0.88)
		_add_prism_between(Vector2(lerpf(x_band.x, x_band.y, 0.18), lerpf(x_band.x, x_band.y, 0.82)), Vector2(z_band.x - 0.42, z_band.x + 0.16), awning_y, awning_y + 0.16, _house_body_materials[(material_index + 1) % _house_body_materials.size()])
	if district == DISTRICT_GARDEN_QUARTER or district == DISTRICT_CULTURAL_CROSS:
		_add_flower_box_row(x_band, z_band, block_top + basement_height + 0.42)

	var center := Vector3((x_band.x + x_band.y) * 0.5, block_top, (z_band.x + z_band.y) * 0.5)
	var entry := Vector3((front_x.x + front_x.y) * 0.5, block_top, front_z.x)
	var slot_kind: String = "residence"
	var work_capacity: int = 1 if floors >= 4 and index % 3 == 0 else 0
	var venue_type: String = ""
	if district == DISTRICT_MARKET_SPINE or district == DISTRICT_CULTURAL_CROSS:
		slot_kind = "mixed_use"
		work_capacity = maxi(work_capacity, 2 + int(floors / 2))
		venue_type = _venue_type_for_house(district, gx, gz, index)
		if venue_type != "":
			_add_storefront_signage(x_band, z_band, block_top, venue_type, material_index)
	var building_seed: int = abs(seed_value * 101 + gx * 31 + gz * 47 + index * 13)
	var window_fill: float = _window_fill_for_slot(slot_kind == "mixed_use", district, building_seed)
	var bay_material := _make_window_glow_material(_window_glow_for_house(district, venue_type), "house_window", building_seed, 0.74 + float(floors) * 0.05, window_fill)
	_add_prism_between(bay_x, bay_z, block_top + basement_height + 0.55, minf(top_y - 0.3, block_top + basement_height + 4.8), bay_material)
	_register_building_slot({
		"id": "house_%d_%d_%d" % [gx, gz, index],
		"kind": slot_kind,
		"district": district,
		"venue_type": venue_type,
		"gx": gx,
		"gz": gz,
		"x_band": x_band,
		"z_band": z_band,
		"center": center,
		"entry": entry,
		"top_y": block_top,
		"roof_y": top_y + 0.28,
		"floors": floors,
		"capacity": maxi(2, floors + 1),
		"work_capacity": work_capacity,
		"label": "House %d-%d-%d" % [gx, gz, index]
	})


func _venue_type_for_house(district: String, gx: int, gz: int, index: int) -> String:
	var roll: int = _positive_modulo(gx * 31 + gz * 17 + index * 13 + seed_value * 5, 6)
	if district == DISTRICT_MARKET_SPINE:
		if roll <= 2:
			return "coffee_shop"
		if roll <= 4:
			return "bookstore"
		return "bakery"
	if district == DISTRICT_CULTURAL_CROSS:
		return "bookstore" if roll % 2 == 0 else "coffee_shop"
	return ""


func _add_storefront_signage(x_band: Vector2, z_band: Vector2, block_top: float, venue_type: String, material_index: int) -> void:
	if venue_type == "":
		return
	var style: Dictionary = VENUE_STYLE_PRESETS.get(venue_type, {})
	var width: float = maxf(1.7, (x_band.y - x_band.x) * 0.56)
	var sign_center := Vector3((x_band.x + x_band.y) * 0.5, block_top + 2.0, z_band.x - 0.18)
	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = Color(style.get("sign_color", _house_body_materials[(material_index + 2) % _house_body_materials.size()].albedo_color))
	sign_material.roughness = 0.58
	var sign := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(width, 0.56, 0.12)
	sign.mesh = sign_mesh
	sign.material_override = sign_material
	sign.position = sign_center
	_generated_root.add_child(sign)

	var awning_material := StandardMaterial3D.new()
	awning_material.albedo_color = Color(style.get("stripe_color", Color(0.84, 0.80, 0.72)))
	awning_material.roughness = 0.84
	var awning_center := Vector3((x_band.x + x_band.y) * 0.5, block_top + 1.52, z_band.x - 0.24)
	var awning := MeshInstance3D.new()
	var awning_mesh := BoxMesh.new()
	awning_mesh.size = Vector3(width * 0.92, 0.14, 0.74)
	awning.mesh = awning_mesh
	awning.material_override = awning_material
	awning.position = awning_center
	_generated_root.add_child(awning)

	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = Color(style.get("stripe_alt", Color(0.96, 0.93, 0.86)))
	stripe_material.roughness = 0.78
	for stripe_index in range(3):
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(width * 0.92, 0.035, 0.12)
		stripe.mesh = stripe_mesh
		stripe.material_override = stripe_material
		stripe.position = awning_center + Vector3(0.0, 0.045 - stripe_index * 0.045, -0.18 + stripe_index * 0.18)
		_generated_root.add_child(stripe)

	var glow_color: Color = Color(style.get("window_glow", Color(0.98, 0.90, 0.78)))
	var glow_seed: int = abs(seed_value * 59 + int(round(x_band.x * 10.0)) * 7 + int(round(z_band.x * 10.0)) * 13 + material_index * 17)
	var glow_material := _make_window_glow_material(glow_color, "storefront_window", glow_seed, 1.1, 1.0)
	glow_material.roughness = 0.18
	var display := MeshInstance3D.new()
	var display_mesh := BoxMesh.new()
	display_mesh.size = Vector3(width * 0.82, 1.05, 0.08)
	display.mesh = display_mesh
	display.material_override = glow_material
	display.position = Vector3((x_band.x + x_band.y) * 0.5, block_top + 1.0, z_band.x - 0.03)
	_generated_root.add_child(display)
	_add_storefront_light_pool(x_band, z_band, block_top, glow_color, glow_seed)
	_add_storefront_mood_lighting(x_band, z_band, block_top, venue_type, glow_seed)

	_add_storefront_decor(x_band, z_band, block_top, venue_type)

	var label := Label3D.new()
	label.text = String(VENUE_DISPLAY_NAMES.get(venue_type, venue_type.capitalize()))
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.pixel_size = 0.0060
	label.modulate = Color(0.98, 0.96, 0.91, 0.98)
	label.outline_modulate = Color(0.05, 0.05, 0.07, 0.92)
	label.position = sign_center + Vector3(0.0, -0.09, -0.08)
	_generated_root.add_child(label)

func _add_storefront_decor(x_band: Vector2, z_band: Vector2, block_top: float, venue_type: String) -> void:
	var decor: String = str(VENUE_STYLE_PRESETS.get(venue_type, {}).get("decor", ""))
	match decor:
		"cafe":
			_add_cafe_storefront_decor(x_band, z_band, block_top)
		"books":
			_add_bookstore_storefront_decor(x_band, z_band, block_top)
		"bread":
			_add_bakery_storefront_decor(x_band, z_band, block_top)


func _add_storefront_light_pool(x_band: Vector2, z_band: Vector2, block_top: float, glow_color: Color, seed: int) -> void:
	var pool := MeshInstance3D.new()
	var pool_mesh := BoxMesh.new()
	pool_mesh.size = Vector3(maxf(1.4, (x_band.y - x_band.x) * 0.72), 0.02, 1.45)
	pool.mesh = pool_mesh
	pool.material_override = _make_glow_pool_material(glow_color, "storefront_pool", seed, 1.0)
	pool.position = Vector3((x_band.x + x_band.y) * 0.5, block_top + 0.03, z_band.x - 0.30)
	_generated_root.add_child(pool)


func _add_storefront_mood_lighting(x_band: Vector2, z_band: Vector2, block_top: float, venue_type: String, seed: int) -> void:
	var style: Dictionary = VENUE_STYLE_PRESETS.get(venue_type, {})
	var lamp_color: Color = Color(style.get("lamp_glow", style.get("window_glow", Color(1.0, 0.84, 0.70))))
	var width: float = maxf(1.4, (x_band.y - x_band.x) * 0.68)
	for lamp_index in range(2):
		var offset_x: float = -width * 0.24 if lamp_index == 0 else width * 0.24
		var pendant := MeshInstance3D.new()
		var pendant_mesh := SphereMesh.new()
		pendant_mesh.radius = 0.09
		pendant_mesh.height = 0.18
		pendant.mesh = pendant_mesh
		pendant.material_override = _make_glow_pool_material(lamp_color, "lamp_bulb", seed + lamp_index * 17, 0.82)
		pendant.position = Vector3((x_band.x + x_band.y) * 0.5 + offset_x, block_top + 1.86, z_band.x + 0.06)
		_generated_root.add_child(pendant)
		var cord := MeshInstance3D.new()
		var cord_mesh := CylinderMesh.new()
		cord_mesh.top_radius = 0.01
		cord_mesh.bottom_radius = 0.01
		cord_mesh.height = 0.52
		cord.mesh = cord_mesh
		cord.material_override = _track_material
		cord.position = pendant.position + Vector3(0.0, 0.24, 0.0)
		_generated_root.add_child(cord)
	var bench := MeshInstance3D.new()
	var bench_mesh := BoxMesh.new()
	bench_mesh.size = Vector3(width * 0.58, 0.12, 0.28)
	bench.mesh = bench_mesh
	bench.material_override = _planter_material
	bench.position = Vector3((x_band.x + x_band.y) * 0.5, block_top + 0.46, z_band.x - 0.54)
	_generated_root.add_child(bench)
	_add_storefront_planters(x_band, z_band, block_top, venue_type)


func _add_storefront_planters(x_band: Vector2, z_band: Vector2, block_top: float, venue_type: String) -> void:
	var style: Dictionary = VENUE_STYLE_PRESETS.get(venue_type, {})
	var planter_color: Color = Color(style.get("planter_color", Color(0.36, 0.40, 0.28)))
	for offset in [-0.54, 0.54]:
		var planter_material := StandardMaterial3D.new()
		planter_material.albedo_color = planter_color
		planter_material.roughness = 0.88
		var planter := MeshInstance3D.new()
		var planter_mesh := BoxMesh.new()
		planter_mesh.size = Vector3(0.26, 0.26, 0.26)
		planter.mesh = planter_mesh
		planter.material_override = planter_material
		planter.position = Vector3((x_band.x + x_band.y) * 0.5 + offset, block_top + 0.18, z_band.x - 0.42)
		_generated_root.add_child(planter)
		var shrub := MeshInstance3D.new()
		var shrub_mesh := SphereMesh.new()
		shrub_mesh.radius = 0.17
		shrub_mesh.height = 0.34
		shrub.mesh = shrub_mesh
		shrub.material_override = _foliage_material
		shrub.position = planter.position + Vector3(0.0, 0.24, 0.0)
		_generated_root.add_child(shrub)


func _add_cafe_storefront_decor(x_band: Vector2, z_band: Vector2, block_top: float) -> void:
	for offset in [-0.32, 0.32]:
		var table_top := MeshInstance3D.new()
		var table_mesh := CylinderMesh.new()
		table_mesh.top_radius = 0.14
		table_mesh.bottom_radius = 0.14
		table_mesh.height = 0.07
		table_top.mesh = table_mesh
		table_top.material_override = _house_trim_material
		table_top.position = Vector3((x_band.x + x_band.y) * 0.5 + offset, block_top + 0.78, z_band.x - 0.42)
		_generated_root.add_child(table_top)
		var table_base := MeshInstance3D.new()
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.03
		base_mesh.bottom_radius = 0.04
		base_mesh.height = 0.58
		table_base.mesh = base_mesh
		table_base.material_override = _track_material
		table_base.position = Vector3((x_band.x + x_band.y) * 0.5 + offset, block_top + 0.46, z_band.x - 0.42)
		_generated_root.add_child(table_base)
		for chair_offset in [-0.16, 0.16]:
			var chair := MeshInstance3D.new()
			var chair_mesh := BoxMesh.new()
			chair_mesh.size = Vector3(0.12, 0.34, 0.12)
			chair.mesh = chair_mesh
			chair.material_override = _house_trim_material
			chair.position = Vector3((x_band.x + x_band.y) * 0.5 + offset + chair_offset, block_top + 0.33, z_band.x - 0.70)
			_generated_root.add_child(chair)
	var steam_strip := MeshInstance3D.new()
	var steam_mesh := BoxMesh.new()
	steam_mesh.size = Vector3(maxf(0.9, (x_band.y - x_band.x) * 0.44), 0.04, 0.24)
	steam_strip.mesh = steam_mesh
	steam_strip.material_override = _make_glow_pool_material(Color(1.0, 0.74, 0.50), "storefront_pool", int(abs(x_band.x * 19.0 + z_band.x * 13.0 + seed_value * 23)), 0.66)
	steam_strip.position = Vector3((x_band.x + x_band.y) * 0.5, block_top + 1.16, z_band.x + 0.10)
	_generated_root.add_child(steam_strip)

func _add_bookstore_storefront_decor(x_band: Vector2, z_band: Vector2, block_top: float) -> void:
	for offset in [-0.42, 0.42]:
		var shelf := MeshInstance3D.new()
		var shelf_mesh := BoxMesh.new()
		shelf_mesh.size = Vector3(0.24, 1.18, 0.18)
		shelf.mesh = shelf_mesh
		shelf.material_override = _planter_material
		shelf.position = Vector3((x_band.x + x_band.y) * 0.5 + offset, block_top + 0.62, z_band.x + 0.08)
		_generated_root.add_child(shelf)
		for row in range(4):
			var book := MeshInstance3D.new()
			var book_mesh := BoxMesh.new()
			book_mesh.size = Vector3(0.18, 0.16, 0.12)
			book.mesh = book_mesh
			book.material_override = _house_body_materials[(row + int(offset > 0.0)) % _house_body_materials.size()]
			book.position = shelf.position + Vector3(0.0, -0.36 + row * 0.24, 0.0)
			_generated_root.add_child(book)
	var crate := MeshInstance3D.new()
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(0.56, 0.22, 0.30)
	crate.mesh = crate_mesh
	crate.material_override = _planter_material
	crate.position = Vector3((x_band.x + x_band.y) * 0.5, block_top + 0.16, z_band.x - 0.14)
	_generated_root.add_child(crate)
	for stack_index in range(3):
		var stack := MeshInstance3D.new()
		var stack_mesh := BoxMesh.new()
		stack_mesh.size = Vector3(0.14, 0.05, 0.18)
		stack.mesh = stack_mesh
		stack.material_override = _house_body_materials[(stack_index + 1) % _house_body_materials.size()]
		stack.position = crate.position + Vector3(-0.16 + stack_index * 0.16, 0.15 + stack_index * 0.03, 0.0)
		_generated_root.add_child(stack)

func _add_bakery_storefront_decor(x_band: Vector2, z_band: Vector2, block_top: float) -> void:
	for offset in [-0.30, 0.30]:
		var basket := MeshInstance3D.new()
		var basket_mesh := BoxMesh.new()
		basket_mesh.size = Vector3(0.24, 0.12, 0.18)
		basket.mesh = basket_mesh
		basket.material_override = _planter_material
		basket.position = Vector3((x_band.x + x_band.y) * 0.5 + offset, block_top + 0.82, z_band.x - 0.10)
		_generated_root.add_child(basket)
		var loaf_material := StandardMaterial3D.new()
		loaf_material.albedo_color = Color(0.90, 0.68, 0.34)
		loaf_material.roughness = 0.76
		for loaf_index in range(2):
			var loaf := MeshInstance3D.new()
			var loaf_mesh := SphereMesh.new()
			loaf_mesh.radius = 0.08
			loaf_mesh.height = 0.12
			loaf.mesh = loaf_mesh
			loaf.material_override = loaf_material
			loaf.position = basket.position + Vector3(-0.05 + loaf_index * 0.10, 0.09, 0.0)
			_generated_root.add_child(loaf)
	var warm_strip := MeshInstance3D.new()
	var warm_strip_mesh := BoxMesh.new()
	warm_strip_mesh.size = Vector3(maxf(0.9, (x_band.y - x_band.x) * 0.52), 0.03, 0.16)
	warm_strip.mesh = warm_strip_mesh
	warm_strip.material_override = _make_glow_pool_material(Color(1.0, 0.78, 0.56), "storefront_pool", int(abs(x_band.y * 17.0 + z_band.y * 11.0 + seed_value * 29)), 0.58)
	warm_strip.position = Vector3((x_band.x + x_band.y) * 0.5, block_top + 1.02, z_band.x + 0.08)
	_generated_root.add_child(warm_strip)


func _add_flower_box_row(x_band: Vector2, z_band: Vector2, height_y: float) -> void:
	var box_x := Vector2(lerpf(x_band.x, x_band.y, 0.24), lerpf(x_band.x, x_band.y, 0.76))
	var box_z := Vector2(z_band.x - 0.14, z_band.x + 0.12)
	_add_prism_between(box_x, box_z, height_y, height_y + 0.16, _planter_material)
	var flower_count: int = clampi(int(round((box_x.y - box_x.x) / 1.2)), 2, 4)
	for i in range(flower_count):
		var t: float = 0.5 if flower_count == 1 else float(i) / float(flower_count - 1)
		var pos := Vector3(lerpf(box_x.x, box_x.y, t), height_y + 0.12, z_band.x + 0.02)
		_add_procedural_flower(pos, (i + int(absf(pos.x) + absf(pos.z))) % maxi(1, _flower_materials.size()), 0.08)


## Procedural flower — flat colored tile (cube) instead of GLB mesh
func _add_procedural_flower(position: Vector3, color_index: int, size: float = 0.12) -> void:
	var mat: Material = _flower_materials[color_index % _flower_materials.size()]
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size * 0.9, 0.04, size * 0.9)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = position
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated_root.add_child(mi)


## Procedural bush — green cube instead of GLB mesh
func _add_procedural_bush(position: Vector3, scale: Vector3 = Vector3.ONE) -> void:
	if _bush_material == null:
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.3)
	mi.mesh = mesh
	mi.material_override = _bush_material
	mi.position = position
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated_root.add_child(mi)


func _add_top_prism(x_band: Vector2, z_band: Vector2, top_y: float, material: Material) -> void:
	_add_prism_between(x_band, z_band, _city_base_y, top_y, material)

func _add_prism_between(x_band: Vector2, z_band: Vector2, bottom_y: float, top_y: float, material: Material) -> void:
	if top_y <= bottom_y:
		return
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(x_band.y - x_band.x, top_y - bottom_y, z_band.y - z_band.x)
	part.mesh = mesh
	part.material_override = material
	part.position = Vector3((x_band.x + x_band.y) * 0.5, (bottom_y + top_y) * 0.5, (z_band.x + z_band.y) * 0.5)
	_generated_root.add_child(part)

func _block_top_height(gx: int, gz: int) -> float:
	var a: float = _street_heights[Vector2i(gx, gz)]
	var b: float = _street_heights[Vector2i(gx + 1, gz)]
	var c: float = _street_heights[Vector2i(gx, gz + 1)]
	var d: float = _street_heights[Vector2i(gx + 1, gz + 1)]
	var base_average: float = (a + b + c + d) * 0.25 + road_surface_thickness
	var candidate_heights: Array = _surrounding_flat_road_heights(gx, gz)
	if candidate_heights.is_empty():
		return base_average

	var best_height: float = INF
	for height in candidate_heights:
		if height >= base_average and height < best_height:
			best_height = height

	return base_average if best_height == INF else best_height

func _surrounding_flat_road_heights(gx: int, gz: int) -> Array:
	var heights: Array = []
	for side in ["north", "south", "west", "east"]:
		for section in _edge_flat_road_sections(side, gx, gz):
			heights.append(section["top_y"])
	return heights

func _edge_sections(side: String, gx: int, gz: int) -> Array:
	var sections: Array = []
	match side:
		"north":
			sections = _road_sections(_street_heights[Vector2i(gx, gz)], _street_heights[Vector2i(gx + 1, gz)], block_size)
		"south":
			sections = _road_sections(_street_heights[Vector2i(gx, gz + 1)], _street_heights[Vector2i(gx + 1, gz + 1)], block_size)
		"west":
			sections = _road_sections(_street_heights[Vector2i(gx, gz)], _street_heights[Vector2i(gx, gz + 1)], block_size)
		"east":
			sections = _road_sections(_street_heights[Vector2i(gx + 1, gz)], _street_heights[Vector2i(gx + 1, gz + 1)], block_size)
	var sections_out: Array = []
	for section in sections:
		sections_out.append({
			"from": section["from_run"],
			"to": section["to_run"],
			"top_y": section["top_y"],
			"is_flat": section["material"] == _road_material
		})
	return sections_out

func _edge_flat_road_sections(side: String, gx: int, gz: int) -> Array:
	var sections_out: Array = []
	for section in _edge_sections(side, gx, gz):
		if bool(section["is_flat"]):
			sections_out.append({
				"from": section["from"],
				"to": section["to"],
				"top_y": section["top_y"]
			})
	return sections_out

func _register_walk_area(x_band: Vector2, z_band: Vector2, top_y: float, kind: String = "road", weight: float = 1.0) -> void:
	var area_size: float = maxf(0.01, (x_band.y - x_band.x) * (z_band.y - z_band.x))
	var area_index: int = _walk_areas.size()
	_walk_areas.append({
		"x": x_band,
		"z": z_band,
		"y": top_y,
		"kind": kind,
		"weight": maxf(0.01, weight),
		"area": area_size
	})
	_index_walk_area(area_index, x_band, z_band)

func get_spawn_point() -> Vector3:
	var start_node := Vector2i(_main_avenue_x, maxi(1, int(grid_size.y * 0.28)))
	var point := _node_position(start_node.x, start_node.y)
	return Vector3(point.x, point.y + road_surface_thickness + 1.65, point.z)

func get_random_walk_point(margin: float = 0.45, preferred_kind: String = "") -> Vector3:
	if _walk_areas.is_empty():
		var spawn := get_spawn_point()
		return Vector3(spawn.x, spawn.y - 1.65, spawn.z)
	var candidates: Array = []
	for area in _walk_areas:
		if preferred_kind == "" or String(area.get("kind", "")) == preferred_kind:
			candidates.append(area)
	if candidates.is_empty():
		candidates = _walk_areas
	var total_weight: float = 0.0
	for candidate in candidates:
		total_weight += float(candidate.get("weight", 1.0)) * float(candidate.get("area", 1.0))
	var pick_weight: float = _rng.randf() * maxf(0.001, total_weight)
	var area: Dictionary = candidates[0]
	for candidate in candidates:
		pick_weight -= float(candidate.get("weight", 1.0)) * float(candidate.get("area", 1.0))
		area = candidate
		if pick_weight <= 0.0:
			break
	var x0: float = float(area["x"].x)
	var x1: float = float(area["x"].y)
	var z0: float = float(area["z"].x)
	var z1: float = float(area["z"].y)
	var safe_margin_x: float = minf(margin, maxf(0.0, (x1 - x0) * 0.5 - 0.08))
	var safe_margin_z: float = minf(margin, maxf(0.0, (z1 - z0) * 0.5 - 0.08))
	var px: float = _rng.randf_range(x0 + safe_margin_x, x1 - safe_margin_x) if x1 - x0 > safe_margin_x * 2.0 else (x0 + x1) * 0.5
	var pz: float = _rng.randf_range(z0 + safe_margin_z, z1 - safe_margin_z) if z1 - z0 > safe_margin_z * 2.0 else (z0 + z1) * 0.5
	return Vector3(px, float(area["y"]), pz)

func get_walk_areas_snapshot() -> Array:
	return _walk_areas.duplicate(true)

func get_building_slots_snapshot() -> Array:
	return _building_slots.duplicate(true)


func get_building_slot_snapshot(building_id: Variant) -> Dictionary:
	for slot in _building_slots:
		if str(slot.get("id", "")) == str(building_id):
			return Dictionary(slot).duplicate(true)
	return {}

func get_block_centers_snapshot() -> Array:
	var blocks: Array = []
	for gx in range(grid_size.x):
		for gz in range(grid_size.y):
			var x_band: Vector2 = _block_band_x(gx)
			var z_band: Vector2 = _block_band_z(gz)
			blocks.append({
				"gx": gx,
				"gz": gz,
				"district": _district_kind_for_block(gx, gz),
				"is_plaza": _is_plaza_block(gx, gz, _district_kind_for_block(gx, gz)),
				"is_landmark": _is_landmark_block(gx, gz, _district_kind_for_block(gx, gz)),
				"center": Vector3((x_band.x + x_band.y) * 0.5, _block_top_height(gx, gz), (z_band.x + z_band.y) * 0.5),
				"top_y": _block_top_height(gx, gz)
			})
	return blocks


func _positive_modulo(value: int, count: int) -> int:
	if count <= 0:
		return 0
	var mod: int = value % count
	return mod + count if mod < 0 else mod

func get_walk_height(world_position: Vector3) -> float:
	var snap := _closest_walk_snap(world_position)
	return snap.height if snap.valid else _city_base_y + 1.65

func get_walk_ground_height(world_position: Vector3) -> float:
	var snap := _closest_walk_snap(world_position)
	return snap.ground_height if snap.valid else _city_base_y


func get_nearest_walk_ground_point(world_position: Vector3) -> Vector3:
	if _walk_areas.is_empty():
		return Vector3(world_position.x, _city_base_y, world_position.z)
	var best_dist: float = INF
	var best_point := Vector3(world_position.x, _city_base_y, world_position.z)
	for area in _walk_area_candidates(world_position, street_width * 0.8):
		var clamped_x: float = clampf(world_position.x, area["x"].x, area["x"].y)
		var clamped_z: float = clampf(world_position.z, area["z"].x, area["z"].y)
		var candidate := Vector3(clamped_x, float(area["y"]), clamped_z)
		var dx: float = candidate.x - world_position.x
		var dz: float = candidate.z - world_position.z
		var distance_sq: float = dx * dx + dz * dz
		if distance_sq < best_dist:
			best_dist = distance_sq
			best_point = candidate
	return best_point

func try_move_on_walk(current_position: Vector3, desired_position: Vector3) -> Vector3:
	var snap := _closest_walk_snap(desired_position)
	if snap.valid:
		return Vector3(snap.position.x, snap.height, snap.position.z)
	var fallback := _closest_walk_snap(current_position)
	if fallback.valid:
		return Vector3(fallback.position.x, fallback.height, fallback.position.z)
	return current_position

func try_move_on_walk_ground(current_position: Vector3, desired_position: Vector3) -> Vector3:
	var snap := _closest_walk_snap(desired_position)
	if snap.valid:
		return Vector3(snap.position.x, snap.ground_height, snap.position.z)
	var fallback := _closest_walk_snap(current_position)
	if fallback.valid:
		return Vector3(fallback.position.x, fallback.ground_height, fallback.position.z)
	return current_position

func _closest_walk_snap(world_position: Vector3) -> Dictionary:
	var best_dist: float = INF
	var best_point: Vector3 = world_position
	var best_ground_height: float = _city_base_y
	var best_height: float = _city_base_y + 1.65
	var best_valid: bool = false
	var max_snap: float = street_width * 0.55

	for area in _walk_area_candidates(world_position, max_snap):
		var clamped_x: float = clampf(world_position.x, area["x"].x, area["x"].y)
		var clamped_z: float = clampf(world_position.z, area["z"].x, area["z"].y)
		var dx: float = world_position.x - clamped_x
		var dz: float = world_position.z - clamped_z
		var dist_sq: float = dx * dx + dz * dz
		if dist_sq <= max_snap * max_snap and dist_sq < best_dist:
			best_dist = dist_sq
			best_point = Vector3(clamped_x, 0.0, clamped_z)
			best_ground_height = float(area["y"])
			best_height = best_ground_height + 1.65
			best_valid = true

	return {"valid": best_valid, "position": best_point, "ground_height": best_ground_height, "height": best_height}


func _index_walk_area(area_index: int, x_band: Vector2, z_band: Vector2) -> void:
	var min_cell := _walk_area_cell_for_point(Vector3(x_band.x, 0.0, z_band.x))
	var max_cell := _walk_area_cell_for_point(Vector3(x_band.y, 0.0, z_band.y))
	for cx in range(min_cell.x, max_cell.x + 1):
		for cz in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(cx, cz)
			var bucket: Array = _walk_area_spatial_index.get(key, [])
			bucket.append(area_index)
			_walk_area_spatial_index[key] = bucket


func _walk_area_candidates(world_position: Vector3, search_radius: float) -> Array:
	if _walk_area_spatial_index.is_empty():
		return _walk_areas
	var min_cell := _walk_area_cell_for_point(world_position - Vector3(search_radius, 0.0, search_radius))
	var max_cell := _walk_area_cell_for_point(world_position + Vector3(search_radius, 0.0, search_radius))
	var seen: Dictionary = {}
	var candidates: Array = []
	for cx in range(min_cell.x, max_cell.x + 1):
		for cz in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(cx, cz)
			for area_index in _walk_area_spatial_index.get(key, []):
				var resolved_index: int = int(area_index)
				if seen.has(resolved_index) or resolved_index < 0 or resolved_index >= _walk_areas.size():
					continue
				seen[resolved_index] = true
				candidates.append(_walk_areas[resolved_index])
	return candidates if not candidates.is_empty() else _walk_areas


func _walk_area_cell_for_point(world_position: Vector3) -> Vector2i:
	var cell_size: float = maxf(1.0, _walk_area_index_cell_size)
	return Vector2i(int(floor(world_position.x / cell_size)), int(floor(world_position.z / cell_size)))

func _register_building_slot(slot: Dictionary) -> void:
	_building_slots.append(slot)


func _terrain_height(x: float, z: float) -> float:
	var total_width: float = _total_width()
	var total_depth: float = _total_depth()
	var nx: float = x / maxf(total_width * 0.5, 0.001)
	var nz: float = z / maxf(total_depth * 0.5, 0.001)
	var slope: float = (nx * 1.12 + nz * 0.22) * terrain_height * 0.60
	var ridge_a: float = sin((x * 0.92 + z * 0.20) * terrain_frequency * 5.8) * terrain_height * 0.46
	var ridge_b: float = sin((x * 0.25 - z * 1.04) * terrain_frequency * 4.5 + 1.15) * terrain_height * 0.24
	var ridge_c: float = sin((x + z * 0.36) * terrain_frequency * 2.9 - 0.55) * terrain_height * 0.10
	var noise_component: float = _terrain_noise.get_noise_2d(x, z) * terrain_height * 0.18
	var hill_a: float = exp(-pow(nx - 0.34, 2.0) * 8.0 - pow(nz + 0.02, 2.0) * 14.0) * terrain_height * 1.42
	var hill_b: float = exp(-pow(nx + 0.13, 2.0) * 12.0 - pow(nz - 0.32, 2.0) * 10.0) * terrain_height * 1.14
	var hill_c: float = exp(-pow(nx - 0.05, 2.0) * 15.0 - pow(nz + 0.38, 2.0) * 11.0) * terrain_height * 1.00
	var hill_d: float = exp(-pow(nx + 0.28, 2.0) * 9.0 - pow(nz - 0.02, 2.0) * 18.0) * terrain_height * 0.48
	var saddle: float = exp(-pow(nx + 0.38, 2.0) * 11.0 - pow(nz + 0.22, 2.0) * 11.0) * terrain_height * 0.50
	return slope + ridge_a + ridge_b + ridge_c + hill_a + hill_b + hill_c + hill_d - saddle + noise_component

func _node_position(ix: int, iz: int) -> Vector3:
	return Vector3(_road_center_x(ix), _street_heights[Vector2i(ix, iz)], _road_center_z(iz))

func _road_band_x(index: int) -> Vector2:
	var left: float = -_total_width() * 0.5 + float(index) * (block_size + street_width)
	return Vector2(left, left + street_width)

func _road_band_z(index: int) -> Vector2:
	var top: float = -_total_depth() * 0.5 + float(index) * (block_size + street_width)
	return Vector2(top, top + street_width)

func _block_band_x(index: int) -> Vector2:
	var road: Vector2 = _road_band_x(index)
	return Vector2(road.y, road.y + block_size)

func _block_band_z(index: int) -> Vector2:
	var road: Vector2 = _road_band_z(index)
	return Vector2(road.y, road.y + block_size)

func _road_center_x(index: int) -> float:
	var band: Vector2 = _road_band_x(index)
	return (band.x + band.y) * 0.5

func _road_center_z(index: int) -> float:
	var band: Vector2 = _road_band_z(index)
	return (band.x + band.y) * 0.5

func _total_width() -> float:
	return float(grid_size.x) * block_size + float(grid_size.x + 1) * street_width

func _total_depth() -> float:
	return float(grid_size.y) * block_size + float(grid_size.y + 1) * street_width
