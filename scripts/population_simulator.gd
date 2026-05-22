extends Node
class_name PopulationSimulator

signal population_regenerated(summary: Dictionary)
signal life_event(event: Dictionary)

const MALE_FIRST_NAMES := [
	"Samuel", "Elias", "Noah", "Mateo", "Theo", "Julian", "Micah", "Leo", "Owen", "Gabriel",
	"Adrian", "Isaac", "Henry", "Miles", "Daniel", "Victor", "Hugo", "Felix", "Roman", "Lucas"
]
const FEMALE_FIRST_NAMES := [
	"Clara", "Maya", "Elena", "Sofia", "Lila", "Nora", "Iris", "Hazel", "Camila", "Eva",
	"Lucia", "Amelia", "Naomi", "Ruby", "June", "Celine", "Vera", "Alice", "Ines", "Leona"
]
const LAST_NAMES := [
	"Martinez", "Sullivan", "Nguyen", "Rivera", "Patel", "Morrison", "Alvarez", "Bennett", "Kim", "Rossi",
	"Delgado", "Hughes", "Santos", "Brooks", "Ramirez", "Khan", "Haddad", "Mori", "Silva", "Bauer"
]
const ADULT_JOBS := [
	"barista", "teacher", "electrician", "nurse", "clerk", "cook", "designer", "gardener", "driver", "bookseller",
	"musician", "tailor", "baker", "developer", "caretaker", "planner", "mechanic", "photographer"
]
const SENIOR_JOBS := ["retired teacher", "retired carpenter", "retired nurse", "retired clerk", "retired tailor"]
const CHILD_ROLES := ["student", "student", "student", "teen helper", "little explorer"]
const SPEED_PRESETS := [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 6.0, 24.0]
const STRONG_BOND_THRESHOLD := 45
const MARRIAGE_BOND_THRESHOLD := 36
const LIFE_EVENT_CYCLE_DAYS := 30
const YEAR_EPOCH_HOUR := 5.0
const SUNRISE_HOUR := 6.0
const SUNSET_HOUR := 18.3
const VISUAL_PREDAWN_LENGTH := 1.5
const VISUAL_SUNRISE_LENGTH := 7.0
const VISUAL_DAY_LENGTH := 5.0
const VISUAL_SUNSET_LENGTH := 8.0
const VISUAL_LATE_NIGHT_LENGTH := 2.5

@export var city_path: NodePath
@export var min_population: int = 64
@export var max_population: int = 180
@export_range(0.2, 4.0, 0.1) var residents_per_block: float = 1.1
@export var simulation_year: int = 2026
@export var start_day_of_year: int = 120
@export var start_hour: float = 8.0
@export var hours_per_second: float = 0.25

var _city: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_person_id: int = 1
var _next_household_id: int = 1
var _lineage_index: int = 1
var _people: Array = []
var _people_by_id: Dictionary = {}
var _households: Array = []
var _households_by_id: Dictionary = {}
var _blocks: Array = []
var _building_slots: Array = []
var _building_by_id: Dictionary = {}
var _building_occupancy: Dictionary = {}
var _current_year: int = 2026
var _current_day_of_year: int = 120
var _current_hour: float = 8.0
var _paused: bool = false
var _speed_index: int = 2
var _birth_count: int = 0
var _death_count: int = 0
var _recent_events: Array[String] = []
var _recent_event_records: Array[Dictionary] = []


func _ready() -> void:
	_resolve_city()
	call_deferred("generate_population")


func _process(delta: float) -> void:
	if _paused:
		return
	advance_hours(delta * hours_per_second)


func generate_population() -> void:
	_resolve_city()
	_people.clear()
	_people_by_id.clear()
	_households.clear()
	_households_by_id.clear()
	_building_occupancy.clear()
	_recent_events.clear()
	_recent_event_records.clear()
	_birth_count = 0
	_death_count = 0
	_next_person_id = 1
	_next_household_id = 1
	_lineage_index = 1
	_current_year = simulation_year
	_current_day_of_year = 1
	_current_hour = start_hour
	_paused = false
	_sync_speed_index_to_current_scale()
	_seed_rng()
	_blocks = _fetch_blocks()
	_building_slots = _fetch_buildings()
	_building_by_id.clear()
	for slot in _building_slots:
		_building_by_id[slot.get("id", "")] = slot
	var target_population: int = _target_population()
	while get_population_size() < target_population:
		_build_lineage(target_population)
	_assign_workplaces()
	_seed_social_bonds()
	_form_relationship_marriages(6)
	_log_event("Population seeded: %d residents across %d households." % [get_population_size(), _households.size()])
	emit_signal("population_regenerated", get_population_summary())


func get_population_size() -> int:
	var alive_count: int = 0
	for person in _people:
		if bool(person.get("alive", true)):
			alive_count += 1
	return alive_count


func get_population_snapshot(include_deceased: bool = true) -> Array:
	var result: Array = []
	for person in _people:
		if include_deceased or bool(person.get("alive", true)):
			result.append(person.duplicate(true))
	return result


func get_households_snapshot() -> Array:
	return _households.duplicate(true)


func get_population_ids() -> Array:
	var ids: Array = []
	for person in _people:
		if bool(person.get("alive", true)):
			ids.append(int(person.get("id", -1)))
	return ids


func get_household_ids() -> Array:
	var ids: Array = []
	for household in _households:
		ids.append(int(household.get("id", -1)))
	return ids


func get_population_page(page_index: int = 0, page_size: int = 14) -> Dictionary:
	var alive_people: Array = []
	for person in _people:
		if bool(person.get("alive", true)):
			alive_people.append(person)
	var start: int = maxi(0, page_index) * maxi(1, page_size)
	var items: Array = []
	for index in range(start, mini(start + page_size, alive_people.size())):
		var person: Dictionary = alive_people[index]
		var bonds: Array = get_social_bonds(int(person.get("id", -1)), 1)
		items.append({
			"id": person.get("id", -1),
			"full_name": person.get("full_name", "Resident"),
			"age": person.get("age", 0),
			"occupation": person.get("occupation", "local"),
			"household_id": person.get("household_id", -1),
			"home_building_id": person.get("home_building_id", -1),
			"top_bond": bonds[0] if not bonds.is_empty() else {}
		})
	return {
		"page": maxi(0, page_index),
		"page_size": maxi(1, page_size),
		"total": alive_people.size(),
		"items": items
	}


func get_household_page(page_index: int = 0, page_size: int = 10) -> Dictionary:
	var start: int = maxi(0, page_index) * maxi(1, page_size)
	var items: Array = []
	for index in range(start, mini(start + page_size, _households.size())):
		var household: Dictionary = _households[index]
		var member_names: Array = []
		for member_id in household.get("member_ids", []):
			var person: Dictionary = _people_by_id.get(member_id, {})
			if not person.is_empty() and bool(person.get("alive", true)):
				member_names.append(person.get("full_name", "Resident"))
		items.append({
			"id": household.get("id", -1),
			"kind": household.get("kind", "home"),
			"building_id": household.get("building_id", -1),
			"member_count": household.get("member_ids", []).size(),
			"member_names": member_names,
			"lineage_id": household.get("lineage_id", "L000")
		})
	return {
		"page": maxi(0, page_index),
		"page_size": maxi(1, page_size),
		"total": _households.size(),
		"items": items
	}


