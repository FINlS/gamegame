extends CharacterBody2D
class_name Enemy
## Простой враг ближнего боя без текстур (рисуется прямоугольником).
## Патрулирует, замечает игрока, преследует, бьёт с замахом (телеграф), потом восстанавливается.
##
## Слои: 1 = мир, 2 = враги, 3 = игрок. Враг сталкивается только с миром (слой 1),
## поэтому игрока не толкает и сам не выталкивается из него.
## Игрок бьёт врага через take_hit(), враг бьёт игрока через take_damage()
## (игрок должен быть в группе "player", скрипт player.gd добавляет её сам).

signal died

enum State { PATROL, CHASE, WINDUP, ATTACK, RECOVER, STAGGER }

@export_group("Stats")
@export var max_health := 30.0
@export var knockback := Vector2(220, -140)
@export var stagger_time := 0.25

@export_group("Movement")
@export var patrol_speed := 70.0
@export var chase_speed := 130.0
@export var patrol_time := 1.8              ## сколько идёт в одну сторону
@export var gravity_multiplier := 1.3

@export_group("Perception")
@export var sight_range := 260.0
@export var lose_range := 380.0             ## дальше этого теряет игрока
@export var sight_height := 90.0            ## на какой разнице высот ещё видит

@export_group("Attack")
@export var attack_range := 46.0            ## с какой дистанции начинает замах
@export var attack_damage := 15.0           ## сколько макс. стамины отнимает удар
@export var windup_time := 0.4              ## замах: окно, чтобы увернуться
@export var attack_active_time := 0.15
@export var recover_time := 0.6             ## после удара: окно, чтобы контратаковать
@export var attack_size := Vector2(44, 32)
@export var attack_offset := 34.0

@export_group("Art")
@export_file("*.png") var sheet_path := "res://art/flea_sheet.png"
@export var sprite_scale := 2.0
@export var body_size := Vector2(36, 30)   ## размер коллайдера
@export var feet_y := 30.0                 ## на какой строке кадра (из 32) стоят ноги

const ENEMY_ANIMS := [
	{"name": "walk", "frames": 4, "fps": 8.0},
	{"name": "windup", "frames": 1, "fps": 1.0, "loop": false},
	{"name": "attack", "frames": 2, "fps": 14.0, "loop": false},
	{"name": "recover", "frames": 1, "fps": 1.0, "loop": false},
	{"name": "stagger", "frames": 1, "fps": 1.0, "loop": false},
]

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var state: State = State.PATROL
var health := 0.0
var facing := 1.0

var _half := Vector2(14, 20)
var _state_timer := 0.0
var _flash_timer := 0.0
var _patrol_dir := 1.0
var _attack_hit := false
var _attack_area: Area2D
var _player: Node2D
var _sprite: AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemy")
	health = max_health

	# Своя форма на каждого врага: ресурс из сцены общий для всех экземпляров
	var rect := RectangleShape2D.new()
	rect.size = body_size
	$CollisionShape2D.shape = rect
	_half = body_size / 2.0

	# Зона удара: слой 0, видит слой 3 (игрок)
	_attack_area = Area2D.new()
	_attack_area.name = "AttackArea"
	_attack_area.collision_layer = 0
	_attack_area.collision_mask = 1 << 2
	_attack_area.monitoring = false
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = attack_size
	shape.shape = box
	_attack_area.add_child(shape)
	add_child(_attack_area)

	_setup_sprite()
	_set_state(State.PATROL)


func _physics_process(delta: float) -> void:
	velocity.y += gravity * gravity_multiplier * delta
	_state_timer -= delta
	_flash_timer = maxf(_flash_timer - delta, 0.0)

	match state:
		State.PATROL:
			_do_patrol()
		State.CHASE:
			_do_chase()
		State.WINDUP:
			_do_windup(delta)
		State.ATTACK:
			_do_attack(delta)
		State.RECOVER:
			_do_recover(delta)
		State.STAGGER:
			_do_stagger(delta)

	move_and_slide()
	_update_animation()
	queue_redraw()


# ---------------------------------------------------------------- состояния

func _do_patrol() -> void:
	facing = _patrol_dir
	velocity.x = _patrol_dir * patrol_speed

	var hit_wall := is_on_wall() and signf(get_wall_normal().x) == -_patrol_dir
	if hit_wall or not _has_floor_ahead(_patrol_dir) or _state_timer <= 0.0:
		_patrol_dir = -_patrol_dir
		_state_timer = patrol_time

	if _can_see_player():
		_set_state(State.CHASE)


func _do_chase() -> void:
	var p := _get_player()
	if p == null or global_position.distance_to(p.global_position) > lose_range:
		_set_state(State.PATROL)
		return

	var dx := p.global_position.x - global_position.x
	if dx != 0.0:
		facing = signf(dx)

	var dy := absf(p.global_position.y - global_position.y)
	if absf(dx) <= attack_range and dy < sight_height * 0.5:
		velocity.x = 0.0
		_set_state(State.WINDUP)
		return

	# Не прыгает в пропасть вслед за игроком
	velocity.x = facing * chase_speed if _has_floor_ahead(facing) else 0.0


