class_name FolderRow
extends Button
## A folder in a FileTree. Click to open or close it.

var opened := false


func _init(folder: String, is_open: bool) -> void:
	opened = is_open
	text = "    " + folder
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	clip_text = true
	flat = true
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Shows or hides this folder."


func _draw() -> void:
	var c := Vector2(10, size.y / 2.0)
	var points := [c + Vector2(-4, -2.5), c + Vector2(4, -2.5), c + Vector2(0, 3.5)] if opened \
			else [c + Vector2(-2.5, -4), c + Vector2(3.5, 0), c + Vector2(-2.5, 4)]
	draw_colored_polygon(PackedVector2Array(points), Palette.TEXT_DIM)
