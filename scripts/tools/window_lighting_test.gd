extends SceneTree

## Renders city day/night views synchronously.

const CityGenerator = preload("res://scripts/city_generator.gd")

func _init() -> void:
	print("=== WINDOW LIGHTING TEST ===")
	var root := Node3D.new()
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(3, 3)
	city.seed_value = 42
	root.add_child(city)
	city.generate_city()
	print("City gen done")

	# Force one frame to render
	RenderingServer.force_draw()
	

	# Use the main viewport to capture
	var main_vp := get_root()
	# main_vp.size is set by engine

	# Position camera in main viewport
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(6, 4, 10)
	cam.look_at(Vector3(8, 1, 6))
	root.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.position = Vector3(10, 15, 5)
	sun.look_at(Vector3(0, 0, 0))
	sun.light_energy = 1.2
	root.add_child(sun)

	# Render DAY
	RenderingServer.force_draw()
	var day_img: Image = main_vp.get_texture().get_image()
	if day_img != null:
		day_img.save_png("user://window_test_day.png")
		print("Day saved: %dx%d" % [day_img.get_width(), day_img.get_height()])

	# Apply NIGHT
	var night_state := {
		"daylight": 0.0, "night": 1.0, "blue_hour": 0.0, "warm_hour": 0.0,
		"window_strength": 0.82, "storefront_strength": 0.6, "lamp_strength": 0.8,
		"window_color_bias": Color(0.98, 0.84, 0.66)
	}
	city.apply_lighting_state(night_state)
	sun.light_energy = 0.08
	sun.light_color = Color(0.2, 0.25, 0.4)

	RenderingServer.force_draw()
	var night_img: Image = main_vp.get_texture().get_image()
	if night_img != null:
		night_img.save_png("user://window_test_night.png")
		print("Night saved: %dx%d" % [night_img.get_width(), night_img.get_height()])

	print("=== DONE ===")
	quit()