func _do_windup(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
	if _state_timer <= 0.0:
		_set_state(State.ATTACK)


func _do_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
	if not _attack_hit:
		for body in _attack_area.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("take_damage"):
				_attack_hit = true
				body.take_damage(attack_damage, global_position)
				break
	if _state_timer <= 0.0:
		_set_state(State.RECOVER)


func _do_recover(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
	if _state_timer <= 0.0:
		_set_state(State.CHASE)


func _do_stagger(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
	if _state_timer <= 0.0:
		_set_state(State.CHASE)


func _set_state(new_state: State) -> void:
	state = new_state
	match new_state:
		State.PATROL:
			_state_timer = patrol_time
		State.WINDUP:
			_state_timer = windup_time
			_attack_area.position = Vector2(facing * attack_offset, 0.0)
		State.ATTACK:
			_state_timer = attack_active_time
			_attack_hit = false
		State.RECOVER:
			_state_timer = recover_time
		State.STAGGER:
			_state_timer = stagger_time
	# Зона включается уже на замахе, чтобы к удару список пересечений был готов
	_attack_area.monitoring = new_state == State.WINDUP or new_state == State.ATTACK


# ---------------------------------------------------------------------- урон

## Вызывается игроком при попадании.
func take_hit(damage: float, from_pos: Vector2) -> void:
	health -= damage
	_flash_timer = 0.1
	if health <= 0.0:
		died.emit()
		queue_free()
		return

	var dir := signf(global_position.x - from_pos.x)
	if dir == 0.0:
		dir = 1.0
	velocity = Vector2(dir * knockback.x, knockback.y)
	_set_state(State.STAGGER)


# ------------------------------------------------------------------- вспомогательное

func _setup_sprite() -> void:
	if not ResourceLoader.exists(sheet_path):
		return
	var tex := load(sheet_path) as Texture2D
	if tex == null:
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Visual"
	_sprite.sprite_frames = SpriteSheet.build(tex, Vector2i(32, 32), ENEMY_ANIMS)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * sprite_scale
	# Центр кадра = 16, ноги на feet_y: ставим их на нижний край коллайдера
	_sprite.position = Vector2(0.0, _half.y - (feet_y - 16.0) * sprite_scale)
	add_child(_sprite)
	_sprite.play("walk")


func _update_animation() -> void:
	if _sprite == null:
		return
	var anim := "walk"
	match state:
		State.WINDUP:
			anim = "windup"
		State.ATTACK:
			anim = "attack"
		State.RECOVER:
			anim = "recover"
		State.STAGGER:
			anim = "stagger"
	if _sprite.animation != anim:
		_sprite.play(anim)
	# Ходьба замирает, когда враг стоит
	_sprite.speed_scale = 1.0 if (anim != "walk" or absf(velocity.x) > 5.0) else 0.0
	_sprite.flip_h = facing < 0.0
	_sprite.modulate = Color(2.2, 2.2, 2.2) if _flash_timer > 0.0 else Color.WHITE


func _get_player() -> Node2D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player


func _can_see_player() -> bool:
	var p := _get_player()
	if p == null:
		return false
	return global_position.distance_to(p.global_position) <= sight_range \
			and absf(p.global_position.y - global_position.y) <= sight_height


## Луч вниз перед врагом: есть ли там пол (чтобы не сходить с платформы).
func _has_floor_ahead(dir: float) -> bool:
	var origin := global_position + Vector2(dir * (_half.x + 6.0), _half.y - 4.0)
	var query := PhysicsRayQueryParameters2D.create(
			origin, origin + Vector2(0.0, 24.0), collision_mask, [get_rid()])
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _draw() -> void:
	var color := Color(0.75, 0.2, 0.2)
	match state:
		State.WINDUP:
			color = Color(1.0, 0.8, 0.2)
		State.RECOVER:
			color = Color(0.45, 0.2, 0.2)
		State.STAGGER:
			color = Color(0.9, 0.5, 0.5)
	if _flash_timer > 0.0:
		color = Color.WHITE

	if _sprite == null:
		draw_rect(Rect2(-_half, _half * 2.0), color)
		draw_rect(Rect2(Vector2(facing * _half.x * 0.5 - 3.0, -_half.y * 0.5), Vector2(6, 6)), Color.BLACK)

	# Телеграф удара: игрок видит, куда и когда прилетит
	if state == State.WINDUP or state == State.ATTACK:
		var alpha := 0.25 if state == State.WINDUP else 0.55
		var area := Rect2(Vector2(facing * attack_offset, 0.0) - attack_size / 2.0, attack_size)
		draw_rect(area, Color(1.0, 0.2, 0.2, alpha))

	# Полоска здоровья
	var w := _half.x * 2.0
	var top := -_half.y - 8.0
	if _sprite != null:
		top = _sprite.position.y + (5.0 - 16.0) * sprite_scale - 8.0
	draw_rect(Rect2(Vector2(-_half.x, top), Vector2(w, 4.0)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(Vector2(-_half.x, top), Vector2(w * clampf(health / max_health, 0.0, 1.0), 4.0)), Color.LIME_GREEN)
