extends SceneTree

func _init() -> void:
	print("has G singleton? ", Engine.has_singleton("G"))
	print("get_singleton G: ", Engine.get_singleton_list())
	# Try accessing G directly.
	var ok := false
	if ClassDB.class_exists("G"):
		ok = true
	print("ClassDB has G: ", ok)
	print("root node list: ", get_root().get_children())
	quit(0)
