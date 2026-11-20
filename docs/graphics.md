# Graphics Geometry and Rasterisation Contract

This document describes the clock renderer’s geometric contracts and current rasterisation behaviour. It also records historical verification and performance measurements, and identifies proposed extensions separately from the implemented API.

## 1. Design principles

The graphics library targets low-resolution LED displays with a regular pixel grid. Its drawing API uses the following conventions:

- **Pixel-sized geometry by default.** One drawing unit corresponds to one destination pixel pitch.
- **Continuous geometry.** Geometric primitives use `Float` coordinates and may move or extend by fractional amounts.
- **Discrete pixel addressing.** Framebuffer locations and dimensions use `Int`.
- **Proposed physical coordinates.** A context-level scale would let geometric primitives accept millimetres using the destination LED pitch.
- **One geometric contract.** The meaning of a shape does not change according to whether it is rendered by analytical coverage, supersampling or another implementation.

A whole-surface fill uses the integer `contextFrame`, a convention that can remain independent of drawing units if physical coordinates are added.

## 2. Pixel grid and default coordinates

In the default coordinate system:

- The origin `(0, 0)` is the **top-left boundary** of the drawing surface.
- X increases rightwards; Y increases downwards.
- Each destination pixel occupies a unit square.
- Integer pairs used as pixel indices identify pixels, not geometric points at their centres.

Pixel `(x, y)` occupies:

`[x, x + 1) × [y, y + 1)`

Its geometric centre is:

`(Float(x) + 0.5, Float(y) + 0.5)`

For a 64×64 surface, the default geometric extent is `[0, 64) × [0, 64)`, with centre `(32, 32)`.

### Geometry versus pixel addressing

These remain deliberately distinct concepts:

| Concept | Representation | Meaning |
| --- | --- | --- |
| `DrawingPoint`, `DrawingSize`, `DrawingRect` | `Float` | Continuous geometry in destination-pixel units |
| Radii and other geometric dimensions | `Float` | Continuous dimensions in destination-pixel units |
| `PixelPoint`, `PixelSize`, `PixelRect` | `Int` | Discrete framebuffer indices, sizes and bounds |

Conversions are explicit. `PixelPoint.drawingCentre` adds `0.5` to each component after conversion to `Float`. `DrawingPoint.pixelContainingPoint` uses mathematical `floor`, including for negative coordinates, and returns `nil` when the result is not representable as an `Int`. `PixelRect.drawingRect` converts the origin and size directly, without a centre offset.

Direct pixel operations such as `setPixel(at:to:)` address actual destination pixels. Pixel-aligned bitmap rendering uses this discrete addressing convention.

## 3. Context coordinate transform and physical pixel pitch

`DrawingContext` currently takes geometry in destination-pixel units and has no coordinate-transform or pitch setting. A rectangle of width `10` spans ten destination pixel pitches.

**Proposed extension:** with a panel pitch of `p` millimetres and a context configured to accept millimetre coordinates, the mapping would be:

`pixelCoordinate = drawingCoordinate / p`

The same scale would apply to geometric positions, sizes, radii and any future geometric stroke widths. The context would carry the scale. A single uniform scale is sufficient for the square-pitch HUB75 panels under consideration.

For example, using a 30 mm square rectangle in millimetre coordinates:

| Destination | Pixel pitch | Pixel-space rectangle size |
| --- | --- | --- |
| P3 | 3 mm | 10 × 10 |
| P2.5 | 2.5 mm | 12 × 12 |

Conversely, a **10 mm** square occupies approximately `3.333 × 3.333` pixel pitches on P3, or `4 × 4` on P2.5. The rasteriser would receive the fractional P3 boundaries.

In the proposed P3 mode, `(0, 0, 10, 10)` would specify a 10 mm square. The same ten-pixel square drawn by the current API would require `(0, 0, 30, 30)` in that mode.

The proposed mapping would be optional, with destination-pixel units remaining the default.

A whole-surface operation such as an illustrative `fill(color:)` would stay unit-independent. Any bounds exposed in drawing units would reflect the scale, while discrete framebuffer bounds would remain in pixel indices. API names are undecided.