func get_social_bonds(person_id: int, limit: int = 6) -> Array:
	var person: Dictionary = _people_by_id.get(person_id, {})
	if person.is_empty():
		return []
	var bonds_dict: Dictionary = person.get("social_bonds", {})
	var entries: Array = []
	for target_key in bonds_dict.keys():
		var bond: Dictionary = bonds_dict[target_key]
		var target_id: int = int(target_key)
		var target_person: Dictionary = _people_by_id.get(target_id, {})
		entries.append({
			"target_id": target_id,
			"target_name": target_person.get("full_name", "Resident %d" % target_id),
			"score": int(bond.get("score", 0)),
			"kind": bond.get("kind", "social"),
			"alive": target_person.get("alive", true)
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return abs(int(a.get("score", 0))) > abs(int(b.get("score", 0)))
	)
	return entries.slice(0, mini(limit, entries.size()))


func get_population_summary() -> Dictionary:
	var lineages: Dictionary = {}
	var children: int = 0
	var adults: int = 0
	var seniors: int = 0
	var workers: int = 0
	for person in _people:
		if not bool(person.get("alive", true)):
			continue
		lineages[person["lineage_id"]] = true
		var age: int = int(person["age"])
		if age < 18:
			children += 1
		elif age >= 62:
			seniors += 1
		else:
			adults += 1
		if str(person.get("work_building_id", -1)) != "-1":
			workers += 1
	return {
		"population": get_population_size(),
		"households": _households.size(),
		"lineages": lineages.size(),
		"children": children,
		"adults": adults,
		"seniors": seniors,
		"workers": workers,
		"births": _birth_count,
		"deaths": _death_count,
		"year": _current_year,
		"day_of_year": _current_day_of_year,
		"hour": snappedf(_current_hour, 0.01),
		"day_phase": get_day_phase_label(),
		"time_label": get_time_label(),
		"time_scale": hours_per_second,
		"paused": _paused,
		"recent_events": _recent_events.duplicate()
	}


func get_time_label() -> String:
	return "Year %d · %s · %s" % [_current_year, get_day_phase_label(), _hour_label(_current_hour)]


func get_day_phase_label() -> String:
	if _current_hour < YEAR_EPOCH_HOUR:
		return "night"
	if _current_hour < SUNRISE_HOUR + 1.0:
		return "sunrise"
	if _current_hour < SUNSET_HOUR - 1.2:
		return "day"
	if _current_hour < SUNSET_HOUR + 1.5:
		return "sunset"
	return "night"


func get_recent_events(limit: int = 8) -> Array:
	var start: int = maxi(0, _recent_events.size() - limit)
	return _recent_events.slice(start, _recent_events.size())


func get_recent_event_records(limit: int = 8) -> Array:
	var start: int = maxi(0, _recent_event_records.size() - limit)
	return _recent_event_records.slice(start, _recent_event_records.size())


func get_random_residents(count: int) -> Array:
	var alive_people: Array = []
	for person in _people:
		if bool(person.get("alive", true)):
			alive_people.append(person.duplicate(true))
	_shuffle_array(alive_people)
	return alive_people.slice(0, mini(count, alive_people.size()))


func get_person(person_id: int) -> Dictionary:
	var person: Dictionary = _people_by_id.get(person_id, {})
	return person.duplicate(true) if not person.is_empty() else {}


func get_household(household_id: int) -> Dictionary:
	var household: Dictionary = _households_by_id.get(household_id, {})
	return household.duplicate(true) if not household.is_empty() else {}


func get_sibling_ids(person_id: int, include_deceased: bool = true) -> Array:
	var person: Dictionary = _people_by_id.get(person_id, {})
	if person.is_empty():
		return []
	var father_id: int = int(person.get("father_id", -1))
	var mother_id: int = int(person.get("mother_id", -1))
	if father_id == -1 and mother_id == -1:
		return []
	var siblings: Array = []
	for candidate in _people:
		var candidate_id: int = int(candidate.get("id", -1))
		if candidate_id == person_id:
			continue
		if not include_deceased and not bool(candidate.get("alive", true)):
			continue
		if (father_id != -1 and int(candidate.get("father_id", -2)) == father_id) or (mother_id != -1 and int(candidate.get("mother_id", -2)) == mother_id):
			siblings.append(candidate_id)
	return siblings


func get_lineage_member_ids(lineage_id: String, include_deceased: bool = true) -> Array:
	var members: Array = []
	for person in _people:
		if str(person.get("lineage_id", "")) != lineage_id:
			continue
		if not include_deceased and not bool(person.get("alive", true)):
			continue
		members.append(int(person.get("id", -1)))
	return members


func get_dashboard_snapshot() -> Dictionary:
	var featured_people: Array = get_random_residents(5)
	var featured_households: Array = []
	for household in _households.slice(0, mini(5, _households.size())):
		featured_households.append(household.duplicate(true))
	return {
		"summary": get_population_summary(),
		"featured_people": featured_people,
		"featured_households": featured_households,
		"recent_events": get_recent_events(8),
		"recent_event_records": get_recent_event_records(8)
	}


func get_visual_time_state() -> Dictionary:
	return {
		"year": _current_year,
		"day_of_year": _current_day_of_year,
		"hour": snappedf(_current_hour, 0.01),
		"day_phase": get_day_phase_label(),
		"time_label": get_time_label(),
		"time_scale": hours_per_second,
		"paused": _paused
	}


func get_person_activity(person_id: int) -> Dictionary:
	var person: Dictionary = _people_by_id.get(person_id, {})
	if person.is_empty() or not bool(person.get("alive", true)):
		return {}
	var routine_seed: int = person_id * 17 + _current_year * 3 + _current_day_of_year * 11
	var routine_roll: int = _positive_modulo(routine_seed, 100)
	var mode: String = "home"
	var target: Vector3 = Vector3(person.get("home_entry", Vector3.ZERO))
	var hour: float = _current_hour
	var age: int = int(person.get("age", 0))
	var work_building_id: Variant = person.get("work_building_id", -1)
	if hour >= 7.25 and hour < 9.0 and str(work_building_id) != "-1" and routine_roll < 72:
		mode = "commute"
		target = _pick_promenade_target_near(Vector3(person.get("work_entry", target)), person_id, 9.0)
	elif age < 18 and hour >= 7.5 and hour < 15.5 and str(work_building_id) != "-1":
		mode = "school"
		target = Vector3(person.get("work_entry", target))
		if hour >= 11.5 and hour <= 13.5 and routine_roll < 34:
			mode = "market"
			target = _pick_destination_for_person(person, ["plaza", "mixed_use", "civic_landmark"])
	elif hour >= 8.0 and hour < 17.0 and str(work_building_id) != "-1":
		mode = "work"
		target = Vector3(person.get("work_entry", target))
		if hour >= 11.5 and hour <= 14.5 and routine_roll < 42:
			mode = "market"
			target = _pick_destination_for_person(person, ["plaza", "mixed_use", "civic_landmark"])
	elif hour >= 17.0 and hour < 20.75:
		if routine_roll < 60:
			mode = "plaza"
			target = _pick_destination_for_person(person, ["plaza", "mixed_use", "civic_landmark"])
		else:
			mode = "wander"
			target = _random_walk_anchor_near(Vector3(person.get("home_entry", target)), 16.0 if age < 18 else 12.5)
	elif hour >= 20.75 and hour < 22.5 and routine_roll < 28:
		mode = "evening_stroll"
		target = _pick_promenade_target_near(Vector3(person.get("home_entry", target)), person_id + 17, 11.0)
	return {
		"mode": mode,
		"target": target,
		"label": "%s → %s" % [person.get("full_name", "Resident"), mode]
	}


func get_resident_anchor(person_id: int, anchor_kind: String = "home") -> Vector3:
	var person: Dictionary = _people_by_id.get(person_id, {})
	if person.is_empty():
		return Vector3.ZERO
	match anchor_kind:
		"work":
			return Vector3(person.get("work_entry", person.get("home_entry", Vector3.ZERO)))
		_:
			return Vector3(person.get("home_entry", Vector3.ZERO))


func set_time_scale(value: float) -> void:
	hours_per_second = maxf(0.0, value)
	_paused = is_zero_approx(hours_per_second)
	_log_event("Time speed set to %.1fx hours/sec." % [hours_per_second])


func cycle_time_scale() -> float:
	_speed_index = (_speed_index + 1) % SPEED_PRESETS.size()
	set_time_scale(float(SPEED_PRESETS[_speed_index]))
	return hours_per_second


func toggle_paused() -> bool:
	_paused = not _paused
	_log_event("Simulation %s." % ["paused" if _paused else "resumed"])
	return _paused


func is_paused() -> bool:
	return _paused


func advance_hours(hours: float) -> void:
	if hours <= 0.0:
		return
	var remaining: float = hours
	while remaining > 0.0001:
		var until_epoch: float = _visual_hours_until_next_year_epoch()
		if remaining < until_epoch - 0.0001:
			var visual_progress: float = _visual_progress_from_clock_hour(_current_hour)
			_current_hour = _clock_hour_from_visual_progress(visual_progress + remaining)
			remaining = 0.0
			continue
		remaining -= until_epoch
		_current_hour = YEAR_EPOCH_HOUR
		_current_year += 1
		_current_day_of_year = 1
		_on_year_passed()
		emit_signal("population_regenerated", get_population_summary())


func advance_years(years: int = 1) -> void:
	for _i in range(maxi(0, years)):
		_current_year += 1
		_current_day_of_year = 1
		_current_hour = YEAR_EPOCH_HOUR
		_on_year_passed(true)
		emit_signal("population_regenerated", get_population_summary())


func focus_random_household() -> Dictionary:
	if _households.is_empty():
		return {}
	return _households[_rng.randi_range(0, _households.size() - 1)].duplicate(true)


func _resolve_city() -> void:
	if city_path != NodePath():
		_city = get_node_or_null(city_path)
	elif get_parent() != null:
		_city = get_parent().get_node_or_null("City")


func _seed_rng() -> void:
	var base_seed: int = 1013
	if _city != null and _city.get("seed_value") != null:
		base_seed = int(_city.get("seed_value"))
	_rng.seed = int(abs(base_seed * 48611 + 9382849))


func _target_population() -> int:
	var block_count: int = _blocks.size()
	if block_count <= 0 and _city != null and _city.get("grid_size") != null:
		var grid: Vector2i = _city.get("grid_size")
		block_count = grid.x * grid.y
	var ideal: int = int(round(float(block_count) * residents_per_block))
	ideal += _rng.randi_range(-4, 7)
	return clampi(ideal, min_population, max_population)


func _fetch_blocks() -> Array:
	if _city != null and _city.has_method("get_block_centers_snapshot"):
		return _city.call("get_block_centers_snapshot")
	return []


func _fetch_buildings() -> Array:
	if _city != null and _city.has_method("get_building_slots_snapshot"):
		return _city.call("get_building_slots_snapshot")
	return []


func _build_lineage(target_population: int) -> void:
	var lineage_id: String = "L%03d" % _lineage_index
	_lineage_index += 1
	var surname: String = _pick(LAST_NAMES)
	var founder_age_a: int = _rng.randi_range(56, 79)
	var founder_age_b: int = clampi(founder_age_a + _rng.randi_range(-5, 4), 52, 82)
	var founder_a := _create_person(lineage_id, _pick(MALE_FIRST_NAMES), surname, "male", founder_age_a, _job_for_age(founder_age_a), 0)
	var founder_b := _create_person(lineage_id, _pick(FEMALE_FIRST_NAMES), surname, "female", founder_age_b, _job_for_age(founder_age_b), 0)
	_link_spouses(founder_a, founder_b)

	var founder_members: Array = [founder_a["id"], founder_b["id"]]
	var child_count: int = _rng.randi_range(1, 4)
	for _child_index in range(child_count):
		var parent_min_age: int = mini(founder_age_a, founder_age_b)
		var adult_child: bool = _rng.randf() < 0.82 or get_population_size() < target_population - 8
		var child_age: int = _rng.randi_range(20, mini(44, parent_min_age - 18)) if adult_child else _rng.randi_range(5, 18)
		var child_gender: String = "female" if _rng.randf() < 0.5 else "male"
		var child_first: String = _pick(FEMALE_FIRST_NAMES) if child_gender == "female" else _pick(MALE_FIRST_NAMES)
		var child := _create_person(lineage_id, child_first, surname, child_gender, child_age, _job_for_age(child_age), 1)
		_link_parent_child(founder_a["id"], child["id"])
		_link_parent_child(founder_b["id"], child["id"])
		if adult_child and get_population_size() < target_population:
			var spouse_gender: String = "male" if child_gender == "female" else "female"
			var spouse_first: String = _pick(MALE_FIRST_NAMES) if spouse_gender == "male" else _pick(FEMALE_FIRST_NAMES)
			var spouse_last: String = surname if _rng.randf() < 0.62 else _pick(LAST_NAMES)
			var spouse_age: int = clampi(child_age + _rng.randi_range(-4, 5), 20, 52)
			var spouse := _create_person(lineage_id, spouse_first, spouse_last, spouse_gender, spouse_age, _job_for_age(spouse_age), 1)
			_link_spouses(child, spouse)
			var household_members: Array = [child["id"], spouse["id"]]
			var grandchild_count: int = _rng.randi_range(0, 3)
			for _grandchild in range(grandchild_count):
				if get_population_size() >= target_population + 8:
					break
				var max_child_age: int = maxi(1, mini(child_age, spouse_age) - 19)
				var grandchild_age: int = _rng.randi_range(0, mini(17, max_child_age))
				var grandchild_gender: String = "female" if _rng.randf() < 0.5 else "male"
				var grandchild_first: String = _pick(FEMALE_FIRST_NAMES) if grandchild_gender == "female" else _pick(MALE_FIRST_NAMES)
				var grandchild := _create_person(lineage_id, grandchild_first, surname, grandchild_gender, grandchild_age, _job_for_age(grandchild_age), 2)
				_link_parent_child(child["id"], grandchild["id"])
				_link_parent_child(spouse["id"], grandchild["id"])
				household_members.append(grandchild["id"])
			_register_household(lineage_id, household_members, "family_unit")
		else:
			founder_members.append(child["id"])

	_register_household(lineage_id, founder_members, "founder_home")


func _create_person(lineage_id: String, first_name: String, last_name: String, gender: String, age: int, occupation: String, generation: int) -> Dictionary:
	var person := {
		"id": _next_person_id,
		"lineage_id": lineage_id,
		"generation": generation,
		"first_name": first_name,
		"last_name": last_name,
		"full_name": "%s %s" % [first_name, last_name],
		"gender": gender,
		"age": age,
		"birth_year": _current_year - age,
		"occupation": occupation,
		"father_id": -1,
		"mother_id": -1,
		"spouse_id": -1,
		"child_ids": [],
		"household_id": -1,
		"home_block": {},
		"home_building_id": -1,
		"home_entry": Vector3.ZERO,
		"work_building_id": -1,
		"work_entry": Vector3.ZERO,
		"social_bonds": {},
		"alive": true,
		"death_year": -1,
		"bio": _bio_for_person(first_name, age, occupation)
	}
	_next_person_id += 1
	_people.append(person)
	_people_by_id[person["id"]] = person
	return person


func _register_household(lineage_id: String, member_ids: Array, household_kind: String) -> Dictionary:
	var household := {
		"id": _next_household_id,
		"lineage_id": lineage_id,
		"kind": household_kind,
		"member_ids": member_ids.duplicate(),
		"block": {},
		"building_id": -1,
		"label": "Household %d" % _next_household_id
	}
	_next_household_id += 1
	_households.append(household)
	_households_by_id[household["id"]] = household
	var assigned := _assign_household_home(household)
	for member_id in member_ids:
		var person: Dictionary = _people_by_id.get(member_id, {})
		if person.is_empty():
			continue
		person["household_id"] = household["id"]
		if not assigned.is_empty():
			person["home_block"] = assigned.get("block", {})
			person["home_building_id"] = assigned.get("building_id", -1)
			person["home_entry"] = assigned.get("entry", Vector3.ZERO)
		_save_person(person)
	return household


func _assign_household_home(household: Dictionary) -> Dictionary:
	var household_size: int = household["member_ids"].size()
	var slot := _pick_building_for_household(household_size)
	if slot.is_empty():
		var fallback_block: Dictionary = _blocks[_rng.randi_range(0, _blocks.size() - 1)] if not _blocks.is_empty() else {}
		household["block"] = fallback_block
		return {"block": fallback_block, "building_id": -1, "entry": Vector3(fallback_block.get("center", Vector3.ZERO))}
	var building_id = slot.get("id", -1)
	_building_occupancy[building_id] = int(_building_occupancy.get(building_id, 0)) + household_size
	household["building_id"] = building_id
	household["block"] = {
		"gx": slot.get("gx", -1),
		"gz": slot.get("gz", -1),
		"center": slot.get("center", Vector3.ZERO),
		"top_y": slot.get("top_y", 0.0)
	}
	_households_by_id[household["id"]] = household
	return {
		"block": household["block"],
		"building_id": building_id,
		"entry": slot.get("entry", slot.get("center", Vector3.ZERO))
	}


func _pick_building_for_household(size_needed: int) -> Dictionary:
	var candidates: Array = []
	for slot in _building_slots:
		var kind: String = str(slot.get("kind", ""))
		if kind != "residence" and kind != "mixed_use":
			continue
		var capacity: int = int(slot.get("capacity", 0))
		var occupied: int = int(_building_occupancy.get(slot.get("id", -1), 0))
		if occupied + size_needed <= capacity:
			candidates.append(slot)
	if candidates.is_empty():
		return {}
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _assign_workplaces() -> void:
	var workplace_slots: Array = []
	for slot in _building_slots:
		if int(slot.get("work_capacity", 0)) > 0:
			workplace_slots.append(slot)
	if workplace_slots.is_empty():
		return
	var occupancy: Dictionary = {}
	for person in _people:
		if not bool(person.get("alive", true)):
			continue
		var age: int = int(person.get("age", 0))
		if age < 7:
			continue
		if age >= 18 and age < 62:
			var work_slot: Dictionary = _pick_workplace_slot(workplace_slots, occupancy)
			if not work_slot.is_empty():
				person["work_building_id"] = work_slot.get("id", -1)
				person["work_entry"] = work_slot.get("entry", work_slot.get("center", Vector3.ZERO))
				occupancy[work_slot.get("id", -1)] = int(occupancy.get(work_slot.get("id", -1), 0)) + 1
			_save_person(person)
		elif age >= 7 and age < 18:
			var school_slot: Dictionary = workplace_slots[_rng.randi_range(0, workplace_slots.size() - 1)]
			person["work_building_id"] = school_slot.get("id", -1)
			person["work_entry"] = school_slot.get("entry", school_slot.get("center", Vector3.ZERO))
			_save_person(person)


func _pick_workplace_slot(slots: Array, occupancy: Dictionary) -> Dictionary:
	var open_slots: Array = []
	for slot in slots:
		var slot_id = slot.get("id", -1)
		var used: int = int(occupancy.get(slot_id, 0))
		if used < int(slot.get("work_capacity", 0)):
			open_slots.append(slot)
	if open_slots.is_empty():
		return {}
	return open_slots[_rng.randi_range(0, open_slots.size() - 1)]


func _seed_social_bonds() -> void:
	for household in _households:
		var members: Array = household.get("member_ids", [])
		for i in range(members.size()):
			for j in range(i + 1, members.size()):
				_set_social_bond(int(members[i]), int(members[j]), _rng.randi_range(48, 82), "family")

	var workplace_groups: Dictionary = {}
	var home_groups: Dictionary = {}
	for person in _people:
		if not bool(person.get("alive", true)):
			continue
		var work_id: String = str(person.get("work_building_id", -1))
		if work_id != "-1":
			if not workplace_groups.has(work_id):
				workplace_groups[work_id] = []
			workplace_groups[work_id].append(int(person.get("id", -1)))
		var home_id: String = str(person.get("home_building_id", -1))
		if home_id != "-1":
			if not home_groups.has(home_id):
				home_groups[home_id] = []
			home_groups[home_id].append(int(person.get("id", -1)))

	for group in workplace_groups.values():
		_seed_group_bonds(group, "coworker")
	for group in home_groups.values():
		_seed_group_bonds(group, "neighbor")

	var alive_ids: Array = []
	for person in _people:
		if bool(person.get("alive", true)):
			alive_ids.append(int(person.get("id", -1)))
	for _i in range(maxi(1, alive_ids.size() / 18)):
		if alive_ids.size() < 2:
			break
		var a_id: int = alive_ids[_rng.randi_range(0, alive_ids.size() - 1)]
		var b_id: int = alive_ids[_rng.randi_range(0, alive_ids.size() - 1)]
		if a_id == b_id:
			continue
		_set_social_bond(a_id, b_id, _rng.randi_range(-34, -10), "rival")


func _seed_group_bonds(group: Array, base_kind: String) -> void:
	if group.size() < 2:
		return
	for i in range(group.size()):
		for j in range(i + 1, mini(group.size(), i + 4)):
			var delta: int = _rng.randi_range(-8, 30)
			if base_kind == "neighbor" or base_kind == "coworker":
				delta = _rng.randi_range(-4, 34)
				var a: Dictionary = _people_by_id.get(int(group[i]), {})
				var b: Dictionary = _people_by_id.get(int(group[j]), {})
				if _can_people_marry(a, b):
					delta += _rng.randi_range(6, 18)
			_set_social_bond(int(group[i]), int(group[j]), delta, base_kind)


func _set_social_bond(a_id: int, b_id: int, delta: int, kind: String) -> void:
	if a_id == b_id:
		return
	var a: Dictionary = _people_by_id.get(a_id, {})
	var b: Dictionary = _people_by_id.get(b_id, {})
	if a.is_empty() or b.is_empty():
		return
	var a_bonds: Dictionary = a.get("social_bonds", {})
	var b_bonds: Dictionary = b.get("social_bonds", {})
	var a_key: String = str(b_id)
	var b_key: String = str(a_id)
	var a_prev: int = int(Dictionary(a_bonds.get(a_key, {})).get("score", 0))
	var new_score: int = clampi(a_prev + delta, -100, 100)
	a_bonds[a_key] = {"score": new_score, "kind": kind, "updated_year": _current_year}
	b_bonds[b_key] = {"score": new_score, "kind": kind, "updated_year": _current_year}
	a["social_bonds"] = a_bonds
	b["social_bonds"] = b_bonds
	_save_person(a)
	_save_person(b)
	if abs(a_prev) < STRONG_BOND_THRESHOLD and abs(new_score) >= STRONG_BOND_THRESHOLD:
		_log_event("Social bond: %s and %s became strongly %s (%d)." % [a.get("full_name", "Resident"), b.get("full_name", "Resident"), kind, new_score])


func _link_spouses(a: Dictionary, b: Dictionary) -> void:
	a["spouse_id"] = b["id"]
	b["spouse_id"] = a["id"]
	_save_person(a)
	_save_person(b)
	_set_social_bond_value(int(a["id"]), int(b["id"]), 78, "married")


func _link_parent_child(parent_id: int, child_id: int) -> void:
	var parent: Dictionary = _people_by_id.get(parent_id, {})
	var child: Dictionary = _people_by_id.get(child_id, {})
	if parent.is_empty() or child.is_empty():
		return
	var child_ids: Array = parent["child_ids"]
	child_ids.append(child_id)
	parent["child_ids"] = child_ids
	if parent["gender"] == "male":
		child["father_id"] = parent_id
	else:
		child["mother_id"] = parent_id
	_save_person(parent)
	_save_person(child)


func _save_person(person: Dictionary) -> void:
	_people_by_id[person["id"]] = person
	for index in range(_people.size()):
		if int(_people[index]["id"]) == int(person["id"]):
			_people[index] = person
			return


func _save_household(household: Dictionary) -> void:
	_households_by_id[household["id"]] = household
	for index in range(_households.size()):
		if int(_households[index]["id"]) == int(household["id"]):
			_households[index] = household
			return


func _on_year_passed(force_annual: bool = false) -> void:
	var births_before: int = _birth_count
	var deaths_before: int = _death_count
	_evolve_social_bonds()
	for person in _people:
		if not bool(person.get("alive", true)):
			continue
		person["age"] = int(person["age"]) + 1
		person["occupation"] = _job_for_age(int(person["age"])) if int(person["age"]) < 18 or int(person["age"]) >= 62 else person["occupation"]
		person["bio"] = _bio_for_person(str(person["first_name"]), int(person["age"]), str(person["occupation"]))
		_save_person(person)
	_emit_birthday_spotlights(1 if _rng.randf() < 0.75 else 2)
	var marriages_this_cycle: int = _form_relationship_marriages(4)
	if marriages_this_cycle == 0 and _rng.randf() < 0.22:
		_seed_newcomer_marriages(1)
	_apply_births(1.0)
	_apply_deaths(1.0)
	if force_annual or _birth_count != births_before or _death_count != deaths_before:
		_log_event("Year %d dawned before sunrise: +%d births, %d deaths." % [_current_year, _birth_count - births_before, _death_count - deaths_before])


func _visual_hours_until_next_year_epoch() -> float:
	var current_progress: float = _visual_progress_from_clock_hour(_current_hour)
	var epoch_progress: float = _visual_progress_from_clock_hour(YEAR_EPOCH_HOUR)
	if current_progress < epoch_progress:
		return epoch_progress - current_progress
	return 24.0 - current_progress + epoch_progress


func _visual_progress_from_clock_hour(hour: float) -> float:
	var wrapped_hour: float = fposmod(hour, 24.0)
	if wrapped_hour < YEAR_EPOCH_HOUR:
		return inverse_lerp(0.0, YEAR_EPOCH_HOUR, wrapped_hour) * VISUAL_PREDAWN_LENGTH
	if wrapped_hour < 8.0:
		return VISUAL_PREDAWN_LENGTH + inverse_lerp(YEAR_EPOCH_HOUR, 8.0, wrapped_hour) * VISUAL_SUNRISE_LENGTH
	if wrapped_hour < 16.0:
		return VISUAL_PREDAWN_LENGTH + VISUAL_SUNRISE_LENGTH + inverse_lerp(8.0, 16.0, wrapped_hour) * VISUAL_DAY_LENGTH
	if wrapped_hour < 20.5:
		return VISUAL_PREDAWN_LENGTH + VISUAL_SUNRISE_LENGTH + VISUAL_DAY_LENGTH + inverse_lerp(16.0, 20.5, wrapped_hour) * VISUAL_SUNSET_LENGTH
	return VISUAL_PREDAWN_LENGTH + VISUAL_SUNRISE_LENGTH + VISUAL_DAY_LENGTH + VISUAL_SUNSET_LENGTH + inverse_lerp(20.5, 24.0, wrapped_hour) * VISUAL_LATE_NIGHT_LENGTH


func _clock_hour_from_visual_progress(progress: float) -> float:
	var wrapped_progress: float = fposmod(progress, 24.0)
	if wrapped_progress < VISUAL_PREDAWN_LENGTH:
		return lerpf(0.0, YEAR_EPOCH_HOUR, inverse_lerp(0.0, VISUAL_PREDAWN_LENGTH, wrapped_progress))
	wrapped_progress -= VISUAL_PREDAWN_LENGTH
	if wrapped_progress < VISUAL_SUNRISE_LENGTH:
		return lerpf(YEAR_EPOCH_HOUR, 8.0, inverse_lerp(0.0, VISUAL_SUNRISE_LENGTH, wrapped_progress))
	wrapped_progress -= VISUAL_SUNRISE_LENGTH
	if wrapped_progress < VISUAL_DAY_LENGTH:
		return lerpf(8.0, 16.0, inverse_lerp(0.0, VISUAL_DAY_LENGTH, wrapped_progress))
	wrapped_progress -= VISUAL_DAY_LENGTH
	if wrapped_progress < VISUAL_SUNSET_LENGTH:
		return lerpf(16.0, 20.5, inverse_lerp(0.0, VISUAL_SUNSET_LENGTH, wrapped_progress))
	wrapped_progress -= VISUAL_SUNSET_LENGTH
	return lerpf(20.5, 24.0, inverse_lerp(0.0, VISUAL_LATE_NIGHT_LENGTH, wrapped_progress))


func _apply_births(cycle_fraction: float = 1.0) -> void:
	var cycle_chance: float = _scaled_cycle_probability(0.16, cycle_fraction)
	for household in _households:
		var couples: Array = _get_household_spouse_pairs(household)
		if couples.is_empty():
			continue
		if _rng.randf() > cycle_chance:
			continue
		var parents: Array = couples[_rng.randi_range(0, couples.size() - 1)]
		var adult_a: Dictionary = parents[0]
		var adult_b: Dictionary = parents[1]
		var surname: String = str(adult_a.get("last_name", _pick(LAST_NAMES)))
		var gender: String = "female" if _rng.randf() < 0.5 else "male"
		var first_name: String = _pick(FEMALE_FIRST_NAMES) if gender == "female" else _pick(MALE_FIRST_NAMES)
		var baby := _create_person(str(household.get("lineage_id", "L000")), first_name, surname, gender, 0, "toddler", int(adult_a.get("generation", 1)) + 1)
		_link_parent_child(int(adult_a["id"]), int(baby["id"]))
		_link_parent_child(int(adult_b["id"]), int(baby["id"]))
		household["member_ids"].append(baby["id"])
		_save_household(household)
		var baby_record: Dictionary = _people_by_id.get(int(baby["id"]), {})
		baby_record["household_id"] = household["id"]
		baby_record["home_block"] = household.get("block", {})
		baby_record["home_building_id"] = household.get("building_id", -1)
		if str(household.get("building_id", -1)) != "-1" and _building_by_id.has(household.get("building_id", -1)):
			var building: Dictionary = _building_by_id[household.get("building_id", -1)]
			baby_record["home_entry"] = building.get("entry", building.get("center", Vector3.ZERO))
		_save_person(baby_record)
		_set_social_bond(int(adult_a["id"]), int(baby["id"]), 72, "family")
		_set_social_bond(int(adult_b["id"]), int(baby["id"]), 72, "family")
		_set_social_bond(int(adult_a["id"]), int(adult_b["id"]), 5, "married")
		_birth_count += 1
		_log_event(
			"Birth: %s joined household %d." % [baby_record.get("full_name", "New baby"), household.get("id", -1)],
			"birth",
			[int(baby_record.get("id", -1)), int(adult_a.get("id", -1)), int(adult_b.get("id", -1))],
			int(baby_record.get("id", -1)),
			{
				"household_id": int(household.get("id", -1)),
				"parents": [adult_a.get("full_name", "Parent"), adult_b.get("full_name", "Parent")]
			}
		)


func _apply_deaths(cycle_fraction: float = 1.0) -> void:
	for person in _people:
		if not bool(person.get("alive", true)):
			continue
		var age: int = int(person.get("age", 0))
		var annual_death_roll: float = 0.0
		if age >= 95:
			annual_death_roll = 0.45
		elif age >= 88:
			annual_death_roll = 0.22
		elif age >= 80:
			annual_death_roll = 0.10
		elif age >= 72:
			annual_death_roll = 0.04
		var death_roll: float = _scaled_cycle_probability(annual_death_roll, cycle_fraction)
		if death_roll <= 0.0 or _rng.randf() > death_roll:
			continue
		person["alive"] = false
		person["death_year"] = _current_year
		_save_person(person)
		_death_count += 1
		_log_event(
			"Death: %s at age %d." % [person.get("full_name", "Resident"), age],
			"death",
			[int(person.get("id", -1))],
			int(person.get("id", -1)),
			{"age": age}
		)


func _evolve_social_bonds() -> void:
	var alive_ids: Array = []
	for person in _people:
		if bool(person.get("alive", true)):
			alive_ids.append(int(person.get("id", -1)))
	for _step in range(mini(12, alive_ids.size())):
		var person_id: int = alive_ids[_rng.randi_range(0, alive_ids.size() - 1)]
		var person: Dictionary = _people_by_id.get(person_id, {})
		if person.is_empty():
			continue
		var person_household: String = str(person.get("household_id", -1))
		var person_work: String = str(person.get("work_building_id", -1))
		var person_home: String = str(person.get("home_building_id", -1))
		var candidate_ids: Array = []
		for other in _people:
			if not bool(other.get("alive", true)):
				continue
			if int(other.get("id", -1)) == person_id:
				continue
			if str(other.get("household_id", -1)) == person_household or str(other.get("work_building_id", -1)) == person_work or str(other.get("home_building_id", -1)) == person_home:
				candidate_ids.append(int(other.get("id", -1)))
		if candidate_ids.is_empty() and alive_ids.size() > 1:
			candidate_ids = alive_ids.duplicate()
			candidate_ids.erase(person_id)
		if candidate_ids.is_empty():
			continue
		var other_id: int = candidate_ids[_rng.randi_range(0, candidate_ids.size() - 1)]
		var other_person: Dictionary = _people_by_id.get(other_id, {})
		var kind: String = "neighbor"
		var delta: int = _rng.randi_range(-10, 12)
		if str(other_person.get("household_id", -1)) == person_household:
			kind = "family"
			delta = _rng.randi_range(4, 10)
		elif person_work != "-1" and str(other_person.get("work_building_id", -1)) == person_work:
			kind = "coworker"
			delta = _rng.randi_range(-8, 14)
		elif person_home != "-1" and str(other_person.get("home_building_id", -1)) == person_home:
			kind = "neighbor"
			delta = _rng.randi_range(-6, 12)
		else:
			kind = "acquaintance"
		_set_social_bond(person_id, other_id, delta, kind)
	if _rng.randf() < 0.72:
		_form_relationship_marriages(3)


func _form_relationship_marriages(max_pairs: int = 3) -> int:
	var singles: Array = []
	for person in _people:
		if _is_marriage_candidate(person):
			singles.append(int(person.get("id", -1)))
	if singles.size() < 2:
		return 0
	_shuffle_array(singles)
	var marriages_formed: int = 0
	for person_id in singles:
		if marriages_formed >= max_pairs:
			break
		var person: Dictionary = _people_by_id.get(person_id, {})
		if not _is_marriage_candidate(person):
			continue
		var best_match: Dictionary = {}
		for other_id in singles:
			if int(other_id) == person_id:
				continue
			var other: Dictionary = _people_by_id.get(int(other_id), {})
			if not _is_marriage_candidate(other):
				continue
			var score: int = _marriage_match_score(person, other)
			if score < MARRIAGE_BOND_THRESHOLD:
				continue
			if best_match.is_empty() or score > int(best_match.get("score", -999)):
				best_match = {"id": int(other_id), "score": score}
		if best_match.is_empty():
			for other_id in singles:
				if int(other_id) == person_id:
					continue
				var fallback_other: Dictionary = _people_by_id.get(int(other_id), {})
				if not _is_marriage_candidate(fallback_other):
					continue
				var fallback_score: int = _marriage_match_score(person, fallback_other)
				if fallback_score < 24:
					continue
				if best_match.is_empty() or fallback_score > int(best_match.get("score", -999)):
					best_match = {"id": int(other_id), "score": fallback_score}
		if best_match.is_empty():
			continue
		var chosen: Dictionary = _people_by_id.get(int(best_match.get("id", -1)), {})
		if not _is_marriage_candidate(chosen):
			continue
		if _rng.randf() > clampf((float(best_match.get("score", 0)) - 18.0) / 42.0, 0.45, 0.98):
			continue
		_marry_pair(person, chosen)
		marriages_formed += 1
	return marriages_formed


func _seed_newcomer_marriages(max_pairs: int = 1) -> int:
	var marriages_formed: int = 0
	for person in _people:
		if marriages_formed >= max_pairs:
			break
		if not _is_marriage_candidate(person):
			continue
		var partner_gender: String = "male" if str(person.get("gender", "male")) == "female" else "female"
		var partner_first: String = _pick(MALE_FIRST_NAMES) if partner_gender == "male" else _pick(FEMALE_FIRST_NAMES)
		var partner_age: int = clampi(int(person.get("age", 28)) + _rng.randi_range(-5, 4), 22, 56)
		var partner_last: String = _pick(LAST_NAMES)
		if partner_last == str(person.get("last_name", "")) and _rng.randf() < 0.7:
			partner_last = _pick(LAST_NAMES)
		var newcomer := _create_person(str(person.get("lineage_id", "L000")), partner_first, partner_last, partner_gender, partner_age, _job_for_age(partner_age), int(person.get("generation", 1)))
		_marry_pair(person, newcomer)
		marriages_formed += 1
	return marriages_formed


func _marriage_match_score(a: Dictionary, b: Dictionary) -> int:
	if not _can_people_marry(a, b):
		return -999
	var social_score: int = _get_social_bond_score(int(a.get("id", -1)), int(b.get("id", -1)))
	var score: int = social_score
	var age_gap: int = abs(int(a.get("age", 0)) - int(b.get("age", 0)))
	score += maxi(0, 16 - age_gap * 2)
	var a_work: String = str(a.get("work_building_id", -1))
	var b_work: String = str(b.get("work_building_id", -1))
	var a_home: String = str(a.get("home_building_id", -1))
	var b_home: String = str(b.get("home_building_id", -1))
	if a_work != "-1" and a_work == b_work:
		score += 12
	if a_home != "-1" and a_home == b_home:
		score += 8
	if str(a.get("last_name", "")) == str(b.get("last_name", "")):
		score -= 10
	return score


func _is_marriage_candidate(person: Dictionary) -> bool:
	if person.is_empty() or not bool(person.get("alive", true)):
		return false
	if int(person.get("spouse_id", -1)) != -1:
		return false
	var age: int = int(person.get("age", 0))
	return age >= 22 and age <= 52


func _can_people_marry(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if int(a.get("id", -1)) == int(b.get("id", -1)):
		return false
	if str(a.get("gender", "")) == str(b.get("gender", "")):
		return false
	var a_household: String = str(a.get("household_id", -1))
	var b_household: String = str(b.get("household_id", -1))
	if a_household != "-1" and a_household == b_household:
		return false
	if _are_close_relatives(a, b):
		return false
	return true


func _are_close_relatives(a: Dictionary, b: Dictionary) -> bool:
	var a_id: int = int(a.get("id", -1))
	var b_id: int = int(b.get("id", -1))
	if a_id == int(b.get("father_id", -1)) or a_id == int(b.get("mother_id", -1)):
		return true
	if b_id == int(a.get("father_id", -1)) or b_id == int(a.get("mother_id", -1)):
		return true
	if int(a.get("father_id", -1)) != -1 and int(a.get("father_id", -1)) == int(b.get("father_id", -2)):
		return true
	if int(a.get("mother_id", -1)) != -1 and int(a.get("mother_id", -1)) == int(b.get("mother_id", -2)):
		return true
	if Array(a.get("child_ids", [])).has(b_id) or Array(b.get("child_ids", [])).has(a_id):
		return true
	return false


func _get_social_bond_score(a_id: int, b_id: int) -> int:
	var a: Dictionary = _people_by_id.get(a_id, {})
	if a.is_empty():
		return 0
	var bonds: Dictionary = a.get("social_bonds", {})
	return int(Dictionary(bonds.get(str(b_id), {})).get("score", 0))


func _set_social_bond_value(a_id: int, b_id: int, score: int, kind: String) -> void:
	if a_id == b_id:
		return
	var a: Dictionary = _people_by_id.get(a_id, {})
	var b: Dictionary = _people_by_id.get(b_id, {})
	if a.is_empty() or b.is_empty():
		return
	var clamped_score: int = clampi(score, -100, 100)
	var a_bonds: Dictionary = a.get("social_bonds", {})
	var b_bonds: Dictionary = b.get("social_bonds", {})
	a_bonds[str(b_id)] = {"score": clamped_score, "kind": kind, "updated_year": _current_year}
	b_bonds[str(a_id)] = {"score": clamped_score, "kind": kind, "updated_year": _current_year}
	a["social_bonds"] = a_bonds
	b["social_bonds"] = b_bonds
	_save_person(a)
	_save_person(b)


func _marry_pair(a: Dictionary, b: Dictionary) -> void:
	_link_spouses(a, b)
	_move_couple_to_new_household(int(a.get("id", -1)), int(b.get("id", -1)))
	_log_event(
		"Marriage: %s and %s paired up through a strong relationship." % [a.get("full_name", "Resident"), b.get("full_name", "Resident")],
		"marriage",
		[int(a.get("id", -1)), int(b.get("id", -1))],
		int(a.get("id", -1)),
		{"partner_ids": [int(a.get("id", -1)), int(b.get("id", -1))]}
	)


func _move_couple_to_new_household(a_id: int, b_id: int) -> void:
	var a: Dictionary = _people_by_id.get(a_id, {})
	var b: Dictionary = _people_by_id.get(b_id, {})
	if a.is_empty() or b.is_empty():
		return
	_remove_member_from_household(a_id, int(a.get("household_id", -1)))
	_remove_member_from_household(b_id, int(b.get("household_id", -1)))
	var lineage_id: String = str(a.get("lineage_id", b.get("lineage_id", "L000")))
	var new_household: Dictionary = _register_household(lineage_id, [a_id, b_id], "married_household")
	a = _people_by_id.get(a_id, a)
	b = _people_by_id.get(b_id, b)
	a["household_id"] = new_household.get("id", -1)
	b["household_id"] = new_household.get("id", -1)
	_save_person(a)
	_save_person(b)
	_prune_empty_households()


func _remove_member_from_household(person_id: int, household_id: int) -> void:
	if household_id == -1:
		return
	var household: Dictionary = _households_by_id.get(household_id, {})
	if household.is_empty():
		return
	var members: Array = household.get("member_ids", [])
	members.erase(person_id)
	household["member_ids"] = members
	_save_household(household)


func _prune_empty_households() -> void:
	var kept: Array = []
	var rebuilt_index: Dictionary = {}
	for household in _households:
		if Array(household.get("member_ids", [])).is_empty():
			continue
		kept.append(household)
		rebuilt_index[household.get("id", -1)] = household
	_households = kept
	_households_by_id = rebuilt_index


func _get_household_spouse_pairs(household: Dictionary) -> Array:
	var pairs: Array = []
	var seen: Dictionary = {}
	for member_id in household.get("member_ids", []):
		var resident: Dictionary = _people_by_id.get(member_id, {})
		if resident.is_empty() or not bool(resident.get("alive", true)):
			continue
		var spouse_id: int = int(resident.get("spouse_id", -1))
		if spouse_id == -1 or seen.has(member_id) or seen.has(spouse_id):
			continue
		var spouse: Dictionary = _people_by_id.get(spouse_id, {})
		if spouse.is_empty() or not bool(spouse.get("alive", true)):
			continue
		if spouse.get("household_id", -1) != household.get("id", -2):
			continue
		var age_a: int = int(resident.get("age", 0))
		var age_b: int = int(spouse.get("age", 0))
		if age_a < 24 or age_a > 42 or age_b < 24 or age_b > 42:
			continue
		pairs.append([resident, spouse])
		seen[member_id] = true
		seen[spouse_id] = true
	return pairs


func _random_walk_anchor_near(origin: Vector3, radius: float) -> Vector3:
	if _city != null and _city.has_method("get_random_walk_point"):
		for _attempt in range(10):
			var candidate: Vector3 = _city.call("get_random_walk_point", 0.55)
			if Vector2(candidate.x - origin.x, candidate.z - origin.z).length() <= radius:
				return candidate
		return _city.call("get_random_walk_point", 0.55)
	return origin


func _pick_promenade_target_near(origin: Vector3, seed_value_local: int, radius: float) -> Vector3:
	if _city == null or not _city.has_method("get_walk_areas_snapshot"):
		return _random_walk_anchor_near(origin, radius)
	var candidates: Array = []
	for area in _city.call("get_walk_areas_snapshot"):
		var center := Vector3(
			(float(area["x"].x) + float(area["x"].y)) * 0.5,
			float(area.get("y", 0.0)),
			(float(area["z"].x) + float(area["z"].y)) * 0.5
		)
		if Vector2(center.x - origin.x, center.z - origin.z).length() <= radius:
			candidates.append(center)
	if candidates.is_empty():
		return _random_walk_anchor_near(origin, radius)
	return Vector3(candidates[_positive_modulo(seed_value_local * 37 + _current_day_of_year * 13, candidates.size())])


func _pick_destination_for_person(person: Dictionary, preferred_kinds: Array) -> Vector3:
	var home_entry := Vector3(person.get("home_entry", Vector3.ZERO))
	var candidates: Array = []
	for slot in _building_slots:
		if not preferred_kinds.has(str(slot.get("kind", ""))):
			continue
		candidates.append(slot)
	if candidates.is_empty():
		return _random_walk_anchor_near(home_entry, 16.0)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_venue: String = str(a.get("venue_type", ""))
		var b_venue: String = str(b.get("venue_type", ""))
		if (a_venue != "") != (b_venue != ""):
			return a_venue != ""
		var a_point: Vector3 = _representative_destination_point(a, home_entry)
		var b_point: Vector3 = _representative_destination_point(b, home_entry)
		return Vector2(a_point.x - home_entry.x, a_point.z - home_entry.z).length_squared() < Vector2(b_point.x - home_entry.x, b_point.z - home_entry.z).length_squared()
	)
	var choice_pool: Array = candidates.slice(0, mini(8, candidates.size()))
	var choice_index: int = _positive_modulo(int(person.get("id", -1)) * 19 + _current_day_of_year * 7 + _current_year, choice_pool.size())
	var choice: Dictionary = choice_pool[choice_index]
	return _destination_point_for_slot(choice, int(person.get("id", -1)), home_entry)


func _representative_destination_point(slot: Dictionary, fallback: Vector3) -> Vector3:
	var entry_points: Array = slot.get("entry_points", [])
	if not entry_points.is_empty():
		return Vector3(entry_points[0])
	return Vector3(slot.get("entry", slot.get("center", fallback)))


func _destination_point_for_slot(slot: Dictionary, person_id: int, fallback: Vector3) -> Vector3:
	var gathering_points: Array = slot.get("gathering_points", [])
	if not gathering_points.is_empty():
		var gather_index: int = _positive_modulo(person_id * 11 + _current_day_of_year * 5 + _current_year, gathering_points.size())
		return Vector3(gathering_points[gather_index])
	var entry_points: Array = slot.get("entry_points", [])
	if not entry_points.is_empty():
		var entry_index: int = _positive_modulo(person_id * 17 + _current_day_of_year * 3 + _current_year, entry_points.size())
		return Vector3(entry_points[entry_index])
	return Vector3(slot.get("entry", slot.get("center", fallback)))


func _pick(items: Array) -> Variant:
	return items[_rng.randi_range(0, items.size() - 1)]


func _job_for_age(age: int) -> String:
	if age < 6:
		return "toddler"
	if age < 18:
		return _pick(CHILD_ROLES)
	if age >= 62:
		return _pick(SENIOR_JOBS)
	return _pick(ADULT_JOBS)


func _bio_for_person(first_name: String, age: int, occupation: String) -> String:
	if age < 18:
		return "%s is %d and known around the block as a %s." % [first_name, age, occupation]
	return "%s is %d and works as a %s." % [first_name, age, occupation]


func _scaled_cycle_probability(base_probability: float, cycle_fraction: float) -> float:
	var clamped_base: float = clampf(base_probability, 0.0, 1.0)
	var clamped_fraction: float = maxf(0.0, cycle_fraction)
	if clamped_base <= 0.0 or clamped_fraction <= 0.0:
		return 0.0
	if clamped_base >= 1.0:
		return 1.0
	return 1.0 - pow(1.0 - clamped_base, clamped_fraction)


func _sync_speed_index_to_current_scale() -> void:
	var closest_index: int = 0
	var closest_distance: float = INF
	for index in range(SPEED_PRESETS.size()):
		var distance: float = absf(float(SPEED_PRESETS[index]) - hours_per_second)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	_speed_index = closest_index


func _shuffle_array(items: Array) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap_index: int = _rng.randi_range(0, index)
		var tmp = items[index]
		items[index] = items[swap_index]
		items[swap_index] = tmp


func _positive_modulo(value: int, count: int) -> int:
	if count <= 0:
		return 0
	var mod: int = value % count
	return mod + count if mod < 0 else mod


func _hour_label(value: float) -> String:
	var hour: int = int(floor(value))
	var minute: int = int(round((value - float(hour)) * 60.0))
	if minute >= 60:
		minute = 0
		hour = (hour + 1) % 24
	return "%02d:%02d" % [hour, minute]


func _emit_birthday_spotlights(count: int = 1) -> void:
	var candidates: Array = []
	for person in _people:
		if not bool(person.get("alive", true)):
			continue
		if int(person.get("age", 0)) < 5:
			continue
		candidates.append(int(person.get("id", -1)))
	if candidates.is_empty():
		return
	_shuffle_array(candidates)
	var shown: int = 0
	for person_id in candidates:
		if shown >= maxi(1, count):
			break
		var person: Dictionary = _people_by_id.get(person_id, {})
		if person.is_empty():
			continue
		shown += 1
		_log_event(
			"Birthday: %s is celebrating %d." % [person.get("full_name", "Resident"), int(person.get("age", 0))],
			"birthday",
			[int(person.get("id", -1))],
			int(person.get("id", -1)),
			{"household_id": int(person.get("household_id", -1)), "age": int(person.get("age", 0))}
		)


func _log_event(text: String, event_type: String = "system", person_ids: Array = [], primary_person_id: int = -1, details: Dictionary = {}) -> void:
	_recent_events.append(text)
	if _recent_events.size() > 24:
		_recent_events = _recent_events.slice(_recent_events.size() - 24, _recent_events.size())
	var event_record: Dictionary = {
		"type": event_type,
		"text": text,
		"year": _current_year,
		"day_of_year": _current_day_of_year,
		"hour": snappedf(_current_hour, 0.01),
		"person_ids": person_ids.duplicate(),
		"primary_person_id": primary_person_id
	}
	for key in details.keys():
		event_record[key] = details[key]
	_recent_event_records.append(event_record)
	if _recent_event_records.size() > 24:
		_recent_event_records = _recent_event_records.slice(_recent_event_records.size() - 24, _recent_event_records.size())
	if event_type == "birth" or event_type == "death" or event_type == "marriage" or event_type == "birthday":
		emit_signal("life_event", event_record.duplicate(true))
