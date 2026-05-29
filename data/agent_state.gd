extends RefCounted
class_name AgentState

## ECS Component: the runtime state of a visible pedestrian agent.
## Tier 3 data — rapidly variant, never persisted.

var entity_id: int = -1        # Links to Person.id in population data
var ped_index: int = -1        # Index in the agent array
var type: String = "person"    # "person", "dog"
var mode: String = "wander"    # Current activity mode
var motivation: String = ""    # Why they're doing this
var goal: String = ""          # What they're trying to achieve
var target: Vector3            # Where they're walking to
var speed: float = 1.0         # Current walk speed
var pause_time: float = 0.0    # Seconds remaining in current pause
var stuck_time: float = 0.0    # Seconds without meaningful movement
var player_lock_time: float = 0.0  # Seconds locked to player interaction
var speech_cooldown: float = 0.0   # Seconds until can speak again
var meet_cooldown: float = 0.0     # Seconds until can meetup again
var group_role: String = "solo"    # "solo", "leader", "follower"
var group_kind: String = ""    # "social", "family", "meetup"
var social_group_id: int = -1
var initiative: String = "self" # What initiated current behavior
var root: Node3D = null        # Scene node (visual layer bridge)
var visual: Node3D = null      # Visual instance (proxy or GLB)


func reset() -> void:
	entity_id = -1
	ped_index = -1
	type = "person"
	mode = "wander"
	motivation = ""
	goal = ""
	target = Vector3.ZERO
	speed = 1.0
	pause_time = 0.0
	stuck_time = 0.0
	player_lock_time = 0.0
	speech_cooldown = 0.0
	meet_cooldown = 0.0
	group_role = "solo"
	group_kind = ""
	social_group_id = -1
	initiative = "self"
	root = null
	visual = null


## Convert to Dictionary for backward compatibility with existing code
func to_dict() -> Dictionary:
	return {
		"entity_id": entity_id,
		"ped_index": ped_index,
		"type": type,
		"mode": mode,
		"motivation": motivation,
		"goal": goal,
		"target": target,
		"speed": speed,
		"pause_time": pause_time,
		"stuck_time": stuck_time,
		"player_lock_time": player_lock_time,
		"speech_cooldown": speech_cooldown,
		"meet_cooldown": meet_cooldown,
		"group_role": group_role,
		"group_kind": group_kind,
		"social_group_id": social_group_id,
		"initiative": initiative,
		"root": root,
		"visual": visual,
		"identity": {}  # filled by caller
	}
