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
# State enum (expanded with shoot & aim-up states)
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

	# Aim up + shoot-up variants
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

var was_on_floor: bool = false
var is_dashing: bool = false
var is_jumping: bool = false
var is_hit: bool = false

var aiming: bool = false
var aim_up: bool = false                     # whether the player is holding Up (aiming up)
var shooting: bool = false
var pre_aiming: bool = false
var pre_aim_frames: int = 0

# crouch
var is_crouching: bool = false

const MAX_JUMPS: int = 2
var jumps_left: int = MAX_JUMPS

var coyote_time: float = 0.1
var coyote_timer: float = 0.0
var jump_buffer_time: float = 0.15
var jump_buffer_timer: float = 0.0

var jump_held: bool = false
var jump_hold_timer: float = 0.0

# timers / runtime helpers
var _hit_timer: Timer = null
var _slide_shoot_cd: float = 0.0
var _slide_time_elapsed: float = 0.0

# misc
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

	# hit/stun timer (restartable)
	_hit_timer = Timer.new()
	_hit_timer.one_shot = true
	add_child(_hit_timer)
	_hit_timer.wait_time = HIT_STUN_TIME
	_hit_timer.connect("timeout", Callable(self, "_on_hit_recovered"))

# ----------------------------
# Main loop
# ----------------------------
func _physics_process(delta: float) -> void:
	# cooldowns
	_slide_shoot_cd = max(0.0, _slide_shoot_cd - delta)

	_handle_input(delta)
	_apply_gravity(delta)
	_handle_horizontal()

	# slide timer / hold logic
	_update_slide_timer(delta)

	move_and_slide()
	_handle_landing()

	# post-move housekeeping
	was_on_floor = is_on_floor()
	if velocity.y >= 0:
		is_jumping = false

	# state precedence
	if shooting:
		_change_state(_shoot_state_for_motion())
		return

	if pre_aiming:
		return

	if not is_dashing and not is_hit:
		_select_state_from_motion()

	# prefer AimUp when aim_up is true
	if aim_up and not (is_dashing or is_hit or shooting or pre_aiming):
		_change_state(STATE_AIM_UP)
	elif aiming and not (is_dashing or is_hit or shooting or pre_aiming):
		_change_state(STATE_AIM)

# ----------------------------
# Helpers for animations
# ----------------------------
func _has_anim(_name: String) -> bool:
	return animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(_name)

# central helper that prefers crouch variants, aim_up, aim, then base
func _play_anim_with_aim(base_name: String) -> void:
	if animated_sprite:
		animated_sprite.flip_h = facing_dir > 0

	# 1) crouch-specific (if crouching)
	if is_crouching and animated_sprite and animated_sprite.sprite_frames:
		# prefer crouch aim up / crouch aim
		if aim_up and _has_anim("CrouchAimUp"):
			animated_sprite.play("CrouchAimUp"); return
		if aiming and _has_anim("CrouchAim"):
			animated_sprite.play("CrouchAim"); return
		# try generic Crouch + base (CrouchIdle / CrouchWalk etc)
		var cbase := "Crouch" + base_name
		if _has_anim(cbase):
			animated_sprite.play(cbase); return
		# fallback to CrouchIdle if we're crouching and base is Idle or not found
		if _has_anim("CrouchIdle"):
			animated_sprite.play("CrouchIdle"); return

	# 2) aim up
	if aim_up and animated_sprite and animated_sprite.sprite_frames:
		var aim_up_name := "AimUp" + base_name
		if animated_sprite.sprite_frames.has_animation(aim_up_name):
			animated_sprite.play(aim_up_name); return
		if base_name == "Idle" and animated_sprite.sprite_frames.has_animation("AimUp"):
			animated_sprite.play("AimUp"); return

	# 3) aim
	if aiming and animated_sprite and animated_sprite.sprite_frames:
		var aim := "Aim" + base_name
		if animated_sprite.sprite_frames.has_animation(aim):
			animated_sprite.play(aim); return
		if base_name == "Idle" and animated_sprite.sprite_frames.has_animation("Aim"):
			animated_sprite.play("Aim"); return

	# 4) base
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(base_name):
		animated_sprite.play(base_name); return

	# final fallback
	if animated_sprite:
		animated_sprite.play("Idle")

