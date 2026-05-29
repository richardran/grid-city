extends SceneTree

const LegoBlockGenerator = preload("res://scripts/tools/lego_block_generator.gd")
const OUTPUT_SPEC_PATH := "res://outputs/lego_block_sample.json"

func _init() -> void:
	var spec: Dictionary = LegoBlockGenerator.create_block_spec_from_request({
		"module_id": 100,
		"block_width": 18.0,
		"block_depth": 18.0,
		"corner_size": 5.2,
		"bridge_depth": 3.2,
		"gap_size": 0.6,
		"floor_count": 4,
		"roof_type": "flat",
		"name": "LegoBlock_Sample"
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
