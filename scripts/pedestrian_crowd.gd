extends Node3D
class_name PedestrianCrowd

const PERSON_SCENE_PATHS := [
	"res://assets/characters/pedestrian_man.glb",
	"res://assets/characters/pedestrian_woman.glb",
	"res://assets/characters/pedestrian_child.glb"
]
const DOG_SCENE_PATH := "res://assets/characters/dog_companion.glb"
const DOG_TYPE := "dog"
const PERSON_TYPES := ["man", "woman", "child"]
const PERSON_COLORS := {
	"man": Color(0.28, 0.45, 0.79),
	"woman": Color(0.82, 0.39, 0.46),
	"child": Color(0.38, 0.72, 0.42),
	"dog": Color(0.74, 0.56, 0.28)
}

@export var city_path: NodePath
@export var population_path: NodePath
@export var camera_path: NodePath
@export var min_pedestrians: int = 8
@export var max_pedestrians: int = 18
@export_range(0.02, 0.40, 0.01) var density_per_block: float = 0.14
@export var min_dogs: int = 3
@export var max_dogs: int = 6
@export_range(0.00, 0.20, 0.01) var dog_density_per_block: float = 0.045
@export var walk_speed_min: float = 0.82
@export var walk_speed_max: float = 1.34
@export var dog_walk_speed_min: float = 1.18
@export var dog_walk_speed_max: float = 1.82
@export var target_distance_min: float = 5.0
@export var dog_target_distance_min: float = 3.2
@export var bob_height: float = 0.05
@export var turn_lerp_speed: float = 5.0
@export var model_yaw_offset_degrees: float = 180.0
@export var dog_model_scale: float = 0.88
@export var show_identity_labels: bool = false
@export var max_active_event_effects: int = 20
@export var max_detailed_pedestrians: int = 18
@export_range(1, 4, 1) var crowd_update_slices: int = 2
@export var player_label_distance: float = 16.0
@export var overlook_label_distance: float = 32.0
@export var house_event_roadside_offset: float = 2.2
@export var world_event_ground_lift: float = 0.16
@export var world_event_persistence_days: float = 90.0
@export_range(0.0, 1.0, 0.05) var social_group_share: float = 0.78
@export_range(0.55, 1.8, 0.05) var social_group_spacing: float = 0.92
@export_range(2, 5, 1) var max_social_group_members: int = 4
@export_range(0.0, 1.0, 0.05) var dog_group_follow_share: float = 0.72

var _city: Node
var _population: Node
var _camera: Camera3D
var _population_connected: bool = false
var _camera_resolve_attempted: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pedestrians: Array[Dictionary] = []
var _tracked_person_ids: Array[int] = []
var _active_event_effects: Array[Dictionary] = []
var _frame_counter: int = 0
var _optional_scene_cache: Dictionary = {}
var _missing_optional_assets: Dictionary = {}
var _social_groups: Dictionary = {}
var _person_group_assignments: Dictionary = {}
var _group_leader_indices_by_person: Dictionary = {}
var _group_leader_indices_by_group: Dictionary = {}
var _dog_group_assignments: Array = []


func _ready() -> void:
	_resolve_city()
	_resolve_camera()
	call_deferred("populate_now")


func clear_pedestrians() -> void:
	_pedestrians.clear()
	_active_event_effects.clear()
	_social_groups.clear()
	_person_group_assignments.clear()
	_group_leader_indices_by_person.clear()
	_group_leader_indices_by_group.clear()
	_dog_group_assignments.clear()
	for child in get_children():
		child.queue_free()


func populate_now() -> void:
	_resolve_city()
	_resolve_population()
	_resolve_camera()
	_ensure_population_connection()
	clear_pedestrians()
	if _city == null or not _city.has_method("get_random_walk_point"):
		return
	var city_seed: int = int(_city.get("seed_value")) if _city.get("seed_value") != null else 1
	_rng.seed = int(abs(city_seed * 19349663 + 907633515))
	var target_count: int = _target_count()
	var residents: Array = _compose_resident_identities(target_count)
	_rebuild_social_group_state(residents)
	for index in range(target_count):
		var identity: Dictionary = residents[index] if index < residents.size() else {}
		var group_info: Dictionary = _group_assignment_for_identity(identity)
		_spawn_pedestrian(index, identity, group_info)
	var dog_count: int = _target_dog_count()
	_dog_group_assignments = _plan_dog_social_assignments(dog_count)
	for dog_index in range(dog_count):
		var dog_group: Dictionary = _dog_group_assignments[dog_index] if dog_index < _dog_group_assignments.size() else {}
		_spawn_dog(target_count + dog_index, dog_group)
	_rebuild_group_leader_indices()


func get_pedestrian_count() -> int:
	return _pedestrians.size()


func get_active_event_effect_count() -> int:
	return _active_event_effects.size()


func get_pedestrian_debug_snapshot() -> Array:
	var snapshot: Array = []
	for ped in _pedestrians:
		if not is_instance_valid(ped["root"]):
			continue
		var identity: Dictionary = ped.get("identity", {})
		var actor_type: String = str(ped.get("type", "person"))
		var label_text: String = "Dog" if actor_type == DOG_TYPE else String(identity.get("full_name", ""))
		snapshot.append({
			"type": actor_type,
			"position": ped["root"].position,
			"target": ped["target"],
			"mode": str(ped.get("mode", "wander")),
			"group_kind": str(ped.get("group_kind", "solo")),
			"group_id": str(ped.get("group_id", "")),
			"speed": ped["speed"],
			"color": PERSON_COLORS.get(actor_type, Color.WHITE),
			"identity": identity,
			"label": label_text
		})
	return snapshot


func pick_person_from_screen(camera: Camera3D, screen_position: Vector2, max_screen_distance: float = 34.0) -> Dictionary:
	if camera == null:
		return {}
	var best_hit: Dictionary = {}
	var best_distance: float = max_screen_distance
	for ped in _pedestrians:
		var identity: Dictionary = ped.get("identity", {})
		var root: Node3D = ped.get("root") as Node3D
		if identity.is_empty() or root == null or not is_instance_valid(root):
			continue
		var world_anchor := root.global_position + Vector3(0.0, 1.2, 0.0)
		if camera.is_position_behind(world_anchor):
			continue
		var projected: Vector2 = camera.unproject_position(world_anchor)
		var distance: float = projected.distance_to(screen_position)
		if distance > best_distance:
			continue
		best_distance = distance
		best_hit = {
			"person_id": int(identity.get("id", -1)),
			"identity": identity,
			"screen_distance": distance,
			"world_position": root.global_position
		}
	return best_hit


func _process(delta: float) -> void:
	if _city == null or _pedestrians.is_empty():
		return
	var slice_count: int = maxi(1, crowd_update_slices)
	var frame_phase: int = _frame_counter % slice_count
	_frame_counter += 1
	for index in range(_pedestrians.size()):
		var ped: Dictionary = _pedestrians[index]
		var root: Node3D = ped["root"]
		var visual: Node3D = ped["visual"]
		if not is_instance_valid(root) or not is_instance_valid(visual):
			continue
		var identity: Dictionary = ped.get("identity", {})
		var tracked: bool = not identity.is_empty() and _tracked_person_ids.has(int(identity.get("id", -1)))
		if not tracked and slice_count > 1 and index % slice_count != frame_phase:
			ped = _animate_actor_visual(ped, delta, false)
			_pedestrians[index] = ped
			continue
		var pause_time: float = float(ped["pause_time"])
		var social_target: Variant = _group_follow_target(ped, root.position)
		if social_target != null:
			ped["target"] = social_target
			ped["pause_time"] = 0.0
			ped["speed"] = _group_speed_for_actor(ped)
			pause_time = 0.0
		if pause_time > 0.0:
			pause_time = maxf(0.0, pause_time - delta)
			ped["pause_time"] = pause_time
			ped = _animate_actor_visual(ped, delta, false)
			_pedestrians[index] = ped
			continue

		var position: Vector3 = root.position
		var target: Vector3 = ped["target"]
		var toward := Vector3(target.x - position.x, 0.0, target.z - position.z)
		var distance: float = toward.length()
		if distance < 0.45 or float(ped["stuck_time"]) > 1.0:
			var group_target: Variant = _group_follow_target(ped, position)
			if group_target != null:
				ped["target"] = group_target
				ped["speed"] = _group_speed_for_actor(ped)
				ped["stuck_time"] = 0.0
				ped["pause_time"] = 0.0
				_pedestrians[index] = ped
				continue
			var activity: Dictionary = _activity_for_identity(identity)
			var mode: String = str(activity.get("mode", ped.get("mode", "wander")))
			ped["mode"] = mode
			ped["target"] = _pick_target_for_pedestrian(ped, position)
			ped["speed"] = _pedestrian_speed_for_identity(str(ped.get("type", "person")), identity, mode)
			ped["stuck_time"] = 0.0
			ped["pause_time"] = _random_pause_for_actor(str(ped.get("type", "person")), mode)
			_pedestrians[index] = ped
			continue

		var direction := toward / maxf(distance, 0.001)
		var step_speed: float = float(ped["speed"])
		var desired := position + direction * (step_speed * delta)
		var moved := desired
		if _city.has_method("try_move_on_walk_ground"):
			moved = _city.call("try_move_on_walk_ground", position, desired)
		root.position = moved
		var moved_dist: float = Vector2(moved.x - position.x, moved.z - position.z).length()
		ped["stuck_time"] = float(ped["stuck_time"]) + delta if moved_dist < 0.003 else 0.0
		var heading: float = atan2(direction.x, direction.z) + deg_to_rad(model_yaw_offset_degrees)
		root.rotation.y = lerp_angle(root.rotation.y, heading, minf(1.0, delta * turn_lerp_speed))
		ped = _animate_actor_visual(ped, delta, true)
		_pedestrians[index] = ped
	_update_event_effects(delta)
	_update_label_visibility()


