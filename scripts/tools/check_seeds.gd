extends SceneTree
const CityGenerator = preload("res://scripts/city_generator.gd")
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(4, 4)
	city.seed_value = 42
	root.add_child(city)
	city.generate_city()
	var profiles: Array = city.get("_emissive_material_profiles")
	print("Profiles: %d" % profiles.size())
	var seeds: Dictionary = {}
	for p in profiles:
		var cat: String = str(p.get("category", "?"))
		var seed: int = int(p.get("seed", 0))
		var key: String = "%s_%d" % [cat, seed]
		seeds[key] = seeds.get(key, 0) + 1
	for key in seeds:
		print("  %s x%d" % [key, seeds[key]])
	# Apply midnight state
	var st := {"daylight": 0.0, "night": 1.0, "blue_hour": 0.0, "warm_hour": 0.0, "window_strength": 0.82, "storefront_strength": 0.0, "lamp_strength": 0.0, "window_color_bias": Color(0.98, 0.84, 0.66)}
	city.apply_lighting_state(st)
	print("\nAfter midnight state:")
	var house_count: int = 0
	var lit_count: int = 0
	for p in profiles:
		var cat: String = str(p.get("category", "?"))
		if cat != "house_window" and cat != "": continue
		house_count += 1
		var m = p.get("material")
		if m == null: continue
		if m.emission_energy_multiplier > 0.01: lit_count += 1
	print("House window profiles: %d, Lit at midnight: %d" % [house_count, lit_count])
	quit()
