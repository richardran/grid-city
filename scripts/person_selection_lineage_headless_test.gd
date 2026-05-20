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
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 40
	population.max_population = 80
	population.hours_per_second = 72.0
	root.add_child(population)
	population.generate_population()

	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.population_path = NodePath("../Population")
	crowd.min_pedestrians = 6
	crowd.max_pedestrians = 10
	crowd.min_dogs = 0
	crowd.max_dogs = 0
	crowd.max_detailed_pedestrians = 0
	root.add_child(crowd)
	crowd.populate_now()

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 44.0, 36.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	root.add_child(camera)
	camera.current = true

	var ui := PopulationUI.new()
	ui.name = "PopulationUI"
	ui.population_path = NodePath("../Population")
	ui.crowd_path = NodePath("../Crowd")
	ui.camera_path = NodePath("../Camera3D")
	_build_ui_stub(ui)
	root.add_child(ui)

	await process_frame
	await process_frame

	var selected_id: int = -1
	for child in crowd.get_children():
		if child is Node3D:
			var identity: Dictionary = (child as Node3D).get_meta("identity", {})
			if identity.is_empty():
				continue
			var screen_pos: Vector2 = camera.unproject_position((child as Node3D).global_position + Vector3(0.0, 1.2, 0.0))
			var hit: Dictionary = crowd.pick_person_from_screen(camera, screen_pos, 48.0)
			selected_id = int(hit.get("person_id", -1))
			if selected_id != -1:
				ui.select_person(selected_id)
				break
	assert(selected_id != -1)

	var selection := ui.get_node("Panel/Margin/VBox/Selection") as RichTextLabel
	assert(selection != null)
	assert(selection.text.contains("[b]About[/b]"))
	assert(selection.text.contains("[b]Lineage[/b]"))
	assert(selection.text.contains("Parents:"))
	assert(selection.text.contains("Lineage members:"))
	print("person_selection_lineage_headless_test: ok")
	root.free()
	quit(0)


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

	var summary := RichTextLabel.new()
	summary.name = "Summary"
	vbox.add_child(summary)

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

	var selection := RichTextLabel.new()
	selection.name = "Selection"
	vbox.add_child(selection)

	var list := RichTextLabel.new()
	list.name = "List"
	vbox.add_child(list)

	var events := RichTextLabel.new()
	events.name = "Events"
	vbox.add_child(events)
