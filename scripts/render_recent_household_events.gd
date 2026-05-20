extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const OUT_PATH := "res://outputs/recent_household_events.svg"

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
	population.advance_hours(24.0 * 365.0 * 5.0)

	var grid: Vector2i = city.grid_size
	var total_width: float = float(grid.x) * city.block_size + float(grid.x + 1) * city.street_width
	var total_depth: float = float(grid.y) * city.block_size + float(grid.y + 1) * city.street_width
	var walk_areas: Array = city.get_walk_areas_snapshot()
	var event_records: Array = population.get_recent_event_records(12)

	var width := 1200
	var height := 1200
	var pad := 72.0
	var inner_w: float = width - pad * 2.0
	var inner_h: float = height - pad * 2.0

	var parts: PackedStringArray = []
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [width, height, width, height])
	parts.append('<rect width="100%" height="100%" fill="#f8fafc"/>')
	parts.append('<text x="72" y="38" font-family="Arial, sans-serif" font-size="24" fill="#1e293b">Recent household event markers</text>')
	parts.append('<text x="72" y="62" font-family="Arial, sans-serif" font-size="14" fill="#64748b">Five simulated years, showing latest household-centered life events.</text>')

	for area in walk_areas:
		var x0: float = _sx(float(area["x"].x), total_width, inner_w, pad)
		var x1: float = _sx(float(area["x"].y), total_width, inner_w, pad)
		var y0: float = _sy(float(area["z"].x), total_depth, inner_h, pad)
		var y1: float = _sy(float(area["z"].y), total_depth, inner_h, pad)
		parts.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#dbe4ea" stroke="#cbd5e1" stroke-width="0.8"/>' % [x0, y0, x1 - x0, y1 - y0])

	var legend_y: int = 1086
	for index in range(event_records.size()):
		var event: Dictionary = event_records[index]
		var anchor: Vector3 = _event_anchor(population, event)
		if anchor.x == INF:
			continue
		var px: float = _sx(anchor.x, total_width, inner_w, pad)
		var py: float = _sy(anchor.z, total_depth, inner_h, pad)
		var color: String = _event_color(str(event.get("type", "system")))
		var glyph: String = _event_glyph(str(event.get("type", "system")))
		parts.append('<circle cx="%.2f" cy="%.2f" r="14" fill="%s" fill-opacity="0.28" stroke="%s" stroke-width="2.5"/>' % [px, py, color, color])
		parts.append('<text x="%.2f" y="%.2f" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" fill="%s">%s</text>' % [px, py + 5.0, color, glyph.xml_escape()])
		if index < 8:
			parts.append('<text x="%.2f" y="%.2f" font-family="Arial, sans-serif" font-size="12" fill="#334155">%s</text>' % [px + 18.0, py - 10.0, String(event.get("text", "event")).xml_escape()])
		parts.append('<text x="72" y="%d" font-family="Arial, sans-serif" font-size="13" fill="#475569">%s %s</text>' % [legend_y + index * 18, glyph.xml_escape(), String(event.get("text", "event")).xml_escape()])

	parts.append('</svg>')

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
	file.store_string("\n".join(parts))
	file.close()
	print(ProjectSettings.globalize_path(OUT_PATH))
	root.free()
	quit(0)


func _event_anchor(population: PopulationSimulator, event: Dictionary) -> Vector3:
	var household_id: int = int(event.get("household_id", -1))
	if household_id != -1:
		var household: Dictionary = population.get_household(household_id)
		for member_id in household.get("member_ids", []):
			var person: Dictionary = population.get_person(int(member_id))
			if person.has("home_entry"):
				return Vector3(person.get("home_entry", Vector3.ZERO))
	for person_id in event.get("person_ids", []):
		var person: Dictionary = population.get_person(int(person_id))
		if person.has("home_entry"):
			return Vector3(person.get("home_entry", Vector3.ZERO))
	return Vector3(INF, INF, INF)


func _event_color(event_type: String) -> String:
	match event_type:
		"birth":
			return "#f59e0b"
		"marriage":
			return "#ec4899"
		"birthday":
			return "#8b5cf6"
		"death":
			return "#60a5fa"
		_:
			return "#94a3b8"


func _event_glyph(event_type: String) -> String:
	match event_type:
		"birth":
			return "🎈"
		"marriage":
			return "✿"
		"birthday":
			return "★"
		"death":
			return "✧"
		_:
			return "•"


func _sx(x: float, total_width: float, inner_w: float, pad: float) -> float:
	return pad + ((x + total_width * 0.5) / total_width) * inner_w


func _sy(z: float, total_depth: float, inner_h: float, pad: float) -> float:
	return pad + ((z + total_depth * 0.5) / total_depth) * inner_h
