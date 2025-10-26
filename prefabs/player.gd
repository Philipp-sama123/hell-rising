extends CharacterBody2D
class_name player

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

# ----------
# States ---
# ----------
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
# Node references ---
# -------------------
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Node2D = $Muzzle
@onready var normal_shape: CollisionShape2D = $NormalShape
@onready var slide_shape: CollisionShape2D = $SlideShape

@onready var muzzle_up: Node2D = $"MuzzleUp"
@onready var muzzle_dash: Node2D = $"MuzzleDash"
@onready var muzzle_crouch: Node2D = $"MuzzleCrouch"
@onready var muzzle_up_crouch: Node2D = $"MuzzleUpCrouch"

# -----------------
# Runtime state ---
# -----------------
var state: int = STATE_IDLE
var facing_dir: int = 1

var was_on_floor: bool = false
var is_dashing: bool = false
var is_jumping: bool = false
var is_hit: bool = false

var aiming: bool = false
var aim_up: bool = false
var shooting: bool = false
var pre_aiming: bool = false
var pre_aim_frames: int = 0

var is_crouching: bool = false

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

# ----------
# _ready ---
# ----------
func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_on_frame_changed)

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

	_hit_timer = Timer.new()
	_hit_timer.one_shot = true
	add_child(_hit_timer)
	_hit_timer.wait_time = HIT_STUN_TIME
	_hit_timer.connect("timeout", Callable(self, "_on_hit_recovered"))

# -------------
# Main loop ---
# -------------
func _physics_process(delta: float) -> void:
	_slide_shoot_cd = max(0.0, _slide_shoot_cd - delta)

	_handle_input(delta)
	_apply_gravity(delta)
	_handle_horizontal()

	_update_slide_timer(delta)

	move_and_slide()
	_update_muzzle_transform()
	_handle_landing()

	was_on_floor = is_on_floor()
	if velocity.y >= 0:
		is_jumping = false

	# shooting handled by explicit state selection early
	if shooting:
		_change_state(_state_for_motion_and_flags())
		return

	if pre_aiming:
		return

	if _can_change_state():
		_change_state(_state_for_motion_and_flags())

# small helper to avoid repeating checks
func _can_change_state() -> bool:
	return not is_dashing and not is_hit

# ------------------
# Input handling ---
# ------------------

func _handle_input(delta: float) -> void:
	# update facing
	var axis_dir := int(Input.get_axis("Left", "Right"))
	if axis_dir != 0:
		facing_dir = axis_dir
	if animated_sprite:
		animated_sprite.flip_h = facing_dir > 0

	# read aim inputs first
	aiming = Input.is_action_pressed("Aim")
	aim_up = Input.is_action_pressed("Up") and is_on_floor() and not is_dashing

	# crouch
	var crouch_pressed := Input.is_action_pressed("Crouch")
	var want_crouch := crouch_pressed and is_on_floor() and not is_dashing
	if want_crouch != is_crouching:
		is_crouching = want_crouch
		if is_crouching:
			velocity.x = 0
		_change_state(_state_for_motion_and_flags())

	_update_muzzle_transform()

	# Dash: can't start while shooting or crouching
	if Input.is_action_just_pressed("Dash") and not shooting and not is_crouching and not is_hit:
		_start_dash()

	# Shoot: immediate, or slide-shoot if dashing
	if Input.is_action_just_pressed("Shoot") and not shooting:
		if is_dashing and _slide_shoot_cd <= 0.0:
			_do_slide_shoot()
			_slide_shoot_cd = SLIDE_SHOOT_COOLDOWN
		else:
			_shot_fired_in_animation = false
			shooting = true
			_change_state(_state_for_motion_and_flags())

	# cancel pre-aim if dashing/hit
	if is_dashing or is_hit:
		pre_aiming = false

	# Jump buffering & coyote
	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)

	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = max(coyote_timer - delta, 0)

	# consume buffered jump (first jump)
	if jump_buffer_timer > 0 and not is_dashing and jumps_left == MAX_JUMPS and (is_on_floor() or coyote_timer > 0):
		jumps_left -= 1
		jump_buffer_timer = 0
		coyote_timer = 0
		is_jumping = true
		aim_up = false
		_change_state(STATE_JUMP)
		_start_jump_sequence()
	# double jump immediate
	elif Input.is_action_just_pressed("Jump") and jumps_left > 0 and not is_dashing:
		jumps_left -= 1
		is_jumping = true
		velocity.y = 0
		aim_up = false
		_change_state(STATE_JUMP)
		_apply_jump_instant()
		jump_hold_timer = JUMP_HOLD_TIME

	jump_held = Input.is_action_pressed("Jump")

