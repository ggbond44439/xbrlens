# XBRLens

XBRLens is a MoonBit-native XBRL 2.1 parsing and validation engine. It is intended for financial filing ingestion, taxonomy-aware fact normalization, XBRL Dimensions handling and calculation relationship checks.

## Features

- Bounded, namespace-aware XML parser with DTD/entity rejection
- XBRL contexts, periods, entities, units, item facts and nested tuple facts
- Footnote links, roleRef and arcroleRef parsing
- Exact arbitrary-precision decimal arithmetic
- Taxonomy schema parsing for concepts, imports and role types
- Offline taxonomy catalog and import resolution
- Label, presentation and calculation linkbases
- XBRL Dimensions 1.0 explicit and typed members
- Weighted calculation validation
- Duplicate, conflict and integrity diagnostics
- JSON and CSV fact export
- CLI workflows and inspectable security audits
- `wasm`, `wasm-gc` and JavaScript test coverage

## Install

```bash
moon add ggbond44439/xbrlens@0.3.0
```

The current Mooncakes release is `0.3.0`. The library requires MoonBit `moonc >= 0.10.16` and has no native runtime dependency.

## Usage

```moonbit
let instance = match @xbrlens.parse_instance_xml(source, @xbrlens.XbrlLimits::strict()) {
  Ok(value) => value
  Err(err) => abort(err.to_string())
}

let facts_json = match @xbrlens.export_json(instance) {
  Ok(value) => value
  Err(err) => abort(err.to_string())
}
```

The source argument is an XBRL instance XML string. The parser rejects unsafe declarations, external entities, invalid control characters, malformed namespaces and inputs exceeding configured limits.

## CLI

```bash
moon run cmd/main -- inspect '<instance-xml>'
moon run cmd/main -- facts '<instance-xml>'
moon run cmd/main -- facts --csv '<instance-xml>'
moon run cmd/main -- validate '<instance-xml>'
moon run cmd/main -- calc '<instance-xml>' '<taxonomy-xml>' '<linkbase-xml>'
moon run cmd/main -- diff '<left-instance-xml>' '<right-instance-xml>'
```

## Examples and fixtures

The representative fixture in `fixtures/sample/` contains an instance, taxonomy and calculation linkbase covering duration/instant contexts, a monetary unit, an explicit dimension and a weighted calculation.

```bash
moon run examples/smoke
moon run cmd/main -- calc "$(cat fixtures/sample/instance.xml)" "$(cat fixtures/sample/taxonomy.xsd)" "$(cat fixtures/sample/calculation.xml)"
```

Run independent XML-parser differential checking and the repeatable CLI benchmark:

```bash
python scripts/differential_check.py
python scripts/benchmark.py --iterations 3
```

## Verification

```bash
moon check --target all
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon fmt --check
```

## XBRL 2.1 conformance target

The project target is complete conformance to the XBRL 2.1 base specification and XBRL Dimensions 1.0. The bounded parser is a security and resource-control layer, not the conformance boundary. No standard-defined behavior such as tuple facts or footnote links is permanently excluded from the target.

The implementation is organized into explicit delivery phases:

1. **Current baseline:** bounded XML parsing; QName and namespace handling; instances, contexts, periods, units and item facts; item and nested tuple facts; label, presentation, calculation and footnote linkbases; roleRef and arcroleRef; XBRL Dimensions 1.0 explicit and typed members; precision-aware calculation checks; integrity diagnostics; JSON/CSV export and CLI.
2. **DX/DTS phase:** complete XML Schema and XLink conformance relevant to XBRL, `xsi:nil` and `xsi:type` validation, substitution-group and type derivation semantics, full DTS discovery through offline catalogs, import/redefine/include handling and linkbase role resolution.
3. **Instance semantics phase:** complete tuple content models, tuple/item identity and consistency rules, footnote and locator edge cases, context aspect equivalence, unit equivalence and all duplicate-fact consistency rules required by the base specification.
4. **Conformance phase:** run the official XBRL 2.1 and XBRL Dimensions conformance suites, track every test failure explicitly, and require the complete suite to pass before declaring full conformance. Compatibility fixtures and negative tests remain in CI.
5. **Adjacent specifications:** XBRL Formula, Transformation and Generic Link are separate specifications and are not used to redefine the XBRL 2.1 base target. They can be added as explicitly scoped extensions after the base conformance suite passes.

The current release is therefore a standards-targeted implementation in progress, not a claim that every conformance-suite case already passes.

## Calculation decision mechanism

Calculation checks do not compare rounded lexical values by exact string equality. For each numeric fact, the engine derives an accuracy half-unit from `decimals`, or from significant digits and magnitude when `precision` is supplied:

- `decimals="2"` means a half-unit of `0.005`;
- `decimals="-6"` means a half-unit of `500000`;
- `precision="3"` uses the fact magnitude and significant-digit position;
- `decimals="INF"` is treated as exact.

Child values and their weighted uncertainty are accumulated with exact decimal arithmetic. The resulting expected interval and the parent fact interval are compared for overlap. A missing accuracy indicator on a numeric calculation fact is rejected rather than assumed exact.

Facts are matched by semantic context and unit signatures, not only by `contextRef` or `unitRef` strings. Context signatures include entity, period, segment/scenario content and dimensional content. Unit signatures include normalized measure sets, including divide numerators and denominators. This prevents a calculation from being considered reliable merely because two references share an identifier-like lexical form.

Example: a parent fact of `5,400,000` with `decimals="-6"` and children `2,000,000` and `3,000,000`, each with `decimals="-6"`, produces overlapping expected and reported intervals and is accepted. A parent of `7,000,000` with the same children is outside the expected interval and is reported as a mismatch. The executable fixture is `fixtures/sample/rounded_instance.xml`.

## Security

Parsing is bounded by configurable source, XML depth, node, attribute, text, fact and linkbase-arc limits. DTDs and external entities are rejected, as are invalid XML control characters and raw `]]>` text. Use `audit_instance_source` to obtain a bounded input audit summary.

## License

Apache-2.0