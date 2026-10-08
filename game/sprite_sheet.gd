class_name SpriteSheet
## Строит SpriteFrames из листа спрайтов: каждая строка листа это одна анимация,
## каждый столбец это кадр. Ничего настраивать в редакторе не нужно.
##
## anims: массив словарей {"name": "run", "frames": 4, "fps": 12.0, "loop": true}
## в том же порядке, в котором анимации идут сверху вниз в листе.


static func build(texture: Texture2D, frame_size: Vector2i, anims: Array) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")

	for row in anims.size():
		var info: Dictionary = anims[row]
		var anim_name := StringName(info["name"])
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, float(info.get("fps", 8.0)))
		frames.set_animation_loop(anim_name, bool(info.get("loop", true)))
		for col in range(int(info["frames"])):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
			frames.add_frame(anim_name, atlas)
	return frames
