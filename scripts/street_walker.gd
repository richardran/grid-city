extends Camera3D

@export var city_path: NodePath
@export var move_speed: float = 4.8
@export var turn_speed: float = 1.9
@export var eye_height: float = 1.65
@export var ground_look_pitch: float = -0.12
@export var ground_height_offset: float = 0.0
@export var overlook_look_pitch: float = -0.52
@export var overlook_height_offset: float = 18.0
@export_enum("ground", "overlook") var initial_view_mode: String = "ground"

var _city: Node
var _yaw: float = 0.0
var _view_mode: String = "ground"

func _ready() -> void:
	if city_path != NodePath():
		_city = get_node_or_null(city_path)
	else:
		_city = get_parent().get_node_or_null("City")

	if _city != null and _city.has_method("get_spawn_point"):
		var spawn: Vector3 = _city.call("get_spawn_point")
		position = spawn
	_yaw = rotation.y
	set_view_mode(initial_view_mode)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		toggle_view_mode()

func _process(delta: float) -> void:
	var turn_input: float = 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		turn_input += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		turn_input -= 1.0
	_yaw += turn_input * turn_speed * delta

	var move_input: float = 0.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		move_input += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		move_input -= 1.0

	var forward := Vector3.FORWARD.rotated(Vector3.UP, _yaw)
	if move_input != 0.0:
		var desired := position + forward * (move_input * move_speed * delta)
		if _city != null and _city.has_method("try_move_on_walk"):
			position = _city.call("try_move_on_walk", position, desired)
		else:
			position = desired

	_apply_view_transform()


func toggle_view_mode() -> String:
	set_view_mode("ground" if _view_mode == "overlook" else "overlook")
	return _view_mode


func set_view_mode(mode: String) -> void:
	_view_mode = "overlook" if mode == "overlook" else "ground"
	_apply_view_transform()


func get_view_mode() -> String:
	return _view_mode


func get_view_mode_label() -> String:
	return "Overlook" if _view_mode == "overlook" else "Ground"


func _apply_view_transform() -> void:
	if _city != null and _city.has_method("get_walk_height"):
		position.y = _city.call("get_walk_height", position) + _current_height_offset()
	rotation = Vector3(_current_pitch(), _yaw, 0.0)


func _current_pitch() -> float:
	return overlook_look_pitch if _view_mode == "overlook" else ground_look_pitch


func _current_height_offset() -> float:
	return overlook_height_offset if _view_mode == "overlook" else ground_height_offset
