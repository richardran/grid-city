extends RefCounted
class_name LegoBlockGenerator

const BuildingAPI = preload("res://scripts/building_api.gd")

const DEFAULT_BLOCK_WIDTH: float = 18.0
const DEFAULT_BLOCK_DEPTH: float = 18.0
const DEFAULT_CORNER_SIZE: float = 5.2
const DEFAULT_BRIDGE_DEPTH: float = 3.2
const DEFAULT_GAP_SIZE: float = 0.6
const PASSAGE_CLEARANCE_FLOORS: int = 1

const MIN_BLOCK_SIZE: float = 10.0
const MAX_BLOCK_SIZE: float = 64.0
const MIN_CORNER_SIZE: float = 3.2
const MIN_BRIDGE_DEPTH: float = 2.6
const MIN_GAP_SIZE: float = 0.2


static func normalize_request(request: Dictionary) -> Dictionary:
	var block_width: float = clampf(float(request.get("block_width", DEFAULT_BLOCK_WIDTH)), MIN_BLOCK_SIZE, MAX_BLOCK_SIZE)
	var block_depth: float = clampf(float(request.get("block_depth", DEFAULT_BLOCK_DEPTH)), MIN_BLOCK_SIZE, MAX_BLOCK_SIZE)
	var min_side: float = minf(block_width, block_depth)
	var corner_size: float = clampf(float(request.get("corner_size", DEFAULT_CORNER_SIZE)), MIN_CORNER_SIZE, min_side * 0.45)
	var gap_size: float = clampf(float(request.get("gap_size", DEFAULT_GAP_SIZE)), MIN_GAP_SIZE, min_side * 0.12)
	var max_bridge_depth: float = maxf(MIN_BRIDGE_DEPTH, min_side * 0.28)
	var bridge_depth: float = clampf(float(request.get("bridge_depth", DEFAULT_BRIDGE_DEPTH)), MIN_BRIDGE_DEPTH, max_bridge_depth)
	var bridge_width: float = maxf(MIN_BRIDGE_DEPTH, block_width - corner_size * 2.0 - gap_size * 2.0)
	var bridge_length: float = maxf(MIN_BRIDGE_DEPTH, block_depth - corner_size * 2.0 - gap_size * 2.0)
	var latched_bridge_width: float = maxf(MIN_BRIDGE_DEPTH, block_width - corner_size * 2.0)
	var latched_bridge_length: float = maxf(MIN_BRIDGE_DEPTH, block_depth - corner_size * 2.0)
	var floor_count: int = clampi(_to_int(request.get("floor_count", 4), 4), BuildingAPI.MIN_FLOORS, BuildingAPI.MAX_FLOORS)
	var module_id: int = _to_int(request.get("module_id", BuildingAPI.MODULE_ID_SINGLE_WINDOW_FLOOR), BuildingAPI.MODULE_ID_SINGLE_WINDOW_FLOOR)
	if module_id != BuildingAPI.MODULE_ID_SINGLE_WINDOW_FLOOR:
		module_id = BuildingAPI.MODULE_ID_SINGLE_WINDOW_FLOOR
	var roof_type: String = _normalize_roof_type(str(request.get("roof_type", BuildingAPI.ROOF_TYPE_FLAT)))
	var position: Vector3 = _variant_to_vec3(request.get("position", Vector3.ZERO))
	var rotation_degrees_y: float = float(request.get("rotation_degrees_y", 0.0))
	var name: String = str(request.get("name", "LegoBlock"))
	return {
		"module_id": module_id,
		"block_width": block_width,
		"block_depth": block_depth,
		"corner_size": corner_size,
		"bridge_depth": bridge_depth,
		"gap_size": gap_size,
		"bridge_width": bridge_width,
		"bridge_length": bridge_length,
		"latched_bridge_width": latched_bridge_width,
		"latched_bridge_length": latched_bridge_length,
		"floor_count": floor_count,
		"roof_type": roof_type,
		"position": _vec3_dict(position),
		"rotation_degrees_y": rotation_degrees_y,
		"name": name
	}


