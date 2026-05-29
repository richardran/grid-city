extends SceneTree

const StreetWalker = preload("res://scripts/street_walker.gd")


func _init() -> void:
	_test_default_view_is_ground()
	_test_toggle_view_mode()
	_test_keyboard_input()
	print("street_walker_headless_test: ok")
	quit(0)


func _test_default_view_is_ground() -> void:
	var walker := StreetWalker.new()
	assert(walker.get_view_mode() == "ground", "Default view should be 'ground', got '%s'" % walker.get_view_mode())
	assert(walker.get_view_mode_label() == "Ground", "Default label should be 'Ground', got '%s'" % walker.get_view_mode_label())
	walker.free()


func _test_toggle_view_mode() -> void:
	var walker := StreetWalker.new()
	# Initial is ground
	assert(walker.get_view_mode() == "ground")
	# Toggle to overlook
	walker.toggle_view_mode()
	assert(walker.get_view_mode() == "overlook", "After toggle should be 'overlook', got '%s'" % walker.get_view_mode())
	assert(walker.get_view_mode_label() == "Overlook")
	# Toggle back to ground
	walker.toggle_view_mode()
	assert(walker.get_view_mode() == "ground", "After second toggle should be 'ground', got '%s'" % walker.get_view_mode())
	walker.free()


func _test_keyboard_input() -> void:
	# Test that the walker responds to keyboard input
	var walker := StreetWalker.new()
	walker.set_process(true)
	walker.set_process_input(true)
	
	# Simulate V key press for toggle
	var event := InputEventKey.new()
	event.keycode = KEY_V
	event.pressed = true
	walker._unhandled_input(event)
	assert(walker.get_view_mode() == "overlook", "V should toggle to overlook")
	
	# Toggle back
	var event2 := InputEventKey.new()
	event2.keycode = KEY_V
	event2.pressed = true
	walker._unhandled_input(event2)
	assert(walker.get_view_mode() == "ground", "Second V should toggle back to ground")
	
	walker.free()
