class_name Vessel
extends RefCounted
## The ball is the meter: the souls it has taken this match.
## Challenge → Take → Borrow → Risk → Cash Out.
##   Beating an opponent (nutmeg, tackle, interception, dribble past…) feeds the ball and stores
##   that opponent's Soul Signature. The team the ball is bonded to borrows power by stage.
##   Unfed, it gets hungry and drains — faster the fuller it is. Passing steadies it.
##   Losing it is exposure: mid charge scatters, overload backlashes into the taker's hands.
##   A goal cashes it out (resets); an overloaded goal is worth two bricks.

enum Kind { SPEED, POWER, TRICK, VISION, GUARD }
enum Stage { DORMANT, STIRRING, POSSESSED, HUNGRY, OVERLOADED }
enum Lost { NONE, SCATTER, BACKLASH }

const KINDS := [
	{"name": "SPEED", "color": Color("39ff14")},
	{"name": "POWER", "color": Color("ff2a2a")},
	{"name": "TRICK", "color": Color("b04dff")},
	{"name": "VISION", "color": Color("2d8cff")},
	{"name": "GUARD", "color": Color("ffc300")},
]
## Borrowed body of the bonded team. Everyone else plays at DORMANT: the injured baseline.
const STAGES := [
	{"name": "DORMANT", "at": 0.0, "speed": 0.9, "accel": 0.7, "turn": 0.6, "shot": 0.92, "decay": 0.0},
	{"name": "STIRRING", "at": 20.0, "speed": 1.0, "accel": 0.9, "turn": 0.85, "shot": 1.0, "decay": 1.5},
	{"name": "POSSESSED", "at": 45.0, "speed": 1.06, "accel": 1.1, "turn": 1.0, "shot": 1.08, "decay": 3.0},
	{"name": "HUNGRY", "at": 70.0, "speed": 1.12, "accel": 1.25, "turn": 1.15, "shot": 1.15, "decay": 5.0},
	{"name": "OVERLOADED", "at": 90.0, "speed": 1.18, "accel": 1.4, "turn": 1.3, "shot": 1.25, "decay": 8.0},
]
const HUNGER_DELAY := 3.0     # seconds unfed before it starts eating itself
const STEADY_DECAY := 0.35    # decay multiplier while passes keep it steady
const SCATTER_KEEP := 0.25    # POSSESSED/HUNGRY lost: most souls scatter
const BACKLASH_KEEP := 0.8    # OVERLOADED lost: the taker inherits most of it

var charge := 0.0
var bond := 0                 # team the souls currently serve
var souls := [0.0, 0.0, 0.0, 0.0, 0.0]
var last_feed := 0.0
var steady_until := -10.0
## Charge a team banked by scoring: the goal cashes the ball out, but half of what the scorer had is
## waiting for them the next time they take the ball (so scoring snowballs).
var bank_charge := [0.0, 0.0]
var bank_souls := [[0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0]]


func reset(team: int, now: float) -> void:
	charge = 0.0
	bond = team
	souls = [0.0, 0.0, 0.0, 0.0, 0.0]
	last_feed = now
	steady_until = -10.0


## Put `keep` of the current charge and souls aside for `team`, to be claimed on their next possession.
func bank(team: int, keep: float) -> void:
	bank_charge[team] = charge * keep
	bank_souls[team] = souls.map(func(s: float) -> float: return s * keep)


## `team` has the ball: pour their banked charge in. Returns how much came in.
func claim_bank(team: int, now: float) -> float:
	var amount: float = bank_charge[team]
	if amount <= 0.0 or team != bond:
		return 0.0
	charge = minf(100.0, charge + amount)
	for k in souls.size():
		souls[k] += bank_souls[team][k]
	bank_charge[team] = 0.0
	bank_souls[team] = [0.0, 0.0, 0.0, 0.0, 0.0]
	last_feed = now
	return amount


func clear_bank() -> void:
	bank_charge = [0.0, 0.0]
	bank_souls = [[0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0]]


func stage() -> int:
	for s in range(STAGES.size() - 1, -1, -1):
		if charge >= STAGES[s].at:
			return s
	return Stage.DORMANT


## Which stolen identity dominates the ball, or -1 while it sleeps.
func dominant() -> int:
	if stage() == Stage.DORMANT:
		return -1
	var best := -1
	for k in souls.size():
		if souls[k] > 0.0 and (best < 0 or souls[k] > souls[best]):
			best = k
	return best


func color() -> Color:
	var d := dominant()
	return Color.WHITE if d < 0 else KINDS[d].color


