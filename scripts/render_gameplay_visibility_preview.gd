extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")
const OUT_PATH := "res://outputs/gameplay_visibility_preview.svg"

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
	population.advance_hours(24.0 * 180.0)

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

	var events: Array = population.get_recent_event_records(10)
	var latest_event: Dictionary = events[events.size() - 1] if not events.is_empty() else {}
	var latest_anchor: Vector3 = _event_anchor(population, latest_event)
	if latest_anchor.x == INF:
		latest_anchor = city.get_spawn_point() if city.has_method("get_spawn_point") else Vector3.ZERO

	var snapshot: Array = crowd.get_pedestrian_debug_snapshot()
	var nearby: Array = []
	for ped in snapshot:
		var pos: Vector3 = ped["position"]
		var planar_distance: float = Vector2(pos.x - latest_anchor.x, pos.z - latest_anchor.z).length()
		if planar_distance <= 13.0:
			nearby.append({
				"position": pos,
				"distance": planar_distance,
				"label": Dictionary(ped.get("identity", {})).get("full_name", ped.get("label", "Resident")),
				"color": Color(ped.get("color", Color.WHITE))
			})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)

	var grid: Vector2i = city.grid_size
	var total_width: float = float(grid.x) * city.block_size + float(grid.x + 1) * city.street_width
	var total_depth: float = float(grid.y) * city.block_size + float(grid.y + 1) * city.street_width
	var walk_areas: Array = city.get_walk_areas_snapshot()

	var width := 1520
	var height := 960
	var parts: PackedStringArray = []
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [width, height, width, height])
	parts.append('<rect width="100%" height="100%" fill="#f8fafc"/>')
	parts.append('<text x="56" y="40" font-family="Arial, sans-serif" font-size="28" fill="#0f172a">Gameplay visibility check</text>')
	parts.append('<text x="56" y="66" font-family="Arial, sans-serif" font-size="14" fill="#475569">Ground view centers on the latest event. Nearby names are shown only inside the player label radius. Right side mirrors the event feed/overview state.</text>')

	_parts_local_panel(parts, latest_anchor, latest_event, nearby)
	_parts_city_panel(parts, walk_areas, events, population, latest_anchor, total_width, total_depth)
	_parts_feed_panel(parts, events, nearby)

	parts.append('</svg>')
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
	file.store_string("\n".join(parts))
	file.close()
	print(ProjectSettings.globalize_path(OUT_PATH))
	root.free()
	quit(0)


func _parts_local_panel(parts: PackedStringArray, anchor: Vector3, latest_event: Dictionary, nearby: Array) -> void:
	var panel_x := 56.0
	var panel_y := 98.0
	var panel_w := 640.0
	var panel_h := 520.0
	parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="20" fill="#ffffff" stroke="#dbe4ee"/>' % [panel_x, panel_y, panel_w, panel_h])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="22" fill="#0f172a">Ground view around latest event</text>' % [panel_x + 20.0, panel_y + 30.0])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="13" fill="#64748b">Visible beacon duration: ~6.5s+ · enlarged world event scale: 3.1×</text>' % [panel_x + 20.0, panel_y + 52.0])
	var cx: float = panel_x + panel_w * 0.5
	var cy: float = panel_y + panel_h * 0.56
	var scale: float = 15.5
	parts.append('<circle cx="%.2f" cy="%.2f" r="155" fill="none" stroke="#cbd5e1" stroke-dasharray="8 8" stroke-width="2"/>' % [cx, cy])
	parts.append('<circle cx="%.2f" cy="%.2f" r="46" fill="%s" fill-opacity="0.18" stroke="%s" stroke-width="3"/>' % [cx, cy, _event_color(str(latest_event.get("type", "birthday"))), _event_color(str(latest_event.get("type", "birthday")))])
	parts.append('<text x="%.2f" y="%.2f" text-anchor="middle" font-family="Arial, sans-serif" font-size="32" fill="%s">%s</text>' % [cx, cy + 11.0, _event_color(str(latest_event.get("type", "birthday"))), _event_glyph(str(latest_event.get("type", "birthday"))).xml_escape()])
	parts.append('<text x="%.2f" y="%.2f" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" fill="#334155">latest event house</text>' % [cx, cy + 78.0])
	for entry in nearby.slice(0, mini(10, nearby.size())):
		var pos: Vector3 = entry.get("position", Vector3.ZERO)
		var px: float = cx + (pos.x - anchor.x) * scale
		var py: float = cy + (pos.z - anchor.z) * scale
		var color: Color = entry.get("color", Color.WHITE)
		var hex: String = "#%s" % color.to_html(false)
		parts.append('<circle cx="%.2f" cy="%.2f" r="7" fill="%s" stroke="#1e293b" stroke-width="1.2"/>' % [px, py, hex])
		parts.append('<text x="%.2f" y="%.2f" font-family="Arial, sans-serif" font-size="13" fill="#0f172a">%s</text>' % [px + 10.0, py - 10.0, String(entry.get("label", "Resident")).xml_escape()])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="13" fill="#475569">Dashed ring = name-label distance. %d nearby names would render here.</text>' % [panel_x + 20.0, panel_y + panel_h - 18.0, nearby.size()])


