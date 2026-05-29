extends Node
class_name CrowdConversation

## Manages NPC conversation state, dialogue generation, and OpenRouter LLM integration.
## Attached as a child of PedestrianCrowd. Uses the crowd's pedestrian array directly.

var crowd: Node  # Reference to PedestrianCrowd parent

## Conversation state
var active_conversations: Array = []
var next_conversation_delay: float = 1.2
var player_conversation_delay: float = 0.9

## OpenRouter state
var openrouter_api_key: String = ""
var openrouter_request_in_flight: bool = false
var openrouter_request: HTTPRequest

## Exported config — synced from crowd via _receive_config()
var enable_llm_conversations: bool = true
var openrouter_model: String = "openai/gpt-4.1-mini"
var openrouter_max_tokens: int = 320
var openrouter_timeout_seconds: float = 10.0
var conversation_share: float = 0.58
var conversation_radius: float = 4.6
var conversation_line_duration: float = 2.2
var player_conversation_share: float = 0.7
var player_conversation_radius: float = 7.5
var player_conversation_cooldown: float = 3.6

const OPENROUTER_ENV_KEY := "OPENROUTER_API_KEY"
const OPENROUTER_CHAT_URL := "https://openrouter.ai/api/v1/chat/completions"


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	openrouter_api_key = OS.get_environment(OPENROUTER_ENV_KEY).strip_edges()
	if enable_llm_conversations and crowd != null:
		openrouter_request = HTTPRequest.new()
		openrouter_request.name = "OpenRouterRequest"
		openrouter_request.timeout = openrouter_timeout_seconds
		openrouter_request.request_completed.connect(_on_openrouter_request_completed)
		add_child(openrouter_request)


func receive_config(config: Dictionary) -> void:
	enable_llm_conversations = bool(config.get("enable_llm_conversations", true))
	openrouter_model = str(config.get("openrouter_model", "openai/gpt-4.1-mini"))
	openrouter_max_tokens = int(config.get("openrouter_max_tokens", 320))
	openrouter_timeout_seconds = float(config.get("openrouter_timeout_seconds", 10.0))
	conversation_share = float(config.get("conversation_share", 0.58))
	conversation_radius = float(config.get("conversation_radius", 4.6))
	conversation_line_duration = float(config.get("conversation_line_duration", 2.2))
	player_conversation_share = float(config.get("player_conversation_share", 0.7))
	player_conversation_radius = float(config.get("player_conversation_radius", 7.5))
	player_conversation_cooldown = float(config.get("player_conversation_cooldown", 3.6))


func clear() -> void:
	active_conversations.clear()
	next_conversation_delay = 1.2
	player_conversation_delay = 0.9
	openrouter_request_in_flight = false


