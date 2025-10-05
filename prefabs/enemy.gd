extends CharacterBody2D

signal shoot

@export var SPEED: float = 50.0
@export var detection_range: float = 800.0
@export var stop_min: float = 10.0
@export var stop_max: float = 50.0
@export var shoot_cooldown: float = 1.0
@export var bullet_speed: float = 300.0
@export var muzzle_node_path: NodePath = NodePath("Muzzle")
@export var player_path: NodePath = NodePath()
@export var bullet_scene: PackedScene

@export var sprite_faces_right: bool = true
@export var extra_hold_seconds: float = 2.0
@export var default_shoot_anim_duration: float = 0.5

# health + stun
@export var health: int = 3
@export var hit_flash_seconds: float = 2.0
@export var stun_seconds: float = 0.4

# NEW: how quickly horizontal velocity decays while stunned (pixels/sec^2-ish)
@export var STUN_DECAY: float = 400.0

# animation names (tweak to match your SpriteFrames)
const ANIM_RUN_GUN = "RunGun"
const ANIM_IDLE_GUN = "IdleGun"
const ANIM_RUN = "Run"
const ANIM_IDLE = "Idle"
const ANIM_SHOOT = "Shoot"
const ANIM_EXPLODE = "Explode"

# runtime
var _player: Node = null
var _muzzle: Node2D = null
var _stop_distance: float = 20.0
var _shoot_timer: float = 0.0
var _alive: bool = true
var _is_shoot_anim: bool = false
var _hold_timer: float = 0.0

# stun timer (stops AI movement briefly when hit)
var _stun_timer: float = 0.0

# --- muzzle original transforms (for flipping)
var _muzzle_offset: Vector2 = Vector2.ZERO
var _muzzle_original_rotation: float = 0.0
var _muzzle_scale_abs: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	# resolve player: inspector -> common node names -> group
	if player_path != NodePath():
		_player = get_node_or_null(player_path)

	if not _player:
		var root = get_tree().get_root()
		_player = root.find_node("Player", true, false) or root.find_node("player", true, false)

	if not _player:
		var candidates = get_tree().get_nodes_in_group("player")
		if candidates.size() > 0:
			_player = candidates[0]

	if not _player:
		printerr("Enemy: couldn't find a player node. Set player_path or add player to 'player' group.")

	_muzzle = get_node_or_null(muzzle_node_path)
	# record muzzle original local transform so we can mirror reliably
	if _muzzle and _muzzle is Node2D:
		_muzzle_offset = (_muzzle as Node2D).position
		_muzzle_original_rotation = (_muzzle as Node2D).rotation
		_muzzle_scale_abs = abs((_muzzle as Node2D).scale.x)

	# randomize stopping distance
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	_stop_distance = rng.randf_range(stop_min, stop_max)

	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_anim_finished)

func _physics_process(delta: float) -> void:
	if not _alive:
		return

	# stun handling (highest priority)
	if _stun_timer > 0.0:
		_stun_timer = max(_stun_timer - delta, 0.0)
		# DON'T immediately zero horizontal velocity — let impulse carry it.
		# Instead apply a decay so velocity slows smoothly while stunned.
		velocity.x = move_toward(velocity.x, 0.0, STUN_DECAY * delta)

		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_IDLE_GUN):
			_play_anim(ANIM_IDLE_GUN)
		else:
			_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# timers
	if _shoot_timer > 0.0:
		_shoot_timer = max(_shoot_timer - delta, 0.0)

	if _hold_timer > 0.0:
		_hold_timer = max(_hold_timer - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_IDLE_GUN):
			_play_anim(ANIM_IDLE_GUN)
		else:
			_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# gravity
	if not is_on_floor():
		velocity += ProjectSettings.get_setting("physics/2d/default_gravity_vector") * ProjectSettings.get_setting("physics/2d/default_gravity") * delta

	# no player -> idle
	if not _player:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	var to_player = _player.global_position - global_position
	var dist_x = abs(to_player.x)

	# face player (supports sprite_faces_right)
	if animated_sprite:
		var player_left = _player.global_position.x < global_position.x
		animated_sprite.flip_h = (player_left != sprite_faces_right)

		# mirror muzzle after sprite flip so muzzle stays on the correct side
		_update_muzzle_flip(animated_sprite.flip_h)

	# out of detection range -> idle
	if dist_x > detection_range:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# approach until within stop distance (horizontal)
	if dist_x > _stop_distance + 1.0:
		var dir_x = sign(to_player.x)
		velocity.x = dir_x * SPEED
		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_RUN_GUN):
			if not _is_shoot_anim:
				_play_anim(ANIM_RUN_GUN)
		else:
			if not _is_shoot_anim:
				_play_anim(ANIM_RUN)
	else:
		# stop and prepare to shoot
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if not _is_shoot_anim:
			if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_IDLE_GUN):
				_play_anim(ANIM_IDLE_GUN)
			else:
				_play_anim(ANIM_IDLE)

		# fire when cooldown ready and not already mid-shoot and not holding
		if _shoot_timer <= 0.0 and not _is_shoot_anim and _hold_timer <= 0.0:
			_do_shoot()

	move_and_slide()

