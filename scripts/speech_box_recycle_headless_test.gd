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
	city.seed_value = 515253
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 80
	population.max_population = 120
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
	crowd.conversation_share = 0.0
	crowd.player_conversation_share = 0.0
	crowd.enable_llm_conversations = false
	root.add_child(crowd)
	crowd.populate_now()
	crowd.set("_player_conversation_recycle_distance", 999.0)

	await process_frame
	await process_frame

	var candidates: Array[int] = _candidate_indices(crowd)
	assert(candidates.size() >= 4)
	for click_index in range(4):
		assert(crowd.call("trigger_player_conversation_for_pedestrian", int(candidates[click_index])))
	var snapshot: Array = crowd.call("get_conversation_chat_snapshot")
	assert(snapshot.size() == 3)
	assert(not _snapshot_has_speaker(snapshot, int(candidates[0])))
	assert(_snapshot_has_speaker(snapshot, int(candidates[1])))
	assert(_snapshot_has_speaker(snapshot, int(candidates[2])))
	assert(_snapshot_has_speaker(snapshot, int(candidates[3])))
	assert(crowd.call("get_player_conversation_count") == 3)

	camera.global_position = Vector3(1000.0, 20.0, 1000.0)
	crowd.set("_player_conversation_recycle_distance", 12.0)
	crowd._process(0.1)
	assert(crowd.call("get_player_conversation_count") == 0)
	assert(Array(crowd.call("get_conversation_chat_snapshot")).is_empty())

	print("speech_box_recycle_headless_test: ok")
	root.free()
	quit(0)


func _candidate_indices(crowd: Node) -> Array[int]:
	var indices: Array[int] = []
	var pedestrians: Array = crowd.get("_pedestrians")
	for ped_index in range(pedestrians.size()):
		var ped: Dictionary = Dictionary(pedestrians[ped_index])
		var root: Node3D = ped.get("root") as Node3D
		if str(ped.get("type", "")) == "dog" or root == null or not is_instance_valid(root):
			continue
		if Dictionary(ped.get("identity", {})).is_empty():
			continue
		indices.append(ped_index)
	return indices


func _snapshot_has_speaker(snapshot: Array, ped_index: int) -> bool:
	for entry in snapshot:
		if int(Dictionary(entry).get("speaker_index", -1)) == ped_index:
			return true
	return false
