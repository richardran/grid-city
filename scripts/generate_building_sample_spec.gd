extends SceneTree

const BuildingAPI = preload("res://scripts/building_api.gd")
const OUTPUT_SPEC_PATH := "res://outputs/building_sample_latest.json"

func _init() -> void:
	var request := {
		"module_id": 100,
		"width_modules": 4,
		"length_modules": 3,
		"floor_count": 3,
		"roof_type": "flat",
		"name": "Building_Sample_Latest"
	}
	var spec: Dictionary = BuildingAPI.create_building_spec_from_request(request)
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
