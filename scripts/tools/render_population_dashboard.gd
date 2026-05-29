extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const PopulationSimulator = preload("res://scripts/population_simulator.gd")
const OUT_PATH := "res://outputs/population_dashboard.svg"

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
	root.add_child(sim)
	sim.generate_population()
	sim.advance_hours(14.0)

	var dashboard: Dictionary = sim.get_dashboard_snapshot()
	var summary: Dictionary = dashboard.get("summary", {})
	var featured_people: Array = dashboard.get("featured_people", [])
	var events: Array = dashboard.get("recent_events", [])
	var bond_preview: Array = []
	if not featured_people.is_empty():
		bond_preview = sim.get_social_bonds(int(featured_people[0].get("id", -1)), 3)

	var parts: PackedStringArray = []
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="760" viewBox="0 0 1100 760">')
	parts.append('<rect width="100%" height="100%" fill="#eef2f7"/>')
	parts.append('<rect x="30" y="30" width="420" height="700" rx="18" fill="#ffffff" stroke="#d6dee8"/>')
	parts.append('<text x="56" y="74" font-family="Arial, sans-serif" font-size="28" fill="#1c2733">Population Simulator</text>')
	parts.append('<text x="56" y="106" font-family="Arial, sans-serif" font-size="18" fill="#4c5b6d">%s</text>' % str(summary.get("time_label", "Year 2026")).xml_escape())
	parts.append('<text x="56" y="144" font-family="Arial, sans-serif" font-size="16" fill="#334155">Population %d · Households %d · Lineages %d</text>' % [summary.get("population", 0), summary.get("households", 0), summary.get("lineages", 0)])
	parts.append('<text x="56" y="170" font-family="Arial, sans-serif" font-size="16" fill="#334155">Children %d · Adults %d · Seniors %d · Workers %d</text>' % [summary.get("children", 0), summary.get("adults", 0), summary.get("seniors", 0), summary.get("workers", 0)])
	parts.append('<text x="56" y="196" font-family="Arial, sans-serif" font-size="16" fill="#334155">Births %d · Deaths %d · Speed %.1fh/s</text>' % [summary.get("births", 0), summary.get("deaths", 0), summary.get("time_scale", 0.0)])

	var button_specs := [
		{"x": 56, "y": 228, "w": 112, "label": "Pause/Resume"},
		{"x": 180, "y": 228, "w": 100, "label": "Cycle Speed"},
		{"x": 292, "y": 228, "w": 78, "label": "+6 h"},
		{"x": 56, "y": 274, "w": 92, "label": "+1 year"},
		{"x": 160, "y": 274, "w": 126, "label": "Next resident"},
		{"x": 298, "y": 274, "w": 124, "label": "Next household"},
		{"x": 56, "y": 320, "w": 112, "label": "Residents list"},
		{"x": 180, "y": 320, "w": 124, "label": "Households list"},
		{"x": 316, "y": 320, "w": 92, "label": "Next page"}
	]
	for spec in button_specs:
		parts.append('<rect x="%d" y="%d" width="%d" height="34" rx="8" fill="#dde8ff" stroke="#b9c9e6"/>' % [spec["x"], spec["y"], spec["w"]])
		parts.append('<text x="%d" y="%d" font-family="Arial, sans-serif" font-size="13" fill="#203047">%s</text>' % [spec["x"] + 11, spec["y"] + 22, String(spec["label"]).xml_escape()])

	parts.append('<text x="56" y="386" font-family="Arial, sans-serif" font-size="20" fill="#1c2733">Featured residents</text>')
	var row_y: int = 416
	for person in featured_people:
		parts.append('<rect x="56" y="%d" width="368" height="52" rx="10" fill="#f8fbff" stroke="#d6dee8"/>' % [row_y - 22])
		parts.append('<text x="72" y="%d" font-family="Arial, sans-serif" font-size="16" fill="#1f2937">%s</text>' % [row_y, String(person.get("full_name", "Resident")).xml_escape()])
		parts.append('<text x="72" y="%d" font-family="Arial, sans-serif" font-size="13" fill="#4b5563">Age %s · %s · Home %s</text>' % [row_y + 18, person.get("age", 0), String(person.get("occupation", "local")).xml_escape(), person.get("home_building_id", -1)])
		row_y += 66

	parts.append('<rect x="486" y="30" width="584" height="700" rx="18" fill="#ffffff" stroke="#d6dee8"/>')
	parts.append('<text x="512" y="74" font-family="Arial, sans-serif" font-size="28" fill="#1c2733">Simulation events</text>')
	var event_y: int = 112
	for event in events:
		parts.append('<text x="512" y="%d" font-family="Arial, sans-serif" font-size="15" fill="#334155">• %s</text>' % [event_y, String(event).xml_escape()])
		event_y += 28
	parts.append('<text x="512" y="340" font-family="Arial, sans-serif" font-size="20" fill="#1c2733">Social bonds</text>')
	var bond_y: int = 372
	for bond in bond_preview:
		parts.append('<text x="512" y="%d" font-family="Arial, sans-serif" font-size="15" fill="#4b5563">• %s (%s %d)</text>' % [bond_y, String(bond.get("target_name", "Resident")).xml_escape(), String(bond.get("kind", "social")).xml_escape(), int(bond.get("score", 0))])
		bond_y += 28
	parts.append('<text x="512" y="484" font-family="Arial, sans-serif" font-size="20" fill="#1c2733">Interaction notes</text>')
	parts.append('<text x="512" y="514" font-family="Arial, sans-serif" font-size="15" fill="#4b5563">Use the panel to switch between resident and household lists, inspect selections, and jump the camera to the current resident.</text>')
	parts.append('<text x="512" y="544" font-family="Arial, sans-serif" font-size="15" fill="#4b5563">Positive and negative social bonds form from family, work, neighborhood, and rival interactions, then evolve lightly over time.</text>')
	parts.append('</svg>')

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
	file.store_string("\n".join(parts))
	file.close()
	print(ProjectSettings.globalize_path(OUT_PATH))
	root.free()
	quit(0)
