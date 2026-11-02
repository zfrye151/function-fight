extends Control

# ─────────────────────────────────────────────
#  State
# ─────────────────────────────────────────────
enum BattleState { START, PLAYER_TURN, EVALUATING, ENEMY_TURN, WIN, LOSE }
var current_state: BattleState = BattleState.START

var enemy_health:  float = 100.0
var player_health: float = 100.0

const PLAYER_DAMAGE:  float = 25.0
const ENEMY_DAMAGE:   float = 15.0
const WRONG_PENALTY:  float = 10.0

var _pending_operation: String = ""
var _btn_callables: Dictionary = {}   # { button_name: Callable }

# Typewriter state
var _typewriter_full_text:  String = ""   # final BBCode string (shown when done)
var _typewriter_plain_text: String = ""   # stripped plain text for character counting
var _typewriter_index:      int    = 0
var _typewriter_timer:      float  = 0.0
const TYPEWRITER_SPEED:     float  = 0.03  # seconds per character
const DIALOG_FONT_SIZE:     int    = 48

# Shake state
var _shake_timer:    float  = 0.0
var _shake_origin:   Vector2 = Vector2.ZERO
const SHAKE_DURATION: float  = 0.4
const SHAKE_STRENGTH: float  = 8.0

# ─────────────────────────────────────────────
#  Node refs
# ─────────────────────────────────────────────
@onready var dialog_text     : RichTextLabel = $MainLayout/ControlPanel/UIContainer/PanelLayout/DialogText
@onready var enemy_math_label: RichTextLabel = $MainLayout/ArenaPanel/Arena/EnemyContainer/EnemyMathLabel
@onready var enemy_hp_bar    : ProgressBar   = $MainLayout/ArenaPanel/Arena/EnemyContainer/EnemyHealth
@onready var player_hp_bar   : ProgressBar   = $MainLayout/ArenaPanel/Arena/PlayerContainer/PlayerHealth

@onready var action_grid = $MainLayout/ControlPanel/UIContainer/PanelLayout/ActionGrid
@onready var diff_button : Button = $MainLayout/ControlPanel/UIContainer/PanelLayout/ActionGrid/DiffButton
@onready var int_button  : Button = $MainLayout/ControlPanel/UIContainer/PanelLayout/ActionGrid/IntButton
@onready var log_button  : Button = $MainLayout/ControlPanel/UIContainer/PanelLayout/ActionGrid/LogButton
@onready var eval_button : Button = $MainLayout/ControlPanel/UIContainer/PanelLayout/ActionGrid/EvalButton

@onready var battle_manager = $BattleManager

# Audio — add these three AudioStreamPlayer nodes as children of BattleScene
# and assign .wav/.ogg files in the Inspector
@onready var hit_sound  : AudioStreamPlayer = $HitSound
@onready var hurt_sound : AudioStreamPlayer = $HurtSound
@onready var win_sound  : AudioStreamPlayer = $WinSound

# ─────────────────────────────────────────────
#  Boot
# ─────────────────────────────────────────────
func _ready() -> void:
	enemy_hp_bar.max_value  = 100
	player_hp_bar.max_value = 100
	_shake_origin = enemy_math_label.position
	_set_mode_operations()
	_start_new_round()

# ─────────────────────────────────────────────
#  Process — drives typewriter + shake
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	_process_typewriter(delta)
	_process_shake(delta)

func _process_typewriter(delta: float) -> void:
	if _typewriter_index >= _typewriter_plain_text.length():
		return
	_typewriter_timer -= delta
	if _typewriter_timer <= 0.0:
		_typewriter_timer = TYPEWRITER_SPEED
		_typewriter_index += 1
		if _typewriter_index >= _typewriter_plain_text.length():
			# Reveal the full styled BBCode now that we've "typed" every character
			dialog_text.text = _typewriter_full_text
		else:
			# Show only plain text while still typing — no BBCode leaking through
			dialog_text.text = "[font_size=%d]" % DIALOG_FONT_SIZE + \
				_typewriter_plain_text.left(_typewriter_index) + "[/font_size]"

func _process_shake(delta: float) -> void:
	if _shake_timer <= 0.0:
		return
	_shake_timer -= delta
	if _shake_timer <= 0.0:
		enemy_math_label.position = _shake_origin
	else:
		var offset := Vector2(
			randf_range(-SHAKE_STRENGTH, SHAKE_STRENGTH),
			randf_range(-SHAKE_STRENGTH, SHAKE_STRENGTH)
		)
		enemy_math_label.position = _shake_origin + offset

