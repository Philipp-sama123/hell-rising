extends CharacterBody2D
class_name player

# -------------------
# Exports (tweakable)
# -------------------
@export var WALK_SPEED: float = 30.0
@export var RUN_SPEED: float = 100.0
@export var DASH_SPEED: float = 500.0
@export var BULLET_SPEED: float = 150.0

@export var JUMP_VELOCITY: float = -300.0
@export var DOUBLE_JUMP_VELOCITY: float = -350.0
@export var GRAVITY_VELOCITY: Vector2 = Vector2(0, 490)
@export var JUMP_DELAY: float = 0.15
@export var JUMP_HOLD_TIME: float = 0.25
@export var HOLD_GRAVITY_MULT: float = 0.25
@export var PRE_AIM_FRAME_COUNT: int = 5

@export var HIT_STUN_TIME: float = 0.25
@export var hit_kb_strength: float = 150.0

@export var SLIDE_SHOOT_COOLDOWN: float = 0.15
@export var SLIDE_MIN_TIME: float = 0.5
@export var SLIDE_MAX_TIME: float = 5.0

@export var BulletScene: PackedScene

# Single global shot frame for all Shoot animations (0-based).
# Change in the inspector if you want the bullet to spawn on a different frame.
@export var SHOT_FRAME: int = 0

# ----------------
# Animation states
# ----------------
enum {
	STATE_IDLE,
	STATE_WALK,
	STATE_RUN,
	STATE_JUMP,
	STATE_FALL,
	STATE_DASH,

	STATE_AIM_IDLE,
	STATE_AIM_WALK,
	STATE_AIM_RUN,
	STATE_AIM_JUMP,
	STATE_AIM_FALL,

	STATE_AIMUP_IDLE,
	STATE_AIMUP_WALK,
	STATE_AIMUP_RUN,

	STATE_CROUCH_IDLE,
	STATE_CROUCH_AIM_IDLE,
	STATE_CROUCH_AIMUP_IDLE,
	STATE_CROUCH_SHOOT_IDLE,
	STATE_CROUCH_SHOOTUP_IDLE,

	STATE_SHOOT_IDLE,
	STATE_SHOOT_WALK,
	STATE_SHOOT_RUN,
	STATE_SHOOT_JUMP,
	STATE_SHOOT_FALL,

	STATE_SHOOTUP_IDLE,
	STATE_SHOOTUP_WALK,
	STATE_SHOOTUP_RUN,

	STATE_SHOOT_DASH
}

var _STATE_ANIM: Dictionary = {
	STATE_IDLE: "Idle",
	STATE_WALK: "Walk",
	STATE_RUN: "Run",
	STATE_JUMP: "Jump",
	STATE_FALL: "Fall",
	STATE_DASH: "Dash",

	STATE_AIM_IDLE: "AimIdle",
	STATE_AIM_WALK: "AimWalk",
	STATE_AIM_RUN: "AimRun",
	STATE_AIM_JUMP: "AimJump",
	STATE_AIM_FALL: "AimFall",

	STATE_AIMUP_IDLE: "AimUpIdle",
	STATE_AIMUP_WALK: "AimUpWalk",
	STATE_AIMUP_RUN: "AimUpRun",

	STATE_CROUCH_IDLE: "CrouchIdle",
	STATE_CROUCH_AIM_IDLE: "CrouchAimIdle",
	STATE_CROUCH_AIMUP_IDLE: "CrouchAimUpIdle",
	STATE_CROUCH_SHOOT_IDLE: "CrouchShootIdle",
	STATE_CROUCH_SHOOTUP_IDLE: "CrouchShootUpIdle",

	STATE_SHOOT_IDLE: "ShootIdle",
	STATE_SHOOT_WALK: "ShootWalk",
	STATE_SHOOT_RUN: "ShootRun",
	STATE_SHOOT_JUMP: "ShootJump",
	STATE_SHOOT_FALL: "ShootFall",

	STATE_SHOOTUP_IDLE: "ShootUpIdle",
	STATE_SHOOTUP_WALK: "ShootUpWalk",
	STATE_SHOOTUP_RUN: "ShootUpRun",

	STATE_SHOOT_DASH: "ShootDash"
}

# -------------------
# Node references
# -------------------
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Node2D = $Muzzle
@onready var muzzle_up: Node2D = $"MuzzleUp"
@onready var muzzle_dash: Node2D = $"MuzzleDash"
@onready var muzzle_crouch: Node2D = $"MuzzleCrouch"
@onready var muzzle_up_crouch: Node2D = $"MuzzleUpCrouch"

