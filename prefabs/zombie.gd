extends CharacterBody2D

# --- tunables ---
@export var SPEED: float = 25.0
@export var attack_distance: float = 20.0
@export var attack_damage: int = 1
@export var attack_duration: float = 0.3    # fallback length (not required when using animation end)
@export var idle_after_attack: float = 0.5  # idle pause after each attack
@export var player_path: NodePath = NodePath()   # optional explicit player path
@export var sprite_faces_right: bool = true

# which frames (1-based in the inspector) are the hit frames of the Attack animation
@export var attack_hit_frame_start: int = 3
@export var attack_hit_frame_end: int = 5

# --- health / stun / knockback ---
@export var health: int = 3
@export var stun_seconds: float = 0.2
@export var hit_flash_seconds: float = 0.15
@export var kb_strength: float = 200.0        # knockback (x) applied to this enemy when damaged
@export var player_kb_strength: float = 120.0 # knockback (x) applied to player when hit

# --- nodes / runtime ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_area: Area2D = $DamageArea
var _player: Node = null

var _cooldown_timer: float = 0.0
var _attacking: bool = false

var _stun_timer: float = 0.0
var _alive: bool = true

# store original local offset & scale so we can flip reliably
var _damage_area_original_offset: Vector2 = Vector2.ZERO
var _damage_area_original_scale: Vector2 = Vector2.ONE

# capture facing at the start of an attack to avoid flipping mid-attack
var _attack_facing_right: bool = true

func _ready() -> void:
	# prefer explicit player_path, otherwise search the "player" group
	if player_path != NodePath():
		_player = get_node_or_null(player_path)
	if not _player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]
	# helpful debug when player still missing
	if not _player:
		printerr("Enemy: couldn't find player. Set player_path or add player to 'player' group.")

	if damage_area:
		damage_area.monitoring = false
		damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
		_damage_area_original_offset = damage_area.position
		_damage_area_original_scale = damage_area.scale

	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_anim_finished)
		# use frame_changed to toggle the damage area during attack frames
		animated_sprite.frame_changed.connect(Callable(self, "_on_sprite_frame_changed"))


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	# stun handling
	if _stun_timer > 0.0:
		_stun_timer = max(_stun_timer - delta, 0.0)

		velocity.x = move_toward(velocity.x, 0.0, 1200 * delta)
		_play("Idle")
		move_and_slide()
		return

	# cooldown timer handling
	if _cooldown_timer > 0.0:
		_cooldown_timer = max(_cooldown_timer - delta, 0.0)

	# gravity (keep vertical behavior)
	if not is_on_floor():
		velocity += ProjectSettings.get_setting("physics/2d/default_gravity_vector") \
					* ProjectSettings.get_setting("physics/2d/default_gravity") * delta

	# no player -> idle
	if not _player:
		_play("Idle")
		move_and_slide()
		return

	# compute direction to player
	var to_player = _player.global_position - global_position
	var dist = to_player.length()

	# facing: use captured facing during attack so it doesn't change mid-attack
	var facing_right: bool
	if _attacking:
		facing_right = _attack_facing_right
	else:
		facing_right = to_player.x < 0.0

	if animated_sprite:
		if sprite_faces_right:
			animated_sprite.flip_h = not facing_right
		else:
			animated_sprite.flip_h = facing_right

	# flip/move damage area reliably (position + scale)
	if damage_area:
		damage_area.position.x = abs(_damage_area_original_offset.x) * (1 if facing_right else -1)
		damage_area.position.y = _damage_area_original_offset.y
		damage_area.scale.x = abs(_damage_area_original_scale.x) * (1 if facing_right else -1)
		damage_area.scale.y = _damage_area_original_scale.y

	# if currently attacking, don't chase / start a new attack — finish animation first
	if _attacking:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 12)
		move_and_slide()
		return

	# behavior: attack if close (and not already attacking/cooling), otherwise chase
	if dist <= attack_distance and not _attacking and _cooldown_timer <= 0.0:
		_start_attack()
	elif dist > attack_distance:
		# chase
		velocity.x = sign(to_player.x) * SPEED
		_play("Walk")
	else:
		# inside attack distance but in cooldown/attack: slow to stop
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 8)

	move_and_slide()


