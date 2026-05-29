extends SceneTree

const BarcelonaBlockGenerator = preload("res://scripts/barcelona_block_generator.gd")

func _init() -> void:
	var spec: Dictionary = BarcelonaBlockGenerator.create_block_spec_from_request({
		"module_id": 100,
		"module_ids": [100, 101, 102, 103],
		"block_width": 18.0,
		"block_depth": 18.0,
		"bridge_depth": 3.2,
		"gap_size": 0.0,
		"floor_count": 4,
		"roof_type": "flat",
		"passage_side": "east",
		"name": "BarcelonaTest"
	})
	assert(spec["kind"] == "barcelona_block")
	assert(spec["footprint"]["width"] == 18.0)
	assert(spec["footprint"]["depth"] == 18.0)
	assert(spec["passage_side"] == "east")
	assert(spec["request"]["module_ids"].size() == 4)
	assert(spec["courtyard"]["width"] == 7.6)
	assert(spec["courtyard"]["depth"] == 7.6)
	assert(spec["buildings"].size() == 8)

	var east_segment: Dictionary = spec["buildings"][6]
	var west_segment: Dictionary = spec["buildings"][7]
	assert(spec["buildings"][1]["building_spec"]["module_id"] == 101)
	assert(spec["buildings"][2]["building_spec"]["module_id"] == 102)
	assert(spec["buildings"][3]["building_spec"]["module_id"] == 103)
	assert(east_segment["is_elevated"] == true)
	assert(float(east_segment["position"]["y"]) > 0.0)
	assert(is_equal_approx(float(east_segment["target_footprint"]["width"]), 7.6))
	assert(west_segment["is_elevated"] == false)
	assert(is_equal_approx(float(west_segment["target_footprint"]["width"]), 7.6))

	var normalized: Dictionary = BarcelonaBlockGenerator.normalize_request({
		"block_width": 200.0,
		"block_depth": 9.0,
		"bridge_depth": 99.0,
		"gap_size": -2.0,
		"module_id": 555,
		"module_ids": [555, 102, 102],
		"floor_count": 99,
		"roof_type": "weird",
		"passage_side": "bad"
	})
	assert(normalized["block_width"] == BarcelonaBlockGenerator.MAX_BLOCK_SIZE)
	assert(normalized["block_depth"] == BarcelonaBlockGenerator.MIN_BLOCK_SIZE)
	assert(normalized["gap_size"] == 0.0)
	assert(normalized["module_id"] == 100)
	assert(normalized["module_ids"].size() == 2)
	assert(normalized["module_ids"][1] == 102)
	assert(normalized["floor_count"] == 24)
	assert(normalized["roof_type"] == "flat")
	assert(normalized["passage_side"] == "north")

	var node: Node3D = BarcelonaBlockGenerator.build_block_from_spec(spec)
	assert(node.name == "BarcelonaTest")
	assert(node.get_child_count() == 8)
	assert(node.get_node("Building_East").position.y > 0.0)

	node.free()
	print("barcelona_block_generator_headless_test: ok")
	quit(0)
