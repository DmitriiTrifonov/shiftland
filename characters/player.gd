extends RigidBody2D
## Tech-demo movement controller for all three forms (GDD §5, §13.2, §14).
## One persistent RigidBody2D for every form so switching never touches
## linear_velocity/global_position — momentum carries across the shift.

enum Form { CIRCLE, TRIANGLE, SQUARE }

const STICK_DEADZONE := 0.25

const CIRCLE_MASS := 0.6
const CIRCLE_RADIUS := 28.0 # must track CircleShape2D.radius in build_scenes.gd
# Purely a visual cap on the sprite's spin now (see CIRCLE_LAUNCH_*_SPEED
# below) — kept well inside the range already verified stable live, rather
# than the much higher number that used to also double as the top-speed
# knob (see that comment for why that coupling had to go).
const CIRCLE_MAX_ANGULAR_VELOCITY := 90.0
const CIRCLE_SPIN_ATTACK_THRESHOLD := 10.0
const CIRCLE_ATTACK_BURST := 25.0
const CIRCLE_KNOCKBACK := 260.0
const CIRCLE_ANGULAR_DAMP := 0.4
# Spin dash: wind up in place, release to launch — no more continuous
# stick-steered rolling (GDD §5/§7 revision). With a stick, winding means
# physically tracing a circle (charge tracks radians actually swept, not
# just holding a direction); spin_ccw/spin_cw keys keep the old hold-to-charge
# behavior since a digital key can't be "rotated".
const CIRCLE_CHARGE_RATE := 0.6
const CIRCLE_CHARGE_MAX := 1.0
const CIRCLE_CHARGE_MIN_LAUNCH := 0.15
# Launch speed is a LINEAR speed driven straight into linear_velocity.x on
# release (see circle_roll_speed/_dir below), not an angular_velocity fed
# through the physics engine's own friction-based spin-to-roll conversion —
# that conversion was the actual bug behind "speed gets eaten fast after the
# dash". Verified live via Godot MCP: forcing angular_velocity straight to a
# few hundred rad/s made the contact solver blow up within 1-2 physics
# frames — a single step at that rate sweeps the circle through multiple
# full turns, far past what discrete contact resolution can handle — and
# both velocities got silently zeroed by the fall-safety net almost
# instantly. That looked exactly like "speed evaporating" but was really a
# physics crash, not gradual friction decay, so no amount of raising the old
# angular numbers could ever have fixed it. Driving translation directly
# (same pattern Triangle/Square already use for their own movement) sidesteps
# the unstable regime entirely and makes top speed both stable and tunable.
const CIRCLE_LAUNCH_MIN_SPEED := 500.0
const CIRCLE_LAUNCH_MAX_SPEED := 3000.0
# How fast a full-speed roll bleeds off on its own once launched (px/s per
# second) — the "Sonic keeps rolling for a good while" feel. At max speed
# that's ~8.5s to coast to a stop; scales down proportionally from a lighter
# charge.
const CIRCLE_ROLL_FRICTION := 350.0
# Charging now takes noticeably longer to fill (was 1 turn / 1.2 charge-per-
# second) — the payoff being bigger means the wind-up should feel like it too.
const CIRCLE_STICK_TURNS_TO_FULL := 2.0
# How far the SpinMarker visually winds — in the direction it's about to
# launch — while charging, as a fraction of a full turn at CIRCLE_CHARGE_MAX.
# Purely cosmetic (charge itself is unaffected): previews which way the roll
# is about to go before it fires, distinct from the marker's other job of
# showing the actual roll direction/speed once launched. Deliberately
# NOT a whole number of turns (verified live: 1.0 was tried first and rotates
# a full 360°, landing exactly back on the neutral spot — a full charge then
# looked visually identical to no charge at all, hiding the one moment that
# most needs to read clearly). 0.5 lands the marker on the exact opposite
# side of the body at max charge, as far from neutral as it can get.
const CIRCLE_WIND_VISUAL_TURNS := 0.5
# Hysteresis so ordinary analog jitter near STICK_DEADZONE can't flicker
# winding off for a single frame (that used to silently fire a zero-charge
# launch and wipe the charge back to 0 while the stick was still held).
const CIRCLE_WIND_RELEASE_DEADZONE := 0.12
# Per-frame angle deltas smaller than this are stick-noise, not real turning —
# ignoring them stops jitter from falsely flipping the winding direction.
const CIRCLE_STICK_TURN_NOISE := 0.03

