extends CharacterBody2D

signal shoot                  # emitted when firing (useful if you don't use bullet_scene)

@export var SPEED: float = 50.0
@export var detection_range: float = 800.0
@export var stop_min: float = 10.0
@export var stop_max: float = 50.0
@export var shoot_cooldown: float = 1.0     # seconds between shots
@export var bullet_speed: float = 800.0
@export var muzzle_node_path: NodePath = NodePath("Muzzle")
@export var player_path: NodePath = NodePath()   # set in inspector if you want (optional)
@export var bullet_scene: PackedScene         # optional: assign your bullet PackedScene in inspector

# If your sprite art faces right by default set true, otherwise false.
@export var sprite_faces_right: bool = true

# extra hold time after shoot animation ends (in seconds)
@export var extra_hold_seconds: float = 2.0

# fallback duration if animation frames/speed can't be determined
@export var default_shoot_anim_duration: float = 0.5

# animations that exist in your sprite frames (adjust names if needed)
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
var _hold_timer: float = 0.0   # NEW: enforced stand-still timer after shooting

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	# player lookup: prioritized
	if player_path != NodePath():
		_player = get_node_or_null(player_path)

	# try common names if not provided
	if not _player:
		var root = get_tree().get_root()
		_player = root.find_node("Player", true, false)
		if not _player:
			_player = root.find_node("player", true, false)

	# fallback to group "player"
	if not _player:
		var candidates = get_tree().get_nodes_in_group("player")
		if candidates.size() > 0:
			_player = candidates[0]

	if not _player:
		# debug-friendly hint
		printerr("Enemy: couldn't find a player node automatically. Set player_path or add the player to group 'player'.")

	# get muzzle node if present
	_muzzle = get_node_or_null(muzzle_node_path)

	# randomize desired stopping distance within range
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	_stop_distance = rng.randf_range(stop_min, stop_max)

	# connect animation finished to handle explode/loop return
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_anim_finished)

func _physics_process(delta: float) -> void:
	if not _alive:
		return

	# update shoot timer
	if _shoot_timer > 0.0:
		_shoot_timer = max(_shoot_timer - delta, 0.0)

	# update hold timer (stand-still after shooting)
	if _hold_timer > 0.0:
		_hold_timer = max(_hold_timer - delta, 0.0)
		# while holding, force no horizontal movement and show IdleGun if available
		velocity.x = 0
		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_IDLE_GUN):
			_play_anim(ANIM_IDLE_GUN)
		else:
			_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# gravity for enemies that can fall
	if not is_on_floor():
		velocity += ProjectSettings.get_setting("physics/2d/default_gravity_vector") * ProjectSettings.get_setting("physics/2d/default_gravity") * delta

	# no player -> idle
	if not _player:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# vector to player
	var to_player = _player.global_position - global_position
	# *** USE HORIZONTAL DISTANCE for approach/stop/shoot decisions ***
	var dist_x = abs(to_player.x)
	var dist_total = to_player.length()  # still available if you want to use full distance for other checks

	# face player with configurable sprite direction
	if animated_sprite:
		var player_left = _player.global_position.x < global_position.x
		animated_sprite.flip_h = (player_left != sprite_faces_right)

	# if player far (horizontally) -> idle
	if dist_x > detection_range:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# inside detection: approach until within horizontal stop distance
	if dist_x > _stop_distance + 1.0:
		# move toward player on X axis only
		var dir_x = sign(to_player.x)
		velocity.x = dir_x * SPEED
		# prefer run-with-gun animation if available
		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_RUN_GUN):
			if not _is_shoot_anim:
				_play_anim(ANIM_RUN_GUN)
		else:
			if not _is_shoot_anim:
				_play_anim(ANIM_RUN)
	else:
		# close enough horizontally: stop moving horizontally and shoot (when allowed)
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if not _is_shoot_anim:
			if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_IDLE_GUN):
				_play_anim(ANIM_IDLE_GUN)
			else:
				_play_anim(ANIM_IDLE)

		# fire if cooldown is ready and not currently in a shoot animation and not holding
		if _shoot_timer <= 0.0 and not _is_shoot_anim and _hold_timer <= 0.0:
			_do_shoot()

	# apply movement
	move_and_slide()

