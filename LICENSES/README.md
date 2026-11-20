# Copyright and third-party notices

## Original clock software

Stinky Kitten Limited owns and publishes the original clock software developed by Gary J.H. Atkinson. The company is the licensor under the [PolyForm Noncommercial License 1.0.0](../LICENSE). The [required notice](../NOTICE) must accompany redistribution along with the licence text or its official URL, as specified in the licence. Commercial exploitation of the original clock software requires separate permission from Stinky Kitten Limited.

The clock licence covers the company's original software, including its hand-authored `MSFBitFont` and original rasterisation and integration code. The following material has separate rights or licence terms.

## Fonts

[`ClockFont.swift`](../src/render/fonts/ClockFont.swift) contains rasterised glyph data from Liberation Sans Bold. The retired `SmallFont.swift` used Liberation Sans. The verified source fonts are Liberation 2.1.5, digitised data copyright (c) 2010 Google Corporation and copyright (c) 2012 Red Hat, Inc. Reserved names include Arimo, Tinos, Cousine and Liberation. The derived glyph data remains under the [SIL Open Font License 1.1](Liberation-OFL-1.1.txt), which includes the complete source notice. `ClockFont` and `SmallFont` identify the derived application assets. References to Liberation in provenance comments acknowledge upstream.

The Liberation TTFs are absent from the source snapshot. See [font provenance](../docs/font-provenance.md) for source hashes, exact regeneration results and current glyph provenance. Any distribution of historical font variants must carry the applicable notices.

[`PixelOperator8Font.swift`](../src/render/fonts/PixelOperator8Font.swift) supplies printable ASCII glyphs used by the production analytical and digital faces. It is generated from the [vendored `PixelOperator8.ttf`](../tools/fonts/PixelOperator8.ttf) by Jayvee Enaguas (HarvettFox96), release 2018.10.04-1. The font and its derived glyph data are covered by [CC0 1.0](PixelOperator-CC0-1.0.txt). See [font provenance](../docs/font-provenance.md#pixel-operator-8).

## Raspberry Pi SDK and HUB75 dependency

[`pico_sdk_import.cmake`](../pico_sdk_import.cmake) retains its original Raspberry Pi BSD-3-Clause notice. The corresponding [SDK licence](Pico-SDK-BSD-3-Clause.txt) is included here.

The separately distributed [HUB75 binary package](https://github.com/stinky-kitten/skls-hub75-dist/releases/tag/v0.1.0-experimental.3) carries the Stinky Kitten HUB75 Binary Library Licence — Version 1.0 and Pico SDK/PIO notices. The package licence covers the company's original driver contributions. Raspberry Pi's BSD rights in incorporated material remain separate. The driver licence grants rights to the driver as described by its own terms.

This release consists of source code. Any future distribution of compiled firmware must account for the terms of the components actually linked or included, including Pico SDK and toolchain components, USB and optional CYW43 support. The HUB75 package notices cover the driver distribution.

## Photographs and demonstration videos

Gary J.H. Atkinson owns the [digital face](../docs/images/radio-clock-digital.jpg), [analogue face](../docs/images/radio-clock-analogue.jpg) and [earlier analytical face](../docs/images/analytical-msf-clock.jpg) photographs. He licenses them to Stinky Kitten Limited for project publication and promotion. The photographs are outside the PolyForm grant. The publication copies omit embedded personal metadata. The analytical photograph retains its original JPEG image data and Display P3 colour profile.

The developer's personally created demonstration videos likewise remain personally owned and are licensed to the company for project publication and promotion. Any links point to externally hosted videos. The videos are outside the PolyForm grant.

## Review ZIP utility

Stinky Kitten Limited includes the copy of [`tools/make_review_zip.sh`](../tools/make_review_zip.sh) distributed with `sk-radio-clock` in its original software licensed under PolyForm Noncommercial 1.0.0. This grant applies to the clock repository’s copy. Licensing for the canonical utility in the separate `sk-tools` repository is undecided.