const TRIANGLE_MASS := 1.0
const TRIANGLE_SPEED := 220.0
const TRIANGLE_KNOCKBACK := 320.0
# Wedge (GDD §6 "Треугольник-клин" generalized to normal movement): whichever
# of the 3 corners currently points down into the floor plants like a staff
# and the body rides up it. Offsets measured from triangle.png's alpha mask,
# relative to Corpus's origin (the incenter, see the incenter-pivot change) —
# apex, then the two base corners. A corner's rotated-direction.y ranges from
# -1 (aiming up) to +1 (aiming straight down); MIN_DOWN gates how far past
# horizontal it must tip before it counts as "planting". Kept fairly steep on
# purpose: at a shallow angle the wedge's long ray (90 units) sweeps its
# landing point across a wide horizontal span for a tiny change in ray-origin
# height — and the origin height is itself the wedge's own output from the
# previous frame. Straddling a gap (e.g. standing across two separate boxes)
# that feedback loop never settles: the ray alternates between the near box,
# the far box, and the gap between them, each giving a wildly different
# target height, so the body bounces instead of planting (bug report: corner
# turned almost parallel to the ground while standing on two boxes).
# Requiring a steeper tip keeps the ray closer to vertical, where a height
# change barely moves the landing point at all.
const TRIANGLE_CORNERS := [
	Vector2(0.0, -43.835),   # apex
	Vector2(-31.875, 19.665), # base-left
	Vector2(31.875, 19.665),  # base-right
]
const TRIANGLE_WEDGE_RAY_LENGTH := 90.0
const TRIANGLE_WEDGE_MIN_DOWN := 0.6
# Caps how fast the wedge can correct the body's height in one frame. Without
# this the controller is "deadbeat" (closes the whole gap in a single physics
# step) — fine while sliding along a flat floor where the target barely moves
# frame to frame, but walking up to a crate can make the raycast hit jump from
# a far floor point to a near point on the crate's face/edge in one frame,
# demanding tens of pixels of correction *this step* — which becomes a huge
# one-frame velocity spike and reads as being launched into the air (bug
# report: climbing onto a crate as Triangle shoots you upward).
const TRIANGLE_WEDGE_MAX_CLIMB_SPEED := 500.0
# Jumping off a plant needs a moment where the wedge won't immediately
# re-solve the body back down to the same spot — without this, jump while
# still aiming down would get silently cancelled one physics tick later.
const TRIANGLE_WEDGE_RELEASE_TIME := 0.3

const SQUARE_MASS := 4.5
# Mass alone doesn't change how fast a RigidBody2D falls (gravity acceleration
# is mass-independent) — this is what actually makes Square drop faster;
# the raised mass instead makes it hit harder and resist being shoved around
# in collisions, matching the "heavy" request in spirit.
const SQUARE_GRAVITY_SCALE := 1.7
const SQUARE_SPEED := 70.0
const SQUARE_LUNGE := 90.0
const SQUARE_KNOCKBACK := 480.0

const JUMP_IMPULSE := 420.0
const ATTACK_DURATION := 0.15
const FACE_EMOTION_HOLD := 0.25
const MOVE_EMOTION_SPEED := 40.0

const LEG_STEP_LENGTH := 26.0
const LEG_LIFT := 6.0
const LEG_BASE_REACH := 40.0
const LEG_CYCLE_BASE_RATE := 5.0
const LEG_CYCLE_SPEED_SCALE := 0.03

var current_form: int = Form.TRIANGLE
var grounded := false
var facing := 1.0
var aim_angle := 0.0
var aim_is_from_stick := false
var leg_phase := 0.0
var attack_timer := 0.0
var face_emotion_timer := 0.0
var spin_charge := 0.0
var spin_charge_dir := 0.0
var stick_winding := false
var prev_stick_angle := 0.0
var circle_roll_speed := 0.0
var circle_roll_dir := 0.0
var circle_roll_prev_speed := 0.0
var wedge_active := false
var wedge_release_timer := 0.0
var spin_marker_base_offset := Vector2.ZERO

