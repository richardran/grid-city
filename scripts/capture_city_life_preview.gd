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

	var city := scene.get_node("City")
	var population := scene.get_node("Population")
	var camera := scene.get_node("Camera3D")
	var ui := scene.get_node("PopulationUI")
	var title := scene.get_node_or_null("PreviewLabel")
	var atmosphere := scene.get_node_or_null("Atmosphere")

	ui.visible = false
	if title != null:
		title.visible = false

	var slots: Array = city.call("get_building_slots_snapshot")
	var venue_slot: Dictionary = {}
	var plaza_slot: Dictionary = {}
	for slot in slots:
		if venue_slot.is_empty() and ["coffee_shop", "bookstore"].has(String(slot.get("venue_type", ""))):
			venue_slot = slot
		if plaza_slot.is_empty() and ["plaza", "civic_landmark"].has(String(slot.get("kind", ""))):
			plaza_slot = slot
	if venue_slot.is_empty():
		push_error("No coffee shop or bookstore slot found for preview capture")
		quit(1)
		return
	if plaza_slot.is_empty():
		plaza_slot = venue_slot

	await _capture_view(population, camera, atmosphere, Vector3(venue_slot.get("entry", Vector3.ZERO)), 6.3, "city_life_sunrise.png")
	await _capture_view(population, camera, atmosphere, Vector3(plaza_slot.get("entry", plaza_slot.get("center", Vector3.ZERO))), 18.55, "city_life_sunset.png")
	await _capture_view(population, camera, atmosphere, Vector3(plaza_slot.get("entry", plaza_slot.get("center", Vector3.ZERO))), 19.35, "city_life_blue_hour_moon.png")
	await _capture_view(population, camera, atmosphere, Vector3(venue_slot.get("entry", venue_slot.get("center", Vector3.ZERO))), 21.2, "city_life_night_lamps.png")
	quit(0)


func _capture_view(population: Node, camera: Camera3D, atmosphere: Node, focus: Vector3, target_hour: float, filename: String) -> void:
	if population.has_method("get_population_summary") and population.has_method("advance_hours"):
		var summary: Dictionary = population.call("get_population_summary")
		var current_hour: float = float(summary.get("hour", 8.0))
		var delta_hours: float = fposmod(target_hour - current_hour + 24.0, 24.0)
		population.call("advance_hours", delta_hours)
	for _step in range(6):
		await process_frame
	if atmosphere != null and atmosphere.has_method("apply_atmosphere"):
		atmosphere.call("apply_atmosphere")
	camera.call("set_view_mode", "ground")
	camera.position = focus + Vector3(-7.8, 4.4, 9.4)
	camera.set("_yaw", atan2(focus.x - camera.position.x, focus.z - camera.position.z))
	camera.rotation.x = -0.30
	for _step in range(3):
		await process_frame
	await _save_viewport_png(filename)


func _save_viewport_png(filename: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image: Image = get_root().get_texture().get_image()
	var output_path: String = ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, filename])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	image.save_png(output_path)
	print(output_path)
