extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")
const PopulationUI = preload("res://scripts/population_ui.gd")

func _init() -> void:
	var root := Node3D.new()
	root.name = "TestRoot"
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.name = "City"
	city.regenerate_on_ready = false
	city.seed_value = 222333
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 50
	population.max_population = 80
	population.start_hour = 18.0
	root.add_child(population)
	population.generate_population()

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	root.add_child(camera)

	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.population_path = NodePath("../Population")
	crowd.camera_path = NodePath("../Camera3D")
	crowd.min_pedestrians = 12
	crowd.max_pedestrians = 16
	crowd.min_dogs = 0
	crowd.max_dogs = 0
	crowd.max_detailed_pedestrians = 0
	crowd.conversation_share = 0.0
	crowd.enable_llm_conversations = false
	root.add_child(crowd)
	crowd.populate_now()

	var ui := PopulationUI.new()
	ui.name = "PopulationUI"
	ui.population_path = NodePath("../Population")
	ui.crowd_path = NodePath("../Crowd")
	ui.camera_path = NodePath("../Camera3D")
	_build_ui_stub(ui)
	root.add_child(ui)

	await process_frame
	await process_frame

	var candidate: Dictionary = _visible_click_candidate(crowd, camera)
	assert(not candidate.is_empty())
	var person_id: int = int(candidate.get("person_id", -1))
	var ped_index: int = int(candidate.get("ped_index", -1))
	var screen_pos: Vector2 = Vector2(candidate.get("screen_pos", Vector2.ZERO))
	var speech_pos: Vector2 = Vector2(candidate.get("speech_pos", Vector2.ZERO))
	var clicked_position: Vector3 = Vector3(candidate.get("position", Vector3.ZERO))
	assert(person_id > 0)
	assert(ped_index >= 0)
	assert(get_root().get_visible_rect().has_point(speech_pos))

	ui.call("_pick_person_at_screen", screen_pos)
	assert(crowd.get_player_conversation_count() > 0)
	var pedestrians_after_click: Array = crowd.get("_pedestrians")
	var clicked_ped: Dictionary = Dictionary(pedestrians_after_click[ped_index])
	var clicked_identity: Dictionary = Dictionary(clicked_ped.get("identity", {}))
	assert(int(clicked_identity.get("id", -1)) == person_id)
	var clicked_root: Node3D = clicked_ped.get("root") as Node3D
	var click_position: Vector3 = clicked_root.global_position
	assert(click_position.distance_to(clicked_position) < 0.05)
	assert(float(clicked_ped.get("player_lock_time", 0.0)) > 0.0)
	for _step in range(8):
		crowd._process(0.2)
		ui._process(0.2)
	assert(int(ui.call("get_visible_chat_box_count")) == 1)
	var pedestrians_after_wait: Array = crowd.get("_pedestrians")
	var waited_ped: Dictionary = Dictionary(pedestrians_after_wait[ped_index])
	var waited_root: Node3D = waited_ped.get("root") as Node3D
	assert(waited_root.global_position.distance_to(click_position) < 0.05)
	assert(float(waited_ped.get("player_lock_time", 0.0)) > 0.0)

	_seed_pending_player_conversation(crowd, ped_index)
	var generated_lines: Array[String] = [
		"Visible click line one.",
		"Visible click line two.",
		"Visible click line three."
	]
	crowd.call("_finalize_openrouter_player_lines", ped_index, generated_lines, "ok")
	await process_frame
	ui.call("_update_conversation_boxes")

	assert(_speaker_is_visible(crowd, camera, ped_index))
	assert(int(ui.call("get_visible_chat_box_count")) == 1)
	var box := ui.get_node("ConversationOverlay/ChatBox0") as Control
	assert(box != null and box.visible)
	var label := box.get_node("BubbleMargin/Text") as Label
	assert(label.text.contains("Visible click line one."))
	assert(not label.text.contains("Visible click line two."))
	assert(not label.text.contains("Visible click line three."))

	for _step in range(12):
		crowd._process(0.2)
		ui._process(0.2)
	assert(label.text.contains("Visible click line one."))
	assert(label.text.contains("Visible click line two."))
	assert(not label.text.contains("Visible click line three."))

	for _step in range(12):
		crowd._process(0.2)
		ui._process(0.2)
	assert(label.text.contains("Visible click line one."))
	assert(label.text.contains("Visible click line two."))
	assert(label.text.contains("Visible click line three."))

	var viewport_rect: Rect2 = get_root().get_visible_rect()
	assert(viewport_rect.has_point(box.position + box.size * 0.5))

	print("speech_box_click_visibility_headless_test: ok")
	root.free()
	quit(0)


func _visible_click_candidate(crowd: Node, camera: Camera3D) -> Dictionary:
	var pedestrians: Array = crowd.get("_pedestrians")
	for ped_index in range(pedestrians.size()):
		var ped: Dictionary = Dictionary(pedestrians[ped_index])
		if str(ped.get("type", "")) == "dog":
			continue
		var root: Node3D = ped.get("root") as Node3D
		var identity: Dictionary = Dictionary(ped.get("identity", {}))
		if root == null or not is_instance_valid(root) or identity.is_empty():
			continue
		var focus: Vector3 = root.global_position + Vector3(0.0, 1.2, 0.0)
		camera.global_position = focus + Vector3(0.0, 0.85, 3.4)
		camera.look_at(focus, Vector3.UP)
		var screen_pos: Vector2 = camera.unproject_position(focus)
		var hit: Dictionary = crowd.call("pick_person_from_screen", camera, screen_pos, 48.0)
		if int(hit.get("person_id", -1)) == int(identity.get("id", -1)):
			return {
				"ped_index": ped_index,
				"person_id": int(identity.get("id", -1)),
				"screen_pos": screen_pos,
				"speech_pos": camera.unproject_position(root.global_position + Vector3(0.0, 1.55, 0.0)),
				"position": root.global_position
			}
	return {}


func _speaker_is_visible(crowd: Node, camera: Camera3D, ped_index: int) -> bool:
	var pedestrians: Array = crowd.get("_pedestrians")
	if ped_index < 0 or ped_index >= pedestrians.size():
		return false
	var ped: Dictionary = Dictionary(pedestrians[ped_index])
	var root: Node3D = ped.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		return false
	if camera.is_position_behind(root.global_position):
		return false
	return get_root().get_visible_rect().grow(42.0).has_point(camera.unproject_position(root.global_position))


func _seed_pending_player_conversation(crowd: Node, ped_index: int) -> void:
	crowd.set("_active_conversations", [
		{"id": "pending_click", "speaker_indices": [ped_index], "lines": [{"speaker_index": ped_index, "text": "..."}], "line_index": 0, "elapsed": 0.0, "line_duration": 2.2, "is_player": true, "llm_pending": true}
	])


func _build_ui_stub(ui: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	ui.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)

	for label_name in ["Summary", "Selection", "List", "Events"]:
		var label := RichTextLabel.new()
		label.name = label_name
		vbox.add_child(label)

	var controls := GridContainer.new()
	controls.name = "Controls"
	vbox.add_child(controls)
	for button_name in [
		"TogglePause",
		"CycleSpeed",
		"Advance6Hours",
		"AdvanceYear",
		"NextResident",
		"NextHousehold",
		"JumpToSelection",
		"ShowPopulation",
		"ShowHouseholds",
		"PrevPage",
		"NextPage"
	]:
		var button := Button.new()
		button.name = button_name
		controls.add_child(button)
	var spacer := Control.new()
	spacer.name = "Spacer"
	controls.add_child(spacer)
