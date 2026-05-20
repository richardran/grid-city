extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const OUT_DIR := "res://outputs"

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var scene := MAIN_SCENE.instantiate()
	get_root().add_child(scene)
	for _step in range(6):
		await process_frame

	var city := scene.get_node("City")
	var population := scene.get_node("Population")
	var camera := scene.get_node("Camera3D")
	var atmosphere := scene.get_node("Atmosphere")
	var ui := scene.get_node("PopulationUI")
	var title := scene.get_node_or_null("PreviewLabel")
	ui.visible = false
	if title != null:
		title.visible = false

	var focus := Vector3.ZERO
	for slot in city.call("get_building_slots_snapshot"):
		if ["plaza", "civic_landmark"].has(String(slot.get("kind", ""))):
			focus = Vector3(slot.get("entry", slot.get("center", Vector3.ZERO)))
			break

	var summary: Dictionary = population.call("get_population_summary")
	var current_hour: float = float(summary.get("hour", 8.0))
	population.call("advance_hours", fposmod(19.35 - current_hour + 24.0, 24.0))
	for _step in range(10):
		await process_frame
	atmosphere.call("apply_atmosphere")
	camera.call("set_view_mode", "ground")
	camera.position = focus + Vector3(-7.4, 4.8, 10.8)
	camera.set("_yaw", atan2(focus.x - camera.position.x, focus.z - camera.position.z))
	camera.rotation.x = -0.36
	for _step in range(4):
		await process_frame
	await _save_viewport_png("city_life_blue_hour_moon.png")
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
