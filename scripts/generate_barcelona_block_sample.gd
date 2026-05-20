extends SceneTree

const BarcelonaBlockGenerator = preload("res://scripts/barcelona_block_generator.gd")
const OUTPUT_SPEC_PATH := "res://outputs/barcelona_block_sample.json"

func _init() -> void:
	var spec: Dictionary = BarcelonaBlockGenerator.create_block_spec_from_request({
		"module_id": 100,
		"module_ids": [100, 101, 102, 103],
		"block_width": 18.0,
		"block_depth": 18.0,
		"edge_depth": 4.0,
		"floor_count": 4,
		"roof_type": "flat",
		"name": "BarcelonaBlock_Sample"
	})
	_ensure_parent_dir(OUTPUT_SPEC_PATH)
	var file := FileAccess.open(OUTPUT_SPEC_PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(spec, "\t"))
	file.close()
	print(ProjectSettings.globalize_path(OUTPUT_SPEC_PATH))
	quit(0)


func _ensure_parent_dir(res_path: String) -> void:
	var absolute_parent := ProjectSettings.globalize_path(res_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_parent)
