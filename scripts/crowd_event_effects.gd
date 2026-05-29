extends Node
# class_name CrowdEventEffects — uses preload from pedestrian_crowd.gd instead

## ECS System: manages life event visual effects (births, deaths, marriages, birthdays).
## Self-contained — creates/deletes visual nodes from event data.

var active_event_effects: Array = []  # Active visual effect instances

@export var max_active_event_effects: int = 12
@export var world_event_ground_lift: float = 0.16
@export var world_event_persistence_days: float = 90.0


func receive_config(config: Dictionary) -> void:
	max_active_event_effects = int(config.get("max_active_event_effects", 12))
	world_event_ground_lift = float(config.get("world_event_ground_lift", 0.16))
	world_event_persistence_days = float(config.get("world_event_persistence_days", 90.0))


func clear() -> void:
	for effect in active_event_effects:
		var parent_root: Node3D = effect.get("parent_root") as Node3D
		if parent_root != null and is_instance_valid(parent_root):
			parent_root.queue_free()
	active_event_effects.clear()


func get_active_effect_count() -> int:
	return active_event_effects.size()


func play_life_event_effect(event: Dictionary, crowd_node: Node = null) -> void:
	if event.is_empty():
		return
	# Remove expired effects
	for index in range(active_event_effects.size() - 1, -1, -1):
		var effect: Dictionary = active_event_effects[index]
		var elapsed: float = float(effect.get("elapsed", 0.0))
		var duration: float = float(effect.get("duration", 10.0))
		if elapsed > duration:
			var parent_root: Node3D = effect.get("parent_root") as Node3D
			if parent_root != null and is_instance_valid(parent_root):
				parent_root.queue_free()
			active_event_effects.remove_at(index)
	# Evict oldest if at capacity
	while active_event_effects.size() >= max_active_event_effects:
		var oldest: Dictionary = active_event_effects[0]
		var oldest_root: Node3D = oldest.get("parent_root") as Node3D
		if oldest_root != null and is_instance_valid(oldest_root):
			oldest_root.queue_free()
		active_event_effects.remove_at(0)
	# Spawn the visual effect
	if event.get("type") == "birth" or event.get("type") == "birthday" \
		or event.get("type") == "marriage" or event.get("type") == "death":
		var effect_root := Node3D.new()
		effect_root.name = "LifeEventEffect_%s" % event.get("type", "event")
		var anchor: Vector3 = _event_anchor_for(event, crowd_node)
		if anchor == Vector3.INF:
			return
		effect_root.position = anchor
		if crowd_node != null and crowd_node.has_method("get_city_layout"):
			var layout = crowd_node.get_city_layout()
			if layout != null:
				effect_root.position.y = layout.get_walk_ground_height(anchor) + world_event_ground_lift
		add_child(effect_root)
		_spawn_event_effect(effect_root, event)


func update(delta: float) -> void:
	for index in range(active_event_effects.size() - 1, -1, -1):
		var effect: Dictionary = active_event_effects[index]
		effect["elapsed"] = float(effect.get("elapsed", 0.0)) + delta
		var node_variant = effect.get("node")
		if node_variant == null:
			active_event_effects.remove_at(index)
			continue
		if not is_instance_valid(node_variant):
			active_event_effects.remove_at(index)
			continue
		var node: Node3D = node_variant as Node3D
		var event_type: String = str(effect.get("event_type", ""))
		var elapsed: float = float(effect.get("elapsed", 0.0))
		if node != null and is_instance_valid(node):
			var t: float = clampf(elapsed / maxf(0.001, float(effect.get("duration", 10.0))), 0.0, 1.0)
			_animate_event_effect(node, event_type, elapsed, t)
			if elapsed > float(effect.get("duration", 10.0)):
				var fade: float = maxf(0.0, 1.0 - (elapsed - float(effect.get("duration", 10.0))) * 0.5)
				if node is MeshInstance3D:
					var mi: MeshInstance3D = node as MeshInstance3D
					if mi.material_override != null and mi.material_override is StandardMaterial3D:
						var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
						mat.albedo_color.a = fade
						mat.emission_enabled = fade > 0.01
		var duration: float = float(effect.get("duration", 10.0))
		if elapsed > duration + 2.0:
			var parent_root: Node3D = effect.get("parent_root") as Node3D
			if parent_root != null and is_instance_valid(parent_root):
				parent_root.queue_free()
			active_event_effects.remove_at(index)


