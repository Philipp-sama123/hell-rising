extends CharacterBody2D
class_name player

# -------------------------
# --- Movement constants ---
@export var WALK_SPEED: float = 30.0
@export var RUN_SPEED: float = 60.0
@export var DASH_SPEED: float = 450.0
@export var BULLET_SPEED: float = 150.0
# --- Jump / gravity ---
@export var JUMP_VELOCITY: float = -300.0
@export var DOUBLE_JUMP_VELOCITY: float = -350.0
@export var GRAVITY_VELOCITY: Vector2 = Vector2(0.0, 490.0)
@export var JUMP_DELAY: float = 0.15
@export var JUMP_HOLD_TIME: float = 0.25
@export var HOLD_GRAVITY_MULT: float = 0.25
@export var PRE_AIM_FRAME_COUNT: int = 5

# --- Animation states ---
enum {
	STATE_IDLE,
	STATE_WALK,
	STATE_RUN,
	STATE_JUMP,
	STATE_FALL,
	STATE_DASH,
	STATE_AIM,
	STATE_SHOOT,
	STATE_HIT,
}

# -------------------------
# --- Exported Bullet config (set in Inspector) ---
@export var BulletScene: PackedScene
@export var SHOOT_FIRE_FRAME: int = 0

# -------------------------
# --- Onready nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# use get_node_or_null so missing muzzle doesn't cause errors
@onready var muzzle: Node2D = get_node_or_null("Muzzle") as Node2D

# -------------------------
# --- State variables ---
var state: int = STATE_IDLE
var was_on_floor: bool = false
var is_dashing: bool = false
var is_jumping: bool = false
var is_hit: bool = false

# timers & buffers
var coyote_time: float = 0.1
var coyote_timer: float = 0.0
var jump_buffer_time: float = 0.15
var jump_buffer_timer: float = 0.0

# facing (1 = right, -1 = left). initialize as you like
var facing_dir: int = 1

# aiming / shooting / pre-aim
var aiming: bool = false
var shooting: bool = false
var pre_aiming: bool = false
var pre_aim_frames: int = 0

# jumps
const MAX_JUMPS: int = 2
var jumps_left: int = MAX_JUMPS

# hold-to-jump
var jump_held: bool = false
var jump_hold_timer: float = 0.0

# bullet one-shot guard per animation
var _shot_fired_in_animation: bool = false

# stored muzzle baseline (used for mirroring)
var _muzzle_base_offset: Vector2 = Vector2.ZERO
var _muzzle_base_scale: Vector2 = Vector2.ONE

# -------------------------
func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_on_frame_changed)

	# store muzzle baseline so we can mirror it when flipping
	if muzzle:
		# use absolute X so original orientation doesn't matter
		_muzzle_base_offset = Vector2(abs(muzzle.position.x), muzzle.position.y)
		_muzzle_base_scale = muzzle.scale.abs() # absolute to keep only magnitudes

# -------------------------
func _physics_process(delta: float) -> void:
	_handle_input_and_actions(delta)
	_apply_gravity(delta)
	_handle_horizontal_movement(delta)

	# move the body (CharacterBody2D uses `velocity`)
	move_and_slide()

	_handle_landing()
	_update_prev_floor_state()

	# clear jumping flag once we start falling
	if velocity.y >= 0:
		is_jumping = false

	# state selection (do not override shooting or pre-aim visuals)
	if shooting:
		_change_state(STATE_SHOOT)
		return

	if pre_aiming:
		# keep manually-played Aim* animation during pre-aim
		return

	if not is_dashing and not is_hit:
		_select_state_from_motion()

	# prefer Aim if hold-to-aim and not in an interrupting state
	if aiming and not is_dashing and not is_hit and not shooting and not pre_aiming:
		_change_state(STATE_AIM)

