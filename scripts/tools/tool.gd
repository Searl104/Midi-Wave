class_name Tool
extends RefCounted
## One tool on the toolbar. A subclass names itself, draws its icon and holds its operations.
## ToolManager passes it input events through handle_input().

var surface: WaveSurface


func _init(owner_surface: WaveSurface) -> void:
	surface = owner_surface


func tool_id() -> String:
	return ""


func title() -> String:
	return ""


## Which toolbar section it sits in.
func section() -> int:
	return 0


## True for tools that move the view: picking one doesn't change the mode or the selection.
func navigates() -> bool:
	return false


func cursor() -> Control.CursorShape:
	return Control.CURSOR_ARROW


## False for the tool that only plays: the layout is locked while it's in use.
func edits_layout() -> bool:
	return true


## Returns true if the event was used.
func handle_input(_event: InputEvent) -> bool:
	return false


func activate() -> void:
	pass


func deactivate() -> void:
	pass


## Picked again while already active.
func repick() -> void:
	pass


func draw_icon(_canvas: CanvasItem, _c: Vector2, _ink: Color) -> void:
	pass


## Drawn over the objects on the surface while this tool is active.
func draw_overlay(_canvas: WaveSurface) -> void:
	pass
