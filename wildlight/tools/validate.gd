extends SceneTree
## Loads every script in the project so parse errors surface in CI, including
## the ones without a class_name that the class cache scan skips.
##
##   godot --headless --script res://tools/validate.gd


func _init() -> void:
	var files: Array[String] = []
	_walk("res://scripts", files)
	_walk("res://tools", files)
	var failed := 0
	for path in files:
		var script: Resource = load(path)
		if script == null:
			print("FAILED  ", path)
			failed += 1
	print("checked %d scripts, %d failed" % [files.size(), failed])
	quit(1 if failed > 0 else 0)


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
