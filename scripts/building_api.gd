extends RefCounted
class_name BuildingAPI

const MODULE_ID_SINGLE_WINDOW_FLOOR: int = 100
const MODULE_ID_ARCH_TOP_WINDOW: int = 101
const MODULE_ID_CHECKER_GLASS: int = 102
const MODULE_ID_TWIN_WINDOW: int = 103
const CORNER_MODULE_ID: int = 190

const SUPPORTED_WINDOW_MODULE_IDS: Array[int] = [
	MODULE_ID_SINGLE_WINDOW_FLOOR,
	MODULE_ID_ARCH_TOP_WINDOW,
	MODULE_ID_CHECKER_GLASS,
	MODULE_ID_TWIN_WINDOW
]

const DEFAULT_MODULE_WIDTH: float = 3.2
const DEFAULT_MODULE_DEPTH: float = 0.25
const DEFAULT_MODULE_HEIGHT: float = 3.0
const DEFAULT_WINDOW_WIDTH: float = 1.35
const DEFAULT_WINDOW_HEIGHT: float = 1.5
const DEFAULT_WINDOW_SILL: float = 0.95
const DEFAULT_WINDOW_RECESS: float = 0.08
const DEFAULT_FRAME_THICKNESS: float = 0.06
const DEFAULT_FRAME_DEPTH: float = 0.04
const DEFAULT_SLAB_BAND_HEIGHT: float = 0.12

const ROOF_TYPE_FLAT := "flat"
const ROOF_TYPE_PITCHED := "pitched"

const MIN_WIDTH_MODULES: int = 1
const MAX_WIDTH_MODULES: int = 32
const MIN_LENGTH_MODULES: int = 1
const MAX_LENGTH_MODULES: int = 32
const MIN_FLOORS: int = 1
const MAX_FLOORS: int = 24

static var _mesh_cache: Dictionary = {}
static var _material_cache: Dictionary = {}


static func is_supported_window_module_id(module_id: int) -> bool:
	return module_id in SUPPORTED_WINDOW_MODULE_IDS


static func sanitize_window_module_id(module_id: int) -> int:
	return module_id if is_supported_window_module_id(module_id) else MODULE_ID_SINGLE_WINDOW_FLOOR


static func sanitize_window_module_ids(module_ids: Array) -> Array[int]:
	var sanitized: Array[int] = []
	for value in module_ids:
		var module_id: int = sanitize_window_module_id(_to_int(value, MODULE_ID_SINGLE_WINDOW_FLOOR))
		if not sanitized.has(module_id):
			sanitized.append(module_id)
	if sanitized.is_empty():
		sanitized.append(MODULE_ID_SINGLE_WINDOW_FLOOR)
	return sanitized


static func module_definition(module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR) -> Dictionary:
	module_id = sanitize_window_module_id(module_id)
	match module_id:
		MODULE_ID_ARCH_TOP_WINDOW:
			return {
				"module_id": module_id,
				"identity": "%d" % module_id,
				"name": "arch_top_window_module",
				"palette": "painted_lady_mint",
				"width": DEFAULT_MODULE_WIDTH,
				"depth": DEFAULT_MODULE_DEPTH,
				"height": DEFAULT_MODULE_HEIGHT,
				"window": {
					"count": 1,
					"style": "arch_top",
					"width": 1.42,
					"height": 1.64,
					"sill_height": 0.84,
					"recess": DEFAULT_WINDOW_RECESS,
					"arch_height": 0.58,
					"arch_rows": 5
				},
				"frame_thickness": DEFAULT_FRAME_THICKNESS,
				"frame_depth": DEFAULT_FRAME_DEPTH,
				"slab_band_height": DEFAULT_SLAB_BAND_HEIGHT
			}
		MODULE_ID_CHECKER_GLASS:
			return {
				"module_id": module_id,
				"identity": "%d" % module_id,
				"name": "checker_glass_module",
				"palette": "default",
				"width": DEFAULT_MODULE_WIDTH,
				"depth": DEFAULT_MODULE_DEPTH,
				"height": DEFAULT_MODULE_HEIGHT,
				"window": {
					"count": 1,
					"style": "checker",
					"width": 1.44,
					"height": 1.58,
					"sill_height": 0.86,
					"recess": DEFAULT_WINDOW_RECESS,
					"checker_rows": 3,
					"checker_cols": 2
				},
				"frame_thickness": DEFAULT_FRAME_THICKNESS,
				"frame_depth": DEFAULT_FRAME_DEPTH,
				"slab_band_height": DEFAULT_SLAB_BAND_HEIGHT
			}
		MODULE_ID_TWIN_WINDOW:
			return {
				"module_id": module_id,
				"identity": "%d" % module_id,
				"name": "twin_window_module",
				"palette": "default",
				"width": DEFAULT_MODULE_WIDTH,
				"depth": DEFAULT_MODULE_DEPTH,
				"height": DEFAULT_MODULE_HEIGHT,
				"window": {
					"count": 2,
					"style": "twin",
					"width": 1.68,
					"height": 1.54,
					"sill_height": 0.88,
					"recess": DEFAULT_WINDOW_RECESS,
					"pair_gap": 0.18,
					"transom_height": 0.26
				},
				"frame_thickness": DEFAULT_FRAME_THICKNESS,
				"frame_depth": DEFAULT_FRAME_DEPTH,
				"slab_band_height": DEFAULT_SLAB_BAND_HEIGHT
			}
		_:
			return {
				"module_id": module_id,
				"identity": "%d" % module_id,
				"name": "single_window_one_floor_module",
				"palette": "default",
				"width": DEFAULT_MODULE_WIDTH,
				"depth": DEFAULT_MODULE_DEPTH,
				"height": DEFAULT_MODULE_HEIGHT,
				"window": {
					"count": 1,
					"style": "single",
					"width": DEFAULT_WINDOW_WIDTH,
					"height": DEFAULT_WINDOW_HEIGHT,
					"sill_height": DEFAULT_WINDOW_SILL,
					"recess": DEFAULT_WINDOW_RECESS
				},
				"frame_thickness": DEFAULT_FRAME_THICKNESS,
				"frame_depth": DEFAULT_FRAME_DEPTH,
				"slab_band_height": DEFAULT_SLAB_BAND_HEIGHT
			}


