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

enum {
	STATE_IDLE,
	STATE_WALK,
	STATE_RUN,
	STATE_JUMP,
	STATE_FALL,
	STATE_DASH,

	# aim variants
	STATE_AIM_IDLE,
	STATE_AIM_WALK,
	STATE_AIM_RUN,
	STATE_AIM_JUMP,
	STATE_AIM_FALL,

	# aim up variants
	STATE_AIMUP_IDLE,
	STATE_AIMUP_WALK,
	STATE_AIMUP_RUN,

	# crouch
	STATE_CROUCH_IDLE,
	STATE_CROUCH_AIM_IDLE,
	STATE_CROUCH_AIMUP_IDLE,
	STATE_CROUCH_SHOOT_IDLE,
	STATE_CROUCH_SHOOTUP_IDLE,

	# shoot
	STATE_SHOOT_IDLE,
	STATE_SHOOT_WALK,
	STATE_SHOOT_RUN,
	STATE_SHOOT_JUMP,
	STATE_SHOOT_FALL,

	# shoot up
	STATE_SHOOTUP_IDLE,
	STATE_SHOOTUP_WALK,
	STATE_SHOOTUP_RUN,

	# dash-shoot
	STATE_SHOOT_DASH
}

# ----------------------------
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

	# aim-up ground-only
	STATE_AIMUP_IDLE: "AimUpIdle",
	STATE_AIMUP_WALK: "AimUpWalk",
	STATE_AIMUP_RUN: "AimUpRun",

	# only idle-like crouch variants (no walk/run/jump/fall)
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

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Node2D = $Muzzle
@onready var normal_shape: CollisionShape2D = $NormalShape
@onready var slide_shape: CollisionShape2D = $SlideShape
@onready var muzzle_up: Node2D = $"MuzzleUp"

# ----------------------------
# Runtime state
# ----------------------------
var state: int = STATE_IDLE
var facing_dir: int = 1

# movement / dash / hit
var was_on_floor: bool = false
var is_dashing: bool = false
var is_jumping: bool = false
var is_hit: bool = false

# aiming & shooting
var aiming: bool = false
var aim_up: bool = false
var shooting: bool = false
var pre_aiming: bool = false
var pre_aim_frames: int = 0

# crouch
var is_crouching: bool = false

# jumps
const MAX_JUMPS: int = 2
var jumps_left: int = MAX_JUMPS

# timers for jump buffering / coyote
var coyote_time: float = 0.1
var coyote_timer: float = 0.0
var jump_buffer_time: float = 0.15
var jump_buffer_timer: float = 0.0

# jump hold
var jump_held: bool = false
var jump_hold_timer: float = 0.0

# timers / runtime helpers
var _hit_timer: Timer = null
var _slide_shoot_cd: float = 0.0
var _slide_time_elapsed: float = 0.0

# misc bullet/animation helpers
var _shot_fired_in_animation: bool = false
var _muzzle_base_offset: Vector2 = Vector2.ZERO
var _muzzle_base_scale: Vector2 = Vector2.ONE

var _muzzle_up_base_offset: Vector2 = Vector2.ZERO
var _muzzle_up_base_scale: Vector2 = Vector2.ONE

# ----------------------------
# Lifecycle
# ----------------------------
func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.frame_changed.connect(_on_frame_changed)

	if muzzle:
		_muzzle_base_offset = Vector2(abs(muzzle.position.x), muzzle.position.y)
		_muzzle_base_scale = muzzle.scale.abs()
	if muzzle_up:
		_muzzle_up_base_offset = Vector2(abs(muzzle_up.position.x), muzzle_up.position.y)
		_muzzle_up_base_scale = muzzle_up.scale.abs()

	# hit/stun timer, restartable
	_hit_timer = Timer.new()
	_hit_timer.one_shot = true
	add_child(_hit_timer)
	_hit_timer.wait_time = HIT_STUN_TIME
	_hit_timer.connect("timeout", Callable(self, "_on_hit_recovered"))

