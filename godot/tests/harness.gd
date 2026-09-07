## The thing every test file in here is.
##   extends "res://tests/harness.gd"
##
## WHY THIS EXISTS, and it is not tidiness.
##
## There were 161 test methods across fourteen files, and every one of them was
## reached by its own name TYPED A SECOND TIME BY HAND — either in a `const
## TESTS` array at the top of the file or as a call written out in
## `_initialize()`. That is a hand-kept checklist 161 entries long, in the
## repository whose CLAUDE.md says a hand-kept checklist will fall behind, and
## it already had: methods appended to tests/test_save.gd sat there for a while
## being counted as coverage and never running once. Nothing catches that. There
## is no error, no warning, nothing on the console — the file passes, and the
## thing it was written to check is simply not checked.
##
## So the list is DERIVED. Every method whose name begins with `_test_` runs, in
## the order it is declared, because it exists. There is nothing to keep in step.
##
## The second thing it does is make the abort guard automatic. A runtime error
## inside a test aborts THAT METHOD and returns to the caller, so the checks
## below the error never run and the file still says ALL PASS — verified, on
## tests/test_art.gd, by putting a typo in the middle of a method: two of its
## three checks vanished and the file reported success. (tests/run_all.sh does
## catch it, through its rule about unexpected console lines. Running one file
## on its own, which is how anyone actually iterates, does not.) Eight files
## guarded against this by calling `done("_test_the_name")` on the last line;
## the other six did not, and the eight had to repeat the name a third time.
## Here `done()` takes no argument — it knows which test is running — and a test
## that never reaches it is reported.
##
## What a file overrides: setup() once before anything, before_each()/after_each()
## around every test, teardown() at the end, and summary() for the detail its
## ALL PASS line used to carry. All four may await.
extends SceneTree

## Appended to by check(). Non-empty means the file fails.
var failures: Array[String] = []

## The test currently running, so done() needs no argument.
var _current := ""
var _reached: Dictionary = {}
var _ran: Array[String] = []


func _initialize() -> void:
	# Every test file did this first: one frame so the autoloads are up.
	await process_frame

	var tests := test_methods()
	if tests.is_empty():
		failures.append("this file declares no _test_ methods at all — it would otherwise pass having checked nothing")

	# Called through call() rather than as setup() so that a file overriding one
	# of these with a coroutine is not a compile-time REDUNDANT_AWAIT warning
	# here, where the base version is a plain function. The suite fails on
	# unexpected warnings, so this is not cosmetic.
	await call("setup")
	for name in tests:
		_current = name
		await call("before_each", name)
		await call(name)
		if not _reached.has(name):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % name)
		await call("after_each", name)
		_ran.append(name)
	await call("teardown")

	if failures.is_empty():
		var extra := str(await call("summary"))
		print("ALL PASS — %d test method(s)%s" % [_ran.size(), "" if extra == "" else " — " + extra])
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


## EVERY `_test_` METHOD THIS FILE DECLARES, in declaration order.
##
## get_method_list() on the instance returns the subclass's own methods first, in
## the order they are written, then this class's, then SceneTree's — checked
## rather than assumed, because "runs in a sensible order" and "runs in the order
## you read them" are different promises and the second is the one a test file's
## structure relies on.
func test_methods() -> Array[String]:
	var out: Array[String] = []
	for m in get_method_list():
		var name := str(m.get("name", ""))
		if name.begins_with("_test_") and not out.has(name):
			out.append(name)
	return out


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


## The last line of every test. Says "this method ran to the end" — without it,
## a method that died halfway reports success for the half that ran.
func done() -> void:
	_reached[_current] = true


# ── hooks, all optional ─────────────────────────────────────────────────

## Once, after the autoloads are up and before the first test.
func setup() -> void:
	pass


func before_each(_test_name: String) -> void:
	pass


func after_each(_test_name: String) -> void:
	pass


## Once, after the last test — whether or not anything failed. Where a file puts
## the state it borrowed back the way it found it.
func teardown() -> void:
	pass


## Whatever this file's ALL PASS line used to say beyond the count: "10 sounds
## registered", "art status: {...}". Returned rather than printed so the harness
## owns the line.
func summary() -> String:
	return ""
