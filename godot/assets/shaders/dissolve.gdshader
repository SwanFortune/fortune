// A card coming apart: melting into steam, or burning from its edges. Used by
// autoload/Feel.gd on a COPY of the card — its panel, its words, its drawing,
// every child drawing with this one material — so it works on whatever the
// card looks like: the placeholder today, the illustrator's drawing tomorrow.
//
// `progress` runs 0 (whole) to 1 (gone). A value-noise field decides which
// part goes first; `bias` leans it — positive melts from the top down, like
// something softening — and `edge_color` is the rim left along the line as it
// goes: warm white for steam, orange for fire.
//
// The noise is laid over the CARD, not over each part of it: every child has
// its own UVs (a letter's are a corner of the font's atlas), so the pattern is
// taken from where a pixel is inside `card` — the card's top-left and size on
// screen, kept up to date by Feel as the card moves and shrinks.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.92, 0.78, 1.0);
uniform float edge = 0.09;
uniform float grain = 14.0;
uniform float bias = 0.55;
uniform vec4 card = vec4(0.0, 0.0, 100.0, 140.0);

varying vec2 on_card;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	on_card = (world - card.xy) / max(card.zw, vec2(1.0));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 p = clamp(on_card, vec2(0.0), vec2(1.0));
	float n = noise(p * grain) * 0.65 + noise(p * grain * 2.7) * 0.35;
	// Lean the order: with bias > 0 the top of the card goes first.
	n = mix(n, 1.0 - p.y, clamp(bias, 0.0, 1.0) * 0.6);
	float cut = progress * (1.0 + edge);
	if (n < cut - edge) {
		c.a = 0.0;
	} else if (n < cut) {
		c = vec4(edge_color.rgb, c.a * edge_color.a);
	}
	COLOR = c;
}
