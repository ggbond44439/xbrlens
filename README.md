# XBRLens

XBRLens is a MoonBit-native XBRL 2.1 parsing and validation engine. It is intended for financial filing ingestion, taxonomy-aware fact normalization, XBRL Dimensions handling and calculation relationship checks.

## Features

- Bounded, namespace-aware XML parser with DTD/entity rejection
- XBRL contexts, periods, entities, units and facts
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
moon add ggbond44439/xbrlens@0.1.6
```

The current Mooncakes release is `0.1.6`. The library requires MoonBit `moonc >= 0.10.16` and has no native runtime dependency.

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

## Security

Parsing is bounded by configurable source, XML depth, node, attribute, text, fact and linkbase-arc limits. DTDs and external entities are rejected, as are invalid XML control characters and raw `]]>` text. Use `audit_instance_source` to obtain a bounded input audit summary.

## License

Apache-2.0