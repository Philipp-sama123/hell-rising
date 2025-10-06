extends CharacterBody2D

# --- tunables ---
@export var SPEED: float = 25.0
@export var attack_distance: float = 20.0
@export var attack_damage: int = 1
@export var attack_duration: float = 0.3    # how long the attack animation/hit window lasts
@export var idle_after_attack: float = 0.5  # idle pause after each attack
@export var damage_area_path: NodePath = NodePath("DamageArea")
@export var player_path: NodePath = NodePath()   # optional explicit player path
@export var sprite_faces_right: bool = true

# --- health / stun / knockback ---
@export var health: int = 3
@export var stun_seconds: float = 0.2
@export var hit_flash_seconds: float = 0.15
@export var kb_strength: float = 200.0        # knockback (x) applied to this enemy when damaged
@export var player_kb_strength: float = 120.0 # knockback (x) applied to player when hit

# --- nodes / runtime ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _player: Node = null
var _damage_area: Area2D = null

var _attack_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _attacking: bool = false

var _stun_timer: float = 0.0
var _alive: bool = true

func _ready() -> void:
	# find player (explicit path -> node named Player -> group 'player')
	if player_path != NodePath():
		_player = get_node_or_null(player_path)
	if not _player:
		_player = get_tree().get_root().find_node("Player", true, false) \
				  or get_tree().get_root().find_node("player", true, false)
	if not _player:
		var c = get_tree().get_nodes_in_group("player")
		if c.size() > 0:
			_player = c[0]
	if not _player:
		printerr("Enemy: couldn't find player. Set player_path or add player to 'player' group.")

	_damage_area = get_node_or_null(damage_area_path)
	if _damage_area and _damage_area is Area2D:
		_damage_area.monitoring = false
		_damage_area.body_entered.connect(Callable(self, "_on_damage_area_body_entered"))
	else:
		_damage_area = null

	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_anim_finished)


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	if _stun_timer > 0.0:
		_stun_timer = max(_stun_timer - delta, 0.0)

		velocity.x = move_toward(velocity.x, 0.0, 1200 * delta)
		_play("Idle")
		move_and_slide()
		return

	# timers for attack lifecycle
	if _attack_timer > 0.0:
		_attack_timer = max(_attack_timer - delta, 0.0)
		if _attack_timer == 0.0:
			# attack finished -> disable damage and go to idle cooldown
			_attacking = false
			_disable_damage_area()
			_cooldown_timer = idle_after_attack
			_play("Idle")
	elif _cooldown_timer > 0.0:
		_cooldown_timer = max(_cooldown_timer - delta, 0.0)
		# when that hits 0 we will decide to attack again or chase

	# gravity (keep vertical behavior)
	if not is_on_floor():
		velocity += ProjectSettings.get_setting("physics/2d/default_gravity_vector") \
					* ProjectSettings.get_setting("physics/2d/default_gravity") * delta

	# no player -> idle
	if not _player:
		_play("Idle")
		move_and_slide()
		return

	# facing
	var to_player = _player.global_position - global_position
	var dist = to_player.length()
	if animated_sprite:
		var player_left = _player.global_position.x < global_position.x
		animated_sprite.flip_h = (player_left != sprite_faces_right)

	# behavior: attack if close (and not already attacking/cooling), otherwise chase
	if dist <= attack_distance and _attack_timer == 0.0 and _cooldown_timer == 0.0:
		_start_attack()
	elif dist > attack_distance:
		# chase
		velocity.x = sign(to_player.x) * SPEED
		_play("Walk")
	else:
		# inside attack distance but in cooldown/attack: slow to stop
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 8)

	move_and_slide()


func _start_attack() -> void:
	_attacking = true
	_attack_timer = attack_duration
	if _damage_area:
		_damage_area.monitoring = true
		# disable damage area after attack_duration (safeguard)
		var t = get_tree().create_timer(attack_duration)
		t.timeout.connect(Callable(self, "_disable_damage_area"))
	_play("Attack")


func _disable_damage_area() -> void:
	if _damage_area:
		_damage_area.monitoring = false


func _on_damage_area_body_entered(body: Node) -> void:
	if not body:
		return
	# only damage player
	var is_player_body := body == _player or (body.has_method("is_in_group") and body.is_in_group("player"))
	if not is_player_body:
		return
	# apply damage if possible
	if body.has_method("take_damage"):
		body.take_damage(attack_damage)
	# try to apply knockback to player (x-axis only)
	if body.has_method("add_impulse"):
		var kb_dir_x = sign(body.global_position.x - global_position.x)
		if kb_dir_x == 0:
			kb_dir_x = 1
		body.add_impulse(Vector2(kb_dir_x * player_kb_strength, 0))


# --- enemy takes damage: reduces health, stuns, flashes and gets knocked back (x-only) ---
func take_damage(amount: int = 1, source_pos: Vector2 = Vector2.ZERO) -> void:
	if not _alive:
		return
	health -= amount
	# apply stun and visual flash
	_stun_timer = stun_seconds
	if animated_sprite:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5)
	var t = get_tree().create_timer(hit_flash_seconds)
	t.timeout.connect(Callable(self, "_restore_color"))
	# apply horizontal-only knockback to this enemy (preserve vertical velocity)
	var dir_x: float = 0.0
	if source_pos != Vector2.ZERO:
		dir_x = sign(global_position.x - source_pos.x)
		if dir_x == 0:
			dir_x = 1
	else:
		# fallback: push backwards based on facing
		if animated_sprite and (animated_sprite.flip_h == sprite_faces_right):
			dir_x = -1
		else:
			dir_x = 1
	velocity.x = dir_x * kb_strength

	# if dead now, play death
	if health <= 0:
		_die()


func _restore_color() -> void:
	if animated_sprite:
		animated_sprite.modulate = Color(1, 1, 1)


func _die() -> void:
	_alive = false
	_disable_damage_area()
	velocity = Vector2.ZERO
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Die"):
		_play("Die")
	else:
		queue_free()


func _on_anim_finished() -> void:
	if animated_sprite.animation == "Die":
		queue_free()


# safe animation play helper
func _play(name: String) -> void:
	if not animated_sprite:
		return
	if animated_sprite.animation == name:
		return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(name):
		animated_sprite.play(name)
