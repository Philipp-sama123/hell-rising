extends CharacterBody2D

signal attacked

# movement / detection
@export var SPEED: float = 200.0
@export var detection_range: float = 800.0
@export var stop_min: float = 50.0
@export var stop_max: float = 250.0

# melee / attack tuning
@export var attack_damage: int = 1
@export var attack_hit_window: float = 0.12   # how long damage collider stays active
@export var attack_range: float = 80.0        # horizontal range to allow melee
@export var attack_pause: float = 0.2         # wait this long between attacks

# nodes
@export var damage_area_node_path: NodePath = NodePath("DamageArea")
@export var player_path: NodePath = NodePath()

# sprite facing (true if the sprite faces right by default)
@export var sprite_faces_right: bool = true

# animations
const ANIM_WALK = "Walk"
const ANIM_IDLE = "Idle"
const ANIM_ATTACK = "Attack"
const ANIM_DIE = "Die"

# health / stun (kept simple)
@export var health: int = 3
@export var hit_flash_seconds: float = 0.15
@export var stun_seconds: float = 0.2
var _stun_timer: float = 0.0

# state machine
const STATE_IDLE = "idle"
const STATE_CHASE = "chase"
const STATE_ATTACK = "attack"
const STATE_COOLDOWN = "cooldown"
const STATE_DEAD = "dead"
var _state: String = STATE_IDLE

# runtime
var _player: Node = null
var _damage_area: Area2D = null
var _stop_distance: float = 60.0
var _attack_timer: float = 0.0    # counts down attack animation time
var _cooldown_timer: float = 0.0  # counts down pause between attacks
var _alive: bool = true

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	# player lookup (fallbacks)
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
		printerr("MeleeEnemy: couldn't find a player node. Set player_path or add player to 'player' group.")

	# damage area
	_damage_area = get_node_or_null(damage_area_node_path)
	if _damage_area and _damage_area is Area2D:
		_damage_area.monitoring = false
		_damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
	else:
		_damage_area = null

	# randomize stop distance
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	_stop_distance = rng.randf_range(stop_min, stop_max)

	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_anim_finished)


func _physics_process(delta: float) -> void:
	if _state == STATE_DEAD:
		return

	# stun handling (highest priority)
	if _stun_timer > 0.0:
		_stun_timer = max(_stun_timer - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, 1200 * delta)
		_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# countdown timers
	if _attack_timer > 0.0:
		_attack_timer = max(_attack_timer - delta, 0.0)
		# when attack animation time finishes, move to cooldown and explicitly play Idle
		if _attack_timer == 0.0 and _state == STATE_ATTACK:
			_state = STATE_COOLDOWN
			_cooldown_timer = attack_pause
			# ensure damage area is off and idle animation plays immediately
			_disable_damage_area()
			_play_anim(ANIM_IDLE)               # <-- explicit idle play on attack end

	if _cooldown_timer > 0.0:
		_cooldown_timer = max(_cooldown_timer - delta, 0.0)
		if _cooldown_timer == 0.0 and _state == STATE_COOLDOWN:
			_state = STATE_CHASE
			_play_anim(ANIM_WALK)               # <-- explicit walk when returning to chase

	# gravity
	if not is_on_floor():
		velocity += ProjectSettings.get_setting("physics/2d/default_gravity_vector") * ProjectSettings.get_setting("physics/2d/default_gravity") * delta

	# if no player: idle
	if not _player:
		_state = STATE_IDLE
		velocity.x = move_toward(velocity.x, 0, SPEED)
		_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	var to_player = _player.global_position - global_position
	var dist_x = abs(to_player.x)

	# face the player correctly using sprite_faces_right
	if animated_sprite:
		var player_left = _player.global_position.x < global_position.x
		animated_sprite.flip_h = (player_left != sprite_faces_right)   # <-- FIXED facing logic

	# out of detection range -> idle
	if dist_x > detection_range:
		_state = STATE_IDLE
		velocity.x = move_toward(velocity.x, 0, SPEED)
		_play_anim(ANIM_IDLE)
		move_and_slide()
		return

	# state handling
	if _state == STATE_IDLE:
		_state = STATE_CHASE

	if _state == STATE_CHASE:
		# if player is within attack_range, start attack
		if dist_x <= attack_range:
			_start_attack()
		else:
			# move horizontally toward player
			var dir = sign(to_player.x)
			velocity.x = dir * SPEED
			_play_anim(ANIM_WALK)

	elif _state == STATE_ATTACK:
		# during attack we remain stopped and play attack anim
		velocity.x = move_toward(velocity.x, 0, SPEED * 8)
		_play_anim(ANIM_ATTACK)

	elif _state == STATE_COOLDOWN:
		# stopped while waiting the pause
		velocity.x = move_toward(velocity.x, 0, SPEED * 8)
		_play_anim(ANIM_IDLE)

	move_and_slide()


func _start_attack() -> void:
	if _state == STATE_ATTACK or _state == STATE_COOLDOWN:
		return
	_state = STATE_ATTACK

	# compute animation duration if possible
	var anim_duration = 0.4
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_ATTACK):
		if animated_sprite.sprite_frames.has_method("get_frame_count"):
			var fc = animated_sprite.sprite_frames.get_frame_count(ANIM_ATTACK)
			var sp = 1.0
			if "speed" in animated_sprite:
				sp = max(animated_sprite.speed, 0.001)
			elif animated_sprite.has_method("get_speed"):
				sp = max(animated_sprite.get_speed(), 0.001)
			if fc > 0:
				anim_duration = float(fc) / sp

	_attack_timer = anim_duration
	# enable damage collider immediately for a short hit window
	if _damage_area:
		_damage_area.monitoring = true
		var t = get_tree().create_timer(attack_hit_window)
		t.timeout.connect(Callable(self, "_disable_damage_area"))

	_play_anim(ANIM_ATTACK)   # ensure attack animation is forced immediately
	emit_signal("attacked", self, _player.global_position)

func _disable_damage_area() -> void:
	if _damage_area:
		_damage_area.monitoring = false

func _on_damage_area_body_entered(body: Node) -> void:
	if _state == STATE_DEAD:
		return
	var is_player_body := false
	if body == _player:
		is_player_body = true
	elif body.has_method("is_in_group") and body.is_in_group("player"):
		is_player_body = true
	if not is_player_body:
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage)
	if body.has_method("add_impulse"):
		var kb_dir = (body.global_position - global_position).normalized()
		body.add_impulse(kb_dir * 120)

# damage / death
func take_damage(amount: int = 1) -> void:
	health -= amount
	_stun_timer = stun_seconds
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5)
	var t = get_tree().create_timer(hit_flash_seconds)
	t.timeout.connect(Callable(self, "_restore_color"))
	if health <= 0:
		_die()

func _restore_color() -> void:
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 1)

func _die() -> void:
	_state = STATE_DEAD
	_alive = false
	velocity = Vector2.ZERO
	if _damage_area:
		_damage_area.monitoring = false
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_DIE):
		animated_sprite.play(ANIM_DIE)
	else:
		queue_free()

func _on_anim_finished() -> void:
	var a = animated_sprite.animation
	if a == ANIM_DIE:
		queue_free()

# helper to play animation safely (no interrupt check - explicit play allowed)
func _play_anim(name: String) -> void:
	if not animated_sprite:
		return
	# only skip if already playing the requested anim
	if animated_sprite.animation == name:
		return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(name):
		animated_sprite.play(name)