func get_conversation_chat_snapshot(pedestrians: Array, camera: Camera3D = null) -> Array:
	var snapshot: Array = []
	var by_speaker: Dictionary = {}
	var speaker_order: Array[int] = []
	# Player conversations first, then NPC
	var ordered_conversations: Array = []
	for conversation in active_conversations:
		if bool(conversation.get("is_player", false)):
			ordered_conversations.append(conversation)
	for conversation in active_conversations:
		if not bool(conversation.get("is_player", false)):
			ordered_conversations.append(conversation)
	for conversation in ordered_conversations:
		var line_index: int = int(conversation.get("line_index", 0))
		var lines: Array = conversation.get("lines", [])
		if line_index < 0 or line_index >= lines.size():
			continue
		var visible_lines: Array[String] = _visible_lines_for_conversation(conversation, line_index)
		if visible_lines.is_empty():
			continue
		var speaker_index: int = _speaker_index_for_conversation_line(conversation, line_index)
		if speaker_index < 0 or speaker_index >= pedestrians.size():
			continue
		var speaker: Dictionary = pedestrians[speaker_index]
		var root: Node3D = speaker.get("root") as Node3D
		if root == null or not is_instance_valid(root):
			continue
		# Skip if speaker is behind the camera — prevents ghost boxes
		if camera != null and camera.is_position_behind(root.global_position):
			continue
		var speaker_position: Vector3 = root.global_position if root.is_inside_tree() else root.position
		if not by_speaker.has(speaker_index):
			by_speaker[speaker_index] = {
				"conversation_id": str(conversation.get("id", "")),
				"speaker_index": speaker_index,
				"speaker_position": speaker_position + Vector3(0.0, 1.55, 0.0),
				"lines": [],
				"is_player": bool(conversation.get("is_player", false)),
				"llm_pending": bool(conversation.get("llm_pending", false))
			}
			speaker_order.append(speaker_index)
		var entry: Dictionary = Dictionary(by_speaker[speaker_index])
		if bool(conversation.get("is_player", false)):
			entry["is_player"] = true
		if bool(conversation.get("llm_pending", false)):
			entry["llm_pending"] = true
		var entry_lines: Array = Array(entry.get("lines", []))
		for visible_text in visible_lines:
			var clean: String = str(visible_text).strip_edges()
			if clean == "":
				continue
			entry_lines.append(clean)
			while entry_lines.size() > 3:
				entry_lines.remove_at(0)
		entry["lines"] = entry_lines
		entry["speaker_position"] = speaker_position + Vector3(0.0, 1.55, 0.0)
		by_speaker[speaker_index] = entry
	for speaker_index in speaker_order:
		var entry: Dictionary = Dictionary(by_speaker[speaker_index])
		var entry_lines: Array = Array(entry.get("lines", []))
		if entry_lines.is_empty():
			continue
		entry["text"] = "\n".join(_string_lines(entry_lines))
		snapshot.append(entry)
		if snapshot.size() >= 3:
			break
	return snapshot


func _speaker_index_for_conversation_line(conversation: Dictionary, line_index: int) -> int:
	var lines: Array = conversation.get("lines", [])
	if lines.is_empty():
		return -1
	var resolved_index: int = clampi(line_index, 0, lines.size() - 1)
	return int(Dictionary(lines[resolved_index]).get("speaker_index", -1))


func _visible_lines_for_conversation(conversation: Dictionary, line_index: int) -> Array[String]:
	if bool(conversation.get("llm_pending", false)) and bool(conversation.get("is_player", false)):
		return ["..."]
	var lines: Array = conversation.get("lines", [])
	var visible: Array[String] = []
	var start_index: int = maxi(0, line_index - 2)
	for index in range(start_index, mini(line_index + 1, lines.size())):
		var text: String = str(Dictionary(lines[index]).get("text", "")).strip_edges()
		if text != "":
			visible.append(text)
	return visible


func _string_lines(lines: Array) -> Array[String]:
	var result: Array[String] = []
	for line in lines:
		result.append(str(line))
	return result


func get_player_conversation_count() -> int:
	var count: int = 0
	for conversation in active_conversations:
		if bool(conversation.get("is_player", false)):
			count += 1
	return count


func is_ped_in_player_conversation(ped_index: int) -> bool:
	return _player_conversation_speaker_lookup().has(ped_index)