# ----------------------------
# Main loop
# ----------------------------
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

	# when shooting, the concrete state mapper will choose the correct shoot state
	if shooting:
		_change_state(_state_for_motion_and_flags())
		return

	if pre_aiming:
		return

	if not is_dashing and not is_hit:
		_select_state_from_motion()

	# prefer aim-up / aim when requested (choose concrete state)
	if aim_up and not (is_dashing or is_hit or shooting or pre_aiming):
		_change_state(_state_for_motion_and_flags())
	elif aiming and not (is_dashing or is_hit or shooting or pre_aiming):
		_change_state(_state_for_motion_and_flags())

func _require_play(_name: String) -> void:
	if not animated_sprite:
		push_error("AnimatedSprite2D node missing (animated_sprite is null).")
		assert(false, "AnimatedSprite2D node missing.")
	if not animated_sprite.sprite_frames:
		push_error("sprite_frames missing on AnimatedSprite2D.")
		assert(false, "sprite_frames missing.")
	# flip before play so animation uses correct facing immediately
	animated_sprite.flip_h = facing_dir > 0
	assert(animated_sprite.sprite_frames.has_animation(_name), "Missing animation: " + _name)
	animated_sprite.play(_name)

# ----------------------------
# Input handling
# ----------------------------
func _handle_input(delta: float) -> void:
	# facing from horizontal axis
	var dir := int(Input.get_axis("Left", "Right"))
	if dir != 0:
		facing_dir = dir
	if animated_sprite:
		animated_sprite.flip_h = facing_dir > 0

	# read aiming states early (so crouch logic below sees the current aim state)
	aiming = Input.is_action_pressed("Aim")
	aim_up = Input.is_action_pressed("Up") and is_on_floor() and not is_dashing

	# Crouch handling (hold-to-crouch). keep on-floor / not-dashing / not-hit requirement.
	var crouch_pressed := Input.is_action_pressed("Crouch")
	var want_crouch := crouch_pressed and is_on_floor() and not is_dashing
	if want_crouch != is_crouching:
		is_crouching = want_crouch
		if is_crouching:
			velocity.x = 0
		# refresh current motion animation so the crouch variant plays
		_change_state(_state_for_motion_and_flags())

	_update_muzzle_transform()

	# Dash (can't start while shooting or crouching)
	if Input.is_action_just_pressed("Dash") and not shooting and not is_crouching:
		_start_dash()

	# Shoot handling — immediate shooting, no pre-aiming delay
	if Input.is_action_just_pressed("Shoot") and not shooting:
		if is_dashing and _slide_shoot_cd <= 0.0:
			_do_slide_shoot()
			_slide_shoot_cd = SLIDE_SHOOT_COOLDOWN
		else:
			_shot_fired_in_animation = false
			shooting = true
			_change_state(_state_for_motion_and_flags())

	# pre-aim cancels while dashing or hit (kept harmless if pre_aiming is never set)
	if is_dashing or is_hit:
		pre_aiming = false

	# Jump buffering
	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)

	# coyote timer update
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = max(coyote_timer - delta, 0)

	if jump_buffer_timer > 0 and not is_dashing and jumps_left == MAX_JUMPS and (is_on_floor() or coyote_timer > 0):
		jumps_left -= 1
		jump_buffer_timer = 0
		coyote_timer = 0
		is_jumping = true
		aim_up = false 
		_change_state(STATE_JUMP)
		_apply_jump_velocity()
	elif Input.is_action_just_pressed("Jump") and jumps_left > 0 and not is_dashing:
		jumps_left -= 1
		is_jumping = true
		velocity.y = 0
		aim_up = false  # stop aiming up when jumping
		_change_state(STATE_JUMP)
		_apply_jump_instant()
		jump_hold_timer = JUMP_HOLD_TIME

	jump_held = Input.is_action_pressed("Jump")

