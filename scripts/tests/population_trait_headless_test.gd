extends SceneTree

const PopulationSimulator = preload("res://scripts/population_simulator.gd")


func _init() -> void:
	_test_trait_generation()
	_test_trait_range()
	_test_trait_inheritance()
	_test_trait_advance_year()
	print("population_trait_headless_test: ok")
	quit(0)


func _test_trait_generation() -> void:
	var sim := PopulationSimulator.new()
	sim.min_population = 80
	sim.max_population = 120
	sim.call("generate_population")
	var people: Array = sim.call("get_population_snapshot")
	assert(people.size() >= 80)
	var with_traits: int = 0
	for person in people:
		var traits = person.get("traits", {})
		if not traits.is_empty():
			with_traits += 1
	assert(with_traits == people.size(), "All %d people should have traits, got %d" % [people.size(), with_traits])
	sim.free()


func _test_trait_range() -> void:
	var sim := PopulationSimulator.new()
	sim.min_population = 80
	sim.max_population = 120
	sim.seed_value = 42
	sim.call("generate_population")
	var people: Array = sim.call("get_population_snapshot")
	for person in people:
		var traits = person.get("traits", {})
		var openness: float = float(traits.get("openness", -1.0))
		var sociability: float = float(traits.get("sociability", -1.0))
		var energy: float = float(traits.get("energy", -1.0))
		assert(openness >= 0.1 and openness <= 0.98, "Openness out of range: %f" % openness)
		assert(sociability >= 0.1 and sociability <= 0.98, "Sociability out of range: %f" % sociability)
		assert(energy >= 0.1 and energy <= 0.98, "Energy out of range: %f" % energy)
	sim.free()


func _test_trait_inheritance() -> void:
	var sim := PopulationSimulator.new()
	sim.min_population = 100
	sim.max_population = 160
	sim.seed_value = 123
	sim.call("generate_population")
	var people: Array = sim.call("get_population_snapshot")
	# Build parent-child lookup
	var person_by_id: Dictionary = {}
	for person in people:
		person_by_id[int(person["id"])] = person
	var lineage_similarity: int = 0
	var total_checks: int = 0
	for person in people:
		var father_id: int = int(person.get("father_id", -1))
		var mother_id: int = int(person.get("mother_id", -1))
		if father_id == -1 or mother_id == -1:
			continue
		var father = person_by_id.get(father_id, {})
		var mother = person_by_id.get(mother_id, {})
		if father.is_empty() or mother.is_empty():
			continue
		var child_traits = person.get("traits", {})
		var parent_traits = father.get("traits", mother.get("traits", {}))
		if parent_traits.is_empty():
			continue
		# Children should have traits within 0.4 of parent average
		var child_open: float = float(child_traits.get("openness", 0.5))
		var parent_open: float = (float(father.get("traits", {}).get("openness", 0.5)) + float(mother.get("traits", {}).get("openness", 0.5))) * 0.5
		if abs(child_open - parent_open) < 0.4:
			lineage_similarity += 1
		total_checks += 1
	assert(total_checks > 10, "Should have at least 10 parent-child pairs, got %d" % total_checks)
	assert(lineage_similarity > total_checks * 0.6, "At least 60%% of children should be within 0.4 of parent average (%d/%d)" % [lineage_similarity, total_checks])
	sim.free()


func _test_trait_advance_year() -> void:
	var sim := PopulationSimulator.new()
	sim.min_population = 60
	sim.max_population = 100
	sim.seed_value = 77
	sim.call("generate_population")
	# Advance a full year to trigger births
	sim.call("advance_hours", 24.0 * 365.0)
	var people: Array = sim.call("get_population_snapshot")
	var newborns: int = 0
	for person in people:
		if int(person.get("age", 99)) == 0:
			newborns += 1
			var traits = person.get("traits", {})
			assert(not traits.is_empty(), "Newborn should have traits")
			assert(float(traits.get("openness", 0.0)) > 0.0, "Newborn trait should be > 0")
	assert(newborns > 0, "Should have at least 1 newborn after a year")
	sim.free()
