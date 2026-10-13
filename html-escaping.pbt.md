# HTML escaping property tests

The root module uses official `moonbitlang/core/quickcheck` only in test scope.
Run `moon test --target all -j 2`.

`html_escape_property_test.mbt` checks text escaping and `title` attribute
serialization against an independent, deliberately partial character-reference
interpreter. Its five supported references use the
[WHATWG mappings](https://html.spec.whatwg.org/multipage/named-characters.html#named-character-references)
and the numeric reference `&#x27;` for U+0027. This strict interpreter accepts only
the serializer's intended escaped subset, not the full HTML parsing language.
It rejects raw reserved characters, unknown and incomplete references, and
decodes only once. Independent vectors test the interpreter; exact serializer
vectors prevent double-escaping and verify each reference spelling.

The generated property has seed 20261012, count 2000, max_size 64, and
max_shrinks 1000. Core generates and shrinks byte arrays before mapping them to
an 18-symbol alphabet containing all five escaped characters, whitespace,
entity-like fragments, and representative BMP/supplementary Unicode. Explicit
boundaries include empty input, repeated delimiters, entity-looking input and
1024 repetitions of a mixed escaping/Unicode string. This is not exhaustive
Unicode coverage. NUL, CR, arbitrary attributes/tags, URL validation, browser
parsing, DOM behavior, sanitization, networking and the nested native/GPUI module
are outside scope.

The native-backend turtles 0.4.6 comparison uses the same unchanged `html.mbt`
source and 15 body-only mutants, with two jobs:

```
turtles --target native --file html.mbt --operators body --jobs 2
```

Baseline: 12 killed, 3 survived. With tests: 13 killed, 2 survived. No timeouts or
unviable mutants. One newly killed mutant makes `is_url_attribute` always true,
incorrectly rejecting ordinary title whitespace (shrunk byte input `[0xa9]`,
mapped to LF). It is caught by both the generated property and a boundary test,
so there are zero property-only kills. Removing `escape_html`'s body was already
caught by existing tests; the new property also catches it with `[0x00]`, mapped
to `a`. The remaining body mutants concern boolean-attribute classification and
void tags, outside this escaping property. Coarse body mutations do not establish
fine-grained escape coverage or comprehensive correctness.

Pristine and property-only root MoonBit tests pass twice on wasm, wasm-gc, JS
and native backends (12 tests before, 15 after). Root all-target check, browser
JS release build and compiled-renderer smoke check also pass. During that initial
property-only validation, full root formatting failed on pre-existing
README.mbt.md and generated-contract formatting, while React/Vite and
generated-contract gates were blocked by missing JS dependencies/tool setup.

The combined property and generator-formatting patch resolves those validation
blockers. With MoonBit 0.10.14+7d59c7ec9 and pnpm 11.24.0, root `moon fmt --check`
and all-target check pass, with 15 tests passing on each of the four backends.
Vite check, TypeScript checking, all 3 frontend unit tests, the Vite build,
generated-contract check and complete `build:parity` pass. The generator now uses
a visible temporary package so MoonBit actually formats the generated contract;
its tokens, comments and all 180 string literals remain unchanged. README.mbt.md
also receives formatter normalization, including explicit `nocheck` fence metadata.
These root-module and frontend gates do not establish real UI end-to-end behavior,
browser visual/interaction parity, or comprehensive sanitization correctness.
