extends SceneTree
const CityGenerator = preload("res://scripts/city_generator.gd")
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(3, 3)
	city.seed_value = 42
	root.add_child(city)
	city.generate_city()
	var profiles: Array = city.get("_emissive_material_profiles")
	var st := {"daylight": 0.0, "night": 1.0, "blue_hour": 0.0, "warm_hour": 0.0, "window_strength": 0.82, "storefront_strength": 0.0, "lamp_strength": 0.0, "window_color_bias": Color(0.98, 0.84, 0.66)}
	city.apply_lighting_state(st)
	# Show house_window profiles with index and emiss
	var idx: int = 0
	for p in profiles:
		var cat: String = str(p.get("category", "?"))
		if cat != "house_window": continue
		var pi: int = int(p.get("profile_index", -1))
		var seed: int = int(p.get("seed", 0))
		var m = p.get("material")
		if m == null: continue
		print("idx=%d pi=%d seed=%d emiss=%.3f" % [idx, pi, seed, m.emission_energy_multiplier])
		idx += 1
		if idx >= 20: break
	quit()