### Physical LED model

Treat the panel as a regular lattice of LED **centres** at its declared pitch, with each LED associated with a nominal pixel cell. In millimetre coordinates for a uniform pitch `p`, the centre of LED `(x, y)` is:

`((x + 0.5) * p, (y + 0.5) * p)`

The actual luminous element may occupy less than that cell, and optical characteristics can differ between panels. Geometry and coverage refer to the **nominal cells**, not the measured emitting area of individual LEDs. Physical display brightness and calibration are separate concerns.

## 4. Rectangle semantics

Both geometric and pixel rectangles are **half-open** on their maximum X and Y boundaries. Minimum boundaries are included; maximum boundaries are excluded.

In the default coordinate system:

- `DrawingRect(x: 0, y: 0, width: 10, height: 10)` fully covers pixels `(0, 0)` through `(9, 9)`.
- `DrawingRect(x: 0, y: 0, width: 1, height: 1)` fully covers only pixel `(0, 0)`.
- `PixelRect` describes the equivalent discrete pixel-index bounds.

Geometric rectangles can have fractional origins and dimensions. The rasteriser evaluates their boundaries directly in destination-pixel coordinates. Rectangles with nonpositive dimensions are empty, and rectangles touching only at an edge or corner have no area of intersection.

Converting framebuffer dimensions above 2²⁴ to `Float` can round the geometric bounds. This does not affect supported HUB75 panel sizes. The rasterisers enforce the integer storage bounds separately from the geometric calculation.

## 5. Coverage and antialiasing

### Coverage and compositing contract

A geometric shape is rasterised into **coverage**, the fraction of each nominal destination-pixel cell occupied by the shape in destination coordinates. Coverage is in `[0, 1]` and is independent of colour opacity.

For an axis-aligned rectangle, exact coverage is its intersection area with the pixel's unit square. These examples use destination-pixel units:

**Rectangle `(0.5, 0.5, 1, 1)`**

Pixels `(0, 0)`, `(1, 0)`, `(0, 1)` and `(1, 1)` each receive **25%** coverage.

**Rectangle `(0.25, 0.25, 1, 1)`**

| Pixel | Coverage |
| --- | ---: |
| `(0, 0)` | 56.25% |
| `(1, 0)` | 18.75% |
| `(0, 1)` | 18.75% |
| `(1, 1)` | 6.25% |

For a shape wholly within the destination, the sum of exact, unquantised pixel coverages equals its **area in destination-pixel-square units**. Approximation and 8-bit quantisation can change the rendered sum. Under the proposed millimetre mode, area in mm² would be divided by `p²` before comparison with pixel coverages.

Coverage combines with the source's opacity before compositing:

`effectiveAlpha = sourceAlpha * coverage`

### Current rasterisers

The meaning of the geometry does not depend on its rasterisation method. Possible implementations include:

- Exact analytical coverage for axis-aligned rectangles.
- Analytical area coverage for polygons and thick lines where worthwhile.
- Supersampling and filtering for curved or more complex shapes.

`fillRect(_:)` for `DrawingRect` calculates axis overlap and multiplies the horizontal and vertical fractions before quantising them to 8 bits. The `PixelRect` overload fills clipped integer rows. `fillAntialiasedQuad` accepts a finite, strictly convex perimeter in either winding. It identifies full-coverage runs and computes unit-cell intersection areas at the boundary. The current analogue face uses native circle and quadrilateral coverage. Supersampling was used by the earlier analogue renderer and remains a valid reference or alternative sampling technique. The separate binary `fillQuad` and `fillCircle` helpers sample at integer raster coordinates and paint whole pixels.

Production filled circles use Float refined-chord coverage below a radius of 24 pixels. At radius 24 and above they use tangent coverage, with refined chord for cells where the tangent geometry is ambiguous. A recorded host sweep covered 1,024 fractional centres on a 64×64 framebuffer. In that sweep, switching from refined chord at `24.nextDown` to tangent at `24` changed blue intensity by up to two levels out of 255 across at most 116 pixels per frame. These are sampled maxima. Visibility during radius animation on the panel remains unverified.

