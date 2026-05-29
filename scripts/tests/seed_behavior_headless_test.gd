extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")

func _init() -> void:
	_test_runtime_random_seed()
	_test_runtime_random_layout_variation()
	_test_fixed_seed_reproducibility()
	_test_multi_seed_smoke_pass()
	print("seed_behavior_headless_test: ok")
	quit(0)


func _test_runtime_random_seed() -> void:
	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.seed_value = 0
	city.generate_city()
	assert(int(city.seed_value) != 0)
	assert(city.get_child_count() == 1)
	city.free()


func _test_runtime_random_layout_variation() -> void:
	var city_a := CityGenerator.new()
	city_a.regenerate_on_ready = false
	city_a.seed_value = 0
	city_a.generate_city()
	var city_b := CityGenerator.new()
	city_b.regenerate_on_ready = false
	city_b.seed_value = 0
	city_b.generate_city()
	assert(int(city_a.seed_value) != int(city_b.seed_value))
	assert(_city_signature(city_a) != _city_signature(city_b))
	city_a.free()
	city_b.free()


func _test_fixed_seed_reproducibility() -> void:
	var city_a := CityGenerator.new()
	city_a.regenerate_on_ready = false
	city_a.seed_value = 4242
	city_a.generate_city()
	var city_b := CityGenerator.new()
	city_b.regenerate_on_ready = false
	city_b.seed_value = 4242
	city_b.generate_city()
	assert(_city_signature(city_a) == _city_signature(city_b))
	city_a.free()
	city_b.free()


func _test_multi_seed_smoke_pass() -> void:
	for fixed_seed in [11, 29, 47, 83, 127, 211]:
		var root := Node3D.new()
		get_root().add_child(root)
		var city := CityGenerator.new()
		city.name = "City"
		city.regenerate_on_ready = false
		city.seed_value = int(fixed_seed)
		root.add_child(city)
		city.generate_city()
		assert(city.get_building_slots_snapshot().size() > 0)
		var population := PopulationSimulator.new()
		population.name = "Population"
		population.city_path = NodePath("../City")
		population.min_population = 40
		population.max_population = 120
		root.add_child(population)
		population.generate_population()
		assert(int(population.get_population_summary().get("population", 0)) >= 40)
		var crowd := PedestrianCrowd.new()
		crowd.name = "Crowd"
		crowd.city_path = NodePath("../City")
		crowd.population_path = NodePath("../Population")
		crowd.min_pedestrians = 8
		crowd.max_pedestrians = 16
		crowd.min_dogs = 2
		crowd.max_dogs = 4
		root.add_child(crowd)
		crowd.populate_now()
		assert(crowd.get_pedestrian_count() >= 10)
		for _step in range(12):
			crowd._process(0.2)
		root.free()


func _city_signature(city: Node) -> String:
	var slots: Array = city.call("get_building_slots_snapshot")
	var blocks: Array = city.call("get_block_centers_snapshot")
	return "%d|%d|%s|%s" % [
		slots.size(),
		blocks.size(),
		JSON.stringify(slots.slice(0, mini(5, slots.size()))),
		JSON.stringify(blocks.slice(0, mini(5, blocks.size())))
	]