# ----------------
# Dash / slide ---
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
	slide_shape.set_deferred("disabled", not slide)
	normal_shape.set_deferred("disabled", slide)

func _update_slide_timer(delta: float) -> void:
	if not is_dashing:
		return
	_slide_time_elapsed += delta
	if _slide_time_elapsed >= SLIDE_MAX_TIME or (not Input.is_action_pressed("Dash") and _slide_time_elapsed >= SLIDE_MIN_TIME):
		_end_dash()

# ----------------------------
# Movement: gravity & horizontal
# ----------------------------
func _start_jump_sequence() -> void:
	# keep the previous behavior: delayed first-jump
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

func _handle_horizontal() -> void:
	if is_crouching:
		velocity.x = 0
		return

	if not is_dashing and not is_hit:
		var dir := int(Input.get_axis("Left", "Right"))
		var is_running := Input.is_action_pressed("Run")
		if dir != 0:
			velocity.x = dir * (RUN_SPEED if is_running else WALK_SPEED)
		else:
			velocity.x = move_toward(velocity.x, 0, WALK_SPEED)

# ----------------------------
# Landing & state selection
# ----------------------------
func _handle_landing() -> void:
	if not was_on_floor and is_on_floor():
		jumps_left = MAX_JUMPS
		jump_hold_timer = 0
		is_jumping = false
		if is_dashing:
			return
		_change_state(_state_for_motion_and_flags())

func _select_state_from_motion() -> void:
	_change_state(_state_for_motion_and_flags())

# ----------------------------
# State selection helpers (condensed)
# ----------------------------
func _state_for_motion_and_flags() -> int:
	# motion primitives
	var abs_vx = abs(velocity.x)
	var on_floor = is_on_floor()
	var motion_is_idle = on_floor and abs_vx < 0.01
	var motion_is_walk = on_floor and abs_vx >= 0.01 and abs_vx <= WALK_SPEED
	var motion_is_run  = on_floor and abs_vx > WALK_SPEED
	var airborne_up = not on_floor and velocity.y < 0

	# airborne branch
	if not on_floor:
		return _air_state_for_shoot_or_aim(airborne_up)

	# crouch -> only the idle-like crouch variants exist
	if is_crouching:
		if shooting:
			return STATE_CROUCH_SHOOTUP_IDLE if aim_up else STATE_CROUCH_SHOOT_IDLE
		if aim_up:
			return STATE_CROUCH_AIMUP_IDLE
		if aiming:
			return STATE_CROUCH_AIM_IDLE
		return STATE_CROUCH_IDLE

	# shooting on ground (aim-up handled separately)
	if shooting:
		if aim_up:
			if motion_is_idle:
				return STATE_SHOOTUP_IDLE
			elif motion_is_walk:
				return STATE_SHOOTUP_WALK
			else:
				return STATE_SHOOTUP_RUN
		if motion_is_idle:
			return STATE_SHOOT_IDLE
		if motion_is_walk:
			return STATE_SHOOT_WALK
		if motion_is_run:
			return STATE_SHOOT_RUN
		return STATE_SHOOT_IDLE

	# aim-up (ground)
	if aim_up:
		if motion_is_idle:
			return STATE_AIMUP_IDLE
		if motion_is_walk:
			return STATE_AIMUP_WALK
		return STATE_AIMUP_RUN

	# normal aim (ground)
	if aiming:
		if motion_is_idle:
			return STATE_AIM_IDLE
		if motion_is_walk:
			return STATE_AIM_WALK
		return STATE_AIM_RUN

	# plain motion states
	if motion_is_idle:
		return STATE_IDLE
	if motion_is_walk:
		return STATE_WALK
	return STATE_RUN

