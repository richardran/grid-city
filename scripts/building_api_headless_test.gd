extends SceneTree

const BuildingAPI = preload("res://scripts/building_api.gd")

func _init() -> void:
	var definition: Dictionary = BuildingAPI.module_definition(100)
	assert(definition["module_id"] == 100)
	assert(definition["window"]["count"] == 1)
	assert(BuildingAPI.module_definition(101)["window"]["style"] == "arch_top")
	assert(BuildingAPI.module_definition(102)["window"]["style"] == "checker")
	assert(BuildingAPI.module_definition(103)["window"]["style"] == "twin")

	var wall: Dictionary = BuildingAPI.create_wall_spec(100, 5)
	assert(wall["module_count"] == 5)
	assert(wall["modules"].size() == 5)
	assert(wall["modules"][0]["identity"] == "100")

	var floor: Dictionary = BuildingAPI.create_floor_spec(100, 4, 2, 3)
	assert(floor["wall_count"] == 4)
	assert(floor["walls"].size() == 4)
	assert(floor["walls"][0]["modules"].size() == 4)
	assert(floor["walls"][1]["modules"].size() == 3)
	assert(floor["corners"].size() == 4)
	assert(is_equal_approx(float(floor["elevation"]), 6.0))

	var request: Dictionary = {
		"module_id": 999,
		"width_modules": 0,
		"length_modules": 99,
		"floor_count": 40,
		"roof_type": "whatever",
		"position": [2, 0, -3],
		"rotation_degrees_y": 15.0,
		"name": "RuntimeBuilding"
	}
	var normalized: Dictionary = BuildingAPI.normalize_building_request(request)
	assert(normalized["module_id"] == 100)
	assert(normalized["requested_module_id"] == 999)
	assert(normalized["width_modules"] == BuildingAPI.MIN_WIDTH_MODULES)
	assert(normalized["length_modules"] == BuildingAPI.MAX_LENGTH_MODULES)
	assert(normalized["floor_count"] == BuildingAPI.MAX_FLOORS)
	assert(normalized["roof_type"] == BuildingAPI.ROOF_TYPE_FLAT)

	var style_request: Dictionary = BuildingAPI.normalize_building_request({
		"module_id": 102,
		"width_modules": 3,
		"floor_count": 2
	})
	assert(style_request["module_id"] == 102)

	var runtime_spec: Dictionary = BuildingAPI.create_building_spec_from_request({
		"module_id": 101,
		"width_modules": 4,
		"length_modules": 3,
		"floor_count": 3,
		"roof_type": BuildingAPI.ROOF_TYPE_PITCHED,
		"position": Vector3(1, 0, 2),
		"rotation_degrees_y": 30.0,
		"name": "RuntimeBuilding"
	})
	assert(runtime_spec["request"]["name"] == "RuntimeBuilding")
	assert(runtime_spec["request"]["width_modules"] == 4)
	assert(runtime_spec["request"]["length_modules"] == 3)
	assert(runtime_spec["roof_type"] == BuildingAPI.ROOF_TYPE_PITCHED)

	var building_node: Node3D = BuildingAPI.build_building_from_spec(runtime_spec)
	assert(building_node.name == "RuntimeBuilding")
	assert(building_node.position == Vector3(1, 0, 2))
	assert(is_equal_approx(building_node.rotation_degrees.y, 30.0))
	assert(building_node.get_child_count() == 4)
	assert(building_node.get_node("Floor_0").get_child_count() == 5)
	assert(building_node.get_node("Floor_0/Wall_0").get_child_count() == 4)
	assert(building_node.get_node("Floor_0/Corners").get_child_count() == 4)
	assert(building_node.get_node("Floor_0/Wall_0/Module_101_0/Arch_Glass_Center") != null)
	assert(building_node.get_node("Roof").get_child_count() >= 2)

	var runtime_node: Node3D = BuildingAPI.build_building_from_request({
		"module_id": 100,
		"width_modules": 2,
		"length_modules": 2,
		"floor_count": 2
	})
	assert(runtime_node.get_child_count() == 3)
	assert(runtime_node.get_node("Roof").get_child_count() == 1)

	var module_node: Node3D = BuildingAPI.build_module_node(100)
	var arch_module_node: Node3D = BuildingAPI.build_module_node(101)
	var checker_module_node: Node3D = BuildingAPI.build_module_node(102)
	var twin_module_node: Node3D = BuildingAPI.build_module_node(103)
	var corner_node: Node3D = BuildingAPI.build_corner_module_node(100)
	var flat_roof_node: Node3D = BuildingAPI.build_roof_module_node(BuildingAPI.ROOF_TYPE_FLAT)
	var pitched_roof_node: Node3D = BuildingAPI.build_roof_module_node(BuildingAPI.ROOF_TYPE_PITCHED)
	assert(module_node.get_child_count() == 10)
	assert(arch_module_node.get_node("Arch_Frame_Center") != null)
	assert(checker_module_node.get_node("Checker_Mullion_V_0") != null)
	assert(twin_module_node.get_node("Twin_Mullion_Center") != null)
	assert(corner_node.get_child_count() == 1)
	assert(flat_roof_node.get_child_count() == 1)
	assert(pitched_roof_node.get_child_count() >= 2)

	building_node.free()
	runtime_node.free()
	module_node.free()
	arch_module_node.free()
	checker_module_node.free()
	twin_module_node.free()
	corner_node.free()
	flat_roof_node.free()
	pitched_roof_node.free()
	BuildingAPI.clear_caches()
	print("building_api_headless_test: ok")
	quit(0)
