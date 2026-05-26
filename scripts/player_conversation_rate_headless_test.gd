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
	crowd.enable_llm_conversations = false
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
	var person_id: int = int(candidate.get("person_id", -1))
	var first_name: String = str(candidate.get("first_name", ""))
	assert(person_id > 0)
	assert(first_name != "")
	var context: Dictionary = population.get_resident_conversation_context(person_id)
	assert(not context.is_empty())
	assert(Dictionary(context.get("activity", {})).has("mode"))
	camera.global_position = focus + Vector3(0.0, 1.0, 3.1)
	camera.look_at(focus, Vector3.UP)

	_block_selected_pedestrian_for_retry(crowd, ped_index)
	assert(crowd.trigger_player_conversation_for_person(person_id))
	var forced_snapshot: Array = crowd.get_conversation_chat_snapshot()
	assert(not forced_snapshot.is_empty())
	assert(bool(Dictionary(forced_snapshot[0]).get("is_player", false)))
	assert(str(Dictionary(forced_snapshot[0]).get("text", "")).contains(first_name))
	_reset_pedestrian_for_retry(crowd, ped_index)

	_seed_pending_player_conversation(crowd, ped_index)
	for _step in range(12):
		crowd._process(1.0)
	var pending_snapshot: Array = crowd.get_conversation_chat_snapshot()
	assert(not pending_snapshot.is_empty())
	assert(bool(Dictionary(pending_snapshot[0]).get("llm_pending", false)))
	_reset_pedestrian_for_retry(crowd, ped_index)

	var generated_lines: Array[String] = ["Fresh line from the model.", "Second line stays in the same box.", "Third line rolls below it."]
	_seed_pending_player_conversation(crowd, ped_index)
	crowd.call("_finalize_openrouter_player_lines", ped_index, generated_lines, "ok")
	var recreated_snapshot: Array = crowd.get_conversation_chat_snapshot()
	assert(not recreated_snapshot.is_empty())
	var first_text: String = str(Dictionary(recreated_snapshot[0]).get("text", ""))
	assert(first_text.contains("Fresh line from the model."))
	assert(not first_text.contains("Second line stays in the same box."))
	assert(not first_text.contains("Third line rolls below it."))
	_advance_conversation(crowd, 2.4)
	var second_snapshot: Array = crowd.get_conversation_chat_snapshot()
	assert(not second_snapshot.is_empty())
	var second_text: String = str(Dictionary(second_snapshot[0]).get("text", ""))
	assert(second_text.contains("Fresh line from the model."))
	assert(second_text.contains("Second line stays in the same box."))
	assert(not second_text.contains("Third line rolls below it."))
	_advance_conversation(crowd, 2.4)
	var third_snapshot: Array = crowd.get_conversation_chat_snapshot()
	assert(not third_snapshot.is_empty())
	var third_text: String = str(Dictionary(third_snapshot[0]).get("text", ""))
	assert(third_text.contains("Fresh line from the model."))
	assert(third_text.contains("Second line stays in the same box."))
	assert(third_text.contains("Third line rolls below it."))
	var streamed_lines: Array[String] = ["Fourth line streams in.", "Fifth line streams in."]
	crowd.call("_finalize_openrouter_player_lines", ped_index, streamed_lines, "ok")
	_advance_conversation(crowd, 2.4)
	var fourth_snapshot: Array = crowd.get_conversation_chat_snapshot()
	assert(not fourth_snapshot.is_empty())
	var fourth_text: String = str(Dictionary(fourth_snapshot[0]).get("text", ""))
	assert(not fourth_text.contains("Fresh line from the model."))
	assert(fourth_text.contains("Second line stays in the same box."))
	assert(fourth_text.contains("Third line rolls below it."))
	assert(fourth_text.contains("Fourth line streams in."))
	_advance_conversation(crowd, 2.4)
	var fifth_snapshot: Array = crowd.get_conversation_chat_snapshot()
	assert(not fifth_snapshot.is_empty())
	var fifth_text: String = str(Dictionary(fifth_snapshot[0]).get("text", ""))
	assert(not fifth_text.contains("Second line stays in the same box."))
	assert(fifth_text.contains("Third line rolls below it."))
	assert(fifth_text.contains("Fourth line streams in."))
	assert(fifth_text.contains("Fifth line streams in."))
	_reset_pedestrian_for_retry(crowd, ped_index)

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
				"person_id": int(identity.get("id", -1)),
				"first_name": str(identity.get("first_name", identity.get("full_name", "Resident"))).split(" ")[0],
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


func _block_selected_pedestrian_for_retry(crowd: Node, ped_index: int) -> void:
	var pedestrians: Array = crowd.get("_pedestrians")
	assert(ped_index >= 0 and ped_index < pedestrians.size())
	var ped: Dictionary = pedestrians[ped_index]
	ped["speech_cooldown"] = 99.0
	ped["mode"] = "home"
	pedestrians[ped_index] = ped
	crowd.set("_pedestrians", pedestrians)
	crowd.set("_active_conversations", [
		{"id": "ambient_a", "speaker_indices": [ped_index], "lines": [{"speaker_index": ped_index, "text": "ambient"}], "line_index": 0, "elapsed": 0.0, "line_duration": 2.0, "is_player": false, "llm_pending": false},
		{"id": "ambient_b", "speaker_indices": [0], "lines": [{"speaker_index": 0, "text": "ambient"}], "line_index": 0, "elapsed": 0.0, "line_duration": 2.0, "is_player": false, "llm_pending": false},
		{"id": "ambient_c", "speaker_indices": [1], "lines": [{"speaker_index": 1, "text": "ambient"}], "line_index": 0, "elapsed": 0.0, "line_duration": 2.0, "is_player": false, "llm_pending": false}
	])


func _seed_pending_player_conversation(crowd: Node, ped_index: int) -> void:
	crowd.set("_active_conversations", [
		{"id": "pending_player", "speaker_indices": [ped_index], "lines": [{"speaker_index": ped_index, "text": "..."}], "line_index": 0, "elapsed": 99.0, "line_duration": 0.5, "is_player": true, "llm_pending": true}
	])


func _advance_conversation(crowd: Node, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(0.2, remaining)
		crowd._process(step)
		remaining -= step