func _start_attack() -> void:
	_attacking = true
	# capture facing at start of attack so we don't flip mid-attack
	if _player:
		_attack_facing_right = (_player.global_position.x < global_position.x)
	else:
		_attack_facing_right = (not animated_sprite.flip_h) if sprite_faces_right else animated_sprite.flip_h

	# don't enable damage_area here — frame_changed handler will manage hit frames
	_play("Attack")


# called by AnimatedSprite2D.frame_changed
func _on_sprite_frame_changed() -> void:
	if not _attacking:
		return

	if not animated_sprite or animated_sprite.animation != "Attack":
		if damage_area:
			damage_area.monitoring = false
		return

	var f := animated_sprite.frame
	var start_idx = max(0, attack_hit_frame_start - 1)  # convert 1-based inspector to 0-based
	var end_idx = max(start_idx, attack_hit_frame_end - 1)
	if damage_area:
		damage_area.monitoring = (f >= start_idx and f <= end_idx)


# called by AnimatedSprite2D.animation_finished
func _on_anim_finished() -> void:
	# when the attack animation finishes, finish the attack lifecycle
	if not animated_sprite:
		return

	_attacking = false
	_disable_damage_area()
	_cooldown_timer = idle_after_attack
	_play("Idle")
	# keep original die behaviour: free when Die animation finishes
	if animated_sprite.animation == "Die":
		queue_free()


func _disable_damage_area() -> void:
	if damage_area:
		damage_area.monitoring = false


func _on_damage_area_body_entered(body: Node) -> void:
	if not body:
		return
	# only damage player
	var is_player_body := body == _player or (body.has_method("is_in_group") and body.is_in_group("player"))
	if not is_player_body:
		return

	# prefer single-call API: take_damage(amount, source_pos, knockback_strength)
	if body.has_method("take_damage"):
		# pass enemy global_position so the target can compute direction
		body.call("take_damage", attack_damage, global_position, player_kb_strength)
	else:
		# fallback: apply damage via other methods/properties
		if body.has_method("apply_damage"):
			body.call("apply_damage", attack_damage)
		elif "health" in body:
			body.health = max(0, int(body.health) - int(attack_damage))

		# if the fallback target is a CharacterBody2D and supports impulses, apply knockback once
		if body is CharacterBody2D and body.has_method("add_impulse"):
			var kb_dir_x = sign(body.global_position.x - global_position.x)
			if kb_dir_x == 0:
				kb_dir_x = 1
			body.call("add_impulse", Vector2(kb_dir_x * player_kb_strength, 0))


func take_damage(amount: int = 1, source_pos: Vector2 = Vector2.ZERO, knockback_strength: float = -1.0) -> void:
	if not _alive:
		return

	health -= amount

	# apply stun and visual flash
	_stun_timer = stun_seconds
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5)
	var t = get_tree().create_timer(hit_flash_seconds)
	t.timeout.connect(Callable(self, "_restore_color"))

	# compute horizontal-only knockback to this enemy (preserve vertical velocity)
	var dir_x: float = 0.0
	if source_pos != Vector2.ZERO:
		dir_x = sign(global_position.x - source_pos.x)
		if dir_x == 0:
			dir_x = 1
	else:
		# fallback: push backwards based on facing
		if animated_sprite and (animated_sprite.flip_h == sprite_faces_right):
			dir_x = -1
		else:
			dir_x = 1

	var used_kb =  knockback_strength if (knockback_strength > 0.0) else kb_strength
	velocity.x = dir_x * used_kb

	# if dead now, play death
	if health <= 0:
		_die()


func _restore_color() -> void:
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 1)


func _die() -> void:
	_alive = false
	_disable_damage_area()
	velocity = Vector2.ZERO
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Die"):
		_play("Die")
	else:
		queue_free()


func _play(_name: String) -> void:
	if not animated_sprite:
		return
	if animated_sprite.animation == _name:
		return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(_name):
		animated_sprite.play(_name)
