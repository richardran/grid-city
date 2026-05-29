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

	var population := scene.get_node("Population")
	var crowd := scene.get_node("Crowd")
	var camera := scene.get_node("Camera3D")
	var ui := scene.get_node("PopulationUI")

	population.call("advance_hours", 24.0 * 180.0)
	await process_frame
	await process_frame

	var events: Array = population.call("get_recent_event_records", 12)
	var latest: Dictionary = {}
	for index in range(events.size() - 1, -1, -1):
		var candidate: Dictionary = events[index]
		if ["birth", "birthday", "marriage", "death"].has(str(candidate.get("type", ""))):
			latest = candidate
			break
	if latest.is_empty() and not events.is_empty():
		latest = events[events.size() - 1]
	if latest.is_empty():
		push_error("No recent event found for capture")
		quit(1)
		return

	crowd.call("play_life_event_effect", latest)
	await process_frame
	await process_frame

	var anchor := _latest_world_anchor(crowd)
	if anchor == Vector3.INF:
		push_error("No world event anchor found for capture")
		quit(1)
		return

	var tracked: Array = latest.get("person_ids", [])
	if tracked.is_empty() and int(latest.get("primary_person_id", -1)) != -1:
		tracked = [int(latest.get("primary_person_id", -1))]
	crowd.call("set_tracked_people", tracked)
	await process_frame
	await process_frame

	camera.call("set_view_mode", "ground")
	camera.position = anchor + Vector3(-5.5, -4.4, 9.0)
	camera.set("_yaw", atan2(anchor.x - camera.position.x, anchor.z - camera.position.z))
	await process_frame
	await process_frame
	_save_viewport_png("event_ground_view.png")

	camera.call("set_view_mode", "ground")
	camera.position = anchor + Vector3(-2.2, -4.9, 4.6)
	camera.set("_yaw", atan2(anchor.x - camera.position.x, anchor.z - camera.position.z))
	await process_frame
	await process_frame
	_save_viewport_png("event_ground_closeup.png")

	camera.call("set_view_mode", "overlook")
	camera.position = anchor + Vector3(-10.0, -2.0, 16.0)
	camera.set("_yaw", atan2(anchor.x - camera.position.x, anchor.z - camera.position.z))
	await process_frame
	await process_frame
	_save_viewport_png("event_overlook_view.png")

	ui.visible = false
	camera.call("set_view_mode", "ground")
	camera.position = anchor + Vector3(-2.2, -4.9, 4.6)
	camera.set("_yaw", atan2(anchor.x - camera.position.x, anchor.z - camera.position.z))
	await process_frame
	await process_frame
	_save_viewport_png("event_ground_clean.png")

	quit(0)


func _latest_world_anchor(crowd: Node) -> Vector3:
	for index in range(crowd.get_child_count() - 1, -1, -1):
		var child := crowd.get_child(index)
		if child is Node3D and String(child.name).begins_with("WorldEventAnchor_"):
			return (child as Node3D).global_position
	return Vector3.INF


func _save_viewport_png(filename: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image: Image = get_root().get_texture().get_image()
	var output_path: String = ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, filename])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	image.save_png(output_path)
	print(output_path)