func _parts_city_panel(parts: PackedStringArray, walk_areas: Array, events: Array, population: PopulationSimulator, latest_anchor: Vector3, total_width: float, total_depth: float) -> void:
	var panel_x := 730.0
	var panel_y := 98.0
	var panel_w := 734.0
	var panel_h := 520.0
	var pad := 24.0
	parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="20" fill="#ffffff" stroke="#dbe4ee"/>' % [panel_x, panel_y, panel_w, panel_h])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="22" fill="#0f172a">Overlook map + recent event anchors</text>' % [panel_x + 20.0, panel_y + 30.0])
	var inner_x: float = panel_x + pad
	var inner_y: float = panel_y + 54.0
	var inner_w: float = panel_w - pad * 2.0
	var inner_h: float = panel_h - 78.0
	for area in walk_areas:
		var x0: float = _map_x(float(area["x"].x), total_width, inner_x, inner_w)
		var x1: float = _map_x(float(area["x"].y), total_width, inner_x, inner_w)
		var y0: float = _map_y(float(area["z"].x), total_depth, inner_y, inner_h)
		var y1: float = _map_y(float(area["z"].y), total_depth, inner_y, inner_h)
		parts.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#e2e8f0" stroke="#cbd5e1" stroke-width="0.8"/>' % [x0, y0, x1 - x0, y1 - y0])
	for event in events:
		if not (event is Dictionary):
			continue
		var entry: Dictionary = event
		var anchor: Vector3 = _event_anchor(population, entry)
		if anchor.x == INF:
			continue
		var px: float = _map_x(anchor.x, total_width, inner_x, inner_w)
		var py: float = _map_y(anchor.z, total_depth, inner_y, inner_h)
		var color: String = _event_color(str(entry.get("type", "birthday")))
		parts.append('<circle cx="%.2f" cy="%.2f" r="14" fill="%s" fill-opacity="0.22" stroke="%s" stroke-width="2.4"/>' % [px, py, color, color])
		parts.append('<text x="%.2f" y="%.2f" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" fill="%s">%s</text>' % [px, py + 5.0, color, _event_glyph(str(entry.get("type", "birthday"))).xml_escape()])
	var lx: float = _map_x(latest_anchor.x, total_width, inner_x, inner_w)
	var ly: float = _map_y(latest_anchor.z, total_depth, inner_y, inner_h)
	parts.append('<circle cx="%.2f" cy="%.2f" r="24" fill="none" stroke="#0f172a" stroke-width="2" stroke-dasharray="6 5"/>' % [lx, ly])
	parts.append('<text x="%.2f" y="%.2f" font-family="Arial, sans-serif" font-size="13" fill="#334155">ground camera focus</text>' % [lx + 18.0, ly - 16.0])


func _parts_feed_panel(parts: PackedStringArray, events: Array, nearby: Array) -> void:
	var panel_x := 56.0
	var panel_y := 646.0
	var panel_w := 1408.0
	var panel_h := 254.0
	parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="20" fill="#ffffff" stroke="#dbe4ee"/>' % [panel_x, panel_y, panel_w, panel_h])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="22" fill="#0f172a">Panel state</text>' % [panel_x + 20.0, panel_y + 30.0])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="14" fill="#475569">Ground is the default mode. Overlook remains available as a toggle.</text>' % [panel_x + 20.0, panel_y + 54.0])
	var left_x: float = panel_x + 24.0
	var row_y: float = panel_y + 88.0
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="18" fill="#0f172a">Event feed</text>' % [left_x, row_y])
	for index in range(mini(8, events.size())):
		var entry: Dictionary = events[events.size() - 1 - index]
		parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="14" fill="#334155">%s Y%s D%s · %s</text>' % [left_x, row_y + 28.0 + index * 22.0, _event_glyph(str(entry.get("type", "birthday"))).xml_escape(), str(entry.get("year", "?")).xml_escape(), str(entry.get("day_of_year", "?")).xml_escape(), str(entry.get("text", "event")).xml_escape()])
	var right_x: float = panel_x + 760.0
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="18" fill="#0f172a">View details</text>' % [right_x, row_y])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="14" fill="#334155">Mode: Ground</text>' % [right_x, row_y + 28.0])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="14" fill="#334155">Toggle key: V</text>' % [right_x, row_y + 50.0])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="14" fill="#334155">Nearby visible names: %d</text>' % [right_x, row_y + 72.0, nearby.size()])
	parts.append('<text x="%.1f" y="%.1f" font-family="Arial, sans-serif" font-size="14" fill="#334155">Latest event button jumps to the most recent event house.</text>' % [right_x, row_y + 94.0])


func _event_anchor(population: PopulationSimulator, event: Dictionary) -> Vector3:
	var household_id: int = int(event.get("household_id", -1))
	if household_id != -1:
		var household: Dictionary = population.get_household(household_id)
		for member_id in household.get("member_ids", []):
			var person: Dictionary = population.get_person(int(member_id))
			if person.has("home_entry"):
				return Vector3(person.get("home_entry", Vector3.ZERO))
	for person_id in event.get("person_ids", []):
		var resident: Dictionary = population.get_person(int(person_id))
		if resident.has("home_entry"):
			return Vector3(resident.get("home_entry", Vector3.ZERO))
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


func _map_x(x: float, total_width: float, inner_x: float, inner_w: float) -> float:
	return inner_x + ((x + total_width * 0.5) / total_width) * inner_w


func _map_y(z: float, total_depth: float, inner_y: float, inner_h: float) -> float:
	return inner_y + ((z + total_depth * 0.5) / total_depth) * inner_h
