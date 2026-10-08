extends CharacterBody2D
class_name Player
## Игрок: стамина вместо HP, адреналин, прыжок и дэш с зажатием.
##
## Сцена: Player (CharacterBody2D, этот скрипт)
##        ├─ CollisionShape2D   (обязательно с таким именем)
##        └─ Sprite2D / AnimatedSprite2D (флипай через flip_h, а не scale.x)
## Плюс любой StaticBody2D с коллизией в качестве пола.

signal stamina_changed(current: float, max_value: float, bonus: float)
signal adrenaline_changed(value: float)
signal died

enum State { NORMAL, DASH_HOVER, DASH }

@export_group("Stamina")
@export var max_stamina_start := 100.0
@export var regen_rate := 25.0            ## стамина в секунду
@export var regen_delay := 0.6            ## пауза после траты, прежде чем пойдёт восстановление
@export var emergency_threshold := 0.3    ## доля от макс. стамины, ниже которой "экстренная ситуация"
@export var hurt_knockback := Vector2(260, -180)  ## отдача при уроне
@export var hurt_stun_time := 0.15                ## сколько нельзя управлять горизонталью
@export var invulnerable_time := 0.6      ## неуязвимость после урона

@export_group("Adrenaline")
@export var adrenaline_max := 100.0
@export var adrenaline_per_attack := 12.0
@export var adrenaline_emergency_rate := 10.0  ## набор в секунду в экстренной ситуации
@export var adrenaline_decay_rate := 8.0       ## спад в секунду
@export var adrenaline_decay_delay := 2.0      ## сколько держится до начала спада
@export var bonus_per_adrenaline := 0.5        ## сколько временной стамины даёт 1 адреналина

@export_group("Adrenaline Rush")
## Бонусы при полном адреналине (при половине адреналина действуют вполовину).
@export var rush_speed_bonus := 0.3            ## +30% к скорости бега
@export var rush_accel_bonus := 0.6            ## +60% к разгону и торможению (резче)
@export var rush_dash_bonus := 0.3             ## быстрее дэш и короче перезарядка
@export var rush_attack_bonus := 0.35          ## быстрее атаки
@export var rush_blend_speed := 2.5            ## как быстро раж нарастает и спадает
@export var rush_tint := true                  ## лёгкий тёплый оттенок персонажа в раже

@export_group("Art")
@export_file("*.png") var sheet_path := "res://art/hero_sheet.png"
@export var sprite_scale := 2.0
@export var feet_y := 31.0                     ## на какой строке кадра (из 32) стоят ноги

const HERO_ANIMS := [
	{"name": "idle", "frames": 2, "fps": 3.0},
	{"name": "run", "frames": 4, "fps": 12.0},
	{"name": "jump", "frames": 1, "fps": 1.0, "loop": false},
	{"name": "fall", "frames": 1, "fps": 1.0, "loop": false},
	{"name": "dash_hover", "frames": 1, "fps": 1.0, "loop": false},
	{"name": "dash", "frames": 1, "fps": 1.0, "loop": false},
	{"name": "attack", "frames": 3, "fps": 18.0, "loop": false},
	{"name": "hurt", "frames": 1, "fps": 1.0, "loop": false},
]

@export_group("Camera")
@export var create_camera := true              ## создать Camera2D, если у игрока её нет
@export var camera_smoothing_calm := 3.0       ## при адреналине 0: плавная, камера отстаёт
@export var camera_smoothing_rush := 25.0      ## при полном адреналине: резкая, почти жёсткая

@export_group("Movement")
@export var run_speed := 260.0
@export var accel := 3600.0
@export var friction := 5000.0
@export var turn_accel_bonus := 1.6            ## множитель разгона при развороте
@export var air_control := 0.85
@export var gravity_multiplier := 1.3
@export var fall_gravity_scale := 1.6
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Jump")
@export var jump_speed := 400.0
@export var jump_cost := 6.0
@export var jump_hold_cost_per_sec := 30.0     ## доп. стамина за удержание
@export var jump_hold_gravity_scale := 0.4     ## пока держим, гравитация слабее
@export var jump_hold_max_time := 0.35
@export var jump_cut_factor := 0.55            ## отпустил кнопку на взлёте: скорость умножается на это

