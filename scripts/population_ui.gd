extends CanvasLayer
class_name PopulationUI

@export var population_path: NodePath
@export var crowd_path: NodePath
@export var camera_path: NodePath

var _population: Node
var _crowd: Node
var _camera: Camera3D
var _selected_person_id: int = -1
var _selected_household_id: int = -1
var _refresh_accum: float = 0.0
var _list_mode: String = "population"
var _page_index: int = 0
var _resident_page_size: int = 10
var _household_page_size: int = 8
var _tracked_ages_by_id: Dictionary = {}


func _ready() -> void:
	_population = get_node_or_null(population_path)
	_crowd = get_node_or_null(crowd_path)
	_camera = get_node_or_null(camera_path) as Camera3D
	if _population != null and _population.has_signal("life_event") and not _population.is_connected("life_event", Callable(self, "_on_life_event")):
		_population.connect("life_event", Callable(self, "_on_life_event"))
	_wire_button("Panel/Margin/VBox/Controls/TogglePause", _on_toggle_pause)
	_wire_button("Panel/Margin/VBox/Controls/CycleSpeed", _on_cycle_speed)
	_wire_button("Panel/Margin/VBox/Controls/Advance6Hours", _on_advance_6_hours)
	_wire_button("Panel/Margin/VBox/Controls/AdvanceYear", _on_advance_year)
	_wire_button("Panel/Margin/VBox/Controls/NextResident", _on_next_resident)
	_wire_button("Panel/Margin/VBox/Controls/NextHousehold", _on_next_household)
	_wire_button("Panel/Margin/VBox/Controls/JumpToSelection", _on_jump_to_selection)
	_wire_button("Panel/Margin/VBox/Controls/ShowPopulation", _on_set_ground_view)
	_wire_button("Panel/Margin/VBox/Controls/ShowHouseholds", _on_set_overlook_view)
	_wire_button("Panel/Margin/VBox/Controls/PrevPage", _on_jump_to_latest_event)
	var next_page_button := get_node_or_null("Panel/Margin/VBox/Controls/NextPage") as Control
	if next_page_button != null:
		next_page_button.visible = false
	var spacer := get_node_or_null("Panel/Margin/VBox/Controls/Spacer") as Control
	if spacer != null:
		spacer.visible = false
	if _population != null and _population.has_method("get_random_residents"):
		var residents: Array = _population.call("get_random_residents", 1)
		if not residents.is_empty():
			_selected_person_id = int(residents[0].get("id", -1))
			_selected_household_id = int(residents[0].get("household_id", -1))
	_sync_tracked_visualization()
	_update_ui()


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= 0.25:
		_refresh_accum = 0.0
		_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered != null:
			return
		_pick_person_at_screen(mouse_event.position)


func _wire_button(path: String, callable_method: Callable) -> void:
	var button := get_node_or_null(path)
	if button != null and button is BaseButton:
		(button as BaseButton).pressed.connect(callable_method)


func _update_ui() -> void:
	if _population == null or not _population.has_method("get_dashboard_snapshot"):
		return
	var snapshot: Dictionary = _population.call("get_dashboard_snapshot")
	var summary: Dictionary = snapshot.get("summary", {})
	var summary_label := get_node_or_null("Panel/Margin/VBox/Summary") as RichTextLabel
	if summary_label != null:
		summary_label.text = "[b]%s[/b]\nPopulation: %d | Households: %d | Lineages: %d\nChildren: %d | Adults: %d | Seniors: %d | Workers: %d\nBirths: %d | Deaths: %d | Crowd shown: %d" % [
			summary.get("time_label", "Time unavailable"),
			summary.get("population", 0),
			summary.get("households", 0),
			summary.get("lineages", 0),
			summary.get("children", 0),
			summary.get("adults", 0),
			summary.get("seniors", 0),
			summary.get("workers", 0),
			summary.get("births", 0),
			summary.get("deaths", 0),
			_crowd.get_pedestrian_count() if _crowd != null and _crowd.has_method("get_pedestrian_count") else 0
		]
	var speed_button := get_node_or_null("Panel/Margin/VBox/Controls/CycleSpeed") as Button
	if speed_button != null:
		speed_button.text = "Speed %.1fh/s" % float(summary.get("time_scale", 0.0))
	var pause_button := get_node_or_null("Panel/Margin/VBox/Controls/TogglePause") as Button
	if pause_button != null:
		pause_button.text = "Resume" if bool(summary.get("paused", false)) else "Pause"
	var ground_view_button := get_node_or_null("Panel/Margin/VBox/Controls/ShowPopulation") as Button
	if ground_view_button != null:
		ground_view_button.text = "Ground ✓" if _current_view_mode() == "ground" else "Ground"
	var overlook_view_button := get_node_or_null("Panel/Margin/VBox/Controls/ShowHouseholds") as Button
	if overlook_view_button != null:
		overlook_view_button.text = "Overlook ✓" if _current_view_mode() == "overlook" else "Overlook"
	var latest_event_button := get_node_or_null("Panel/Margin/VBox/Controls/PrevPage") as Button
	if latest_event_button != null:
		latest_event_button.text = "Latest event"
	_update_selection_details()
	var recent_events: Array = snapshot.get("recent_event_records", snapshot.get("recent_events", []))
	_update_list_panel(recent_events)
	_update_events(recent_events)
	_sync_tracked_visualization()
	_update_tracked_birthdays()


