extends Node3D
class_name CityVisualizer

## Reads a CityLayout and creates/updates the Godot scene tree.
## Pure visual layer — no generation logic, no data mutation.

var layout: CityLayout = null
var generated_root: Node3D = null

# Shared caches
static var _mesh_cache: Dictionary = {}
static var _material_cache: Dictionary = {}

# Material references set by city_generator
var _road_material: Material
var _stair_material: Material
var _foundation_material: Material
var _wall_material: Material
var _house_trim_material: Material
var _house_body_materials: Array[Material] = []
var _track_material: Material
var _railing_material: Material
var _planter_material: Material
var _foliage_material: Material
var _vine_material: Material
var _lamp_post_material: Material
var _trunk_material: Material
var _canopy_material: Material

var _emissive_material_profiles: Array = []
var _lighting_state: Dictionary = {}
var _spatial_grid: Dictionary = {}
var _block_width: float = 0.0


func clear() -> void:
	if generated_root != null and is_instance_valid(generated_root):
		generated_root.queue_free()
		generated_root = null
	_emissive_material_profiles.clear()
	_spatial_grid.clear()
	layout = null


func build_from_layout(p_layout: CityLayout, materials: Dictionary) -> void:
	clear()
	layout = p_layout
	_block_width = layout.block_size + layout.street_width
	_road_material = materials.get("road")
	_stair_material = materials.get("stair")
	_foundation_material = materials.get("foundation")
	_wall_material = materials.get("wall")
	_house_trim_material = materials.get("house_trim")
	_house_body_materials = materials.get("house_body_materials", [])
	_track_material = materials.get("track")
	_railing_material = materials.get("railing")
	_planter_material = materials.get("planter")
	_foliage_material = materials.get("foliage")
	_vine_material = materials.get("vine")
	_lamp_post_material = materials.get("lamp_post")
	_trunk_material = materials.get("trunk")
	_canopy_material = materials.get("canopy")

	generated_root = Node3D.new()
	generated_root.name = "GeneratedCity"
	add_child(generated_root)

	_create_city_base()
	# Roads, blocks, etc. would be created here from layout data


func _spatial_parent_for(world_pos: Vector3) -> Node3D:
	if _block_width <= 0.0 or generated_root == null:
		return generated_root
	var cx: int = int(floor(world_pos.x / _block_width))
	var cz: int = int(floor(world_pos.z / _block_width))
	var key: String = "c_%d_%d" % [cx, cz]
	if _spatial_grid.has(key):
		return _spatial_grid[key] as Node3D
	var cell := Node3D.new()
	cell.name = "Cell_%d_%d" % [cx, cz]
	generated_root.add_child(cell)
	_spatial_grid[key] = cell
	return cell


func _create_city_base() -> void:
	if layout == null:
		return
	var base := MeshInstance3D.new()
	base.name = "CityBase"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(layout.total_width(), 2.0, layout.total_depth())
	base.mesh = mesh
	base.material_override = _wall_material
	base.position = Vector3(0.0, layout.city_base_y - 1.0, 0.0)
	generated_root.add_child(base)


# Cached mesh factories (shared across instances)

static func cached_box(w: float, h: float, d: float) -> BoxMesh:
	var key: String = "box_%.3f_%.3f_%.3f" % [w, h, d]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	_mesh_cache[key] = mesh
	return mesh


static func cached_cylinder(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var key: String = "cyl_%.3f_%.3f_%.3f" % [top_r, bottom_r, height]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	_mesh_cache[key] = mesh
	return mesh


static func cached_sphere(radius: float, height: float = -1.0) -> SphereMesh:
	var key: String = "sph_%.3f" % radius
	if height > 0.0:
		key = "sph_%.3f_%.3f" % [radius, height]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as SphereMesh
	var mesh := SphereMesh.new()
	mesh.radius = radius
	if height > 0.0:
		mesh.height = height
	_mesh_cache[key] = mesh
	return mesh


static func cached_cone(bottom_r: float, height: float) -> CylinderMesh:
	var key: String = "cone_%.3f_%.3f" % [bottom_r, height]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 8
	_mesh_cache[key] = mesh
	return mesh


static func cached_material(key: String, setup_func: Callable) -> Material:
	if _material_cache.has(key):
		return _material_cache[key]
	var mat: Material = setup_func.call()
	_material_cache[key] = mat
	return mat
