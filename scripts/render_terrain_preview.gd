extends SceneTree

const CityGenerator = preload("res://scripts/city_generator.gd")
const OUT_PATH := "res://outputs/terrain_preview.svg"

func _init() -> void:
	var city := CityGenerator.new()
	city.grid_size = Vector2i(10, 10)
	city.block_size = 16.0
	city.street_width = 6.0
	city.seed_value = 7
	city.terrain_height = 11.5
	city.terrain_frequency = 0.0195
	city._setup_noise()

	var total_width: float = city._total_width()
	var total_depth: float = city._total_depth()
	var samples_x: int = 72
	var samples_z: int = 72
	var min_h: float = INF
	var max_h: float = -INF
	var heights: Array = []

	for iz in range(samples_z):
		var row: Array = []
		var z: float = lerpf(-total_depth * 0.5, total_depth * 0.5, float(iz) / float(samples_z - 1))
		for ix in range(samples_x):
			var x: float = lerpf(-total_width * 0.5, total_width * 0.5, float(ix) / float(samples_x - 1))
			var h: float = city._terrain_height(x, z)
			row.append(h)
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
		heights.append(row)

	var width := 1080
	var height := 1080
	var pad := 64.0
	var inner_w: float = width - pad * 2.0
	var inner_h: float = height - pad * 2.0
	var parts: PackedStringArray = []
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [width, height, width, height])
	parts.append('<rect width="100%" height="100%" fill="#f5f7fb"/>')
	parts.append('<text x="64" y="36" font-family="Arial, sans-serif" font-size="24" fill="#1e2837">Terrain preview — slightly hillier San Francisco profile</text>')
	parts.append('<text x="64" y="60" font-family="Arial, sans-serif" font-size="14" fill="#5e6a78">seed 7 · terrain_height 11.5 · terrain_frequency 0.0195 · sampled from city_generator.gd</text>')

	for iz in range(samples_z - 1):
		for ix in range(samples_x - 1):
			var h00: float = heights[iz][ix]
			var h10: float = heights[iz][ix + 1]
			var h01: float = heights[iz + 1][ix]
			var h11: float = heights[iz + 1][ix + 1]
			var avg: float = (h00 + h10 + h01 + h11) * 0.25
			var t: float = inverse_lerp(min_h, max_h, avg)
			var fill: String = _terrain_color(t)
			var x0: float = pad + inner_w * float(ix) / float(samples_x - 1)
			var x1: float = pad + inner_w * float(ix + 1) / float(samples_x - 1)
			var y0: float = pad + inner_h * float(iz) / float(samples_z - 1)
			var y1: float = pad + inner_h * float(iz + 1) / float(samples_z - 1)
			parts.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" stroke="none"/>' % [x0, y0, x1 - x0 + 0.4, y1 - y0 + 0.4, fill])

	for contour_index in range(1, 9):
		var contour_h: float = lerpf(min_h, max_h, float(contour_index) / 9.0)
		for iz in range(samples_z - 1):
			for ix in range(samples_x - 1):
				var cell_min: float = minf(minf(heights[iz][ix], heights[iz][ix + 1]), minf(heights[iz + 1][ix], heights[iz + 1][ix + 1]))
				var cell_max: float = maxf(maxf(heights[iz][ix], heights[iz][ix + 1]), maxf(heights[iz + 1][ix], heights[iz + 1][ix + 1]))
				if contour_h < cell_min or contour_h > cell_max:
					continue
				var x0: float = pad + inner_w * float(ix) / float(samples_x - 1)
				var x1: float = pad + inner_w * float(ix + 1) / float(samples_x - 1)
				var y0: float = pad + inner_h * float(iz) / float(samples_z - 1)
				var y1: float = pad + inner_h * float(iz + 1) / float(samples_z - 1)
				parts.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="#ffffff" stroke-opacity="0.18" stroke-width="1"/>' % [x0, y0, x1 - x0, y1 - y0])

	for ix in range(city.grid_size.x + 1):
		var road_x: float = pad + inner_w * float(ix) / float(city.grid_size.x)
		parts.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#2d3440" stroke-opacity="0.22" stroke-width="1.2"/>' % [road_x, pad, road_x, pad + inner_h])
	for iz in range(city.grid_size.y + 1):
		var road_y: float = pad + inner_h * float(iz) / float(city.grid_size.y)
		parts.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#2d3440" stroke-opacity="0.22" stroke-width="1.2"/>' % [pad, road_y, pad + inner_w, road_y])

	parts.append('<rect x="64" y="962" width="952" height="46" rx="12" fill="#ffffff" fill-opacity="0.72" stroke="#d2dae5"/>')
	parts.append('<text x="82" y="990" font-family="Arial, sans-serif" font-size="14" fill="#334155">Low: %.2f  ·  High: %.2f  ·  Darker lines show the street grid sitting on steeper hills</text>' % [min_h, max_h])
	parts.append('</svg>')

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
	file.store_string("\n".join(parts))
	file.close()
	print(ProjectSettings.globalize_path(OUT_PATH))
	city.free()
	quit(0)


func _terrain_color(t: float) -> String:
	var low := Color(0.67, 0.77, 0.66)
	var mid := Color(0.84, 0.79, 0.62)
	var high := Color(0.73, 0.59, 0.47)
	var color: Color = low.lerp(mid, clampf(t * 1.35, 0.0, 1.0)) if t < 0.55 else mid.lerp(high, clampf((t - 0.55) / 0.45, 0.0, 1.0))
	return "#%s" % color.to_html(false)
