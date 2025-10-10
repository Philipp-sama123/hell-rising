extends CharacterBody2D

@export var player_path: NodePath
@export var speed: float = 50.0
@export var chase_range: float = 300.0
@export var patrol_direction: Vector2 = Vector2.LEFT
@export var damage: int = 10

# new tuning exports for scale effect
@export var explode_scale: float = 1.8
@export var explode_grow_time: float = 0.15

@onready var player = get_node_or_null(player_path)
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var cshape: CollisionShape2D = $CollisionShape2D

var _state := "idle"
var _vel := Vector2.ZERO

func _ready() -> void:
	if player_path and not player:
		player = get_node_or_null(player_path)

	# play Fly animation if present
	animated_sprite.play("Fly")

	# connect explode animation finish
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_sprite_animation_finished)

func _physics_process(delta: float) -> void:
	if player_path and not player:
		player = get_node_or_null(player_path)

	if player and is_instance_valid(player):
		var to_player = player.global_position - global_position
		var dist = to_player.length()

		if _state != "exploding":
			if dist <= 30:
				_start_explode()
			elif dist <= chase_range:
				_state = "chase"
				_vel = to_player.normalized() * speed
			else:
				_state = "idle"
				_vel = patrol_direction.normalized() * speed
	else:
		_state = "idle"
		_vel = patrol_direction.normalized() * speed

	if _state == "exploding":
		_vel = Vector2.ZERO

	velocity = _vel
	move_and_slide()

func _start_explode() -> void:
	if _state == "exploding":
		return
	_state = "exploding"
	_vel = Vector2.ZERO

	# grow the sprite using a Tween while the explode animation plays
	var base_scale = animated_sprite.scale
	var target_scale = base_scale * explode_scale
	# create a quick tween (Godot 4)
	var tw = create_tween()
	tw.tween_property(animated_sprite, "scale", target_scale, explode_grow_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# play explode animation and apply damage (if desired)
	animated_sprite.play("Explode")
	_apply_damage_to_player()

func _apply_damage_to_player() -> void:
	print("--- DEBUG --- _apply_damage_to_player")
	# add actual damage calls here if you want:
	# if player and is_instance_valid(player) and player.has_method("take_damage"):
	#     player.take_damage(damage)

func _on_sprite_animation_finished() -> void:
	var a = animated_sprite.animation
	if a == "Explode":
		queue_free()
