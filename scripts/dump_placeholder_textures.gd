extends SceneTree
## Headless entry that regenerates every procedural placeholder texture
## and writes them to disk as PNGs so artists can edit them directly.
##
## Invoke from PowerShell:
##   godot --headless -s scripts/dump_placeholder_textures.gd
##
## Or use the wrapper: scripts/dump_placeholder_textures.ps1


const _OUTPUT_DIR := "res://assets/images/placeholders"


func _init() -> void:
	print("=== dump_placeholder_textures ===")

	var abs_dir := ProjectSettings.globalize_path(_OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var entries: Array = [
		{
			"name": "terrain_interior_atlas.png",
			"texture": PlaceholderTerrainTextures.make_interior_atlas(),
		},
		{
			"name": "terrain_surface_atlas.png",
			"texture": PlaceholderTerrainTextures.make_surface_atlas(),
		},
		{
			"name": "terrain_damage_tier_atlas.png",
			"texture": PlaceholderTerrainTextures.make_damage_tier_atlas(),
		},
		{
			"name": "parallax_far.png",
			"texture": PlaceholderParallaxTextures.make_far(),
		},
		{
			"name": "parallax_mid.png",
			"texture": PlaceholderParallaxTextures.make_mid(),
		},
		{
			"name": "parallax_near.png",
			"texture": PlaceholderParallaxTextures.make_near(),
		},
	]

	var had_error := false
	for entry in entries:
		var out_path: String = _OUTPUT_DIR + "/" + entry["name"]
		var texture: ImageTexture = entry["texture"]
		var image := texture.get_image()
		# Damage atlas is L8; expand to RGBA8 so Aseprite / most editors
		# can open it without complaining about single-channel format.
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		var abs_path := ProjectSettings.globalize_path(out_path)
		var err := image.save_png(abs_path)
		if err != OK:
			printerr("Failed to save %s: %s" % [out_path, err])
			had_error = true
			continue
		print("Saved %s (%dx%d)"
				% [out_path, image.get_width(), image.get_height()])

	quit(1 if had_error else 0)
