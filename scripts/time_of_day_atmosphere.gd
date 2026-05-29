extends Node3D
class_name TimeOfDayAtmosphere

@export var population_path: NodePath
@export var sun_path: NodePath
@export var environment_path: NodePath
@export var city_path: NodePath

var _population: Node
var _sun: DirectionalLight3D
var _environment_node: WorldEnvironment
var _city: Node
var _moon: MeshInstance3D
var _moon_material: StandardMaterial3D
var _last_visual_hour: float = -INF


func _ready() -> void:
	_population = get_node_or_null(population_path)
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_environment_node = get_node_or_null(environment_path) as WorldEnvironment
	_city = get_node_or_null(city_path)
	_ensure_moon()
	apply_atmosphere()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_N:
		var current: Dictionary = get_lighting_state(_current_hour())
		var is_night: bool = float(current.get("night", 0.0)) > 0.5
		print("Night toggle -> %s" % ["day" if is_night else "night"])
		apply_atmosphere(2.0 if not is_night else 14.0)


func _process(_delta: float) -> void:
	var hour: float = _current_hour()
	if is_equal_approx(hour, _last_visual_hour):
		return
	apply_atmosphere(hour)


func apply_atmosphere(hour_override: float = NAN) -> void:
	var hour: float = hour_override
	if is_nan(hour):
		hour = _current_hour()
	_last_visual_hour = hour
	var lighting: Dictionary = get_lighting_state(hour)
	var daylight: float = float(lighting.get("daylight", 1.0))
	var blue_hour: float = float(lighting.get("blue_hour", 0.0))
	var warm_hour: float = float(lighting.get("warm_hour", 0.0))
	var night: float = float(lighting.get("night", 0.0))
	var moonlight: float = float(lighting.get("moonlight", 0.0))

	if _sun != null:
		var day_progress: float = fposmod((hour - 6.0) / 24.0, 1.0)
		var sun_pitch: float = lerpf(0.36, -1.24, clampf((sin(day_progress * TAU) + 1.0) * 0.5, 0.0, 1.0))
		var sun_yaw: float = lerpf(-0.45, 0.92, clampf((cos(day_progress * TAU) + 1.0) * 0.5, 0.0, 1.0))
		_sun.rotation = Vector3(sun_pitch, sun_yaw, 0.0)
		var sun_day := Color(1.0, 0.95, 0.84)
		var sun_blue := Color(0.52, 0.68, 1.0)
		var sun_warm := Color(1.0, 0.56, 0.30)
		var sun_night := Color(0.24, 0.30, 0.44)
		var blue_mix: float = clampf(blue_hour * 1.2, 0.0, 1.0)
		var warm_mix: float = clampf(warm_hour * 0.95, 0.0, 1.0)
		var lit_color: Color = sun_day.lerp(sun_blue, blue_mix).lerp(sun_warm, warm_mix)
		_sun.light_color = lit_color.lerp(sun_night, clampf(night * (1.0 - blue_hour * 0.82), 0.0, 1.0))
		_sun.light_energy = lerpf(0.14, 1.02, daylight)
		_sun.light_energy += warm_hour * 0.22
		_sun.light_energy += blue_hour * 0.08
		_sun.light_energy += moonlight * 0.14
		_sun.light_energy = clampf(_sun.light_energy, 0.14, 1.24)
		_sun.visible = true

	if _environment_node != null and _environment_node.environment != null:
		var env: Environment = _environment_node.environment
		var night_color := Color(0.08, 0.11, 0.20)
		var dawn_color := Color(0.22, 0.34, 0.68)
		var sunrise_color := Color(1.0, 0.55, 0.34)
		var day_color := Color(0.60, 0.78, 0.98)
		var clear: Color = night_color.lerp(dawn_color, blue_hour)
		clear = clear.lerp(day_color, daylight)
		clear = clear.lerp(sunrise_color, clampf(warm_hour * 0.72, 0.0, 1.0))
		clear = clear.lerp(Color(0.22, 0.26, 0.34), moonlight * 0.42)
		env.background_mode = Environment.BG_COLOR
		env.background_color = clear
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = clear.lerp(Color(0.82, 0.86, 0.95), moonlight * 0.34).lerp(Color(1.0, 0.95, 0.88), daylight * 0.18 + warm_hour * 0.18)
		env.ambient_light_energy = lerpf(0.22, 0.52, daylight) + blue_hour * 0.16 + warm_hour * 0.10 + moonlight * 0.12

	if _city != null and _city.has_method("apply_lighting_state"):
		_city.call("apply_lighting_state", lighting)

	_update_moon(hour, blue_hour, night)


