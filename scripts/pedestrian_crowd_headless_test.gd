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
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 40
	population.max_population = 120
	population.start_hour = 19.0
	population.hours_per_second = 72.0
	root.add_child(population)
	population.generate_population()
	var summary: Dictionary = population.get_population_summary()
	assert(int(summary.get("population", 0)) >= 40)
	assert(int(summary.get("households", 0)) > 0)
	assert(int(summary.get("lineages", 0)) > 0)

	var population_snapshot: Array = population.get_population_snapshot()
	var lineage_links: int = 0
	for person in population_snapshot:
		if int(person.get("father_id", -1)) > 0 or int(person.get("mother_id", -1)) > 0:
			lineage_links += 1
	assert(lineage_links > 0)

	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.population_path = NodePath("../Population")
	crowd.min_pedestrians = 10
	crowd.max_pedestrians = 14
	crowd.min_dogs = 2
	crowd.max_dogs = 3
	crowd.social_group_share = 0.45
	crowd.meetup_join_share = 1.0
	crowd.meetup_join_radius = 14.0
	crowd.conversation_share = 0.0
	crowd.player_conversation_share = 1.0
	crowd.player_conversation_radius = 999.0
	crowd.player_conversation_cooldown = 0.1
	root.add_child(crowd)
	crowd.populate_now()

	var count: int = crowd.get_pedestrian_count()
	assert(count >= 12)
	assert(count <= 17)
	assert(crowd.has_method("has_text_api_config"))
	assert(not bool(crowd.call("has_text_api_config")))
	var parsed_lines: Array = crowd.call("_extract_generated_lines_from_choice", {"message": {"content": "```json\n[\"Hi there.\", \"Market's busy today.\", \"Take the plaza road.\"]\n```"}})
	assert(parsed_lines.size() == 3)
	assert(String(parsed_lines[0]) == "Hi there.")
	var chunked_lines: Array = crowd.call("_extract_generated_lines_from_choice", {"message": {"content": [{"type": "text", "text": "[\"Morning.\", \"Square's lively.\", \"Try the bakery.\"]"}]}})
	assert(chunked_lines.size() == 3)
	var text_lines: Array = crowd.call("_extract_generated_lines_from_choice", {"text": "Hello there\nTry the coffee stall\nThe plaza is ahead"})
	assert(text_lines.size() == 3)
	var fallback_lines: Array = crowd.call("_extract_generated_lines_from_choice", {"message": {"content": "1. Hello there\n2. Try the coffee stall\n3. The plaza is ahead"}})
	assert(fallback_lines.size() == 3)
	assert(String(fallback_lines[1]) == "Try the coffee stall")
	assert(String(crowd.call("_message_content_to_text", null)) == "")
	var null_lines: Array = crowd.call("_extract_generated_lines_from_choice", {"message": {"content": null}})
	assert(null_lines.is_empty())
	var snapshot_before: Array = crowd.get_pedestrian_debug_snapshot()
	assert(snapshot_before.size() == count)
	assert(snapshot_before[0].has("type"))
	assert(snapshot_before[0].has("position"))
	assert(snapshot_before[0].has("target"))
	assert(snapshot_before[0].has("mode"))
	assert(snapshot_before[0].has("motivation"))
	assert(snapshot_before[0].has("goal"))
	assert(snapshot_before[0].has("initiative"))
	assert(snapshot_before[0].has("group_kind"))
	assert(snapshot_before[0].has("identity"))
	assert(not Dictionary(snapshot_before[0]["identity"]).is_empty())
	var dog_count: int = 0
	var grouped_people: int = 0
	var hotspot_people: int = 0
	for entry in snapshot_before:
		if String(entry.get("type", "")) == "dog":
			dog_count += 1
		if ["plaza", "coffee", "shopping", "market", "evening_stroll"].has(String(entry.get("mode", ""))):
			hotspot_people += 1
		if String(entry.get("group_kind", "solo")) != "solo":
			grouped_people += 1
	assert(grouped_people > 0)
	assert(hotspot_people > 0)
	assert(dog_count >= 2)
	assert(dog_count <= 3)
	var tracked_identity: Dictionary = snapshot_before[0]["identity"]
	crowd.set_tracked_people([int(tracked_identity.get("id", -1))])
	crowd.refresh_identities_from_population()
	var tracked_snapshot: Array = crowd.get_pedestrian_debug_snapshot()
	assert(int(Dictionary(tracked_snapshot[0]["identity"]).get("id", -1)) == int(tracked_identity.get("id", -1)))
	crowd.play_life_event_effect({
		"type": "birth",
		"person_ids": [int(tracked_identity.get("id", -1))],
		"text": "Birth test"
	})
	assert(crowd.get_active_event_effect_count() > 0)
	var event_visit_count: int = 0
	for entry in crowd.get_pedestrian_debug_snapshot():
		if String(entry.get("mode", "")) == "event_visit":
			event_visit_count += 1
	assert(event_visit_count > 0)
	var world_anchor: Node3D = null
	for child in crowd.get_children():
		if child is Node3D and String(child.name).begins_with("WorldEventAnchor_"):
			world_anchor = child as Node3D
			break
	assert(world_anchor != null)
	var anchor_position: Vector3 = world_anchor.position
	var walk_ground: float = city.get_walk_ground_height(anchor_position)
	assert(absf(anchor_position.y - (walk_ground + crowd.world_event_ground_lift)) < 0.3)

	population.generate_population()
	var snapshot_refreshed: Array = crowd.get_pedestrian_debug_snapshot()
	assert(snapshot_refreshed.size() == count)
	assert(snapshot_refreshed[0].has("label"))
	assert(String(snapshot_refreshed[0]["label"]).length() > 0)
	var internal_pedestrians: Array = crowd.get("_pedestrians")
	var solo_indices: Array = []
	for ped_index in range(internal_pedestrians.size()):
		var ped: Dictionary = internal_pedestrians[ped_index]
		if String(ped.get("type", "")) == "dog":
			continue
		if String(ped.get("group_role", "solo")) == "solo":
			solo_indices.append(ped_index)
	assert(solo_indices.size() >= 2)
	crowd.call("_form_meetup_group", int(solo_indices[0]), int(solo_indices[1]))
	crowd.call("_rebuild_group_leader_indices")
	crowd.call("_start_conversation", int(solo_indices[0]), int(solo_indices[1]))
	var chat_snapshot: Array = crowd.call("get_conversation_chat_snapshot")
	assert(not chat_snapshot.is_empty())
	assert(String(Dictionary(chat_snapshot[0]).get("text", "")).length() > 0)

	var test_camera := Camera3D.new()
	test_camera.position = Vector3.ZERO
	root.add_child(test_camera)
	crowd.camera_path = NodePath("../TestCamera")
	test_camera.name = "TestCamera"
	crowd.call("_resolve_camera")
	var solo_for_player: int = -1
	for ped_index in range(internal_pedestrians.size()):
		var ped: Dictionary = internal_pedestrians[ped_index]
		if String(ped.get("type", "")) == "dog":
			continue
		if crowd.call("_can_start_conversation", ped_index, ped):
			solo_for_player = ped_index
			break
	assert(solo_for_player >= 0)
	var player_root: Node3D = Dictionary(internal_pedestrians[solo_for_player]).get("root") as Node3D
	var before_player_pos: Vector3 = player_root.position
	crowd.call("_start_player_conversation", solo_for_player)
	crowd._process(0.5)
	assert(player_root.position.distance_to(before_player_pos) < 0.001)
	assert(bool(crowd.call("_ped_is_engaged_with_player", solo_for_player)))
	var player_snapshot: Array = crowd.call("get_conversation_chat_snapshot")
	assert(not player_snapshot.is_empty())
	assert(String(Dictionary(player_snapshot[0]).get("text", "")).length() > 0)

	for _step in range(170):
		crowd._process(0.2)
	assert(crowd.get_active_event_effect_count() == 0)
	var snapshot_after: Array = crowd.get_pedestrian_debug_snapshot()
	var moved_any: bool = false
	var meetup_count: int = 0
	for idx in range(mini(snapshot_before.size(), snapshot_after.size())):
		var before_pos: Vector3 = snapshot_before[idx]["position"]
		var after_pos: Vector3 = snapshot_after[idx]["position"]
		if before_pos.distance_to(after_pos) > 0.01:
			moved_any = true
	for entry in snapshot_after:
		if String(entry.get("group_kind", "")) == "meetup":
			meetup_count += 1
	assert(moved_any)
	assert(meetup_count > 0)
	assert(Array(crowd.call("get_conversation_chat_snapshot")).is_empty())

	root.free()
	print("pedestrian_crowd_headless_test: ok")
	quit(0)
