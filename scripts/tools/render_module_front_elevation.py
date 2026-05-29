import re
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[1]
SCENE_PATH = ROOT / "scenes" / "modules" / "module_101_arch_top.tscn"
OUT_PATH = ROOT / "outputs" / "module_101_arch_front.svg"

BOX_HEADER_RE = re.compile(r'^\[sub_resource type="BoxMesh" id="([^"]+)"\]$')
BOX_SIZE_RE = re.compile(r'^size = Vector3\(([^,]+), ([^,]+), ([^)]+)\)$')
MAT_HEADER_RE = re.compile(r'^\[sub_resource type="StandardMaterial3D" id="([^"]+)"\]$')
ALBEDO_RE = re.compile(r'^albedo_color = Color\(([^,]+), ([^,]+), ([^,]+), ([^)]+)\)$')
NODE_HEADER_RE = re.compile(r'^\[node name="([^"]+)" type="MeshInstance3D" parent="\."[^\]]*\]$')
MATERIAL_RE = re.compile(r'^material_override = SubResource\("([^"]+)"\)$')
MESH_RE = re.compile(r'^mesh = SubResource\("([^"]+)"\)$')


def classify(name: str) -> str:
    if name.startswith("Frame") or name.startswith("Arch_Frame"):
        return "frame"
    if name.startswith("Glass") or name.startswith("Arch_Glass"):
        return "glass"
    return "wall"


def rgb_to_hex(rgb: Tuple[float, float, float]) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(channel * 255.0)))) for channel in rgb)


def darken(rgb: Tuple[float, float, float], factor: float) -> str:
    return rgb_to_hex(tuple(channel * factor for channel in rgb))


def load_rects() -> List[Dict[str, float]]:
    lines = SCENE_PATH.read_text(encoding="utf-8").splitlines()
    box_sizes: Dict[str, Tuple[float, float, float]] = {}
    material_colors: Dict[str, Tuple[str, str, float]] = {}
    current_box_id = None
    current_mat_id = None
    current_name = None
    current_position = None
    current_material = None
    rects: List[Dict[str, float]] = []

    for line in lines:
        line = line.strip()

        box_header = BOX_HEADER_RE.match(line)
        if box_header:
            current_box_id = box_header.group(1)
            current_mat_id = None
            continue
        if current_box_id:
            size_match = BOX_SIZE_RE.match(line)
            if size_match:
                box_sizes[current_box_id] = tuple(float(size_match.group(i)) for i in range(1, 4))
                current_box_id = None
            continue

        mat_header = MAT_HEADER_RE.match(line)
        if mat_header:
            current_mat_id = mat_header.group(1)
            current_box_id = None
            continue
        if current_mat_id:
            albedo_match = ALBEDO_RE.match(line)
            if albedo_match:
                rgba = tuple(float(albedo_match.group(i)) for i in range(1, 5))
                rgb = rgba[:3]
                alpha = rgba[3]
                material_colors[current_mat_id] = (rgb_to_hex(rgb), darken(rgb, 0.58), alpha)
                current_mat_id = None
            continue

        node_header = NODE_HEADER_RE.match(line)
        if node_header:
            current_name = node_header.group(1)
            current_position = None
            current_material = None
            continue
        if current_name:
            if line.startswith("transform = Transform3D("):
                numbers = [float(value) for value in re.findall(r'-?\d+(?:\.\d+)?', line)]
                current_position = tuple(numbers[-3:])
                continue
            material_match = MATERIAL_RE.match(line)
            if material_match:
                current_material = material_match.group(1)
                continue
            mesh_match = MESH_RE.match(line)
            if mesh_match and current_position is not None:
                mesh_id = mesh_match.group(1)
                sx, sy, _sz = box_sizes[mesh_id]
                x, y, z = current_position
                fill, stroke, opacity = material_colors.get(current_material, ("#c7ced6", "#6b7280", 1.0))
                rects.append({
                    "name": current_name,
                    "kind": classify(current_name),
                    "x0": x - sx * 0.5,
                    "x1": x + sx * 0.5,
                    "y0": y - sy * 0.5,
                    "y1": y + sy * 0.5,
                    "z": z,
                    "fill": fill,
                    "stroke": stroke,
                    "opacity": opacity,
                })
                current_name = None
                current_position = None
                current_material = None
    return rects


def main() -> None:
    rects = load_rects()
    min_x = min(r["x0"] for r in rects)
    max_x = max(r["x1"] for r in rects)
    min_y = min(r["y0"] for r in rects)
    max_y = max(r["y1"] for r in rects)
    scale = 240.0
    pad = 48.0
    width = int((max_x - min_x) * scale + pad * 2)
    height = int((max_y - min_y) * scale + pad * 2 + 60)

    def sx(x: float) -> float:
        return pad + (x - min_x) * scale

    def sy(y: float) -> float:
        return pad + (max_y - y) * scale + 40

    draw_order = {"wall": 0, "glass": 1, "frame": 2}
    rects.sort(key=lambda r: (draw_order[r["kind"]], r["z"]))

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f4f7fb"/>',
        '<text x="48" y="34" font-family="Arial, sans-serif" font-size="24" fill="#1e2837">Module 101 arch window front elevation</text>',
        '<text x="48" y="58" font-family="Arial, sans-serif" font-size="14" fill="#5e6a78">Generated from the saved Godot primitive scene</text>',
    ]
    for rect in rects:
        x = sx(rect["x0"])
        y = sy(rect["y1"])
        w = (rect["x1"] - rect["x0"]) * scale
        h = (rect["y1"] - rect["y0"]) * scale
        fill = rect["fill"]
        stroke = rect["stroke"]
        opacity = rect["opacity"]
        parts.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}" fill-opacity="{opacity:.2f}" stroke="{stroke}" stroke-width="1.5"/>'
        )
    parts.append('</svg>')
    OUT_PATH.write_text("\n".join(parts), encoding="utf-8")
    print(OUT_PATH)


if __name__ == "__main__":
    main()