@onready var ground_check: RayCast2D = $GroundCheck
@onready var circle_form: Node2D = $CircleForm
@onready var circle_collision: CollisionShape2D = $CircleCollision
@onready var spin_marker: Sprite2D = $CircleForm/SpinMarker
@onready var spin_attack_shape: CollisionShape2D = $CircleForm/SpinAttackArea/SpinAttackShape
@onready var triangle_form: Node2D = $TriangleForm
@onready var triangle_collision: CollisionShape2D = $TriangleCollision
@onready var corpus: Node2D = $TriangleForm/Corpus
@onready var point_attack_shape: CollisionShape2D = $TriangleForm/Corpus/PointAttackArea/PointAttackShape
@onready var triangle_legs: Node2D = $TriangleForm/Legs
@onready var square_form: Node2D = $SquareForm
@onready var square_collision: CollisionShape2D = $SquareCollision
@onready var square_legs: Node2D = $SquareForm/Legs
@onready var square_attack_area: Area2D = $SquareForm/AttackArea
@onready var square_attack_shape: CollisionShape2D = $SquareForm/AttackArea/AttackShape
@onready var face: Node2D = $Face


func _ready() -> void:
	add_to_group("player")
	spin_marker_base_offset = spin_marker.position
	_set_form(current_form)


func _physics_process(delta: float) -> void:
	# GroundCheck is a direct child of this rotating body, so without this it
	# spins along with Circle's roll and the ray stops pointing straight down —
	# grounded flickers false mid-spin and jump silently drops (bug report).
	ground_check.global_rotation = 0.0
	ground_check.force_raycast_update()
	grounded = ground_check.is_colliding()
	_update_form_from_triggers()

	match current_form:
		Form.CIRCLE:
			_process_circle(delta)
		Form.TRIANGLE:
			_process_triangle(delta)
		Form.SQUARE:
			_process_square(delta)

	_handle_jump()
	_handle_attack_input()
	_update_timers(delta)


## Gamepad right stick first. Mouse aiming only kicks in when no gamepad is
## connected at all — otherwise releasing the stick back to center would
## snap aim to wherever the mouse happens to sit instead of holding position
## (GDD §10; mouse is the keyboard/mouse solo fallback, not a second input).
func _get_rotation_input() -> Vector2:
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	if stick.length() > STICK_DEADZONE:
		return stick
	if not Input.get_connected_joypads().is_empty():
		return Vector2.ZERO
	var mouse_dir := get_global_mouse_position() - global_position
	if mouse_dir.length() > 4.0:
		return mouse_dir.normalized()
	return Vector2.ZERO


