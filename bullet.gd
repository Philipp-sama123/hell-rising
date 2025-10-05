extends Area2D

signal hit(target)
signal died()

@export var speed: float = 200.0
@export var damage: int = 1
@export var lifetime: float = 4.0
@export var collision_ignore_owner: bool = true
@export var sprite_faces_right: bool = false

# runtime
var velocity: Vector2 = Vector2.ZERO
var owner_id: int = 0
var _dying: bool = false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

func _ready() -> void:
	# connect signals defensively
	if anim:
		anim.animation_finished.connect(_on_anim_finished)
	if lifetime_timer:
		lifetime_timer.one_shot = true
		lifetime_timer.wait_time = lifetime
		lifetime_timer.connect("timeout", Callable(self, "_on_lifetime_timeout"))
		lifetime_timer.start()

	connect("body_entered", Callable(self, "_on_body_entered"))

	# play flight loop animation if present
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("Loop"):
		anim.play("Loop")

func _physics_process(delta: float) -> void:
	if _dying:
		return
		
	global_position += velocity * delta
	
	if anim and abs(velocity.x) > 0.1:
			if sprite_faces_right:
				# art faces right by default -> flip when moving left
				anim.flip_h = velocity.x < 0.0
			else:
				# art faces left by default -> flip when moving right
				anim.flip_h = velocity.x > 0.0
# Setters (public API used by spawn code)
func set_velocity(v: Vector2) -> void:
	velocity = v

func set_direction(dir: Vector2, spd: float = -1.0) -> void:
	if spd > 0.0:
		velocity = dir.normalized() * spd
	else:
		velocity = dir.normalized() * speed

# store shooter owner by instance id (avoid using Node.set_owner)
func set_shooter_owner(node: Node) -> void:
	if node:
		owner_id = node.get_instance_id()

func _on_body_entered(body: Node) -> void:
	if _dying:
		return

	# ignore owner / other bullets
	if collision_ignore_owner and body and body.get_instance_id() == owner_id:
		return

	if body.is_in_group("bullet"):
		return

	# deliver damage via signal (the caller can handle how to apply damage)
	emit_signal("hit", body)

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
