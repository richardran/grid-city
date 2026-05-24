extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")

func _init() -> void:
	var root := Node.new()
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.name = "City"
	city.regenerate_on_ready = false
	root.add_child(city)
	city.generate_city()

	var sim := PopulationSimulator.new()
	sim.name = "Population"
	sim.city_path = NodePath("../City")
	sim.min_population = 40
	sim.max_population = 120
	root.add_child(sim)
	sim.generate_population()

	var summary_before: Dictionary = sim.get_population_summary()
	assert(int(summary_before.get("population", 0)) >= 40)
	assert(int(summary_before.get("households", 0)) > 0)
	assert(int(summary_before.get("workers", 0)) > 0)
	assert(String(summary_before.get("day_phase", "")).length() > 0)

	var residents: Array = sim.get_random_residents(4)
	assert(not residents.is_empty())
	var resident: Dictionary = residents[0]
	assert(str(resident.get("home_building_id", -1)) != "-1")
	var activity_before: Dictionary = sim.get_person_activity(int(resident.get("id", -1)))
	assert(not activity_before.is_empty())
	assert(String(activity_before.get("mode", "")).length() > 0)
	assert(String(activity_before.get("motivation", "")).length() > 0)
	assert(String(activity_before.get("goal", "")).length() > 0)
	assert(int(activity_before.get("initiator_id", -1)) == int(resident.get("id", -1)))
	var bonds: Array = sim.get_social_bonds(int(resident.get("id", -1)), 4)
	assert(not bonds.is_empty())
	var married_found: bool = false
	for candidate in sim.get_population_snapshot(false):
		var spouse_id: int = int(candidate.get("spouse_id", -1))
		if spouse_id == -1:
			continue
		var spouse_bonds: Array = sim.get_social_bonds(int(candidate.get("id", -1)), 6)
		for bond in spouse_bonds:
			if int(bond.get("target_id", -1)) == spouse_id:
				assert(int(bond.get("score", 0)) >= 60)
				married_found = true
				break
		if married_found:
			break
	assert(married_found)
	var population_page: Dictionary = sim.get_population_page(0, 8)
	assert(int(population_page.get("total", 0)) >= 40)
	assert(not Array(population_page.get("items", [])).is_empty())
	var household_page: Dictionary = sim.get_household_page(0, 6)
	assert(not Array(household_page.get("items", [])).is_empty())
	var recent_event_records: Array = sim.get_recent_event_records(24)
	assert(not recent_event_records.is_empty())
	assert(Dictionary(recent_event_records[0]).has("type"))
	assert(Dictionary(recent_event_records[0]).has("text"))

	sim.advance_hours(10.0)
	var activity_after: Dictionary = sim.get_person_activity(int(resident.get("id", -1)))
	assert(not activity_after.is_empty())
	sim.advance_hours(8.5)
	var evening_activity: Dictionary = sim.get_person_activity(int(resident.get("id", -1)))
	assert(["plaza", "wander", "evening_stroll", "home", "shopping", "coffee", "errand"].has(String(evening_activity.get("mode", ""))))
	var mixed_type_match_score: int = sim.call("_marriage_match_score", {
		"id": 9001,
		"gender": "male",
		"age": 31,
		"household_id": 41,
		"work_building_id": "cafe-12",
		"home_building_id": "block-a"
	}, {
		"id": 9002,
		"gender": "female",
		"age": 29,
		"household_id": "77",
		"work_building_id": "cafe-12",
		"home_building_id": "block-b"
	})
	assert(mixed_type_match_score > -999)
	var year_before_epoch: int = int(sim.get_population_summary().get("year", 0))
	sim.advance_hours(24.0)
	var summary_after_epoch: Dictionary = sim.get_population_summary()
	assert(int(summary_after_epoch.get("year", 0)) == year_before_epoch + 1)
	assert(String(summary_after_epoch.get("day_phase", "")).length() > 0)

	var age_before: int = int(sim.get_person(int(resident.get("id", -1))).get("age", 0))
	sim.advance_years(1)
	var person_after: Dictionary = sim.get_person(int(resident.get("id", -1)))
	assert(int(person_after.get("age", 0)) >= age_before)
	var summary_after: Dictionary = sim.get_population_summary()
	assert(int(summary_after.get("year", 0)) == int(summary_after_epoch.get("year", 0)) + 1)

	print("population_simulator_headless_test: ok")
	root.free()
	quit(0)