## Spin dash (GDD §5/§7 revision): wind up in place, release to launch — the
## roll afterwards is its own script-driven coast (circle_roll_speed, decaying
## at CIRCLE_ROLL_FRICTION), not continuous steering or physics momentum.
## With the stick, winding means physically tracing a circle: charge tracks
## radians actually swept (clockwise or counter-clockwise), not just holding
## a direction, so waggling the stick back and forth charges nothing.
func _process_circle(delta: float) -> void:
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	var key_axis := Input.get_axis("spin_ccw", "spin_cw")
	var charging := false

	# Once winding, only a deeper release counts as "let go" — see
	# CIRCLE_WIND_RELEASE_DEADZONE comment above.
	var wind_threshold := CIRCLE_WIND_RELEASE_DEADZONE if stick_winding else STICK_DEADZONE

	if stick.length() > wind_threshold:
		var current_angle := stick.angle()
		if stick_winding:
			var turned := angle_difference(prev_stick_angle, current_angle)
			if absf(turned) > CIRCLE_STICK_TURN_NOISE:
				var turn_dir := signf(turned)
				if spin_charge_dir != 0.0 and turn_dir != spin_charge_dir:
					spin_charge = 0.0 # reversed winding direction — start over
				spin_charge_dir = turn_dir
				spin_charge = clampf(spin_charge + absf(turned) / (TAU * CIRCLE_STICK_TURNS_TO_FULL) * CIRCLE_CHARGE_MAX, 0.0, CIRCLE_CHARGE_MAX)
				prev_stick_angle = current_angle
			# else: treat as noise — keep the stale prev_stick_angle so a slow
			# turn still accumulates once its total crosses the noise floor.
		else:
			stick_winding = true # first frame of a wind-up: just record the angle, no delta yet
			prev_stick_angle = current_angle
		charging = true
	else:
		stick_winding = false
		if not is_zero_approx(key_axis):
			var dir := signf(key_axis)
			if spin_charge_dir != 0.0 and dir != spin_charge_dir:
				spin_charge = 0.0
			spin_charge_dir = dir
			spin_charge = minf(spin_charge + CIRCLE_CHARGE_RATE * delta, CIRCLE_CHARGE_MAX)
			charging = true
		elif spin_charge_dir != 0.0:
			if spin_charge >= CIRCLE_CHARGE_MIN_LAUNCH:
				circle_roll_speed = lerpf(CIRCLE_LAUNCH_MIN_SPEED, CIRCLE_LAUNCH_MAX_SPEED, spin_charge / CIRCLE_CHARGE_MAX)
				circle_roll_dir = spin_charge_dir
			spin_charge = 0.0
			spin_charge_dir = 0.0

	if charging:
		# Frozen, not stopped: circle_roll_speed/_dir are left untouched here,
		# so momentum from an earlier roll carries through a wind-up instead
		# of hard-cutting — only the visible spin pauses, echoing "wind up in
		# place" without actually fighting whatever motion is still ongoing.
		angular_velocity = 0.0
	else:
		# Coast: driven straight into linear_velocity.x every frame, the same
		# way Triangle/Square already drive their own movement, instead of
		# leaving translation to the physics engine's contact/friction solver
		# (see CIRCLE_LAUNCH_MIN_SPEED comment for why that broke down). Decays
		# on its own fixed schedule rather than physics friction, and angular
		# velocity is derived from it purely for the visual roll — never the
		# other way around anymore. Only touches linear_velocity.x while an
		# actual dash is live (circle_roll_dir != 0) — otherwise it's left
		# alone so momentum carried in from another form (or a bump) isn't
		# stomped to 0 just for standing in Circle form without having
		# charged anything (GDD §5: form switches never touch linear_velocity).
		if circle_roll_dir != 0.0:
			# Hitting a wall dead-on used to pin the ball there indefinitely
			# instead of falling: re-asserting linear_velocity.x into the same
			# solid obstacle every single frame keeps generating a real normal
			# force, and with friction=1.0 that's enough lateral grip to cancel
			# gravity too — verified live via MCP (rolled into WallRight, got
			# stuck floating mid-air at the wall face until roll_speed decayed
			# away on its own several seconds later). Detected by comparing
			# actual speed against what last frame commanded: a genuine wall
			# stop kills nearly all of it in a single step, whereas riding up
			# a slope changes direction but not speed anywhere near that fast.
			if circle_roll_prev_speed > 0.0 and linear_velocity.length() < circle_roll_prev_speed * 0.25:
				circle_roll_speed = 0.0
				circle_roll_dir = 0.0
				circle_roll_prev_speed = 0.0
			else:
				circle_roll_speed = maxf(circle_roll_speed - CIRCLE_ROLL_FRICTION * delta, 0.0)
				if circle_roll_speed <= 0.0:
					circle_roll_dir = 0.0
				linear_velocity.x = circle_roll_dir * circle_roll_speed
				angular_velocity = circle_roll_dir * clampf(circle_roll_speed / CIRCLE_RADIUS, 0.0, CIRCLE_MAX_ANGULAR_VELOCITY)
				circle_roll_prev_speed = circle_roll_speed
		else:
			angular_velocity = 0.0
			circle_roll_prev_speed = 0.0

	# While charge is held, the marker winds forward in the direction the
	# launch will send it — a preview of which way it's about to take off,
	# building up the same way it'll keep going once released. spin_charge_dir
	# is 0 whenever nothing is charging (including the instant of launch,
	# reset just above), which snaps this back to the neutral offset; once
	# actually rolling, the body's own rotation carries the marker again.
	var wind_angle := spin_charge_dir * spin_charge * CIRCLE_WIND_VISUAL_TURNS * TAU
	spin_marker.position = spin_marker_base_offset.rotated(wind_angle)

	var spinning_fast := absf(angular_velocity) > CIRCLE_SPIN_ATTACK_THRESHOLD
	spin_attack_shape.disabled = not spinning_fast

	if face_emotion_timer <= 0.0:
		if spin_charge_dir != 0.0 or spinning_fast:
			face.set_emotion("wild")
		elif linear_velocity.length() > MOVE_EMOTION_SPEED:
			face.set_emotion("moving")
		else:
			face.set_emotion("idle")