@export_group("Dash")
@export var dash_start_cost := 10.0
@export var dash_hover_cost_per_sec := 20.0    ## стамина в секунду, пока висишь
@export var dash_tap_threshold := 0.15         ## отпустил раньше: быстрый дэш, держишь дольше: зависание
@export var dash_tap_distance := 110.0         ## фиксированная дальность быстрого дэша
@export var dash_max_distance := 260.0         ## фиксированный потолок дальности при удержании
@export var dash_charge_time := 0.7            ## за сколько секунд зависания дальность растёт от tap до max
@export var dash_avg_speed := 800.0            ## средняя скорость рывка (старт быстрее, конец медленнее)
@export var dash_exit_factor := 0.2            ## доля скорости, которая остаётся после дэша
@export var dash_cooldown := 0.15
@export var dash_invulnerable := true          ## неуязвим, пока летишь рывком (не при зависании)

@export_group("Attack")
@export var attack_cost := 8.0
@export var attack_cooldown := 0.3
@export var attack_damage := 10.0
@export var attack_active_time := 0.12         ## сколько кадров хитбокс живёт
@export var attack_size := Vector2(52, 36)
@export var attack_offset := 36.0

@export var debug_draw := true

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var state: State = State.NORMAL
var facing := 1.0

# Стамина
var max_stamina := 0.0
var stamina := 0.0
var bonus_stamina := 0.0   # временный запас от адреналина, тратится первым
var adrenaline := 0.0

# Таймеры и флаги
var _regen_timer := 0.0
var _adrenaline_decay_timer := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _attack_timer := 0.0
var _dash_cooldown_timer := 0.0
var _invuln_timer := 0.0
var _stun_timer := 0.0

var _rush := 0.0               # 0..1, сглаженный адреналин, от него зависят все бонусы
var _camera: Camera2D
var _sprite: AnimatedSprite2D
var _attack_anim_left := 0.0

var _attack_area: Area2D
var _attack_active_left := 0.0
var _attack_hit_bodies: Array = []

var _jump_holding := false
var _jump_hold_time := 0.0

var _air_dash_ready := true
var _hover_time := 0.0
var _dash_pending := false       # кнопка нажата, ещё не ясно: тап или удержание
var _dash_press_time := 0.0
var _dash_elapsed := 0.0
var _dash_total_time := 0.0
var _dash_distance := 0.0
var _dash_start_pos := Vector2.ZERO
var dash_dir := Vector2.RIGHT


func _ready() -> void:
	add_to_group("player")
	# Слои: 1 = мир, 2 = враги, 3 = игрок. Игрок сталкивается только с миром.
	collision_layer = 1 << 2
	collision_mask = 1
	_ensure_input_actions()
	_setup_attack_area()
	_setup_camera()
	_setup_sprite()
	max_stamina = max_stamina_start
	stamina = max_stamina
	_emit_stamina()


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_rush(delta)

	match state:
		State.NORMAL:
			_state_normal(delta)
		State.DASH_HOVER:
			_state_hover(delta)
		State.DASH:
			_state_dash(delta)

	_update_regen(delta)
	_update_adrenaline(delta)
	_update_attack(delta)
	_update_animation()

	if debug_draw or state == State.DASH_HOVER or _attack_active_left > 0.0:
		queue_redraw()


# ---------------------------------------------------------------- состояния

func _state_normal(delta: float) -> void:
	var input_x := Input.get_axis("move_left", "move_right")
	if input_x != 0.0:
		facing = signf(input_x)

	# Гравитация
	var g := gravity * gravity_multiplier
	if _jump_holding:
		g *= jump_hold_gravity_scale
	elif velocity.y > 0.0:
		g *= fall_gravity_scale
	velocity.y += g * delta

	# Горизонталь
	var rate := (accel if input_x != 0.0 else friction) * (1.0 + rush_accel_bonus * _rush)
	if input_x != 0.0 and signf(velocity.x) == -signf(input_x):
		rate *= turn_accel_bonus
	if not is_on_floor():
		rate *= air_control
	if _stun_timer <= 0.0:
		velocity.x = move_toward(velocity.x, input_x * run_speed * (1.0 + rush_speed_bonus * _rush), rate * delta)

	# Прыжок: coyote time + буфер нажатия
	if is_on_floor():
		_coyote_timer = coyote_time
		_air_dash_ready = true
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		if try_spend(jump_cost):
			_start_jump()

	# Удержание прыжка: выше, но дороже
	if _jump_holding:
		_jump_hold_time += delta
		var released := not Input.is_action_pressed("jump")
		var still_holding := not released \
				and _jump_hold_time < jump_hold_max_time \
				and velocity.y < 0.0
		if still_holding:
			still_holding = _drain(jump_hold_cost_per_sec * delta)
		if not still_holding:
			_jump_holding = false
			if released and velocity.y < 0.0:
				velocity.y *= jump_cut_factor

	# Атака
	if Input.is_action_just_pressed("attack") and _attack_timer <= 0.0:
		if try_spend(attack_cost):
			_attack_timer = attack_cooldown / (1.0 + rush_attack_bonus * _rush)
			_do_attack()

	# Дэш: короткое нажатие даёт быстрый рывок, удержание переводит в зависание.
	# Пока решается, тап это или удержание, персонаж двигается как обычно.
	if Input.is_action_just_pressed("dash") \
			and _dash_cooldown_timer <= 0.0 \
			and (is_on_floor() or _air_dash_ready):
		if try_spend(dash_start_cost):
			_dash_pending = true
			_dash_press_time = 0.0
	if _dash_pending:
		_dash_press_time += delta
		if not Input.is_action_pressed("dash"):
			_dash_pending = false
			_start_dash(dash_tap_distance)
			return
		elif _dash_press_time >= dash_tap_threshold:
			_dash_pending = false
			_enter_hover()
			return

	move_and_slide()


