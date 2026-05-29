extends RefCounted
class_name CityLayout

## Pure data representation of a generated city.
## No Godot scene nodes — only floats, Vector3s, and arrays.

var grid_size: Vector2i
var block_size: float
var street_width: float
var seed_value: int
var main_avenue_x: int
var signature_cross_z: int
var city_base_y: float
var terrain_height: float
var terrain_frequency: float

var walk_areas = []  # Array[Dictionary]
var building_slots = []  # Array[Dictionary]
var street_heights: Dictionary = {}  # Vector2i → float


func _init(p_grid_size: Vector2i, p_block_size: float, p_street_width: float,
		   p_seed: int, p_main_av: int, p_sign_z: int, p_base_y: float,
		   p_terrain_h: float, p_terrain_freq: float) -> void:
	grid_size = p_grid_size
	block_size = p_block_size
	street_width = p_street_width
	seed_value = p_seed
	main_avenue_x = p_main_av
	signature_cross_z = p_sign_z
	city_base_y = p_base_y
	terrain_height = p_terrain_h
	terrain_frequency = p_terrain_freq


func setup(walk, slots, heights: Dictionary) -> void:
	walk_areas = walk
	building_slots = slots
	street_heights = heights


func total_width() -> float:
	return float(grid_size.x) * block_size + float(grid_size.x + 1) * street_width


func total_depth() -> float:
	return float(grid_size.y) * block_size + float(grid_size.y + 1) * street_width


func road_band_x(index: int) -> Vector2:
	var left: float = -total_width() * 0.5 + float(index) * (block_size + street_width)
	return Vector2(left, left + street_width)


func road_band_z(index: int) -> Vector2:
	var top: float = -total_depth() * 0.5 + float(index) * (block_size + street_width)
	return Vector2(top, top + street_width)


func block_band_x(index: int) -> Vector2:
	var road: Vector2 = road_band_x(index)
	return Vector2(road.y, road.y + block_size)


func block_band_z(index: int) -> Vector2:
	var road: Vector2 = road_band_z(index)
	return Vector2(road.y, road.y + block_size)


func road_center_x(index: int) -> float:
	var band: Vector2 = road_band_x(index)
	return (band.x + band.y) * 0.5


func road_center_z(index: int) -> float:
	var band: Vector2 = road_band_z(index)
	return (band.x + band.y) * 0.5


func node_position(ix: int, iz: int) -> Vector3:
	return Vector3(road_center_x(ix), _street_height(Vector2i(ix, iz)), road_center_z(iz))


func _street_height(key: Vector2i) -> float:
	return street_heights.get(key, city_base_y)


func get_spawn_point() -> Vector3:
	var start_node := Vector2i(main_avenue_x, maxi(1, int(grid_size.y * 0.28)))
	var point := node_position(start_node.x, start_node.y)
	return Vector3(point.x, point.y + 1.65, point.z)


func get_walk_height(world_position: Vector3) -> float:
	var snap := _closest_walk_snap(world_position)
	return snap.height if snap.valid else city_base_y + 1.65


func get_walk_ground_height(world_position: Vector3) -> float:
	var snap := _closest_walk_snap(world_position)
	return snap.ground_height if snap.valid else city_base_y


func get_nearest_walk_ground_point(world_position: Vector3) -> Vector3:
	if walk_areas.is_empty():
		return Vector3(world_position.x, city_base_y, world_position.z)
	var best_dist: float = INF
	var best_point := Vector3(world_position.x, city_base_y, world_position.z)
	for area in walk_areas:
		var x_band: Vector2 = Vector2(area.get("x", Vector2.ZERO))
		var z_band: Vector2 = Vector2(area.get("z", Vector2.ZERO))
		var clamped_x: float = clampf(world_position.x, x_band.x, x_band.y)
		var clamped_z: float = clampf(world_position.z, z_band.x, z_band.y)
		var candidate := Vector3(clamped_x, area.get("y", city_base_y), clamped_z)
		var distance_sq: float = Vector2(candidate.x - world_position.x, candidate.z - world_position.z).length_squared()
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


