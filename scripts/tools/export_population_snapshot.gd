extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const OUT_PATH := "res://outputs/population_snapshot.json"

func _init() -> void:
	var root := Node.new()
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.name = "City"
	city.regenerate_on_ready = false
	root.add_child(city)
	city.generate_city()

	var population := PopulationSimulator.new()
	population.name = "Population"
	population.city_path = NodePath("../City")
	root.add_child(population)
	population.generate_population()

	var people: Array = population.get_population_snapshot()
	var households: Array = population.get_households_snapshot()
	var sample_people: Array = []
	for i in range(mini(14, people.size())):
		sample_people.append(people[i])
	var payload := {
		"summary": population.get_population_summary(),
		"sample_people": sample_people,
		"sample_households": households.slice(0, mini(8, households.size()))
	}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print(ProjectSettings.globalize_path(OUT_PATH))
	root.free()
	quit(0)
