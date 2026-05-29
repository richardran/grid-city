extends Node3D
func _ready():
	var f = FileAccess.open("user://test_output.txt", FileAccess.WRITE)
	if f:
		f.store_string("hello from min test")
		f.close()
	get_tree().quit()