func get_lighting_state(hour_override: float = NAN) -> Dictionary:
	var hour: float = hour_override
	if is_nan(hour):
		hour = _current_hour()
	var daylight: float = _daylight01(hour)
	var sunrise_band: float = _band_strength(hour, 5.0, 8.1)
	var sunset_band: float = _band_strength(hour, 16.2, 20.5)
	var blue_hour: float = maxf(_band_strength(hour, 5.0, 6.6), _band_strength(hour, 17.8, 20.9))
	var warm_hour: float = maxf(sunrise_band, sunset_band)
	var night: float = 1.0 - daylight
	var moonlight: float = clampf(maxf(night * 0.48, blue_hour * 0.22), 0.0, 0.55)
	return {
		"hour": hour,
		"daylight": daylight,
		"blue_hour": blue_hour,
		"warm_hour": warm_hour,
		"night": night,
		"moonlight": moonlight,
		"window_strength": clampf(night * 0.82 + blue_hour * 0.32 + warm_hour * 0.18, 0.0, 1.0),
		"storefront_strength": clampf(maxf(night * 0.92, blue_hour * 0.72) + warm_hour * 0.22, 0.0, 1.0),
		"lamp_strength": clampf(night * 1.05 + blue_hour * 0.38, 0.0, 1.0),
		"window_color_bias": Color(0.98, 0.84, 0.66)
	}


func _ensure_moon() -> void:
	if _moon != null and is_instance_valid(_moon):
		return
	_moon = MeshInstance3D.new()
	_moon.name = "Moon"
	var sphere := SphereMesh.new()
	sphere.radius = 1.8
	sphere.height = 3.6
	_moon.mesh = sphere
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon_material = StandardMaterial3D.new()
	_moon_material.albedo_color = Color(0.90, 0.93, 1.0)
	_moon_material.emission_enabled = true
	_moon_material.emission = Color(0.64, 0.72, 0.98)
	_moon_material.emission_energy_multiplier = 0.85
	_moon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_moon.material_override = _moon_material
	add_child(_moon)


func _update_moon(hour: float, blue_hour: float, night: float) -> void:
	if _moon == null:
		return
	var visibility: float = clampf(maxf(blue_hour * 1.15, night * 0.95), 0.0, 1.0)
	_moon.visible = visibility > 0.05
	if not _moon.visible:
		return
	var total_width: float = 180.0
	if _city != null and _city.get("grid_size") != null:
		var grid: Vector2i = _city.get("grid_size")
		var block_size: float = float(_city.get("block_size"))
		var street_width: float = float(_city.get("street_width"))
		total_width = float(grid.x) * block_size + float(grid.x + 1) * street_width
	var t: float = fposmod((hour - 17.0) / 15.0, 1.0)
	var moon_x: float = lerpf(total_width * 0.34, -total_width * 0.28, t)
	var moon_y: float = lerpf(14.0, 38.0, sin(t * PI))
	var moon_z: float = -total_width * 0.42 + cos(t * PI) * 8.0
	_moon.position = Vector3(moon_x, moon_y, moon_z)
	if _moon_material != null:
		_moon_material.albedo_color = Color(0.76, 0.84, 1.0).lerp(Color(0.98, 0.98, 1.0), blue_hour * 0.55)
		_moon_material.emission_energy_multiplier = lerpf(0.24, 1.05, visibility)


func _current_hour() -> float:
	if _population != null:
		if _population.has_method("get_visual_time_state"):
			return float(Dictionary(_population.call("get_visual_time_state")).get("hour", 8.0))
		if _population.has_method("get_population_summary"):
			return float(Dictionary(_population.call("get_population_summary")).get("hour", 8.0))
	return 8.0


func _daylight01(hour: float) -> float:
	if hour <= 4.8 or hour >= 20.8:
		return 0.0
	if hour < 7.8:
		return inverse_lerp(4.8, 7.8, hour)
	if hour > 17.8:
		return 1.0 - inverse_lerp(17.8, 20.8, hour)
	return 1.0


func _band_strength(hour: float, start_hour: float, end_hour: float) -> float:
	if hour < start_hour or hour > end_hour:
		return 0.0
	var mid: float = (start_hour + end_hour) * 0.5
	if hour <= mid:
		return inverse_lerp(start_hour, mid, hour)
	return 1.0 - inverse_lerp(mid, end_hour, hour)