@onready var normal_shape: CollisionShape2D = $NormalShape
@onready var slide_shape: CollisionShape2D = $SlideShape
@onready var head_shape: CollisionShape2D = $HeadShape

# -------------------
# Runtime variables
# -------------------
var state: int = STATE_IDLE
var facing_dir: int = 1

var was_on_floor: bool = false
var is_dashing: bool = false
var is_jumping: bool = false
var is_hit: bool = false
var is_crouching: bool = false

var aiming: bool = false
var aim_up: bool = false
var shooting: bool = false
var pre_aiming: bool = false
var pre_aim_frames: int = 0

const MAX_JUMPS: int = 2
var jumps_left: int = MAX_JUMPS

var coyote_time: float = 0.1
var coyote_timer: float = 0.0
var jump_buffer_time: float = 0.15
var jump_buffer_timer: float = 0.0

var jump_held: bool = false
var jump_hold_timer: float = 0.0

var _hit_timer: Timer = null
var _slide_shoot_cd: float = 0.0
var _slide_time_elapsed: float = 0.0

var _shot_fired_in_animation: bool = false
var _shooting_anim_playing: bool = false

# muzzle/base transforms saved from scene
var _muzzle_base_offset: Vector2 = Vector2.ZERO
var _muzzle_base_scale: Vector2 = Vector2.ONE
var _muzzle_up_base_offset: Vector2 = Vector2.ZERO
var _muzzle_up_base_scale: Vector2 = Vector2.ONE
var _muzzle_dash_base_offset: Vector2 = Vector2.ZERO
var _muzzle_dash_base_scale: Vector2 = Vector2.ONE
var _muzzle_crouch_base_offset: Vector2 = Vector2.ZERO
var _muzzle_crouch_base_scale: Vector2 = Vector2.ONE
var _muzzle_up_crouch_base_offset: Vector2 = Vector2.ZERO
var _muzzle_up_crouch_base_scale: Vector2 = Vector2.ONE

var _normal_shape_base_offset: Vector2 = Vector2.ZERO
var _normal_shape_base_scale: Vector2 = Vector2.ONE
var _slide_shape_base_offset: Vector2 = Vector2.ZERO
var _slide_shape_base_scale: Vector2 = Vector2.ONE
var _head_shape_base_offset: Vector2 = Vector2.ZERO
var _head_shape_base_scale: Vector2 = Vector2.ONE

# ---------------------------
# Movement & action enums
# ---------------------------
enum MovementState {
	MOVE_IDLE,
	MOVE_WALK,
	MOVE_RUN,
	MOVE_CROUCH,
	MOVE_DASH,
	MOVE_JUMP,
	MOVE_FALL
}
enum ActionState {
	A_NONE,
	A_AIM,
	A_AIM_UP,
	A_SHOOT,
	A_SLIDE_SHOOT
}

var movement_state: int = MovementState.MOVE_IDLE
var action_state: int = ActionState.A_NONE

# horizontal smoothing
@export var H_ACCEL: float = 1200.0
@export var H_DECEL: float = 1200.0

# ------------------------
# Shot direction locking
# ------------------------
var _shot_dir_locked: bool = false
var _locked_shot_dir: Vector2 = Vector2.ZERO

