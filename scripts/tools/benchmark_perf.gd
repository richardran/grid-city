extends SceneTree

## Automated benchmark: single-pass simulation, logs performance.
## Usage: godot --headless --script scripts/tools/benchmark_perf.gd

const CityGenerator = preload("res://scripts/city_generator.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")


func _init() -> void:
	print("=== BENCHMARK START ===")
	var t_start: int = Time.get_ticks_usec()

	# --- Generation phase ---
	var root := Node3D.new()
	root.name = "BenchRoot"
	get_root().add_child(root)

	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(8, 8)
	city.seed_value = 42
	city.name = "City"
	root.add_child(city)

	var t0 := Time.get_ticks_usec()
	city.generate_city()
	var gen_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	print("City gen: %.0fms" % gen_ms)

	# --- Spawn pedestrians ---
	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.min_pedestrians = 40
	crowd.max_pedestrians = 60
	crowd.crowd_update_slices = 1
	root.add_child(crowd)

	t0 = Time.get_ticks_usec()
	crowd.populate_now()
	var pop_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	print("Populate: %.0fms" % pop_ms)

	var ped_count: int = crowd.get_pedestrian_count()
	print("Pedestrians: %d" % ped_count)

	# --- Snapshot ---
	_snapshot("after_gen", root, crowd)

	# --- Simulate N frames in each view ---
	var views: Array[Dictionary] = [
		{"name": "idle_ground", "pos": Vector3(0, 2, -8)},
		{"name": "overlook", "pos": Vector3(0, 20, -8)},
		{"name": "click_convo", "pos": Vector3(2, 2, -8)},
		{"name": "busy_corner", "pos": Vector3(20, 2, 12)},
	]
	var frame_count: int = 120

	for view in views:
		var cam := Camera3D.new()
		cam.current = true
		cam.position = view["pos"]
		cam.look_at(Vector3(0, 0, 0))
		root.add_child(cam)
		crowd.set("_camera", cam)

		# Simulate frames
		t0 = Time.get_ticks_usec()
		for f in range(frame_count):
			if f == 60 and view["name"] == "click_convo":
				# Click a pedestrian mid-way through
				var peds: Array = crowd.get("_pedestrians")
				if peds.size() > 0 and crowd.has_method("trigger_player_conversation_for_pedestrian"):
					crowd.call("trigger_player_conversation_for_pedestrian", 0)
			crowd._process(0.016)
		var avg_ms: float = (Time.get_ticks_usec() - t0) / 1000.0 / float(frame_count)
		print("View %s: %.2fms/frame" % [view["name"], avg_ms])
		_snapshot(view["name"], root, crowd)
		cam.queue_free()

	# --- Final report ---
	var total_s: float = (Time.get_ticks_usec() - t_start) / 1000000.0
	print("\n=== BENCHMARK RESULT ===")
	print("Total: %.1fs" % total_s)
	quit()


func _snapshot(label: String, root: Node, crowd: Node) -> void:
	var nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var resources: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var mem: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var peds: int = crowd.get_pedestrian_count()
	var meshes: int = _count_meshes(root)
	print("  [%s] nodes=%d res=%d mem=%.0fMB peds=%d meshes=%d" % [label, nodes, resources, mem, peds, meshes])


func _count_meshes(node: Node) -> int:
	var c: int = 0
	if node is MeshInstance3D:
		c += 1
	for child in node.get_children():
		c += _count_meshes(child)
	return c