func _resolve_city() -> void:
	if city_path != NodePath():
		_city = get_node_or_null(city_path)
	elif get_parent() != null:
		_city = get_parent().get_node_or_null("City")


func _resolve_population() -> void:
	if population_path != NodePath():
		_population = get_node_or_null(population_path)
	elif get_parent() != null:
		_population = get_parent().get_node_or_null("Population")


func _resolve_camera() -> void:
	if _camera != null or _camera_resolve_attempted:
		return
	_camera_resolve_attempted = true
	if camera_path != NodePath():
		_camera = get_node_or_null(camera_path) as Camera3D
	elif get_parent() != null:
		_camera = get_parent().get_node_or_null("Camera3D") as Camera3D
	var viewport := get_viewport()
	if _camera == null and viewport != null:
		_camera = get_viewport().get_camera_3d()


func _ensure_population_connection() -> void:
	if _population_connected or _population == null:
		return
	if _population.has_signal("population_regenerated"):
		_population.connect("population_regenerated", Callable(self, "_on_population_regenerated"))
	if _population.has_signal("life_event"):
		_population.connect("life_event", Callable(self, "_on_life_event"))
		_population_connected = true


func refresh_identities_from_population() -> void:
	_resolve_population()
	if _population == null or _pedestrians.is_empty():
		return
	var resident_slots: Array[int] = []
	for index in range(_pedestrians.size()):
		if str(_pedestrians[index].get("type", "person")) != DOG_TYPE:
			resident_slots.append(index)
	var residents: Array = _compose_resident_identities(resident_slots.size())
	_rebuild_social_group_state(residents)
	_dog_group_assignments = _plan_dog_social_assignments(_dog_count())
	var resident_cursor: int = 0
	var dog_cursor: int = 0
	for index in range(_pedestrians.size()):
		var ped: Dictionary = _pedestrians[index]
		if not is_instance_valid(ped["root"]):
			continue
		if str(ped.get("type", "person")) == DOG_TYPE:
			ped = _refresh_dog_social_state(ped, dog_cursor)
			dog_cursor += 1
			_pedestrians[index] = ped
			continue
		var identity: Dictionary = residents[resident_cursor] if resident_cursor < residents.size() else {}
		resident_cursor += 1
		ped = _apply_identity_to_pedestrian(ped, index, identity)
		_pedestrians[index] = ped
	_rebuild_group_leader_indices()


func set_tracked_people(person_ids: Array) -> void:
	var cleaned: Array[int] = []
	for raw_id in person_ids:
		var person_id: int = int(raw_id)
		if person_id <= 0 or cleaned.has(person_id):
			continue
		cleaned.append(person_id)
	if cleaned == _tracked_person_ids:
		return
	_tracked_person_ids = cleaned
	refresh_identities_from_population()


func play_life_event_effect(event: Dictionary) -> void:
	if event.is_empty():
		return
	var event_type: String = str(event.get("type", "system"))
	if event_type != "birth" and event_type != "marriage" and event_type != "death" and event_type != "birthday":
		return
	_spawn_world_event_effect(event)
	var person_ids: Array = event.get("person_ids", [])
	for ped in _pedestrians:
		var root: Node3D = ped.get("root") as Node3D
		var identity: Dictionary = ped.get("identity", {})
		if root == null or identity.is_empty():
			continue
		var person_id: int = int(identity.get("id", -1))
		if person_id == -1 or not person_ids.has(person_id):
			continue
		_spawn_event_effect(root, event)


func _on_population_regenerated(_summary: Dictionary) -> void:
	refresh_identities_from_population()


func _on_life_event(event: Dictionary) -> void:
	play_life_event_effect(event)


func _target_count() -> int:
	var grid: Vector2i = _city.get("grid_size") if _city.get("grid_size") != null else Vector2i(8, 8)
	var ideal: int = int(round(float(grid.x * grid.y) * density_per_block))
	var jitter: int = _rng.randi_range(-2, 3)
	return clampi(ideal + jitter, min_pedestrians, max_pedestrians)


func _target_dog_count() -> int:
	if max_dogs <= 0:
		return 0
	var grid: Vector2i = _city.get("grid_size") if _city != null and _city.get("grid_size") != null else Vector2i(8, 8)
	var ideal: int = int(round(float(grid.x * grid.y) * dog_density_per_block))
	var jitter: int = _rng.randi_range(-1, 1)
	return clampi(ideal + jitter, min_dogs, max_dogs)


func _dog_count() -> int:
	var count: int = 0
	for ped in _pedestrians:
		if str(ped.get("type", "person")) == DOG_TYPE:
			count += 1
	return count


func _compose_resident_identities(target_count: int) -> Array:
	var residents: Array = []
	if _population == null or target_count <= 0:
		return residents
	var seen: Dictionary = {}
	if _population.has_method("get_person"):
		for tracked_id in _tracked_person_ids:
			var tracked: Dictionary = _population.call("get_person", tracked_id)
			if tracked.is_empty() or not bool(tracked.get("alive", true)):
				continue
			var person_id: int = int(tracked.get("id", -1))
			if person_id <= 0 or seen.has(person_id):
				continue
			seen[person_id] = true
			residents.append(tracked)
	if _population.has_method("get_random_residents"):
		var filler_count: int = maxi(target_count * 2, target_count + _tracked_person_ids.size())
		for candidate in _population.call("get_random_residents", filler_count):
			if residents.size() >= target_count:
				break
			var person_id: int = int(candidate.get("id", -1))
			if person_id <= 0 or seen.has(person_id):
				continue
			seen[person_id] = true
			residents.append(candidate)
			_append_social_companions(candidate, residents, seen, target_count)
	return residents.slice(0, mini(target_count, residents.size()))


func _append_social_companions(identity: Dictionary, residents: Array, seen: Dictionary, target_count: int) -> void:
	if _population == null or residents.size() >= target_count or identity.is_empty():
		return
	var companion_ids: Array[int] = []
	var spouse_id: int = int(identity.get("spouse_id", -1))
	if spouse_id > 0:
		companion_ids.append(spouse_id)
	var household_id: int = int(identity.get("household_id", -1))
	if household_id > 0 and _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", household_id)
		for member_id in Array(household.get("member_ids", [])):
			var resolved_member_id: int = int(member_id)
			if resolved_member_id > 0 and resolved_member_id != int(identity.get("id", -1)) and not companion_ids.has(resolved_member_id):
				companion_ids.append(resolved_member_id)
	if _population.has_method("get_social_bonds"):
		for bond in _population.call("get_social_bonds", int(identity.get("id", -1)), 3):
			var target_id: int = int(bond.get("target_id", -1))
			if target_id > 0 and int(bond.get("score", 0)) >= 24 and not companion_ids.has(target_id):
				companion_ids.append(target_id)
	for companion_id in companion_ids:
		if residents.size() >= target_count or seen.has(companion_id):
			continue
		if not _population.has_method("get_person"):
			break
		var companion: Dictionary = _population.call("get_person", companion_id)
		if companion.is_empty() or not bool(companion.get("alive", true)):
			continue
		seen[companion_id] = true
		residents.append(companion)


func _rebuild_social_group_state(residents: Array) -> void:
	var social_plan: Dictionary = _plan_social_groups(residents)
	_social_groups = Dictionary(social_plan.get("groups", {}))
	_person_group_assignments = Dictionary(social_plan.get("assignments", {}))


