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

## License

Apache-2.0
