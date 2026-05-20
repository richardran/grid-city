extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")
const OUT_PATH := "res://outputs/pedestrian_layout.svg"

func _init() -> void:
	var root := Node3D.new()
	root.name = "RenderRoot"
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.name = "City"
	city.regenerate_on_ready = false
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
	population.generate_population()

	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.population_path = NodePath("../Population")
	crowd.min_pedestrians = 42
	crowd.max_pedestrians = 68
	crowd.density_per_block = 0.62
	crowd.max_detailed_pedestrians = 12
	crowd.crowd_update_slices = 3
	root.add_child(crowd)
	crowd.populate_now()

	var grid: Vector2i = city.grid_size
	var total_width: float = float(grid.x) * city.block_size + float(grid.x + 1) * city.street_width
	var total_depth: float = float(grid.y) * city.block_size + float(grid.y + 1) * city.street_width
	var walk_areas: Array = city.get_walk_areas_snapshot()
	var snapshot: Array = crowd.get_pedestrian_debug_snapshot()

	var width := 1200
	var height := 1200
	var pad := 72.0
	var inner_w: float = width - pad * 2.0
	var inner_h: float = height - pad * 2.0

	var parts: PackedStringArray = []
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [width, height, width, height])
	parts.append('<rect width="100%" height="100%" fill="#f5f7fb"/>')
	var population_summary: Dictionary = population.get_population_summary()
	parts.append('<text x="72" y="38" font-family="Arial, sans-serif" font-size="24" fill="#1e2837">Pedestrian density layout preview</text>')
	parts.append('<text x="72" y="62" font-family="Arial, sans-serif" font-size="14" fill="#5e6a78">Population %d · households %d · lineages %d · active pedestrians %d</text>' % [population_summary.get("population", 0), population_summary.get("households", 0), population_summary.get("lineages", 0), snapshot.size()])

	for area in walk_areas:
		var x0: float = _sx(float(area["x"].x), total_width, inner_w, pad)
		var x1: float = _sx(float(area["x"].y), total_width, inner_w, pad)
		var y0: float = _sy(float(area["z"].x), total_depth, inner_h, pad)
		var y1: float = _sy(float(area["z"].y), total_depth, inner_h, pad)
		parts.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#d8dddf" stroke="#c7cfd6" stroke-width="0.8"/>' % [x0, y0, x1 - x0, y1 - y0])

	for ped_index in range(snapshot.size()):
		var ped: Dictionary = snapshot[ped_index]
		var pos: Vector3 = ped["position"]
		var target: Vector3 = ped["target"]
		var color: Color = ped["color"]
		var identity: Dictionary = ped.get("identity", {})
		var hex: String = "#%s" % color.to_html(false)
		var px: float = _sx(pos.x, total_width, inner_w, pad)
		var py: float = _sy(pos.z, total_depth, inner_h, pad)
		var tx: float = _sx(target.x, total_width, inner_w, pad)
		var ty: float = _sy(target.z, total_depth, inner_h, pad)
		parts.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-opacity="0.45" stroke-width="2"/>' % [px, py, tx, ty, hex])
		parts.append('<circle cx="%.2f" cy="%.2f" r="5.2" fill="%s" stroke="#203040" stroke-width="1.0"/>' % [px, py, hex])
		if ped_index < 12 and not identity.is_empty():
			var label: String = "%s, %s" % [identity.get("full_name", "Resident"), identity.get("occupation", "local")]
			parts.append('<text x="%.2f" y="%.2f" font-family="Arial, sans-serif" font-size="12" fill="#22303f">%s</text>' % [px + 10.0, py - 8.0, label.xml_escape()])

	parts.append('<rect x="72" y="1088" width="400" height="76" rx="12" fill="#ffffff" fill-opacity="0.82" stroke="#d2dae5"/>')
	parts.append('<circle cx="98" cy="1130" r="6" fill="#4773ca" stroke="#203040" stroke-width="1.0"/><text x="112" y="1135" font-family="Arial, sans-serif" font-size="14" fill="#334155">man</text>')
	parts.append('<circle cx="176" cy="1130" r="6" fill="#d16375" stroke="#203040" stroke-width="1.0"/><text x="190" y="1135" font-family="Arial, sans-serif" font-size="14" fill="#334155">woman</text>')
	parts.append('<circle cx="280" cy="1130" r="6" fill="#61b85f" stroke="#203040" stroke-width="1.0"/><text x="294" y="1135" font-family="Arial, sans-serif" font-size="14" fill="#334155">child</text>')
	parts.append('<text x="98" y="1154" font-family="Arial, sans-serif" font-size="13" fill="#5b6470">Only a sample of labels is shown here so the denser crowd stays readable.</text>')
	parts.append('</svg>')

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
	file.store_string("\n".join(parts))
	file.close()
	print(ProjectSettings.globalize_path(OUT_PATH))
	root.free()
	quit(0)


func _sx(x: float, total_width: float, inner_w: float, pad: float) -> float:
	return pad + ((x + total_width * 0.5) / total_width) * inner_w


func _sy(z: float, total_depth: float, inner_h: float, pad: float) -> float:
	return pad + ((z + total_depth * 0.5) / total_depth) * inner_h