static func build_module_node(module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR) -> Node3D:
	return _build_module_node({
		"module_id": module_id,
		"identity": "%d" % module_id,
		"index": 0,
		"position": _vec3_dict(Vector3.ZERO),
		"rotation_degrees": _vec3_dict(Vector3.ZERO)
	})


static func build_corner_module_node(module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR) -> Node3D:
	var definition := module_definition(module_id)
	return _build_corner_node({
		"module_id": CORNER_MODULE_ID,
		"identity": "%d_corner" % module_id,
		"index": 0,
		"position": _vec3_dict(Vector3.ZERO),
		"palette": str(definition.get("palette", "default")),
		"size": _vec3_dict(Vector3(float(definition["depth"]), float(definition["height"]), float(definition["depth"])))
	})


static func build_roof_module_node(roof_type: String = ROOF_TYPE_FLAT, width: float = DEFAULT_MODULE_WIDTH * 4.0, depth: float = DEFAULT_MODULE_WIDTH * 3.0, module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR) -> Node3D:
	return _build_roof_node({"width": width, "depth": depth}, DEFAULT_MODULE_HEIGHT, roof_type, str(module_definition(module_id).get("palette", "default")))


static func create_wall_spec(module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR, module_count: int = 4, origin: Vector3 = Vector3.ZERO, yaw_degrees: float = 0.0) -> Dictionary:
	var definition := module_definition(module_id)
	var safe_count: int = maxi(1, module_count)
	var width: float = float(definition["width"])
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var modules: Array[Dictionary] = []
	var total_width: float = float(safe_count) * width
	for index in range(safe_count):
		var local_offset := Vector3(-total_width * 0.5 + width * (float(index) + 0.5), 0.0, 0.0)
		var world_position: Vector3 = origin + basis * local_offset
		modules.append({
			"module_id": definition["module_id"],
			"identity": definition["identity"],
			"index": index,
			"position": _vec3_dict(world_position),
			"rotation_degrees": _vec3_dict(Vector3(0.0, yaw_degrees, 0.0))
		})
	return {
		"kind": "wall",
		"module_id": definition["module_id"],
		"identity": definition["identity"],
		"module_count": safe_count,
		"origin": _vec3_dict(origin),
		"yaw_degrees": yaw_degrees,
		"span": total_width,
		"modules": modules
	}


