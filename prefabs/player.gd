extends CharacterBody2D

class_name player

# --- Movement constants ---
@export var WALK_SPEED = 30.0
@export var RUN_SPEED = 60.0
@export var DASH_SPEED = 250.0

# --- Jump/gravity ---
@export var JUMP_VELOCITY = -300.0
@export var DOUBLE_JUMP_VELOCITY = -350.0
@export var GRAVITY_VELOCITY = Vector2(0.0, 490.0)
@export var JUMP_DELAY = 0.15
@export var JUMP_HOLD_TIME = 0.25
@export var HOLD_GRAVITY_MULT = 0.25

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

# --- State variables ---
var state = STATE_IDLE
var was_on_floor = false
var is_dashing = false
var is_jumping = false    
var is_hit = false

# --- Timers & buffers ---
var coyote_time = 0.1
var coyote_timer = 0.0
var jump_buffer_time = 0.15
var jump_buffer_timer = 0.0

# facing (1 right, -1 left). initialize as you like:
var facing_dir: int = 1

# Animated sprite
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

# aim / shoot flags
var aiming: bool = false
var shooting: bool = false

# jumps
const MAX_JUMPS = 2
var jumps_left: int = MAX_JUMPS

# hold-to-jump state
var jump_held: bool = false
var jump_hold_timer: float = 0.0

func _ready():
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_on_frame_changed)

func _physics_process(delta: float) -> void:

	# --- Move input ---
	var is_running = Input.is_action_pressed("Run")
	var dir = Input.get_axis("Left", "Right")  # -1, 0, +1

	# if player gives horizontal input, update facing immediately
	if dir != 0:
		facing_dir = dir

	# keep sprite flip consistent every frame so all animations face the same way
	if animated_sprite:
		# keep original project flip behaviour
		animated_sprite.flip_h = facing_dir > 0

	# --- Dash ---
	if Input.is_action_just_pressed("Dash"):
		velocity.x = facing_dir * DASH_SPEED
		velocity.y = 0
		is_dashing = true
		_change_state(STATE_DASH)

	# --- Aim & Shoot ---
	aiming = Input.is_action_pressed("Aim")
	if Input.is_action_just_pressed("Shoot"):
		# play shoot animation but do not forcibly stop movement
		shooting = true
		_change_state(STATE_SHOOT)

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

	# --- First jump (buffered + delayed) ---
	# This branch only triggers on the first jump (jumps_left == MAX_JUMPS)
	if jump_buffer_timer > 0.0 and not is_dashing and jumps_left == MAX_JUMPS:
		if is_on_floor() or coyote_timer > 0.0:
			jumps_left -= 1
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			is_jumping = true
			_change_state(STATE_JUMP)
			_apply_jump_velocity()

	# --- Second jump (instant double jump) ---
	elif Input.is_action_just_pressed("Jump") and jumps_left > 0 and not is_dashing:
		jumps_left -= 1
		is_jumping = true
		velocity.y = 0.0
		_change_state(STATE_JUMP)
		_apply_jump_instant()
		jump_hold_timer = JUMP_HOLD_TIME

	# update jump held
	jump_held = Input.is_action_pressed("Jump")

	# --- Gravity ---
	if not is_on_floor() and not is_dashing:
		if jump_held and jump_hold_timer > 0.0 and velocity.y < 0:
			# reduced gravity while holding
			velocity += GRAVITY_VELOCITY * HOLD_GRAVITY_MULT * delta
			jump_hold_timer = max(jump_hold_timer - delta, 0.0)
		else:
			velocity += GRAVITY_VELOCITY * delta
			if velocity.y >= 0 or not jump_held:
				jump_hold_timer = 0.0

	# --- Horizontal movement ---
	if not is_dashing and not is_hit:
		if dir != 0:
			velocity.x = dir * (RUN_SPEED if is_running else WALK_SPEED)
		else:
			velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED)

	# --- Move the body (CharacterBody2D uses `velocity`) ---
	move_and_slide()

	# --- Landing detection ---
	if not was_on_floor and is_on_floor():
		jumps_left = MAX_JUMPS
		jump_hold_timer = 0.0
		is_jumping = false
		# if shooting, continue shoot state; else if aiming, go to aim state; else normal idle/walk
		if shooting:
			_change_state(STATE_SHOOT)
		elif aiming:
			_change_state(STATE_AIM)
		else:
			_change_state(STATE_IDLE if velocity.x == 0 else STATE_WALK)

	# update previous floor state
	was_on_floor = is_on_floor()

	# clear the one-shot jumping flag once we start falling
	if velocity.y >= 0:
		is_jumping = false

	# --- State selection (Jump vs Fall from vertical velocity) ---
	# If currently shooting, keep STATE_SHOOT until its animation finishes (don't override)
	if shooting:
		_change_state(STATE_SHOOT)
		# skip the normal movement-driven state selection while shooting
		return

	if not is_dashing and not is_hit:
		var abs_vel_x = abs(velocity.x)
		if not is_on_floor():
			if velocity.y < 0:
				_change_state(STATE_JUMP)
			else:
				_change_state(STATE_FALL)
		else:
			if abs_vel_x == 0:
				_change_state(STATE_IDLE)
			elif abs_vel_x > WALK_SPEED:
				_change_state(STATE_RUN)
			else:
				_change_state(STATE_WALK)

	# If the player is holding aim and we're not shooting/dashing/hit, prefer the aim state
	if aiming and not is_dashing and not is_hit and not shooting:
		_change_state(STATE_AIM)

