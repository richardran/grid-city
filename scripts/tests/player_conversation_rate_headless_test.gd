extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")


func _init() -> void:
	var root := Node3D.new()
	root.name = "TestRoot"
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.name = "City"
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(3, 3)
	city.seed_value = 7
	root.add_child(city)
	city.generate_city()

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	root.add_child(camera)

	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.population_path = NodePath("../Population")
	crowd.camera_path = NodePath("../Camera3D")
	crowd.min_pedestrians = 14
	crowd.max_pedestrians = 18
	crowd.min_dogs = 0
	crowd.max_dogs = 0
	crowd.conversation_share = 0.0
	crowd.player_conversation_share = 1.0
	crowd.player_conversation_radius = 999.0
	crowd.player_conversation_cooldown = 0.1
	crowd.crowd_update_slices = 1
	root.add_child(crowd)
	crowd.populate_now()

	var internal_pedestrians: Array = crowd.get("_pedestrians")
	var ped_index: int = -1
	for idx in range(internal_pedestrians.size()):
		var ped: Dictionary = internal_pedestrians[idx]
		if String(ped.get("type", "")) == "dog" or String(ped.get("type", "")) == "":
			continue
		ped_index = idx
		break
	assert(ped_index >= 0)
	var ped_entry: Dictionary = internal_pedestrians[ped_index]
	var root_node: Node3D = ped_entry.get("root") as Node3D
	var focus: Vector3 = root_node.position if root_node != null else Vector3.ZERO
	camera.global_position = focus + Vector3(0.0, 1.0, 3.1)
	camera.look_at(focus, Vector3.UP)

	var seen_player_conversations: Dictionary = {}
	for cycle in range(3):
		var ped: Dictionary = internal_pedestrians[ped_index]
		var identity: Dictionary = ped.get("identity", {})
		var person_id: int = int(identity.get("id", -1))
		crowd.trigger_player_conversation_for_person(person_id)
		for entry in crowd.get_conversation_chat_snapshot():
			var data := Dictionary(entry)
			if bool(data.get("is_player", false)):
				seen_player_conversations[str(data.get("conversation_id", ""))] = true
		for step in range(16):
			crowd._process(0.2)
		_reset_pedestrian_for_retry(crowd, ped_index)

	assert(seen_player_conversations.size() >= 2)
	print("player_conversation_rate_headless_test: ok (%d player conversations)" % seen_player_conversations.size())
	root.free()
	quit(0)


func _reset_pedestrian_for_retry(crowd: Node, ped_index: int) -> void:
	var internal_pedestrians: Array = crowd.get("_pedestrians")
	if ped_index >= 0 and ped_index < internal_pedestrians.size():
		var ped: Dictionary = internal_pedestrians[ped_index]
		ped["speech_cooldown"] = 0.0
		ped["pause_time"] = 0.0
		ped["stuck_time"] = 0.0
		if ped.has("root") and ped["root"] != null:
			if crowd.camera_path != NodePath():
				var camera: Node = crowd.get_node(crowd.camera_path)
				if camera != null:
					ped["root"].position = camera.global_position + Vector3(0.0, 0.0, 2.0)
		internal_pedestrians[ped_index] = ped
