extends SceneTree

const BuildingAPI = preload("res://scripts/building_api.gd")
const OUTPUT_SCENE_PATH := "res://scenes/generated/building_100_w4_l3_f3.tscn"
const OUTPUT_SPEC_PATH := "res://outputs/building_100_w4_l3_f3.json"

func _init() -> void:
	_ensure_parent_dir(OUTPUT_SCENE_PATH)
	_ensure_parent_dir(OUTPUT_SPEC_PATH)

	var spec: Dictionary = BuildingAPI.create_building_spec(100, 4, 3, 3)
	var building: Node3D = BuildingAPI.build_building_from_spec(spec)
	building.name = "Building_100_W4_L3_F3"
	_set_owner_recursive(building)

	var packed := PackedScene.new()
	var pack_result: int = packed.pack(building)
	assert(pack_result == OK)
	var save_result: int = ResourceSaver.save(packed, OUTPUT_SCENE_PATH)
	assert(save_result == OK)

	var file := FileAccess.open(OUTPUT_SPEC_PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(spec, "\t"))
	file.close()

	print("generated scene: %s" % ProjectSettings.globalize_path(OUTPUT_SCENE_PATH))
	print("generated spec: %s" % ProjectSettings.globalize_path(OUTPUT_SPEC_PATH))
	print("summary: module=100 width=4 length=3 floors=3")

	building.free()
	BuildingAPI.clear_caches()
	quit(0)


func _ensure_parent_dir(res_path: String) -> void:
	var absolute_parent := ProjectSettings.globalize_path(res_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_parent)


func _set_owner_recursive(root: Node) -> void:
	for child in root.get_children():
		_assign_owner_recursive(child, root)


func _assign_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_assign_owner_recursive(child, owner)
