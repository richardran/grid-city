extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert(scene != null)
	var main := scene.instantiate()
	get_root().add_child(main)

	var population := main.get_node("Population")
	var crowd := main.get_node("Crowd")
	var atmosphere := main.get_node("Atmosphere")
	var ui := main.get_node("PopulationUI")
	assert(population != null)
	assert(crowd != null)
	assert(atmosphere != null)
	assert(ui != null)

	await process_frame
	await process_frame

	assert(population.has_method("get_population_summary"))
	var summary: Dictionary = population.call("get_population_summary")
	assert(int(summary.get("population", 0)) > 0)
	assert(crowd.has_method("get_pedestrian_count"))
	assert(int(crowd.call("get_pedestrian_count")) > 0)
	assert(atmosphere.has_method("apply_atmosphere"))
	atmosphere.call("apply_atmosphere")

	var summary_label := ui.get_node("Panel/Margin/VBox/Summary")
	var list_label := ui.get_node("Panel/Margin/VBox/List")
	var show_population_button := ui.get_node("Panel/Margin/VBox/Controls/ShowPopulation")
	var show_households_button := ui.get_node("Panel/Margin/VBox/Controls/ShowHouseholds")
	assert(summary_label != null)
	assert(list_label != null)
	assert(show_population_button != null)
	assert(show_households_button != null)

	var selection_before := (ui.get_node("Panel/Margin/VBox/Selection") as RichTextLabel).text
	ui.call("_on_next_resident")
	var selection_after_resident := (ui.get_node("Panel/Margin/VBox/Selection") as RichTextLabel).text
	assert(selection_after_resident != "")
	assert(selection_after_resident != selection_before)
	ui.call("_on_next_household")
	var selection_after_household := (ui.get_node("Panel/Margin/VBox/Selection") as RichTextLabel).text
	assert(selection_after_household != selection_after_resident)
	print("main_scene_headless_test: ok")
	main.free()
	quit(0)