func _do_shoot() -> void:
	_shoot_timer = shoot_cooldown

	# Play shoot animation from frame 0 and mark that we are playing a shoot anim
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_SHOOT):
		_is_shoot_anim = true
		animated_sprite.frame = 0
		animated_sprite.play(ANIM_SHOOT)
		# attempt to compute animation duration and set hold timer = anim_duration + extra_hold_seconds
		var anim_duration = default_shoot_anim_duration
		# best-effort: get frame count from SpriteFrames and divide by AnimatedSprite speed
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_SHOOT):
			# safe calls in case some API is missing
			if animated_sprite.sprite_frames.has_method("get_frame_count"):
				var fc = animated_sprite.sprite_frames.get_frame_count(ANIM_SHOOT)
				# AnimatedSprite2D has property 'speed' (frames per second)
				var sp = 1.0
				# try to read speed property (fallback to 1 if missing)
				if "speed" in animated_sprite:
					sp = max(animated_sprite.speed, 0.001)
				elif animated_sprite.has_method("get_speed"):
					sp = max(animated_sprite.get_speed(), 0.001)
				# compute duration defensively
				if fc > 0:
					anim_duration = float(fc) / sp
		_hold_timer = anim_duration + extra_hold_seconds
	else:
		# no animation — use fallback hold
		_hold_timer = default_shoot_anim_duration + extra_hold_seconds

	# spawn bullet if provided
	if bullet_scene:
		# prefer muzzle if available, else spawn a bit in front of enemy
		var spawn_pos: Vector2
		if _muzzle and _muzzle is Node2D:
			spawn_pos = (_muzzle as Node2D).global_position
		else:
			var forward = -1 if animated_sprite.flip_h else 1
			spawn_pos = global_position + Vector2(forward * 8, 0)

		var b = bullet_scene.instantiate()

		# add to the active scene
		if get_tree().current_scene:
			get_tree().current_scene.add_child(b)
		else:
			add_child(b)

		# position (world)
		if "global_position" in b:
			b.global_position = spawn_pos
		elif "position" in b:
			# in case the bullet is a local node, convert
			b.position = to_local(spawn_pos)

		# set owner so bullet won't hurt the shooter (uses bullet.set_shooter_owner() or similar)
		if b.has_method("set_shooter_owner"):
			b.set_shooter_owner(self)
		elif b.has_method("set_owner"): # defensive, but usually set_shooter_owner is used
			# avoid overriding Godot's set_owner; only call if the bullet exposed a custom API (rare)
			# otherwise skip
			pass

		# set direction toward player (best-effort)
		var dir = (_player.global_position - spawn_pos).normalized()
		if b.has_method("set_direction"):
			b.set_direction(dir, bullet_speed)
		elif b.has_method("set_velocity"):
			b.set_velocity(dir * bullet_speed)
		elif "velocity" in b:
			b.velocity = dir * bullet_speed

	# always emit shoot signal so other systems can react (sound/effects)
	emit_signal("shoot", self, _player.global_position)

func take_damage(amount: int = 1) -> void:
	# very simple: die on any hit
	_die()

func _die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	# play explode animation and remove when done
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_EXPLODE):
		animated_sprite.play(ANIM_EXPLODE)
	else:
		queue_free()

func _on_anim_finished() -> void:
	var a = animated_sprite.animation
	# when explode ends, free
	if a == ANIM_EXPLODE:
		queue_free()
		return

	# if Shoot finished, clear shoot flag and resume IdleGun or Idle
	if a.find("Shoot") != -1:
		_is_shoot_anim = false
		# If we still have hold time left, keep IdleGun (we already guard movement with _hold_timer)
		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_IDLE_GUN):
			animated_sprite.play(ANIM_IDLE_GUN)
		else:
			animated_sprite.play(ANIM_IDLE)

func _play_anim(name: String) -> void:
	if not animated_sprite:
		return
	# If we're currently playing shoot animation, don't overwrite it
	# (But we allow IdleGun while hold timer is active)
	if _is_shoot_anim:
		return
	if animated_sprite.animation == name:
		return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(name):
		animated_sprite.play(name)
