extends CanvasLayer
class_name PopulationUI

const CHAT_BOX_COUNT := 3
const SUMMARY_PATH := "Panel/Margin/VBox/Summary"
const SELECTION_PATH := "Panel/Margin/VBox/Selection"
const LIST_PATH := "Panel/Margin/VBox/List"
const EVENTS_PATH := "Panel/Margin/VBox/Events"
const TOGGLE_PAUSE_PATH := "Panel/Margin/VBox/Controls/TogglePause"
const TOGGLE_VIEW_PATH := "Panel/Margin/VBox/Controls/ShowPopulation"
const LATEST_EVENT_PATH := "Panel/Margin/VBox/Controls/PrevPage"

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
var _conversation_overlay: Control
var _conversation_boxes: Array = []
var _summary_label: RichTextLabel
var _selection_label: RichTextLabel
var _list_label: RichTextLabel
var _events_label: RichTextLabel
var _pause_button: Button
var _toggle_view_button: Button
var _latest_event_button: Button
var _fps_label: Label


func _ready() -> void:
	_population = get_node_or_null(population_path)
	_crowd = get_node_or_null(crowd_path)
	_camera = get_node_or_null(camera_path) as Camera3D
	_summary_label = get_node_or_null(SUMMARY_PATH) as RichTextLabel
	_selection_label = get_node_or_null(SELECTION_PATH) as RichTextLabel
	_list_label = get_node_or_null(LIST_PATH) as RichTextLabel
	_events_label = get_node_or_null(EVENTS_PATH) as RichTextLabel
	_pause_button = get_node_or_null(TOGGLE_PAUSE_PATH) as Button
	_toggle_view_button = get_node_or_null(TOGGLE_VIEW_PATH) as Button
	_latest_event_button = get_node_or_null(LATEST_EVENT_PATH) as Button
	_ensure_conversation_boxes()
	if _population != null and _population.has_signal("life_event") and not _population.is_connected("life_event", Callable(self, "_on_life_event")):
		_population.connect("life_event", Callable(self, "_on_life_event"))
	_wire_button(TOGGLE_PAUSE_PATH, _on_toggle_pause)
	_wire_button("Panel/Margin/VBox/Controls/AdvanceYear", _on_advance_year)
	_wire_button("Panel/Margin/VBox/Controls/NextResident", _on_next_resident)
	_wire_button("Panel/Margin/VBox/Controls/NextHousehold", _on_next_household)
	_wire_button(TOGGLE_VIEW_PATH, _on_toggle_view)
	_wire_button(LATEST_EVENT_PATH, _on_jump_to_latest_event)
	# FPS counter — top-right corner
	_fps_label = Label.new()
	_fps_label.name = "FPSCounter"
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-10.0, 10.0)
	_fps_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 0.85))
	_fps_label.add_theme_font_size_override("font_size", 14)
	add_child(_fps_label)
	for hidden_path in [
		"Panel/Margin/VBox/Controls/CycleSpeed",
		"Panel/Margin/VBox/Controls/Advance6Hours",
		"Panel/Margin/VBox/Controls/JumpToSelection",
		"Panel/Margin/VBox/Controls/ShowHouseholds",
		"Panel/Margin/VBox/Controls/NextPage",
		"Panel/Margin/VBox/Controls/Spacer"
	]:
		var hidden_control := get_node_or_null(hidden_path) as Control
		if hidden_control != null:
			hidden_control.visible = false
	if _population != null and _population.has_method("get_random_residents"):
		var residents: Array = _population.call("get_random_residents", 1)
		if not residents.is_empty():
			_selected_person_id = int(residents[0].get("id", -1))
			_selected_household_id = int(residents[0].get("household_id", -1))
	_sync_tracked_visualization()
	_update_ui()


func _process(delta: float) -> void:
	# FPS counter — every frame
	if _fps_label != null:
		var fps: int = Performance.get_monitor(Performance.TIME_FPS)
		var objects: int = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var prims: int = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		_fps_label.text = "%d FPS | %d obj | %dK tri | %d nodes" % [fps, objects, prims / 1000, nodes]
	_refresh_accum += delta
	if _refresh_accum >= 0.25:
		_refresh_accum = 0.0
		_update_ui()
	_update_conversation_boxes()


func get_chat_box_count() -> int:
	return _conversation_boxes.size()


func get_visible_chat_box_count() -> int:
	var count: int = 0
	for box in _conversation_boxes:
		var control := box as Control
		if control != null and control.visible:
			count += 1
	return count


