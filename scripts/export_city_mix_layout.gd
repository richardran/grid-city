extends SceneTree

const CityGeneratorScript = preload("res://scripts/city_generator.gd")
const OUTPUT_PATH := "res://outputs/city_mix_layout.json"

func _init() -> void:
	var generator := CityGeneratorScript.new()
	generator.regenerate_on_ready = false
	generator.grid_size = Vector2i(4, 4)
	generator.block_size = 18.0
	generator.street_width = 6.0
	generator.use_barcelona_block_mix = true
	generator.barcelona_block_chance = 0.4
	generator.seed_value = 1337
	generator.generate_city()

	var blocks: Array = []
	for gx in range(generator.grid_size.x):
		for gz in range(generator.grid_size.y):
			var x_band: Vector2 = generator._block_band_x(gx)
			var z_band: Vector2 = generator._block_band_z(gz)
			var block_top: float = generator._block_top_height(gx, gz)
			var style: String = "barcelona" if generator._should_use_barcelona_block(gx, gz) else "traditional"
			var block_data := {
				"gx": gx,
				"gz": gz,
				"x_band": {"x": x_band.x, "y": x_band.y},
				"z_band": {"x": z_band.x, "y": z_band.y},
				"style": style
			}
			if style == "barcelona":
				block_data["request"] = generator._make_barcelona_block_request(x_band, z_band, block_top, gx, gz)
			blocks.append(block_data)

	var payload := {
		"grid_size": {"x": generator.grid_size.x, "y": generator.grid_size.y},
		"block_size": generator.block_size,
		"street_width": generator.street_width,
		"blocks": blocks
	}
	_ensure_parent_dir(OUTPUT_PATH)
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	generator.free()
	print(ProjectSettings.globalize_path(OUTPUT_PATH))
	quit(0)


func _ensure_parent_dir(res_path: String) -> void:
	var absolute_parent := ProjectSettings.globalize_path(res_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_parent)