func get_random_walk_point(rng: RandomNumberGenerator, margin: float = 0.45, preferred_kind: String = "") -> Vector3:
	if walk_areas.is_empty():
		var spawn := get_spawn_point()
		return Vector3(spawn.x, spawn.y - 1.65, spawn.z)
	var candidates: Array[Dictionary] = []
	for area in walk_areas:
		if preferred_kind == "" or area.get("kind", "") == preferred_kind:
			candidates.append(area)
	if candidates.is_empty():
		candidates = walk_areas
	var total_weight: float = 0.0
	for candidate in candidates:
		var x_band: Vector2 = Vector2(candidate.get("x", Vector2.ZERO))
		var z_band: Vector2 = Vector2(candidate.get("z", Vector2.ZERO))
		var w: float = candidate.get("weight", 1.0)
		var a: float = (x_band.y - x_band.x) * (z_band.y - z_band.x)
		total_weight += w * maxf(0.01, a)
	var pick_weight: float = rng.randf() * maxf(0.001, total_weight)
	var area: Dictionary = candidates[0]
	for candidate in candidates:
		var x_band: Vector2 = Vector2(candidate.get("x", Vector2.ZERO))
		var z_band: Vector2 = Vector2(candidate.get("z", Vector2.ZERO))
		var w: float = candidate.get("weight", 1.0)
		var a: float = (x_band.y - x_band.x) * (z_band.y - z_band.x)
		pick_weight -= w * maxf(0.01, a)
		area = candidate
		if pick_weight <= 0.0:
			break
	var area_x: Vector2 = Vector2(area.get("x", Vector2.ZERO))
	var area_z: Vector2 = Vector2(area.get("z", Vector2.ZERO))
	var x0: float = area_x.x
	var x1: float = area_x.y
	var z0: float = area_z.x
	var z1: float = area_z.y
	var safe_margin_x: float = minf(margin, maxf(0.0, (x1 - x0) * 0.5 - 0.08))
	var safe_margin_z: float = minf(margin, maxf(0.0, (z1 - z0) * 0.5 - 0.08))
	var px: float = rng.randf_range(x0 + safe_margin_x, x1 - safe_margin_x) if x1 - x0 > safe_margin_x * 2.0 else (x0 + x1) * 0.5
	var pz: float = rng.randf_range(z0 + safe_margin_z, z1 - safe_margin_z) if z1 - z0 > safe_margin_z * 2.0 else (z0 + z1) * 0.5
	return Vector3(px, area.get("y", city_base_y), pz)


func get_building_slots_snapshot() -> Array:
	return building_slots.duplicate(true)


func get_walk_areas_snapshot() -> Array:
	return walk_areas.duplicate(true)


func _closest_walk_snap(world_position: Vector3) -> Dictionary:
	var best_dist: float = INF
	var best_point: Vector3 = world_position
	var best_ground_height: float = city_base_y
	var best_height: float = city_base_y + 1.65
	var best_valid: bool = false
	var max_snap: float = street_width * 0.55
	for area in walk_areas:
		var x_band: Vector2 = Vector2(area.get("x", Vector2.ZERO))
		var z_band: Vector2 = Vector2(area.get("z", Vector2.ZERO))
		var clamped_x: float = clampf(world_position.x, x_band.x, x_band.y)
		var clamped_z: float = clampf(world_position.z, z_band.x, z_band.y)
		var dx: float = world_position.x - clamped_x
		var dz: float = world_position.z - clamped_z
		var dist: float = sqrt(dx * dx + dz * dz)
		if dist <= max_snap and dist < best_dist:
			best_dist = dist
			best_point = Vector3(clamped_x, 0.0, clamped_z)
			best_ground_height = area.get("y", city_base_y)
			best_height = best_ground_height + 1.65
			best_valid = true
	return {"valid": best_valid, "position": best_point, "ground_height": best_ground_height, "height": best_height}