# -------------------------
func take_damage():
	if is_dashing:
		return
	_change_state(STATE_HIT)
	is_hit = true
	velocity.x = 0
	print("Take DAMAGE!!")

# jump implementations
func _apply_jump_velocity():
	await get_tree().create_timer(JUMP_DELAY).timeout
	velocity.y = JUMP_VELOCITY
	jump_hold_timer = JUMP_HOLD_TIME

func _apply_jump_instant():
	velocity.y = DOUBLE_JUMP_VELOCITY

# -------------------------
# Animation helpers (prefer Aim variants when aiming)
func _play_anim_with_aim(base_name: String) -> void:
	# keep flip consistent again (defensive)
	if animated_sprite:
		animated_sprite.flip_h = facing_dir > 0

	# prefer Aim + Base (AimRun, AimWalk, AimIdle) when aiming
	if animated_sprite and animated_sprite.sprite_frames:
		if aiming:
			var aim_name = "Aim" + base_name
			if animated_sprite.sprite_frames.has_animation(aim_name):
				animated_sprite.play(aim_name)
				return
			# also try shorter "Aim" fallback (if you have a generic Aim animation)
			if base_name == "Idle" and animated_sprite.sprite_frames.has_animation("Aim"):
				animated_sprite.play("Aim")
				return
		# otherwise play base animation if it exists
		if animated_sprite.sprite_frames.has_animation(base_name):
			animated_sprite.play(base_name)
			return

	# fallback
	if animated_sprite:
		animated_sprite.play("Idle")

func _change_state(new_state):
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
			# Aim is essentially the movement state but preferring Aim variants
			var abs_vel_x = abs(velocity.x)
			var base_motion: String = "Idle"
			if is_on_floor():
				if abs_vel_x == 0:
					base_motion = "Idle"
				elif abs_vel_x > WALK_SPEED:
					base_motion = "Run"
				else:
					base_motion = "Walk"
			else:
				if velocity.y < 0:
					base_motion = "Jump"
				else:
					base_motion = "Fall"
			# _play_anim_with_aim will prefer Aim + base_motion automatically
			_play_anim_with_aim(base_motion)
		STATE_SHOOT:
			# Special logic: prefer AimShoot + motion (if aiming),
			# then motion-specific Shoot (ShootJump/ShootFall/ShootRun/ShootWalk),
			# then generic AimShoot / Shoot, then fallback to motion.
			var abs_vel_x = abs(velocity.x)
			var base_motion: String = "Idle"

			if is_on_floor():
				if abs_vel_x == 0:
					base_motion = "Idle"
				elif abs_vel_x > WALK_SPEED:
					base_motion = "Run"
				else:
					base_motion = "Walk"
			else:
				if velocity.y < 0:
					base_motion = "Jump"
				else:
					base_motion = "Fall"

			var aim_motion_shoot_name = "AimShoot" + base_motion   # e.g. AimShootJump
			var motion_shoot_name = "Shoot" + base_motion         # e.g. ShootJump

			# prefer AimShootMotion if aiming and exists
			if aiming and animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(aim_motion_shoot_name):
				animated_sprite.play(aim_motion_shoot_name)
				return

			# then try motion-specific Shoot (ShootJump / ShootFall / ShootRun / ShootWalk)
			if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(motion_shoot_name):
				animated_sprite.play(motion_shoot_name)
				return

			# try generic AimShoot (aiming) then generic Shoot
			if aiming and animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("AimShoot"):
				animated_sprite.play("AimShoot")
				return

			if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Shoot"):
				animated_sprite.play("Shoot")
				return

			# fallback to motion (this will prefer Aim variants via helper)
			_play_anim_with_aim(base_motion)
		STATE_HIT:
			_play_anim_with_aim("Hit")

func _on_animation_finished() -> void:
	var anim_name = animated_sprite.animation
	# clear transient states
	is_dashing = false
	is_hit = false
	is_jumping = false

	# clear shooting when any Shoot* animation finishes
	if anim_name != "" and anim_name.find("Shoot") != -1:
		shooting = false
		# when a shoot animation finishes, return to Aim if aim is held, otherwise to motion
		if aiming:
			_change_state(STATE_AIM)
		else:
			# choose the appropriate motion state
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

	# handle dash ending
	if anim_name == "Dash":
		if is_on_floor():
			velocity.x = 0
			_change_state(STATE_IDLE if velocity.x == 0 else STATE_WALK)
		else:
			_change_state(STATE_FALL)

func _on_frame_changed():
	# Placeholder for frame-driven events (e.g. enabling hitboxes for melee)
	pass