func _spawn_event_effect(root: Node3D, event: Dictionary) -> void:
	var event_type: String = str(event.get("type", "birth"))
	var duration: float = _world_event_duration(event)
	var effect_node: Node3D
	match event_type:
		"birth":
			effect_node = _create_birth_effect(root)
		"birthday":
			effect_node = _create_birthday_effect(root)
		"marriage":
			effect_node = _create_marriage_effect(root)
		"death":
			effect_node = _create_death_effect(root)
		_:
			effect_node = _create_event_beacon(root, event_type)
	if effect_node == null:
		root.queue_free()
		return
	active_event_effects.append({
		"node": effect_node,
		"parent_root": root,
		"event_type": event_type,
		"elapsed": 0.0,
		"duration": duration
	})
	if event_type in ["birth", "death", "marriage"]:
		var caption: Node3D = _create_event_caption(root, event_type, event)
		if caption != null:
			active_event_effects.append({
				"node": caption,
				"parent_root": root,
				"event_type": event_type + "_caption",
				"elapsed": 0.0,
				"duration": duration + 1.0
			})


func _event_anchor_for(event: Dictionary, crowd_node: Node = null) -> Vector3:
	if crowd_node == null:
		return Vector3.INF
	var population = crowd_node.get("_population") if crowd_node != null else null
	if population == null or not population.has_method("get_person"):
		return Vector3.INF
	var household_id: int = int(event.get("household_id", -1))
	if household_id != -1 and population.has_method("get_household"):
		var household: Dictionary = population.call("get_household", household_id)
		for member_id in household.get("member_ids", []):
			var person: Dictionary = population.call("get_person", int(member_id))
			if not person.is_empty() and person.has("home_entry"):
				return Vector3(person.get("home_entry", Vector3.ZERO))
	for person_id in event.get("person_ids", []):
		var event_person: Dictionary = population.call("get_person", int(person_id))
		if not event_person.is_empty() and event_person.has("home_entry"):
			return Vector3(event_person.get("home_entry", Vector3.ZERO))
	return Vector3.INF


func _world_event_duration(event: Dictionary) -> float:
	match str(event.get("type", "")):
		"birth":
			return 5.0
		"birthday":
			return 3.5
		"marriage":
			return 6.0
		_:
			return 4.0


func _create_event_beacon(effect_root: Node3D, event_type: String) -> Node3D:
	var beacon := MeshInstance3D.new()
	beacon.mesh = _cached_sphere(0.12)
	beacon.material_override = _make_glow_material(_event_type_color(event_type))
	effect_root.add_child(beacon)
	return beacon


func _create_birth_effect(effect_root: Node3D) -> Node3D:
	var root := Node3D.new()
	var color: Color = Color(0.92, 0.72, 0.48)
	for i in range(8):
		var orb := MeshInstance3D.new()
		orb.mesh = _cached_sphere(0.06)
		orb.material_override = _make_glow_material(color)
		var angle: float = TAU * float(i) / 8.0
		orb.position = Vector3(cos(angle) * 0.2, 0.15 + sin(angle * 2.0) * 0.05, sin(angle) * 0.2)
		root.add_child(orb)
	effect_root.add_child(root)
	return root


func _create_birthday_effect(effect_root: Node3D) -> Node3D:
	return _create_event_beacon(effect_root, "birthday")