static func create_floor_spec(module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR, width_modules: int = 4, floor_index: int = 0, length_modules: int = -1) -> Dictionary:
	var definition := module_definition(module_id)
	var safe_width_modules: int = maxi(1, width_modules)
	var safe_length_modules: int = maxi(1, length_modules if length_modules > 0 else width_modules)
	var module_width: float = float(definition["width"])
	var module_depth: float = float(definition["depth"])
	var module_height: float = float(definition["height"])
	var width_span: float = float(safe_width_modules) * module_width
	var length_span: float = float(safe_length_modules) * module_width
	var half_width: float = width_span * 0.5
	var half_length: float = length_span * 0.5
	var wall_offset_x: float = half_width - module_depth * 0.5
	var wall_offset_z: float = half_length - module_depth * 0.5
	var level_y: float = float(floor_index) * module_height
	var walls: Array[Dictionary] = [
		create_wall_spec(module_id, safe_width_modules, Vector3(0.0, level_y, wall_offset_z), 0.0),
		create_wall_spec(module_id, safe_length_modules, Vector3(wall_offset_x, level_y, 0.0), 90.0),
		create_wall_spec(module_id, safe_width_modules, Vector3(0.0, level_y, -wall_offset_z), 180.0),
		create_wall_spec(module_id, safe_length_modules, Vector3(-wall_offset_x, level_y, 0.0), 270.0)
	]
	var corners: Array[Dictionary] = _create_corner_specs(module_id, wall_offset_x, wall_offset_z, level_y, module_depth, module_height, str(definition.get("palette", "default")))
	return {
		"kind": "floor",
		"module_id": definition["module_id"],
		"identity": definition["identity"],
		"floor_index": floor_index,
		"elevation": level_y,
		"width_modules": safe_width_modules,
		"length_modules": safe_length_modules,
		"wall_count": 4,
		"footprint": {"width": width_span, "depth": length_span},
		"corners": corners,
		"walls": walls
	}


static func create_building_spec(module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR, width_modules: int = 4, floor_count: int = 5, length_modules: int = -1) -> Dictionary:
	var request := normalize_building_request({
		"module_id": module_id,
		"width_modules": width_modules,
		"length_modules": length_modules,
		"floor_count": floor_count
	})
	return create_building_spec_from_request(request)


static func create_building_spec_from_request(request: Dictionary) -> Dictionary:
	var normalized := normalize_building_request(request)
	var definition := module_definition(int(normalized["module_id"]))
	var safe_width_modules: int = int(normalized["width_modules"])
	var safe_length_modules: int = int(normalized["length_modules"])
	var safe_floor_count: int = int(normalized["floor_count"])
	var roof_type: String = str(normalized["roof_type"])
	var floors: Array[Dictionary] = []
	for floor_index in range(safe_floor_count):
		floors.append(create_floor_spec(int(definition["module_id"]), safe_width_modules, floor_index, safe_length_modules))
	var footprint_width: float = float(safe_width_modules) * float(definition["width"])
	var footprint_depth: float = float(safe_length_modules) * float(definition["width"])
	return {
		"kind": "building",
		"module_id": definition["module_id"],
		"identity": definition["identity"],
		"width_modules": safe_width_modules,
		"length_modules": safe_length_modules,
		"wall_count_per_floor": 4,
		"floor_count": safe_floor_count,
		"module_height": definition["height"],
		"roof_type": roof_type,
		"footprint": {"width": footprint_width, "depth": footprint_depth},
		"request": normalized,
		"floors": floors
	}


static func normalize_building_request(request: Dictionary) -> Dictionary:
	var requested_module_id: int = _to_int(request.get("module_id", MODULE_ID_SINGLE_WINDOW_FLOOR), MODULE_ID_SINGLE_WINDOW_FLOOR)
	var width_modules: int = clampi(_to_int(request.get("width_modules", 4), 4), MIN_WIDTH_MODULES, MAX_WIDTH_MODULES)
	var default_length_input: Variant = request.get("length_modules", width_modules)
	var length_modules: int = clampi(_to_int(default_length_input, width_modules), MIN_LENGTH_MODULES, MAX_LENGTH_MODULES)
	var floor_count: int = clampi(_to_int(request.get("floor_count", 5), 5), MIN_FLOORS, MAX_FLOORS)
	var roof_type: String = _normalize_roof_type(str(request.get("roof_type", ROOF_TYPE_FLAT)))
	var module_id: int = sanitize_window_module_id(requested_module_id)
	var position: Vector3 = _variant_to_vec3(request.get("position", Vector3.ZERO))
	var rotation_degrees_y: float = float(request.get("rotation_degrees_y", 0.0))
	var name: String = str(request.get("name", "Building_%d" % module_id))
	return {
		"module_id": module_id,
		"requested_module_id": requested_module_id,
		"width_modules": width_modules,
		"length_modules": length_modules,
		"floor_count": floor_count,
		"roof_type": roof_type,
		"position": _vec3_dict(position),
		"rotation_degrees_y": rotation_degrees_y,
		"name": name,
		"constraints": {
			"width_modules": {"min": MIN_WIDTH_MODULES, "max": MAX_WIDTH_MODULES},
			"length_modules": {"min": MIN_LENGTH_MODULES, "max": MAX_LENGTH_MODULES},
			"floor_count": {"min": MIN_FLOORS, "max": MAX_FLOORS},
			"roof_types": [ROOF_TYPE_FLAT, ROOF_TYPE_PITCHED]
		}
	}