# ─────────────────────────────────────────────
#  Round management
# ─────────────────────────────────────────────
func _start_new_round() -> void:
	battle_manager.generate_new_problem()
	var p: Dictionary = battle_manager.get_problem()

	_set_math_label(enemy_math_label, "f(x) = " + p["expression"])
	_type_dialog("A wild function appears!\n[b]f(x) = %s[/b]\n\nChoose your operation!" % p["expression"])
	_refresh_hp_bars()
	_set_mode_operations()
	current_state = BattleState.PLAYER_TURN

# ─────────────────────────────────────────────
#  Button modes
# ─────────────────────────────────────────────
func _disconnect_btn(btn: Button, key: String) -> void:
	if _btn_callables.has(key):
		var c: Callable = _btn_callables[key]
		if btn.pressed.is_connected(c):
			btn.pressed.disconnect(c)
		_btn_callables.erase(key)

func _connect_btn(btn: Button, key: String, c: Callable) -> void:
	_disconnect_btn(btn, key)
	_btn_callables[key] = c
	btn.pressed.connect(c)

func _set_mode_operations() -> void:
	diff_button.text  = "Differentiate"
	int_button.text   = "Integrate"
	log_button.text   = "Natural Log"
	eval_button.text  = "Evaluate x=0"

	_connect_btn(diff_button, "diff", func(): on_operation_selected("DERIVATIVE"))
	_connect_btn(int_button,  "int",  func(): on_operation_selected("ANTIDERIVATIVE"))
	_connect_btn(log_button,  "log",  func(): on_operation_selected("NATURAL_LOG"))
	_connect_btn(eval_button, "eval", func(): on_operation_selected("EVALUATE"))

	_toggle_all_buttons(true)

func _set_mode_confirm() -> void:
	diff_button.text  = ""
	int_button.text   = ""
	log_button.text   = "✓  Got it!"
	eval_button.text  = "✗  Missed it"

	_disconnect_btn(diff_button, "diff")
	_disconnect_btn(int_button,  "int")
	_connect_btn(log_button,  "log",  func(): _on_self_grade(true))
	_connect_btn(eval_button, "eval", func(): _on_self_grade(false))

	diff_button.disabled = true
	int_button.disabled  = true
	log_button.disabled  = false
	eval_button.disabled = false

# ─────────────────────────────────────────────
#  Operation selected
# ─────────────────────────────────────────────
func on_operation_selected(operation: String) -> void:
	if current_state != BattleState.PLAYER_TURN:
		return

	_toggle_all_buttons(false)
	current_state = BattleState.EVALUATING
	_pending_operation = operation

	var p: Dictionary = battle_manager.get_problem()
	var answer: String = ""
	var op_label: String = ""

	match operation:
		"DERIVATIVE":
			answer   = p["derivative"]
			op_label = "Derivative"
		"ANTIDERIVATIVE":
			answer   = p["antiderivative"]
			op_label = "Antiderivative"
		"NATURAL_LOG":
			answer   = p["derivative"]
			op_label = "d/dx (via ln rule)"
		"EVALUATE":
			answer   = _evaluate_at_zero(p)
			op_label = "f(0)"

	_type_dialog(
		"[b]%s[/b] of f(x) = %s\n\n[color=#88ffcc]Answer: %s[/color]\n\nDid you get it right?" \
		% [op_label, p["expression"], answer]
	)
	_set_mode_confirm()

# ─────────────────────────────────────────────
#  Self-grading
# ─────────────────────────────────────────────
func _on_self_grade(correct: bool) -> void:
	_toggle_all_buttons(false)
	_resolve_player_action(correct)

# ─────────────────────────────────────────────
#  Combat resolution
# ─────────────────────────────────────────────
func _resolve_player_action(correct: bool) -> void:
	if correct:
		enemy_health -= PLAYER_DAMAGE
		enemy_health  = maxf(enemy_health, 0.0)
		hit_sound.play()
		_shake_label()
		_type_dialog("[color=#88ffcc]✓ Correct! You dealt [b]%.0f[/b] damage![/color]" % PLAYER_DAMAGE)
	else:
		player_health -= WRONG_PENALTY
		player_health  = maxf(player_health, 0.0)
		hurt_sound.play()
		_type_dialog("[color=#ff8888]✗ Wrong answer! Recoil dealt [b]%.0f[/b] damage to you![/color]" % WRONG_PENALTY)

	_refresh_hp_bars()
	await get_tree().create_timer(1.6).timeout
	await _enemy_turn()

