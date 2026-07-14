extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _start_dealing_phase() -> void:
	narration_box.say(tr("Cliquez sur la pile pour distribuer les mers."))
