## Base payload for commands emitted by `CommandSystem` and consumed by
## `CommandReceiver` adapters.
##
## Concrete command types should set `type` in their constructor and expose the
## normalized input values their matching receiver understands.
class_name Command

extends RefCounted

enum Type {
	NONE,
	ENGINE,
}

## Lightweight discriminator for generic receivers/debug logging. Receivers
## should still prefer type-safe checks such as `command is EngineCommand`.
var type: Type = Type.NONE