static func build_building_node(module_id: int = MODULE_ID_SINGLE_WINDOW_FLOOR, width_modules: int = 4, floor_count: int = 5, length_modules: int = -1) -> Node3D:
	return build_building_from_spec(create_building_spec(module_id, width_modules, floor_count, length_modules))


static func build_building_from_request(request: Dictionary) -> Node3D:
	return build_building_from_spec(create_building_spec_from_request(request))


static func clear_caches() -> void:
	_mesh_cache.clear()
	_material_cache.clear()


static func build_building_from_spec(spec: Dictionary) -> Node3D:
	var request: Dictionary = spec.get("request", {})
	var root := Node3D.new()
	root.name = str(request.get("name", "Building_%s" % str(spec.get("identity", MODULE_ID_SINGLE_WINDOW_FLOOR))))
	root.position = _dict_to_vec3(request.get("position", _vec3_dict(Vector3.ZERO)))
	root.rotation_degrees = Vector3(0.0, float(request.get("rotation_degrees_y", 0.0)), 0.0)
	for floor_spec in spec.get("floors", []):
		root.add_child(_build_floor_node(floor_spec))
	root.add_child(_build_roof_node(spec.get("footprint", {"width": 1.0, "depth": 1.0}), float(spec.get("floor_count", 1)) * float(spec.get("module_height", DEFAULT_MODULE_HEIGHT)), str(spec.get("roof_type", ROOF_TYPE_FLAT)), str(module_definition(int(spec.get("module_id", MODULE_ID_SINGLE_WINDOW_FLOOR))).get("palette", "default"))))
	return root


static func _build_floor_node(floor_spec: Dictionary) -> Node3D:
	var floor_node := Node3D.new()
	floor_node.name = "Floor_%d" % int(floor_spec.get("floor_index", 0))
	for wall_spec in floor_spec.get("walls", []):
		floor_node.add_child(_build_wall_node(wall_spec))
	var corners_node := Node3D.new()
	corners_node.name = "Corners"
	for corner_spec in floor_spec.get("corners", []):
		corners_node.add_child(_build_corner_node(corner_spec))
	floor_node.add_child(corners_node)
	return floor_node


static func _build_wall_node(wall_spec: Dictionary) -> Node3D:
	var wall_node := Node3D.new()
	wall_node.name = "Wall_%0.0f" % float(wall_spec.get("yaw_degrees", 0.0))
	for module_spec in wall_spec.get("modules", []):
		wall_node.add_child(_build_module_node(module_spec))
	return wall_node


