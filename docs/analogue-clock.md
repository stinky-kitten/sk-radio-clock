# Analogue clock face

The analogue face works with both time sources. The default Pico 2 W setup uses Wi-Fi/NTP, starts on the analogue face and uses the optional GP28 button to switch between analogue and digital. With the optional MSF receiver configured, the clock starts on the analytical face and the button cycles through analytical, analogue and digital. `ClockFaceKind` defines this order and `ClockFaceInstance` constructs the selected face with the current configuration and panel size. Each face retains its own concrete theme values for `ClockThemeKind.standard`.

## Rendering architecture

`ClockFace.render(into:displaySnapshot:)` accepts `inout DrawingContext` and returns a completion Boolean. `Renderer` constructs the context with the borrowed buffer and request deadline. Initialization rejects nonpositive dimensions and insufficient capacity; extra capacity is accepted, but drawing addresses only the declared surface. The context does not allocate or own the framebuffer and must not outlive the driver's borrowing period. Renderer success requires both face completion and an active context status.

`canContinue` reads status without sampling time. `checkDeadline()` samples the optional absolute deadline and latches failure at equality or later; once failed, subsequent checks return false without further clock reads. With no deadline, the context remains active. Spans, strokes and glyphs check before rasterization; their pixel helpers inspect status without sampling time. Composite fills can cancel between row spans, and text can cancel between glyphs. This is cooperative cancellation, not continuous time monitoring or a hard framebuffer-ownership gate.

Both time sources use the same native renderer. The analogue face redraws the 64×64 XRGB8888 image directly into the borrowed buffer. It clears to black, draws the grey bezel and white dial using `fillAntialiasedCircle`, and adds the twelve grey markers using `fillAntialiasedQuad`. It then paints the available hour, minute and seconds hands in that order using radial rectangles. The black centre boss covers the base of the hands whenever at least one hand is present.

The dial is drawn even before time is available. In MSF mode, the renderer paints the pixel-aligned signal indicator last, including during acquisition. Bright green for HIGH and dark green for LOW follow the physical receiver input, so the flashing reflects the signal itself. In NTP mode the renderer skips the indicator entirely.

Native geometry uses unit pixel cells, with the panel centre at (32, 32) in drawing coordinates. This is the same physical point as (31.5, 31.5) in the integer-pixel-centre convention used by the previous supersampled renderer. Hand vertices remain fractional. The hour hand has length 16 and width 4, the minute hand length 23 and width 2.5, and the seconds hand length 26 and width 1 in output pixels. The boss radius is 2.5, the bezel radius is 31.5, and the white dial radius is 30.

The native primitives quantise coverage and composite each shape in layer order. Antialiased edges and overlapping shapes can differ from the earlier renderer, which selected the topmost colour per supersample and averaged the samples once.

## Time and movement

The analogue renderer derives all hand angles from the supplied `ClockSnapshot` on each frame. There is no independent animation clock or accumulated animation state. `hasSecondTiming` controls whether the renderer uses seconds and their fractional phase.

For fractional seconds `s`, the clockwise hand angles from twelve are:

```text
second = s × 2π / 60
minute = (minute + s / 60) × 2π / 60
hour   = (hour % 12 + (minute + s / 60) / 60) × 2π / 12
```

Geometry is evaluated once per frame, with one sine/cosine pair per visible hand. Each hand renders independently according to the snapshot's time availability. A provisional minute uses second interpolation only when second timing is available. A known hour uses minute interpolation only when the minute is known. Unknown minute placeholders never contribute, even when seconds are available. Without finer information, provisional hands stay on their corresponding hour or minute marks.

### Wi-Fi/NTP

Main reads the synchronised UTC instant from the Pico's always-on timer via `WiFiService.currentUTC()`. It constructs a `ClockSnapshot` in the configured time zone, converting the instant's nanoseconds to `subsecondMicroseconds`. A successful snapshot has acquired time and second timing, so all three hands use the shared interpolation. If the timer has no valid reading or the conversion fails, Main supplies `.unknown` and the face shows the dial without hands.

### MSF acquisition and holdover

Main prefers `MSFClockModel.currentSnapshot(at:)`, then the acquisition snapshot, then `.unknown`. Before the model accepts a time estimate, `MSFClockAcquisition.currentSnapshot(at:)` projects every retained hypothesis and exposes candidate hours and minutes only where all hypotheses agree. Disagreement, empty or overflowed hypotheses and uncertain hour carries can leave fields unknown. This view neither promotes acquisition nor creates radio evidence.