# -------------
# Initialization
# -------------
func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_on_frame_changed)

	# cache base offsets & scales (use abs for x to simplify flipping)
	if muzzle:
		_muzzle_base_offset = Vector2(abs(muzzle.position.x), muzzle.position.y)
		_muzzle_base_scale = muzzle.scale.abs()
	if muzzle_up:
		_muzzle_up_base_offset = Vector2(abs(muzzle_up.position.x), muzzle_up.position.y)
		_muzzle_up_base_scale = muzzle_up.scale.abs()
	if muzzle_dash:
		_muzzle_dash_base_offset = Vector2(abs(muzzle_dash.position.x), muzzle_dash.position.y)
		_muzzle_dash_base_scale = muzzle_dash.scale.abs()
	if muzzle_crouch:
		_muzzle_crouch_base_offset = Vector2(abs(muzzle_crouch.position.x), muzzle_crouch.position.y)
		_muzzle_crouch_base_scale = muzzle_crouch.scale.abs()
	if muzzle_up_crouch:
		_muzzle_up_crouch_base_offset = Vector2(abs(muzzle_up_crouch.position.x), muzzle_up_crouch.position.y)
		_muzzle_up_crouch_base_scale = muzzle_up_crouch.scale.abs()

	if normal_shape:
		_normal_shape_base_offset = Vector2(abs(normal_shape.position.x), normal_shape.position.y)
		_normal_shape_base_scale = normal_shape.scale.abs()
	if slide_shape:
		_slide_shape_base_offset = Vector2(abs(slide_shape.position.x), slide_shape.position.y)
		_slide_shape_base_scale = slide_shape.scale.abs()
	if head_shape:
		_head_shape_base_offset = Vector2(abs(head_shape.position.x), head_shape.position.y)
		_head_shape_base_scale = head_shape.scale.abs()

	_hit_timer = Timer.new()
	_hit_timer.one_shot = true
	add_child(_hit_timer)
	_hit_timer.wait_time = HIT_STUN_TIME
	_hit_timer.connect("timeout", Callable(self, "_on_hit_recovered"))

# -------------
# Main loop
# -------------
func _physics_process(delta: float) -> void:
	_slide_shoot_cd = max(0.0, _slide_shoot_cd - delta)

	_handle_input(delta)
	_update_movement(delta)
	_apply_gravity(delta)
	_update_slide_timer(delta)

	move_and_slide()
	_update_muzzle_transform()
	_handle_landing()

	_select_states()

	# if shooting, prioritize shoot animations (we still run physics)
	if shooting:
		_change_state(_state_for_motion_and_flags())
		return

	if pre_aiming:
		return

	if _can_change_state():
		_change_state(_state_for_motion_and_flags())

	was_on_floor = is_on_floor()
	if velocity.y >= 0:
		is_jumping = false

func _can_change_state() -> bool:
	return not is_dashing and not is_hit

# ------------------
# Input & movement
# ------------------
func _handle_input(delta: float) -> void:
	# facing
	var axis_dir := int(Input.get_axis("Left", "Right"))
	if axis_dir != 0:
		facing_dir = axis_dir
	if animated_sprite:
		animated_sprite.flip_h = facing_dir > 0

	# aim inputs
	aiming = Input.is_action_pressed("Aim")
	aim_up = Input.is_action_pressed("Up") and is_on_floor() and not is_dashing

	# crouch toggle
	var want_crouch := Input.is_action_pressed("Crouch") and is_on_floor() and not is_dashing
	if want_crouch != is_crouching:
		is_crouching = want_crouch
		if is_crouching:
			velocity.x = 0
		_change_state(_state_for_motion_and_flags())

	_update_muzzle_transform()

	# dash
	if Input.is_action_just_pressed("Dash") and not shooting and not is_crouching and not is_hit:
		_start_dash()

	# shoot
	if Input.is_action_just_pressed("Shoot") and not shooting:
		if is_dashing and _slide_shoot_cd <= 0.0:
			_do_slide_shoot()
			_slide_shoot_cd = SLIDE_SHOOT_COOLDOWN
		else:
			_shot_fired_in_animation = false
			shooting = true
			_shot_dir_locked = true
			_locked_shot_dir = Vector2(0, -1) if aim_up else Vector2(facing_dir, 0)
			_change_state(_state_for_motion_and_flags())

	# cancel pre-aim when dashing or hit
	if is_dashing or is_hit:
		pre_aiming = false

	# jump buffering & coyote
	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)

	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = max(coyote_timer - delta, 0)

	# consume buffered jump (first jump) - blocked while shooting/dashing
	if jump_buffer_timer > 0 and not is_dashing and not shooting and jumps_left == MAX_JUMPS and (is_on_floor() or coyote_timer > 0):
		jumps_left -= 1
		jump_buffer_timer = 0
		coyote_timer = 0
		is_jumping = true
		aim_up = false
		_change_state(STATE_JUMP)
		_start_jump_sequence()
	# double jump (also blocked while shooting)
	elif Input.is_action_just_pressed("Jump") and jumps_left > 0 and not is_dashing and not shooting:
		jumps_left -= 1
		is_jumping = true
		velocity.y = 0
		aim_up = false
		_change_state(STATE_JUMP)
		_apply_jump_instant()
		jump_hold_timer = JUMP_HOLD_TIME

	jump_held = Input.is_action_pressed("Jump")