func update(delta: float, pedestrians: Array, camera: Camera3D, rng: RandomNumberGenerator, frame_counter: int) -> void:
	# Advance active conversations
	var conversation_candidates: Array = []
	var new_conversations: Array = []
	for conversation_index in range(active_conversations.size() - 1, -1, -1):
		var conversation: Dictionary = active_conversations[conversation_index]
		var elapsed: float = float(conversation.get("elapsed", 0.0)) + delta
		conversation["elapsed"] = elapsed
		var line_index: int = int(conversation.get("line_index", 0))
		var lines: Array = conversation.get("lines", [])
		var line_duration: float = float(conversation.get("line_duration", 2.2))
		if bool(conversation.get("llm_pending", false)):
			pass  # wait for LLM
		elif line_index < lines.size() and elapsed >= line_duration:
			line_index += 1
			conversation["line_index"] = line_index
			conversation["elapsed"] = 0.0
			if line_index >= lines.size():
				active_conversations.remove_at(conversation_index)
				continue
		if not bool(conversation.get("is_player", false)) and not bool(conversation.get("llm_pending", false)):
			for sid in conversation.get("speaker_indices", []):
				if sid >= 0 and sid < pedestrians.size():
					conversation_candidates.append(sid)
		active_conversations[conversation_index] = conversation

	# NPC-to-NPC conversation attempts
	next_conversation_delay = maxf(0.0, next_conversation_delay - delta)
	player_conversation_delay = maxf(0.0, player_conversation_delay - delta)

	if active_conversations.size() < 3 and next_conversation_delay <= 0.0:
		var pair: Array = _find_conversation_pair(pedestrians, frame_counter)
		if not pair.is_empty():
			_start_conversation_from_lines(pair[0], pedestrians[pair[0]], pair[1], pedestrians[pair[1]], _conversation_lines_for_pair(pair[0], pedestrians[pair[0]], pair[1], pedestrians[pair[1]]), conversation_line_duration, false, false, pedestrians)
			next_conversation_delay = rng.randf_range(2.5, 6.5)
		else:
			next_conversation_delay = 0.8

	# Player conversation attempts
	if active_conversations.size() < 3 and player_conversation_delay <= 0.0 and camera != null:
		var player_candidate_index: int = _find_player_conversation_candidate(pedestrians, camera, frame_counter)
		if player_candidate_index >= 0:
			_start_player_conversation(player_candidate_index, false, pedestrians)
			player_conversation_delay = rng.randf_range(player_conversation_cooldown * 0.8, player_conversation_cooldown * 1.35)

	# Clean up stale conversations
	for conversation_index in range(active_conversations.size() - 1, -1, -1):
		var conversation: Dictionary = active_conversations[conversation_index]
		var elapsed: float = float(conversation.get("elapsed", 0.0))
		if elapsed > 30.0:
			active_conversations.remove_at(conversation_index)


func trigger_player_conversation_for_person(person_id: int, pedestrians: Array) -> bool:
	for ped_index in range(pedestrians.size()):
		var identity: Dictionary = pedestrians[ped_index].get("identity", {})
		if int(identity.get("id", -1)) == person_id:
			_start_player_conversation(ped_index, true, pedestrians)
			player_conversation_delay = _rng.randf_range(player_conversation_cooldown * 0.9, player_conversation_cooldown * 1.2)
			return true
	return false


func _find_conversation_pair(pedestrians: Array, frame_counter: int) -> Array:
	var candidates: Array = []
	for index_a in range(pedestrians.size()):
		var ped_a: Dictionary = pedestrians[index_a]
		if float(ped_a.get("speech_cooldown", 0.0)) > 0.0:
			continue
		var mode_a: String = str(ped_a.get("mode", "wander"))
		if not _mode_supports_conversation(mode_a):
			continue
		var pos_a: Vector3 = ped_a.get("root", {}).position if ped_a.get("root") != null else Vector3.ZERO
		for index_b in range(index_a + 1, pedestrians.size()):
			var ped_b: Dictionary = pedestrians[index_b]
			if float(ped_b.get("speech_cooldown", 0.0)) > 0.0:
				continue
			var mode_b: String = str(ped_b.get("mode", "wander"))
			if not _mode_supports_conversation(mode_b):
				continue
			var pos_b: Vector3 = ped_b.get("root", {}).position if ped_b.get("root") != null else Vector3.ZERO
			if pos_a.distance_to(pos_b) < conversation_radius:
				var combined_seed: int = index_a * 1000 + index_b + frame_counter
				if combined_seed % 10 < int(conversation_share * 10.0):
					return [index_a, index_b]
	return []


func _find_player_conversation_candidate(pedestrians: Array, camera: Camera3D, frame_counter: int) -> int:
	if camera == null:
		return -1
	var camera_pos: Vector3 = camera.global_position
	var candidates: Array = []
	for index in range(pedestrians.size()):
		var ped: Dictionary = pedestrians[index]
		if float(ped.get("speech_cooldown", 0.0)) > 0.0:
			continue
		var is_player: bool = _player_conversation_speaker_lookup().has(index)
		if is_player:
			continue
		var mode: String = str(ped.get("mode", "wander"))
		if not _mode_supports_conversation(mode):
			continue
		var root: Node3D = ped.get("root") as Node3D
		if root == null:
			continue
		var distance: float = root.global_position.distance_to(camera_pos)
		if distance < player_conversation_radius:
			candidates.append({"index": index, "distance": distance})
	if candidates.is_empty():
		return -1
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", INF)) < float(b.get("distance", INF))
	)
	return int(candidates[0].get("index", -1))


