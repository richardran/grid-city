extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const OUT_DIR := "res://outputs"

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var scene := MAIN_SCENE.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	await process_frame

	var crowd := scene.get_node("Crowd")
	var camera := scene.get_node("Camera3D")
	var ui := scene.get_node("PopulationUI")
	var title := scene.get_node_or_null("PreviewLabel")

	for _step in range(20):
		await process_frame

	var dog_nodes: Array[Node3D] = []
	for child in crowd.get_children():
		if child is Node3D and String(child.name).begins_with("Dog_"):
			dog_nodes.append(child as Node3D)
	if dog_nodes.is_empty():
		push_error("No dogs found for preview capture")
		quit(1)
		return

	var center := Vector3.ZERO
	var sample_count: int = mini(4, dog_nodes.size())
	for index in range(sample_count):
		center += dog_nodes[index].global_position
	center /= float(sample_count)

	ui.visible = false
	if title != null:
		title.visible = false
	camera.call("set_view_mode", "ground")
	camera.position = center + Vector3(-8.0, 4.8, 9.2)
	camera.set("_yaw", atan2(center.x - camera.position.x, center.z - camera.position.z))
	camera.rotation.x = -0.32
	await process_frame
	await process_frame
	_save_viewport_png("dog_city_preview.png")

	camera.call("set_view_mode", "overlook")
	camera.position = center + Vector3(-12.0, 10.0, 14.0)
	camera.set("_yaw", atan2(center.x - camera.position.x, center.z - camera.position.z))
	camera.rotation.x = -0.54
	await process_frame
	await process_frame
	_save_viewport_png("dog_city_overlook_preview.png")

	quit(0)


func _save_viewport_png(filename: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image: Image = get_root().get_texture().get_image()
	var output_path: String = ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, filename])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	image.save_png(output_path)
	print(output_path)