### Clipping, span painting and framebuffer writes

1. **Geometric drawing and rasterisation** accept coordinates that may extend outside the destination. They clip against destination bounds and calculate coverage as required. They pass only valid, preclipped spans to the painter. When clipping a variable-coverage span, the caller must keep the borrowed coverage values aligned with their destination columns.
2. **Span painting** applies the selected drawing colour and any supplied coverage. The legacy `SpanRasterTarget.paintSpan` and both `CoverageSpanRasterTarget.paintSpan` overloads receive preclipped spans and perform no geometric or framebuffer clipping. Out-of-bounds span coordinates violate the caller contract.
3. **Framebuffer writes** include `writeOpaqueSpan`, which overwrites a span with opaque pixels and ignores source alpha, and `writeBlendedSpan`, which composites a span using a constant effective alpha. Both require preclipped bounds and check the deadline once before writing. `setPixel` and `blendPixel` remain checked pixel-addressing operations.

For every span, callers must satisfy `0 <= y < contextSize.height` and the applicable column bounds.

| Operation | Column bounds |
| --- | --- |
| Legacy `paintSpan`, constant-coverage `paintSpan`, `writeOpaqueSpan`, and `writeBlendedSpan` | `0 <= from <= to <= contextSize.width` |
| Variable-coverage `paintSpan` | `from >= 0`, `from <= contextSize.width`, and `coverage.count <= contextSize.width - from` |

An explicit end column is exclusive. Equal start and end columns form a valid empty span. A borrowed coverage array supplies one coverage value per consecutive destination pixel, starting at `from`, and may be empty.

Quad and circle rasterisation clamp rounded coordinates to the actual integer framebuffer dimensions on both axes. Analytical rectangles also enforce integer bounds before painting their rows and spans. This keeps emitted addresses in bounds even when converting a framebuffer dimension to `Float` rounds it up. Geometric coverage at very large coordinates is still limited by `Float` precision.

### Drawing completion and deadlines

The fill and span operations described here return `true` when they complete without a deadline failure. An operation may do computational work and leave the framebuffer untouched. A successful result gives no assurance that time remains for the next operation. A return value of `false` means a deadline check failed and the operation could not continue.

Clipping and deadline checking are separate responsibilities. Obvious no-ops can return before reaching a deadline checkpoint. A valid empty span that reaches an RGB painter or a span writer may still check the deadline and return `false` on expiry without modifying the framebuffer. The variable-coverage painter checks the deadline before processing a nonempty coverage array with nonzero source alpha, even if every sample later yields zero effective alpha.