func _apply_identity_to_pedestrian(ped: Dictionary, index: int, identity: Dictionary) -> Dictionary:
	var group_info: Dictionary = _group_assignment_for_identity(identity)
	ped["identity"] = identity
	ped["root"].set_meta("identity", identity)
	ped["group_id"] = str(group_info.get("id", ""))
	ped["group_kind"] = str(group_info.get("kind", "solo"))
	ped["group_role"] = str(group_info.get("role", "solo"))
	ped["leader_person_id"] = int(group_info.get("leader_id", int(identity.get("id", -1))))
	ped["group_offset"] = Vector3(group_info.get("offset", Vector3.ZERO))
	var display_name: String = str(identity.get("full_name", "Pedestrian"))
	ped["root"].name = "Pedestrian_%02d_%s_%s" % [index, String(ped.get("type", "person")), display_name.replace(" ", "_")]
	_refresh_identity_label(ped["root"], identity)
	return ped


func _rebuild_group_leader_indices() -> void:
	_group_leader_indices_by_person.clear()
	_group_leader_indices_by_group.clear()
	for index in range(_pedestrians.size()):
		var ped: Dictionary = _pedestrians[index]
		if str(ped.get("group_role", "solo")) != "leader":
			continue
		var identity: Dictionary = ped.get("identity", {})
		if not identity.is_empty():
			_group_leader_indices_by_person[int(identity.get("id", -1))] = index
		var group_id: String = str(ped.get("group_id", ""))
		if group_id != "":
			_group_leader_indices_by_group[group_id] = index


func _refresh_dog_social_state(ped: Dictionary, dog_index: int) -> Dictionary:
	ped["identity"] = {}
	var group_info: Dictionary = _dog_group_assignments[dog_index] if dog_index < _dog_group_assignments.size() else {}
	ped["group_id"] = str(group_info.get("group_id", ""))
	ped["group_kind"] = str(group_info.get("group_kind", "solo"))
	ped["group_role"] = "dog" if not group_info.is_empty() else "solo"
	ped["leader_person_id"] = int(group_info.get("leader_id", -1))
	ped["group_offset"] = Vector3(group_info.get("offset", Vector3.ZERO))
	return ped


func _group_assignment_for_identity(identity: Dictionary) -> Dictionary:
	if identity.is_empty():
		return {}
	return Dictionary(_person_group_assignments.get(int(identity.get("id", -1)), {}))


func _plan_social_groups(residents: Array) -> Dictionary:
	var groups: Dictionary = {}
	var assignments: Dictionary = {}
	if residents.is_empty() or _population == null:
		return {"groups": groups, "assignments": assignments}
	var eligible_count: int = int(round(float(residents.size()) * social_group_share))
	var activity_by_id: Dictionary = {}
	var selected_by_id: Dictionary = {}
	var used: Dictionary = {}
	for identity in residents:
		var person_id: int = int(identity.get("id", -1))
		if person_id <= 0:
			continue
		selected_by_id[person_id] = identity
		activity_by_id[person_id] = _activity_for_identity(identity)
	var group_index: int = 0
	var household_members: Dictionary = {}
	for identity in residents:
		var person_id: int = int(identity.get("id", -1))
		var household_id: int = int(identity.get("household_id", -1))
		if person_id <= 0 or household_id <= 0:
			continue
		if not _allows_family_group_mode(_mode_for_activity(activity_by_id.get(person_id, {}))):
			continue
		if not household_members.has(household_id):
			household_members[household_id] = []
		Array(household_members[household_id]).append(identity)
	for household_id in household_members.keys():
		var members: Array = Array(household_members[household_id])
		if members.size() < 2 or used.size() >= eligible_count:
			continue
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_age: int = int(a.get("age", 30))
			var b_age: int = int(b.get("age", 30))
			if (a_age < 18) != (b_age < 18):
				return a_age >= 18
			return a_age > b_age
		)
		var family_members: Array = []
		for member in members:
			var member_id: int = int(member.get("id", -1))
			if used.has(member_id):
				continue
			family_members.append(member)
			if family_members.size() >= max_social_group_members:
				break
		if family_members.size() >= 2:
			group_index = _register_social_group(groups, assignments, used, group_index, "family", family_members, _select_group_leader(family_members), activity_by_id)

	for identity in residents:
		if used.size() >= eligible_count:
			break
		var person_id: int = int(identity.get("id", -1))
		var spouse_id: int = int(identity.get("spouse_id", -1))
		if person_id <= 0 or spouse_id <= 0 or used.has(person_id) or used.has(spouse_id):
			continue
		if not selected_by_id.has(spouse_id):
			continue
		var spouse: Dictionary = Dictionary(selected_by_id.get(spouse_id, {}))
		if spouse.is_empty() or not _activities_can_share_group(activity_by_id.get(person_id, {}), activity_by_id.get(spouse_id, {})):
			continue
		group_index = _register_social_group(groups, assignments, used, group_index, "lovers", [identity, spouse], person_id, activity_by_id)

	for identity in residents:
		if used.size() >= eligible_count:
			break
		var person_id: int = int(identity.get("id", -1))
		if person_id <= 0 or used.has(person_id):
			continue
		var friend_members: Array = [identity]
		if _population.has_method("get_social_bonds"):
			for bond in _population.call("get_social_bonds", person_id, 4):
				var target_id: int = int(bond.get("target_id", -1))
				if target_id <= 0 or used.has(target_id) or not selected_by_id.has(target_id):
					continue
				if int(bond.get("score", 0)) < 26:
					continue
				var friend: Dictionary = Dictionary(selected_by_id.get(target_id, {}))
				if friend.is_empty() or not _activities_can_share_group(activity_by_id.get(person_id, {}), activity_by_id.get(target_id, {})):
					continue
				friend_members.append(friend)
				if friend_members.size() >= mini(3, max_social_group_members):
					break
		if friend_members.size() >= 2:
			group_index = _register_social_group(groups, assignments, used, group_index, "friends", friend_members, person_id, activity_by_id)

	return {"groups": groups, "assignments": assignments}


func _register_social_group(groups: Dictionary, assignments: Dictionary, used: Dictionary, group_index: int, group_kind: String, members: Array, leader_id: int, activity_by_id: Dictionary) -> int:
	var filtered: Array = []
	for member in members:
		var member_id: int = int(member.get("id", -1))
		if member_id <= 0 or used.has(member_id):
			continue
		filtered.append(member)
	if filtered.size() < 2:
		return group_index
	group_index += 1
	var group_id: String = "%s_%02d" % [group_kind, group_index]
	var ordered: Array = []
	var leader_identity: Dictionary = {}
	for member in filtered:
		if int(member.get("id", -1)) == leader_id:
			leader_identity = member
			break
	if leader_identity.is_empty():
		leader_identity = filtered[0]
	ordered.append(leader_identity)
	for member in filtered:
		if int(member.get("id", -1)) != int(leader_identity.get("id", -1)):
			ordered.append(member)
	var formation: Array = _group_offsets_for_kind(group_kind, ordered.size())
	var anchor: Vector3 = _spawn_position_for_identity(leader_identity)
	var member_ids: Array = []
	groups[group_id] = {
		"id": group_id,
		"kind": group_kind,
		"leader_id": int(leader_identity.get("id", -1)),
		"member_ids": member_ids,
		"anchor": anchor,
		"mode": _mode_for_activity(activity_by_id.get(int(leader_identity.get("id", -1)), {}))
	}
	for member_index in range(ordered.size()):
		var member: Dictionary = ordered[member_index]
		var member_id: int = int(member.get("id", -1))
		used[member_id] = true
		member_ids.append(member_id)
		assignments[member_id] = {
			"id": group_id,
			"kind": group_kind,
			"leader_id": int(leader_identity.get("id", -1)),
			"role": "leader" if member_index == 0 else "member",
			"offset": formation[member_index] if member_index < formation.size() else Vector3.ZERO,
			"anchor": anchor
		}
	return group_index


func _select_group_leader(members: Array) -> int:
	var best_id: int = int(Dictionary(members[0]).get("id", -1)) if not members.is_empty() else -1
	var best_score: float = -INF
	for member in members:
		var identity: Dictionary = member
		var age: int = int(identity.get("age", 30))
		var score: float = float(age)
		if age >= 18:
			score += 120.0
		if int(identity.get("spouse_id", -1)) > 0:
			score += 18.0
		if score > best_score:
			best_score = score
			best_id = int(identity.get("id", -1))
	return best_id


func _mode_for_activity(activity: Dictionary) -> String:
	return str(activity.get("mode", "wander"))


