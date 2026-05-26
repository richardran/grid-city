# Godot City Grid

A Godot 4 prototype of a San Francisco-style hillside city.

## Current design

This version was rebuilt from scratch around a simple rule:

- **no visible terrain mesh**
- heights come from a terrain function
- the city is filled entirely by **road solids** and **block/foundation solids**
- roads and block foundations use the **same exact grid boundaries**
- together they tile the city footprint without intentional gaps

## What it does

- Generates a grid street system over varying SF-like hill heights
- Uses stepped road segments where elevation changes are larger
- Creates a house/foundation block in every block formed by the road grid
- Places house masses on top of each block foundation
- Constrains the viewer to explicit walkable road surfaces
- Shows ambient pedestrian conversation bubbles, including occasional player-nearby remarks when you get close enough
- Can optionally pull player-directed NPC lines from OpenRouter when `OPENROUTER_API_KEY` is set in the environment

## Run

```powershell
godot --path .
```

Or open the `godot-city-grid` folder in the Godot editor.

## Controls

- `W / S` or `Up / Down`: walk forward / backward
- `A / D` or `Left / Right`: turn
- `V`: toggle between ground view and overlook view
- Walk near pedestrians to occasionally trigger short nearby remarks
- Click a pedestrian to inspect them and force a short conversation with that person

## Optional OpenRouter dialogue

If `OPENROUTER_API_KEY` is available in the environment, player-nearby pedestrian remarks can be replaced with short generated lines via OpenRouter.

The crowd script defaults to `openrouter/auto`, which lets OpenRouter route to a fast available model automatically. You can override that in the `Crowd` node with `openrouter_model` if you want a fixed model instead.

## Optional voiced conversations

Player-directed conversation lines can also be rendered to voice and played back through an OpenAI-compatible speech API.

Default settings expect:
- `OPENAI_API_KEY`
- `https://api.openai.com/v1/audio/speech`
- model `gpt-4o-mini-tts`
- voice `alloy`

You can change the environment variable name, API base URL, model, and voice on the `Crowd` node if you want to use another compatible provider.

## Main files

- `scenes/main.tscn` - main scene
- `scripts/city_generator.gd` - rebuilt grid/road/block generator
- `scripts/street_walker.gd` - street-level walker
- `scripts/building_api.gd` - modular building API for Godot callers

## Modular building API

Module `100` is the canonical building unit:
- `1 module (id 100)` = `1 wall segment` = `1 floor tall` = `1 recessed window`
- `array of modules` = `1 wall`
- `4 walls` + `4 corner caps` = `1 floor shell`
- `array of floors` + `roof module` = `1 building`

This API is intended for **runtime game calls**. Buildings are generated **entirely from code** from the module definition; no hand-authored building mesh is required.
The corner seam is handled with generated **corner cap modules**, which is simpler and more reliable for later procedural generation than trying to hand-tune every wall length.

### Runtime request API

```gdscript
var request := {
	"module_id": 100,
	"width_modules": 4,
	"length_modules": 3,
	"floor_count": 3,
	"roof_type": "flat", # or "pitched"
	"position": Vector3(0, 0, 0),
	"rotation_degrees_y": 0.0,
	"name": "ShopBlock_A"
}

var building := BuildingAPI.build_building_from_request(request)
add_child(building)
```

### Request constraints

Inputs are clamped to a reasonable runtime-safe range:
- `width_modules`: `1..32`
- `length_modules`: `1..32`
- `floor_count`: `1..24`
- `roof_type`: `flat | pitched` (`flat` is default)
- unsupported `module_id` values currently fall back to `100`

### Data-first usage

```gdscript
var spec := BuildingAPI.create_building_spec_from_request({
	"module_id": 100,
	"width_modules": 4,
	"length_modules": 3,
	"floor_count": 3
})
var building := BuildingAPI.build_building_from_spec(spec)
```

You can also work at lower levels:

```gdscript
var wall := BuildingAPI.create_wall_spec(100, 6)
var floor := BuildingAPI.create_floor_spec(100, 4, 0, 3)
var module_scene := BuildingAPI.build_module_node(100)
var corner_scene := BuildingAPI.build_corner_module_node(100)
var roof_scene := BuildingAPI.build_roof_module_node("pitched")
```

Permanent primitive assets can be regenerated with:

```powershell
godot --headless --path . --script res://scripts/save_building_primitive_assets.gd
```

This writes:
- `res://scenes/modules/module_100_single_window.tscn`
- `res://scenes/modules/module_100_corner_cap.tscn`
- `res://scenes/modules/roof_flat_w4_l3.tscn`
- `res://scenes/modules/roof_pitched_w4_l3.tscn`

Headless verification:

```powershell
godot --headless --path . --script res://scripts/building_api_headless_test.gd
```