func _update_selection_details() -> void:
	var details := get_node_or_null("Panel/Margin/VBox/Selection") as RichTextLabel
	if details == null:
		return
	var lines: Array[String] = []
	if _selected_person_id != -1 and _population.has_method("get_person"):
		var person: Dictionary = _population.call("get_person", _selected_person_id)
		if not person.is_empty():
			lines.append("[b]Resident[/b]: %s" % person.get("full_name", "Resident"))
			lines.append("Age %d · %s · %s" % [person.get("age", 0), person.get("occupation", "local"), "alive" if bool(person.get("alive", true)) else "deceased"])
			lines.append("Lineage %s · Generation %s · Household %s" % [person.get("lineage_id", "?"), person.get("generation", "?"), person.get("household_id", "?")])
			var bio: String = str(person.get("bio", ""))
			if bio != "":
				lines.append("")
				lines.append("[b]About[/b]")
				lines.append(bio)
			lines.append("")
			lines.append("[b]Lineage[/b]")
			lines.append("Parents: %s" % _relationship_names([person.get("father_id", -1), person.get("mother_id", -1)]))
			lines.append("Siblings: %s" % _sibling_names_for(person))
			lines.append("Children: %s" % _relationship_names(person.get("child_ids", []), 6))
			var spouse_id: int = int(person.get("spouse_id", -1))
			if spouse_id != -1 and _population.has_method("get_person"):
				var spouse: Dictionary = _population.call("get_person", spouse_id)
				if not spouse.is_empty():
					lines.append("Spouse: %s" % spouse.get("full_name", "Resident"))
			lines.append("Lineage members: %s" % _lineage_member_summary(str(person.get("lineage_id", "L000")), int(person.get("id", -1))))
			if str(person.get("home_building_id", -1)) != "-1":
				lines.append("")
				lines.append("[b]Places[/b]")
				lines.append("Home building: %s" % person.get("home_building_id", -1))
			if str(person.get("work_building_id", -1)) != "-1":
				lines.append("Work building: %s" % person.get("work_building_id", -1))
			if _population.has_method("get_social_bonds"):
				var bonds: Array = _population.call("get_social_bonds", _selected_person_id, 4)
				if not bonds.is_empty():
					lines.append("")
					lines.append("Social bonds:")
					for bond in bonds:
						var score: int = int(bond.get("score", 0))
						var sign: String = "+" if score >= 0 else ""
						lines.append("  • %s %s (%s%d)" % [bond.get("target_name", "Resident"), bond.get("kind", "social"), sign, score])
	if _selected_household_id != -1 and _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", _selected_household_id)
		if not household.is_empty():
			lines.append("\n[b]Household[/b] %d · %s" % [household.get("id", -1), household.get("kind", "home")])
			var member_ids: Array = household.get("member_ids", [])
			lines.append("Members: %s" % str(member_ids))
			lines.append("Building: %s" % household.get("building_id", -1))
	if lines.is_empty():
		lines.append("[b]Selection[/b]\nClick a resident in the world or use the buttons below to inspect residents or households.")
	details.text = "\n".join(lines)