# helper to mirror muzzle transform
func _update_muzzle_flip(flipped: bool) -> void:
	if not _muzzle or not (_muzzle is Node2D):
		return
	var m := _muzzle as Node2D
	# mirror local X offset using the recorded original offset (avoids cumulative multiplications)
	m.position.x = _muzzle_offset.x * ( -1 if flipped else 1 )
	# mirror rotation so muzzle angle looks mirrored when flipped
	m.rotation = _muzzle_original_rotation * ( -1 if flipped else 1 )
	# ensure scale magnitude is preserved and sign follows flip
	m.scale.x = _muzzle_scale_abs * ( -1 if flipped else 1 )

func _do_shoot() -> void:
	_shoot_timer = shoot_cooldown

	# play shoot anim if present and compute hold time
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_SHOOT):
		_is_shoot_anim = true
		animated_sprite.frame = 0
		animated_sprite.play(ANIM_SHOOT)

		# best-effort compute anim duration
		var anim_duration = default_shoot_anim_duration
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_SHOOT):
			if animated_sprite.sprite_frames.has_method("get_frame_count"):
				var fc = animated_sprite.sprite_frames.get_frame_count(ANIM_SHOOT)
				var sp = 1.0
				if "speed" in animated_sprite:
					sp = max(animated_sprite.speed, 0.001)
				elif animated_sprite.has_method("get_speed"):
					sp = max(animated_sprite.get_speed(), 0.001)
				if fc > 0:
					anim_duration = float(fc) / sp
		_hold_timer = anim_duration + extra_hold_seconds
	else:
		_hold_timer = default_shoot_anim_duration + extra_hold_seconds

	# spawn bullet if assigned
	if bullet_scene:
		var spawn_pos: Vector2
		if _muzzle and _muzzle is Node2D:
			spawn_pos = _muzzle.global_position
		else:
			var forward = -1 if animated_sprite and animated_sprite.flip_h else 1
			spawn_pos = global_position + Vector2(forward * 8, 0)

		var b = bullet_scene.instantiate()
		if get_tree().current_scene:
			get_tree().current_scene.add_child(b)
		else:
			add_child(b)

		if "global_position" in b:
			b.global_position = spawn_pos
		elif "position" in b:
			b.position = to_local(spawn_pos)

		# set owner if supported
		if b.has_method("set_shooter_owner"):
			b.set_shooter_owner(self)

		# direction toward player
		var dir = (_player.global_position - spawn_pos).normalized()
		if b.has_method("set_direction"):
			b.set_direction(dir, bullet_speed)
		elif b.has_method("set_velocity"):
			b.set_velocity(dir * bullet_speed)
		elif "velocity" in b:
			b.velocity = dir * bullet_speed

		# optional: listen to bullet hit/died if you want (example)
		# if b.has_signal("hit"):
		#     b.connect("hit", Callable(self, "_on_bullet_hit"))

	emit_signal("shoot", self, _player.global_position)

# -------------------------
func take_damage(amount: int = 1) -> void:
	# apply health
	health -= amount

	# small stun and 2s red flash (non-blocking)
	_stun_timer = stun_seconds

	# set sprite red tint
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5)

	# restore color after hit_flash_seconds (non-blocking)
	_call_restore_color(hit_flash_seconds)

	# NOTE: don't zero out velocity here — let add_impulse control knockback so the impulse isn't canceled.
	# if you call take_damage without an impulse and want the enemy to stop, you can still explicitly set velocity = Vector2.ZERO before/after calling take_damage.

	if health <= 0:
		_die()

# helper that runs the delayed restore (keeps take_damage synchronous)
func _call_restore_color(delay_time: float) -> void:
	# start a one-shot timer and restore modulate on timeout without blocking
	var t = get_tree().create_timer(delay_time)
	t.timeout.connect(Callable(self, "_on_flash_timeout"))

func _on_flash_timeout() -> void:
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 1)

func _die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_EXPLODE):
		animated_sprite.play(ANIM_EXPLODE)
	else:
		queue_free()

func _on_anim_finished() -> void:
	var a = animated_sprite.animation
	if a == ANIM_EXPLODE:
		queue_free()
		return

	if a.find("Shoot") != -1:
		_is_shoot_anim = false
		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_IDLE_GUN):
			animated_sprite.play(ANIM_IDLE_GUN)
		else:
			animated_sprite.play(ANIM_IDLE)

func _play_anim(name: String) -> void:
	if not animated_sprite:
		return
	if _is_shoot_anim:
		return
	if animated_sprite.animation == name:
		return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(name):
		animated_sprite.play(name)
		
func add_impulse(impulse: Vector2) -> void:
	# Set horizontal velocity to the impulse (prevents stacking) and start stun.
	# Also optionally accept vertical impulse if provided.
	velocity.x = impulse.x
	# if caller wants vertical knockback, they can pass impulse.y != 0
	if abs(impulse.y) > 0.0:
		velocity.y = impulse.y
	_stun_timer = stun_seconds