# ----------------------------
# Input handling
# ----------------------------
func _handle_input(delta: float) -> void:
	var dir := int(Input.get_axis("Left", "Right"))
	if dir != 0:
		facing_dir = dir

	if animated_sprite:
		animated_sprite.flip_h = facing_dir > 0

	_update_muzzle_transform()

	# Dash (don't start dash while actively shooting)
	if Input.is_action_just_pressed("Dash") and not shooting and not is_crouching:
		_start_dash()

	# Aim & AimUp (Up is a dedicated Input action in your project)
	aiming = Input.is_action_pressed("Aim")
	# allow aim_up while on the floor OR while crouching (and not dashing)
	aim_up = Input.is_action_pressed("Up") and (is_on_floor() or is_crouching) and not is_dashing

	# Shoot handling
	if Input.is_action_just_pressed("Shoot") and not shooting and not pre_aiming:
		# slide-shoot (immediate) while dashing
		if is_dashing and _slide_shoot_cd <= 0.0:
			_do_slide_shoot()
			_slide_shoot_cd = SLIDE_SHOOT_COOLDOWN
		else:
			# If aiming up, start the shoot-up state
			if aim_up:
				shooting = true
				_change_state(_shoot_state_for_motion())
			elif aiming:
				shooting = true
				_change_state(_shoot_state_for_motion())
			else:
				# pre-aim (normal aim or aim_up) — use central helper
				pre_aiming = true
				pre_aim_frames = PRE_AIM_FRAME_COUNT
				var base_motion := _get_motion_name_from_velocity()
				# let _play_anim_with_aim pick the correct Aim / AimUp / CrouchAim / CrouchAimUp variant
				_play_anim_with_aim(base_motion)

	# pre-aim cancels while dashing/hit
	if is_dashing or is_hit:
		pre_aiming = false

	# rest of the function unchanged...
	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)

	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = max(coyote_timer - delta, 0)

	# Jump logic (buffered jump)
	if jump_buffer_timer > 0 and not is_dashing and jumps_left == MAX_JUMPS and (is_on_floor() or coyote_timer > 0):
		jumps_left -= 1
		jump_buffer_timer = 0
		coyote_timer = 0
		is_jumping = true
		# stop aiming up when jumping
		aim_up = false
		_change_state(STATE_JUMP)
		_apply_jump_velocity()
	# Immediate jump (double jump)
	elif Input.is_action_just_pressed("Jump") and jumps_left > 0 and not is_dashing:
		jumps_left -= 1
		is_jumping = true
		velocity.y = 0
		# stop aiming up when jumping
		aim_up = false
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
# Movement
# ----------------------------
func _apply_jump_velocity() -> void:
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
	# if crouching, ignore horizontal input (no movement while crouched)
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
# Landing
# ----------------------------
func _handle_landing() -> void:
	# landing event happened this frame
	if not was_on_floor and is_on_floor():
		jumps_left = MAX_JUMPS
		jump_hold_timer = 0
		is_jumping = false

		# do not override dash state/animation if still dashing
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
# Animation & State change (crouch-aware)
# ----------------------------
func _play_crouch_shoot_variant(prefix: String, motion: String) -> bool:
	# Try crouch-specific shoot animations. Return true if played.
	var names := [prefix + motion, prefix, "Crouch" + prefix + motion, "Crouch" + prefix, "CrouchShoot", "CrouchShoot" + motion]
	for n in names:
		if _has_anim(n):
			animated_sprite.play(n)
			return true
	return false

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
			_play_anim_with_aim(_get_motion_name_from_velocity())
		STATE_AIM_UP:
			# AimUp variants: try AimUp<Motion>, then AimUp
			var am := _get_motion_name_from_velocity()
			var aim_up_name := "AimUp" + am
			if _has_anim(aim_up_name):
				animated_sprite.play(aim_up_name)
			elif _has_anim("AimUp"):
				animated_sprite.play("AimUp")
			# crouch preference handled in _play_anim_with_aim fallback
			else:
				_play_anim_with_aim(am)

		# Generic shoot: try to play Shoot<Motion>, fallback to Shoot, then motion animation
		STATE_SHOOT:
			_shot_fired_in_animation = false
			var bm := _get_motion_name_from_velocity()
			# crouch-specific shoot first
			if is_crouching and _play_crouch_shoot_variant("Shoot", bm):
				return
			var mn := "Shoot" + bm
			if _has_anim(mn):
				animated_sprite.play(mn); return
			if _has_anim("Shoot"):
				animated_sprite.play("Shoot"); return
			_play_anim_with_aim(bm)

		# Specific Shoot states prefer Shoot<Motion>
		STATE_SHOOT_IDLE:
			if is_crouching and _play_crouch_shoot_variant("ShootIdle", "Idle"):
				return
			if _has_anim("ShootIdle"):
				animated_sprite.play("ShootIdle")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Idle")

		STATE_SHOOT_WALK:
			if is_crouching and _play_crouch_shoot_variant("ShootWalk", "Walk"):
				return
			if _has_anim("ShootWalk"):
				animated_sprite.play("ShootWalk")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Walk")

		STATE_SHOOT_RUN:
			if is_crouching and _play_crouch_shoot_variant("ShootRun", "Run"):
				return
			if _has_anim("ShootRun"):
				animated_sprite.play("ShootRun")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Run")

		STATE_SHOOT_JUMP:
			if is_crouching and _play_crouch_shoot_variant("ShootJump", "Jump"):
				return
			if _has_anim("ShootJump"):
				animated_sprite.play("ShootJump")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Jump")

		STATE_SHOOT_FALL:
			if is_crouching and _play_crouch_shoot_variant("ShootFall", "Fall"):
				return
			if _has_anim("ShootFall"):
				animated_sprite.play("ShootFall")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Fall")

		# ----------------------------
		# Aim-Up specific shooting states
		STATE_SHOOT_UP:
			_shot_fired_in_animation = false
			var bm_up := _get_motion_name_from_velocity()
			# crouch-specific shoot-up first
			if is_crouching and (_has_anim("CrouchShootUp" + bm_up) or _has_anim("CrouchShootUp")):
				if _has_anim("CrouchShootUp" + bm_up):
					animated_sprite.play("CrouchShootUp" + bm_up); return
				animated_sprite.play("CrouchShootUp"); return
			# try non-crouch ShootUp variants
			var mn_up := "ShootUp" + bm_up
			if _has_anim(mn_up):
				animated_sprite.play(mn_up); return
			if _has_anim("ShootUp"):
				animated_sprite.play("ShootUp"); return
			# fallback to generic shoot behavior
			_play_anim_with_aim(bm_up)

		STATE_SHOOT_UP_IDLE:
			if is_crouching and _has_anim("CrouchShootUpIdle"):
				animated_sprite.play("CrouchShootUpIdle")
			elif _has_anim("ShootUpIdle"):
				animated_sprite.play("ShootUpIdle")
			elif _has_anim("ShootUp"):
				animated_sprite.play("ShootUp")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Idle")

		STATE_SHOOT_UP_WALK:
			if is_crouching and _has_anim("CrouchShootUpWalk"):
				animated_sprite.play("CrouchShootUpWalk")
			elif _has_anim("ShootUpWalk"):
				animated_sprite.play("ShootUpWalk")
			elif _has_anim("ShootUp"):
				animated_sprite.play("ShootUp")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Walk")

		STATE_SHOOT_UP_RUN:
			if is_crouching and _has_anim("CrouchShootUpRun"):
				animated_sprite.play("CrouchShootUpRun")
			elif _has_anim("ShootUpRun"):
				animated_sprite.play("ShootUpRun")
			elif _has_anim("ShootUp"):
				animated_sprite.play("ShootUp")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Run")

		STATE_SHOOT_UP_JUMP:
			if is_crouching and _has_anim("CrouchShootUpJump"):
				animated_sprite.play("CrouchShootUpJump")
			elif _has_anim("ShootUpJump"):
				animated_sprite.play("ShootUpJump")
			elif _has_anim("ShootUp"):
				animated_sprite.play("ShootUp")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Jump")

		STATE_SHOOT_UP_FALL:
			if is_crouching and _has_anim("CrouchShootUpFall"):
				animated_sprite.play("CrouchShootUpFall")
			elif _has_anim("ShootUpFall"):
				animated_sprite.play("ShootUpFall")
			elif _has_anim("ShootUp"):
				animated_sprite.play("ShootUp")
			elif _has_anim("Shoot"):
				animated_sprite.play("Shoot")
			else:
				_play_anim_with_aim("Fall")

