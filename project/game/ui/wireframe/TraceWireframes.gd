@tool
extends EditorScript

## Re-traces the frame readout outlines from the wireframe sprites.
## Open this script and use File > Run (Ctrl+Shift+X). Only needed when
## the sprites change; the result is saved next to this script.

const OUTPUT := "res://game/ui/wireframe/wireframe_outlines.tres"


func _run() -> void:
	var outlines := WireframeTracer.trace_all()
	var err := ResourceSaver.save(outlines, OUTPUT)
	if err == OK:
		print("Traced %d outlines into %s" % [outlines.parts.size(), OUTPUT])
	else:
		push_error("Couldn't save %s (error %d)" % [OUTPUT, err])
