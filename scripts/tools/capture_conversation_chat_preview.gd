extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const OUT_PATH := "res://outputs/conversation_chat_preview.png"

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var scene := MAIN_SCENE.instantiate()
	get_root().add_child(scene)
	for _step in range(6):
		await process_frame
	var crowd := scene.get_node("Crowd")
	var camera := scene.get_node("Camera3D") as Camera3D
	var ui := scene.get_node("PopulationUI")
	ui.visible = true
	var internal: Array = crowd.get("_pedestrians")
	var selected_index: int = -1
	for idx in range(internal.size()):
		var ped: Dictionary = internal[idx]
		if String(ped.get("type", "")) == "dog":
			continue
		selected_index = idx
		break
	if selected_index == -1:
		push_error("Not enough pedestrians for chat preview")
		quit(1)
		return
	var ped: Dictionary = internal[selected_index]
	var root_ped: Node3D = ped.get("root") as Node3D
	var focus: Vector3 = root_ped.position + Vector3(0.0, 1.2, 0.0)
	camera.call("set_view_mode", "ground")
	camera.position = focus + Vector3(-1.2, 0.9, 3.2)
	camera.look_at(focus, Vector3.UP)
	crowd.call("_start_player_conversation", selected_index)
	for _step in range(10):
		await process_frame
	await _save_png()
	quit(0)


func _save_png() -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var image: Image = get_root().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print(ProjectSettings.globalize_path(OUT_PATH))