func _update_list_panel(events: Array) -> void:
	var list_label := get_node_or_null("Panel/Margin/VBox/List") as RichTextLabel
	if list_label == null:
		return
	var lines: Array[String] = ["[b]Event feed[/b]"]
	if events.is_empty():
		lines.append("No life events yet.")
	else:
		for index in range(events.size() - 1, -1, -1):
			var event = events[index]
			if event is Dictionary:
				var entry: Dictionary = event
				lines.append("%s Y%s D%s · %s" % [
					_event_prefix(str(entry.get("type", "system"))),
					entry.get("year", "?"),
					entry.get("day_of_year", "?"),
					str(entry.get("text", "event"))
				])
			else:
				lines.append("• %s" % str(event))
	list_label.text = "\n".join(lines)


func _update_events(events: Array) -> void:
	var log := get_node_or_null("Panel/Margin/VBox/Events") as RichTextLabel
	if log == null:
		return
	var lines: Array[String] = ["[b]View[/b]"]
	var summary: Dictionary = _population.call("get_population_summary") if _population != null and _population.has_method("get_population_summary") else {}
	lines.append("Mode: %s" % _current_view_label())
	lines.append("Phase: %s" % str(summary.get("day_phase", "day")))
	lines.append("Move: arrows | Toggle view: V")
	lines.append("Blue hour is around sunrise/sunset; moon shows best near sunset/night.")
	lines.append("Click a resident to inspect their lineage.")
	lines.append("Names appear when residents are near you.")
	if not events.is_empty() and events[events.size() - 1] is Dictionary:
		var latest: Dictionary = events[events.size() - 1]
		lines.append("")
		lines.append("[b]Latest life event[/b]")
		lines.append("%s %s" % [_event_prefix(str(latest.get("type", "system"))), str(latest.get("text", "event"))])
	log.text = "\n".join(lines)


func _event_prefix(event_type: String) -> String:
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


func _tracked_person_ids() -> Array:
	var ids: Array = []
	if _selected_person_id != -1:
		_append_related_person_ids(ids, _selected_person_id)
	if _selected_household_id != -1 and _population != null and _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", _selected_household_id)
		for member_id in household.get("member_ids", []):
			var resolved_id: int = int(member_id)
			_append_related_person_ids(ids, resolved_id)
	return ids


func _append_related_person_ids(ids: Array, seed_id: int) -> void:
	if seed_id == -1 or ids.has(seed_id):
		return
	ids.append(seed_id)
	if _population == null or not _population.has_method("get_person"):
		return
	var person: Dictionary = _population.call("get_person", seed_id)
	if person.is_empty():
		return
	for related_id in [person.get("spouse_id", -1), person.get("father_id", -1), person.get("mother_id", -1)]:
		var resolved_id: int = int(related_id)
		if resolved_id != -1 and not ids.has(resolved_id):
			ids.append(resolved_id)
	for child_id in person.get("child_ids", []):
		var resolved_child_id: int = int(child_id)
		if resolved_child_id != -1 and not ids.has(resolved_child_id):
			ids.append(resolved_child_id)
	if _population.has_method("get_social_bonds"):
		for bond in _population.call("get_social_bonds", seed_id, 4):
			var bonded_id: int = int(Dictionary(bond).get("target_id", -1))
			if bonded_id != -1 and not ids.has(bonded_id):
				ids.append(bonded_id)


func _sync_tracked_visualization() -> void:
	if _crowd != null and _crowd.has_method("set_tracked_people"):
		_crowd.call("set_tracked_people", _tracked_person_ids())


func _update_tracked_birthdays() -> void:
	if _population == null or not _population.has_method("get_person"):
		return
	var next_ages: Dictionary = {}
	for person_id in _tracked_person_ids():
		var person: Dictionary = _population.call("get_person", int(person_id))
		if person.is_empty() or not bool(person.get("alive", true)):
			continue
		var resolved_id: int = int(person.get("id", -1))
		var age: int = int(person.get("age", 0))
		next_ages[resolved_id] = age
		if _tracked_ages_by_id.has(resolved_id) and int(_tracked_ages_by_id[resolved_id]) < age and _crowd != null and _crowd.has_method("play_life_event_effect"):
			_crowd.call("play_life_event_effect", {
				"type": "birthday",
				"person_ids": [resolved_id],
				"text": "Birthday: %s turned %d." % [person.get("full_name", "Resident"), age]
			})
	_tracked_ages_by_id = next_ages


