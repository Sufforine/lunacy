extends Resource
class_name AbilityDefinition

enum AnimationLayer { FULL_BODY, UPPER_BODY }
enum InterruptReason { MOVEMENT = 1, JUMP = 2, DAMAGE = 4 }

## Shared, immutable configuration. Runtime state belongs to AbilityController.
@export var id: StringName
@export var title: String = ""
@export var icon: Texture2D
@export var animation: Animation
@export_range(0.0, 60.0) var cooldown: float = 0.8
@export_range(0.0, 10.0) var effect_delay: float = 0.3
## 0 uses the clip length; a positive value overrides gameplay duration.
## Hit timing is always host-timed, never driven by client animation callbacks.
@export_range(0.0, 10.0) var duration: float = 0.0
@export_range(0, 10000) var mana_cost: int = 0
@export var requires_grounded: bool = true
@export var behavior: AbilityBehavior
@export_group("Animation and movement")
## Upper body preserves locomotion below Spine; full body replaces the pose.
@export var animation_layer: AnimationLayer = AnimationLayer.FULL_BODY
## Applies during both ordinary and held actions. Zero stops controlled movement,
## but gravity and external impulses continue to move the physical body.
@export_range(0.0, 1.0) var movement_multiplier: float = 1.0
@export var allow_sprint: bool = false
@export_group("Interrupts")
## System transitions such as death, loading and equipment changes always cancel.
## These flags describe ordinary gameplay events which may cancel the action.
@export_flags("Movement", "Jump", "Damage") var interrupt_flags: int = InterruptReason.JUMP | InterruptReason.DAMAGE
@export_range(0.0, 10.0, 0.05) var movement_interrupt_speed: float = 0.2
@export_group("Held action")
## Hold the secondary input to maintain a guard. No repeated activation cost.
@export var held: bool = false
@export_range(0.0, 0.95) var physical_damage_reduction: float = 0.0


func is_valid() -> bool:
	return id != &"" and (held or behavior != null) and effect_delay >= 0.0


func get_duration() -> float:
	var authored_duration := duration
	if authored_duration <= 0.0:
		authored_duration = animation.length if animation != null else 0.8
	return maxf(authored_duration, effect_delay + 0.05)


func get_animation_speed() -> float:
	if animation == null:
		return 1.0
	return animation.length / maxf(get_duration(), 0.001)


func is_interrupted_by(reason: int) -> bool:
	return (interrupt_flags & reason) != 0