func _enemy_turn() -> void:
	if await _check_battle_over():
		return

	current_state = BattleState.ENEMY_TURN
	player_health -= ENEMY_DAMAGE
	player_health  = maxf(player_health, 0.0)

	hurt_sound.play()
	_type_dialog("[color=#ff8888]The enemy function retaliates for [b]%.0f[/b] damage![/color]" % ENEMY_DAMAGE)
	_refresh_hp_bars()

	await get_tree().create_timer(1.6).timeout

	if await _check_battle_over():
		return

	_start_new_round()

# ─────────────────────────────────────────────
#  Win / lose
# ─────────────────────────────────────────────
func _check_battle_over() -> bool:
	if enemy_health <= 0:
		current_state = BattleState.WIN
		win_sound.play()
		_type_dialog("[b][color=#ffdd55]Enemy function defeated!\n+50 Math XP! ✨[/color][/b]")
		_toggle_all_buttons(false)
		await get_tree().create_timer(2.2).timeout
		enemy_health = 100.0
		_start_new_round()
		return true

	if player_health <= 0:
		current_state = BattleState.LOSE
		hurt_sound.play()
		_type_dialog("[color=#ff4444][b]Your HP hit 0. Game over![/b]\n\nPress Differentiate to retry.[/color]")
		diff_button.text = "Try Again"
		diff_button.disabled = false
		diff_button.pressed.connect(func(): _retry(), CONNECT_ONE_SHOT)
		return true

	return false

func _retry() -> void:
	player_health = 100.0
	enemy_health  = 100.0
	_refresh_hp_bars()
	_start_new_round()

# ─────────────────────────────────────────────
#  Evaluate at x = 0
# ─────────────────────────────────────────────
func _evaluate_at_zero(p: Dictionary) -> String:
	match p["type"]:
		"CONSTANT":    return p["expression"]
		"POLYNOMIAL":  return "0"
		"RATIONAL":    return "undefined (division by zero)"
		"EXPONENTIAL": return p["expression"].replace("e^x", "e^0 = 1")
		"LOGARITHMIC": return "undefined (ln(0))"
		"TRIG":        return _trig_at_zero(p["expression"])
		"INVTRIG":     return _invtrig_at_zero(p["expression"])
	return "?"

func _trig_at_zero(expr: String) -> String:
	if "sin" in expr:   return "0"
	if "cos" in expr:   return expr.left(expr.find("·")) + "·1 = " + expr.left(expr.find("·"))
	if "tan" in expr:   return "0"
	if "sec" in expr:   return expr.left(expr.find("·")) + "·1 = " + expr.left(expr.find("·"))
	if "csc" in expr:   return "undefined"
	if "cot" in expr:   return "undefined"
	return "?"

func _invtrig_at_zero(expr: String) -> String:
	if "arcsin" in expr: return "0"
	if "arctan" in expr: return "0"
	return "?"

# ─────────────────────────────────────────────
#  UI helpers
# ─────────────────────────────────────────────

# Strips BBCode tags to get plain text for character-by-character reveal
func _strip_bbcode(s: String) -> String:
	var result := ""
	var in_tag := false
	for ch in s:
		if ch == "[":
			in_tag = true
		elif ch == "]":
			in_tag = false
		elif not in_tag:
			result += ch
	return result

# Typewriter: type plain text, snap to full styled BBCode at the end
func _type_dialog(bbcode: String) -> void:
	dialog_text.bbcode_enabled = true
	_typewriter_full_text  = "[font_size=%d]" % DIALOG_FONT_SIZE + bbcode + "[/font_size]"
	_typewriter_plain_text = _strip_bbcode(bbcode)
	_typewriter_index      = 0
	_typewriter_timer      = 0.0
	dialog_text.text       = ""

func _set_dialog(bbcode: String) -> void:
	# Instant reveal — no typewriter
	var full := "[font_size=%d]" % DIALOG_FONT_SIZE + bbcode + "[/font_size]"
	dialog_text.bbcode_enabled = true
	_typewriter_full_text  = full
	_typewriter_plain_text = _strip_bbcode(bbcode)
	_typewriter_index      = _typewriter_plain_text.length()
	dialog_text.text       = full

func _set_math_label(label: RichTextLabel, text: String) -> void:
	label.bbcode_enabled = true
	label.text = "[center][b][font_size=48]" + text + "[/font_size][/b][/center]"

func _shake_label() -> void:
	_shake_origin = enemy_math_label.position
	_shake_timer  = SHAKE_DURATION

func _refresh_hp_bars() -> void:
	enemy_hp_bar.value  = enemy_health
	player_hp_bar.value = player_health

func _toggle_all_buttons(enabled: bool) -> void:
	for btn in [diff_button, int_button, log_button, eval_button]:
		btn.disabled = !enabled