func _update_movement(delta: float) -> void:
	if is_crouching:
		velocity.x = move_toward(velocity.x, 0, H_DECEL * delta)
		return
	if is_dashing or is_hit:
		return

	var dir := int(Input.get_axis("Left", "Right"))
	var is_running := Input.is_action_pressed("Run")
	var target_speed := dir * (RUN_SPEED if is_running else WALK_SPEED) if dir != 0 else 0.0
	var accel := H_ACCEL if abs(target_speed) > abs(velocity.x) else H_DECEL
	velocity.x = move_toward(velocity.x, target_speed, accel * delta)

# ----------------
# Dash / slide
# ----------------
func _start_dash() -> void:
	velocity.x = facing_dir * DASH_SPEED
	velocity.y = 0
	is_dashing = true
	pre_aiming = false
	_slide_time_elapsed = 0.0
	_change_state(STATE_DASH)
	_set_collision_mode(true)

func _end_dash() -> void:
	is_dashing = false
	_set_collision_mode(false)
	_change_state(_state_for_motion_and_flags())

func _set_collision_mode(slide: bool) -> void:
	if slide_shape:
		slide_shape.set_deferred("disabled", not slide)
	if normal_shape:
		normal_shape.set_deferred("disabled", slide)

func _update_slide_timer(delta: float) -> void:
	if not is_dashing:
		return
	_slide_time_elapsed += delta
	if _slide_time_elapsed >= SLIDE_MAX_TIME or (not Input.is_action_pressed("Dash") and _slide_time_elapsed >= SLIDE_MIN_TIME):
		_end_dash()

# ----------------------------
# Jump & gravity
# ----------------------------
func _start_jump_sequence() -> void:
	await get_tree().create_timer(JUMP_DELAY).timeout
	velocity.y = JUMP_VELOCITY
	jump_hold_timer = JUMP_HOLD_TIME

func _apply_jump_instant() -> void:
	velocity.y = DOUBLE_JUMP_VELOCITY

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		if jump_held and jump_hold_timer > 0 and velocity.y < 0:
			velocity += GRAVITY_VELOCITY * HOLD_GRAVITY_MULT * delta
			jump_hold_timer = max(jump_hold_timer - delta, 0)
		else:
			velocity += GRAVITY_VELOCITY * delta
			if velocity.y >= 0 or not jump_held:
				jump_hold_timer = 0

func _handle_landing() -> void:
	if not was_on_floor and is_on_floor():
		jumps_left = MAX_JUMPS
		jump_hold_timer = 0
		is_jumping = false
		if is_dashing:
			return
		_change_state(_state_for_motion_and_flags())

# ----------------------------
# Input-first state selection
# ----------------------------
func _select_states() -> void:
	# action priority
	if is_dashing and Input.is_action_just_pressed("Shoot") and _slide_shoot_cd <= 0.0:
		action_state = ActionState.A_SLIDE_SHOOT
	elif shooting:
		action_state = ActionState.A_SHOOT
	elif aim_up:
		action_state = ActionState.A_AIM_UP
	elif aiming:
		action_state = ActionState.A_AIM
	else:
		action_state = ActionState.A_NONE

	# movement mapping
	if is_dashing:
		movement_state = MovementState.MOVE_DASH
		return
	if is_crouching and is_on_floor():
		movement_state = MovementState.MOVE_CROUCH
		return
	if not is_on_floor():
		movement_state = MovementState.MOVE_JUMP if velocity.y < 0 else MovementState.MOVE_FALL
		return

	var axis := int(Input.get_axis("Left", "Right"))
	if axis == 0:
		movement_state = MovementState.MOVE_IDLE
		return
	var running := Input.is_action_pressed("Run")
	movement_state = MovementState.MOVE_RUN if running else MovementState.MOVE_WALK

