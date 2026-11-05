class_name UndoHistory
extends RefCounted
## Undo / redo over layout snapshots. Every edit goes through WaveSurface.save_notes(), which
## records the layout it replaced. Edits in one frame (a group edit) form one step, as do all the
## edits of an open stroke.

const LIMIT := 50

var _undo: Array = []              # layout snapshots, newest last
var _redo: Array = []
var _snapshot: Array = []          # the layout as of the last recorded edit
var _ready := false
var _restoring := false
var _last_frame := -1
var _stroke_open := false


## Remembers the layout an edit replaced so it can be undone.
func record(layout: Array) -> void:
	if _restoring or not _ready:
		return
	if JSON.stringify(layout) == JSON.stringify(_snapshot):
		return
	var frame := Engine.get_process_frames()
	if (frame != _last_frame and not (_stroke_open and _last_frame >= 0)) or _undo.is_empty():
		_undo.append(_snapshot)
		if _undo.size() > LIMIT:
			_undo.pop_front()
	_last_frame = frame
	_redo.clear()
	_snapshot = layout.duplicate(true)


## A layout is about to load: its edits aren't recorded.
func begin_load() -> void:
	_ready = false


## The load finished; `layout` is the new baseline. A fresh load (not undo) clears the history.
func end_load(layout: Array) -> void:
	if not _restoring:
		_undo.clear()
		_redo.clear()
	_snapshot = layout.duplicate(true)
	_ready = true
	_last_frame = -1


func begin_restore() -> void:
	_restoring = true


func end_restore() -> void:
	_restoring = false
	_last_frame = -1


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_steps() -> int:
	return _undo.size()


func redo_steps() -> int:
	return _redo.size()


## The layout to restore for an undo.
func step_back() -> Array:
	_redo.append(_snapshot)
	return _undo.pop_back()


## The layout to restore for a redo.
func step_forward() -> Array:
	_undo.append(_snapshot)
	return _redo.pop_back()


## Starts or ends a stroke: every edit until it ends is one undo step (a Draw drag).
func set_stroke(open: bool) -> void:
	_stroke_open = open
	if open:
		_last_frame = -1


## The next edit starts a new undo step even if it lands in the same frame.
func end_group() -> void:
	_last_frame = -1