func _start_player_conversation(ped_index: int, use_llm: bool = false, pedestrians: Array = []) -> void:
	if ped_index < 0 or ped_index >= pedestrians.size():
		return
	var ped: Dictionary = pedestrians[ped_index]
	var lines: Array = _conversation_lines_for_player(ped_index, ped)
	_start_conversation_from_lines(ped_index, ped, -1, {}, lines, conversation_line_duration, true, use_llm, pedestrians)


func _start_conversation_from_lines(index_a: int, ped_a: Dictionary, index_b: int, ped_b: Dictionary, lines: Array, line_duration: float, is_player_conversation: bool, use_llm: bool = false, pedestrians: Array = []) -> void:
	if lines.is_empty():
		return
	var speakers: Array = [index_a]
	if index_b >= 0:
		speakers.append(index_b)
	# Sociability trait affects how long conversations last
	var identity_a: Dictionary = ped_a.get("identity", {})
	var traits_a: Dictionary = identity_a.get("traits", {})
	var sociability: float = float(traits_a.get("sociability", 0.5))
	var adjusted_duration: float = line_duration * lerpf(0.6, 1.6, sociability)
	var conversation := {
		"id": "conversation_%02d" % (active_conversations.size() + 1 + randi() % 97),
		"speaker_indices": speakers,
		"lines": lines,
		"line_index": 0,
		"elapsed": 0.0,
		"line_duration": adjusted_duration,
		"is_player": is_player_conversation,
		"llm_pending": false
	}
	active_conversations.append(conversation)
	# Player conversations: NPC stops for 30s (until convo ends)
	# Also mark as solo so social groups don't override the pause
	if is_player_conversation:
		ped_a["pause_time"] = maxf(float(ped_a.get("pause_time", 0.0)), 30.0)
		ped_a["group_role"] = "solo"
	else:
		ped_a["pause_time"] = maxf(float(ped_a.get("pause_time", 0.0)), line_duration * 0.75)
	ped_a["speech_cooldown"] = maxf(float(ped_a.get("speech_cooldown", 0.0)), 10.0 if not is_player_conversation else player_conversation_cooldown)
	if index_a >= 0 and index_a < pedestrians.size():
		pedestrians[index_a] = ped_a
	if index_b >= 0:
		if is_player_conversation:
			ped_b["pause_time"] = maxf(float(ped_b.get("pause_time", 0.0)), 30.0)
			ped_b["group_role"] = "solo"
		else:
			ped_b["pause_time"] = maxf(float(ped_b.get("pause_time", 0.0)), line_duration * 0.75)
		ped_b["speech_cooldown"] = maxf(float(ped_b.get("speech_cooldown", 0.0)), 10.0)
		if index_b < pedestrians.size():
			pedestrians[index_b] = ped_b
	if is_player_conversation and use_llm:
		var started_request: bool = _request_openrouter_player_lines(index_a, ped_a)
		if started_request:
			conversation["llm_pending"] = true
			active_conversations[active_conversations.size() - 1] = conversation


func _conversation_lines_for_pair(index_a: int, ped_a: Dictionary, index_b: int, ped_b: Dictionary) -> Array:
	var identity_a: Dictionary = ped_a.get("identity", {})
	var identity_b: Dictionary = ped_b.get("identity", {})
	var name_b: String = str(identity_b.get("first_name", identity_b.get("full_name", "Friend"))).split(" ")[0]
	var mode: String = str(ped_a.get("mode", ped_b.get("mode", "wander")))
	var lines: Array[String] = []
	match mode:
		"coffee":
			lines = [
				"Want to grab a coffee, %s?" % name_b,
				"Yeah, let's take the corner table.",
				"I heard the square is lively tonight."
			]
		"shopping", "market", "errand":
			lines = [
				"I'm heading past the shops—coming?",
				"Sure, I need one more thing anyway.",
				"Let's check the bakery before it closes."
			]
		"event_visit":
			lines = [
				"Looks like something's happening over there.",
				"Let's stay a minute and watch.",
				"Everyone from the square is drifting over."
			]
		"plaza", "evening_stroll":
			lines = [
				"Nice evening for a walk, huh?",
				"Yeah—let's loop through the square.",
				"Maybe we can stop by the café after."
			]
		_:
			lines = [
				"Hey %s, where are you headed?" % name_b,
				"Just wandering for a bit.",
				"Come with me—there's more going on by the plaza."
			]
	return _sequence_lines(lines, index_a, index_b)