# ----------------------------------------
# Map movement_state + action_state -> STATE_*
# ----------------------------------------
func _state_for_motion_and_flags() -> int:
	# crouch (ground) variants
	if movement_state == MovementState.MOVE_CROUCH:
		if shooting:
			return STATE_CROUCH_SHOOTUP_IDLE if aim_up else STATE_CROUCH_SHOOT_IDLE
		if aim_up:
			return STATE_CROUCH_AIMUP_IDLE
		if aiming:
			return STATE_CROUCH_AIM_IDLE
		return STATE_CROUCH_IDLE

	# slide-shoot while dashing
	if movement_state == MovementState.MOVE_DASH and action_state == ActionState.A_SLIDE_SHOOT:
		return STATE_SHOOT_DASH

	# airborne
	if movement_state == MovementState.MOVE_JUMP or movement_state == MovementState.MOVE_FALL:
		var airborne_up := movement_state == MovementState.MOVE_JUMP
		if action_state == ActionState.A_SHOOT:
			return STATE_SHOOT_JUMP if airborne_up else STATE_SHOOT_FALL
		if action_state == ActionState.A_AIM or action_state == ActionState.A_AIM_UP:
			return STATE_AIM_JUMP if airborne_up else STATE_AIM_FALL
		return STATE_JUMP if airborne_up else STATE_FALL

	# ground shooting: prefer ShootUp when aiming up
	if action_state == ActionState.A_SHOOT:
		if aim_up:
			if movement_state == MovementState.MOVE_IDLE:
				return STATE_SHOOTUP_IDLE
			if movement_state == MovementState.MOVE_WALK:
				return STATE_SHOOTUP_WALK
			return STATE_SHOOTUP_RUN
		if movement_state == MovementState.MOVE_IDLE:
			return STATE_SHOOT_IDLE
		if movement_state == MovementState.MOVE_WALK:
			return STATE_SHOOT_WALK
		return STATE_SHOOT_RUN

	# aim up on ground
	if action_state == ActionState.A_AIM_UP:
		if movement_state == MovementState.MOVE_IDLE:
			return STATE_AIMUP_IDLE
		if movement_state == MovementState.MOVE_WALK:
			return STATE_AIMUP_WALK
		return STATE_AIMUP_RUN

	# aim normal on ground
	if action_state == ActionState.A_AIM:
		if movement_state == MovementState.MOVE_IDLE:
			return STATE_AIM_IDLE
		if movement_state == MovementState.MOVE_WALK:
			return STATE_AIM_WALK
		return STATE_AIM_RUN

	# plain motion
	if movement_state == MovementState.MOVE_IDLE:
		return STATE_IDLE
	if movement_state == MovementState.MOVE_WALK:
		return STATE_WALK
	return STATE_RUN

# ----------------------
# Animation handling
# ----------------------
func _require_play(_name: String, start_frame: int = -1) -> void:
	assert(animated_sprite, "AnimatedSprite2D missing.")
	assert(animated_sprite.sprite_frames, "SpriteFrames missing.")
	animated_sprite.flip_h = facing_dir > 0
	assert(animated_sprite.sprite_frames.has_animation(_name), "Missing animation: " + _name)
	animated_sprite.play(_name)
	if start_frame >= 0:
		var frame_count := animated_sprite.sprite_frames.get_frame_count(_name)
		animated_sprite.frame = clamp(start_frame, 0, max(frame_count - 1, 0))
	_shooting_anim_playing = _name.find("Shoot") != -1

func _change_state(new_state: int) -> void:
	if new_state == state:
		return

	var anim_name = _STATE_ANIM.get(new_state, "")
	if anim_name == "":
		push_warning("No animation mapping for state: " + str(new_state))
		state = new_state
		return

	var cur_anim = animated_sprite.animation if animated_sprite else ""
	var cur_is_shoot = cur_anim != "" and cur_anim.find("Shoot") != -1
	var new_is_shoot = anim_name.find("Shoot") != -1

	# If we're already in a Shoot animation and switching to another Shoot, preserve playhead
	if cur_is_shoot and new_is_shoot and _shooting_anim_playing:
		var cur_frame := animated_sprite.frame
		state = new_state
		_require_play(anim_name, cur_frame)
		return

	state = new_state
	_require_play(anim_name)

# ----------------
# Damage & hit
# ----------------
func take_damage(_damage: int = 1, source_pos: Vector2 = Vector2.ZERO, knockback_strength: float = -1.0) -> void:
	if is_dashing:
		return
	pre_aiming = false
	if _hit_timer:
		_hit_timer.start(HIT_STUN_TIME)

	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5)
		var t = get_tree().create_timer(HIT_STUN_TIME)
		t.timeout.connect(Callable(self, "_restore_color"))

	# compute facing of knockback if needed (not applied currently)
	var dir_x: int = 0
	if source_pos != Vector2.ZERO:
		dir_x = int(sign(global_position.x - source_pos.x))
		if dir_x == 0:
			dir_x = int(sign(velocity.x)) if abs(velocity.x) > 0.1 else -facing_dir
	else:
		dir_x = int(sign(velocity.x)) if abs(velocity.x) > 0.1 else -facing_dir
	if dir_x == 0:
		dir_x = 1