# -------------------------
# Input / actions handling (keeps original behaviour)
func _handle_input_and_actions(delta: float) -> void:
	var is_running: bool = Input.is_action_pressed("Run")
	var dir: int = int(Input.get_axis("Left", "Right"))  # -1, 0, +1

	# update facing immediately when horizontal input is given
	if dir != 0:
		facing_dir = dir

	# keep sprite flip consistent every frame so animations face same way
	if animated_sprite:
		# keep original project flip behaviour (unchanged)
		animated_sprite.flip_h = facing_dir > 0

	# mirror muzzle to match sprite flip (new behaviour requested)
	_update_muzzle_transform()

	# --- Dash ---
	if Input.is_action_just_pressed("Dash"):
		velocity.x = facing_dir * DASH_SPEED
		velocity.y = 0.0
		is_dashing = true
		pre_aiming = false # cancel pre-aim on dash
		_change_state(STATE_DASH)

	# --- Aim & Shoot ---
	aiming = Input.is_action_pressed("Aim")

	if Input.is_action_just_pressed("Shoot") and not shooting and not pre_aiming:
		if aiming:
			shooting = true
			_change_state(STATE_SHOOT)
		else:
			# start pre-aim (play Aim animation for a few frames, then shoot)
			pre_aiming = true
			pre_aim_frames = PRE_AIM_FRAME_COUNT

			# pick motion-specific Aim animation if available
			var base_motion: String = _get_motion_name_from_velocity()
			var aim_motion_name: String = "Aim" + base_motion

			if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(aim_motion_name):
				animated_sprite.play(aim_motion_name)
			elif animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Aim"):
				animated_sprite.play("Aim")
			else:
				_change_state(STATE_AIM)

	# cancel pre-aim on interrupting conditions
	if is_dashing or is_hit:
		pre_aiming = false

	# --- Jump buffer handling ---
	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	# --- Coyote timer ---
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	# --- First jump (buffered + delayed; only for the first jump) ---
	if jump_buffer_timer > 0.0 and not is_dashing and jumps_left == MAX_JUMPS:
		if is_on_floor() or coyote_timer > 0.0:
			jumps_left -= 1
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			is_jumping = true
			_change_state(STATE_JUMP)
			_apply_jump_velocity()

	# --- Second jump ---
	elif Input.is_action_just_pressed("Jump") and jumps_left > 0 and not is_dashing:
		jumps_left -= 1
		is_jumping = true
		velocity.y = 0.0
		_change_state(STATE_JUMP)
		_apply_jump_instant()
		jump_hold_timer = JUMP_HOLD_TIME

	# update jump held flag
	jump_held = Input.is_action_pressed("Jump")

# -------------------------
func _apply_jump_velocity() -> void:
	# delayed first jump
	await get_tree().create_timer(JUMP_DELAY).timeout
	velocity.y = JUMP_VELOCITY
	jump_hold_timer = JUMP_HOLD_TIME

func _apply_jump_instant() -> void:
	# instantaneous double-jump
	velocity.y = DOUBLE_JUMP_VELOCITY

# -------------------------
# Gravity handling (preserves original logic)
func _apply_gravity(delta: float) -> void:
	if not is_on_floor() and not is_dashing:
		if jump_held and jump_hold_timer > 0.0 and velocity.y < 0.0:
			velocity += GRAVITY_VELOCITY * HOLD_GRAVITY_MULT * delta
			jump_hold_timer = max(jump_hold_timer - delta, 0.0)
		else:
			velocity += GRAVITY_VELOCITY * delta
			if velocity.y >= 0.0 or not jump_held:
				jump_hold_timer = 0.0

# -------------------------
# Horizontal movement (preserves original behaviour)
func _handle_horizontal_movement(delta: float) -> void:
	# only control horizontal movement when not dashing or hit
	if not is_dashing and not is_hit:
		var dir: int = int(Input.get_axis("Left", "Right"))
		var is_running: bool = Input.is_action_pressed("Run")
		if dir != 0:
			velocity.x = dir * (RUN_SPEED if is_running else WALK_SPEED)
		else:
			velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED)

# -------------------------
# Landing / floor updates
func _handle_landing() -> void:
	if not was_on_floor and is_on_floor():
		jumps_left = MAX_JUMPS
		jump_hold_timer = 0.0
		is_jumping = false

		# if currently shooting, stay in shoot; else go to aim or motion
		if shooting:
			_change_state(STATE_SHOOT)
		elif aiming:
			_change_state(STATE_AIM)
		else:
			_change_state(STATE_IDLE if velocity.x == 0 else STATE_WALK)

func _update_prev_floor_state() -> void:
	was_on_floor = is_on_floor()

# -------------------------
# State selection (movement -> states)
func _select_state_from_motion() -> void:
	var abs_vx: float = abs(velocity.x)
	if not is_on_floor():
		if velocity.y < 0:
			_change_state(STATE_JUMP)
		else:
			_change_state(STATE_FALL)
	else:
		if abs_vx == 0:
			_change_state(STATE_IDLE)
		elif abs_vx > WALK_SPEED:
			_change_state(STATE_RUN)
		else:
			_change_state(STATE_WALK)

# -------------------------
# Animation helpers
func _play_anim_with_aim(base_name: String) -> void:
	# preserve the flip again (defensive)
	if animated_sprite:
		animated_sprite.flip_h = facing_dir > 0

	# prefer Aim + base if aiming
	if animated_sprite and animated_sprite.sprite_frames:
		if aiming:
			var aim_name = "Aim" + base_name
			if animated_sprite.sprite_frames.has_animation(aim_name):
				animated_sprite.play(aim_name)
				return
			if base_name == "Idle" and animated_sprite.sprite_frames.has_animation("Aim"):
				animated_sprite.play("Aim")
				return

		if animated_sprite.sprite_frames.has_animation(base_name):
			animated_sprite.play(base_name)
			return

	# fallback to Idle if nothing found
	if animated_sprite:
		animated_sprite.play("Idle")