func _ensure_conversation_boxes() -> void:
	if _conversation_overlay != null:
		return
	_conversation_overlay = Control.new()
	_conversation_overlay.name = "ConversationOverlay"
	_conversation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_conversation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_conversation_overlay)
	for index in range(CHAT_BOX_COUNT):
		var box := PanelContainer.new()
		box.name = "ChatBox%d" % index
		box.visible = false
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.size = Vector2(240.0, 88.0)
		var margin := MarginContainer.new()
		margin.name = "BubbleMargin"
		margin.set("theme_override_constants/margin_left", 10)
		margin.set("theme_override_constants/margin_top", 6)
		margin.set("theme_override_constants/margin_right", 10)
		margin.set("theme_override_constants/margin_bottom", 6)
		box.add_child(margin)
		var label := Label.new()
		label.name = "Text"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(220.0, 74.0)
		margin.add_child(label)
		_conversation_overlay.add_child(box)
		_conversation_boxes.append(box)


func _update_conversation_boxes() -> void:
	for box in _conversation_boxes:
		var control := box as Control
		if control != null:
			control.visible = false
	if _crowd == null or not _crowd.has_method("get_conversation_chat_snapshot"):
		return
	var chat_snapshot: Array = _crowd.call("get_conversation_chat_snapshot")
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var box_index: int = 0
	for entry in chat_snapshot:
		if box_index >= _conversation_boxes.size():
			break
		var entry_data: Dictionary = Dictionary(entry)
		var world_point: Vector3 = Vector3(entry_data.get("speaker_position", Vector3.ZERO))
		var box := _conversation_boxes[box_index] as PanelContainer
		var label := box.get_node_or_null("BubbleMargin/Text") as Label
		if label == null:
			continue
		label.text = str(entry_data.get("text", ""))
		var screen_point: Vector2 = _speech_screen_point(world_point, viewport_rect)
		if screen_point == Vector2.INF:
			continue
		box.position = _clamped_speech_box_position(screen_point, box.size, viewport_rect, box_index)
		box.visible = true
		box_index += 1


func _speech_screen_point(world_point: Vector3, viewport_rect: Rect2) -> Vector2:
	if _camera == null:
		return Vector2.INF
	if _camera.is_position_behind(world_point):
		return Vector2.INF
	var projected: Vector2 = _camera.unproject_position(world_point)
	if not is_finite(projected.x) or not is_finite(projected.y):
		return Vector2.INF
	if not viewport_rect.has_point(projected):
		return Vector2.INF
	return projected


func _clamped_speech_box_position(screen_point: Vector2, box_size: Vector2, viewport_rect: Rect2, box_index: int) -> Vector2:
	var margin: float = 12.0
	var desired: Vector2 = screen_point - box_size * Vector2(0.5, 1.0) - Vector2(0.0, 10.0)
	var min_position: Vector2 = viewport_rect.position + Vector2(margin, margin)
	var max_position: Vector2 = viewport_rect.end - box_size - Vector2(margin, margin)
	if max_position.x < min_position.x:
		max_position.x = min_position.x
	if max_position.y < min_position.y:
		max_position.y = min_position.y
	desired.x = clampf(desired.x, min_position.x, max_position.x)
	desired.y = clampf(desired.y, min_position.y, max_position.y)
	if box_index > 0 and desired.y >= max_position.y - 1.0:
		desired.y = maxf(min_position.y, desired.y - float(box_index) * (box_size.y + 8.0))
	return desired


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
	if _summary_label != null:
		var api_status: Dictionary = _crowd.call("get_api_detection_snapshot") if _crowd != null and _crowd.has_method("get_api_detection_snapshot") else {}
		var summary_lines: Array[String] = [
			"[b]%s[/b]" % summary.get("time_label", "Time unavailable"),
			"Population: %d | Households: %d | Lineages: %d" % [summary.get("population", 0), summary.get("households", 0), summary.get("lineages", 0)],
			"Children: %d | Adults: %d | Seniors: %d | Workers: %d" % [summary.get("children", 0), summary.get("adults", 0), summary.get("seniors", 0), summary.get("workers", 0)],
			"Births: %d | Deaths: %d | Crowd shown: %d" % [summary.get("births", 0), summary.get("deaths", 0), _crowd.get_pedestrian_count() if _crowd != null and _crowd.has_method("get_pedestrian_count") else 0]
		]
		if not api_status.is_empty():
			summary_lines.append("OpenRouter key: %s" % ("detected" if bool(api_status.get("text", false)) else "missing"))
		_summary_label.text = "\n".join(summary_lines)
	if _pause_button != null:
		_pause_button.text = "Resume" if bool(summary.get("paused", false)) else "Pause"
	if _toggle_view_button != null:
		_toggle_view_button.text = "View: %s" % _current_view_label()
	if _latest_event_button != null:
		_latest_event_button.text = "Latest event"
	_update_selection_details()
	var recent_events: Array = snapshot.get("recent_event_records", snapshot.get("recent_events", []))
	_update_list_panel(recent_events)
	_update_events(recent_events)
	_sync_tracked_visualization()
	_update_tracked_birthdays()


