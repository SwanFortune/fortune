#!/usr/bin/env node
//
// Runs the PROTOTYPE'S OWN simulate() — the specification — on cases handed to
// it as JSON, so tests/test_against_the_prototype.gd can compare it with
// Rules.gd's port over inputs no human would ever trace by hand.
//
//     node tests/prototype_bridge.js cases.json out.json
//
// WHY THIS IS AN EXTRACTOR AND NOT A COPY. CLAUDE.md says `project/` is the
// specification and that where the two disagree the prototype is right. A
// transcription of simulate() into this file would be a copy of the spec, and a
// copy stops tracking what it copied — which is the failure this repository
// keeps finding, most recently in the mod-override rules. So the functions are
// cut out of project/Parlour v23.dc.html AT RUN TIME, by brace matching. Edit
// the prototype and this follows; delete a function it needs and this says so
// rather than quietly testing a stale copy.
//
// project/ is never written to. It is opened read-only and nothing else.
'use strict';

const fs = require('fs');
const path = require('path');

const SPEC = path.join(__dirname, '..', '..', 'project', 'Parlour v23.dc.html');

// simulate() reaches out to exactly these five, and they reach no further than
// `this.state` and the NEXT ring. Checked by listing every `this.` inside
// simulate(); if that list grows, this throws rather than guessing.
const WANTED = ['simulate', 'linkOf', 'elOf', 'elBonus', 'myEl', 'has'];

/** The source text of one method, found by its name and matched to its brace. */
function cut(src, name) {
	const lines = src.split('\n');
	const opener = new RegExp('^\\s*' + name + '\\s*\\(');
	for (let i = 0; i < lines.length; i++) {
		if (!opener.test(lines[i]) || !lines[i].includes('{')) continue;
		let depth = 0;
		for (let j = i; j < lines.length; j++) {
			for (const ch of lines[j]) {
				if (ch === '{') depth++;
				else if (ch === '}') depth--;
			}
			if (depth === 0) return lines.slice(i, j + 1).join('\n');
		}
	}
	throw new Error(
		name + '() is no longer in ' + path.basename(SPEC) + ' under that name. ' +
		'The specification moved and the port is now being checked against nothing — ' +
		'find it and update tests/prototype_bridge.js.');
}

function engine() {
	const src = fs.readFileSync(SPEC, 'utf8');

	const ring = /const NEXT = (\{[^}]*\})/.exec(src);
	if (!ring) throw new Error('the NEXT ring is no longer a one-line const in the prototype');

	// Anything simulate() calls that is not one of the five and not a method of
	// its own — `fill()` builds the minthree note's wording from the sitter's
	// pronoun, which is prose, not arithmetic. The comparison treats halveNote
	// as present-or-absent for exactly that reason.
	const preamble = 'const NEXT = ' + ring[1] + ';\n' +
		'const fill = (s) => s;\n';

	const methods = WANTED.map((n) => cut(src, n)).join(',\n');
	// Object-literal method shorthand is the shape they are already written in.
	const factory = new Function(preamble + 'return { state: null,\n' + methods + '\n};');
	return factory();
}

function main() {
	const [, , casesPath, outPath] = process.argv;
	if (!casesPath || !outPath) {
		throw new Error('usage: prototype_bridge.js <cases.json> <out.json>');
	}
	const proto = engine();
	const cases = JSON.parse(fs.readFileSync(casesPath, 'utf8'));
	const out = cases.map((one) => {
		proto.state = one.state;
		return proto.simulate(one.f);
	});
	fs.writeFileSync(outPath, JSON.stringify(out));
	process.stderr.write('bridge: ran ' + out.length + ' case(s) through the prototype\n');
}

main();
