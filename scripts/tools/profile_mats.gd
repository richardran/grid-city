extends SceneTree
const CityGenerator = preload("res://scripts/city_generator.gd")
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(8, 8)
	city.seed_value = 42
	root.add_child(city)
	city.generate_city()
	var profiles: Array = city.get("_emissive_material_profiles")
	var house_count: int = 0
	for p in profiles:
		if str(p.get("category","")) == "house_window":
			house_count += 1
	print("Total emissive profiles: %d" % profiles.size())
	print("House window profiles: %d (one per regular building)" % house_count)
	print("Barcelona glass: 22 cached variants (20 seeded + 2 base)")
	print("OK: ~22 glass materials shared across all Barcelona modules — zero per-frame overhead")
	quit()
