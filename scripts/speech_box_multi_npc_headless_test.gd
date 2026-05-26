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
	city.seed_value = 414243
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 70
	population.max_population = 100
	population.start_hour = 17.0
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

	var pair: Dictionary = _visible_pair(crowd, camera)
	assert(not pair.is_empty())
	var first: Dictionary = Dictionary(pair.get("first", {}))
	var second: Dictionary = Dictionary(pair.get("second", {}))
	var first_index: int = int(first.get("ped_index", -1))
	var second_index: int = int(second.get("ped_index", -1))
	assert(first_index >= 0 and second_index >= 0 and first_index != second_index)

	ui.call("_pick_person_at_screen", Vector2(first.get("screen_pos", Vector2.ZERO)))
	ui.call("_pick_person_at_screen", Vector2(second.get("screen_pos", Vector2.ZERO)))
	for _step in range(4):
		crowd._process(0.16)
		ui._process(0.16)
	_assert_two_pinned_boxes(crowd, ui, camera, first_index, second_index)

	ui.call("_pick_person_at_screen", Vector2(first.get("screen_pos", Vector2.ZERO)))
	for _step in range(4):
		crowd._process(0.16)
		ui._process(0.16)
	_assert_two_pinned_boxes(crowd, ui, camera, first_index, second_index)

	ui.call("_pick_person_at_screen", Vector2(second.get("screen_pos", Vector2.ZERO)))
	for _step in range(4):
		crowd._process(0.16)
		ui._process(0.16)
	_assert_two_pinned_boxes(crowd, ui, camera, first_index, second_index)

	print("speech_box_multi_npc_headless_test: ok")
	root.free()
	quit(0)


func _visible_pair(crowd: Node, camera: Camera3D) -> Dictionary:
	var pedestrians: Array = crowd.get("_pedestrians")
	for first_index in range(pedestrians.size()):
		var first: Dictionary = Dictionary(pedestrians[first_index])
		var first_root: Node3D = first.get("root") as Node3D
		if not _is_clickable_person(first, first_root):
			continue
		for second_index in range(first_index + 1, pedestrians.size()):
			var second: Dictionary = Dictionary(pedestrians[second_index])
			var second_root: Node3D = second.get("root") as Node3D
			if not _is_clickable_person(second, second_root):
				continue
			var midpoint: Vector3 = (first_root.global_position + second_root.global_position) * 0.5 + Vector3(0.0, 1.15, 0.0)
			var distance: float = first_root.global_position.distance_to(second_root.global_position)
			if distance < 1.0 or distance > 8.0:
				continue
			camera.look_at_from_position(midpoint + Vector3(0.0, 2.4, 7.0), midpoint, Vector3.UP)
			var first_focus: Vector3 = first_root.global_position + Vector3(0.0, 1.2, 0.0)
			var second_focus: Vector3 = second_root.global_position + Vector3(0.0, 1.2, 0.0)
			if camera.is_position_behind(first_focus) or camera.is_position_behind(second_focus):
				continue
			var first_screen: Vector2 = camera.unproject_position(first_focus)
			var second_screen: Vector2 = camera.unproject_position(second_focus)
			var viewport_rect: Rect2 = get_root().get_visible_rect()
			if not viewport_rect.has_point(first_screen) or not viewport_rect.has_point(second_screen):
				continue
			if first_screen.distance_to(second_screen) < 90.0:
				continue
			var first_hit: Dictionary = crowd.call("pick_person_from_screen", camera, first_screen, 48.0)
			var second_hit: Dictionary = crowd.call("pick_person_from_screen", camera, second_screen, 48.0)
			if int(first_hit.get("ped_index", -1)) != first_index or int(second_hit.get("ped_index", -1)) != second_index:
				continue
			return {
				"first": {"ped_index": first_index, "screen_pos": first_screen},
				"second": {"ped_index": second_index, "screen_pos": second_screen}
			}
	return {}


func _assert_two_pinned_boxes(crowd: Node, ui: CanvasLayer, camera: Camera3D, first_index: int, second_index: int) -> void:
	var snapshot: Array = crowd.call("get_conversation_chat_snapshot")
	assert(_snapshot_has_speaker(snapshot, first_index))
	assert(_snapshot_has_speaker(snapshot, second_index))
	ui.call("_update_conversation_boxes")
	assert(int(ui.call("get_visible_chat_box_count")) >= 2)
	assert(_visible_box_for_speaker(ui, camera, crowd, first_index))
	assert(_visible_box_for_speaker(ui, camera, crowd, second_index))


func _snapshot_has_speaker(snapshot: Array, ped_index: int) -> bool:
	for entry in snapshot:
		if int(Dictionary(entry).get("speaker_index", -1)) == ped_index:
			return true
	return false


func _visible_box_for_speaker(ui: CanvasLayer, camera: Camera3D, crowd: Node, ped_index: int) -> bool:
	var pedestrians: Array = crowd.get("_pedestrians")
	var ped: Dictionary = Dictionary(pedestrians[ped_index])
	var root: Node3D = ped.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		return false
	var head_screen: Vector2 = camera.unproject_position(root.global_position + Vector3(0.0, 1.55, 0.0))
	for index in range(int(ui.call("get_chat_box_count"))):
		var box := ui.get_node("ConversationOverlay/ChatBox%d" % index) as Control
		if box == null or not box.visible:
			continue
		var center: Vector2 = box.position + box.size * 0.5
		var bottom_center: Vector2 = box.position + Vector2(box.size.x * 0.5, box.size.y)
		if abs(center.x - head_screen.x) <= 130.0 and abs(bottom_center.y - (head_screen.y - 10.0)) <= 70.0:
			return true
	return false


func _is_clickable_person(ped: Dictionary, root: Node3D) -> bool:
	return str(ped.get("type", "")) != "dog" and root != null and is_instance_valid(root) and not Dictionary(ped.get("identity", {})).is_empty()


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