func _process_triangle(delta: float) -> void:
	var move_x := Input.get_axis("move_left", "move_right")
	linear_velocity.x = move_x * TRIANGLE_SPEED
	if not is_zero_approx(move_x):
		facing = signf(move_x)

	# Points exactly where the stick is deflected, instantly; holds that
	# angle once the stick returns to center (per user decision — no ease,
	# no drift back to neutral).
	# +PI/2 offset: the sprite's un-rotated pose already points "up" (angle
	# -PI/2 in Vector2.angle() terms), but stick angle 0 means "right" —
	# without the offset the corpus sits 90° off from where the stick points.
	var stick_raw := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	var aim := _get_rotation_input()
	if aim.length() > 0.0:
		aim_angle = aim.angle() + PI / 2.0
		# Tracks whether the *held* aim came from a real stick push, not the
		# mouse fallback — kept alongside aim_angle (not reset when the stick
		# re-centers) so the wedge below stays consistent with the aim it's
		# still holding, instead of the aim staying down while the wedge lets
		# go and the body's normal standing height doesn't clear the tip.
		aim_is_from_stick = stick_raw.length() > STICK_DEADZONE
	corpus.rotation = aim_angle

	var leg_reach := _process_triangle_wedge(delta)
	_update_legs(triangle_legs, move_x, delta, leg_reach)

	if face_emotion_timer <= 0.0:
		face.set_emotion("moving" if absf(move_x) > 0.1 else "idle")


## Wedge: whichever of the 3 corners is currently aimed steepest into the
## floor (and actually reaches it) becomes this frame's pivot — solves the
## exact body height that plants that corner on the detected ground point
## (pure function of aim angle + hit point, recomputed fresh every frame —
## no accumulated state, so no drift). Returns how far below the (now
## raised) hip the ground sits, so the legs can be stretched to visually
## bridge the gap; returns the normal reach when nothing is planted.
##
## Gated on aim_is_from_stick, not on whether the stick is deflected *right
## now*: the aim itself holds its last direction after the stick re-centers
## (deliberate design, see _process_triangle), so the wedge must keep
## matching that same held aim — cutting the lift the instant the stick
## re-centers left the corpus still visually pointing down while the body
## dropped back to normal standing height, which doesn't clear the tip
## (bug report: "wedges into the floor on release"). Still never engages
## from the mouse fallback, which continuously tracks the cursor and sits
## below the character far too often to treat as a deliberate plant.
func _process_triangle_wedge(delta: float) -> float:
	wedge_active = false
	if wedge_release_timer > 0.0:
		return LEG_BASE_REACH

	if not aim_is_from_stick:
		return LEG_BASE_REACH

	var best_dir := Vector2.ZERO
	var best_distance := 0.0
	var best_down := TRIANGLE_WEDGE_MIN_DOWN
	for corner: Vector2 in TRIANGLE_CORNERS:
		var dir := corner.rotated(corpus.rotation).normalized()
		if dir.y > best_down:
			best_down = dir.y
			best_dir = dir
			best_distance = corner.length()

	if best_dir == Vector2.ZERO:
		return LEG_BASE_REACH # no corner is aimed steeply enough down

	var from := corpus.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + best_dir * TRIANGLE_WEDGE_RAY_LENGTH)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return LEG_BASE_REACH

	var hit_dist := from.distance_to(hit.position)
	if hit_dist >= best_distance:
		return LEG_BASE_REACH # ground is farther than that corner reaches — stand normally

	var target_y: float = hit.position.y - corpus.position.y - best_distance * best_dir.y
	# Drive via linear_velocity, not a direct global_position write: writing
	# position from script skips the physics step's own collision resolution
	# for that motion, which showed up as the body sinking/losing collision
	# with the ground for a frame right as the wedge released (bug report).
	# Clamped (see TRIANGLE_WEDGE_MAX_CLIMB_SPEED) so a sudden jump in the
	# target — e.g. the ray hitting a crate's face instead of the far floor —
	# ramps up to speed instead of snapping there in one step.
	var desired_climb := (target_y - global_position.y) / delta
	linear_velocity.y = clampf(desired_climb, -TRIANGLE_WEDGE_MAX_CLIMB_SPEED, TRIANGLE_WEDGE_MAX_CLIMB_SPEED)
	wedge_active = true

	return maxf(hit.position.y - target_y, LEG_BASE_REACH)