func _on_life_event(_event: Dictionary) -> void:
	# Crowd handles simulator life-event playback directly; UI only injects extra birthday popups.
	return


func _on_toggle_pause() -> void:
	if _population != null and _population.has_method("toggle_paused"):
		_population.call("toggle_paused")
	_update_ui()


func _on_cycle_speed() -> void:
	if _population != null and _population.has_method("cycle_time_scale"):
		_population.call("cycle_time_scale")
	_update_ui()


func _on_advance_6_hours() -> void:
	if _population != null and _population.has_method("advance_hours"):
		_population.call("advance_hours", 6.0)
	_update_ui()


func _on_advance_year() -> void:
	if _population != null and _population.has_method("advance_years"):
		_population.call("advance_years", 1)
	_update_ui()


func _on_next_resident() -> void:
	if _population == null or not _population.has_method("get_population_ids"):
		return
	var resident_ids: Array = _population.call("get_population_ids")
	if resident_ids.is_empty():
		return
	var current_index: int = resident_ids.find(_selected_person_id)
	if current_index == -1:
		current_index = 0
	else:
		current_index = (current_index + 1) % resident_ids.size()
	select_person(int(resident_ids[current_index]))
	_list_mode = "population"
	_page_index = int(floor(float(current_index) / float(_resident_page_size)))


func _on_next_household() -> void:
	if _population == null or not _population.has_method("get_household_ids"):
		return
	var household_ids: Array = _population.call("get_household_ids")
	if household_ids.is_empty():
		return
	var current_index: int = household_ids.find(_selected_household_id)
	if current_index == -1:
		current_index = 0
	else:
		current_index = (current_index + 1) % household_ids.size()
	_selected_household_id = int(household_ids[current_index])
	if _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", _selected_household_id)
		var members: Array = household.get("member_ids", [])
		if not members.is_empty():
			_selected_person_id = int(members[0])
	_list_mode = "households"
	_page_index = int(floor(float(current_index) / float(_household_page_size)))
	_sync_tracked_visualization()
	_update_ui()


func _on_set_ground_view() -> void:
	if _camera != null and _camera.has_method("set_view_mode"):
		_camera.call("set_view_mode", "ground")
	_update_ui()


func _on_set_overlook_view() -> void:
	if _camera != null and _camera.has_method("set_view_mode"):
		_camera.call("set_view_mode", "overlook")
	_update_ui()


func _on_jump_to_latest_event() -> void:
	if _camera == null or _population == null or not _population.has_method("get_recent_event_records"):
		return
	var events: Array = _population.call("get_recent_event_records", 1)
	if events.is_empty() or not (events[0] is Dictionary):
		return
	var anchor: Vector3 = _event_anchor_for(Dictionary(events[0]))
	if anchor == Vector3.INF:
		return
	_camera.position = anchor + Vector3(0.0, 1.65, 0.0)
	if _camera.has_method("set_view_mode"):
		_camera.call("set_view_mode", "ground")


func _on_next_page() -> void:
	return


func _on_jump_to_selection() -> void:
	if _camera == null or _population == null or not _population.has_method("get_person"):
		return
	var person: Dictionary = _population.call("get_person", _selected_person_id)
	if person.is_empty():
		return
	var anchor: Vector3 = Vector3(person.get("home_entry", Vector3.ZERO))
	if _population.has_method("get_person_activity"):
		var activity: Dictionary = _population.call("get_person_activity", _selected_person_id)
		if not activity.is_empty():
			anchor = Vector3(activity.get("target", anchor))
	_camera.position = anchor + Vector3(0.0, 1.65, 0.0)


func select_person(person_id: int) -> void:
	if _population == null or not _population.has_method("get_person"):
		return
	var person: Dictionary = _population.call("get_person", person_id)
	if person.is_empty():
		return
	_selected_person_id = int(person.get("id", -1))
	_selected_household_id = int(person.get("household_id", -1))
	_list_mode = "population"
	_sync_tracked_visualization()
	_update_ui()


