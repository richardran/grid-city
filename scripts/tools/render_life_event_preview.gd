extends SceneTree

const PedestrianCrowd = preload("res://scripts/pedestrian_crowd.gd")
const OUT_PATH := "res://outputs/life_event_preview.svg"

func _init() -> void:
	var root := Node3D.new()
	root.name = "PreviewRoot"
	get_root().add_child(root)

	var crowd := PedestrianCrowd.new()
	crowd.name = "PreviewCrowd"
	root.add_child(crowd)

	var anchors := [
		{"type": "birth", "label": "Birth balloons", "x": 170.0},
		{"type": "marriage", "label": "Marriage petals", "x": 500.0},
		{"type": "death", "label": "Death motes", "x": 830.0}
	]
	var preview_roots: Array[Node3D] = []
	for anchor_info in anchors:
		var anchor := Node3D.new()
		anchor.name = "%sAnchor" % str(anchor_info["type"]).capitalize()
		root.add_child(anchor)
		preview_roots.append(anchor)
		crowd.play_life_event_effect({
			"type": anchor_info["type"],
			"person_ids": [1],
			"text": anchor_info["label"]
		})
		# play_life_event_effect requires a matching pedestrian identity, so spawn directly for the preview anchors.
		crowd._spawn_event_effect(anchor, {"type": anchor_info["type"], "text": anchor_info["label"]})

	crowd._update_event_effects(0.85)

	var parts: PackedStringArray = []
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="430" viewBox="0 0 1000 430">')
	parts.append('<rect width="100%" height="100%" fill="#f7f8fc"/>')
	parts.append('<text x="56" y="42" font-family="Arial, sans-serif" font-size="28" fill="#1f2937">Life-event popup preview</text>')
	parts.append('<text x="56" y="68" font-family="Arial, sans-serif" font-size="15" fill="#526072">Selected residents now get event-specific popup effects as time advances.</text>')

	for index in range(preview_roots.size()):
		var anchor_info: Dictionary = anchors[index]
		var center_x: float = float(anchor_info["x"])
		parts.append('<rect x="%.0f" y="92" width="260" height="286" rx="22" fill="#ffffff" stroke="#d8deea"/>' % [center_x - 130.0])
		parts.append('<text x="%.0f" y="124" text-anchor="middle" font-family="Arial, sans-serif" font-size="20" fill="#223043">%s</text>' % [center_x, String(anchor_info["label"])])
		parts.append('<line x1="%.0f" y1="332" x2="%.0f" y2="332" stroke="#cbd5e1" stroke-width="2"/>' % [center_x - 56.0, center_x + 56.0])
		var effect_root := preview_roots[index].get_child(0) as Node3D
		if effect_root == null:
			continue
			
		var caption := effect_root.get_node_or_null("Caption") as Label3D
		if caption != null:
			parts.append('<text x="%.0f" y="156" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" fill="%s">%s</text>' % [center_x, _svg_color(caption.modulate), caption.text.xml_escape()])
		for child in effect_root.get_children():
			if child is MeshInstance3D:
				var mesh_instance := child as MeshInstance3D
				var material := mesh_instance.material_override as StandardMaterial3D
				if material == null:
					continue
				var px: float = center_x + child.position.x * 92.0
				var py: float = 300.0 - child.position.y * 92.0
				var radius: float = 8.0
				if mesh_instance.mesh is SphereMesh:
					radius = maxf(5.0, float((mesh_instance.mesh as SphereMesh).radius) * child.scale.x * 74.0)
				parts.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" fill-opacity="%.3f"/>' % [px, py, radius, _svg_color(material.albedo_color), material.albedo_color.a])

	parts.append('<text x="56" y="402" font-family="Arial, sans-serif" font-size="13" fill="#667085">Preview generated from the same procedural popup effect code used in-scene.</text>')
	parts.append('</svg>')

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_PATH), FileAccess.WRITE)
	file.store_string("\n".join(parts))
	file.close()
	print(ProjectSettings.globalize_path(OUT_PATH))
	root.free()
	quit(0)


func _svg_color(color: Color) -> String:
	return "#%s" % color.to_html(false)