func _process_square(delta: float) -> void:
	var move_x := Input.get_axis("move_left", "move_right")
	linear_velocity.x = move_x * SQUARE_SPEED
	if not is_zero_approx(move_x):
		facing = signf(move_x)

	_update_legs(square_legs, move_x, delta, LEG_BASE_REACH)

	if face_emotion_timer <= 0.0:
		face.set_emotion("moving" if absf(move_x) > 0.1 else "idle")


## Placeholder procedural legs (GDD §13.2 spike #1): straight stick legs,
## foot targets from a downward raycast, phase driven by walk speed.
## Only animates while actually walking on the ground — otherwise (standing
## still, or airborne off a jump) the cycle freezes at a neutral stance
## instead of endlessly stepping in place. Also counts as "grounded" while
## wedge_active: the wedge lifts the body past GroundCheck's fixed 40-unit
## reach, so the raw ray reports airborne even though a corner is still
## planted and the character is still sliding along the floor — without this
## the legs would freeze mid-stride the moment the wedge lifts high enough
## (bug report: legs stop moving when you get taller from the wedge).
func _update_legs(legs: Node2D, move_x: float, delta: float, vertical_reach: float) -> void:
	if (grounded or wedge_active) and absf(move_x) > 0.05:
		# Scaled by actual linear speed, not the raw -1..1 input axis (that
		# bug made the *0.02 term nearly a no-op, so the cycle always ran at
		# roughly the same slow rate regardless of how fast you were moving).
		leg_phase += delta * (LEG_CYCLE_BASE_RATE + absf(linear_velocity.x) * LEG_CYCLE_SPEED_SCALE)
	else:
		leg_phase = 0.0
	_place_leg(legs, "RayL", "LineL", sin(leg_phase), vertical_reach)
	_place_leg(legs, "RayR", "LineR", sin(leg_phase + PI), vertical_reach)


func _place_leg(legs: Node2D, ray_name: String, line_name: String, phase_value: float, vertical_reach: float) -> void:
	var ray: RayCast2D = legs.get_node(ray_name)
	var line: Line2D = legs.get_node(line_name)

	var swing := maxf(phase_value, 0.0)
	var horizontal := phase_value * LEG_STEP_LENGTH * 0.5
	ray.target_position = Vector2(horizontal, vertical_reach)
	ray.force_raycast_update()

	var hip := ray.position
	var foot: Vector2
	if ray.is_colliding():
		foot = legs.to_local(ray.get_collision_point())
	else:
		foot = hip + ray.target_position
	foot.y -= swing * LEG_LIFT

	line.points = PackedVector2Array([hip, foot])


## Circle/Square are held via triggers; releasing both falls back to
## Triangle as the neutral default form (per user decision).
func _update_form_from_triggers() -> void:
	var desired_form := Form.TRIANGLE
	if Input.is_action_pressed("hold_circle"):
		desired_form = Form.CIRCLE
	elif Input.is_action_pressed("hold_square"):
		desired_form = Form.SQUARE

	if desired_form != current_form:
		_set_form(desired_form)