func _pick_person_at_screen(screen_position: Vector2) -> void:
	if _crowd == null or _camera == null or not _crowd.has_method("pick_person_from_screen"):
		return
	var hit: Dictionary = _crowd.call("pick_person_from_screen", _camera, screen_position, 38.0)
	if hit.is_empty():
		return
	var person_id: int = int(hit.get("person_id", -1))
	if person_id != -1:
		select_person(person_id)


func _relationship_names(raw_ids: Variant, limit: int = 4) -> String:
	var ids: Array = raw_ids if raw_ids is Array else Array(raw_ids)
	var names: Array[String] = []
	for raw_id in ids:
		var resolved_id: int = int(raw_id)
		if resolved_id == -1:
			continue
		var person: Dictionary = _population.call("get_person", resolved_id) if _population != null and _population.has_method("get_person") else {}
		if person.is_empty():
			continue
		names.append(str(person.get("full_name", "Resident")))
		if names.size() >= limit:
			break
	if names.is_empty():
		return "none listed"
	var overflow: int = maxi(0, ids.size() - names.size())
	return ", ".join(names) + (" +%d more" % overflow if overflow > 0 else "")


func _sibling_names_for(person: Dictionary) -> String:
	if _population == null or not _population.has_method("get_sibling_ids"):
		return "none listed"
	var person_id: int = int(person.get("id", -1))
	var sibling_ids: Array = _population.call("get_sibling_ids", person_id, true)
	if sibling_ids.is_empty():
		return "none listed"
	var names: Array[String] = []
	for sibling_id in sibling_ids:
		var sibling: Dictionary = _population.call("get_person", int(sibling_id))
		if sibling.is_empty():
			continue
		names.append(str(sibling.get("full_name", "Resident")))
		if names.size() >= 4:
			break
	var overflow: int = maxi(0, sibling_ids.size() - names.size())
	return ", ".join(names) + (" +%d more" % overflow if overflow > 0 else "")


func _lineage_member_summary(lineage_id: String, selected_person_id: int) -> String:
	if _population == null or not _population.has_method("get_lineage_member_ids"):
		return "unknown"
	var lineage_ids: Array = _population.call("get_lineage_member_ids", lineage_id, true)
	var names: Array[String] = []
	var total: int = 0
	for candidate_id_raw in lineage_ids:
		var candidate_id: int = int(candidate_id_raw)
		total += 1
		if candidate_id == selected_person_id:
			continue
		var entry: Dictionary = _population.call("get_person", candidate_id)
		if entry.is_empty():
			continue
		if names.size() < 5:
			names.append(str(entry.get("full_name", "Resident")))
	if total <= 1:
		return "only known member"
	return ", ".join(names) + (" +%d more" % maxi(0, total - 1 - names.size()) if total - 1 > names.size() else "")


func _join_strings(items: Array) -> String:
	var parts: Array[String] = []
	for item in items:
		parts.append(str(item))
	return ", ".join(parts)


func _current_view_mode() -> String:
	if _camera != null and _camera.has_method("get_view_mode"):
		return str(_camera.call("get_view_mode"))
	return "ground"


func _current_view_label() -> String:
	if _camera != null and _camera.has_method("get_view_mode_label"):
		return str(_camera.call("get_view_mode_label"))
	return "Ground"


func _event_anchor_for(event: Dictionary) -> Vector3:
	if _population == null or not _population.has_method("get_person"):
		return Vector3.INF
	var household_id: int = int(event.get("household_id", -1))
	if household_id != -1 and _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", household_id)
		for member_id in household.get("member_ids", []):
			var person: Dictionary = _population.call("get_person", int(member_id))
			if not person.is_empty() and person.has("home_entry"):
				return Vector3(person.get("home_entry", Vector3.ZERO))
	for person_id in event.get("person_ids", []):
		var event_person: Dictionary = _population.call("get_person", int(person_id))
		if not event_person.is_empty() and event_person.has("home_entry"):
			return Vector3(event_person.get("home_entry", Vector3.ZERO))
	return Vector3.INF
