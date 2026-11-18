# XBRLens

XBRLens is a MoonBit-native XBRL parsing and validation engine. It is designed for financial filing ingestion, taxonomy-aware fact normalization, dimension handling, and calculation relationship checks.

The project is under active development. The public API will stabilize after the XBRL 2.1 instance parser and calculation engine are complete.

## Requirements

- MoonBit toolchain with `moonc >= 0.10.16`
- No native runtime dependency for the core library

## Development

```bash
moon check --target all
moon test --target all
moon fmt --check
```

## Security

Parsing is bounded by configurable source, depth, node, attribute, text, fact and linkbase-arc limits. DTDs and external entities are rejected, as are invalid XML control characters and raw `]]>` text. Use `audit_instance_source` to obtain a bounded input audit summary.

## CLI

The executable entry point supports five workflows:

```bash
moon run cmd/main -- inspect '<xbrli:xbrl xmlns:xbrli="http://www.xbrl.org/2003/instance"></xbrli:xbrl>'
moon run cmd/main -- facts '<instance-xml>'
moon run cmd/main -- facts --csv '<instance-xml>'
moon run cmd/main -- validate '<instance-xml>'
moon run cmd/main -- calc '<instance-xml>' '<taxonomy-xml>' '<linkbase-xml>'
moon run cmd/main -- diff '<left-instance-xml>' '<right-instance-xml>'
```

## License

Apache-2.0
