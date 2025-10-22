extends CharacterBody2D
class_name player

# ----------------------------
# Exports
# ----------------------------
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

# ----------------------------
# State enum (expanded)
# ----------------------------
enum {
	STATE_IDLE,
	STATE_WALK,
	STATE_RUN,
	STATE_JUMP,
	STATE_FALL,
	STATE_DASH,
	STATE_AIM,
	STATE_SHOOT,
	STATE_SHOOT_IDLE,
	STATE_SHOOT_WALK,
	STATE_SHOOT_RUN,
	STATE_SHOOT_JUMP,
	STATE_SHOOT_FALL,

	STATE_AIM_UP,
	STATE_SHOOT_UP,
	STATE_SHOOT_UP_IDLE,
	STATE_SHOOT_UP_WALK,
	STATE_SHOOT_UP_RUN,
	STATE_SHOOT_UP_JUMP,
	STATE_SHOOT_UP_FALL,
}

# ----------------------------
# Onready nodes
# ----------------------------
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

	if shooting:
		_change_state(_shoot_state_for_motion())
		return

	if pre_aiming:
		return

	if not is_dashing and not is_hit:
		_select_state_from_motion()

	# prefer AimUp when requested (unless dashing/hit/shooting)
	if aim_up and not (is_dashing or is_hit or shooting or pre_aiming):
		_change_state(STATE_AIM_UP)
	elif aiming and not (is_dashing or is_hit or shooting or pre_aiming):
		_change_state(STATE_AIM)

func _require_play(name: String) -> void:
	if not animated_sprite:
		push_error("AnimatedSprite2D node missing (animated_sprite is null).")
		assert(false, "AnimatedSprite2D node missing.")
	if not animated_sprite.sprite_frames:
		push_error("sprite_frames missing on AnimatedSprite2D.")
		assert(false, "sprite_frames missing.")
		assert(animated_sprite.sprite_frames.has_animation(name), "Missing animation: " + name)
	# flip before play so animation uses correct facing immediately
	animated_sprite.flip_h = facing_dir > 0
	animated_sprite.play(name)

func _play_anim_with_aim(base_name: String) -> void:
	var motion := base_name  # e.g. "Idle","Walk","Run","Jump","Fall","Dash"
	var anim_name: String
	
	if base_name == "Jump" or base_name == "Fall":
		if aiming and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Aim" + base_name):
			_require_play("Aim" + base_name)
			return
		_require_play(base_name)
		return

	if is_crouching:
		if aim_up:
			anim_name = "CrouchAimUp" + motion
		elif aiming:
			anim_name = "CrouchAim" + motion
		else:
			anim_name = "Crouch" + motion
	else:
		if aim_up:
			anim_name = "AimUp" + motion
		elif aiming:
			anim_name = "Aim" + motion
		else:
			anim_name = motion  # e.g. "Idle", "Walk"

	_require_play(anim_name)

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

	# Crouch handling
	var crouch_pressed := Input.is_action_pressed("Crouch")
	var want_crouch := crouch_pressed and is_on_floor() and not is_dashing and not is_hit
	if want_crouch != is_crouching:
		is_crouching = want_crouch
		if is_crouching:
			velocity.x = 0

	_update_muzzle_transform()

	# Dash (can't start while shooting or crouching)
	if Input.is_action_just_pressed("Dash") and not shooting and not is_crouching:
		_start_dash()

	# Aim & AimUp (Up is a dedicated Input action)
	aiming = Input.is_action_pressed("Aim")
	aim_up = Input.is_action_pressed("Up") and is_on_floor() and not is_dashing

	# Shoot handling
	if Input.is_action_just_pressed("Shoot") and not shooting and not pre_aiming:
		if is_dashing and _slide_shoot_cd <= 0.0:
			_do_slide_shoot()
			_slide_shoot_cd = SLIDE_SHOOT_COOLDOWN
		else:
			if aim_up or aiming:
				shooting = true
				_change_state(_shoot_state_for_motion())
			else:
				# pre-aim before shot
				pre_aiming = true
				pre_aim_frames = PRE_AIM_FRAME_COUNT
				var base_motion := _get_motion_name_from_velocity()
				var aim_anim := ( "AimUp" + base_motion if aim_up else "Aim" + base_motion )
				if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(aim_anim):
					animated_sprite.play(aim_anim)
				elif aim_up and animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("AimUp"):
					animated_sprite.play("AimUp")
				elif animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Aim"):
					animated_sprite.play("Aim")
				else:
					_change_state(STATE_AIM)

	# pre-aim cancels while dashing or hit
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
	if is_on_floor():
		velocity.x = 0
		var abs_vx = abs(velocity.x)
		_change_state(STATE_IDLE if abs_vx == 0 else STATE_WALK)
	else:
		_change_state(STATE_FALL)
	_set_collision_mode(false)

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

		if shooting:
			_change_state(_shoot_state_for_motion())
		elif aim_up:
			_change_state(STATE_AIM_UP)
		elif aiming:
			_change_state(STATE_AIM)
		else:
			_change_state(STATE_IDLE if velocity.x == 0 else STATE_WALK)

func _select_state_from_motion() -> void:
	var abs_vx = abs(velocity.x)
	if not is_on_floor():
		_change_state(STATE_JUMP if velocity.y < 0 else STATE_FALL)
	else:
		if abs_vx == 0:
			_change_state(STATE_IDLE)
		elif abs_vx > WALK_SPEED:
			_change_state(STATE_RUN)
		else:
			_change_state(STATE_WALK)

