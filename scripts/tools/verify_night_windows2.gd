extends SceneTree
const CityGenerator = preload("res://scripts/city_generator.gd")
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(2, 2)
	city.seed_value = 42
	root.add_child(city)
	city.generate_city()
	var profiles: Array = city.get("_emissive_material_profiles")
	print("Total profiles: %d" % profiles.size())
	for p in profiles:
		var cat: String = str(p.get("category", "?"))
		var seed: int = int(p.get("seed", 0))
		var mat: StandardMaterial3D = p.get("material")
		if mat == null: continue
		print("  cat=%s seed=%d emiss=%.3f emission=(%.2f,%.2f,%.2f)" % [cat, seed, mat.emission_energy_multiplier, mat.emission.r, mat.emission.g, mat.emission.b])
		if profiles.size() > 10:
			break
	# Apply night
	var night_state := {"daylight": 0.0, "night": 1.0, "blue_hour": 0.0, "warm_hour": 0.0, "window_strength": 0.82, "storefront_strength": 0.0, "lamp_strength": 0.0, "window_color_bias": Color(0.98, 0.84, 0.66)}
	city.apply_lighting_state(night_state)
	print("\n--- After night state ---")
	var count: int = 0
	for p in profiles:
		var mat: StandardMaterial3D = p.get("material")
		if mat == null: continue
		print("  emiss=%.3f emission=(%.2f,%.2f,%.2f)" % [mat.emission_energy_multiplier, mat.emission.r, mat.emission.g, mat.emission.b])
		count += 1
		if count > 10: break
	quit()