static func create_block_spec_from_request(request: Dictionary) -> Dictionary:
	var normalized := normalize_request(request)
	var block_width: float = float(normalized["block_width"])
	var block_depth: float = float(normalized["block_depth"])
	var corner_size: float = float(normalized["corner_size"])
	var bridge_depth: float = float(normalized["bridge_depth"])
	var bridge_width: float = float(normalized["bridge_width"])
	var bridge_length: float = float(normalized["bridge_length"])
	var latched_bridge_width: float = float(normalized["latched_bridge_width"])
	var latched_bridge_length: float = float(normalized["latched_bridge_length"])
	var floor_count: int = int(normalized["floor_count"])
	var roof_type: String = str(normalized["roof_type"])
	var module_id: int = int(normalized["module_id"])
	var elevated_y: float = float(PASSAGE_CLEARANCE_FLOORS) * float(BuildingAPI.DEFAULT_MODULE_HEIGHT)
	var courtyard_width: float = maxf(0.0, block_width - corner_size * 2.0)
	var courtyard_depth: float = maxf(0.0, block_depth - corner_size * 2.0)
	var buildings: Array[Dictionary] = []

	var corner_half_x: float = block_width * 0.5 - corner_size * 0.5
	var corner_half_z: float = block_depth * 0.5 - corner_size * 0.5
	var bridge_half_x: float = block_width * 0.5 - bridge_depth * 0.5
	var bridge_half_z: float = block_depth * 0.5 - bridge_depth * 0.5

	buildings.append(_create_segment("north_west", module_id, corner_size, corner_size, floor_count, roof_type, Vector3(-corner_half_x, 0.0, corner_half_z), 0.0, false, false))
	buildings.append(_create_segment("north_east", module_id, corner_size, corner_size, floor_count + 1, roof_type, Vector3(corner_half_x, 0.0, corner_half_z), 0.0, false, false))
	buildings.append(_create_segment("south_west", module_id, corner_size, corner_size, max(floor_count - 1, 2), roof_type, Vector3(-corner_half_x, 0.0, -corner_half_z), 0.0, false, false))
	buildings.append(_create_segment("south_east", module_id, corner_size, corner_size, floor_count, roof_type, Vector3(corner_half_x, 0.0, -corner_half_z), 0.0, false, false))
	buildings.append(_create_segment("north_bridge", module_id, latched_bridge_width, bridge_depth, max(floor_count - 2, 2), roof_type, Vector3(0.0, elevated_y, bridge_half_z), 0.0, true, false))
	buildings.append(_create_segment("south_bridge", module_id, bridge_width * 0.82, bridge_depth, max(floor_count - 1, 2), roof_type, Vector3(0.0, 0.0, -bridge_half_z), 0.0, false, false))
	buildings.append(_create_segment("east_bridge", module_id, latched_bridge_length, bridge_depth, max(floor_count - 2, 2), roof_type, Vector3(bridge_half_x, elevated_y, 0.0), 90.0, true, false))
	buildings.append(_create_segment("west_bridge", module_id, bridge_length * 0.78, bridge_depth, max(floor_count - 1, 2), roof_type, Vector3(-bridge_half_x, 0.0, 0.0), 90.0, false, false))

	return {
		"kind": "lego_block",
		"name": normalized["name"],
		"request": normalized,
		"footprint": {"width": block_width, "depth": block_depth},
		"courtyard": {"width": courtyard_width, "depth": courtyard_depth},
		"buildings": buildings
	}


static func build_block_from_request(request: Dictionary) -> Node3D:
	return build_block_from_spec(create_block_spec_from_request(request))


static func build_block_from_spec(spec: Dictionary) -> Node3D:
	var request: Dictionary = spec.get("request", {})
	var root := Node3D.new()
	root.name = str(spec.get("name", request.get("name", "LegoBlock")))
	root.position = _dict_to_vec3(request.get("position", _vec3_dict(Vector3.ZERO)))
	root.rotation_degrees = Vector3(0.0, float(request.get("rotation_degrees_y", 0.0)), 0.0)
	for building in spec.get("buildings", []):
		var child: Node3D = BuildingAPI.build_building_from_spec(building["building_spec"])
		child.name = str(building.get("label", child.name))
		child.position = _dict_to_vec3(building.get("position", _vec3_dict(Vector3.ZERO)))
		child.rotation_degrees = _dict_to_vec3(building.get("rotation_degrees", _vec3_dict(Vector3.ZERO)))
		child.scale = _dict_to_vec3(building.get("scale", _vec3_dict(Vector3.ONE)))
		root.add_child(child)
		if bool(building.get("is_elevated", false)) and building.get("support_columns", []).size() > 0:
			root.add_child(_build_supports_node(building))
	return root


