extends Node

enum FunctionType { POLYNOMIAL, RATIONAL, EXPONENTIAL, LOGARITHMIC, CONSTANT, TRIG, INVTRIG }

var current_problem: Dictionary = {}

func _ready() -> void:
	generate_new_problem()

# ─────────────────────────────────────────────
#  Main entry point
# ─────────────────────────────────────────────
func generate_new_problem() -> void:
	var type_pool: Array[FunctionType] = [
		FunctionType.POLYNOMIAL,
		FunctionType.RATIONAL,
		FunctionType.EXPONENTIAL,
		FunctionType.LOGARITHMIC,
		FunctionType.CONSTANT,
		FunctionType.TRIG,
		FunctionType.INVTRIG,
	]
	var chosen: FunctionType = type_pool.pick_random()
	current_problem = _build_problem(chosen)

func get_problem() -> Dictionary:
	return current_problem

# ─────────────────────────────────────────────
#  Builder — returns { expression, derivative, antiderivative, type }
#  All answers are LaTeX-style strings for display.
# ─────────────────────────────────────────────
func _build_problem(type: FunctionType) -> Dictionary:
	var c: int = randi_range(2, 9)   # coefficient
	var n: int = randi_range(2, 7)   # exponent  (never 0 or 1 so answers stay interesting)

	match type:

		FunctionType.CONSTANT:
			# f(x) = c
			return {
				"type":          "CONSTANT",
				"expression":    "%d" % c,
				"derivative":    "0",
				"antiderivative": "%dx + C" % c,
			}

		FunctionType.POLYNOMIAL:
			# f(x) = c·xⁿ
			var d_coeff: int = c * n              # derivative coefficient
			var a_coeff_num: int = c              # antiderivative  c/(n+1)·x^(n+1)
			var a_coeff_den: int = n + 1
			var a_exp: int    = n + 1
			return {
				"type":          "POLYNOMIAL",
				"expression":    "%dx^%d" % [c, n],
				"derivative":    _poly_term(d_coeff, n - 1),
				"antiderivative": _frac_term(a_coeff_num, a_coeff_den, a_exp) + " + C",
			}

		FunctionType.RATIONAL:
			# f(x) = c / x  (i.e. c·x^-1)
			return {
				"type":          "RATIONAL",
				"expression":    "%d/x" % c,
				"derivative":    "-%d/x^2" % c,
				"antiderivative": "%dln|x| + C" % c,
			}

		FunctionType.EXPONENTIAL:
			# f(x) = c·e^x  (keeps answers clean)
			return {
				"type":          "EXPONENTIAL",
				"expression":    "%de^x" % c,
				"derivative":    "%de^x" % c,
				"antiderivative": "%de^x + C" % c,
			}

		FunctionType.LOGARITHMIC:
			# f(x) = c*ln(x)
			return {
				"type":          "LOGARITHMIC",
				"expression":    "%dln(x)" % c,
				"derivative":    "%d/x" % c,
				"antiderivative": "%d(xln(x) - x) + C" % c,
			}

		FunctionType.TRIG:
			# Pick from the six basic trig rules
			var trig_cases: Array = [
				{ "expr": "%dsin(x)" % c, "deriv": "%dcos(x)" % c,       "anti": "-%dcos(x) + C" % c },
				{ "expr": "%dcos(x)" % c, "deriv": "-%dsin(x)" % c,      "anti": "%dsin(x) + C" % c },
				{ "expr": "%dtan(x)" % c, "deriv": "%dsec^2(x)" % c,     "anti": "%dln|sec(x)| + C" % c },
				{ "expr": "%dsec(x)" % c, "deriv": "%dsec(x)tan(x)" % c, "anti": "%dln|sec(x)+tan(x)| + C" % c },
				{ "expr": "%dcsc(x)" % c, "deriv": "-%dcsc(x)cot(x)" % c,"anti": "-%dln|csc(x)+cot(x)| + C" % c },
				{ "expr": "%dcot(x)" % c, "deriv": "-%dcsc^2(x)" % c,    "anti": "%dln|sin(x)| + C" % c },
			]
			var pick: Dictionary = trig_cases.pick_random()
			return {
				"type":          "TRIG",
				"expression":    pick["expr"],
				"derivative":    pick["deriv"],
				"antiderivative": pick["anti"],
			}

		FunctionType.INVTRIG:
			# Pick from three clean inverse-trig derivative rules
			var inv_cases: Array = [
				{ "expr": "%darcsin(x)" % c, "deriv": "%d/sqrt(1-x^2)" % c,      "anti": "%d(xarcsin(x)+sqrt(1-x^2)) + C" % c },
				{ "expr": "%darctan(x)" % c, "deriv": "%d/(1+x^2)" % c,           "anti": "%d(xarctan(x)-(1/2)ln(1+x^2)) + C" % c },
				{ "expr": "%darcsec(x)" % c, "deriv": "%d/(|x|sqrt(x^2-1))" % c, "anti": "complex form" },
			]
			var pick: Dictionary = inv_cases.pick_random()
			return {
				"type":          "INVTRIG",
				"expression":    pick["expr"],
				"derivative":    pick["deriv"],
				"antiderivative": pick["anti"],
			}

	# Fallback (should never hit)
	return { "type": "CONSTANT", "expression": "1", "derivative": "0", "antiderivative": "x + C" }

# ─────────────────────────────────────────────
#  Formatting helpers
# ─────────────────────────────────────────────

# Returns "cxⁿ" handling special exponent cases
func _poly_term(coeff: int, exp: int) -> String:
	if exp == 0:
		return "%d" % coeff
	if exp == 1:
		return "%dx" % coeff
	return "%dx^%d" % [coeff, exp]

# Returns "(c/d)xⁿ", simplifying when possible
func _frac_term(num: int, den: int, exp: int) -> String:
	var g: int = _gcd(absi(num), absi(den))
	var sn: int = num / g
	var sd: int = den / g
	var coeff_str: String = "%d/%d" % [sn, sd] if sd != 1 else "%d" % sn
	if exp == 1:
		return "%sx" % coeff_str
	return "%sx^%d" % [coeff_str, exp]

func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t: int = b
		b = a % b
		a = t
	return a
