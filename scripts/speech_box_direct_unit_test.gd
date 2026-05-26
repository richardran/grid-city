extends SceneTree

const PopulationUI = preload("res://scripts/population_ui.gd")

class FakeCrowd:
	extends Node
	var snapshot: Array = []

	func get_conversation_chat_snapshot() -> Array:
		return snapshot


func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.look_at_from_position(Vector3(0.0, 1.55, 4.0), Vector3(0.0, 1.55, 0.0), Vector3.UP)
	root.add_child(camera)

	var crowd := FakeCrowd.new()
	crowd.name = "Crowd"
	root.add_child(crowd)

	var ui := PopulationUI.new()
	ui.name = "PopulationUI"
	ui.crowd_path = NodePath("../Crowd")
	ui.camera_path = NodePath("../Camera3D")
	_build_ui_stub(ui)
	root.add_child(ui)
	await process_frame

	crowd.snapshot = [{
		"speaker_index": 0,
		"speaker_position": Vector3(0.0, 1.55, 0.0),
		"text": "hello\nthere",
		"is_player": true
	}]
	ui.call("_update_conversation_boxes")
	assert(int(ui.call("get_visible_chat_box_count")) == 1)
	var box := ui.get_node("ConversationOverlay/ChatBox0") as Control
	assert(box.visible)
	var label := box.get_node("BubbleMargin/Text") as Label
	assert(label.text == "hello\nthere")

	crowd.snapshot = [{
		"speaker_index": 0,
		"speaker_position": Vector3(0.0, 1.55, 10.0),
		"text": "hidden",
		"is_player": true
	}]
	ui.call("_update_conversation_boxes")
	assert(int(ui.call("get_visible_chat_box_count")) == 0)

	print("speech_box_direct_unit_test: ok")
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