# ----------------------------
# Dash helpers
# ----------------------------
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
	# after dash end pick proper concrete state
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
# Movement mechanics
# ----------------------------
func _apply_jump_velocity() -> void:
	# delayed first-jump (keeps original behavior)
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
# Landing & motion -> state
# ----------------------------
func _handle_landing() -> void:
	# landed this frame
	if not was_on_floor and is_on_floor():
		jumps_left = MAX_JUMPS
		jump_hold_timer = 0
		is_jumping = false

		# keep dash visual if still dashing
		if is_dashing:
			return

		_change_state(_state_for_motion_and_flags())

func _select_state_from_motion() -> void:
	var target := _state_for_motion_and_flags()
	_change_state(target)

# ----------------------------
# Animation & State change ---
# ----------------------------
func _change_state(new_state: int) -> void:
	# debug print left in for traceability
	# print("--- DEBUG --- change_state: ", new_state)
	if new_state == state:
		return

	state = new_state

	# lookup and play
	var anim_name = _STATE_ANIM.get(state, "")
	if anim_name == "":
		push_warning("No animation mapping for state: " + str(state))
		return
	_require_play(anim_name)

# map current motion -> explicit state (respects aim_up (ground-only), aiming, shooting, crouch)
func _state_for_motion_and_flags() -> int:
	# derive motion directly (no helper)
	var abs_vx = abs(velocity.x)
	var motion_is_idle = is_on_floor() and abs_vx < 0.01
	var motion_is_walk = is_on_floor() and abs_vx >= 0.01 and abs_vx <= WALK_SPEED
	var motion_is_run  = is_on_floor() and abs_vx > WALK_SPEED
	var airborne_up = not is_on_floor() and velocity.y < 0
	
	# airborne branch
	if not is_on_floor():
		# shooting airborne?
		if shooting:
			return STATE_SHOOT_JUMP if airborne_up else STATE_SHOOT_FALL
		# NOTE: aim_up is ignored in mid-air by design (no AimUp jump/fall)
		if aiming:
			return STATE_AIM_JUMP if airborne_up else STATE_AIM_FALL
		# default airborne
		return STATE_JUMP if airborne_up else STATE_FALL

	# ground: CROUCH is simplified to only idle-like variants (no walk/run/jump/fall)
	if is_crouching:
		# priority: shoot > aim_up > aim > plain crouch idle
		if shooting:
			if aim_up:
				return STATE_CROUCH_SHOOTUP_IDLE
			return STATE_CROUCH_SHOOT_IDLE
		if aim_up:
			return STATE_CROUCH_AIMUP_IDLE
		if aiming:
			return STATE_CROUCH_AIM_IDLE
		return STATE_CROUCH_IDLE

	# ground, not crouching
	if shooting:
		# aim up variants (ground only)
		if aim_up:
			if motion_is_idle:
				return STATE_SHOOTUP_IDLE
			elif motion_is_walk:
				return STATE_SHOOTUP_WALK
			else:
				return STATE_SHOOTUP_RUN
		# normal shoot
		if motion_is_idle:
			return STATE_SHOOT_IDLE
		if motion_is_walk:
			return STATE_SHOOT_WALK
		if motion_is_run:
			return STATE_SHOOT_RUN
		return STATE_SHOOT_IDLE

	if aim_up:
		if motion_is_idle:
			return STATE_AIMUP_IDLE
		if motion_is_walk:
			return STATE_AIMUP_WALK
		return STATE_AIMUP_RUN

	if aiming:
		if motion_is_idle:
			return STATE_AIM_IDLE
		if motion_is_walk:
			return STATE_AIM_WALK
		return STATE_AIM_RUN

	# plain motion states (ground)
	if motion_is_idle:
		return STATE_IDLE
	if motion_is_walk:
		return STATE_WALK
	return STATE_RUN

# ----------------------------
# Damage / hit
# ----------------------------
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

	# determine horizontal knockback direction
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

	print("[take_damage] src:", source_pos, " player:", global_position, " dir_x:", dir_x, " kb:", used_kb, " vel.x:", velocity.x)