static func _create_segment(label: String, module_id: int, target_width: float, target_depth: float, floors: int, roof_type: String, position: Vector3, rotation_y: float, elevated: bool, add_supports: bool) -> Dictionary:
	var module_def: Dictionary = BuildingAPI.module_definition(module_id)
	var width_modules: int = clampi(int(round(target_width / float(module_def["width"]))), BuildingAPI.MIN_WIDTH_MODULES, BuildingAPI.MAX_WIDTH_MODULES)
	var depth_modules: int = clampi(int(round(target_depth / float(module_def["width"]))), BuildingAPI.MIN_LENGTH_MODULES, BuildingAPI.MAX_LENGTH_MODULES)
	var building_spec: Dictionary = BuildingAPI.create_building_spec_from_request({
		"module_id": module_id,
		"width_modules": width_modules,
		"length_modules": depth_modules,
		"floor_count": clampi(floors, BuildingAPI.MIN_FLOORS, BuildingAPI.MAX_FLOORS),
		"roof_type": roof_type,
		"name": "Segment_%s" % label
	})
	var native_footprint: Dictionary = building_spec["footprint"]
	var scale_x: float = target_width / maxf(0.001, float(native_footprint["width"]))
	var scale_z: float = target_depth / maxf(0.001, float(native_footprint["depth"]))
	var support_columns: Array[Dictionary] = []
	if add_supports:
		support_columns = _create_support_columns(target_width, target_depth)
	return {
		"label": "Building_%s" % label.capitalize(),
		"position": _vec3_dict(position),
		"rotation_degrees": _vec3_dict(Vector3(0.0, rotation_y, 0.0)),
		"scale": _vec3_dict(Vector3(scale_x, 1.0, scale_z)),
		"target_footprint": {"width": target_width, "depth": target_depth},
		"is_elevated": elevated,
		"support_columns": support_columns,
		"building_spec": building_spec
	}


static func _create_support_columns(target_width: float, target_depth: float) -> Array[Dictionary]:
	var inset_x: float = maxf(0.45, target_width * 0.22)
	var inset_z: float = maxf(0.45, target_depth * 0.22)
	var half_w: float = target_width * 0.5 - inset_x
	var half_d: float = target_depth * 0.5 - inset_z
	return [
		{"position": _vec3_dict(Vector3(-half_w, BuildingAPI.DEFAULT_MODULE_HEIGHT * 0.5, -half_d)), "size": _vec3_dict(Vector3(0.32, BuildingAPI.DEFAULT_MODULE_HEIGHT, 0.32))},
		{"position": _vec3_dict(Vector3(half_w, BuildingAPI.DEFAULT_MODULE_HEIGHT * 0.5, -half_d)), "size": _vec3_dict(Vector3(0.32, BuildingAPI.DEFAULT_MODULE_HEIGHT, 0.32))},
		{"position": _vec3_dict(Vector3(-half_w, BuildingAPI.DEFAULT_MODULE_HEIGHT * 0.5, half_d)), "size": _vec3_dict(Vector3(0.32, BuildingAPI.DEFAULT_MODULE_HEIGHT, 0.32))},
		{"position": _vec3_dict(Vector3(half_w, BuildingAPI.DEFAULT_MODULE_HEIGHT * 0.5, half_d)), "size": _vec3_dict(Vector3(0.32, BuildingAPI.DEFAULT_MODULE_HEIGHT, 0.32))}
	]


static func _build_supports_node(building: Dictionary) -> Node3D:
	var supports_root := Node3D.new()
	supports_root.name = "%s_Supports" % str(building.get("label", "Building"))
	supports_root.position = _dict_to_vec3(building.get("position", _vec3_dict(Vector3.ZERO)))
	supports_root.rotation_degrees = _dict_to_vec3(building.get("rotation_degrees", _vec3_dict(Vector3.ZERO)))
	supports_root.scale = _dict_to_vec3(building.get("scale", _vec3_dict(Vector3.ONE)))
	for column in building.get("support_columns", []):
		var node := MeshInstance3D.new()
		node.name = "SupportColumn"
		var mesh := BoxMesh.new()
		mesh.size = _dict_to_vec3(column.get("size", _vec3_dict(Vector3(0.32, BuildingAPI.DEFAULT_MODULE_HEIGHT, 0.32))))
		node.mesh = mesh
		node.material_override = _support_material()
		node.position = _dict_to_vec3(column.get("position", _vec3_dict(Vector3.ZERO)))
		supports_root.add_child(node)
	return supports_root


static func _support_material() -> StandardMaterial3D:
	var key := "lego_support"
	if BuildingAPI._material_cache.has(key):
		return BuildingAPI._material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.67, 0.68, 0.72)
	material.roughness = 0.84
	BuildingAPI._material_cache[key] = material
	return material


static func _normalize_roof_type(value: String) -> String:
	var normalized := value.to_lower().strip_edges()
	return normalized if normalized == BuildingAPI.ROOF_TYPE_PITCHED else BuildingAPI.ROOF_TYPE_FLAT


static func _vec3_dict(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


static func _dict_to_vec3(value: Variant) -> Vector3:
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO


static func _variant_to_vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return _dict_to_vec3(value)
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _to_int(value: Variant, default_value: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(round(value))
	if value is String and value.is_valid_int():
		return int(value)
	return default_value
