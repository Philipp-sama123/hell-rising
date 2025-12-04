@tool
extends AnimatedSprite2D

@export var animation_to_play: String = ""

func _get_property_list() -> Array:
	var props: Array = []

	# get SpriteFrames safely
	var sf := sprite_frames
	if sf == null:
		sf = get_sprite_frames()

	if sf:
		var anims := sf.get_animation_names()
		var hint_string := ""

		if anims.size() > 0:
			# Convert PackedStringArray → Array → join
			hint_string = ",".join(Array(anims))

		props.append({
			"name": "animation_to_play",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": hint_string,
			"usage": PROPERTY_USAGE_DEFAULT
		})
	else:
		# When no sprite_frames assigned, fallback to text input
		props.append({
			"name": "animation_to_play",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_DEFAULT
		})

	return props


func _ready() -> void:
	# Don't auto-play in the editor
	if Engine.is_editor_hint():
		return
	if animation_to_play != "":
		play(animation_to_play)
