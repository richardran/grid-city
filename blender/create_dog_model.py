import bpy
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters"
OUTPUT_DIR = ROOT / "outputs"
BLEND_PATH = ROOT.parent / "blender-assets" / "dog_companion.blend"
GLB_PATH = ASSET_DIR / "dog_companion.glb"
PREVIEW_PATH = OUTPUT_DIR / "dog_model_preview.png"


def ensure_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)


def make_material(name: str, color, roughness: float = 0.85):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_cube(name: str, location, scale, material, rotation=(0.0, 0.0, 0.0), parent=None):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    bpy.ops.object.shade_smooth()
    return obj


def add_cone(name: str, location, scale, material, rotation=(0.0, 0.0, 0.0), parent=None, vertices=12):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    bpy.ops.object.shade_smooth()
    return obj


def add_uv_sphere(name: str, location, radius: float, material, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(location=location, radius=radius, segments=16, ring_count=8)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.clear()
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    bpy.ops.object.shade_smooth()
    return obj


def build_dog():
    dog_root = bpy.data.objects.new("DogRoot", None)
    bpy.context.collection.objects.link(dog_root)

    fur = make_material("DogFur", (0.63, 0.42, 0.23, 1.0), 0.92)
    fur_dark = make_material("DogFurDark", (0.22, 0.15, 0.10, 1.0), 0.95)
    collar = make_material("DogCollar", (0.19, 0.54, 0.78, 1.0), 0.55)
    nose = make_material("DogNose", (0.06, 0.05, 0.05, 1.0), 0.4)

    add_cube("Dog_Body", (0.0, 0.52, 0.0), (0.58, 0.22, 0.20), fur, parent=dog_root)
    add_cube("Dog_Chest", (0.48, 0.53, 0.0), (0.18, 0.18, 0.18), fur, parent=dog_root)
    add_cube("Dog_Head", (0.86, 0.63, 0.0), (0.23, 0.18, 0.17), fur, parent=dog_root)
    add_cube("Dog_Muzzle", (1.10, 0.56, 0.0), (0.13, 0.10, 0.10), fur_dark, parent=dog_root)
    add_cube("Dog_Collar", (0.62, 0.50, 0.0), (0.04, 0.12, 0.13), collar, parent=dog_root)

    add_cone("Dog_Ear_L", (0.80, 0.86, 0.11), (0.06, 0.12, 0.06), fur_dark, rotation=(math.radians(12.0), 0.0, math.radians(12.0)), parent=dog_root)
    add_cone("Dog_Ear_R", (0.80, 0.86, -0.11), (0.06, 0.12, 0.06), fur_dark, rotation=(math.radians(-12.0), 0.0, math.radians(12.0)), parent=dog_root)
    add_cone("Dog_Tail", (-0.70, 0.72, 0.0), (0.05, 0.28, 0.05), fur_dark, rotation=(math.radians(76.0), 0.0, 0.0), parent=dog_root)

    leg_positions = {
        "Dog_Leg_FL": (0.40, 0.21, 0.12),
        "Dog_Leg_FR": (0.40, 0.21, -0.12),
        "Dog_Leg_BL": (-0.36, 0.21, 0.12),
        "Dog_Leg_BR": (-0.36, 0.21, -0.12),
    }
    for name, loc in leg_positions.items():
        add_cube(name, loc, (0.06, 0.22, 0.05), fur_dark, parent=dog_root)

    add_uv_sphere("Dog_Eye_L", (1.00, 0.67, 0.10), 0.022, nose, parent=dog_root)
    add_uv_sphere("Dog_Eye_R", (1.00, 0.67, -0.10), 0.022, nose, parent=dog_root)
    add_uv_sphere("Dog_Nose", (1.20, 0.55, 0.0), 0.035, nose, parent=dog_root)

    dog_root.rotation_euler = (0.0, math.radians(90.0), 0.0)
    bpy.context.view_layer.objects.active = dog_root
    return dog_root


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.93, 0.95, 0.98, 1.0)
    bg.inputs[1].default_value = 0.9

    bpy.ops.object.light_add(type="SUN", location=(3.0, 4.0, 5.5))
    sun = bpy.context.active_object
    sun.name = "PreviewSun"
    sun.rotation_euler = (math.radians(38.0), math.radians(0.0), math.radians(28.0))
    sun.data.energy = 2.2

    bpy.ops.object.light_add(type="AREA", location=(-3.8, 2.2, 2.0))
    area = bpy.context.active_object
    area.name = "PreviewFill"
    area.data.energy = 1800
    area.data.shape = "RECTANGLE"
    area.data.size = 4.0
    area.data.size_y = 4.0
    area.rotation_euler = (math.radians(60.0), 0.0, math.radians(-60.0))

    bpy.ops.object.camera_add(location=(5.8, -5.6, 3.9), rotation=(math.radians(68.0), 0.0, math.radians(46.0)))
    camera = bpy.context.active_object
    camera.name = "PreviewCamera"
    camera.data.lens = 48
    scene.camera = camera


def export_selected(root_obj):
    bpy.ops.object.select_all(action="DESELECT")
    root_obj.select_set(True)
    for child in root_obj.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root_obj
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
    )


def main():
    ensure_dir(GLB_PATH)
    ensure_dir(PREVIEW_PATH)
    ensure_dir(BLEND_PATH)
    clear_scene()
    dog_root = build_dog()
    setup_render()
    bpy.context.scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    export_selected(dog_root)
    print(f"Saved {BLEND_PATH}")
    print(f"Rendered {PREVIEW_PATH}")
    print(f"Exported {GLB_PATH}")


if __name__ == "__main__":
    main()