func _allows_family_group_mode(mode: String) -> bool:
	return ["home", "wander", "market", "plaza", "evening_stroll"].has(mode)


func _activities_can_share_group(activity_a: Dictionary, activity_b: Dictionary) -> bool:
	var mode_a: String = _mode_for_activity(activity_a)
	var mode_b: String = _mode_for_activity(activity_b)
	if mode_a == mode_b:
		return true
	var relaxed_modes := ["home", "wander", "market", "plaza", "evening_stroll"]
	return relaxed_modes.has(mode_a) and relaxed_modes.has(mode_b)


func _group_offsets_for_kind(group_kind: String, member_count: int) -> Array:
	var spacing: float = social_group_spacing
	match group_kind:
		"lovers":
			return [
				Vector3.ZERO,
				Vector3(0.42 * spacing, 0.0, -0.28 * spacing)
			].slice(0, member_count)
		"friends":
			return [
				Vector3.ZERO,
				Vector3(0.72 * spacing, 0.0, -0.30 * spacing),
				Vector3(-0.68 * spacing, 0.0, -0.48 * spacing)
			].slice(0, member_count)
		_:
			return [
				Vector3.ZERO,
				Vector3(0.74 * spacing, 0.0, -0.34 * spacing),
				Vector3(-0.72 * spacing, 0.0, -0.54 * spacing),
				Vector3(0.10 * spacing, 0.0, -1.02 * spacing)
			].slice(0, member_count)


func _plan_dog_social_assignments(dog_count: int) -> Array:
	var assignments: Array = []
	if dog_count <= 0:
		return assignments
	var group_ids: Array = _social_groups.keys()
	group_ids.shuffle()
	for group_id in group_ids:
		if assignments.size() >= dog_count:
			break
		if _rng.randf() > dog_group_follow_share:
			continue
		var group: Dictionary = Dictionary(_social_groups.get(group_id, {}))
		if group.is_empty():
			continue
		assignments.append({
			"group_id": str(group.get("id", "")),
			"group_kind": "%s_dog" % str(group.get("kind", "social")),
			"leader_id": int(group.get("leader_id", -1)),
			"offset": Vector3(-0.82 * social_group_spacing, 0.0, -0.98 * social_group_spacing)
		})
	while assignments.size() < dog_count:
		assignments.append({})
	return assignments


func _spawn_pedestrian(index: int, identity: Dictionary = {}, group_info: Dictionary = {}) -> void:
	var type_index: int = _person_type_for_identity(identity)
	var activity: Dictionary = _activity_for_identity(identity)
	var mode: String = str(activity.get("mode", "wander"))
	var root := Node3D.new()
	var display_name: String = str(identity.get("full_name", "Pedestrian"))
	root.name = "Pedestrian_%02d_%s_%s" % [index, PERSON_TYPES[type_index], display_name.replace(" ", "_")]
	add_child(root)
	var visual: Node3D = null
	if index < max_detailed_pedestrians:
		var packed: PackedScene = _load_optional_scene(str(PERSON_SCENE_PATHS[type_index]))
		if packed != null:
			visual = packed.instantiate() as Node3D
	if visual == null:
		visual = _build_proxy_pedestrian_visual(PERSON_TYPES[type_index])
	if visual == null:
		root.queue_free()
		return
	root.add_child(visual)
	var spawn: Vector3 = _group_spawn_position(identity, group_info)
	root.position = spawn
	root.rotation.y = _rng.randf() * TAU
	root.set_meta("identity", identity)
	var ped_type: String = PERSON_TYPES[type_index]
	var speed_scale: float = 0.88 if ped_type == "child" else 1.0
	var initial_target: Vector3 = Vector3(activity.get("target", _pick_target_for_pedestrian({"identity": identity, "mode": mode}, spawn)))
	if not group_info.is_empty() and str(group_info.get("role", "solo")) != "leader":
		var follow_target: Variant = _group_follow_target({
			"type": ped_type,
			"root": root,
			"target": initial_target,
			"group_id": str(group_info.get("id", "")),
			"group_kind": str(group_info.get("kind", "solo")),
			"group_role": str(group_info.get("role", "member")),
			"leader_person_id": int(group_info.get("leader_id", -1)),
			"group_offset": Vector3(group_info.get("offset", Vector3.ZERO))
		}, spawn)
		if follow_target != null:
			initial_target = follow_target
	if show_identity_labels or _tracked_person_ids.has(int(identity.get("id", -1))):
		_add_identity_label(root, identity)
	_pedestrians.append({
		"type": ped_type,
		"root": root,
		"visual": visual,
		"identity": identity,
		"mode": mode,
		"target": initial_target,
		"speed": _pedestrian_speed_for_identity(ped_type, identity, mode) * speed_scale,
		"group_id": str(group_info.get("id", "")),
		"group_kind": str(group_info.get("kind", "solo")),
		"group_role": str(group_info.get("role", "solo")),
		"leader_person_id": int(group_info.get("leader_id", int(identity.get("id", -1)))),
		"group_offset": Vector3(group_info.get("offset", Vector3.ZERO)),
		"bob_phase": _rng.randf() * TAU,
		"gait_time": _rng.randf() * TAU,
		"stuck_time": 0.0,
		"pause_time": 0.0 if str(group_info.get("role", "solo")) != "leader" and not group_info.is_empty() else _random_pause_for_actor(ped_type, mode)
	})


func _spawn_dog(index: int, group_info: Dictionary = {}) -> void:
	var root := Node3D.new()
	root.name = "Dog_%02d" % index
	add_child(root)
	var visual: Node3D = null
	var packed: PackedScene = _load_optional_scene(DOG_SCENE_PATH)
	if packed != null:
		visual = packed.instantiate() as Node3D
	if visual == null:
		visual = _build_proxy_dog_visual()
	if visual == null:
		root.queue_free()
		return
	visual.scale = Vector3.ONE * dog_model_scale
	root.add_child(visual)
	var spawn: Vector3 = _city.call("get_random_walk_point", 0.55) if group_info.is_empty() else _group_spawn_position({}, {
		"anchor": _leader_anchor_for_group(int(group_info.get("leader_id", -1))),
		"offset": Vector3(group_info.get("offset", Vector3.ZERO))
	})
	root.position = spawn
	root.rotation.y = _rng.randf() * TAU
	_pedestrians.append({
		"type": DOG_TYPE,
		"root": root,
		"visual": visual,
		"identity": {},
		"mode": str(group_info.get("group_kind", "wander")),
		"target": _pick_target_for_pedestrian({"type": DOG_TYPE}, spawn) if group_info.is_empty() else spawn,
		"speed": _rng.randf_range(dog_walk_speed_min, dog_walk_speed_max),
		"group_id": str(group_info.get("group_id", "")),
		"group_kind": str(group_info.get("group_kind", "solo")),
		"group_role": "dog" if not group_info.is_empty() else "solo",
		"leader_person_id": int(group_info.get("leader_id", -1)),
		"group_offset": Vector3(group_info.get("offset", Vector3.ZERO)),
		"bob_phase": _rng.randf() * TAU,
		"gait_time": _rng.randf() * TAU,
		"stuck_time": 0.0,
		"pause_time": 0.0 if not group_info.is_empty() else _random_pause_for_actor(DOG_TYPE, "wander"),
		"dog_parts": _collect_dog_parts(visual)
	})


func _group_spawn_position(identity: Dictionary, group_info: Dictionary) -> Vector3:
	var anchor: Vector3 = _spawn_position_for_identity(identity)
	if not group_info.is_empty() and group_info.has("anchor"):
		anchor = Vector3(group_info.get("anchor", anchor))
	var offset: Vector3 = Vector3(group_info.get("offset", Vector3.ZERO)) if not group_info.is_empty() else Vector3.ZERO
	return _offset_group_point(anchor, offset, anchor)


func _offset_group_point(anchor: Vector3, offset: Vector3, fallback: Vector3) -> Vector3:
	var candidate := anchor + Vector3(offset.x, 0.0, offset.z)
	if _city != null and _city.has_method("try_move_on_walk_ground"):
		return _city.call("try_move_on_walk_ground", anchor, candidate)
	if _city != null and _city.has_method("get_nearest_walk_ground_point"):
		return _city.call("get_nearest_walk_ground_point", candidate)
	candidate.y = fallback.y
	return candidate


func _leader_anchor_for_group(leader_person_id: int) -> Vector3:
	if leader_person_id > 0 and _population != null and _population.has_method("get_person"):
		var leader_identity: Dictionary = _population.call("get_person", leader_person_id)
		if not leader_identity.is_empty():
			return _spawn_position_for_identity(leader_identity)
	return _city.call("get_random_walk_point", 0.55)