func _on_hit_recovered() -> void:
	is_hit = false
	if is_dashing:
		return
	_change_state(_state_for_motion_and_flags())

func _restore_color() -> void:
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 1)

# -------------------------
# Slide-shoot / bullets
# -------------------------
func _do_slide_shoot() -> void:
	_shot_dir_locked = true
	_locked_shot_dir = Vector2(0, -1) if aim_up else Vector2(facing_dir, 0)
	_spawn_bullet_from_muzzle()
	_shot_fired_in_animation = true
	animated_sprite.play("ShootDash")
	_shooting_anim_playing = true

	var t = get_tree().create_timer(max(0.08, SLIDE_SHOOT_COOLDOWN))
	t.timeout.connect(Callable(self, "_reset_shot_flag"))

func _reset_shot_flag() -> void:
	_shot_fired_in_animation = false

func _spawn_bullet_from_muzzle() -> void:
	if not BulletScene:
		return

	var b := BulletScene.instantiate()
	if not b:
		return

	var chosen_muzzle: Node2D = null
	var dir_vec: Vector2 = Vector2.ZERO

	# 1) prefer locked direction (set when shooting started)
	if _shot_dir_locked and _locked_shot_dir != Vector2.ZERO:
		dir_vec = _locked_shot_dir.normalized()
		if dir_vec.y < -0.5:
			chosen_muzzle = muzzle_up_crouch if is_crouching and muzzle_up_crouch else muzzle_up if muzzle_up else null
		else:
			chosen_muzzle = muzzle_dash if is_dashing and muzzle_dash else muzzle_crouch if is_crouching and muzzle_crouch else muzzle
		_shot_dir_locked = false
		_locked_shot_dir = Vector2.ZERO
	else:
		# 2) pick visible muzzle (what the player sees)
		if is_dashing and muzzle_dash and muzzle_dash.visible:
			chosen_muzzle = muzzle_dash
		elif is_crouching and muzzle_up_crouch and muzzle_up_crouch.visible:
			chosen_muzzle = muzzle_up_crouch
		elif is_crouching and muzzle_crouch and muzzle_crouch.visible:
			chosen_muzzle = muzzle_crouch
		elif muzzle_up and muzzle_up.visible:
			chosen_muzzle = muzzle_up
		elif muzzle and muzzle.visible:
			chosen_muzzle = muzzle

		# 3) fallback: infer direction from chosen muzzle or animation
		if chosen_muzzle == null:
			var anim_name = animated_sprite.animation if animated_sprite else ""
			var anim_wants_up = anim_name != "" and anim_name.findn("Up") != -1
			dir_vec = Vector2(0, -1) if anim_wants_up else Vector2(facing_dir, 0)
		else:
			dir_vec = Vector2(0, -1) if chosen_muzzle == muzzle_up or chosen_muzzle == muzzle_up_crouch else Vector2(facing_dir, 0)

	# final fallback
	if dir_vec == Vector2.ZERO:
		dir_vec = Vector2(facing_dir, 0)

	# spawn pos from chosen muzzle or approximate
	var spawn_pos: Vector2 = global_position + Vector2(facing_dir * 12, -4)
	if chosen_muzzle:
		spawn_pos = chosen_muzzle.global_position

	get_tree().current_scene.add_child(b)
	b.global_position = spawn_pos

	if not b.is_in_group("bullet"):
		b.add_to_group("bullet")
	if b.has_method("set_shooter_owner"):
		b.set_shooter_owner(self)

	dir_vec = dir_vec.normalized()
	if b.has_method("set_direction"):
		b.set_direction(dir_vec, BULLET_SPEED)
	elif b.has_method("set_velocity"):
		if b.has_variable("speed"):
			b.set_velocity(dir_vec * b.speed)
		else:
			b.set_velocity(dir_vec * BULLET_SPEED)

	if b is Node2D:
		b.rotation = dir_vec.angle()

