extends SceneTree
var _count: int = 0
func _init() -> void:
	print("init done")
func _process(delta: float) -> bool:
	_count += 1
	print("process %d" % _count)
	if _count >= 5:
		quit()
		return false
	return true  # true = continue?