func _group_follow_target(ped: Dictionary, fallback_position: Vector3) -> Variant:
	var group_role: String = str(ped.get("group_role", "solo"))
	if group_role == "solo" or group_role == "leader":
		return null
	var leader: Dictionary = _pedestrian_for_leader(int(ped.get("leader_person_id", -1)), str(ped.get("group_id", "")))
	if leader.is_empty():
		return null
	var leader_root: Node3D = leader.get("root") as Node3D
	if leader_root == null or not is_instance_valid(leader_root):
		return null
	var leader_position: Vector3 = leader_root.position
	var leader_target: Vector3 = Vector3(leader.get("target", leader_position))
	var forward := Vector2(leader_target.x - leader_position.x, leader_target.z - leader_position.z)
	if forward.length() < 0.08:
		forward = Vector2(0.0, 1.0)
	else:
		forward = forward.normalized()
	var right := Vector2(forward.y, -forward.x)
	var local_offset: Vector3 = Vector3(ped.get("group_offset", Vector3.ZERO))
	var world_offset := Vector2(right.x * local_offset.x + forward.x * local_offset.z, right.y * local_offset.x + forward.y * local_offset.z)
	return _offset_group_point(leader_position, Vector3(world_offset.x, 0.0, world_offset.y), fallback_position)


func _group_speed_for_actor(ped: Dictionary) -> float:
	var leader: Dictionary = _pedestrian_for_leader(int(ped.get("leader_person_id", -1)), str(ped.get("group_id", "")))
	if leader.is_empty():
		return float(ped.get("speed", walk_speed_min))
	var leader_speed: float = float(leader.get("speed", walk_speed_min))
	if str(ped.get("type", "person")) == DOG_TYPE:
		return leader_speed * 1.08
	return leader_speed * 0.98


func _pedestrian_for_leader(leader_person_id: int, group_id: String) -> Dictionary:
	var index: int = -1
	if leader_person_id > 0:
		index = int(_group_leader_indices_by_person.get(leader_person_id, -1))
	elif group_id != "":
		index = int(_group_leader_indices_by_group.get(group_id, -1))
	if index < 0 or index >= _pedestrians.size():
		return {}
	return _pedestrians[index]


func _load_optional_scene(asset_path: String) -> PackedScene:
	if _optional_scene_cache.has(asset_path):
		return _optional_scene_cache[asset_path]
	if not _has_ready_import(asset_path):
		_warn_missing_optional_asset(asset_path)
		_optional_scene_cache[asset_path] = null
		return null
	var resource: Resource = ResourceLoader.load(asset_path)
	if resource is PackedScene:
		var packed := resource as PackedScene
		_optional_scene_cache[asset_path] = packed
		return packed
	_warn_missing_optional_asset(asset_path)
	_optional_scene_cache[asset_path] = null
	return null


func _warn_missing_optional_asset(asset_path: String) -> void:
	if _missing_optional_assets.has(asset_path):
		return
	_missing_optional_assets[asset_path] = true
	push_warning("Optional character asset unavailable, using proxy visual: %s" % asset_path)


func _has_ready_import(asset_path: String) -> bool:
	var import_path := "%s.import" % asset_path
	if not FileAccess.file_exists(import_path):
		return false
	var remap := ConfigFile.new()
	if remap.load(import_path) != OK:
		return false
	var imported_path: String = str(remap.get_value("remap", "path", ""))
	return imported_path != "" and FileAccess.file_exists(imported_path)