func _get_motion_name_from_velocity() -> String:
	var abs_vx = abs(velocity.x)
	if is_on_floor():
		if abs_vx == 0:
			return "Idle"
		if abs_vx > WALK_SPEED:
			return "Run"
		return "Walk"
	return "Jump" if velocity.y < 0 else "Fall"

# helper: map current motion → shoot state (respects aim_up)
func _shoot_state_for_motion() -> int:
	var motion := _get_motion_name_from_velocity()
	# if aiming up, choose shoot-up variants
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

func _on_animation_finished() -> void:
	var a := animated_sprite.animation
	is_hit = false
	is_jumping = false

	# When shoot animation ends, revert shooting state and switch to appropriate next state.
	if a != "" and a.find("Shoot") != -1:
		shooting = false
		_shot_fired_in_animation = false

		# if we're in the middle of a dash, ensure dash visual continues
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
		if aim_up:
			# if player pressed Up when pre-aiming, start shoot-up
			if aim_up:
				pre_aiming = false
				shooting = true
				_change_state(_shoot_state_for_motion())
				return
		else:
			if aiming:
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
	# invulnerable while sliding by design
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
			if abs(velocity.x) > 0.1:
				dir_x = int(sign(velocity.x))
			else:
				dir_x = -facing_dir
	else:
		if abs(velocity.x) > 0.1:
			dir_x = int(sign(velocity.x))
		else:
			dir_x = -facing_dir

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

	# Add bullet to scene and set position
	get_tree().current_scene.add_child(b)
	b.global_position = spawn_pos

	# mark as bullet group & owner
	if not b.is_in_group("bullet"):
		b.add_to_group("bullet")
	if b.has_method("set_shooter_owner"):
		b.set_shooter_owner(self)

	# Direction: straight up when aim_up, otherwise horizontal based on facing
	var dir_vec := Vector2(facing_dir, 0)
	if aim_up:
		dir_vec = Vector2(0, -1)

	# Use bullet API to set direction/velocity — bullet will set its rotation immediately
	if b.has_method("set_direction"):
		b.set_direction(dir_vec, BULLET_SPEED)
	elif b.has_method("set_velocity"):
		if b.has_variable("speed"):
			b.set_velocity(dir_vec * b.speed)
		else:
			b.set_velocity(dir_vec * BULLET_SPEED)

	# ensure bullet rotation is applied immediately even if its own helper missed it
	if b is Node2D:
		b.rotation = dir_vec.angle()

# ----------------------------
# Utilities
# ----------------------------
func _update_muzzle_transform() -> void:
	if not muzzle:
		return

	# regular muzzle (mirrored by facing_dir)
	var y_offset := _muzzle_base_offset.y
	# small visual bump down while crouching
	if is_crouching:
		y_offset += 6

	if aim_up:
		# hide the regular muzzle while aiming up
		y_offset -= 6
		muzzle.visible = false
	else:
		muzzle.visible = true

	muzzle.position.x = _muzzle_base_offset.x * facing_dir
	muzzle.position.y = y_offset
	muzzle.scale.x = _muzzle_base_scale.x * float(facing_dir)
	muzzle.scale.y = _muzzle_base_scale.y

	# muzzle_up: use mirrored position (keeps muzzle_up on correct side)
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