Deadline failure remains sticky. `AnalogueClockFace` draws directly into the borrowed framebuffer through `DrawingContext`, using native antialiased circles and quadrilaterals. Its deadline checks are cooperative. A row whose check has passed can finish writing after the driver changes framebuffer ownership. See [analogue framebuffer ownership](analogue-clock.md#framebuffer-ownership).

### Current span integration

Translucent `PixelRect` fills use `writeBlendedSpan` for each preclipped row, including short runs. The legacy RGB and constant-coverage `paintSpan` overloads also use it for partial effective alpha. These paths return early at zero alpha and use `writeOpaqueSpan` at full opacity. The writer checks the deadline once before writing and then completes the span. The measured 23.1% and 30.1% reductions apply only to the historical translucent `PixelRect` workloads below.

The temporary A/B settings, workloads and renderer dispatch have been removed. The normal render profiler and the compositing, clipping and deadline regression tests remain available.

### Historical constant-opacity span performance

#### RP2350 hardware results

The Pico 2 W ran Release firmware with normal HUB75 refresh. Each workload used an A/B/A sequence. A used the existing per-pixel loop for translucent `PixelRect` rows. B used `writeBlendedSpan`. Both used the same clipping, source alpha, and one deadline check per row before writing. The fixed workload replaced the clock face, cleared the same opaque background, and rendered through the normal HUB75 requests. The existing render profiler timed the whole `Renderer.render` call, including the clear and drawing overhead.

| Workload | A1 mean | B mean | A2 mean | Reduction in mean time |
| --- | ---: | ---: | ---: | ---: |
| Long runs (48 rows × 56 pixels) | 723 µs | 556 µs | 723 µs | 23.1% |
| Sparse runs (up to six pixels) | 389 µs | 272 µs | 389 µs | 30.1% |

All six runs completed with zero rejected renders, late starts or late completions. The experiment recorded 577 passing host tests, including checks for framebuffer equivalence and deadline behaviour. The table gives whole-render averages. Per-run maxima and request counts were not supplied for this record. Earlier isolated macOS measurements showed about 8% lower time for 64-pixel blends and no material change for the synthetic short-run mix. The Pico 2 W results apply to the firmware workloads above.

#### ARM Release code generation

The following counts come from disassembling the four saved Pico 2 W UF2 flash payloads as Thumb code. The retained SPARSE-B ELF matches its UF2 and identifies the renderer entry at `0x10005b78`. The other images were compared at the corresponding entry, cross-checked against the call sites and the adjacent main-function entry. Instruction counts cover the steady-state loop bodies, excluding tails, setup and deadline checks. They count decoded instructions rather than cycles.

| Workload | A loop | B loop | Linked renderer region, A → B |
| --- | --- | --- | --- |
| Long | 117 instructions in 392 bytes for four pixels, including six branches | 79 instructions in 266 bytes for four pixels, including one branch | 1,172 → 1,000 bytes |
| Sparse | 36 instructions in 108 bytes per pixel in the called rectangle helper, including eight branches | 87 instructions in 284 bytes for four pixels in the inlined renderer, including five branches, with separate short-run tails | 568 → 1,168 bytes |

- **Long runs.** Both variants inline compositing and unroll four pixels. The compiler folds source-alpha products and uses multiply/shift sequences for the constant divisor. A hoists the row base but still compares the column against the framebuffer width for each pixel and repeatedly reloads some constants via immediate instructions. B walks the destination with a pointer, groups three reads in an `ldmia`, and keeps more channel constants live across pixels. The hot loop has one stack reload in B and none in A. B's renderer reserves 44 local stack bytes versus A's 28, so the instruction savings do not imply less stack use overall.
- **Sparse runs.** A calls an out-of-line rectangle helper for each run. That helper calls the intersection routine, performs row and pixel checks, and has five stack-relative accesses in its per-pixel loop. B inlines clipping and painting in the renderer, eliminating those calls while retaining the timer call at the row checkpoint. Its loop keeps the blend constants mostly in registers and retains checked index addition. The larger B renderer body should be read alongside A's separate rectangle helper, which occupies about 700 bytes before counting the intersection routine. The four-pixel body alone does not describe the work performed by one- to three-pixel runs.
- **Likely contributors.** Fewer inner-loop instructions and branches explain the direction of the long-run result. Inlining, fewer coordinate checks and fewer hot-loop stack accesses are plausible contributors for the sparse workload. Both paths still read and write one framebuffer word per blended pixel. The linked code regions reside in the flash address range, and the changed size and placement can affect instruction fetch. The experiment did not measure XIP traffic or instruction-cache behavior, so it cannot assign any part of the speedup to those effects.

## 6. Line semantics

`strokeLine(from:to:)` takes two integer `PixelPoint` endpoints. It draws a one-pixel-wide raster line, includes both endpoints, and ignores off-screen pixels. Coincident endpoints draw one pixel when in bounds and the stroke has nonzero alpha, subject to the deadline check. The API has no width or cap parameter.

**Proposed geometric stroke.** A future stroke could take `DrawingPoint` endpoints and a `Float` width, with the stroke centred on its path. A square cap would extend half the width beyond each endpoint.

In destination-pixel units, a horizontal line from `(0.5, 0.5)` to `(9.5, 0.5)` at width `1` has a centreline length of **9 geometric units**. Under the proposed square-cap rule its stroke would cover `(0, 0, 10, 1)`, or ten complete pixels.

Coincident-endpoint semantics for a future geometric stroke remain undecided. The raster line's single-pixel rule is implemented and tested.

## 7. Supersampling and coordinate conversions

Production antialiased primitives already receive destination-pixel geometry. If context scaling is added, the conceptual path would be:

`input geometry → context transform → destination-pixel geometry → rasterisation / sampling → destination pixels`

A supersampling rasteriser with factor `S` scales the destination-pixel geometry by `S`. Arbitrary geometric points require no half-pixel offset.

The expression `(pixelIndex + 0.5) * S - 0.5` maps **pixel-centre indices** between raster grids of different resolutions. Apply it only when converting between these index conventions.

Clipping and surface boundaries must be defined against the destination's actual pixel grid. All rasterisation paths must honour the same geometric contract.

## 8. Colour, alpha and physical brightness

The renderer composites the stored 8-bit RGB channel values directly into an opaque framebuffer. It applies rounded source-over arithmetic using effective alpha from source opacity and coverage. This arithmetic treats channel values as linear quantities. The compositor does not decode a transfer function or establish calibrated linear-light colour. A linear-light interpretation depends on how the supplied channel values were encoded.

The pinned HUB75 driver processes the framebuffer separately. The clock requests a 240 Hz refresh target through a preset with gamma transfer (gamma 2.2), six displayed PWM bitplanes and four-phase temporal dithering. The driver distributes the low bits across four physical refreshes. These output settings do not establish measured physical light output at fractional coverage.

In particular, panels with different LED pitches may differ in luminous area and apparent brightness even when the nominal-cell geometry is correct. Such differences belong to display calibration and testing, **not** to the parameters of every drawing primitive.

## 9. Animation and validation

Continuous coordinates allow geometry to move by fractions of a pixel pitch. For example:

- Analogue clock hands can move smoothly between pixel centres.
- The digital clock advances its seconds-progress indicator clockwise around a dim display perimeter. Elapsed seconds and microseconds determine how many pixels are fully lit and how far the leading pixel has progressed. The renderer directly scales that pixel’s RGB values from the dim baseline (a scale of 64 out of 255) towards the full colour, with integer rounding down. It uses opaque pixel writes. This graduated transition gives the eye a smoother progression than an abrupt whole-LED step. The 8-bit channel values and subsequent output processing are separate from perceived or calibrated LED brightness.
- Fractional movement is also useful for scrolling graphics and icons when their rasterisation or placement supports it.

With the proposed millimetre coordinates, motion could be specified in physical units, such as `20 mm/s`. The application would calculate position from elapsed time and the context would convert it to destination-pixel coordinates. At 20 mm/s, this corresponds to approximately 6.67 pixels/s on P3 and 8 pixels/s on P2.5.

Validation should separate:

1. **Geometry:** exact coverage as the reference, with conservation of area for shapes wholly inside the raster before approximation and quantisation.
2. **Output:** colour, alpha, quantisation, gamma and dithering behaviour.
3. **Perception:** smooth motion, apparent brightness and possible pulsing on the real panels.

A useful controlled test is a 1×1 rectangle moving horizontally and diagonally in small fractional increments. Its exact summed coverage should remain constant while entirely inside the surface. Compare quantised results within their rounding limits. Visible pulsing is grounds for investigation, but is not by itself proof that the coverage mathematics is wrong; the LED lattice and visual system also matter.

## 10. Drawing context scope

The clock faces render through `DrawingContext`, which currently accepts an opaque `.bgrx8888` framebuffer. Text has pixel-aligned bitmap glyph support. A common drawing interface across other destination formats and rasterisers remains a design direction.

## 11. Remaining design questions

- **Physical coordinates.** How would the proposed uniform pitch scale interact with bounds and pixel-aligned text? The scope of general geometric transforms is undecided.
- **Geometric strokes.** What should a coincident-endpoint stroke draw, and which cap styles would be supported?
- **Image drawing.** Which image formats, placement rules and image-backed destinations would an extended context support?
