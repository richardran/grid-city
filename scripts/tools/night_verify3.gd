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
	var night_state := {"daylight": 0.0, "night": 1.0, "blue_hour": 0.0, "warm_hour": 0.0, "window_strength": 0.82, "storefront_strength": 0.6, "lamp_strength": 0.8, "window_color_bias": Color(0.98, 0.84, 0.66)}
	city.apply_lighting_state(night_state)
	var dark:int=0; var bright:int=0; var warm:int=0
	for p in profiles:
		var m = p.get("material")
		if m == null: continue
		if m.emission_energy_multiplier < 0.01: dark+=1
		elif m.emission_energy_multiplier > 0.5: bright+=1
		if m.emission.r > 0.9 and m.emission.g < 0.7: warm+=1
		print("  emiss=%.3f col=(%.2f,%.2f,%.2f)" % [m.emission_energy_multiplier, m.emission.r, m.emission.g, m.emission.b])
	print("Dark: %d  Bright: %d  Warm-colored: %d / %d" % [dark, bright, warm, profiles.size()])
	if warm > profiles.size() * 0.3: print("OK: Warm windows confirmed")
	else: print("FAIL: Windows not warm enough")
	if bright > 5 and dark > 5: print("OK: Random darkening confirmed")
	else: print("FAIL: Not enough variation")
	quit()
