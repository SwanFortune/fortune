## The suite checking itself.
##   godot --headless --path godot -s tests/test_the_suite.gd
##
## THE FAILURE THIS EXISTS FOR MAKES NO SOUND. A test method that is declared
## and never called does not error, does not warn, and does not appear anywhere
## — the file passes, the method is counted as coverage by anyone reading it,
## and the thing it was written to check is simply not checked. It has already
## happened here: methods appended to tests/test_save.gd sat unrun for a while
## because the file drove from a hand-written list they were not on.
##
## tests/harness.gd fixed that by deriving the list, and thirteen of the
## fourteen files with test methods are on it. tests/test_scenes.gd is not: it
## interleaves its tests with scene visits that set them up, so moving it is a
## real refactor rather than a mechanical one, and half-doing it would be worse
## than leaving it. This is what keeps it honest in the meantime — and what will
## keep any future file honest, whichever way it is written.
extends "res://tests/harness.gd"

const TEST_DIR := "res://tests"
const HARNESS := "res://tests/harness.gd"

## Files that drive themselves. Each must reach every _test_ method it declares
## by an explicit call in its own source; the harness files have nothing to
## reach, because the list is derived from what exists.
var _files: Dictionary = {}   # path -> source


func setup() -> void:
	for name in _gd_files(TEST_DIR):
		_files[name] = FileAccess.get_file_as_string(name)


func summary() -> String:
	return "%d test file(s) swept" % _files.size()


## EVERY DECLARED TEST IS REACHED, one way or the other.
##
## Two ways are legitimate. A file that extends the harness has its list derived
## from the methods it declares, so the question cannot arise. A file that drives
## itself has to call each one by name, and that name is then written twice —
## which is the arrangement that fails quietly, so it is checked.
func _test_every_test_method_is_actually_run() -> void:
	var checked := 0
	for path in _files:
		var src: String = _files[path]
		var declared := _declared_tests(src)
		if declared.is_empty():
			continue   # a straight-line script; it is all one test
		checked += 1
		if src.contains('extends "%s"' % HARNESS):
			continue   # derived — there is no list to fall behind
		for name in declared:
			# Called by name somewhere in its own file: `_test_x()`, or
			# `await _test_x()`, or listed as a string in a driving array.
			var called := src.contains("%s()" % name) and src.count("%s(" % name) > 1
			var listed := src.contains('"%s"' % name)
			check(called or listed,
				"%s declares %s() and never calls it — it is counted as coverage and does not run. "
				% [path, name]
				+ "Either call it, or put the file on tests/harness.gd, which derives the list.")
	check(checked >= 10, "expected to sweep the files that have test methods, only saw %d" % checked)
	done()


## A HALF-MIGRATED FILE IS THE WORST OF BOTH.
##
## A file that extends the harness but keeps its own `failures`, `check()`,
## `done()` or `const TESTS` shadows the harness with the code it was supposed to
## replace — and shadowing is silent. A leftover `TESTS` array is the sharpest of
## the four: it would sit there looking exactly like the thing that decides what
## runs, while the harness ran everything regardless of it.
func _test_nothing_shadows_the_harness() -> void:
	for path in _files:
		var src: String = _files[path]
		if not src.contains('extends "%s"' % HARNESS):
			continue
		# ANCHORED TO COLUMN 0, which is where a declaration is. Matching these as
		# plain substrings was the first attempt and it failed on this very file:
		# the needles are written out in the message below, so the check found
		# its own definition and reported five leftovers in a file that has
		# none. CLAUDE.md names that mistake; it is easy to make twice.
		for leftover in ["const TESTS", "var failures", "var finished",
				"func check\\(", "func done\\("]:
			var re := RegEx.create_from_string("(?m)^" + leftover)
			check(re.search(src) == null,
				"%s is on the harness and still declares `%s` at the top level — it shadows the harness's own"
				% [path, leftover.replace("\\", "")])
	done()


## EVERY TEST ON THE HARNESS SIGNS OFF.
##
## done() on the last line is what separates "ran to the end" from "died in the
## middle and the checks below it never happened". A method that never calls it
## fails on every single run with a message about a SCRIPT ERROR that is not
## there, which is a confusing way to find out about a missing line — so this
## says it plainly, naming the file and the method.
func _test_every_test_on_the_harness_signs_off() -> void:
	for path in _files:
		var src: String = _files[path]
		if not src.contains('extends "%s"' % HARNESS):
			continue
		for name in _declared_tests(src):
			check(_body_of(src, name).contains("done()"),
				"%s: %s() never calls done(), so the harness cannot tell it apart from one that died halfway"
				% [path, name])
	done()


## THE HARNESS IS WHAT THE FILES SAY IT IS. Derivation is the whole point of it,
## so if this ever stopped deriving, everything above would keep passing while
## nothing ran. Checked against this file itself, whose methods it can count.
func _test_the_harness_derives_its_own_list() -> void:
	# TWO INDEPENDENT DERIVATIONS, ASKED TO AGREE. One is the harness's, from the
	# engine's method table; the other is this file read off the disk as text.
	# Comparing the engine's answer to a list typed in here would be the same
	# hand-kept list this whole file is about — and the first version of this
	# check was worse than that: it asserted only which name came first, which
	# happens to be first alphabetically too, so it passed just as happily with
	# the harness sorting its output. It proved nothing, which is the one thing
	# a test must not do.
	var derived := test_methods()
	var in_source := _declared_tests(_files.get("res://tests/test_the_suite.gd", ""))
	check(not in_source.is_empty(), "this file should be readable as source")
	check(derived == in_source,
		"the harness must run every test this file declares, in the order it declares them.\n"
		+ "  engine says: %s\n  source says: %s" % [derived, in_source])
	done()


func _declared_tests(src: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("(?m)^func (_test_\\w+)\\s*\\(")
	for m in re.search_all(src):
		out.append(m.get_string(1))
	return out


## One function's body: from its `func` line to the next line at column 0.
func _body_of(src: String, name: String) -> String:
	var at := src.find("\nfunc %s(" % name)
	if at < 0:
		return ""
	var lines := src.substr(at + 1).split("\n")
	var out := ""
	for i in lines.size():
		if i > 0 and lines[i] != "" and not lines[i].begins_with("\t") and not lines[i].begins_with(" "):
			break
		out += lines[i] + "\n"
	return out


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