static func _build_module_node(module_spec: Dictionary) -> Node3D:
	var definition := module_definition(int(module_spec.get("module_id", MODULE_ID_SINGLE_WINDOW_FLOOR)))
	var width: float = float(definition["width"])
	var depth: float = float(definition["depth"])
	var height: float = float(definition["height"])
	var window: Dictionary = definition["window"]
	var palette: String = str(definition.get("palette", "default"))
	var window_style: String = str(window.get("style", "single"))
	var window_width: float = float(window["width"])
	var window_height: float = float(window["height"])
	var sill_height: float = float(window["sill_height"])
	var recess: float = float(window["recess"])
	var frame_thickness: float = float(definition["frame_thickness"])
	var frame_depth: float = float(definition["frame_depth"])
	var slab_band_height: float = float(definition["slab_band_height"])
	var side_width: float = (width - window_width) * 0.5
	var top_height: float = height - (sill_height + window_height)
	var bottom_height: float = sill_height
	var window_center_y: float = sill_height + window_height * 0.5
	var module_node := Node3D.new()
	module_node.name = "Module_%s_%d" % [str(module_spec.get("identity", "100")), int(module_spec.get("index", 0))]
	module_node.position = _dict_to_vec3(module_spec.get("position", _vec3_dict(Vector3.ZERO)))
	module_node.rotation_degrees = _dict_to_vec3(module_spec.get("rotation_degrees", _vec3_dict(Vector3.ZERO)))

	module_node.add_child(_make_piece("Wall_Left", Vector3(side_width, height, depth), Vector3(-(width - side_width) * 0.5, height * 0.5, 0.0), _material("wall", palette)))
	module_node.add_child(_make_piece("Wall_Right", Vector3(side_width, height, depth), Vector3((width - side_width) * 0.5, height * 0.5, 0.0), _material("wall", palette)))
	module_node.add_child(_make_piece("Wall_Bottom", Vector3(window_width, bottom_height, depth), Vector3(0.0, bottom_height * 0.5, 0.0), _material("wall", palette)))
	module_node.add_child(_make_piece("Wall_Top", Vector3(window_width, top_height, depth), Vector3(0.0, height - top_height * 0.5, 0.0), _material("wall", palette)))
	module_node.add_child(_make_piece("Slab_Band", Vector3(width, slab_band_height, depth + 0.02), Vector3(0.0, height - slab_band_height * 0.5, 0.0), _material("trim", palette)))
	match window_style:
		"arch_top":
			_add_arch_window_inserts(module_node, window, window_width, window_height, window_center_y, depth, recess, frame_thickness, frame_depth, palette)
		"checker":
			_add_standard_window_inserts(module_node, window_width, window_height, window_center_y, depth, recess, frame_thickness, frame_depth, palette)
			_add_checker_mullions(module_node, window, window_width, window_height, window_center_y, depth, recess, frame_thickness, palette)
		"twin":
			_add_standard_window_inserts(module_node, window_width, window_height, window_center_y, depth, recess, frame_thickness, frame_depth, palette)
			_add_twin_window_details(module_node, window, window_width, window_height, window_center_y, depth, recess, frame_thickness, frame_depth, palette)
		_:
			_add_standard_window_inserts(module_node, window_width, window_height, window_center_y, depth, recess, frame_thickness, frame_depth, palette)
	return module_node


static func _add_standard_window_inserts(module_node: Node3D, window_width: float, window_height: float, window_center_y: float, depth: float, recess: float, frame_thickness: float, frame_depth: float, palette: String = "default") -> void:
	module_node.add_child(_make_piece("Glass", Vector3(window_width - 0.12, window_height - 0.12, 0.02), Vector3(0.0, window_center_y, depth * 0.5 - recess), _material("glass", palette)))
	module_node.add_child(_make_piece("Frame_Left", Vector3(frame_thickness, window_height, frame_depth), Vector3(-window_width * 0.5 + frame_thickness * 0.5, window_center_y, depth * 0.5 - recess * 0.5), _material("frame", palette)))
	module_node.add_child(_make_piece("Frame_Right", Vector3(frame_thickness, window_height, frame_depth), Vector3(window_width * 0.5 - frame_thickness * 0.5, window_center_y, depth * 0.5 - recess * 0.5), _material("frame", palette)))
	module_node.add_child(_make_piece("Frame_Top", Vector3(window_width, frame_thickness, frame_depth), Vector3(0.0, window_center_y + window_height * 0.5 - frame_thickness * 0.5, depth * 0.5 - recess * 0.5), _material("frame", palette)))
	module_node.add_child(_make_piece("Frame_Bottom", Vector3(window_width, frame_thickness, frame_depth), Vector3(0.0, window_center_y - window_height * 0.5 + frame_thickness * 0.5, depth * 0.5 - recess * 0.5), _material("frame", palette)))


