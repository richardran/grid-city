extends SceneTree

## Attempts to render the city day/night to PNG files for visual verification.

const CityGenerator = preload("res://scripts/city_generator.gd")

func _init() -> void:
	print("=== RENDER TEST ===")
	var root := Node3D.new()
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(3, 3)
	city.seed_value = 42
	root.add_child(city)
	city.generate_city()
	print("City done")

	# Camera and lights
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(6, 3, 10)
	cam.look_at(Vector3(8, 1, 6))
	root.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.position = Vector3(10, 15, 5)
	sun.look_at(Vector3(-1, 0, 0))
	sun.light_energy = 1.2
	root.add_child(sun)

	# Force a render frame
	RenderingServer.force_draw()

	# Read back the texture
	var main_vp = get_root()
	if main_vp and main_vp.has_method("get_texture"):
		var tex = main_vp.get_texture()
		if tex:
			var img = tex.get_image()
			if img:
				img.save_png("user://render_test.png")
				print("SAVED render_test.png: %dx%d" % [img.get_width(), img.get_height()])
			else:
				print("FAIL: get_image returned null")
		else:
			print("FAIL: get_texture returned null")
	else:
		print("FAIL: root has no get_texture method")
	print("=== DONE ===")
	quit()