func _add_identity_label(root: Node3D, identity: Dictionary) -> void:
	var existing := root.get_node_or_null("IdentityLabel") as Label3D
	if existing != null:
		_refresh_identity_label(root, identity)
		return
	var label := Label3D.new()
	label.name = "IdentityLabel"
	label.position = Vector3(0.0, 2.05, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0028
	label.modulate = Color(1.0, 1.0, 1.0, 0.82)
	root.add_child(label)
	_refresh_identity_label(root, identity)


func _refresh_identity_label(root: Node3D, identity: Dictionary) -> void:
	var label := root.get_node_or_null("IdentityLabel") as Label3D
	if not _should_show_identity_label(identity):
		if label != null:
			label.queue_free()
		return
	if identity.is_empty():
		if label != null:
			label.text = "Resident"
		return
	if label == null:
		_add_identity_label(root, identity)
		return
	label.text = String(identity.get("full_name", "Resident"))
	label.modulate = Color(1.0, 0.96, 0.74, 0.94) if _tracked_person_ids.has(int(identity.get("id", -1))) else Color(1.0, 1.0, 1.0, 0.82)
	label.visible = _is_label_in_range(root, identity)


func _should_show_identity_label(identity: Dictionary) -> bool:
	if show_identity_labels:
		return true
	if identity.is_empty():
		return false
	if _tracked_person_ids.has(int(identity.get("id", -1))):
		return true
	return _is_label_in_range(null, identity)


func _is_label_in_range(root: Node3D, identity: Dictionary) -> bool:
	if show_identity_labels:
		return true
	if _camera == null:
		_resolve_camera()
	if _camera == null:
		return false
	var anchor: Vector3 = root.global_position if root != null else _spawn_position_for_identity(identity)
	var max_distance: float = overlook_label_distance if _camera.has_method("get_view_mode") and _camera.call("get_view_mode") == "overlook" else player_label_distance
	return _camera.global_position.distance_to(anchor) <= max_distance


func _update_label_visibility() -> void:
	if not show_identity_labels and _camera == null and _tracked_person_ids.is_empty():
		return
	for ped in _pedestrians:
		var root: Node3D = ped.get("root") as Node3D
		var identity: Dictionary = ped.get("identity", {})
		if root == null or identity.is_empty():
			continue
		var label := root.get_node_or_null("IdentityLabel") as Label3D
		if label == null and (show_identity_labels or _tracked_person_ids.has(int(identity.get("id", -1))) or _is_label_in_range(root, identity)):
			_add_identity_label(root, identity)
			label = root.get_node_or_null("IdentityLabel") as Label3D
		if label != null:
			label.visible = _is_label_in_range(root, identity)


func _person_type_for_identity(identity: Dictionary) -> int:
	if identity.is_empty():
		return _rng.randi_range(0, PERSON_SCENE_PATHS.size() - 1)
	var age: int = int(identity.get("age", 30))
	if age < 16:
		return 2
	var gender: String = str(identity.get("gender", "male"))
	return 1 if gender == "female" else 0


func _spawn_position_for_identity(identity: Dictionary) -> Vector3:
	var activity: Dictionary = _activity_for_identity(identity)
	if not activity.is_empty():
		return Vector3(activity.get("target", _city.call("get_random_walk_point", 0.55)))
	return _city.call("get_random_walk_point", 0.55)


func _activity_for_identity(identity: Dictionary) -> Dictionary:
	if _population != null and not identity.is_empty() and _population.has_method("get_person_activity"):
		return _population.call("get_person_activity", int(identity.get("id", -1)))
	return {}


func _pick_target_for_pedestrian(ped: Dictionary, from_position: Vector3) -> Vector3:
	var actor_type: String = str(ped.get("type", "person"))
	var min_distance: float = dog_target_distance_min if actor_type == DOG_TYPE else target_distance_min
	var preferred_walk_kind: String = ""
	if _population != null and _population.has_method("get_person_activity"):
		var identity: Dictionary = ped.get("identity", {})
		if not identity.is_empty():
			var activity: Dictionary = _population.call("get_person_activity", int(identity.get("id", -1)))
			if not activity.is_empty():
				var mode: String = str(activity.get("mode", "wander"))
				if mode == "plaza" or mode == "evening_stroll":
					preferred_walk_kind = "square"
				var directed_target: Vector3 = activity.get("target", from_position)
				if Vector2(directed_target.x - from_position.x, directed_target.z - from_position.z).length() >= 1.2:
					return directed_target
	if _city == null or not _city.has_method("get_random_walk_point"):
		return from_position
	for _attempt in range(12):
		var candidate: Vector3 = _city.call("get_random_walk_point", 0.55, preferred_walk_kind)
		if Vector2(candidate.x - from_position.x, candidate.z - from_position.z).length() >= min_distance:
			return candidate
	return _city.call("get_random_walk_point", 0.55, preferred_walk_kind)


func _pedestrian_speed_for_identity(actor_type: String, identity: Dictionary, mode: String) -> float:
	if actor_type == DOG_TYPE:
		return _rng.randf_range(dog_walk_speed_min, dog_walk_speed_max)
	var base_speed: float = _rng.randf_range(walk_speed_min, walk_speed_max)
	var age: int = int(identity.get("age", 30))
	if age < 16:
		base_speed *= 1.06
	elif age >= 68:
		base_speed *= 0.82
	match mode:
		"commute":
			base_speed *= 1.18
		"school":
			base_speed *= 1.05
		"market":
			base_speed *= 0.94
		"plaza":
			base_speed *= 0.86
		"evening_stroll":
			base_speed *= 0.76
		"home":
			base_speed *= 0.72
	return base_speed


func _random_pause_for_actor(actor_type: String, mode: String = "wander") -> float:
	if actor_type == DOG_TYPE:
		return _rng.randf_range(0.12, 0.6) if _rng.randf() < 0.42 else 0.0
	match mode:
		"commute", "school":
			return _rng.randf_range(0.0, 0.25) if _rng.randf() < 0.18 else 0.0
		"market":
			return _rng.randf_range(0.3, 1.1) if _rng.randf() < 0.40 else 0.0
		"plaza":
			return _rng.randf_range(0.5, 1.7) if _rng.randf() < 0.56 else 0.0
		"evening_stroll":
			return _rng.randf_range(0.4, 1.35) if _rng.randf() < 0.48 else 0.0
		_:
			return _rng.randf_range(0.0, 0.8) if _rng.randf() < 0.30 else 0.0


func _spawn_event_effect(root: Node3D, event: Dictionary, cleanup_parent: bool = false) -> void:
	for child in root.get_children():
		if child is Node3D and String(child.name).begins_with("EventEffect_"):
			child.queue_free()
	for index in range(_active_event_effects.size() - 1, -1, -1):
		var existing: Dictionary = _active_event_effects[index]
		var existing_node: Node3D = existing.get("node") as Node3D
		if existing_node == null or not is_instance_valid(existing_node) or existing_node.get_parent() == root:
			_active_event_effects.remove_at(index)
	var effect_root := Node3D.new()
	effect_root.name = "EventEffect_%s" % str(event.get("type", "event"))
	effect_root.position = Vector3(0.0, 0.0, 0.0)
	effect_root.scale = Vector3.ONE * float(event.get("effect_scale", 1.0))
	root.add_child(effect_root)
	var event_type: String = str(event.get("type", "system"))
	_create_event_beacon(effect_root, event_type)
	var caption := Label3D.new()
	caption.name = "Caption"
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.pixel_size = 0.0065
	caption.outline_modulate = Color(0.02, 0.03, 0.05, 0.96)
	caption.position = Vector3(0.0, 6.8, 0.0)
	caption.text = _event_caption_for_type(event_type)
	caption.modulate = _event_caption_color(event_type)
	effect_root.add_child(caption)
	match event_type:
		"birth":
			_create_birth_effect(effect_root)
		"birthday":
			_create_birthday_effect(effect_root)
		"marriage":
			_create_marriage_effect(effect_root)
		"death":
			_create_death_effect(effect_root)
	_active_event_effects.append({
		"node": effect_root,
		"type": event_type,
		"elapsed": 0.0,
		"duration": float(event.get("effect_duration", 2.8)),
		"cleanup_parent": cleanup_parent,
		"parent_root": root
	})
	while _active_event_effects.size() > maxi(1, max_active_event_effects):
		var oldest: Dictionary = _active_event_effects.pop_front()
		var oldest_node: Node3D = oldest.get("node") as Node3D
		if oldest_node != null and is_instance_valid(oldest_node):
			oldest_node.queue_free()
		var oldest_parent: Node3D = oldest.get("parent_root") as Node3D
		if bool(oldest.get("cleanup_parent", false)) and oldest_parent != null and is_instance_valid(oldest_parent):
			oldest_parent.queue_free()


func _update_event_effects(delta: float) -> void:
	for index in range(_active_event_effects.size() - 1, -1, -1):
		var effect: Dictionary = _active_event_effects[index]
		var node: Node3D = effect.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			_active_event_effects.remove_at(index)
			continue
		var elapsed: float = float(effect.get("elapsed", 0.0)) + delta
		var duration: float = maxf(0.1, float(effect.get("duration", 2.8)))
		var t: float = clampf(elapsed / duration, 0.0, 1.0)
		_animate_event_effect(node, str(effect.get("type", "system")), elapsed, t)
		if t >= 1.0:
			var parent_root: Node3D = effect.get("parent_root") as Node3D
			var cleanup_parent: bool = bool(effect.get("cleanup_parent", false))
			node.queue_free()
			if cleanup_parent and parent_root != null and is_instance_valid(parent_root):
				parent_root.queue_free()
			_active_event_effects.remove_at(index)
			continue
		effect["elapsed"] = elapsed
		_active_event_effects[index] = effect


func _spawn_world_event_effect(event: Dictionary) -> void:
	var anchor: Vector3 = _event_anchor_for(event)
	if anchor == Vector3.INF:
		return
	var world_anchor := Node3D.new()
	world_anchor.name = "WorldEventAnchor_%s" % str(event.get("type", "event"))
	world_anchor.position = anchor
	add_child(world_anchor)
	var scaled_event: Dictionary = event.duplicate(true)
	scaled_event["effect_scale"] = float(event.get("effect_scale", 1.0)) * 3.8
	scaled_event["effect_duration"] = _world_event_duration(event)
	_spawn_event_effect(world_anchor, scaled_event, true)


func _event_anchor_for(event: Dictionary) -> Vector3:
	if _population == null:
		return Vector3.INF
	var household_id: int = int(event.get("household_id", -1))
	if household_id != -1 and _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", household_id)
		var household_anchor: Vector3 = _anchor_from_household(household)
		if household_anchor != Vector3.INF:
			return household_anchor
	for person_id in event.get("person_ids", []):
		var person: Dictionary = _population.call("get_person", int(person_id)) if _population.has_method("get_person") else {}
		var person_anchor: Vector3 = _anchor_from_person(person)
		if person_anchor != Vector3.INF:
			return person_anchor
	var primary_person: Dictionary = _population.call("get_person", int(event.get("primary_person_id", -1))) if _population.has_method("get_person") else {}
	return _anchor_from_person(primary_person)


func _anchor_from_person(person: Dictionary) -> Vector3:
	if person.is_empty():
		return Vector3.INF
	if _city != null and _city.has_method("get_building_slot_snapshot"):
		var building: Dictionary = _city.call("get_building_slot_snapshot", person.get("home_building_id", -1))
		if not building.is_empty():
			return _anchor_from_building(building)
	if person.has("home_entry"):
		return Vector3(person.get("home_entry", Vector3.ZERO))
	var household_id: int = int(person.get("household_id", -1))
	if household_id != -1 and _population != null and _population.has_method("get_household"):
		var household: Dictionary = _population.call("get_household", household_id)
		var household_anchor: Vector3 = _anchor_from_household(household)
		if household_anchor != Vector3.INF:
			return household_anchor
	return Vector3.INF


func _anchor_from_household(household: Dictionary) -> Vector3:
	if household.is_empty():
		return Vector3.INF
	if _city != null and _city.has_method("get_building_slot_snapshot"):
		var building: Dictionary = _city.call("get_building_slot_snapshot", household.get("building_id", -1))
		if not building.is_empty():
			return _anchor_from_building(building)
	if _population == null or not _population.has_method("get_person"):
		return Vector3.INF
	for member_id in household.get("member_ids", []):
		var person: Dictionary = _population.call("get_person", int(member_id))
		if person.is_empty():
			continue
		if _city != null and _city.has_method("get_building_slot_snapshot"):
			var member_building: Dictionary = _city.call("get_building_slot_snapshot", person.get("home_building_id", -1))
			if not member_building.is_empty():
				return _anchor_from_building(member_building)
		if person.has("home_entry"):
			return Vector3(person.get("home_entry", Vector3.ZERO))
	return Vector3.INF


func _anchor_from_building(building: Dictionary) -> Vector3:
	if building.is_empty():
		return Vector3.INF
	var entry: Vector3 = Vector3(building.get("entry", building.get("center", Vector3.ZERO)))
	var center: Vector3 = Vector3(building.get("center", entry))
	var outward := Vector3(entry.x - center.x, 0.0, entry.z - center.z)
	if outward.length() < 0.05:
		outward = Vector3(0.0, 0.0, -1.0)
	else:
		outward = outward.normalized()
	var roadside_target := entry + outward * maxf(0.8, house_event_roadside_offset)
	if _city != null and _city.has_method("get_nearest_walk_ground_point"):
		var nearest_ground: Vector3 = _city.call("get_nearest_walk_ground_point", roadside_target)
		return Vector3(nearest_ground.x, nearest_ground.y + world_event_ground_lift, nearest_ground.z)
	if _city != null and _city.has_method("try_move_on_walk_ground"):
		var grounded: Vector3 = _city.call("try_move_on_walk_ground", entry, roadside_target)
		return Vector3(grounded.x, grounded.y + world_event_ground_lift, grounded.z)
	if _city != null and _city.has_method("get_walk_ground_height"):
		return Vector3(roadside_target.x, float(_city.call("get_walk_ground_height", roadside_target)) + world_event_ground_lift, roadside_target.z)
	return Vector3(roadside_target.x, entry.y + world_event_ground_lift, roadside_target.z)


func _world_event_duration(event: Dictionary) -> float:
	var requested: float = float(event.get("effect_duration", 2.8)) * 3.2
	var hours_per_second_value: float = 72.0
	if _population != null and _population.get("hours_per_second") != null:
		hours_per_second_value = maxf(0.01, float(_population.get("hours_per_second")))
	var persistence_seconds: float = maxf(10.0, (maxf(1.0, world_event_persistence_days) * 24.0) / hours_per_second_value)
	return maxf(requested, persistence_seconds)


func _animate_event_effect(node: Node3D, event_type: String, elapsed: float, t: float) -> void:
	node.position = Vector3(0.0, sin(elapsed * 1.8) * 0.18, 0.0)
	var caption := node.get_node_or_null("Caption") as Label3D
	if caption != null:
		caption.position.y = 6.8 + sin(elapsed * 2.1) * 0.24
		caption.modulate.a = clampf(1.0 - t * 0.72, 0.0, 1.0)
	var ground_ring := node.get_node_or_null("BeaconGroundRing") as MeshInstance3D
	if ground_ring != null:
		var ring_scale: float = 1.0 + sin(elapsed * 2.4) * 0.08
		ground_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
		_set_mesh_alpha(ground_ring, clampf(0.56 - t * 0.18, 0.18, 0.62))
	var base_disc := node.get_node_or_null("BeaconBaseDisc") as MeshInstance3D
	if base_disc != null:
		var disc_scale: float = 1.0 + sin(elapsed * 1.8 + 0.6) * 0.05
		base_disc.scale = Vector3(disc_scale, 1.0, disc_scale)
		_set_mesh_alpha(base_disc, clampf(0.22 - t * 0.08, 0.08, 0.24))
	var beam := node.get_node_or_null("BeaconBeam") as MeshInstance3D
	if beam != null:
		beam.scale.y = 1.0 + sin(elapsed * 2.6) * 0.06
		_set_mesh_alpha(beam, clampf(0.30 - t * 0.18, 0.08, 0.32))
	var flare := node.get_node_or_null("BeaconFlare") as MeshInstance3D
	if flare != null:
		flare.position.y = 5.5 + sin(elapsed * 3.0) * 0.2
		flare.scale = Vector3.ONE * (1.0 + sin(elapsed * 3.8) * 0.08)
		_set_mesh_alpha(flare, clampf(0.88 - t * 0.45, 0.18, 0.9))
	match event_type:
		"birth":
			_animate_birth_effect(node, elapsed, t)
		"birthday":
			_animate_birthday_effect(node, elapsed, t)
		"marriage":
			_animate_marriage_effect(node, elapsed, t)
		"death":
			_animate_death_effect(node, elapsed, t)


func _event_caption_for_type(event_type: String) -> String:
	match event_type:
		"birth":
			return "new life"
		"birthday":
			return "birthday"
		"marriage":
			return "married"
		"death":
			return "farewell"
		_:
			return "event"


func _event_caption_color(event_type: String) -> Color:
	match event_type:
		"birth":
			return Color(1.0, 0.87, 0.48, 0.96)
		"birthday":
			return Color(1.0, 0.82, 0.40, 0.96)
		"marriage":
			return Color(1.0, 0.78, 0.88, 0.96)
		"death":
			return Color(0.86, 0.92, 1.0, 0.96)
		_:
			return Color(1.0, 1.0, 1.0, 0.96)


func _create_event_beacon(effect_root: Node3D, event_type: String) -> void:
	var color: Color = _event_caption_color(event_type)
	var base_disc := MeshInstance3D.new()
	base_disc.name = "BeaconBaseDisc"
	var base_disc_mesh := CylinderMesh.new()
	base_disc_mesh.top_radius = 1.35
	base_disc_mesh.bottom_radius = 1.35
	base_disc_mesh.height = 0.04
	base_disc.mesh = base_disc_mesh
	base_disc.position = Vector3(0.0, 0.03, 0.0)
	base_disc.material_override = _make_glow_material(Color(color.r, color.g, color.b, 0.18))
	effect_root.add_child(base_disc)
	var ground_ring := MeshInstance3D.new()
	ground_ring.name = "BeaconGroundRing"
	var ground_ring_mesh := CylinderMesh.new()
	ground_ring_mesh.top_radius = 1.95
	ground_ring_mesh.bottom_radius = 1.95
	ground_ring_mesh.height = 0.03
	ground_ring.mesh = ground_ring_mesh
	ground_ring.position = Vector3(0.0, 0.05, 0.0)
	ground_ring.material_override = _make_glow_material(Color(color.r, color.g, color.b, 0.48))
	effect_root.add_child(ground_ring)
	var beam := MeshInstance3D.new()
	beam.name = "BeaconBeam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.16
	beam_mesh.bottom_radius = 0.34
	beam_mesh.height = 10.0
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, 5.0, 0.0)
	beam.material_override = _make_glow_material(Color(color.r, color.g, color.b, 0.26))
	effect_root.add_child(beam)
	var flare := MeshInstance3D.new()
	flare.name = "BeaconFlare"
	var flare_mesh := SphereMesh.new()
	flare_mesh.radius = 0.42
	flare_mesh.height = 0.84
	flare.mesh = flare_mesh
	flare.position = Vector3(0.0, 5.5, 0.0)
	flare.material_override = _make_glow_material(Color(color.r, color.g, color.b, 0.92))
	effect_root.add_child(flare)


