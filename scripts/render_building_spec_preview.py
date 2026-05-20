import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "outputs" / "building_100_w4_l3_f3.json"
OUT_PATH = ROOT / "outputs" / "building_100_w4_l3_f3_preview.svg"

SCALE = 18.0
COS = math.cos(math.radians(30))
SIN = math.sin(math.radians(30))


def iso(x: float, y: float, z: float, center_x: float, base_y: float):
    sx = center_x + (x - z) * COS * SCALE
    sy = base_y - y * SCALE + (x + z) * SIN * SCALE
    return (sx, sy)


def load_spec():
    return json.loads(SPEC_PATH.read_text(encoding="utf-8"))


def build_boxes(spec):
    module_width = 3.2
    module_depth = 0.25
    module_height = 3.0
    boxes = []
    colors = {
        0: "#a0bee1",
        90: "#b9cdeb",
        180: "#91afd2",
        270: "#aac3dc",
    }
    for floor in spec["floors"]:
        for wall in floor["walls"]:
            yaw = int(round(wall["yaw_degrees"])) % 360
            for module in wall["modules"]:
                p = module["position"]
                cx = p["x"]
                cy = p["y"]
                cz = p["z"]
                if yaw in (0, 180):
                    size_x, size_z = module_width, module_depth
                else:
                    size_x, size_z = module_depth, module_width
                boxes.append({
                    "min_x": cx - size_x / 2,
                    "max_x": cx + size_x / 2,
                    "min_y": cy,
                    "max_y": cy + module_height,
                    "min_z": cz - size_z / 2,
                    "max_z": cz + size_z / 2,
                    "color": colors[yaw],
                })
    fp = spec["footprint"]
    roof_y = spec["floor_count"] * spec["module_height"]
    boxes.append({
        "min_x": -fp["width"] / 2,
        "max_x": fp["width"] / 2,
        "min_y": roof_y,
        "max_y": roof_y + 0.18,
        "min_z": -fp["depth"] / 2,
        "max_z": fp["depth"] / 2,
        "color": "#8791a0",
    })
    return boxes


def hex_to_rgb(hex_color: str):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4))


def shade(hex_color: str, factor: float) -> str:
    rgb = hex_to_rgb(hex_color)
    vals = [max(0, min(255, int(c * factor))) for c in rgb]
    return "#%02x%02x%02x" % tuple(vals)


def face_points(box, face, center_x, base_y):
    x0, x1 = box["min_x"], box["max_x"]
    y0, y1 = box["min_y"], box["max_y"]
    z0, z1 = box["min_z"], box["max_z"]
    if face == "top":
        pts = [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
    elif face == "left":
        pts = [(x0, y0, z1), (x0, y0, z0), (x0, y1, z0), (x0, y1, z1)]
    else:
        pts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)]
    return [iso(*p, center_x, base_y) for p in pts]


def polygon(points):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in points)


def main():
    spec = load_spec()
    boxes = build_boxes(spec)
    center_x = 700
    base_y = 860
    fp = spec["footprint"]
    ground = [
        iso(-fp["width"] / 2 - 0.2, 0, -fp["depth"] / 2 - 0.2, center_x, base_y),
        iso(fp["width"] / 2 + 0.2, 0, -fp["depth"] / 2 - 0.2, center_x, base_y),
        iso(fp["width"] / 2 + 0.2, 0, fp["depth"] / 2 + 0.2, center_x, base_y),
        iso(-fp["width"] / 2 - 0.2, 0, fp["depth"] / 2 + 0.2, center_x, base_y),
    ]

    boxes.sort(key=lambda b: (b["min_x"] + b["min_z"], b["min_y"]))

    parts = []
    parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="1100" viewBox="0 0 1400 1100">')
    parts.append('<rect width="1400" height="1100" fill="#f2f6fc"/>')
    parts.append(f'<polygon points="{polygon(ground)}" fill="#e1e7ef" stroke="#cdd6e0" stroke-width="2"/>')
    for box in boxes:
        base = box["color"]
        left = face_points(box, "left", center_x, base_y)
        right = face_points(box, "right", center_x, base_y)
        top = face_points(box, "top", center_x, base_y)
        parts.append(f'<polygon points="{polygon(left)}" fill="{shade(base, 0.82)}" stroke="#505a69" stroke-width="1.5"/>')
        parts.append(f'<polygon points="{polygon(right)}" fill="{shade(base, 0.93)}" stroke="#505a69" stroke-width="1.5"/>')
        parts.append(f'<polygon points="{polygon(top)}" fill="{shade(base, 1.05)}" stroke="#505a69" stroke-width="1.5"/>')
    parts.append('<text x="40" y="48" font-family="Arial, sans-serif" font-size="28" fill="#1e2837">Module 100 test building: 4 width × 3 length × 3 floors</text>')
    parts.append('<text x="40" y="82" font-family="Arial, sans-serif" font-size="18" fill="#4b5a6e">Preview built from the generated Godot spec</text>')
    parts.append('</svg>')

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(parts), encoding="utf-8")
    print(OUT_PATH)


if __name__ == "__main__":
    main()
