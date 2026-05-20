extends SceneTree

const CityGeneratorScript = preload("res://scripts/city_generator.gd")

func _init() -> void:
	var generator := CityGeneratorScript.new()
	generator.regenerate_on_ready = false
	generator.grid_size = Vector2i(3, 3)
	generator.block_size = 18.0
	generator.street_width = 6.0
	generator.use_barcelona_block_mix = true
	generator.barcelona_block_chance = 1.0
	generator.seed_value = 42
	generator.generate_city()
	assert(generator.get_child_count() == 1)
	var generated_root: Node3D = generator.get_node("GeneratedCity")
	var found_barcelona := false
	for child in generated_root.get_children():
		if String(child.name).begins_with("BarcelonaBlock_"):
			found_barcelona = true
	assert(found_barcelona)
	assert(generator._should_use_barcelona_block(1, 0, generator._district_kind_for_block(1, 0)) == true)
	var request: Dictionary = generator._make_barcelona_block_request(generator._block_band_x(1), generator._block_band_z(0), generator._block_top_height(1, 0), 1, 0, generator._district_kind_for_block(1, 0))
	assert(request["module_ids"].size() >= 2)
	assert(request["module_ids"].has(100))
	var slot_kinds: Array = []
	for slot in generator.get_building_slots_snapshot():
		slot_kinds.append(String(slot.get("kind", "")))
	assert(slot_kinds.has("civic_landmark") or slot_kinds.has("plaza"))
	var block_found: bool = false
	for block in generator.get_block_centers_snapshot():
		if bool(block.get("is_plaza", false)):
			block_found = true
			assert(String(block.get("district", "")).length() > 0)
	assert(block_found)

	var generator2 := CityGeneratorScript.new()
	generator2.regenerate_on_ready = false
	generator2.grid_size = Vector2i(2, 2)
	generator2.use_barcelona_block_mix = false
	generator2.barcelona_block_chance = 0.0
	generator2.seed_value = 42
	generator2.generate_city()
	var generated_root2: Node3D = generator2.get_node("GeneratedCity")
	for child in generated_root2.get_children():
		assert(not String(child.name).begins_with("BarcelonaBlock_"))
	var venue_found: bool = false
	for slot in generator2.get_building_slots_snapshot():
		if String(slot.get("venue_type", "")) != "":
			venue_found = true
			break
	assert(venue_found)

	generator.free()
	generator2.free()
	print("city_generator_barcelona_mix_test: ok")
	quit(0)