func _state_hover(delta: float) -> void:
	_hover_time += delta
	velocity = Vector2.ZERO
	_update_dash_aim()

	# Висим, пока держим кнопку и есть стамина
	var has_stamina := _drain(dash_hover_cost_per_sec * delta)
	if not Input.is_action_pressed("dash") or not has_stamina:
		_release_dash()


func _state_dash(delta: float) -> void:
	_dash_elapsed += delta
	var u := clampf(_dash_elapsed / _dash_total_time, 0.0, 1.0)
	# Ease-out: максимальная скорость в начале, торможение к концу
	var progress := 1.0 - (1.0 - u) * (1.0 - u)
	var target := _dash_start_pos + dash_dir * _dash_distance * progress
	velocity = (target - global_position) / delta
	move_and_slide()
	if u >= 1.0:
		velocity = dash_dir * _dash_speed_now() * dash_exit_factor
		_dash_cooldown_timer = dash_cooldown / (1.0 + rush_dash_bonus * _rush)
		state = State.NORMAL


# --------------------------------------------------------------------- прыжок

func _start_jump() -> void:
	velocity.y = -jump_speed
	_jump_holding = true
	_jump_hold_time = 0.0
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0


# ----------------------------------------------------------------------- дэш

func _enter_hover() -> void:
	state = State.DASH_HOVER
	_hover_time = 0.0
	_jump_holding = false
	velocity = Vector2.ZERO
	if not is_on_floor():
		_air_dash_ready = false
	_update_dash_aim()


func _release_dash() -> void:
	_start_dash(_current_dash_distance())


func _start_dash(distance: float) -> void:
	_update_dash_aim()
	var reach := _clear_distance(distance)
	if reach < 1.0:
		_dash_cooldown_timer = dash_cooldown
		state = State.NORMAL
		return
	if not is_on_floor():
		_air_dash_ready = false
	_jump_holding = false
	_dash_distance = reach
	_dash_total_time = maxf(reach / _dash_speed_now(), 0.05)
	_dash_elapsed = 0.0
	_dash_start_pos = global_position
	state = State.DASH


func _update_dash_aim() -> void:
	var aim := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if aim.x != 0.0:
		facing = signf(aim.x)
	if aim == Vector2.ZERO:
		aim = Vector2(facing, 0.0)
	dash_dir = aim.normalized()


## Дальность растёт с зажатием до фиксированного максимума.
func _current_dash_distance() -> float:
	var t := clampf(_hover_time / dash_charge_time, 0.0, 1.0)
	return lerpf(dash_tap_distance, dash_max_distance, t)


## Сколько из distance реально свободно до стены (с учётом формы коллайдера).
func _clear_distance(distance: float) -> float:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = collision_shape.shape
	q.transform = collision_shape.global_transform
	q.motion = dash_dir * distance
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.cast_motion(q)
	if result.is_empty():
		return distance
	return distance * result[0]


# -------------------------------------------------------------------- атака

func _do_attack() -> void:
	# Адреналин теперь даётся только за попадание (см. _update_attack)
	_attack_area.position = Vector2(facing * attack_offset, 0.0)
	_attack_hit_bodies.clear()
	_attack_anim_left = 0.2
	_attack_active_left = attack_active_time
	_attack_area.monitoring = true