func _create_birth_effect(effect_root: Node3D) -> void:
	var colors := [
		Color(1.0, 0.56, 0.44, 0.95),
		Color(0.99, 0.79, 0.30, 0.95),
		Color(0.60, 0.84, 1.0, 0.95)
	]
	for index in range(colors.size()):
		var balloon: MeshInstance3D = _make_orb_mesh(0.12, colors[index])
		balloon.name = "Balloon_%d" % index
		effect_root.add_child(balloon)


func _create_birthday_effect(effect_root: Node3D) -> void:
	var colors := [
		Color(1.0, 0.48, 0.42, 0.95),
		Color(0.99, 0.78, 0.22, 0.95),
		Color(0.52, 0.84, 0.40, 0.95),
		Color(0.46, 0.76, 1.0, 0.95),
		Color(0.88, 0.62, 1.0, 0.95)
	]
	for index in range(colors.size()):
		var confetti: MeshInstance3D = _make_orb_mesh(0.045, colors[index])
		confetti.name = "Confetti_%d" % index
		effect_root.add_child(confetti)


func _create_marriage_effect(effect_root: Node3D) -> void:
	for index in range(10):
		var petal: MeshInstance3D = _make_orb_mesh(0.05, Color(1.0, 0.72 + 0.02 * float(index % 3), 0.84 + 0.01 * float(index % 2), 0.9))
		petal.name = "Petal_%d" % index
		effect_root.add_child(petal)


func _create_death_effect(effect_root: Node3D) -> void:
	var halo: MeshInstance3D = _make_orb_mesh(0.16, Color(0.78, 0.87, 1.0, 0.28))
	halo.name = "Halo"
	effect_root.add_child(halo)
	for index in range(6):
		var mote: MeshInstance3D = _make_orb_mesh(0.045, Color(0.92, 0.96, 1.0, 0.72))
		mote.name = "Mote_%d" % index
		effect_root.add_child(mote)


func _animate_birth_effect(node: Node3D, elapsed: float, t: float) -> void:
	var fade: float = clampf(1.0 - t * 0.88, 0.0, 1.0)
	for child in node.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Balloon_"):
			var index: int = int(String(child.name).trim_prefix("Balloon_"))
			var phase: float = elapsed * 1.65 + float(index) * 2.2
			child.position = Vector3(sin(phase) * 0.22, 0.22 + float(index) * 0.08 + t * 0.82, cos(phase * 0.75) * 0.14)
			child.scale = Vector3.ONE * (1.0 + sin(phase * 1.4) * 0.08)
			_set_mesh_alpha(child as MeshInstance3D, fade)


