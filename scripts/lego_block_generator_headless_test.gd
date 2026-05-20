extends SceneTree

const LegoBlockGenerator = preload("res://scripts/lego_block_generator.gd")

func _init() -> void:
	var spec: Dictionary = LegoBlockGenerator.create_block_spec_from_request({
		"module_id": 100,
		"block_width": 18.0,
		"block_depth": 18.0,
		"corner_size": 5.2,
		"bridge_depth": 3.2,
		"gap_size": 0.6,
		"floor_count": 4,
		"roof_type": "flat",
		"name": "LegoBlockTest"
	})
	assert(spec["footprint"]["width"] == 18.0)
	assert(spec["footprint"]["depth"] == 18.0)
	assert(spec["buildings"].size() == 8)
	assert(spec["buildings"][4]["is_elevated"] == true)
	assert(spec["buildings"][6]["is_elevated"] == true)
	assert(spec["buildings"][4]["support_columns"].size() == 0)
	assert(spec["buildings"][6]["support_columns"].size() == 0)
	assert(spec["buildings"][4]["target_footprint"]["width"] == 7.6)
	assert(spec["buildings"][6]["target_footprint"]["width"] == 7.6)
	assert(spec["buildings"][1]["building_spec"]["floor_count"] == 5)
	assert(spec["buildings"][2]["building_spec"]["floor_count"] == 3)

	var node: Node3D = LegoBlockGenerator.build_block_from_spec(spec)
	assert(node.name == "LegoBlockTest")
	assert(node.get_child_count() == 8)
	for child in node.get_children():
		assert(not String(child.name).contains("Supports"))

	var normalized: Dictionary = LegoBlockGenerator.normalize_request({
		"block_width": 100.0,
		"block_depth": 6.0,
		"corner_size": 99.0,
		"bridge_depth": 0.2,
		"gap_size": 0.0,
		"module_id": 999,
		"floor_count": 99,
		"roof_type": "weird"
	})
	assert(normalized["block_width"] == LegoBlockGenerator.MAX_BLOCK_SIZE)
	assert(normalized["block_depth"] == LegoBlockGenerator.MIN_BLOCK_SIZE)
	assert(normalized["bridge_depth"] >= LegoBlockGenerator.MIN_BRIDGE_DEPTH)
	assert(normalized["module_id"] == 100)
	assert(normalized["floor_count"] == 24)
	assert(normalized["roof_type"] == "flat")

	node.free()
	print("lego_block_generator_headless_test: ok")
	quit(0)