## Зона удара создаётся кодом: слой 0, видит слой 2 (враги).
func _setup_attack_area() -> void:
	_attack_area = Area2D.new()
	_attack_area.name = "AttackArea"
	_attack_area.collision_layer = 0
	_attack_area.collision_mask = 2
	_attack_area.monitoring = false
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = attack_size
	shape.shape = box
	_attack_area.add_child(shape)
	add_child(_attack_area)


func _update_attack(delta: float) -> void:
	if _attack_active_left <= 0.0:
		return
	_attack_active_left -= delta
	for body in _attack_area.get_overlapping_bodies():
		if body in _attack_hit_bodies or not body.has_method("take_hit"):
			continue
		_attack_hit_bodies.append(body)
		body.take_hit(attack_damage, global_position)
		on_attack_hit()
	if _attack_active_left <= 0.0:
		_attack_area.monitoring = false


func on_attack_hit() -> void:
	add_adrenaline(adrenaline_per_attack)


# ------------------------------------------------------------------ стамина

func available_stamina() -> float:
	return stamina + bonus_stamina


func try_spend(cost: float) -> bool:
	if available_stamina() < cost:
		return false
	_spend(cost)
	return true


## Непрерывная трата. Возвращает false, когда запас закончился.
func _drain(cost: float) -> bool:
	_spend(minf(cost, available_stamina()))
	return available_stamina() > 0.0


func _spend(cost: float) -> void:
	var from_bonus := minf(bonus_stamina, cost)
	bonus_stamina -= from_bonus
	stamina = maxf(stamina - (cost - from_bonus), 0.0)
	_regen_timer = regen_delay
	_emit_stamina()


func _update_regen(delta: float) -> void:
	if state == State.DASH_HOVER:
		return
	_regen_timer -= delta
	if _regen_timer <= 0.0 and stamina < max_stamina:
		stamina = minf(stamina + regen_rate * delta, max_stamina)
		_emit_stamina()


## Урон снижает максимум стамины.
func take_damage(amount: float, source_pos := Vector2.INF) -> void:
	if amount <= 0.0 or _invuln_timer > 0.0:
		return
	if dash_invulnerable and state == State.DASH:
		return
	_invuln_timer = invulnerable_time
	_dash_pending = false

	# Отдача от источника урона
	if source_pos != Vector2.INF:
		var dir := signf(global_position.x - source_pos.x)
		if dir == 0.0:
			dir = -facing
		velocity = Vector2(dir * hurt_knockback.x, hurt_knockback.y)
		_stun_timer = hurt_stun_time
		_jump_holding = false
	max_stamina = maxf(max_stamina - amount, 0.0)
	stamina = minf(stamina, max_stamina)
	_emit_stamina()

	# Решение по дизайну: урон обрывает зависание
	if state == State.DASH_HOVER:
		_dash_cooldown_timer = dash_cooldown
		state = State.NORMAL

	if max_stamina <= 0.0:
		died.emit()
		set_physics_process(false)


## Лечение: возвращает потерянный максимум (но не выше стартового).
func restore_max_stamina(amount: float) -> void:
	max_stamina = minf(max_stamina + amount, max_stamina_start)
	_emit_stamina()


# ----------------------------------------------------------------- адреналин

func add_adrenaline(amount: float) -> void:
	var gained := minf(amount, adrenaline_max - adrenaline)
	if gained <= 0.0:
		return
	adrenaline += gained
	bonus_stamina += gained * bonus_per_adrenaline
	_adrenaline_decay_timer = adrenaline_decay_delay
	adrenaline_changed.emit(adrenaline)
	_emit_stamina()


## Здесь можно добавить другие условия: много врагов рядом, босс, недавний урон.
func _in_emergency() -> bool:
	return max_stamina > 0.0 and stamina / max_stamina < emergency_threshold


func _update_adrenaline(delta: float) -> void:
	if _in_emergency():
		add_adrenaline(adrenaline_emergency_rate * delta)
	elif adrenaline > 0.0:
		_adrenaline_decay_timer -= delta
		if _adrenaline_decay_timer <= 0.0:
			adrenaline = maxf(adrenaline - adrenaline_decay_rate * delta, 0.0)
			adrenaline_changed.emit(adrenaline)

	# Временный запас не может превышать то, что даёт текущий адреналин
	var cap := adrenaline * bonus_per_adrenaline
	if bonus_stamina > cap:
		bonus_stamina = cap
		_emit_stamina()


# -------------------------------------------------------------------- прочее

func _tick_timers(delta: float) -> void:
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)
	_stun_timer = maxf(_stun_timer - delta, 0.0)
	_attack_anim_left = maxf(_attack_anim_left - delta, 0.0)


