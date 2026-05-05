## Runtime display data exposed by a selectable scene.
##
## Producers own the contents and update cadence. UI consumers should treat
## `info` as read-only presentation data and handle missing keys gracefully.
class_name Selectable3DInfo

extends Node

## Key/value fields shown for the current selection.
var info: Dictionary[String, Variant] = {}
