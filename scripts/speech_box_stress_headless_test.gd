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
	city.seed_value = 303404
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 80
	population.max_population = 120
	population.start_hour = 17.5
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
	crowd.min_pedestrians = 18
	crowd.max_pedestrians = 24
	crowd.min_dogs = 0
	crowd.max_dogs = 0
	crowd.max_detailed_pedestrians = 0
	crowd.conversation_share = 0.0
	crowd.player_conversation_share = 0.0
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

	var tested_count: int = 0
	for ped_index in _candidate_indices(crowd):
		if tested_count >= 6:
			break
		crowd.set("_active_conversations", [])
		var candidate: Dictionary = _visible_click_candidate(crowd, camera, int(ped_index))
		if candidate.is_empty():
			continue
		_run_click_case(crowd, ui, camera, candidate, tested_count)
		tested_count += 1

	assert(tested_count >= 3)
	print("speech_box_stress_headless_test: ok (%d clicks)" % tested_count)
	root.free()
	quit(0)


func _run_click_case(crowd: Node, ui: CanvasLayer, camera: Camera3D, candidate: Dictionary, case_index: int) -> void:
	var ped_index: int = int(candidate.get("ped_index", -1))
	var person_id: int = int(candidate.get("person_id", -1))
	var screen_pos: Vector2 = Vector2(candidate.get("screen_pos", Vector2.ZERO))
	var start_position: Vector3 = Vector3(candidate.get("position", Vector3.ZERO))
	assert(ped_index >= 0)
	assert(person_id > 0)

	ui.call("_pick_person_at_screen", screen_pos)
	ui.call("_update_ui")
	for _step in range(4):
		crowd._process(0.16)
		ui._process(0.16)

	var pedestrians_after_click: Array = crowd.get("_pedestrians")
	var clicked_ped: Dictionary = Dictionary(pedestrians_after_click[ped_index])
	var clicked_root: Node3D = clicked_ped.get("root") as Node3D
	assert(clicked_root != null and is_instance_valid(clicked_root))
	assert(clicked_root.global_position.distance_to(start_position) < 0.05)
	assert(float(clicked_ped.get("player_lock_time", 0.0)) > 0.0)
	assert(int(Dictionary(clicked_ped.get("identity", {})).get("id", -1)) == person_id)
	assert(crowd.get_player_conversation_count() == 1)
	assert(int(ui.call("get_visible_chat_box_count")) == 1)

	var pending_label := _visible_chat_text(ui).strip_edges()
	assert(pending_label != "")

	var lines: Array[String] = [
		"Stress click %d line one." % case_index,
		"Stress click %d line two." % case_index,
		"Stress click %d line three." % case_index
	]
	_seed_pending_player_conversation(crowd, ped_index)
	crowd.call("_finalize_openrouter_player_lines", ped_index, lines, "ok")
	for _step in range(3):
		crowd._process(0.16)
		ui._process(0.16)

	var visible_text: String = _visible_chat_text(ui)
	assert(visible_text.contains(lines[0]))
	assert(not visible_text.contains(lines[1]))
	assert(not visible_text.contains(lines[2]))
	assert(int(ui.call("get_visible_chat_box_count")) == 1)
	assert(_speaker_is_visible(crowd, camera, ped_index))
	assert(_box_is_in_view(ui))

	for _step in range(15):
		crowd._process(0.16)
		ui._process(0.16)
	visible_text = _visible_chat_text(ui)
	assert(visible_text.contains(lines[0]))
	assert(visible_text.contains(lines[1]))
	assert(not visible_text.contains(lines[2]))

	for _step in range(15):
		crowd._process(0.16)
		ui._process(0.16)
	visible_text = _visible_chat_text(ui)
	assert(visible_text.contains(lines[0]))
	assert(visible_text.contains(lines[1]))
	assert(visible_text.contains(lines[2]))

	var focus: Vector3 = clicked_root.global_position + Vector3(0.0, 1.2, 0.0)
	camera.look_at_from_position(focus + Vector3(0.0, 0.85, -3.4), focus + Vector3(0.0, 0.0, -8.0), Vector3.UP)
	ui.call("_update_conversation_boxes")
	assert(int(ui.call("get_visible_chat_box_count")) == 0)

	camera.look_at_from_position(focus + Vector3(0.0, 0.85, 3.4), focus, Vector3.UP)
	ui.call("_update_conversation_boxes")
	assert(int(ui.call("get_visible_chat_box_count")) == 1)
	assert(_visible_chat_text(ui).contains(lines[2]))


func _candidate_indices(crowd: Node) -> Array[int]:
	var indices: Array[int] = []
	var pedestrians: Array = crowd.get("_pedestrians")
	for ped_index in range(pedestrians.size()):
		var ped: Dictionary = Dictionary(pedestrians[ped_index])
		if str(ped.get("type", "")) == "dog":
			continue
		if Dictionary(ped.get("identity", {})).is_empty():
			continue
		indices.append(ped_index)
	return indices


func _visible_click_candidate(crowd: Node, camera: Camera3D, ped_index: int) -> Dictionary:
	var pedestrians: Array = crowd.get("_pedestrians")
	if ped_index < 0 or ped_index >= pedestrians.size():
		return {}
	var ped: Dictionary = Dictionary(pedestrians[ped_index])
	var root: Node3D = ped.get("root") as Node3D
	var identity: Dictionary = Dictionary(ped.get("identity", {}))
	if root == null or not is_instance_valid(root) or identity.is_empty():
		return {}
	var focus: Vector3 = root.global_position + Vector3(0.0, 1.2, 0.0)
	camera.look_at_from_position(focus + Vector3(0.0, 0.85, 3.4), focus, Vector3.UP)
	var screen_pos: Vector2 = camera.unproject_position(focus)
	var hit: Dictionary = crowd.call("pick_person_from_screen", camera, screen_pos, 48.0)
	if int(hit.get("ped_index", -1)) != ped_index:
		return {}
	return {
		"ped_index": ped_index,
		"person_id": int(identity.get("id", -1)),
		"screen_pos": screen_pos,
		"position": root.global_position
	}


func _speaker_is_visible(crowd: Node, camera: Camera3D, ped_index: int) -> bool:
	var pedestrians: Array = crowd.get("_pedestrians")
	if ped_index < 0 or ped_index >= pedestrians.size():
		return false
	var ped: Dictionary = Dictionary(pedestrians[ped_index])
	var root: Node3D = ped.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		return false
	var point: Vector3 = root.global_position + Vector3(0.0, 1.55, 0.0)
	if camera.is_position_behind(point):
		return false
	return get_root().get_visible_rect().has_point(camera.unproject_position(point))


func _seed_pending_player_conversation(crowd: Node, ped_index: int) -> void:
	crowd.set("_active_conversations", [
		{"id": "pending_stress", "speaker_indices": [ped_index], "lines": [{"speaker_index": ped_index, "text": "..."}], "line_index": 0, "elapsed": 0.0, "line_duration": 2.2, "is_player": true, "llm_pending": true}
	])


func _box_is_in_view(ui: CanvasLayer) -> bool:
	var box := ui.get_node("ConversationOverlay/ChatBox0") as Control
	if box == null or not box.visible:
		return false
	return get_root().get_visible_rect().has_point(box.position + box.size * 0.5)


func _visible_chat_text(ui: CanvasLayer) -> String:
	for index in range(int(ui.call("get_chat_box_count"))):
		var box := ui.get_node("ConversationOverlay/ChatBox%d" % index) as Control
		if box != null and box.visible:
			var label := box.get_node("BubbleMargin/Text") as Label
			if label != null:
				return label.text
	return ""


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