func _on_hit_recovered() -> void:
	is_hit = false
	if shooting:
		_change_state(_state_for_motion_and_flags())
	else:
		_change_state(_state_for_motion_and_flags())

func _restore_color() -> void:
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 1)

# ----------------------------
# Slide-shoot / bullets
# ----------------------------
func _do_slide_shoot() -> void:
	_spawn_bullet()
	_shot_fired_in_animation = true
	animated_sprite.play("ShootDash")

	var t = get_tree().create_timer(max(0.08, SLIDE_SHOOT_COOLDOWN))
	t.timeout.connect(Callable(self, "_reset_shot_flag"))

func _reset_shot_flag() -> void:
	_shot_fired_in_animation = false

func _spawn_bullet() -> void:
	if not BulletScene:
		print_debug("BulletScene not assigned; cannot spawn bullet.")
		return

	var b := BulletScene.instantiate()
	if not b:
		return

	var spawn_pos: Vector2
	if aim_up and muzzle_up:
		spawn_pos = muzzle_up.global_position
	elif muzzle:
		spawn_pos = muzzle.global_position
	else:
		spawn_pos = global_position + Vector2(facing_dir * 12, -4)

	get_tree().current_scene.add_child(b)
	b.global_position = spawn_pos

	# add to group and set owner if available
	if not b.is_in_group("bullet"):
		b.add_to_group("bullet")
	if b.has_method("set_shooter_owner"):
		b.set_shooter_owner(self)

	# direction: straight up when aim_up else horizontal by facing_dir
	var dir_vec := Vector2(facing_dir, 0)
	if aim_up:
		dir_vec = Vector2(0, -1)

	# use bullet API to set direction or velocity
	if b.has_method("set_direction"):
		b.set_direction(dir_vec, BULLET_SPEED)
	elif b.has_method("set_velocity"):
		if b.has_variable("speed"):
			b.set_velocity(dir_vec * b.speed)
		else:
			b.set_velocity(dir_vec * BULLET_SPEED)

	# ensure visual rotation
	if b is Node2D:
		b.rotation = dir_vec.angle()

# ----------------------------
# Utilities
# ----------------------------
func _update_muzzle_transform() -> void:
	if not muzzle:
		return

	var y_offset := _muzzle_base_offset.y
	if is_crouching:
		y_offset += 6

	if aim_up:
		y_offset -= 6
		muzzle.visible = false
	else:
		muzzle.visible = true

	muzzle.position.x = _muzzle_base_offset.x * facing_dir
	muzzle.position.y = y_offset
	muzzle.scale.x = _muzzle_base_scale.x * float(facing_dir)
	muzzle.scale.y = _muzzle_base_scale.y

	if muzzle_up:
		if aim_up:
			muzzle_up.visible = true
			var up_y := _muzzle_up_base_offset.y - 6
			muzzle_up.position.x = _muzzle_up_base_offset.x * -facing_dir
			muzzle_up.position.y = up_y + (6 if is_crouching else 0)
			muzzle_up.scale.x = _muzzle_up_base_scale.x * float(facing_dir)
			muzzle_up.scale.y = _muzzle_up_base_scale.y
		else:
			muzzle_up.visible = false

# ----------------------------
# Animation signals
# ----------------------------
func _on_animation_finished() -> void:
	var a := animated_sprite.animation
	is_hit = false
	is_jumping = false

	# When a shoot animation finishes, revert shooting
	if a != "" and a.find("Shoot") != -1:
		shooting = false
		_shot_fired_in_animation = false

		if is_dashing:
			animated_sprite.play("Dash")
		else:
			_change_state(_state_for_motion_and_flags())

func _on_frame_changed() -> void:
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

	var anim_name := animated_sprite.animation
	if shooting and anim_name != "" and anim_name.find("Shoot") != -1 and not _shot_fired_in_animation:
		_shot_fired_in_animation = true
		_spawn_bullet()
