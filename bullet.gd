extends Area2D

signal hit(target, damage)
signal died()

@export var speed: float = 200.0
@export var damage: int = 1
@export var lifetime: float = 4.0
@export var collision_ignore_owner: bool = true

# If true, the bullet will rotate to face its direction (recommended).
@export var rotate_bullet: bool = true

# Set this to true if your art faces RIGHT by default; false if it faces LEFT.
# If your sprite art points up by default, set rotate_bullet = true and adjust orient_offset below if necessary.
@export var sprite_faces_right: bool = false

@export var knockback_strength: float = 150.0

# runtime
var velocity: Vector2 = Vector2.ZERO
var owner_id: int = 0
var _dying: bool = false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

func _ready() -> void:
	if anim:
		anim.animation_finished.connect(_on_anim_finished)
	if lifetime_timer:
		lifetime_timer.one_shot = true
		lifetime_timer.wait_time = lifetime
		lifetime_timer.connect("timeout", Callable(self, "_on_lifetime_timeout"))
		lifetime_timer.start()

	connect("body_entered", Callable(self, "_on_body_entered"))

	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("Loop"):
		anim.play("Loop")

	# Apply rotation to ensure immediate correct facing (in case set_direction was called earlier)
	_apply_rotation_from_velocity()

func _physics_process(delta: float) -> void:
	if _dying:
		return

	global_position += velocity * delta

	# keep visual matched to velocity
	_apply_rotation_from_velocity()

# API
func set_velocity(v: Vector2) -> void:
	velocity = v
	_apply_rotation_from_velocity()

func set_direction(dir: Vector2, spd: float = -1.0) -> void:
	if spd > 0.0:
		velocity = dir.normalized() * spd
	else:
		velocity = dir.normalized() * speed
	_apply_rotation_from_velocity()

func set_shooter_owner(node: Node) -> void:
	if node:
		owner_id = node.get_instance_id()

# collisions
func _on_body_entered(body: Node) -> void:
	if _dying:
		return

	if collision_ignore_owner and body and body.get_instance_id() == owner_id:
		return
	if body.is_in_group("bullet"):
		return

	if body and body.has_method("take_damage"):
		body.take_damage(damage, global_position, knockback_strength)

	emit_signal("hit", body, damage)
	_explode()

func _explode() -> void:
	_dying = true
	velocity = Vector2.ZERO
	if lifetime_timer:
		lifetime_timer.stop()
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("Explode"):
		anim.play("Explode")
	else:
		emit_signal("died")
		queue_free()

func _on_anim_finished() -> void:
	if anim and anim.animation == "Explode":
		emit_signal("died")
		queue_free()

func _on_lifetime_timeout() -> void:
	if not _dying:
		_explode()

# ---------- rotation helper ----------
func _apply_rotation_from_velocity() -> void:
	# nothing to do if no movement
	if velocity.length() <= 0.001:
		return

	var ang := velocity.angle()
	# orient_offset: if your sprite art faces RIGHT by default, orient_offset = 0.
	# if art faces LEFT by default, orient_offset = PI (180°).
	var orient_offset := 0.0
	if not sprite_faces_right:
		orient_offset = PI

	# If we rotate the whole Area2D, child nodes (sprite, collisions) will visually rotate.
	# That's simple and ensures the sprite faces the velocity instantly even before anim onready ran.
	if rotate_bullet:
		rotation = ang + orient_offset
		# reset sprite local rotation/flipping so it doesn't double-rotate
		if anim:
			anim.rotation = 0.0
			anim.flip_h = false
	else:
		# Legacy horizontal-only mode: don't rotate area, use flip instead
		rotation = 0.0
		if anim:
			anim.rotation = 0.0
			if abs(velocity.x) > 0.1:
				if sprite_faces_right:
					anim.flip_h = velocity.x < 0.0
				else:
					anim.flip_h = velocity.x > 0.0