# ---------------------------
# Muzzle transform update
# ---------------------------
func _update_muzzle_transform() -> void:
	if muzzle:
		var y_offset := _muzzle_base_offset.y + (6 if is_crouching else 0)
		muzzle.visible = not aim_up
		muzzle.position.x = _muzzle_base_offset.x * facing_dir
		muzzle.position.y = y_offset
		muzzle.scale = Vector2(_muzzle_base_scale.x * float(facing_dir), _muzzle_base_scale.y)

	if muzzle_up:
		var show_up := aim_up and not is_crouching
		muzzle_up.visible = show_up
		if show_up:
			muzzle_up.position.x = _muzzle_up_base_offset.x * -facing_dir
			muzzle_up.position.y = _muzzle_up_base_offset.y
			muzzle_up.scale = Vector2(_muzzle_up_base_scale.x * float(facing_dir), _muzzle_up_base_scale.y)

	if muzzle_dash:
		muzzle_dash.visible = is_dashing
		muzzle_dash.position.x = _muzzle_dash_base_offset.x * facing_dir
		muzzle_dash.position.y = _muzzle_dash_base_offset.y
		muzzle_dash.scale = Vector2(_muzzle_dash_base_scale.x * float(facing_dir), _muzzle_dash_base_scale.y)

	if muzzle_crouch:
		muzzle_crouch.visible = is_crouching and not aim_up
		muzzle_crouch.position.x = _muzzle_crouch_base_offset.x * facing_dir
		muzzle_crouch.position.y = _muzzle_crouch_base_offset.y
		muzzle_crouch.scale = Vector2(_muzzle_crouch_base_scale.x * float(facing_dir), _muzzle_crouch_base_scale.y)

	if muzzle_up_crouch:
		muzzle_up_crouch.visible = is_crouching and aim_up
		if muzzle_up_crouch.visible:
			muzzle_up_crouch.position.x = _muzzle_up_crouch_base_offset.x * -facing_dir
			muzzle_up_crouch.position.y = _muzzle_up_crouch_base_offset.y
			muzzle_up_crouch.scale = Vector2(_muzzle_up_crouch_base_scale.x * float(facing_dir), _muzzle_up_crouch_base_scale.y)

	if normal_shape:
		normal_shape.position.x = _normal_shape_base_offset.x * -facing_dir
		normal_shape.position.y = _normal_shape_base_offset.y
		normal_shape.scale = Vector2(_normal_shape_base_scale.x * float(facing_dir), _normal_shape_base_scale.y)

	if slide_shape:
		slide_shape.position.x = _slide_shape_base_offset.x * facing_dir
		slide_shape.position.y = _slide_shape_base_offset.y
		slide_shape.scale = Vector2(_slide_shape_base_scale.x * float(facing_dir), _slide_shape_base_scale.y)

	if head_shape:
		head_shape.position.x = _head_shape_base_offset.x * -facing_dir
		head_shape.position.y = _head_shape_base_offset.y
		head_shape.scale = Vector2(_head_shape_base_scale.x * float(facing_dir), _head_shape_base_scale.y)

# ---------------------
# Animation signals
# ---------------------
func _on_animation_finished() -> void:
	var a := animated_sprite.animation
	is_jumping = false

	if a != "" and a.find("Shoot") != -1:
		_shooting_anim_playing = false
		shooting = false
		_shot_fired_in_animation = false
		_shot_dir_locked = false
		_locked_shot_dir = Vector2.ZERO

		# consume buffered jump if present
		if jump_buffer_timer > 0 and not is_dashing and jumps_left == MAX_JUMPS and (is_on_floor() or coyote_timer > 0):
			jumps_left -= 1
			jump_buffer_timer = 0
			coyote_timer = 0
			is_jumping = true
			aim_up = false
			_change_state(STATE_JUMP)
			_start_jump_sequence()
			return

		if is_dashing:
			animated_sprite.play("Dash")
		else:
			_change_state(_state_for_motion_and_flags())
		return

	_change_state(_state_for_motion_and_flags())

func _on_frame_changed() -> void:
	# pre-aim handling
	if pre_aiming:
		if aim_up or aiming:
			pre_aiming = false
			shooting = true
			_change_state(_state_for_motion_and_flags())
			return

		pre_aim_frames -= 1
		if pre_aim_frames <= 0:
			pre_aiming = false
			shooting = true
			_change_state(_state_for_motion_and_flags())
			return

	# spawn bullet on SHOT_FRAME (single shared frame)
	var anim_name := animated_sprite.animation
	if anim_name != "" and anim_name.find("Shoot") != -1 and not _shot_fired_in_animation:
		if animated_sprite.frame == SHOT_FRAME:
			_shot_fired_in_animation = true
			_spawn_bullet_from_muzzle()
