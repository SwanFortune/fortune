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
const METHODS = ['simulate', 'linkOf', 'elOf', 'elBonus', 'myEl', 'has'];

// scaleSitter() is the whole difficulty ladder of the source: how a caller's
// composure and wall grow knock by knock through a night. Pure — it reads its
// three arguments and nothing on `this`.
const PURE_METHODS = ['scaleSitter'];

// autoText() is not a method — it is a plain function with four one-line
// helpers and the element table above it. It writes what is PRINTED ON EVERY
// CARD, which is the half of the specification a player actually reads.
//
// fill() is the pronoun substitution every sign rule goes through ("{S}
// need{es} it" for a he, she or they sitter), and PRON and TOKEN are the table
// and the pattern it fills from.
const FUNCTIONS = ['autoText', 'fill'];
const CONSTS = ['PREVEL', 'NUMW', 'numw', 'capw', 'glyphOf', 'EL', 'PRON', 'TOKEN'];

/** The source text of one definition, found by its name and matched to its brace. */
function cut(src, name, how) {
	const lines = src.split('\n');
	// A method (`simulate(f){`), a function (`function autoText(c){`) or a
	// top-level const, which may be a one-liner or an object over several lines.
	const opener = how === 'const'
		? new RegExp('^const ' + name + '\\s*=')
		: new RegExp('^(function )?\\s*' + name + '\\s*\\(');
	for (let i = 0; i < lines.length; i++) {
		if (!opener.test(lines[i])) continue;
		// A const that closes on its own line needs no brace matching.
		if (how === 'const' && !lines[i].includes('{') || how === 'const' && /};?$/.test(lines[i].trim()) && lines[i].indexOf('{') > lines[i].indexOf('=')) {
			if (!lines[i].includes('{') || /\}\s*;?\s*$/.test(lines[i])) return lines[i];
		}
		if (!lines[i].includes('{')) continue;
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

	// simulate() also calls fill() for the minthree note's wording. That is the
	// real one now, cut out below with the rest; the comparison still treats
	// halveNote as present-or-absent, because the port keeps that wording in the
	// locale rather than in the engine.
	const preamble = 'const NEXT = ' + ring[1] + ';\n';

	const globals = CONSTS.map((n) => cut(src, n, 'const')).join('\n') + '\n'
		+ FUNCTIONS.map((n) => cut(src, n, 'function')).join('\n') + '\n';
	const methods = METHODS.concat(PURE_METHODS).map((n) => cut(src, n)).join(',\n');
	// Object-literal method shorthand is the shape they are already written in.
	const factory = new Function(preamble + globals +
		'return { state: null, autoText, EL, fill, PRON,\n' + methods + '\n};');
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
		if (one.kind === 'autoText') return proto.autoText(one.card);
		if (one.kind === 'elements') return proto.EL;
		if (one.kind === 'fill') return proto.fill(one.text, one.pronoun);
		if (one.kind === 'pronouns') return proto.PRON;
		if (one.kind === 'scaleSitter') return proto.scaleSitter(one.sitter, one.night, one.step);
		proto.state = one.state;
		return proto.simulate(one.f);
	});
	fs.writeFileSync(outPath, JSON.stringify(out));
	process.stderr.write('bridge: ran ' + out.length + ' case(s) through the prototype\n');
}

main();
