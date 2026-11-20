# Current glyph provenance

[`ClockFont.swift`](../src/render/fonts/ClockFont.swift) contains 12 glyphs and 2,214 bitmap bytes. The [CoreText generator](../tools/generate_clock_font.swift) rasterises Liberation Sans Bold 2.1.5 (PostScript name `LiberationSans-Bold`) at 22 px and adds a custom clock colon drawn by `makeClockColon()`. The recorded regeneration matched the checked-in Swift declarations and bitmap data after disregarding comments and trailing whitespace.

Source font SHA-256:

| File | SHA-256 |
| --- | --- |
| LiberationSans-Bold.ttf | 788abee4c806d660e8aee46689dd8540cd4bb98da03dcc9d171ce3efd99a9173 |

The source font comes from the [Liberation Fonts 2.1.5 release](https://github.com/liberationfonts/liberation-fonts/releases/tag/2.1.5). The repository includes the generator and glyph data. The TTF is obtained separately. The derived glyph data remains under the [SIL Open Font License 1.1](../LICENSES/Liberation-OFL-1.1.txt). Redistribution must retain the upstream copyright notice and licence and observe the Reserved Font Name conditions. `ClockFont` identifies the application asset. References to Liberation acknowledge its upstream provenance.

## Pixel Operator 8

The production analytical and digital clock faces use the generated `PixelOperator8Font.swift` glyph table.

The proportional `tools/fonts/PixelOperator8.ttf` is by Jayvee Enaguas (HarvettFox96), version 2018.10.04-1. It was extracted unchanged from the [author's Pixel Operator release on DaFont](https://www.dafont.com/pixel-operator.font). The [release archive](https://dl.dafont.com/dl/?f=pixel_operator) has SHA-256 `95b33667e4884f5714db33d8324472df28f9d5ffed49108824c5819c1a217dad`. The vendored TTF has SHA-256 `5cccb9ef6cf18977b6e5721d49a1a6e78dd6a6f1c4f69537470f7dc1dc829ffc`. The release's CC0 1.0 legal text is in [LICENSES](../LICENSES/PixelOperator-CC0-1.0.txt).

Run `swift tools/generate_pixel_operator_8_font.swift` from the repository root on macOS. Pass an optional output path to generate a separate copy for comparison. The generator checks the source hash and verifies that every printable ASCII outline has only axis-aligned edges on the native 8 px grid. It tests each pixel centre against the outline's winding fill and packs the result directly into A1. The font's fractional leading rounds up to one whole pixel for line layout.
