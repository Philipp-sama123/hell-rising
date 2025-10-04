extends Area2D

signal hit(target)
signal died()

@export var speed: float = 800.0
@export var damage: int = 1
@export var lifetime: float = 4.0    # seconds before auto-free
@export var collision_ignore_owner: bool = true

# runtime
var velocity: Vector2 = Vector2.ZERO
var owner_id: int = 0   # set to shooter's get_instance_id() to ignore self-collisions
var _dying: bool = false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

func _ready() -> void:
	# connect signals (defensive)
	if anim:
		anim.animation_finished.connect(_on_anim_finished)
	if lifetime_timer:
		lifetime_timer.one_shot = true
		lifetime_timer.wait_time = lifetime
		lifetime_timer.connect("timeout", Callable(self, "_on_lifetime_timeout"))
		lifetime_timer.start()
	connect("body_entered", Callable(self, "_on_body_entered"))

	# play flight animation if present
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("Loop"):
		anim.play("Loop")

func _physics_process(delta: float) -> void:
	if _dying:
		return
	# simple Euler movement — keeps Area2D colliding via signals
	global_position += velocity * delta

func set_velocity(v: Vector2) -> void:
	velocity = v

func set_direction(dir: Vector2, spd: float = -1.0) -> void:
	if spd > 0:
		velocity = dir.normalized() * spd
	else:
		velocity = dir.normalized() * speed

# renamed method to avoid overriding Node.set_owner()
func set_shooter_owner(node: Node) -> void:
	if node:
		owner_id = node.get_instance_id()

func _on_body_entered(body: Node) -> void:
	if _dying:
		return

	# ignore owner or other bullets (optional)
	if collision_ignore_owner and body and body.get_instance_id() == owner_id:
		return

	# ignore other bullets (optional) - check for Group "bullet" or class - adjust to taste
	if body.is_in_group("bullet"):
		return

	# deliver damage if target supports it
	#if body and body.has_method("take_damage"):
		# try to call with damage; be forgiving if signature differs
	#	body.callv("take_damage", [damage])
	emit_signal("hit", body)

	# trigger explode / cleanup
	_explode()

func _explode() -> void:
	_dying = true
	velocity = Vector2.ZERO
	# stop lifetime timer (we'll free after explode)
	if lifetime_timer:
		lifetime_timer.stop()
	# play explode animation if present, otherwise free immediately
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("Explode"):
		anim.play("Explode")
	else:
		emit_signal("died")
		queue_free()

func _on_anim_finished() -> void:
	# when explode animation finishes -> free
	if anim and anim.animation == "Explode":
		emit_signal("died")
		queue_free()

func _on_lifetime_timeout() -> void:
	# lifetime ended, just free (optionally play an expire animation)
	if not _dying:
		_explode()