func _air_state_for_shoot_or_aim(airborne_up: bool) -> int:
	if shooting:
		return STATE_SHOOT_JUMP if airborne_up else STATE_SHOOT_FALL
	if aiming:
		return STATE_AIM_JUMP if airborne_up else STATE_AIM_FALL
	return STATE_JUMP if airborne_up else STATE_FALL

# ----------------------
# Animation handling ---
# ----------------------
func _require_play(_name: String) -> void:
	if not animated_sprite:
		push_error("AnimatedSprite2D node missing (animated_sprite is null).")
		assert(false, "AnimatedSprite2D node missing.")
	if not animated_sprite.sprite_frames:
		push_error("sprite_frames missing on AnimatedSprite2D.")
		assert(false, "sprite_frames missing.")
	animated_sprite.flip_h = facing_dir > 0
	assert(animated_sprite.sprite_frames.has_animation(_name), "Missing animation: " + _name)
	animated_sprite.play(_name)

func _change_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	var anim_name = _STATE_ANIM.get(state, "")
	if anim_name == "":
		push_warning("--- ERROR ---No animation mapping for state: " + str(state))
		return
	_require_play(anim_name)

# ----------------
# Damage / hit ---
# ----------------
func take_damage(_damage: int = 1, source_pos: Vector2 = Vector2.ZERO, knockback_strength: float = -1.0) -> void:
	if is_dashing:
		return

	pre_aiming = false
	is_hit = true
	if _hit_timer:
		_hit_timer.start(HIT_STUN_TIME)

	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5)
		var t = get_tree().create_timer(HIT_STUN_TIME)
		t.timeout.connect(Callable(self, "_restore_color"))

	var dir_x: int = 0
	if source_pos != Vector2.ZERO:
		dir_x = int(sign(global_position.x - source_pos.x))
		if dir_x == 0:
			dir_x = int(sign(velocity.x)) if abs(velocity.x) > 0.1 else -facing_dir
	else:
		dir_x = int(sign(velocity.x)) if abs(velocity.x) > 0.1 else -facing_dir

	if dir_x == 0:
		dir_x = 1

	var used_kb = knockback_strength if knockback_strength > 0.0 else hit_kb_strength
	velocity.x = dir_x * used_kb

func _on_hit_recovered() -> void:
	is_hit = false
	_change_state(_state_for_motion_and_flags())

func _restore_color() -> void:
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 1)

# -------------------------
# Slide-shoot / bullets ---
# -------------------------
func _do_slide_shoot() -> void:
	_spawn_bullet_from_muzzle()
	_shot_fired_in_animation = true
	animated_sprite.play("ShootDash")

	var t = get_tree().create_timer(max(0.08, SLIDE_SHOOT_COOLDOWN))
	t.timeout.connect(Callable(self, "_reset_shot_flag"))

func _reset_shot_flag() -> void:
	_shot_fired_in_animation = false

