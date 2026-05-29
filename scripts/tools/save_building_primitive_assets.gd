extends SceneTree

const BuildingAPI = preload("res://scripts/building_api.gd")

const MODULE_SCENE_PATHS := {
	100: "res://scenes/modules/module_100_single_window.tscn",
	101: "res://scenes/modules/module_101_arch_top.tscn",
	102: "res://scenes/modules/module_102_checker_glass.tscn",
	103: "res://scenes/modules/module_103_twin_window.tscn"
}
const CORNER_SCENE_PATH := "res://scenes/modules/module_100_corner_cap.tscn"
const FLAT_ROOF_SCENE_PATH := "res://scenes/modules/roof_flat_w4_l3.tscn"
const PITCHED_ROOF_SCENE_PATH := "res://scenes/modules/roof_pitched_w4_l3.tscn"

func _init() -> void:
	_ensure_parent_dir(str(MODULE_SCENE_PATHS[100]))
	for module_id in MODULE_SCENE_PATHS.keys():
		var scene_path: String = str(MODULE_SCENE_PATHS[module_id])
		_save_scene(BuildingAPI.build_module_node(int(module_id)), scene_path, "Module_%d" % int(module_id))
	_save_scene(BuildingAPI.build_corner_module_node(100), CORNER_SCENE_PATH, "Corner_100")
	_save_scene(BuildingAPI.build_roof_module_node(BuildingAPI.ROOF_TYPE_FLAT, BuildingAPI.DEFAULT_MODULE_WIDTH * 4.0, BuildingAPI.DEFAULT_MODULE_WIDTH * 3.0), FLAT_ROOF_SCENE_PATH, "Roof_Flat")
	_save_scene(BuildingAPI.build_roof_module_node(BuildingAPI.ROOF_TYPE_PITCHED, BuildingAPI.DEFAULT_MODULE_WIDTH * 4.0, BuildingAPI.DEFAULT_MODULE_WIDTH * 3.0), PITCHED_ROOF_SCENE_PATH, "Roof_Pitched")
	BuildingAPI.clear_caches()
	print("saved primitive assets")
	for module_id in MODULE_SCENE_PATHS.keys():
		print(ProjectSettings.globalize_path(str(MODULE_SCENE_PATHS[module_id])))
	print(ProjectSettings.globalize_path(CORNER_SCENE_PATH))
	print(ProjectSettings.globalize_path(FLAT_ROOF_SCENE_PATH))
	print(ProjectSettings.globalize_path(PITCHED_ROOF_SCENE_PATH))
	quit(0)


func _save_scene(root: Node3D, res_path: String, scene_name: String) -> void:
	root.name = scene_name
	_set_owner_recursive(root)
	var packed := PackedScene.new()
	var pack_result: int = packed.pack(root)
	assert(pack_result == OK)
	var save_result: int = ResourceSaver.save(packed, res_path)
	assert(save_result == OK)
	root.free()


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
