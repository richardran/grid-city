extends SceneTree
## Verifies: window materials go dark at night, warm glow colors
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
	
	# Check emissive profiles
	if not city.has_method("get_lighting_debug_snapshot"):
		print("FAIL: no lighting debug")
		quit(); return
	var snap: Dictionary = city.call("get_lighting_debug_snapshot")
	print("Profiles: %d" % snap.get("emissive_profiles", 0))
	
	# Check the emissive materials directly
	var profiles: Array = city.get("_emissive_material_profiles")
	print("Emissive profiles: %d" % profiles.size())
	
	# Apply night state
	var night_state := {
		"daylight": 0.0, "night": 1.0, "blue_hour": 0.0,
		"warm_hour": 0.0, "window_strength": 0.82,
		"storefront_strength": 0.92, "lamp_strength": 1.0,
		"window_color_bias": Color(0.98, 0.84, 0.66)
	}
	city.apply_lighting_state(night_state)
	
	# Re-read profiles and check brightness
	var dark_count: int = 0
	var bright_count: int = 0
	for p in profiles:
		var mat: StandardMaterial3D = p.get("material")
		if mat == null: continue
		if mat.emission_energy_multiplier < 0.05:
			dark_count += 1
		elif mat.emission_energy_multiplier > 0.1:
			bright_count += 1
	
	print("Dark windows: %d  Bright windows: %d" % [dark_count, bright_count])
	if dark_count > 0 and bright_count > 0:
		print("OK: Some windows dark, some bright at night")
	else:
		print("WARNING: All windows same brightness at night")
	
	# Check warm color
	var warm_samples: int = 0
	for p in profiles:
		var mat: StandardMaterial3D = p.get("material")
		if mat == null: continue
		if mat.emission.r > 0.8 and mat.emission.g < 0.7:  # warm = high red, lower green
			warm_samples += 1
	print("Warm-colored windows: %d / %d" % [warm_samples, profiles.size()])
	if warm_samples > profiles.size() * 0.5:
		print("OK: Most windows are warm-colored")
	else:
		print("WARNING: Windows not warm enough")
	
	# Now test daytime
	var day_state := {
		"daylight": 1.0, "night": 0.0, "blue_hour": 0.0,
		"warm_hour": 0.0, "window_strength": 0.1,
		"storefront_strength": 0.0, "lamp_strength": 0.0,
		"window_color_bias": Color(0.98, 0.84, 0.66)
	}
	city.apply_lighting_state(day_state)
	
	var day_bright: int = 0
	for p in profiles:
		var mat: StandardMaterial3D = p.get("material")
		if mat == null: continue
		if mat.emission_energy_multiplier > 0.02:
			day_bright += 1
	print("Daytime windows visible: %d (should be near 0)" % day_bright)
	if day_bright < profiles.size() * 0.1:
		print("OK: Windows nearly invisible during day")
	else:
		print("WARNING: Too many windows visible during day")
	
	print("=== NIGHT WINDOW TEST DONE ===")
	quit()