func _animate_birthday_effect(node: Node3D, elapsed: float, t: float) -> void:
	var fade: float = clampf(1.0 - t * 0.92, 0.0, 1.0)
	for child in node.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Confetti_"):
			var index: int = int(String(child.name).trim_prefix("Confetti_"))
			var angle: float = float(index) / 5.0 * TAU + elapsed * 3.4
			var radius: float = 0.10 + t * 0.58
			child.position = Vector3(cos(angle) * radius, 0.24 + t * 0.92 + sin(elapsed * 5.0 + float(index)) * 0.12, sin(angle) * radius)
			child.scale = Vector3(0.8, 1.3, 0.8) * (0.9 + (1.0 - t) * 0.35)
			_set_mesh_alpha(child as MeshInstance3D, fade)


func _animate_marriage_effect(node: Node3D, elapsed: float, t: float) -> void:
	var fade: float = clampf(1.0 - t * 0.95, 0.0, 1.0)
	for child in node.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Petal_"):
			var index: int = int(String(child.name).trim_prefix("Petal_"))
			var angle: float = float(index) / 10.0 * TAU + elapsed * 1.7
			var radius: float = 0.12 + t * 0.55 + sin(elapsed * 3.2 + float(index)) * 0.04
			child.position = Vector3(cos(angle) * radius, 0.35 + t * 0.24 + sin(angle * 2.0) * 0.06, sin(angle) * radius)
			child.scale = Vector3.ONE * (0.86 + (1.0 - t) * 0.42)
			_set_mesh_alpha(child as MeshInstance3D, fade)


func _animate_death_effect(node: Node3D, elapsed: float, t: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.name == "Halo":
			child.position = Vector3(0.0, 0.34 + t * 0.18, 0.0)
			child.scale = Vector3.ONE * (1.0 + t * 1.9)
			_set_mesh_alpha(child as MeshInstance3D, clampf(0.32 - t * 0.28, 0.0, 0.32))
		elif child is MeshInstance3D and String(child.name).begins_with("Mote_"):
			var index: int = int(String(child.name).trim_prefix("Mote_"))
			var angle: float = float(index) / 6.0 * TAU + elapsed * 0.9
			var radius: float = 0.08 + t * 0.24
			child.position = Vector3(cos(angle) * radius, 0.18 + float(index) * 0.03 + t * 0.62, sin(angle) * radius)
			child.scale = Vector3.ONE * (0.82 + t * 0.36)
			_set_mesh_alpha(child as MeshInstance3D, clampf(0.75 - t * 0.68, 0.0, 0.75))


func _make_orb_mesh(radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	material.no_depth_test = false
	instance.material_override = material
	return instance


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 1.7
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	material.no_depth_test = false
	return material


func _build_proxy_pedestrian_visual(ped_type: String) -> Node3D:
	var color: Color = PERSON_COLORS.get(ped_type, Color.WHITE)
	var visual := Node3D.new()
	visual.name = "ProxyVisual"
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.16 if ped_type != "child" else 0.12
	body_mesh.height = 0.74 if ped_type != "child" else 0.52
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.52 if ped_type != "child" else 0.38, 0.0)
	body.material_override = _make_unshaded_material(color)
	visual.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12 if ped_type != "child" else 0.1
	head_mesh.height = head_mesh.radius * 2.0
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.08 if ped_type != "child" else 0.82, 0.0)
	head.material_override = _make_unshaded_material(color.lightened(0.25))
	visual.add_child(head)
	return visual


func _build_proxy_dog_visual() -> Node3D:
	var visual := Node3D.new()
	visual.name = "DogProxy"
	var fur: StandardMaterial3D = _make_unshaded_material(PERSON_COLORS.get(DOG_TYPE, Color(0.74, 0.56, 0.28)))
	var accent: StandardMaterial3D = _make_unshaded_material(Color(0.20, 0.15, 0.10))
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.9, 0.34, 0.34)
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.52, 0.0)
	body.material_override = fur
	visual.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.34, 0.26, 0.24)
	head.mesh = head_mesh
	head.position = Vector3(0.56, 0.66, 0.0)
	head.material_override = fur
	head.name = "Dog_Head"
	visual.add_child(head)
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.12, 0.36, 0.08)
	tail.mesh = tail_mesh
	tail.position = Vector3(-0.52, 0.76, 0.0)
	tail.rotation.z = deg_to_rad(48.0)
	tail.material_override = accent
	tail.name = "Dog_Tail"
	visual.add_child(tail)
	for leg_data in [
		["Dog_Leg_FL", Vector3(0.26, 0.20, 0.12)],
		["Dog_Leg_FR", Vector3(0.26, 0.20, -0.12)],
		["Dog_Leg_BL", Vector3(-0.24, 0.20, 0.12)],
		["Dog_Leg_BR", Vector3(-0.24, 0.20, -0.12)]
	]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.10, 0.34, 0.08)
		leg.mesh = leg_mesh
		leg.position = leg_data[1]
		leg.material_override = accent
		leg.name = String(leg_data[0])
		visual.add_child(leg)
	return visual


func _animate_actor_visual(ped: Dictionary, delta: float, moving: bool) -> Dictionary:
	var visual: Node3D = ped.get("visual") as Node3D
	if visual == null or not is_instance_valid(visual):
		return ped
	var actor_type: String = str(ped.get("type", "person"))
	if actor_type == DOG_TYPE:
		var gait_time: float = float(ped.get("gait_time", 0.0)) + delta * (1.6 if not moving else 4.6 + float(ped.get("speed", 1.0)) * 2.2)
		ped["gait_time"] = gait_time
		visual.position.y = sin(gait_time * 2.0) * (0.012 if not moving else 0.032)
		_pose_dog_visual(visual, ped.get("dog_parts", {}), gait_time, moving)
		return ped
	ped["bob_phase"] = float(ped.get("bob_phase", 0.0)) + delta * (2.0 if not moving else 5.2 + float(ped.get("speed", 1.0)) * 2.8)
	visual.position.y = sin(float(ped["bob_phase"])) * bob_height * 0.12 if not moving else absf(sin(float(ped["bob_phase"]))) * bob_height
	return ped


func _collect_dog_parts(visual: Node3D) -> Dictionary:
	return {
		"head": _find_descendant_by_name_fragment(visual, "Dog_Head"),
		"tail": _find_descendant_by_name_fragment(visual, "Dog_Tail"),
		"leg_fl": _find_descendant_by_name_fragment(visual, "Dog_Leg_FL"),
		"leg_fr": _find_descendant_by_name_fragment(visual, "Dog_Leg_FR"),
		"leg_bl": _find_descendant_by_name_fragment(visual, "Dog_Leg_BL"),
		"leg_br": _find_descendant_by_name_fragment(visual, "Dog_Leg_BR")
	}


func _find_descendant_by_name_fragment(root: Node, fragment: String) -> Node3D:
	if root == null:
		return null
	for child in root.get_children():
		if child is Node3D and String(child.name).contains(fragment):
			return child as Node3D
		var nested: Node3D = _find_descendant_by_name_fragment(child, fragment)
		if nested != null:
			return nested
	return null


func _pose_dog_visual(visual: Node3D, dog_parts: Dictionary, gait_time: float, moving: bool) -> void:
	var body_pitch: float = sin(gait_time * 2.0) * (0.02 if not moving else 0.07)
	visual.rotation.z = body_pitch
	var head: Node3D = dog_parts.get("head") as Node3D
	if head != null:
		head.rotation.z = -body_pitch * 0.7 + sin(gait_time * 1.3) * 0.04
	var tail: Node3D = dog_parts.get("tail") as Node3D
	if tail != null:
		tail.rotation.y = sin(gait_time * 5.0) * (0.16 if not moving else 0.34)
		tail.rotation.z = deg_to_rad(48.0) + sin(gait_time * 2.5) * 0.08
	var stride: float = 0.10 if not moving else 0.48
	_set_dog_leg_angle(dog_parts.get("leg_fl") as Node3D, sin(gait_time * 4.0) * stride)
	_set_dog_leg_angle(dog_parts.get("leg_br") as Node3D, sin(gait_time * 4.0) * stride)
	_set_dog_leg_angle(dog_parts.get("leg_fr") as Node3D, -sin(gait_time * 4.0) * stride)
	_set_dog_leg_angle(dog_parts.get("leg_bl") as Node3D, -sin(gait_time * 4.0) * stride)


func _set_dog_leg_angle(node: Node3D, angle: float) -> void:
	if node == null:
		return
	node.rotation.z = angle


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	return material


func _set_mesh_alpha(mesh_instance: MeshInstance3D, alpha: float) -> void:
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		return
	var color: Color = material.albedo_color
	color.a = alpha
	material.albedo_color = color
