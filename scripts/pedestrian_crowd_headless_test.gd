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
	crowd.min_pedestrians = 6
	crowd.max_pedestrians = 12
	crowd.min_dogs = 2
	crowd.max_dogs = 3
	root.add_child(crowd)
	crowd.populate_now()

	var count: int = crowd.get_pedestrian_count()
	assert(count >= 8)
	assert(count <= 15)
	var snapshot_before: Array = crowd.get_pedestrian_debug_snapshot()
	assert(snapshot_before.size() == count)
	assert(snapshot_before[0].has("type"))
	assert(snapshot_before[0].has("position"))
	assert(snapshot_before[0].has("target"))
	assert(snapshot_before[0].has("mode"))
	assert(snapshot_before[0].has("group_kind"))
	assert(snapshot_before[0].has("identity"))
	assert(not Dictionary(snapshot_before[0]["identity"]).is_empty())
	var dog_count: int = 0
	var grouped_people: int = 0
	for entry in snapshot_before:
		if String(entry.get("type", "")) == "dog":
			dog_count += 1
		elif String(entry.get("group_kind", "solo")) != "solo":
			grouped_people += 1
	assert(grouped_people > 0)
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

	for _step in range(170):
		crowd._process(0.2)
	assert(crowd.get_active_event_effect_count() == 0)
	var snapshot_after: Array = crowd.get_pedestrian_debug_snapshot()
	var moved_any: bool = false
	for idx in range(mini(snapshot_before.size(), snapshot_after.size())):
		var before_pos: Vector3 = snapshot_before[idx]["position"]
		var after_pos: Vector3 = snapshot_after[idx]["position"]
		if before_pos.distance_to(after_pos) > 0.01:
			moved_any = true
			break
	assert(moved_any)

	root.free()
	print("pedestrian_crowd_headless_test: ok")
	quit(0)