func _conversation_lines_for_player(index_a: int, ped_a: Dictionary) -> Array:
	var identity: Dictionary = ped_a.get("identity", {})
	var first_name: String = str(identity.get("first_name", identity.get("full_name", "Neighbor"))).split(" ")[0]
	var mode: String = str(ped_a.get("mode", "wander"))
	var lines: Array[String] = []
	match mode:
		"coffee":
			lines = [
				"Hey—want to check out the café?",
				"They've actually got open tables right now.",
				"I'm %s, by the way." % first_name
			]
		"shopping", "market", "errand":
			lines = [
				"You made it just before the stalls close.",
				"Best bread stand is halfway down this block.",
				"If you're browsing, it's a good day for it."
			]
		"event_visit":
			lines = [
				"You here for the little crowd gathering too?",
				"Something interesting always starts in the square.",
				"Feels like the whole block noticed."
			]
		"plaza", "evening_stroll":
			lines = [
				"Nice timing—this street's best around now.",
				"If you keep going, the plaza opens up ahead.",
				"People tend to linger there when it's lively."
			]
		_:
			lines = [
				"Hey there.",
				"You look new to this stretch of town.",
				"The plaza's the busiest spot if you're looking for something happening."
			]
	return _sequence_lines(lines, index_a, -1)


static func _sequence_lines(lines: Array[String], index_a: int, index_b: int) -> Array:
	var sequence: Array = []
	for line_index in range(lines.size()):
		var speaker_index: int = index_a
		if index_b >= 0 and line_index % 2 == 1:
			speaker_index = index_b
		sequence.append({
			"speaker_index": speaker_index,
			"text": lines[line_index]
		})
	return sequence


static func _mode_supports_conversation(mode: String) -> bool:
	return ["wander", "plaza", "coffee", "shopping", "market", "errand", "evening_stroll", "event_visit"].has(mode)