static func _add_arch_window_inserts(module_node: Node3D, window: Dictionary, window_width: float, window_height: float, window_center_y: float, depth: float, recess: float, frame_thickness: float, frame_depth: float, palette: String = "default") -> void:
	var arch_height: float = clampf(float(window.get("arch_height", window_height * 0.36)), 0.34, minf(window_height * 0.48, window_width * 0.58))
	var arch_rows: int = clampi(_to_int(window.get("arch_rows", 5), 5), 4, 6)
	var base_height: float = maxf(0.72, window_height - arch_height)
	var window_bottom_y: float = window_center_y - window_height * 0.5
	var spring_top_y: float = window_bottom_y + base_height
	var base_center_y: float = window_bottom_y + base_height * 0.5
	var opening_half_width: float = window_width * 0.5
	var glass_z: float = depth * 0.5 - recess
	var frame_z: float = depth * 0.5 - recess * 0.5
	var base_glass_height: float = maxf(0.18, base_height - frame_thickness * 2.4)
	var base_glass_width: float = maxf(frame_thickness * 3.0, window_width - frame_thickness * 2.4)
	var base_glass_center_y: float = window_bottom_y + frame_thickness + base_glass_height * 0.5
	module_node.add_child(_make_piece("Glass_Base", Vector3(base_glass_width, base_glass_height, 0.02), Vector3(0.0, base_glass_center_y, glass_z), _material("glass", palette)))
	module_node.add_child(_make_piece("Frame_Left", Vector3(frame_thickness, base_height, frame_depth), Vector3(-opening_half_width + frame_thickness * 0.5, base_center_y, frame_z), _material("frame", palette)))
	module_node.add_child(_make_piece("Frame_Right", Vector3(frame_thickness, base_height, frame_depth), Vector3(opening_half_width - frame_thickness * 0.5, base_center_y, frame_z), _material("frame", palette)))
	module_node.add_child(_make_piece("Frame_Bottom", Vector3(window_width, frame_thickness, frame_depth), Vector3(0.0, window_bottom_y + frame_thickness * 0.5, frame_z), _material("frame", palette)))
	module_node.add_child(_make_piece("Arch_Frame_Spring", Vector3(window_width, frame_thickness, frame_depth), Vector3(0.0, spring_top_y - frame_thickness * 0.5, frame_z), _material("frame", palette)))

	for row in range(arch_rows):
		var row_bottom_y: float = spring_top_y + arch_height * float(row) / float(arch_rows)
		var row_top_y: float = spring_top_y + arch_height * float(row + 1) / float(arch_rows)
		var row_mid_y: float = (row_bottom_y + row_top_y) * 0.5
		var row_height: float = row_top_y - row_bottom_y
		var row_t_mid: float = clampf((row_mid_y - spring_top_y) / arch_height, 0.0, 1.0)
		var row_t_top: float = clampf((row_top_y - spring_top_y) / arch_height, 0.0, 1.0)
		var half_width_mid: float = maxf(frame_thickness * 1.4, opening_half_width * sqrt(maxf(0.0, 1.0 - pow(row_t_mid, 2.0))))
		var half_width_top: float = maxf(frame_thickness * 1.1, opening_half_width * sqrt(maxf(0.0, 1.0 - pow(row_t_top, 2.0))))
		var filler_width: float = maxf(0.0, opening_half_width - half_width_mid)
		if filler_width > 0.02:
			var filler_center_x: float = half_width_mid + filler_width * 0.5
			module_node.add_child(_make_piece("Arch_Wall_Left_Spandrel_%d" % row, Vector3(filler_width, row_height + 0.002, depth), Vector3(-filler_center_x, row_mid_y, 0.0), _material("wall", palette)))
			module_node.add_child(_make_piece("Arch_Wall_Right_Spandrel_%d" % row, Vector3(filler_width, row_height + 0.002, depth), Vector3(filler_center_x, row_mid_y, 0.0), _material("wall", palette)))
		var glass_width: float = maxf(frame_thickness * 2.2, half_width_mid * 2.0 - frame_thickness * 2.2)
		var glass_height: float = maxf(0.05, row_height - 0.03)
		var glass_name: String = "Arch_Glass_Center" if row == arch_rows - 1 else "Arch_Glass_Row_%d" % row
		module_node.add_child(_make_piece(glass_name, Vector3(glass_width, glass_height, 0.02), Vector3(0.0, row_mid_y, glass_z), _material("glass", palette)))
		if half_width_mid * 2.0 > frame_thickness * 4.0:
			module_node.add_child(_make_piece("Arch_Frame_Left_Row_%d" % row, Vector3(frame_thickness, row_height, frame_depth), Vector3(-half_width_mid + frame_thickness * 0.5, row_mid_y, frame_z), _material("frame", palette)))
			module_node.add_child(_make_piece("Arch_Frame_Right_Row_%d" % row, Vector3(frame_thickness, row_height, frame_depth), Vector3(half_width_mid - frame_thickness * 0.5, row_mid_y, frame_z), _material("frame", palette)))
		var cap_width: float = maxf(frame_thickness * 2.0, half_width_top * 2.0)
		var cap_name: String = "Arch_Frame_Center" if row == arch_rows - 1 else "Arch_Frame_Cap_%d" % row
		module_node.add_child(_make_piece(cap_name, Vector3(cap_width, frame_thickness, frame_depth), Vector3(0.0, row_top_y - frame_thickness * 0.5, frame_z), _material("frame", palette)))