The scanner exposes the start time of a validated minute marker as immutable snapshot metadata. It becomes available on the marker's validated falling edge, without waiting for a completed calendar frame. Second-start phase alone does not enable the red hand. If the selected clock snapshot lacks second timing, the display merge projects seconds and fractions from the scanner's minute marker. A scanner reset drops that fallback. Established clock-model timing takes precedence and continues through holdover.

In MSF mode, `sampleTime` preserves the exact monotonic capture time used for clock movement. The trace and history use a separate `timestamp` quantised to 20 ms. The sweep therefore uses finer timing than the trace. In an acquired model snapshot, `subsecondMicroseconds = (now - anchorMarkerTime) % 1_000_000`. Whole seconds, minute progression and fractional phase share the same model anchor, including after resynchronisation. The model follows the ordinary 60-second minute grid and retains the last known GMT/BST state through signal loss.

Once the MSF model accepts a calendar estimate with a monotonic anchor, each snapshot it produces sets `hasAcquiredTime` and `hasSecondTiming`. `hasHour` and `hasMinute` then remain true even when radio evidence falls to `.unknown`. A supported partial handoff establishes the same availability as acquisition from a confirmed frame, without making all fields confirmed. During holdover, the analogue hands keep moving from the projected time while the analytical face reports the ageing evidence through `clockState`.

Before acquisition, individual hands can appear or disappear as provisional fields gain or lose agreement or minute-marker timing becomes available or is invalidated. Scanner recovery or reset affects the scanner's timing and does not clear the foreground model's accepted estimate. Valid incoming frames can corroborate or replace the model anchor. If the model cannot provide a snapshot, Main uses the acquisition or unknown fallback described above.

## Framebuffer ownership

The driver owns the framebuffer and can rotate buffers at the absolute request deadline without a completion acknowledgement. The analogue renderer now uses the same cooperative deadline checks as the other faces. A rejected row stops the remaining work, while a row whose check already passed can finish writing after the deadline. Cancellation can leave earlier layers, or only part of the background clear, in the buffer. With the previous private composition and 100 µs guarded row-copy reserve removed, a late row can overlap the driver's ownership transition. A host deadline test verifies cancellation at checkpoints and cannot establish that a firmware row finishes before the hardware deadline.

## Memory and verification

The previous renderer allocated a 16 KiB cached dial and a 64 KiB indexed overlay in C BSS. Both allocations are gone, saving 80 KiB of static working storage. Like-for-like Pico 2 and Pico 2 W Release builds with Wi-Fi disabled both show BSS decreasing from 93,120 to 11,200 bytes. The renderer uses one 64-byte coverage row instead of the former 256-byte RGB composition row. These are buffer sizes. The total stack frame also includes the primitive call frames, and the HUB75 driver's buffers are independent of the face.

Host tests cover hand interpolation and availability, marker and boss placement, layer order, indicator behaviour, framebuffer canaries, and deadline cancellation during both the background clear and bezel drawing. Native-resolution render time and deadline slack on a physical panel remain unmeasured.

## Generate current previews

This host test exports eight 64×64 PNGs using the current production `AnalogueClockFace` with synthetic MSF-configured snapshots. Use a separate output directory to keep the generated files apart from the archived gallery below.

```sh
SK_ANALOGUE_PREVIEW_DIRECTORY=/absolute/output/directory swift test --filter analoguePreviews
```

### Archived supersampled previews

These eight 64×64 PNGs document the earlier supersampled renderer and are retained for historical comparison. The first row shows fully available time. The second shows independent MSF acquisition states with a bright raw signal indicator.

| 12:00:00 | 03:15:30 | 10:10:08.5 | 11:59:59.5 |
| --- | --- | --- | --- |
| ![Noon](images/analogue-120000.png) | ![Quarter past three](images/analogue-031530.png) | ![Ten past ten](images/analogue-101008-5.png) | ![Before noon](images/analogue-115959-5.png) |

| No time information | Second timing only | Minute and second known | Hour and second known |
| --- | --- | --- | --- |
| ![Unknown time](images/analogue-unknown.png) | ![Second only](images/analogue-seconds-only.png) | ![Hour unknown](images/analogue-minute-only.png) | ![Minute unknown](images/analogue-hour-only.png) |
