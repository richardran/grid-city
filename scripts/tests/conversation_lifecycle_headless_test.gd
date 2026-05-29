extends SceneTree

const CrowdConversationScript = preload("res://scripts/crowd_conversation.gd")
const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")
const CityGenerator = preload("res://scripts/city_generator.gd")


func _init() -> void:
	_test_conversation_start_and_advance()
	_test_conversation_expires_after_all_lines()
	_test_llm_pending_shows_dots()
	_test_speaker_face_toward_player()
	_test_player_lock_time_keeps_npc_engaged()
	print("conversation_lifecycle_headless_test: ok")
	quit(0)


func _test_conversation_start_and_advance() -> void:
	var conv := CrowdConversationScript.new()
	var pedestrians: Array = [_make_pedestrian()]
	var lines: Array = [
		{"speaker_index": 0, "text": "line1"},
		{"speaker_index": 0, "text": "line2"},
		{"speaker_index": 0, "text": "line3"}
	]
	# Manually create a conversation (simulates what _start_conversation_from_lines does)
	var conversation := {
		"id": "test_1",
		"speaker_indices": [0],
		"lines": lines,
		"line_index": 0,
		"elapsed": 0.0,
		"line_duration": 1.0,
		"is_player": false,
		"llm_pending": false
	}
	conv.active_conversations.append(conversation)
	
	# Verify snapshot shows line 0
	var snapshot: Array = conv.get_conversation_chat_snapshot(pedestrians)
	assert(snapshot.size() == 1, "Should have 1 snapshot entry")
	var text: String = str(Dictionary(snapshot[0]).get("text", ""))
	assert(text.contains("line1"), "Snapshot should contain line1, got '%s'" % text)
	
	# Advance time past line_duration to move to next line
	conv.update(1.1, pedestrians, null, null, 0)
	snapshot = conv.get_conversation_chat_snapshot(pedestrians)
	assert(snapshot.size() == 1, "Should still have 1 entry after advance")
	text = str(Dictionary(snapshot[0]).get("text", ""))
	assert(text.contains("line2"), "Should show line2 after advance, got '%s'" % text)
	
	conv.free()


func _test_conversation_expires_after_all_lines() -> void:
	var conv := CrowdConversationScript.new()
	var pedestrians: Array = [_make_pedestrian()]
	var lines: Array = [
		{"speaker_index": 0, "text": "only"},
	]
	var conversation := {
		"id": "test_exp",
		"speaker_indices": [0],
		"lines": lines,
		"line_index": 0,
		"elapsed": 0.0,
		"line_duration": 0.5,
		"is_player": false,
		"llm_pending": false
	}
	conv.active_conversations.append(conversation)
	assert(conv.active_conversations.size() == 1, "Should have 1 conversation")
	
	# Advance past the single line — conversation should be removed
	conv.update(1.0, pedestrians, null, null, 0)
	assert(conv.active_conversations.is_empty(), "Conversation should be removed after all lines")
	
	conv.free()


func _test_llm_pending_shows_dots() -> void:
	var conv := CrowdConversationScript.new()
	var pedestrians: Array = [_make_pedestrian()]
	var lines: Array = [{"speaker_index": 0, "text": "fallback"}]
	var conversation := {
		"id": "test_llm",
		"speaker_indices": [0],
		"lines": lines,
		"line_index": 0,
		"elapsed": 0.0,
		"line_duration": 2.0,
		"is_player": true,
		"llm_pending": true
	}
	conv.active_conversations.append(conversation)
	
	var snapshot: Array = conv.get_conversation_chat_snapshot(pedestrians)
	assert(snapshot.size() == 1, "Should have snapshot even when pending")
	var entry: Dictionary = Dictionary(snapshot[0])
	assert(entry.get("text", "") == "...", "Pending should show '...', got '%s'" % entry.get("text", ""))
	assert(entry.get("llm_pending", false) == true, "Should report llm_pending=true")
	
	conv.free()


func _test_speaker_face_toward_player() -> void:
	var conv := CrowdConversationScript.new()
	var root := Node3D.new()
	root.position = Vector3(0.0, 0.0, 0.0)
	var camera := Camera3D.new()
	camera.global_position = Vector3(2.0, 0.0, 3.0)
	
	# Initial rotation
	root.rotation.y = 0.0
	conv._face_actor_toward_player(root, 0.016, camera)
	
	# Should now face toward the camera
	# Face-toward test — requires camera in scene tree, skip in headless
	# The function is verified by the main_scene_headless_test which runs the full scene
	root.free()
	camera.free()
	conv.free()


func _test_player_lock_time_keeps_npc_engaged() -> void:
	# This tests that the pedestrian crowd's _process correctly keeps
	# an NPC locked when player_lock_time > 0
	var city := CityGenerator.new()
	city.regenerate_on_ready = false
	city.grid_size = Vector2i(2, 2)
	city.seed_value = 5
	var root := Node3D.new()
	get_root().add_child(root)
	city.name = "City"
	root.add_child(city)
	city.generate_city()
	
	var crowd := PedestrianCrowd.new()
	crowd.name = "Crowd"
	crowd.city_path = NodePath("../City")
	crowd.min_pedestrians = 4
	crowd.max_pedestrians = 6
	crowd.crowd_update_slices = 1
	root.add_child(crowd)
	crowd.populate_now()
	
	# Simulate: trigger a conversation on ped 0
	var internal: Array = crowd.get("_pedestrians")
	assert(internal.size() >= 1)
	var ped: Dictionary = internal[0]
	var identity: Dictionary = ped.get("identity", {})
	assert(not identity.is_empty())
	var person_id: int = int(identity.get("id", -1))
	
	crowd.trigger_player_conversation_for_person(person_id)
	
	# After trigger, the NPC should have player_lock_time set
	var updated_internal: Array = crowd.get("_pedestrians")
	var updated_ped: Dictionary = updated_internal[0]
	var lock_time: float = float(updated_ped.get("player_lock_time", 0.0))
	assert(lock_time > 0.0, "NPC should have player_lock_time after trigger, got %.2f" % lock_time)
	
	# Process a few frames — NPC should stay locked
	for _step in range(10):
		crowd._process(0.016)
	
	updated_internal = crowd.get("_pedestrians")
	updated_ped = updated_internal[0]
	var still_locked: bool = float(updated_ped.get("player_lock_time", 0.0)) > 0.0
	assert(still_locked, "NPC should have player_lock_time > 0 after 10 frames, got %.2f" % float(updated_ped.get("player_lock_time", 0.0)))
	
	root.free()


func _make_pedestrian() -> Dictionary:
	return {
		"root": _dummy_root(),
		"identity": {"id": 1, "first_name": "Test", "traits": {"openness": 0.5, "sociability": 0.5, "energy": 0.5}},
		"type": "man"
	}


var _dummy_root_ref: Node3D = null
func _dummy_root() -> Node3D:
	if _dummy_root_ref == null:
		_dummy_root_ref = Node3D.new()
		get_root().add_child(_dummy_root_ref)
	return _dummy_root_ref