func _change_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	match state:
		STATE_IDLE:
			_play_anim_with_aim("Idle")
		STATE_WALK:
			_play_anim_with_aim("Walk")
		STATE_RUN:
			_play_anim_with_aim("Run")
		STATE_JUMP:
			_play_anim_with_aim("Jump")
		STATE_FALL:
			_play_anim_with_aim("Fall")
		STATE_DASH:
			_play_anim_with_aim("Dash")
		STATE_AIM:
			var base_motion = _get_motion_name_from_velocity()
			_play_anim_with_aim(base_motion)
		STATE_SHOOT:
			var base_motion = _get_motion_name_from_velocity()
			var motion_shoot_name = "Shoot" + base_motion
			if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(motion_shoot_name):
				animated_sprite.play(motion_shoot_name)
				return
			if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Shoot"):
				animated_sprite.play("Shoot")
				return
			_play_anim_with_aim(base_motion)
		STATE_HIT:
			_play_anim_with_aim("Hit")

func _get_motion_name_from_velocity() -> String:
	var abs_vx: float = abs(velocity.x)
	if is_on_floor():
		if abs_vx == 0:
			return "Idle"
		elif abs_vx > WALK_SPEED:
			return "Run"
		else:
			return "Walk"
	else:
		if velocity.y < 0:
			return "Jump"
		else:
			return "Fall"

# -------------------------
# Animation signals
func _on_animation_finished() -> void:
	var anim_name: String = animated_sprite.animation

	# clear transient flags
	is_dashing = false
	is_hit = false
	is_jumping = false

	# clear shooting when any Shoot* animation finishes
	if anim_name != "" and anim_name.find("Shoot") != -1:
		shooting = false
		_shot_fired_in_animation = false
		if aiming:
			_change_state(STATE_AIM)
		else:
			# pick appropriate motion state
			if is_on_floor():
				var abs_vx = abs(velocity.x)
				if abs_vx == 0:
					_change_state(STATE_IDLE)
				elif abs_vx > WALK_SPEED:
					_change_state(STATE_RUN)
				else:
					_change_state(STATE_WALK)
			else:
				if velocity.y < 0:
					_change_state(STATE_JUMP)
				else:
					_change_state(STATE_FALL)

	# handle dash animation end
	if anim_name == "Dash":
		if is_on_floor():
			velocity.x = 0
			_change_state(STATE_IDLE if velocity.x == 0 else STATE_WALK)
		else:
			_change_state(STATE_FALL)

func _on_frame_changed() -> void:
	# pre-aim frame counting
	if pre_aiming:
		# if player started holding aim during pre-aim, shoot immediately
		if aiming:
			pre_aiming = false
			shooting = true
			_change_state(STATE_SHOOT)
			return

		pre_aim_frames -= 1
		if pre_aim_frames <= 0:
			pre_aiming = false
			shooting = true
			_change_state(STATE_SHOOT)
			return

	# bullet firing: spawn when a Shoot* animation reaches SHOOT_FIRE_FRAME
	var anim_name: String = animated_sprite.animation
	if shooting and anim_name != "" and anim_name.find("Shoot") != -1:
		if animated_sprite.frame == SHOOT_FIRE_FRAME and not _shot_fired_in_animation:
			_shot_fired_in_animation = true
			_spawn_bullet()

# -------------------------
# Damage handler
func take_damage() -> void:
	if is_dashing:
		return
	_change_state(STATE_HIT)
	is_hit = true
	velocity.x = 0
	pre_aiming = false
	print("Take DAMAGE!!")

# -------------------------
# Bullet spawn helper
func _spawn_bullet() -> void:
	if not BulletScene:
		print_debug("BulletScene not assigned; cannot spawn bullet.")
		return

	var b = BulletScene.instantiate()
	if not b:
		return

	get_tree().current_scene.add_child(b)

	# position at muzzle or slightly in front of player
	var spawn_pos: Vector2 = global_position
	if muzzle:
		spawn_pos = muzzle.global_position
	else:
		spawn_pos = global_position + Vector2(facing_dir * 12, -4)

	b.global_position = spawn_pos

	if not b.is_in_group("bullet"):
		b.add_to_group("bullet")

	if b.has_method("set_shooter_owner"):
		b.set_shooter_owner(self)

	# set direction (simple horizontal)
	var dir_vec: Vector2 = Vector2(facing_dir, 0)

	if b.has_method("set_direction"):
		b.set_direction(dir_vec)
	elif b.has_method("set_velocity"):
		if b.has_variable("speed"):
			b.set_velocity(dir_vec * b.speed)
		else:
			b.set_velocity(dir_vec * BULLET_SPEED)

# -------------------------
# Muzzle transform update (NEW): mirrors muzzle position & scale when flipping player
func _update_muzzle_transform() -> void:
	if not muzzle:
		return

	# Use facing_dir (1 = right, -1 = left).
	# We stored an absolute X baseline in _ready, so multiply by facing_dir to mirror.
	muzzle.position.x = _muzzle_base_offset.x * facing_dir
	muzzle.position.y = _muzzle_base_offset.y

	# Mirror horizontal scale accordingly so muzzle visuals flip with sprite.
	# Use the stored absolute scale magnitudes and apply sign via facing_dir.
	muzzle.scale.x = _muzzle_base_scale.x * float(facing_dir)
	# keep Y scale magnitude unchanged
	muzzle.scale.y = _muzzle_base_scale.y

# -------------------------