## Only visibility/collision/mass/lock_rotation change here — linear_velocity
## and global_position are left untouched so the switch is seamless (GDD §5).
func _set_form(new_form: int) -> void:
	current_form = new_form

	circle_form.visible = new_form == Form.CIRCLE
	triangle_form.visible = new_form == Form.TRIANGLE
	square_form.visible = new_form == Form.SQUARE

	circle_collision.disabled = new_form != Form.CIRCLE
	triangle_collision.disabled = new_form != Form.TRIANGLE
	square_collision.disabled = new_form != Form.SQUARE

	spin_attack_shape.disabled = true
	point_attack_shape.disabled = true
	square_attack_shape.disabled = true
	leg_phase = 0.0
	spin_charge = 0.0
	spin_charge_dir = 0.0
	stick_winding = false
	# A half-decayed dash doesn't survive a form switch — otherwise leaving
	# Circle mid-coast and coming back later would suddenly stomp whatever
	# real momentum Triangle/Square built up in the meantime with this stale
	# leftover speed the instant _process_circle runs again.
	circle_roll_speed = 0.0
	circle_roll_dir = 0.0
	circle_roll_prev_speed = 0.0
	wedge_active = false
	wedge_release_timer = 0.0
	# aim_is_from_stick deliberately NOT reset here, same as aim_angle isn't:
	# it describes where aim_angle came from, and aim_angle itself carries
	# across a form switch unchanged (Circle/Square don't touch it). Clearing
	# just the flag while leaving the angle it describes intact desynced them —
	# switch away with the corpus aimed down via the stick, switch back to
	# Triangle without touching the stick again, and the corpus still visibly
	# aims down (stale aim_angle) while the wedge silently refused to engage
	# (aim_is_from_stick wrongly read false) — the exact aim/wedge mismatch
	# already fixed once for the release case, reopened here for form switches.

	match new_form:
		Form.CIRCLE:
			mass = CIRCLE_MASS
			lock_rotation = false
			angular_damp = CIRCLE_ANGULAR_DAMP
			gravity_scale = 1.0
		Form.TRIANGLE:
			mass = TRIANGLE_MASS
			lock_rotation = true
			angular_velocity = 0.0
			rotation = 0.0
			gravity_scale = 1.0
		Form.SQUARE:
			mass = SQUARE_MASS
			lock_rotation = true
			angular_velocity = 0.0
			gravity_scale = SQUARE_GRAVITY_SCALE
			rotation = 0.0


func _handle_jump() -> void:
	if not Input.is_action_just_pressed("jump"):
		return
	if not (grounded or wedge_active):
		return

	apply_central_impulse(Vector2(0.0, -JUMP_IMPULSE))
	if wedge_active:
		wedge_release_timer = TRIANGLE_WEDGE_RELEASE_TIME


func _handle_attack_input() -> void:
	if not Input.is_action_just_pressed("attack"):
		return

	match current_form:
		Form.CIRCLE:
			var dir := 1.0 if is_zero_approx(angular_velocity) else signf(angular_velocity)
			apply_torque_impulse(dir * CIRCLE_ATTACK_BURST)
		Form.TRIANGLE:
			point_attack_shape.disabled = false
			attack_timer = ATTACK_DURATION
		Form.SQUARE:
			square_attack_area.position.x = 30.0 * facing
			square_attack_shape.disabled = false
			attack_timer = ATTACK_DURATION
			apply_central_impulse(Vector2(facing * SQUARE_LUNGE, 0.0))

	face.set_emotion("attack")
	face_emotion_timer = FACE_EMOTION_HOLD


func _update_timers(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta
		if attack_timer <= 0.0:
			point_attack_shape.disabled = true
			square_attack_shape.disabled = true
	if face_emotion_timer > 0.0:
		face_emotion_timer -= delta
	if wedge_release_timer > 0.0:
		wedge_release_timer -= delta


func _on_spin_hit(body: Node2D) -> void:
	_apply_knockback(body, CIRCLE_KNOCKBACK)


func _on_point_hit(body: Node2D) -> void:
	_apply_knockback(body, TRIANGLE_KNOCKBACK)


func _on_square_hit(body: Node2D) -> void:
	_apply_knockback(body, SQUARE_KNOCKBACK)


func _apply_knockback(body: Node2D, strength: float) -> void:
	if body == self or not (body is RigidBody2D):
		return
	var dir := body.global_position - global_position
	if dir.length() < 0.01:
		dir = Vector2.RIGHT
	body.apply_central_impulse(dir.normalized() * strength)
	# Duck-typed damage hook: crates and other plain RigidBody2D targets have
	# no take_hit method and are unaffected — only actual enemies (characters/
	# enemy.gd) respond, so every attack's existing knockback also damages
	# anything that opts in, with zero changes needed at the call sites.
	if body.has_method("take_hit"):
		body.take_hit(1)
