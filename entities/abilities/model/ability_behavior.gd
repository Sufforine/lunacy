extends Resource
class_name AbilityBehavior

## Executed only by the host after the controller has validated an activation.
## Keep this resource stateless. Spawn runtime nodes for projectiles/channels, etc.
## The context contains controller, actor, weapon, ability and activation serial.
func execute(_context: Dictionary) -> void:
	pass


## Called on every peer when the host confirms activation. Cosmetic effects only.
## Runtime nodes can listen to controller.activation_cancelled for cleanup.
func present(_context: Dictionary) -> void:
	pass