## 0..1: how loaded the ball is.
func momentum() -> float:
	return charge / 100.0


## The colour of the ball right now, for the ball and every effect around it: white while it sleeps, then
## the dominant soul washed out at low charge and fully saturated as the momentum builds.
func glow() -> Color:
	return Color.WHITE.lerp(color(), lerpf(0.6, 1.0, momentum()))


## Returns the stage before feeding, so callers can announce a stage-up.
func feed(amount: float, kind: int, now: float) -> int:
	var before := stage()
	charge = minf(100.0, charge + amount)
	if kind >= 0:
		souls[kind] += amount
	last_feed = now
	return before


func steady(now: float, secs: float) -> void:
	steady_until = maxf(steady_until, now + secs)


func is_hungry(now: float) -> bool:
	return stage() > Stage.DORMANT and now - last_feed > HUNGER_DELAY


func tick(delta: float, now: float) -> void:
	if not is_hungry(now):
		return
	var rate: float = STAGES[stage()].decay * (STEADY_DECAY if now < steady_until else 1.0)
	charge = maxf(0.0, charge - rate * delta)
	if charge <= 0.0:
		souls = [0.0, 0.0, 0.0, 0.0, 0.0]


## Possession changed hands. Applies the exposure rule and re-bonds the ball to `team`.
func turnover(team: int, now: float) -> int:
	if team == bond:
		return Lost.NONE
	bond = team
	var s := stage()
	var keep := 1.0
	var lost := Lost.NONE
	if s == Stage.OVERLOADED:
		keep = BACKLASH_KEEP
		lost = Lost.BACKLASH
	elif s >= Stage.POSSESSED:
		keep = SCATTER_KEEP
		lost = Lost.SCATTER
	charge *= keep
	for k in souls.size():
		souls[k] *= keep
	last_feed = now
	return lost


func spend(cost: float) -> bool:
	if charge < cost:
		return false
	charge -= cost
	return true


## Stage multiplier `key` for a player of `team`.
func boost(team: int, key: String) -> float:
	return STAGES[stage() if team == bond else Stage.DORMANT][key]


## Stolen identity this team is carrying, or -1.
func perk(team: int) -> int:
	return dominant() if team == bond else -1


static func self_test() -> void:
	var v := Vessel.new()
	v.reset(0, 0.0)
	assert(v.stage() == Stage.DORMANT and v.dominant() == -1 and v.perk(0) == -1 and v.glow() == Color.WHITE)
	assert(v.boost(0, "speed") == 0.9)
	v.feed(25.0, Kind.SPEED, 0.0)
	assert(v.stage() == Stage.STIRRING and v.dominant() == Kind.SPEED and v.perk(0) == Kind.SPEED and v.perk(1) == -1)
	assert(v.glow().s > 0.0 and v.glow().s < KINDS[Kind.SPEED].color.s)   # tinted, not yet saturated
	assert(v.boost(0, "speed") == 1.0 and v.boost(1, "speed") == 0.9)
	v.tick(1.0, 2.0)                                   # fed recently: no decay
	assert(v.charge == 25.0)
	v.tick(1.0, 10.0)                                  # hungry: STIRRING decays 1.5/s
	assert(is_equal_approx(v.charge, 23.5))
	v.steady(10.0, 2.0)
	v.tick(1.0, 11.0)
	assert(is_equal_approx(v.charge, 23.5 - 1.5 * STEADY_DECAY))
	assert(v.turnover(0, 11.0) == Lost.NONE)           # same team keeps it
	assert(v.turnover(1, 11.0) == Lost.NONE and v.bond == 1)   # low charge: just possession
	v.feed(40.0, Kind.POWER, 12.0)
	assert(v.stage() == Stage.POSSESSED and v.dominant() == Kind.POWER)
	var c := v.charge
	assert(v.turnover(0, 12.0) == Lost.SCATTER and is_equal_approx(v.charge, c * SCATTER_KEEP))
	v.feed(100.0, Kind.TRICK, 13.0)
	assert(v.stage() == Stage.OVERLOADED and v.charge == 100.0)
	assert(v.glow().is_equal_approx(KINDS[Kind.TRICK].color))   # full momentum = full colour
	assert(v.turnover(1, 13.0) == Lost.BACKLASH and v.bond == 1 and v.stage() == Stage.HUNGRY)
	assert(v.spend(30.0) and not v.spend(500.0))
	v.reset(1, 20.0)
	assert(v.charge == 0.0 and v.bond == 1 and v.dominant() == -1)
	print("Vessel self_test OK")
