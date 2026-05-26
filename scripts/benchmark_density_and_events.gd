extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")

var _event_counts := {"birth": 0, "marriage": 0, "death": 0}
var _tracked_event_hits := 0
var _tracked_ids: Array[int] = []
var _tracked_birthday_hits := 0

func _init() -> void:
	var root := Node3D.new()
	root.name = "BenchmarkRoot"
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.name = "City"
	city.regenerate_on_ready = false
	city.seed_value = 12345
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	population.min_population = 140
	population.max_population = 280
	population.residents_per_block = 2.0
	population.hours_per_second = 72.0
	root.add_child(population)
	population.connect("life_event", Callable(self, "_on_life_event"))
	population.generate_population()
	_tracked_ids = _build_tracked_ids(population)

	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.population_path = NodePath("../Population")
	crowd.min_pedestrians = 42
	crowd.max_pedestrians = 68
	crowd.density_per_block = 0.62
	crowd.max_active_event_effects = 24
	crowd.crowd_update_slices = 3
	crowd.max_detailed_pedestrians = 12
	root.add_child(crowd)
	crowd.populate_now()

	var population_summary: Dictionary = population.get_population_summary()
	var start_year: int = int(population_summary.get("year", 0))
	var tracked_ages: Dictionary = _tracked_age_snapshot(population)
	for _year in range(5):
		population.advance_hours(24.0 * 365.0)
		var next_tracked_ages: Dictionary = _tracked_age_snapshot(population)
		for person_id in next_tracked_ages.keys():
			if tracked_ages.has(person_id) and int(next_tracked_ages[person_id]) > int(tracked_ages[person_id]):
				_tracked_birthday_hits += 1
		tracked_ages = next_tracked_ages
	var end_year: int = int(population.get_population_summary().get("year", start_year))

	crowd.set_tracked_people(_tracked_ids)
	for event_type in ["birth", "marriage", "death"]:
		crowd.play_life_event_effect({"type": event_type, "person_ids": _tracked_ids, "text": event_type})

	var frame_count: int = 240
	var started_usec: int = Time.get_ticks_usec()
	for _frame in range(frame_count):
		crowd._process(1.0 / 20.0)
	var elapsed_msec: float = float(Time.get_ticks_usec() - started_usec) / 1000.0

	print("benchmark_density_and_events: population=%d crowd=%d years=%d births=%d marriages=%d deaths=%d avgCrowdProcessMs=%.3f activeEffects=%d" % [
		int(population_summary.get("population", 0)),
		crowd.get_pedestrian_count(),
		end_year - start_year,
		int(_event_counts.get("birth", 0)),
		int(_event_counts.get("marriage", 0)),
		int(_event_counts.get("death", 0)),
		elapsed_msec / float(frame_count),
		crowd.get_active_event_effect_count()
	])
	print("benchmark_density_and_events: trackedIds=%d trackedEventHits=%d trackedBirthdayPopups=%d" % [_tracked_ids.size(), _tracked_event_hits, _tracked_birthday_hits])

	root.free()
	quit(0)


func _on_life_event(event: Dictionary) -> void:
	var event_type: String = str(event.get("type", ""))
	if not _event_counts.has(event_type):
		return
	_event_counts[event_type] = int(_event_counts[event_type]) + 1
	for person_id in event.get("person_ids", []):
		if _tracked_ids.has(int(person_id)):
			_tracked_event_hits += 1
			break


func _build_tracked_ids(population: PopulationSimulator) -> Array[int]:
	var tracked: Array[int] = []
	var residents: Array = population.get_random_residents(1)
	if residents.is_empty():
		return tracked
	var person: Dictionary = residents[0]
	_append_person_and_related_ids(population, tracked, int(person.get("id", -1)))
	var household: Dictionary = population.get_household(int(person.get("household_id", -1)))
	for member_id in household.get("member_ids", []):
		_append_person_and_related_ids(population, tracked, int(member_id))
	return tracked


func _append_unique_id(target: Array[int], person_id: int) -> void:
	if person_id <= 0 or target.has(person_id):
		return
	target.append(person_id)


func _append_person_and_related_ids(population: PopulationSimulator, target: Array[int], person_id: int) -> void:
	_append_unique_id(target, person_id)
	if person_id <= 0:
		return
	var person: Dictionary = population.get_person(person_id)
	if person.is_empty():
		return
	for related_id in [person.get("spouse_id", -1), person.get("father_id", -1), person.get("mother_id", -1)]:
		_append_unique_id(target, int(related_id))
	for child_id in person.get("child_ids", []):
		_append_unique_id(target, int(child_id))
	for bond in population.get_social_bonds(person_id, 4):
		_append_unique_id(target, int(Dictionary(bond).get("target_id", -1)))


func _tracked_age_snapshot(population: PopulationSimulator) -> Dictionary:
	var result: Dictionary = {}
	for person_id in _tracked_ids:
		var person: Dictionary = population.get_person(person_id)
		if person.is_empty() or not bool(person.get("alive", true)):
			continue
		result[person_id] = int(person.get("age", 0))
	return result