func _create_marriage_effect(effect_root: Node3D) -> Node3D:
	var root := Node3D.new()
	var colors: Array[Color] = [Color(0.85, 0.65, 0.75), Color(0.95, 0.80, 0.70)]
	for i in range(6):
		var orb := MeshInstance3D.new()
		orb.mesh = _cached_sphere(0.08)
		orb.material_override = _make_glow_material(colors[i % 2])
		var angle: float = TAU * float(i) / 6.0
		orb.position = Vector3(cos(angle) * 0.3, 0.25, sin(angle) * 0.3)
		root.add_child(orb)
	effect_root.add_child(root)
	return root


func _create_death_effect(effect_root: Node3D) -> Node3D:
	var root := Node3D.new()
	var orb := MeshInstance3D.new()
	orb.mesh = _cached_sphere(0.15)
	orb.material_override = _make_glow_material(Color(0.60, 0.60, 0.65))
	orb.position = Vector3(0.0, 0.12, 0.0)
	root.add_child(orb)
	effect_root.add_child(root)
	return root


func _animate_event_effect(node: Node3D, event_type: String, elapsed: float, t: float) -> void:
	match event_type:
		"birth":
			_animate_birth_effect(node, elapsed, t)
		"birthday":
			_animate_birthday_effect(node, elapsed, t)
		"marriage":
			_animate_marriage_effect(node, elapsed, t)
		"death":
			_animate_death_effect(node, elapsed, t)


func _animate_birth_effect(node: Node3D, elapsed: float, t: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var angle_offset: float = float(child.get_index()) * 0.8
			child.position.y = 0.6 + sin(elapsed * 2.0 + angle_offset) * 0.15
			var scale_val: float = 1.0 + sin(elapsed * 1.5 + angle_offset * 0.5) * 0.2
			child.scale = Vector3.ONE * scale_val


func _animate_birthday_effect(node: Node3D, elapsed: float, t: float) -> void:
	node.scale = Vector3.ONE * (1.0 + sin(elapsed * 3.0) * 0.3)


func _animate_marriage_effect(node: Node3D, elapsed: float, t: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.position.y = 0.8 + sin(elapsed * 2.5 + float(child.get_index())) * 0.2


func _animate_death_effect(node: Node3D, elapsed: float, t: float) -> void:
	var fade: float = 1.0 - t
	node.scale = Vector3.ONE * lerpf(1.0, 0.2, t)
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.material_override != null and mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
			mat.albedo_color.a = fade
			mat.emission_enabled = fade > 0.01


func _create_event_caption(root: Node3D, event_type: String, event: Dictionary) -> Node3D:
	var caption := Label3D.new()
	caption.text = _event_caption_for_type(event_type)
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.pixel_size = 0.008
	caption.modulate = _event_caption_color(event_type)
	caption.position = Vector3(0.0, 1.8, 0.0)
	root.add_child(caption)
	return caption


func _event_caption_for_type(event_type: String) -> String:
	match event_type:
		"birth":
			return "🎈 Birth!"
		"birthday":
			return "★ Birthday!"
		"marriage":
			return "✿ Married!"
		"death":
			return "✧ Passed away"
		_:
			return ""


func _event_caption_color(event_type: String) -> Color:
	match event_type:
		"birth":
			return Color(0.95, 0.80, 0.55)
		"birthday":
			return Color(0.90, 0.85, 0.50)
		"marriage":
			return Color(0.95, 0.75, 0.80)
		"death":
			return Color(0.65, 0.65, 0.70)
		_:
			return Color.WHITE


func _event_type_color(event_type: String) -> Color:
	match event_type:
		"birth":
			return Color(0.95, 0.80, 0.55)
		"birthday":
			return Color(0.90, 0.85, 0.50)
		"marriage":
			return Color(0.95, 0.70, 0.80)
		"death":
			return Color(0.55, 0.55, 0.65)
		_:
			return Color(0.80, 0.80, 0.85)


func _make_glow_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


var _sphere_cache: Dictionary = {}

func _cached_sphere(radius: float) -> SphereMesh:
	var key: String = "sph_%.3f" % radius
	if _sphere_cache.has(key):
		return _sphere_cache[key] as SphereMesh
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_sphere_cache[key] = mesh
	return mesh