func _request_openrouter_player_lines(ped_index: int, ped: Dictionary) -> bool:
	if not enable_llm_conversations or openrouter_request == null or openrouter_request_in_flight:
		return false
	if openrouter_api_key == "":
		push_warning("OpenRouter conversation generation skipped: %s missing" % OPENROUTER_ENV_KEY)
		return false
		
	var identity: Dictionary = ped.get("identity", {})
	var prompt: String = "Write exactly 3 short lines of ambient NPC dialogue spoken by one city pedestrian to a nearby player in a simulation game. Keep each line under 70 characters. Tone: natural, brief, street-level, no meta commentary. Mode: %s. Speaker name: %s. Return exactly 3 plain text lines, one line per line, with no numbering, no bullets, no JSON, and no markdown." % [
		str(ped.get("mode", "wander")),
		str(identity.get("first_name", identity.get("full_name", "Neighbor")))
	]
	var payload := {
		"model": openrouter_model,
		"messages": [
			{
				"role": "system",
				"content": "You write short NPC barks for a city sim. Output only the dialogue lines, nothing else."
			},
			{
				"role": "user",
				"content": prompt
			}
		],
		"temperature": 0.9,
		"max_tokens": openrouter_max_tokens
	}
	var headers := [
		"Authorization: Bearer %s" % openrouter_api_key,
		"Content-Type: application/json",
		"HTTP-Referer: https://openclaw.local/godot-city-grid",
		"X-Title: godot-city-grid"
	]
	openrouter_request_in_flight = true
	openrouter_request.set_meta("conversation_ped_index", ped_index)
	print("OpenRouter conversation request -> ped %d model %s" % [ped_index, openrouter_model])
	var err: int = openrouter_request.request(
		OPENROUTER_CHAT_URL,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		openrouter_request_in_flight = false
		push_warning("OpenRouter conversation request failed to start: %s" % err)
		return false
	return true


func _on_openrouter_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	openrouter_request_in_flight = false
	print("OpenRouter conversation response -> result %d status %d" % [result, response_code])
	var ped_index: int = int(openrouter_request.get_meta("conversation_ped_index", -1))
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_finalize_openrouter_player_lines(ped_index, [], "http_error")
		push_warning("OpenRouter conversation response failed: result=%d status=%d body=%s" % [result, response_code, body.get_string_from_utf8().left(240)])
		return
	if ped_index < 0:
		print("OpenRouter generated -> ped %d: ZERO_MSG (ped gone)" % ped_index)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_finalize_openrouter_player_lines(ped_index, [], "bad_body")
		push_warning("OpenRouter conversation response was not a dictionary: %s" % body.get_string_from_utf8().left(240))
		return
	var choices: Array = Dictionary(parsed).get("choices", [])
	if choices.is_empty():
		_finalize_openrouter_player_lines(ped_index, [], "no_choices")
		push_warning("OpenRouter conversation response had no choices")
		return
	var choice: Dictionary = Dictionary(choices[0])
	var message: Dictionary = Dictionary(choice.get("message", {}))
	var finish_reason: String = str(choice.get("finish_reason", ""))
	var content_preview: String = _extract_choice_text(choice)
	var lines: Array[String] = _extract_generated_lines_from_choice(choice)
	if lines.is_empty():
		var empty_status: String = "length_exhausted" if finish_reason == "length" else "zero_msg"
		_finalize_openrouter_player_lines(ped_index, [], empty_status)
		push_warning("OpenRouter raw content preview: %s" % content_preview.left(240))
		push_warning("OpenRouter choice preview: %s" % JSON.stringify({
			"finish_reason": finish_reason,
			"message": message,
			"text": choice.get("text", null)
		}).left(320))
		if finish_reason == "length":
			push_warning("OpenRouter hit max_tokens before producing visible dialogue; using local fallback lines")
		else:
			push_warning("OpenRouter conversation content was not parseable as lines")
		return
	_finalize_openrouter_player_lines(ped_index, lines, "ok")


func _finalize_openrouter_player_lines(ped_index: int, lines: Array[String], status: String) -> void:
	if lines.is_empty():
		print("OpenRouter generated -> ped %d: ZERO_MSG (%s)" % [ped_index, status])
	else:
		print("OpenRouter generated -> ped %d: %s" % [ped_index, _join_log_lines(lines)])
	for conversation_index in range(active_conversations.size() - 1, -1, -1):
		var conversation: Dictionary = active_conversations[conversation_index]
		if not bool(conversation.get("is_player", false)):
			continue
		var speakers: Array = conversation.get("speaker_indices", [])
		if speakers.is_empty() or int(speakers[0]) != ped_index:
			continue
		conversation["llm_pending"] = false
		if not lines.is_empty():
			conversation["lines"] = _sequence_lines(lines, ped_index, -1)
			conversation["line_index"] = 0
			conversation["elapsed"] = 0.0
		active_conversations[conversation_index] = conversation
		break


func _player_conversation_speaker_lookup() -> Dictionary:
	var lookup: Dictionary = {}
	for conversation in active_conversations:
		if bool(conversation.get("is_player", false)):
			var speakers: Array = conversation.get("speaker_indices", [])
			for sid in speakers:
				lookup[sid] = true
	return lookup


func _face_actor_toward_player(root: Node3D, delta: float, camera: Camera3D) -> void:
	if root == null or camera == null:
		return
	var camera_pos: Vector3 = camera.global_position
	var toward := Vector3(camera_pos.x - root.position.x, 0.0, camera_pos.z - root.position.z)
	if toward.length() < 0.01:
		return
	var target_angle: float = atan2(toward.x, toward.z)
	root.rotation.y = target_angle + deg_to_rad(180.0)


static func _join_log_lines(lines: Array[String]) -> String:
	var combined: String = ""
	for index in range(lines.size()):
		if index > 0:
			combined += " | "
		combined += str(lines[index])
	return combined


static func _extract_generated_lines_from_choice(choice: Dictionary) -> Array[String]:
	var message: Dictionary = Dictionary(choice.get("message", {}))
	var content_text: String = _extract_choice_text(choice).strip_edges()
	if content_text == "":
		return []
	var generated: Variant = null
	var json_candidate: String = _extract_json_array_candidate(content_text)
	if json_candidate != "":
		generated = JSON.parse_string(json_candidate)
	var lines: Array[String] = []
	if typeof(generated) == TYPE_ARRAY:
		for entry in generated:
			var text: String = str(entry).strip_edges()
			if text != "":
				lines.append(text)
			if lines.size() >= 3:
				return lines
	var refusal_value: Variant = message.get("refusal", false)
	if not message.is_empty() and typeof(refusal_value) == TYPE_BOOL and refusal_value:
		return []
	return _fallback_generated_lines(content_text)


static func _extract_choice_text(choice: Dictionary) -> String:
	var message: Dictionary = Dictionary(choice.get("message", {}))
	var content_text: String = _message_content_to_text(message.get("content", null)).strip_edges()
	if content_text != "":
		return content_text
	var text_text: String = _message_content_to_text(choice.get("text", null)).strip_edges()
	if text_text != "":
		return text_text
	return _message_content_to_text(message.get("reasoning", null)).strip_edges()


static func _message_content_to_text(content: Variant) -> String:
	match typeof(content):
		TYPE_NIL:
			return ""
		TYPE_STRING:
			return str(content)
		TYPE_ARRAY:
			var chunks: Array[String] = []
			for entry in content:
				if typeof(entry) == TYPE_NIL:
					continue
				if typeof(entry) == TYPE_DICTIONARY:
					var entry_dict: Dictionary = entry
					var text_value: Variant = entry_dict.get("text", entry_dict.get("content", ""))
					if typeof(text_value) == TYPE_NIL:
						continue
					if typeof(text_value) == TYPE_DICTIONARY:
						var nested: Variant = Dictionary(text_value).get("value", Dictionary(text_value).get("text", ""))
						if typeof(nested) != TYPE_NIL:
							chunks.append(str(nested).strip_edges())
					else:
						chunks.append(str(text_value).strip_edges())
				else:
					chunks.append(str(entry).strip_edges())
			return "\n".join(chunks).strip_edges()
		_:
			return "" if typeof(content) == TYPE_NIL else str(content)


static func _extract_json_array_candidate(content_text: String) -> String:
	var trimmed: String = content_text.strip_edges()
	if trimmed == "":
		return ""
	if trimmed.begins_with("```"):
		var lines: PackedStringArray = trimmed.split("\n")
		if lines.size() >= 3 and String(lines[lines.size() - 1]).strip_edges() == "```":
			lines.remove_at(0)
			lines.remove_at(lines.size() - 1)
			trimmed = "\n".join(lines).strip_edges()
	if trimmed.begins_with("[") and trimmed.ends_with("]"):
		return trimmed
	var start: int = trimmed.find("[")
	var ending: int = trimmed.rfind("]")
	if start >= 0 and ending > start:
		return trimmed.substr(start, ending - start + 1)
	return ""


static func _fallback_generated_lines(content_text: String) -> Array[String]:
	var cleaned: String = content_text.replace("```json", "").replace("```", "").strip_edges()
	var lines: Array[String] = []
	for raw_line in cleaned.split("\n"):
		var line: String = String(raw_line).strip_edges()
		if line == "":
			continue
		line = line.trim_prefix("- ")
		line = line.trim_prefix("* ")
		if line.length() >= 3 and line[0].is_valid_int() and [".", ")", ":", "-"].has(line.substr(1, 1)):
			line = line.substr(2).strip_edges()
		if line.length() < 3:
			continue
		lines.append(line)
		if lines.size() >= 3:
			break
	return lines