# ----------------------------
# Animation & State change ---
# ----------------------------
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
			_require_play("Dash")
		STATE_AIM:
			var motion := _get_motion_name_from_velocity()
			if is_crouching:
				_require_play("CrouchAimIdle")
			else:
				_require_play("Aim" + motion)
		STATE_AIM_UP:
			var motion := _get_motion_name_from_velocity()
			if motion == "Jump" or motion == "Fall":
				_require_play(motion)
			else:
				if is_crouching:
					_require_play("CrouchAimUpIdle")
				else:
					_require_play("AimUp" + motion)

		STATE_SHOOT:
			_shot_fired_in_animation = false
			var motion := _get_motion_name_from_velocity()
			if is_crouching:
				_require_play("CrouchShoot" + motion)
			else:
				_require_play("Shoot" + motion)
		STATE_SHOOT_IDLE:
			_shot_fired_in_animation = false
			if is_crouching:
				_require_play("CrouchShootIdle")
			else:
				_require_play("ShootIdle")
		STATE_SHOOT_WALK:
			_shot_fired_in_animation = false
			if is_crouching:
				_require_play("CrouchShootWalk")
			else:
				_require_play("ShootWalk")
		STATE_SHOOT_RUN:
			_shot_fired_in_animation = false
			if is_crouching:
				_require_play("CrouchShootRun")
			else:
				_require_play("ShootRun")
		STATE_SHOOT_JUMP:
			_shot_fired_in_animation = false
			if is_crouching:
				_require_play("CrouchShootJump")
			else:
				_require_play("ShootJump")
		STATE_SHOOT_FALL:
			_shot_fired_in_animation = false
			if is_crouching:
				_require_play("CrouchShootFall")
			else:
				_require_play("ShootFall")
		STATE_SHOOT_UP:
			_shot_fired_in_animation = false
			var motion_up := _get_motion_name_from_velocity()
			if is_crouching:
				_require_play("CrouchShootUp" + motion_up)
			else:
				_require_play("ShootUp" + motion_up)
		STATE_SHOOT_UP_IDLE:
			if is_crouching:
				_require_play("CrouchShootUpIdle")
			else:
				_require_play("ShootUpIdle")
		STATE_SHOOT_UP_WALK:
			if is_crouching:
				_require_play("CrouchShootUpWalk")
			else:
				_require_play("ShootUpWalk")
		STATE_SHOOT_UP_RUN:
			if is_crouching:
				_require_play("CrouchShootUpRun")
			else:
				_require_play("ShootUpRun")
		STATE_SHOOT_UP_JUMP:
			if is_crouching:
				_require_play("CrouchShootUpJump")
			else:
				_require_play("ShootUpJump")
		STATE_SHOOT_UP_FALL:
			if is_crouching:
				_require_play("CrouchShootUpFall")
			else:
				_require_play("ShootUpFall")

# map current motion -> shoot state (respects aim_up)
func _shoot_state_for_motion() -> int:
	var motion := _get_motion_name_from_velocity()
	if aim_up:
		match motion:
			"Idle":
				return STATE_SHOOT_UP_IDLE
			"Walk":
				return STATE_SHOOT_UP_WALK
			"Run":
				return STATE_SHOOT_UP_RUN
			"Jump":
				return STATE_SHOOT_UP_JUMP
			"Fall":
				return STATE_SHOOT_UP_FALL
			_:
				return STATE_SHOOT_UP
	else:
		match motion:
			"Idle":
				return STATE_SHOOT_IDLE
			"Walk":
				return STATE_SHOOT_WALK
			"Run":
				return STATE_SHOOT_RUN
			"Jump":
				return STATE_SHOOT_JUMP
			"Fall":
				return STATE_SHOOT_FALL
			_:
				return STATE_SHOOT

func _get_motion_name_from_velocity() -> String:
	var abs_vx = abs(velocity.x)
	if is_on_floor():
		if abs_vx == 0:
			return "Idle"
		if abs_vx > WALK_SPEED:
			return "Run"
		return "Walk"
	return "Jump" if velocity.y < 0 else "Fall"

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
		elif aim_up:
			_change_state(STATE_AIM_UP)
		elif aiming:
			_change_state(STATE_AIM)
		else:
			if is_on_floor():
				var abs_vx = abs(velocity.x)
				_change_state(STATE_IDLE if abs_vx == 0 else (STATE_RUN if abs_vx > WALK_SPEED else STATE_WALK))
			else:
				_change_state(STATE_JUMP if velocity.y < 0 else STATE_FALL)

func _on_frame_changed() -> void:
	if pre_aiming:
		if aim_up or aiming:
			pre_aiming = false
			shooting = true
			_change_state(_shoot_state_for_motion())
			return

		pre_aim_frames -= 1
		if pre_aim_frames <= 0:
			pre_aiming = false
			shooting = true
			_change_state(_shoot_state_for_motion())
			return

	var anim_name := animated_sprite.animation
	if shooting and anim_name != "" and anim_name.find("Shoot") != -1 and not _shot_fired_in_animation:
		_shot_fired_in_animation = true
		_spawn_bullet()

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
		_change_state(_shoot_state_for_motion())
	elif aim_up:
		_change_state(STATE_AIM_UP)
	elif aiming:
		_change_state(STATE_AIM)
	else:
		if is_on_floor():
			var abs_vx = abs(velocity.x)
			_change_state(STATE_IDLE if abs_vx == 0 else (STATE_RUN if abs_vx > WALK_SPEED else STATE_WALK))
		else:
			_change_state(STATE_JUMP if velocity.y < 0 else STATE_FALL)

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