## Раж плавно следует за адреналином, чтобы бонусы и камера не дёргались.
func _update_rush(delta: float) -> void:
	var target := adrenaline / adrenaline_max if adrenaline_max > 0.0 else 0.0
	_rush = move_toward(_rush, target, rush_blend_speed * delta)

	# Камера: адреналин 0 = плавная и отстающая, адреналин max = резкая
	if _camera:
		_camera.position_smoothing_speed = lerpf(camera_smoothing_calm, camera_smoothing_rush, _rush)

	if rush_tint:
		modulate = Color.WHITE.lerp(Color(1.0, 0.8, 0.65), _rush * 0.7)


func _setup_camera() -> void:
	for child in get_children():
		if child is Camera2D:
			_camera = child
			break
	if _camera == null and create_camera:
		_camera = Camera2D.new()
		_camera.name = "Camera2D"
		add_child(_camera)
	if _camera:
		_camera.position_smoothing_enabled = true
		_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		_camera.make_current()


func _setup_sprite() -> void:
	if not ResourceLoader.exists(sheet_path):
		return
	var tex := load(sheet_path) as Texture2D
	if tex == null:
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Visual"
	_sprite.sprite_frames = SpriteSheet.build(tex, Vector2i(32, 32), HERO_ANIMS)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * sprite_scale
	# Центр кадра = 16, ноги на feet_y: ставим их на нижний край коллайдера
	_sprite.position = Vector2(
			collision_shape.position.x,
			_collision_bottom() - (feet_y - 16.0) * sprite_scale)
	add_child(_sprite)
	_sprite.play("idle")


func _collision_bottom() -> float:
	var half := 16.0
	var rect := collision_shape.shape as RectangleShape2D
	var capsule := collision_shape.shape as CapsuleShape2D
	if rect:
		half = rect.size.y / 2.0
	elif capsule:
		half = capsule.height / 2.0
	return collision_shape.position.y + half


func _update_animation() -> void:
	if _sprite == null:
		return
	var anim := "idle"
	if _stun_timer > 0.0:
		anim = "hurt"
	elif state == State.DASH_HOVER:
		anim = "dash_hover"
	elif state == State.DASH:
		anim = "dash"
	elif _attack_anim_left > 0.0:
		anim = "attack"
	elif not is_on_floor():
		anim = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 20.0:
		anim = "run"

	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.flip_h = facing < 0.0
	# В раже бег быстрее
	_sprite.speed_scale = 1.0 + rush_speed_bonus * _rush
	# Мигание во время неуязвимости после урона
	var blink := _invuln_timer > 0.0 and int(_invuln_timer * 24.0) % 2 == 0
	_sprite.modulate.a = 0.55 if blink else 1.0


func _dash_speed_now() -> float:
	return dash_avg_speed * (1.0 + rush_dash_bonus * _rush)


func _emit_stamina() -> void:
	stamina_changed.emit(stamina, max_stamina, bonus_stamina)


func _draw() -> void:
	if state == State.DASH_HOVER:
		var max_reach := _clear_distance(dash_max_distance)
		var cur_reach := _clear_distance(_current_dash_distance())
		var full := _hover_time >= dash_charge_time
		var col := Color.ORANGE if full else Color.WHITE

		# Потолок дальности (бледная линия + кольцо) и текущая дальность
		draw_line(Vector2.ZERO, dash_dir * max_reach, Color(1, 1, 1, 0.25), 2.0)
		draw_arc(dash_dir * max_reach, 7.0, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 2.0)
		draw_line(Vector2.ZERO, dash_dir * cur_reach, col, 3.0)
		draw_circle(dash_dir * cur_reach, 5.0, col)

	if _attack_active_left > 0.0:
		var area := Rect2(Vector2(facing * attack_offset, 0.0) - attack_size / 2.0, attack_size)
		draw_rect(area, Color(1.0, 1.0, 1.0, 0.35))

	if debug_draw:
		var txt := "%.0f/%.0f  +%.0f  A:%.0f" % [stamina, max_stamina, bonus_stamina, adrenaline]
		draw_string(ThemeDB.fallback_font, Vector2(-40, -30), txt)


## Чтобы скрипт заработал сразу, без ручной настройки Input Map.
## Если действия уже есть в проекте, они не перезаписываются.
func _ensure_input_actions() -> void:
	var defaults: Dictionary = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE],
		"dash": [KEY_SHIFT],
		"attack": [KEY_J],
	}
	for action: String in defaults:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in defaults[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
