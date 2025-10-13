# Enemy.gd — attach to CharacterBody2D
extends CharacterBody2D

signal hit(body, damage)

@export var player_path: NodePath
@export var speed: float = 50.0
@export var chase_range: float = 300.0
@export var patrol_direction: Vector2 = Vector2.LEFT
@export var damage: int = 10

# visual + knockback
@export var explode_scale: float = 1.8
@export var explode_grow_time: float = 0.15
@export var knockback_strength: float = 200.0   # used for explosion and when this enemy is damaged
@export var debug: bool = false

# threshold to avoid flipping from tiny jitter
@export var facing_threshold: float = 1.0

# health / stun / flash
@export var health: int = 3                # 3 lives
@export var stun_seconds: float = 0.5

@onready var _player = get_node_or_null(player_path)
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var explosion_area: Area2D = $ExplosionArea

var _exploding: bool = false
var _stun_timer: float = 0.0


func _ready() -> void:
	if anim:
		anim.flip_h = false
		anim.scale.x = abs(anim.scale.x)
		anim.scale.y = abs(anim.scale.y)

	if explosion_area:
		explosion_area.monitoring = true
		explosion_area.body_entered.connect(_on_explosion_area_body_entered)
	
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("Fly"):
		anim.play("Fly")
		
	if anim:
		anim.animation_finished.connect(_on_anim_finished)


func _physics_process(_delta: float) -> void:
	# if exploding, freeze movement
	if _exploding:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# stun handling: highest priority (smooth decay)
	if _stun_timer > 0.0:
		_stun_timer = max(_stun_timer - _delta, 0.0)
		velocity = velocity.move_toward(Vector2.ZERO, 600 * _delta)
		move_and_slide()
		return

	# lazy resolve player if path provided but not found yet
	if player_path and not _player:
		_player = get_node_or_null(player_path)

	# chase or patrol
	if _player and is_instance_valid(_player):
		var to_player = _player.global_position - global_position
		if to_player.length() <= chase_range:
			velocity = to_player.normalized() * speed
		else:
			velocity = patrol_direction.normalized() * speed
	else:
		velocity = patrol_direction.normalized() * speed

	# facing based on horizontal velocity with threshold to avoid jitter
	if anim:
		if velocity.x > facing_threshold:
			anim.flip_h = true 
		elif velocity.x < -facing_threshold:
			anim.flip_h = false 

	move_and_slide()


func _on_explosion_area_body_entered(body: Node) -> void:
	if _exploding:
		return
	
	if (is_instance_valid(_player) and body == _player) or (body and body.is_in_group("player")):
		_start_explode()


func _start_explode() -> void:
	_exploding = true
	velocity = Vector2.ZERO

	if anim:
		var target = anim.scale * explode_scale
		var tw = create_tween()
		tw.tween_property(anim, "scale", target, explode_grow_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if anim.sprite_frames and anim.sprite_frames.has_animation("Explode"):
			anim.play("Explode")
	# ToDo: delay this
	_apply_damage()

	if not anim or not (anim.sprite_frames and anim.sprite_frames.has_animation("Explode")):
		queue_free()


func _apply_damage() -> void:
	if not explosion_area:
		return

	var bodies := explosion_area.get_overlapping_bodies()
	if debug:
		print("Explode overlap:", bodies)

	for b in bodies:
		if not b or b == self:
			continue

		# restrict to player or "player" group
		if is_instance_valid(_player):
			if b != _player and not b.is_in_group("player"):
				continue
		elif not b.is_in_group("player"):
			continue

		var applied := false

		# compute direction from explosion center to target (non-zero fallback)
		var dir_vec := (b.global_position - global_position)
		if dir_vec.length() == 0:
			dir_vec = Vector2.RIGHT
		dir_vec = dir_vec.normalized()

		# Prefer unified take_damage API: pass explosion center and scalar knockback
		if b.has_method("take_damage"):
			# pass explosion center as source_pos and scalar knockback_strength
			b.call("take_damage", damage, global_position, knockback_strength)
			applied = true
		elif b.has_method("apply_damage"):
			b.call("apply_damage", damage)
			# fall back to applying a full-vector impulse if supported
			if b.has_method("add_impulse"):
				b.call("add_impulse", dir_vec * knockback_strength)
			applied = true
		elif "health" in b:
			b.health = max(0, int(b.health) - int(damage))
			if b.has_method("add_impulse"):
				b.call("add_impulse", dir_vec * knockback_strength)
			applied = true

		if applied:
			emit_signal("hit", b, damage)
			if debug:
				print("Explode hit:", b, " dmg:", damage, " dir:", dir_vec, " kb:", knockback_strength)


func take_damage(amount: int = 1, source_pos: Vector2 = Vector2.ZERO, kb_override: float = -1.0) -> void:
	if _exploding:
		return

	# reduce health
	health = int(max(0, health - amount))

	# start stun timer
	_stun_timer = stun_seconds

	# flash sprite red and schedule restore
	if anim:
		anim.modulate = Color(1.0, 0.5, 0.5)
		var t = get_tree().create_timer(stun_seconds)
		t.timeout.connect(Callable(self, "_restore_color"))

	var dir_x: int = 0
	if source_pos != Vector2.ZERO:
		dir_x = int(sign(global_position.x - source_pos.x))
		if dir_x == 0:
			# fallback: use current motion if available, otherwise push opposite to facing
			if abs(velocity.x) > 0.1:
				dir_x = int(sign(velocity.x))
			else:
				if anim:
					# if anim.flip_h == true we consider the sprite facing right => push left (dir -1)
					dir_x = -1 if anim.flip_h else 1
				else:
					dir_x = 1
	else:
		# no source: hint from current motion or default right
		if abs(velocity.x) > 0.1:
			dir_x = int(sign(velocity.x))
		else:
			dir_x = 1

	if dir_x == 0:
		dir_x = 1

	var used_kb = (kb_override if kb_override > 0.0 else knockback_strength)

	velocity.x = dir_x * used_kb

	if debug:
		print("[enemy.take_damage] amt:", amount, " health:", health, " src:", source_pos, " dir_x:", dir_x, " kb:", used_kb, " vel.x:", velocity.x)

	# explode if dead
	if health <= 0:
		_start_explode()


func _restore_color() -> void:
	if anim:
		anim.modulate = Color(1, 1, 1)


func _on_anim_finished() -> void:
	if anim and anim.animation == "Explode":
		queue_free()