func _update_selection_details() -> void:
	if _selection_label == null:
		return
	var lines: Array[String] = []
	if _selected_person_id != -1 and _population.has_method("get_person"):
		var person: Dictionary = _population.call("get_person", _selected_person_id)
		if not person.is_empty():
			lines.append("[b]Resident[/b]: %s" % person.get("full_name", "Resident"))
			lines.append("Age %d | %s | %s" % [person.get("age", 0), person.get("occupation", "local"), "alive" if bool(person.get("alive", true)) else "deceased"])
			lines.append("Lineage %s | Generation %s | Household %s" % [person.get("lineage_id", "?"), person.get("generation", "?"), person.get("household_id", "?")])
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
						lines.append("  - %s %s (%s%d)" % [bond.get("target_name", "Resident"), bond.get("kind", "social"), sign, score])
	if _selected_household_id != -1 and _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", _selected_household_id)
		if not household.is_empty():
			lines.append("\n[b]Household[/b] %d | %s" % [household.get("id", -1), household.get("kind", "home")])
			var member_ids: Array = household.get("member_ids", [])
			lines.append("Members: %s" % str(member_ids))
			lines.append("Building: %s" % household.get("building_id", -1))
	if lines.is_empty():
		lines.append("[b]Selection[/b]\nClick a resident in the world or use the buttons below to inspect residents or households.")
	_selection_label.text = "\n".join(lines)


func _update_list_panel(events: Array) -> void:
	if _list_label == null:
		return
	var lines: Array[String] = ["[b]Event feed[/b]"]
	if events.is_empty():
		lines.append("No life events yet.")
	else:
		for index in range(events.size() - 1, -1, -1):
			var event = events[index]
			if event is Dictionary:
				var entry: Dictionary = event
				lines.append("%s Y%s D%s | %s" % [
					_event_prefix(str(entry.get("type", "system"))),
					entry.get("year", "?"),
					entry.get("day_of_year", "?"),
					str(entry.get("text", "event"))
				])
			else:
				lines.append("- %s" % str(event))
	_list_label.text = "\n".join(lines)


func _update_events(events: Array) -> void:
	if _events_label == null:
		return
	var lines: Array[String] = ["[b]View[/b]"]
	var summary: Dictionary = _population.call("get_population_summary") if _population != null and _population.has_method("get_population_summary") else {}
	lines.append("Mode: %s" % _current_view_label())
	lines.append("Phase: %s" % str(summary.get("day_phase", "day")))
	lines.append("Move: arrows | View toggle: V")
	lines.append("Blue hour is around sunrise/sunset; moon shows best near sunset/night.")
	lines.append("Click a resident to inspect them and trigger a quick chat.")
	lines.append("Names appear when residents are near you.")
	var api_status: Dictionary = _crowd.call("get_api_detection_snapshot") if _crowd != null and _crowd.has_method("get_api_detection_snapshot") else {}
	if not api_status.is_empty():
		if not bool(api_status.get("text", false)):
			lines.append("")
			lines.append("OpenRouter text is disabled until OPENROUTER_API_KEY is visible to Godot.")
	if not events.is_empty() and events[events.size() - 1] is Dictionary:
		var latest: Dictionary = events[events.size() - 1]
		lines.append("")
		lines.append("[b]Latest life event[/b]")
		lines.append("%s %s" % [_event_prefix(str(latest.get("type", "system"))), str(latest.get("text", "event"))])
	_events_label.text = "\n".join(lines)


func _event_prefix(event_type: String) -> String:
	match event_type:
		"birth":
			return "[Birth]"
		"marriage":
			return "[Marriage]"
		"birthday":
			return "[Birthday]"
		"death":
			return "[Death]"
		_:
			return "[Event]"


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


func _on_toggle_view() -> void:
	if _camera != null and _camera.has_method("toggle_view_mode"):
		_camera.call("toggle_view_mode")
	elif _current_view_mode() == "overlook":
		_on_set_ground_view()
		return
	else:
		_on_set_overlook_view()
		return
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


func select_person(person_id: int, sync_visualization: bool = true) -> void:
	if _population == null or not _population.has_method("get_person"):
		return
	var person: Dictionary = _population.call("get_person", person_id)
	if person.is_empty():
		return
	_selected_person_id = int(person.get("id", -1))
	_selected_household_id = int(person.get("household_id", -1))
	_list_mode = "population"
	if sync_visualization:
		_sync_tracked_visualization()
	_update_ui()


func _pick_person_at_screen(screen_position: Vector2) -> void:
	if _crowd == null or _camera == null or not _crowd.has_method("pick_person_from_screen"):
		return
	var hit: Dictionary = _crowd.call("pick_person_from_screen", _camera, screen_position, 70.0)
	if hit.is_empty():
		return
	var person_id: int = int(hit.get("person_id", -1))
	if person_id != -1:
		var started: bool = false
		if _crowd.has_method("trigger_player_conversation_for_pedestrian"):
			started = bool(_crowd.call("trigger_player_conversation_for_pedestrian", int(hit.get("ped_index", -1))))
		elif _crowd.has_method("trigger_player_conversation_for_person"):
			started = bool(_crowd.call("trigger_player_conversation_for_person", person_id))
		select_person(person_id, not started)


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