static func _add_checker_mullions(module_node: Node3D, window: Dictionary, window_width: float, window_height: float, window_center_y: float, depth: float, recess: float, frame_thickness: float, palette: String = "default") -> void:
	var cols: int = maxi(1, _to_int(window.get("checker_cols", 2), 2))
	var rows: int = maxi(1, _to_int(window.get("checker_rows", 3), 3))
	for col in range(1, cols):
		var x: float = lerpf(-window_width * 0.5, window_width * 0.5, float(col) / float(cols))
		module_node.add_child(_make_piece("Checker_Mullion_V_%d" % (col - 1), Vector3(frame_thickness, window_height - 0.12, 0.028), Vector3(x, window_center_y, depth * 0.5 - recess * 0.9), _material("frame", palette)))
	for row in range(1, rows):
		var y: float = lerpf(window_center_y - window_height * 0.5, window_center_y + window_height * 0.5, float(row) / float(rows))
		module_node.add_child(_make_piece("Checker_Mullion_H_%d" % (row - 1), Vector3(window_width - 0.12, frame_thickness, 0.028), Vector3(0.0, y, depth * 0.5 - recess * 0.9), _material("frame", palette)))


static func _add_twin_window_details(module_node: Node3D, window: Dictionary, window_width: float, window_height: float, window_center_y: float, depth: float, recess: float, frame_thickness: float, frame_depth: float, palette: String = "default") -> void:
	var pair_gap: float = clampf(float(window.get("pair_gap", 0.18)), frame_thickness * 2.0, window_width * 0.3)
	var transom_height: float = clampf(float(window.get("transom_height", 0.26)), 0.14, window_height * 0.3)
	module_node.add_child(_make_piece("Twin_Mullion_Center", Vector3(frame_thickness * 1.3, window_height - 0.1, frame_depth), Vector3(0.0, window_center_y, depth * 0.5 - recess * 0.5), _material("frame", palette)))
	module_node.add_child(_make_piece("Twin_Frame_Inner_Left", Vector3(frame_thickness, window_height - 0.12, frame_depth), Vector3(-pair_gap * 0.5, window_center_y, depth * 0.5 - recess * 0.5), _material("frame", palette)))
	module_node.add_child(_make_piece("Twin_Frame_Inner_Right", Vector3(frame_thickness, window_height - 0.12, frame_depth), Vector3(pair_gap * 0.5, window_center_y, depth * 0.5 - recess * 0.5), _material("frame", palette)))
	module_node.add_child(_make_piece("Twin_Transom", Vector3(window_width - 0.12, frame_thickness, frame_depth), Vector3(0.0, window_center_y + window_height * 0.5 - transom_height, depth * 0.5 - recess * 0.5), _material("frame", palette)))


static func _build_corner_node(corner_spec: Dictionary) -> Node3D:
	var corner_node := Node3D.new()
	corner_node.name = "Corner_%d" % int(corner_spec.get("index", 0))
	corner_node.position = _dict_to_vec3(corner_spec.get("position", _vec3_dict(Vector3.ZERO)))
	var size := _dict_to_vec3(corner_spec.get("size", _vec3_dict(Vector3(DEFAULT_MODULE_DEPTH, DEFAULT_MODULE_HEIGHT, DEFAULT_MODULE_DEPTH))))
	corner_node.add_child(_make_piece("CornerColumn", size, Vector3(0.0, size.y * 0.5, 0.0), _material("trim", str(corner_spec.get("palette", "default")))))
	return corner_node


static func _build_roof_node(footprint: Dictionary, base_height: float, roof_type: String, palette: String = "default") -> Node3D:
	var roof_node := Node3D.new()
	roof_node.name = "Roof"
	var width: float = float(footprint.get("width", DEFAULT_MODULE_WIDTH))
	var depth: float = float(footprint.get("depth", DEFAULT_MODULE_WIDTH))
	match _normalize_roof_type(roof_type):
		ROOF_TYPE_PITCHED:
			var rise: float = clampf(depth * 0.18, 0.6, 2.0)
			var angle: float = atan2(rise, depth * 0.5)
			var slope_length: float = sqrt(pow(depth * 0.5, 2.0) + pow(rise, 2.0))
			var roof_thickness: float = 0.14
			var fill_height: float = maxf(0.12, rise * 0.55)
			roof_node.add_child(_make_piece("Roof_Fill", Vector3(width, fill_height, depth - 0.04), Vector3(0.0, base_height + fill_height * 0.5, 0.0), _material("wall", palette)))
			roof_node.add_child(_make_piece("Roof_Left", Vector3(width + 0.04, roof_thickness, slope_length + 0.04), Vector3(0.0, base_height + fill_height + rise * 0.5 - roof_thickness * 0.25, -depth * 0.25), _material("roof", palette), Vector3(-angle, 0.0, 0.0)))
			roof_node.add_child(_make_piece("Roof_Right", Vector3(width + 0.04, roof_thickness, slope_length + 0.04), Vector3(0.0, base_height + fill_height + rise * 0.5 - roof_thickness * 0.25, depth * 0.25), _material("roof", palette), Vector3(angle, 0.0, 0.0)))
			roof_node.add_child(_make_piece("Ridge_Cap", Vector3(width + 0.02, 0.08, 0.12), Vector3(0.0, base_height + fill_height + rise - 0.02, 0.0), _material("roof", palette)))
			roof_node.add_child(_make_piece("Soffit", Vector3(width, 0.06, depth), Vector3(0.0, base_height + 0.03, 0.0), _material("trim", palette)))
		_:
			roof_node.add_child(_make_piece("Roof_Flat", Vector3(width, 0.18, depth), Vector3(0.0, base_height + 0.09, 0.0), _material("roof", palette)))
	return roof_node