func _spawn_bullet_from_muzzle() -> void:
	if not BulletScene:
		print_debug("BulletScene not assigned; cannot spawn bullet.")
		return

	var b := BulletScene.instantiate()
	if not b:
		return

	var chosen_muzzle: Node2D = null

	if is_dashing and muzzle_dash:
		chosen_muzzle = muzzle_dash
	elif is_crouching and aim_up and muzzle_up_crouch:
		chosen_muzzle = muzzle_up_crouch
	elif is_crouching and muzzle_crouch:
		chosen_muzzle = muzzle_crouch
	elif aim_up and muzzle_up:
		chosen_muzzle = muzzle_up
	elif muzzle:
		chosen_muzzle = muzzle

	# fallback: compute a reasonable spawn position if no node present
	var spawn_pos: Vector2 = global_position + Vector2(facing_dir * 12, -4)
	if chosen_muzzle:
		spawn_pos = chosen_muzzle.global_position

	get_tree().current_scene.add_child(b)
	b.global_position = spawn_pos

	if not b.is_in_group("bullet"):
		b.add_to_group("bullet")
	if b.has_method("set_shooter_owner"):
		b.set_shooter_owner(self)

	var dir_vec := Vector2(facing_dir, 0)
	# aim-up should point straight up regardless of facing, but for a crouch-aim-up we also want up
	if aim_up:
		dir_vec = Vector2(0, -1)

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
# Muzzle transform update ---
# ---------------------------
func _update_muzzle_transform() -> void:
	# MAIN muzzle (used while standing / walking / run)
	if muzzle:
		var y_offset := _muzzle_base_offset.y
		if is_crouching:
			y_offset += 6
		if aim_up:
			# hide the forward muzzle when aiming up
			muzzle.visible = false
		else:
			muzzle.visible = true

		muzzle.position.x = _muzzle_base_offset.x * facing_dir
		muzzle.position.y = y_offset
		muzzle.scale.x = _muzzle_base_scale.x * float(facing_dir)
		muzzle.scale.y = _muzzle_base_scale.y

	if muzzle_up:
		if aim_up and not is_crouching:
			muzzle_up.visible = true
			var up_y := _muzzle_up_base_offset.y
			muzzle_up.position.x = _muzzle_up_base_offset.x * -facing_dir # shoot up is turned
			muzzle_up.position.y = up_y
			muzzle_up.scale.x = _muzzle_up_base_scale.x * float(facing_dir)
			muzzle_up.scale.y = _muzzle_up_base_scale.y
		else:
			muzzle_up.visible = false

	if muzzle_dash:
		muzzle_dash.visible = is_dashing
		muzzle_dash.position.x = _muzzle_dash_base_offset.x * facing_dir
		muzzle_dash.position.y = _muzzle_dash_base_offset.y
		muzzle_dash.scale.x = _muzzle_dash_base_scale.x * float(facing_dir)
		muzzle_dash.scale.y = _muzzle_dash_base_scale.y

	if muzzle_crouch:
		muzzle_crouch.visible = is_crouching and not aim_up
		muzzle_crouch.position.x = _muzzle_crouch_base_offset.x * facing_dir
		muzzle_crouch.position.y = _muzzle_crouch_base_offset.y
		muzzle_crouch.scale.x = _muzzle_crouch_base_scale.x * float(facing_dir)
		muzzle_crouch.scale.y = _muzzle_crouch_base_scale.y

	if muzzle_up_crouch:
		muzzle_up_crouch.visible = is_crouching and aim_up
		muzzle_up_crouch.position.x = _muzzle_up_crouch_base_offset.x * -facing_dir # shoot up is turned
		muzzle_up_crouch.position.y = _muzzle_up_crouch_base_offset.y
		muzzle_up_crouch.scale.x = _muzzle_up_crouch_base_scale.x * float(facing_dir)
		muzzle_up_crouch.scale.y = _muzzle_up_crouch_base_scale.y

# ---------------------
# Animation signals ---
# ---------------------

func _on_animation_finished() -> void:
	var a := animated_sprite.animation
	is_hit = false
	is_jumping = false

	if a != "" and a.find("Shoot") != -1:
		shooting = false
		_shot_fired_in_animation = false

		if is_dashing:
			animated_sprite.play("Dash")
		else:
			_change_state(_state_for_motion_and_flags())

func _on_frame_changed() -> void:
	# handle pre-aim frames
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

	# spawn bullet at shot frame if not already fired
	var anim_name := animated_sprite.animation
	if shooting and anim_name != "" and anim_name.find("Shoot") != -1 and not _shot_fired_in_animation:
		_shot_fired_in_animation = true
		_spawn_bullet_from_muzzle()
