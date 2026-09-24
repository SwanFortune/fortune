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

// fxAudit() reads six content tables that are globals in the prototype. Those
// tables are CONTENT, which the port loads from data/base/ and a mod can
// change, so they are handed in with each case rather than cut out of the
// .html: what is under test is the audit's logic, over the same data on both
// sides.
const AUDIT_TABLES = ['FX', 'READERS', 'RELICS', 'MARKS', 'SIGNS', 'JOBS'];

function auditor() {
	const src = fs.readFileSync(SPEC, 'utf8');
	return new Function(...AUDIT_TABLES, cut(src, 'fxAudit', 'function') + '\nreturn fxAudit();');
}

// THE RUN FLOW: a fight from the knock to the verdict. startFight() builds it,
// resolveRead() settles each reading and decides win, lose or another round,
// win()/lose() pay out. They are stateful — they read and write `this.state`
// through React's setState — so they are cut out with everything they reach and
// run against a stand-in that applies a patch at once and calls back.
//
// The content they read (JOBS, RELICS, DENIAL_SHIELD) is handed in, as for the
// audit. Colours and the ring are the prototype's own.
const FLOW_METHODS = ['startFight', 'beginTurn', 'drawTo', '_lay', 'resolveRead', 'win', 'lose', 'rollRelic',
	'clearTips', 'cfg', 'shuffle', 'pickRand'];
const FLOW_CONSTS = ['GOLD', 'RING', 'jobOf'];
const FLOW_TABLES = ['JOBS', 'RELICS', 'DENIAL_SHIELD'];

function flow() {
	const src = fs.readFileSync(SPEC, 'utf8');
	const ring = /const NEXT = (\{[^}]*\})/.exec(src);
	const body = 'const NEXT = ' + ring[1] + ';\n'
		+ CONSTS.concat(FLOW_CONSTS).map((n) => cut(src, n, 'const')).join('\n') + '\n'
		+ FUNCTIONS.map((n) => cut(src, n, 'function')).join('\n') + '\n'
		+ 'return { state: null, props: {},\n'
		+ 'setState(patch, then) { Object.assign(this.state, patch); if (then) then(); },\n'
		+ METHODS.concat(FLOW_METHODS).map((n) => cut(src, n)).join(',\n') + '\n};';
	return new Function(...FLOW_TABLES, body);
}

/**
 * One fight, played to the end or to the last scripted reading. `lays` says
 * how many cards from the front of the hand go down each reading; what is
 * reported after each step is everything a shuffle cannot change.
 */
function playFight(make, one) {
	const g = make(...FLOW_TABLES.map((t) => one[t]));
	g.state = one.state;
	g.props = one.props;
	const seen = [];
	const look = () => {
		const f = g.state.f, st = g.state;
		seen.push({
			hp: f.hp, faith: f.faith, coin: f.coin, turn: f.turn, turns: f.turns, denial: f.denial,
			denialUp: f.denialUp, energy: f.energy, energyMax: f.energyMax, handMax: f.handMax, swept: f.swept,
			hand: f.hand.length, draw: f.draw.length, disc: f.disc.length, gone: f.gone.length,
			taken: f.taken != null, max: f.max, cross: f.cross.length,
			runCoin: st.coin, runFaith: st.faith, mended: st.mended, marks: st.marks.length,
			serpEl: st.serpEl || '', res: st.res ? st.res.kind : '', seen: st.seen.length,
		});
	};
	g.startFight(one.o);
	look();
	for (const k of one.lays) {
		if (g.state.res) break;
		if (one.viaLay) {
			// Through the prototype's own _lay(): cost, energy back, draw on lay.
			// It replaces state.f with a copy each time, so ask for it afresh.
			for (let j = 0; j < k && g.state.f.hand.length; j++) g._lay(g.state.f.hand[0].uid);
		} else {
			const f = g.state.f;
			f.cross = f.hand.splice(0, Math.min(k, f.hand.length));
		}
		look();
		g.resolveRead(g.simulate(g.state.f));
		look();
	}
	return seen;
}

// weighted() rolls Math.random() once. To put it next to the port's with the
// SAME roll, it is run with a Math whose random() answers what the case says.
function picker() {
	const src = fs.readFileSync(SPEC, 'utf8');
	const dice = Object.create(Math);
	dice.u = 0;
	dice.random = () => dice.u;
	const make = new Function('Math', cut(src, 'RARW', 'const') + '\nreturn {' + cut(src, 'weighted') + '};');
	const g = make(dice);
	return (pool, u) => { dice.u = u; const c = g.weighted(pool); return c ? pool.indexOf(c) : -1; };
}

function main() {
	const [, , casesPath, outPath] = process.argv;
	if (!casesPath || !outPath) {
		throw new Error('usage: prototype_bridge.js <cases.json> <out.json>');
	}
	const proto = engine();
	const audit = auditor();
	const fights = flow();
	const pick = picker();
	const cases = JSON.parse(fs.readFileSync(casesPath, 'utf8'));
	const out = cases.map((one) => {
		if (one.kind === 'autoText') return proto.autoText(one.card);
		if (one.kind === 'elements') return proto.EL;
		if (one.kind === 'fill') return proto.fill(one.text, one.pronoun);
		if (one.kind === 'pronouns') return proto.PRON;
		if (one.kind === 'weighted') return pick(one.pool, one.u);
		if (one.kind === 'fight') return playFight(fights, one);
		if (one.kind === 'fxAudit') return audit(...AUDIT_TABLES.map((t) => one[t]));
		if (one.kind === 'scaleSitter') return proto.scaleSitter(one.sitter, one.night, one.step);
		proto.state = one.state;
		return proto.simulate(one.f);
	});
	fs.writeFileSync(outPath, JSON.stringify(out));
	process.stderr.write('bridge: ran ' + out.length + ' case(s) through the prototype\n');
}

main();
