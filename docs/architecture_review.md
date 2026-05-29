# Grid City — Architectural Review

## Current Problems

| Issue | Impact |
|-------|--------|
| **Data & visuals mixed** in city_generator.gd | Can't save layouts, no minimap, regeneration is destructive |
| **Pedestrian data as magic-string Dictionaries** | No type safety, bugs from misspelled keys, hard to refactor |
| **Signal spaghetti** — UI calls crowd via `call("method_name")` | No compile-time checking, runtime errors |
| **Monolithic files** (pedestrian_crowd.gd 2100+ lines) | Hard to reason about, test, or modify individual behaviors |
| **No ECS or component pattern** | Every pedestrian has ALL fields (even dogs have `work_building_id`) |
| **City generation = node creation** | Can't preview, can't serialize, can't reuse |

## Proposed Architecture

### Layer 1 — Pure Data (no Godot nodes)

```
res://data/
├── city_data.gd          — CityLayout, Block, Road, BuildingSlot (all Vector2/float)
├── population_data.gd    — Person, Household, SocialBond (all int/float/string)
├── trait_data.gd         — TraitGenerator (stateless, produces trait dicts)
└── activity_data.gd     — ActivityGoal, Destination (pure data for what an NPC wants)
```

CityLayout is a **resource** — can be saved/loaded from disk. Has no MeshInstance3D references.

### Layer 2 — Systems (stateless where possible, one responsibility each)

```
res://systems/
├── city_generator.gd     — Config → CityLayout (pure data generation)
├── city_visualizer.gd    — CityLayout → Godot scene tree (MeshInstance, MultiMesh)
├── population_sim.gd     — Tick hours → update Person[] (mood, births, deaths, relationships)
├── navigation.gd         — CityLayout + Vector3 → walkable target (queries, not nodes)
├── pedestrian_spawner.gd — Person[] → visual agents (reads activity, sets targets)
├── pedestrian_mover.gd   — Each frame: move agents toward targets (no conversation logic)
├── conversation_machine.gd — State machine: idle → talking → done (emits signals)
└── interaction.gd        — Player click → find nearest NPC → trigger conversation
```

Each system is a **class_name** Node or RefCounted:

- Systems that need `_process` (mover, visualizer updates) extend Node
- Systems that are pure logic (generator, sim, navigation) extend RefCounted
- Systems communicate via **signals** and **shared data references**, not `call()`

### Layer 3 — Visuals (thin, driven by data)

```
res://visuals/
├── city_renderer.gd      — CityLayout → rebuild scene tree (replaces city_generator's mesh code)
├── agent_renderer.gd     — Agent[] → GLB instances, proxy visuals (replaces inlined code)
├── speech_bubble.gd      — Conversation signal → screen-space UI (autoload)
└── environment.gd        — TimeOfDay + Weather → Sun/Environment node (already clean)
```

Visuals are **stateless** — they read data and create/destroy nodes. No logic beyond "what mesh goes where."

### Data Flow

```
Config → CityGenerator → CityLayout
                               │
                    ┌──────────┼──────────┐
                    │          │          │
            CityVisualizer  Navigation  SaveToDisk
                    │          │
              Scene Nodes    Walk Queries
                    │          │
              (rendered)   PedestrianMover
                              │
                         Agent[] → AgentRenderer
                              │
                    ConversationMachine ← Interaction
                              │
                         SpeechBubble (UI)
```

### Key Design Decisions

1. **CityLayout as a Resource** — Can be saved to `.res` files. City seed + layout data in one package. Share cities by sending the file.

2. **No magic strings for pedestrian state** — Use typed dictionaries with constants or small classes. `AgentState` has: `position`, `target`, `speed`, `mode`, `pause_time`, `conversation_id`.

3. **Navigation as a query interface** — `CityLayout` stores walk areas. `NavigationSystem` answers "can I walk from X to Y?" and "give me a random walk target near X." No pathfinding graph needed for this style of game (direct wandering).

4. **Conversation as a state machine** — Three states: `idle`, `talking` (with sub-states: awaiting_llm, line_display), `done`. Emits `conversation_started(speaker_a, speaker_b)`, `line_changed(speaker, text)`, `conversation_ended()`. UI subscribes to these signals — no polling.

5. **Population simulation as a tick-based system** — Hours advance, mood updates, relationships decay. The visual crowd reads the current state when spawning — no need to keep them in sync every frame.

6. **Agent count decoupled from population size** — You can have 500 residents but only 40 visible pedestrians. The spawner picks the most "interesting" ones (high sociability, active mood, near player).

### Migration Path

Not a rewrite — an extraction:

1. Create `CityLayout` class, extract pure data from `city_generator.gd:generate_city()`
2. Move mesh creation to `CityVisualizer`, feed from CityLayout
3. Create `AgentState` class, migrate `_pedestrians` array
4. Extract navigation queries from `city_generator.gd` into `NavigationSystem`
5. Keep existing conversation code but make it signal-based
6. One system at a time, tests at each step

### Performance Characteristics

- **CityLayout** — ~10KB memory for 8×8 city (pure floats/ints)
- **CityVisualizer** — Same node count as now, but can use MultiMesh more aggressively
- **Navigation queries** — O(n) walk areas, O(1) with spatial hash
- **Conversation machine** — O(c) where c = active conversations (<=3)
- **Pedestrian mover** — O(p) where p = visible pedestrians (40-60), sliceable

The architecture makes performance bottlenecks obvious: if pedestrian movement is slow, optimize `pedestrian_mover.gd` without touching conversation or rendering code.

## Data Persistence Tiers

Data is categorized by how often it changes, which determines save/load strategy:

### Tier 1 — Invariant (generated once, never changes)
```
CityLayout
├── grid_size, block_size, street_width
├── road segments, intersection positions
├── block positions, heights, districts
├── building slots (positions, types, sizes)
└── walk areas (nav mesh, never moves)
```
**Save/load:** One .res file, written once when city is generated. Read on every load.

### Tier 2 — Slowly Variant (changes hourly/daily)
```
Population Data (Person[])
├── identity (name, age, job) — changes yearly
├── traits (openness, sociability, energy) — permanent after birth
├── relationships (spouse, children, bonds) — changes on life events
├── household/building assignment — changes on move
├── mood, habits — daily cycle
└── alive/dead — changes on death
```
**Save/load:** Snapshot every N game-days or on quit. ~50KB for 300 residents.

### Tier 3 — Rapidly Variant (changes every frame, never saved)
```
Simulation State
├── pedestrian positions, targets, speeds
├── active conversations, dialogue lines
├── current activities and motivations
├── event effects, crowd state
└── camera position, UI state
```
**Save/load:** None. Reconstructed from Tier 1 + Tier 2 on load. Pedestrians re-spawn at their home/work/social destinations based on current time and mood.

### Why This Matters

- **Loading a save**: Load CityLayout (instant), load Population array (fast), reconstruct pedestrians from their current activities (driven by time-of-day + traits + mood). No need to save where every NPC was standing.
- **Headless simulation**: Tier 1 + Tier 2 can be loaded without any visuals. Run 1000 days of simulation, save, then load with full visuals.
- **Testing**: Each tier is independently testable.