static func _create_corner_specs(module_id: int, wall_offset_x: float, wall_offset_z: float, level_y: float, module_depth: float, module_height: float, palette: String = "default") -> Array[Dictionary]:
	var definition := module_definition(module_id)
	var corners: Array[Dictionary] = []
	var positions := [
		Vector3(wall_offset_x, level_y, wall_offset_z),
		Vector3(-wall_offset_x, level_y, wall_offset_z),
		Vector3(wall_offset_x, level_y, -wall_offset_z),
		Vector3(-wall_offset_x, level_y, -wall_offset_z)
	]
	for index in range(positions.size()):
		corners.append({
			"module_id": CORNER_MODULE_ID,
			"identity": "%s_corner" % str(definition["identity"]),
			"index": index,
			"palette": palette,
			"position": _vec3_dict(positions[index]),
			"size": _vec3_dict(Vector3(module_depth, module_height, module_depth))
		})
	return corners


static func _make_piece(name: String, size: Vector3, local_position: Vector3, material: Material, local_rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = name
	piece.mesh = _box_mesh(size)
	piece.material_override = material
	piece.position = local_position
	piece.rotation = local_rotation
	return piece


static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "%0.3f|%0.3f|%0.3f" % [size.x, size.y, size.z]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh_cache[key] = mesh
	return mesh


static func _material(kind: String, palette: String = "default") -> StandardMaterial3D:
	var key := "%s|%s" % [palette, kind]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	match key:
		"painted_lady_mint|wall":
			material.albedo_color = Color(0.64, 0.78, 0.72)
			material.roughness = 0.86
		"painted_lady_mint|trim":
			material.albedo_color = Color(0.95, 0.92, 0.84)
			material.roughness = 0.80
		"painted_lady_mint|frame":
			material.albedo_color = Color(0.24, 0.34, 0.36)
			material.metallic = 0.12
			material.roughness = 0.42
		"painted_lady_mint|glass":
			material.albedo_color = Color(0.64, 0.86, 0.90, 0.58)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.metallic = 0.04
			material.roughness = 0.06
			material.emission_enabled = true
			material.emission = Color(0.70, 0.90, 0.88)
			material.emission_energy_multiplier = 0.16
		"painted_lady_mint|roof":
			material.albedo_color = Color(0.37, 0.46, 0.47)
			material.roughness = 0.76
		"default|wall":
			material.albedo_color = Color(0.78, 0.80, 0.83)
			material.roughness = 0.88
		"default|trim":
			material.albedo_color = Color(0.70, 0.72, 0.75)
			material.roughness = 0.82
		"default|frame":
			material.albedo_color = Color(0.18, 0.20, 0.24)
			material.metallic = 0.2
			material.roughness = 0.45
		"default|glass":
			material.albedo_color = Color(0.55, 0.76, 0.92, 0.45)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.metallic = 0.05
			material.roughness = 0.08
			material.emission_enabled = true
			material.emission = Color(0.60, 0.80, 0.95)
			material.emission_energy_multiplier = 0.1
		"default|roof":
			material.albedo_color = Color(0.56, 0.59, 0.63)
			material.roughness = 0.80
		_:
			material.albedo_color = Color.WHITE
	_material_cache[key] = material
	return material


static func _normalize_roof_type(value: String) -> String:
	var normalized := value.to_lower().strip_edges()
	return normalized if normalized == ROOF_TYPE_PITCHED else ROOF_TYPE_FLAT


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
