extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")

func _init() -> void:
	var root := Node3D.new()
	root.name = "TestRoot"
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.name = "City"
	city.regenerate_on_ready = false
	city.seed_value = 424242
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 60
	population.max_population = 90
	population.start_hour = 18.0
	population.hours_per_second = 72.0
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
	crowd.min_pedestrians = 14
	crowd.max_pedestrians = 18
	crowd.min_dogs = 0
	crowd.max_dogs = 0
	crowd.conversation_share = 0.0
	root.add_child(crowd)
	crowd.populate_now()
	crowd.call("_resolve_camera")

	await process_frame
	await process_frame

	var candidate: Dictionary = _best_candidate(crowd)
	assert(not candidate.is_empty())
	var ped_index: int = int(candidate.get("ped_index", -1))
	var focus: Vector3 = Vector3(candidate.get("focus", Vector3.ZERO))
	assert(ped_index >= 0)
	camera.global_position = focus + Vector3(0.0, 1.0, 3.1)
	camera.look_at(focus, Vector3.UP)

	var seen_player_conversations: Dictionary = {}
	for _cycle in range(3):
		crowd.call("_start_player_conversation", ped_index)
		for entry in crowd.get_conversation_chat_snapshot():
			var data := Dictionary(entry)
			if bool(data.get("is_player", false)):
				seen_player_conversations[str(data.get("conversation_id", ""))] = true
		for _step in range(16):
			crowd._process(0.2)
		_reset_pedestrian_for_retry(crowd, ped_index)

	assert(seen_player_conversations.size() >= 2)
	print("player_conversation_rate_headless_test: ok (%d player conversations)" % seen_player_conversations.size())
	root.free()
	quit(0)


func _best_candidate(crowd: Node) -> Dictionary:
	var internal: Array = crowd.get("_pedestrians")
	for ped_index in range(internal.size()):
		var data := Dictionary(internal[ped_index])
		if String(data.get("type", "")) == "dog":
			continue
		var root: Node3D = data.get("root") as Node3D
		var identity: Dictionary = data.get("identity", {})
		if root != null and is_instance_valid(root) and not identity.is_empty():
			return {
				"ped_index": ped_index,
				"focus": root.global_position + Vector3(0.0, 1.3, 0.0)
			}
	return {}


func _reset_pedestrian_for_retry(crowd: Node, ped_index: int) -> void:
	var pedestrians: Array = crowd.get("_pedestrians")
	if ped_index < 0 or ped_index >= pedestrians.size():
		return
	var ped: Dictionary = pedestrians[ped_index]
	ped["speech_cooldown"] = 0.0
	ped["pause_time"] = 0.0
	pedestrians[ped_index] = ped
	crowd.set("_pedestrians", pedestrians)
	crowd.set("_active_conversations", [])
