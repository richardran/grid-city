extends SceneTree

## Visual test: analyzes scene state without rendering.
## Logs building heights, pedestrian visuals, conversation system.
## Usage: godot --headless --script scripts/tools/visual_test.gd

const CityGenerator = preload("res://scripts/city_generator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")

var _report: String = ""


func _init() -> void:
	_report = ""
	log_msg("=== VISUAL TEST START ===")

	var root := Node3D.new()
	root.name = "TestRoot"
	get_root().add_child(root)

	# Generate city
	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(8, 8)
	city.seed_value = 42
	city.name = "City"
	root.add_child(city)
	var t0 := Time.get_ticks_usec()
	city.generate_city()
	log_msg("City gen: %.0fms" % [(Time.get_ticks_usec() - t0) / 1000.0])

	# Spawn crowd
	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.min_pedestrians = 40
	crowd.max_pedestrians = 60
	crowd.crowd_update_slices = 1
	root.add_child(crowd)
	crowd.populate_now()
	log_msg("Pedestrians: %d" % crowd.get_pedestrian_count())
	log_snapshot("after_gen", crowd, root)

	# --- Analyze buildings ---
	log_msg("\n=== BUILDINGS ===")
	var all_meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, all_meshes)
	log_msg("Total MeshInstance3D: %d" % all_meshes.size())

	# Find heights
	var building_heights: Array[float] = []
	var unshaded_count: int = 0
	for mi in all_meshes:
		if mi.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
			if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				unshaded_count += 1
		if mi.mesh is BoxMesh:
			var box: BoxMesh = mi.mesh as BoxMesh
			if box.size.y > 1.0 and box.size.y < 100.0:
				building_heights.append(box.size.y)

	building_heights.sort()
	if building_heights.size() > 0:
		var total: float = 0.0
		for h in building_heights:
			total += h
		var avg: float = total / float(building_heights.size())
		log_msg("Building-like meshes >1m tall: %d" % building_heights.size())
		log_msg("Avg height: %.1fm" % avg)
		log_msg("Tallest 10: %s" % str(building_heights.slice(maxi(0, building_heights.size()-10))))
		log_msg("Shortest 10: %s" % str(building_heights.slice(0, mini(10, building_heights.size()))))
		# Verify no buildings exceed 5 stories (5*2.6=13m + 1.4m basement = ~14.4m)
		var too_tall: int = 0
		for h in building_heights:
			if h > 15.0:
				too_tall += 1
		if too_tall > 0:
			log_msg("WARNING: %d meshes taller than 15m (exceeds 5 stories)" % too_tall)
		else:
			log_msg("OK: No buildings exceed 5-story height")

	log_msg("Unshaded materials: %d / %d" % [unshaded_count, all_meshes.size()])

	# --- Analyze pedestrians ---
	log_msg("\n=== PEDESTRIANS ===")
	var peds: Array = crowd.get("_pedestrians")
	log_msg("Total pedestrians: %d" % peds.size())

	var has_glb: bool = false
	var cap_body: int = 0
	var sphere_head: int = 0
	for i in range(mini(peds.size(), 20)):
		var ped: Dictionary = peds[i]
		var ped_type: String = str(ped.get("type", "?"))
		var visual: Node3D = ped.get("visual") as Node3D
		if visual == null:
			continue
		for child in visual.get_children():
			if child is MeshInstance3D:
				var mi: MeshInstance3D = child as MeshInstance3D
				if mi.mesh is CapsuleMesh:
					cap_body += 1
				elif mi.mesh is SphereMesh:
					sphere_head += 1

	log_msg("Capsule bodies: %d  Sphere heads: %d" % [cap_body, sphere_head])
	if cap_body > 0 and sphere_head > 0:
		log_msg("OK: Pedestrians use capsule+sphere (no GLB)")
	elif cap_body > 0:
		log_msg("OK: Pedestrians use capsule only")
	else:
		log_msg("WARNING: No pedestrian meshes found!")

	# --- Check conversation system ---
	log_msg("\n=== CONVERSATIONS ===")
	if crowd.has_method("trigger_player_conversation_for_pedestrian"):
		var started: bool = crowd.call("trigger_player_conversation_for_pedestrian", 0)
		log_msg("Trigger conversation on ped 0: %s" % ["ok" if started else "FAILED"])
		for f in range(60):
			crowd._process(0.016)
		if crowd.has_method("get_conversation_chat_snapshot"):
			var snap: Array = crowd.call("get_conversation_chat_snapshot")
			log_msg("Chat snapshot: %d entries" % snap.size())
			for entry in snap:
				var text: String = str(entry.get("text", "(no text)"))
				log_msg("  Bubble text: '%s'" % text)
				if text == "" or text == "...":
					log_msg("  WARNING: Empty or pending text")
	else:
		log_msg("WARNING: No trigger_player_conversation_for_pedestrian method")

	# --- Summary ---
	log_msg("\n=== SUMMARY ===")
	var total_meshes: int = 0
	var total_nodes: int = 0
	var min_y: float = INF
	var max_y: float = -INF
	_scan(root, total_meshes, total_nodes, min_y, max_y)
	log_msg("MeshInstance3D: %d" % total_meshes)
	log_msg("Total nodes: %d" % total_nodes)
	log_msg("Height range: %.1f to %.1f" % [min_y, max_y])
	if max_y > 15.0:
		log_msg("WARNING: Object at %.1f is sky-high" % max_y)
	else:
		log_msg("OK: No objects above 15m")

	log_msg("\n=== END ===")
	var path: String = "user://test_report.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(_report)
		f.close()
	print("Report: " + path)
	quit()


func log_msg(msg: String) -> void:
	_report += msg + "\n"
	print(msg)


func log_snapshot(label: String, crowd: Node, root: Node) -> void:
	log_msg("[%s] peds=%d" % [label, crowd.get_pedestrian_count()])


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _scan(node: Node, meshes: int, nodes: int, min_y: float, max_y: float) -> void:
	nodes += 1
	if node is MeshInstance3D:
		meshes += 1
		var mi: MeshInstance3D = node as MeshInstance3D
		var y: float = mi.global_position.y
		if y < min_y: min_y = y
		if y > max_y: max_y = y
		if mi.mesh is BoxMesh:
			var box: BoxMesh = mi.mesh as BoxMesh
			# For box meshes, top = pos.y + height/2
			var top: float = mi.global_position.y + box.size.y * 0.5
			if top > max_y: max_y = top
	for child in node.get_children():
		_scan(child, meshes, nodes, min_y, max_y)
