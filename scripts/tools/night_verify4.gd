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
	for test in [["EVENING", 0.4], ["NIGHT", 0.7], ["MIDNIGHT", 1.0]]:
		var label: String = test[0]
		var n: float = test[1]
		var st := {"daylight": 1.0-n, "night": n, "blue_hour": 0.0, "warm_hour": 0.0, "window_strength": 0.82, "storefront_strength": 0.0, "lamp_strength": 0.0, "window_color_bias": Color(0.98, 0.84, 0.66)}
		city.apply_lighting_state(st)
		var dark := 0; var lit := 0
		for p in profiles:
			var m = p.get("material")
			if m == null: continue
			var cat: String = str(p.get("category", ""))
			if cat != "house_window" and cat != "": continue
			if m.emission_energy_multiplier < 0.01: dark += 1
			else: lit += 1
		print("%s: lit=%d dark=%d" % [label, lit, dark])
