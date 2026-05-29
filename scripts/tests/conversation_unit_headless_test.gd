extends SceneTree

const CrowdConversationScript = preload("res://scripts/crowd_conversation.gd")


func _init() -> void:
	_test_visible_lines_pending()
	_test_visible_lines_normal()
	_test_visible_lines_scrolled()
	_test_speaker_index()
	_test_string_lines()
	print("conversation_unit_headless_test: ok")
	quit(0)


func _test_visible_lines_pending() -> void:
	# LLM-pending player conversation should show "..."
	var conv := CrowdConversationScript.new()
	var lines: Array = [{"speaker_index": 0, "text": "hello"}, {"speaker_index": 0, "text": "world"}]
	var conversation := {
		"lines": lines,
		"line_index": 0,
		"llm_pending": true,
		"is_player": true
	}
	var visible: Array = conv._visible_lines_for_conversation(conversation, 0)
	assert(visible.size() == 1, "Pending should show 1 line, got %d" % visible.size())
	assert(visible[0] == "...", "Pending should show '...', got '%s'" % visible[0])
	conv.free()


func _test_visible_lines_normal() -> void:
	var conv := CrowdConversationScript.new()
	var lines: Array = [
		{"speaker_index": 0, "text": "first line"},
		{"speaker_index": 1, "text": "second line"},
		{"speaker_index": 0, "text": "third line"}
	]
	var conversation := {
		"lines": lines,
		"line_index": 0,
		"llm_pending": false,
		"is_player": false
	}
	# At line 0: should show only current line
	var visible: Array = conv._visible_lines_for_conversation(conversation, 0)
	assert(visible.size() == 1, "Line 0 should show 1 line, got %d" % visible.size())
	assert(visible[0] == "first line")
	# At line 1: should show lines 0 and 1 (current + 1 previous)
	visible = conv._visible_lines_for_conversation(conversation, 1)
	assert(visible.size() == 2, "Line 1 should show 2 lines, got %d" % visible.size())
	assert(visible[0] == "first line")
	assert(visible[1] == "second line")
	# At line 2: should show lines 0, 1, 2 (current + 2 previous, capped at 3)
	visible = conv._visible_lines_for_conversation(conversation, 2)
	assert(visible.size() == 3, "Line 2 should show 3 lines, got %d" % visible.size())
	assert(visible[0] == "first line")
	assert(visible[1] == "second line")
	assert(visible[2] == "third line")
	conv.free()


func _test_visible_lines_scrolled() -> void:
	var conv := CrowdConversationScript.new()
	var lines: Array = []
	for i in range(10):
		lines.append({"speaker_index": 0, "text": "line %d" % i})
	var conversation := {
		"lines": lines,
		"line_index": 0,
		"llm_pending": false,
		"is_player": false
	}
	# At line 9: should show last 3 lines (7, 8, 9)
	var visible: Array = conv._visible_lines_for_conversation(conversation, 9)
	assert(visible.size() == 3, "Line 9 should show 3 lines, got %d" % visible.size())
	assert(visible[0] == "line 7")
	assert(visible[1] == "line 8")
	assert(visible[2] == "line 9")
	conv.free()


func _test_speaker_index() -> void:
	var conv := CrowdConversationScript.new()
	var lines: Array = [
		{"speaker_index": 3, "text": "hello"},
		{"speaker_index": 7, "text": "world"}
	]
	var conversation := {"lines": lines}
	var idx: int = conv._speaker_index_for_conversation_line(conversation, 0)
	assert(idx == 3, "Line 0 speaker should be 3, got %d" % idx)
	idx = conv._speaker_index_for_conversation_line(conversation, 1)
	assert(idx == 7, "Line 1 speaker should be 7, got %d" % idx)
	# Out of range: should clamp
	idx = conv._speaker_index_for_conversation_line(conversation, 99)
	assert(idx == 7, "Out-of-range should clamp to last, got %d" % idx)
	conv.free()


func _test_string_lines() -> void:
	var conv := CrowdConversationScript.new()
	var input: Array = ["a", "b", "c"]
	var result: Array = conv._string_lines(input)
	assert(result.size() == 3)
	assert(result[0] == "a")
	assert(result[1] == "b")
	assert(result[2] == "c")
	
	# Empty input
	result = conv._string_lines([])
	assert(result.is_empty())
	conv.free()
