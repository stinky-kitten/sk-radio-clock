#!/usr/bin/env swift

import CoreGraphics
import CoreText
import Foundation

let fontName = "Liberation Sans Bold"
let fontSize: CGFloat = 22

let rasterPhaseX: CGFloat = 0.0
let rasterPhaseY: CGFloat = 0.0

let glyphScalars = Array("0123456789?".unicodeScalars)

let defaultOutputPath = "src/render/fonts/ClockFont.swift"

let rasterPadding = 2

struct RasterizedGlyph {
  let scalar: Unicode.Scalar

  let width: Int
  let height: Int
  let left: Int
  let top: Int
  let advance: Int

  let a8: [UInt8]
}

func makeFont() -> CTFont {
  let font = CTFontCreateWithName(
    fontName as CFString,
    fontSize,
    nil
  )

  let actualFamily = CTFontCopyFamilyName(font) as String

  let postScriptName = CTFontCopyPostScriptName(font) as String

  print("Requested font:  \(fontName)")
  print("Actual family:   \(actualFamily)")
  print("PostScript name: \(postScriptName)")
  print("Size:            \(fontSize)")

  guard postScriptName == "LiberationSans-Bold" else {
    fatalError(
      "CoreText selected '\(postScriptName)' for '\(fontName)' instead of 'LiberationSans-Bold'."
    )
  }

  return font
}

func makeClockColon() -> RasterizedGlyph {
  let width = 3
  let dotHeight = 3
  let gap = 4
  let height = dotHeight + gap + dotHeight

  var a8 = [UInt8](
    repeating: 0,
    count: width * height
  )

  for y in 0..<dotHeight {
    for x in 0..<width {
      a8[y * width + x] = 255
    }
  }

  let lowerDotY = dotHeight + gap

  for y in lowerDotY..<height {
    for x in 0..<width {
      a8[y * width + x] = 255
    }
  }

  return RasterizedGlyph(
    scalar: Unicode.Scalar(0xA789)!,
    width: width,
    height: height,
    left: 2,
    top: -12,
    advance: 7,
    a8: a8
  )
}

func glyphForScalar(
  _ scalar: Unicode.Scalar,
  font: CTFont
) -> CGGlyph {
  guard scalar.value <= UInt16.max else {
    fatalError(
      "ClockFont generator currently supports BMP scalars only"
    )
  }

  var character = UniChar(scalar.value)
  var glyph: CGGlyph = 0

  guard
    CTFontGetGlyphsForCharacters(
      font,
      &character,
      &glyph,
      1
    )
  else {
    fatalError(
      String(
        format: "No glyph for U+%04X",
        scalar.value
      )
    )
  }

  return glyph
}

func advanceForGlyph(
  _ glyph: CGGlyph,
  font: CTFont
) -> Int {
  var glyph = glyph
  var advanceSize = CGSize.zero

  CTFontGetAdvancesForGlyphs(
    font,
    .default,
    &glyph,
    &advanceSize,
    1
  )

  return Int(
    advanceSize.width.rounded()
  )
}

func designBoundsForGlyph(
  _ glyph: CGGlyph,
  font: CTFont
) -> CGRect {
  var glyph = glyph
  var bounds = CGRect.zero

  CTFontGetBoundingRectsForGlyphs(
    font,
    .default,
    &glyph,
    &bounds,
    1
  )

  return bounds
}

func cropRenderedPixels(
  _ pixels: [UInt8],
  canvasWidth: Int,
  canvasHeight: Int,
  canvasLeft: Int,
  canvasTop: Int,
  scalar: Unicode.Scalar,
  advance: Int
) -> RasterizedGlyph {
  var minX = canvasWidth
  var minY = canvasHeight
  var maxX = -1
  var maxY = -1

  for y in 0..<canvasHeight {
    for x in 0..<canvasWidth {
      let coverage =
        pixels[y * canvasWidth + x]

      guard coverage != 0 else {
        continue
      }

      minX = min(minX, x)
      minY = min(minY, y)
      maxX = max(maxX, x)
      maxY = max(maxY, y)
    }
  }

  // Space and any other no-ink glyph.
  guard maxX >= minX, maxY >= minY else {
    return RasterizedGlyph(
      scalar: scalar,
      width: 0,
      height: 0,
      left: 0,
      top: 0,
      advance: advance,
      a8: []
    )
  }

  let width =
    maxX - minX + 1

  let height =
    maxY - minY + 1

  var cropped = [UInt8](
    repeating: 0,
    count: width * height
  )

  for y in 0..<height {
    for x in 0..<width {
      cropped[y * width + x] =
        pixels[
          (minY + y) * canvasWidth
            + minX
            + x
        ]
    }
  }

  // Horizontal coordinates grow in the same direction in the
  // CGContext and our framebuffer.
  let left =
    canvasLeft + minX

  // Bitmap row zero is the top row.
  //
  // canvasTop is the distance, in pixels, from the top of the
  // temporary bitmap to the baseline.
  //
  // Therefore a glyph whose first ink row is five pixels above
  // the baseline gets top == -5.
  let top =
    minY - canvasTop

  return RasterizedGlyph(
    scalar: scalar,
    width: width,
    height: height,
    left: left,
    top: top,
    advance: advance,
    a8: cropped
  )
}

func rasterize(
  scalar: Unicode.Scalar,
  font: CTFont
) -> RasterizedGlyph {
  let glyph =
    glyphForScalar(
      scalar,
      font: font
    )

  let advance =
    advanceForGlyph(
      glyph,
      font: font
    )

  let bounds =
    designBoundsForGlyph(
      glyph,
      font: font
    )

  // Spaces and other glyphs with no outline still have an advance.
  guard !bounds.isEmpty else {
    return RasterizedGlyph(
      scalar: scalar,
      width: 0,
      height: 0,
      left: 0,
      top: 0,
      advance: advance,
      a8: []
    )
  }

  // These bounds only size our temporary rendering surface.
  // They are NOT used as the final glyph bitmap bounds.
  //
  // CoreText gets a little room on every side, then we crop the
  // pixels it actually produced.
  let canvasLeft =
    Int(floor(bounds.minX))
    - rasterPadding

  let canvasRight =
    Int(ceil(bounds.maxX))
    + rasterPadding

  let canvasBottom =
    Int(floor(bounds.minY))
    - rasterPadding

  let canvasTop =
    Int(ceil(bounds.maxY))
    + rasterPadding

  let canvasWidth =
    max(
      1,
      canvasRight - canvasLeft
    )

  let canvasHeight =
    max(
      1,
      canvasTop - canvasBottom
    )

  // Put the glyph origin/baseline exactly on integer pixel
  // coordinates in the temporary bitmap.
  let baselineX =
    -canvasLeft

  let baselineY =
    -canvasBottom

  var pixels = [UInt8](
    repeating: 0,
    count: canvasWidth * canvasHeight
  )

  pixels.withUnsafeMutableBytes { storage in
    guard let baseAddress = storage.baseAddress else {
      fatalError(
        "Unable to obtain bitmap storage"
      )
    }

    guard
      let context = CGContext(
        data: baseAddress,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: canvasWidth,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else {
      fatalError(
        "Unable to create grayscale CGContext"
      )
    }

    // Use grayscale antialiasing and permit fractional glyph positioning
    // so raster phase can be tuned for the physical HUB75 pixel grid.
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    context.setAllowsFontSubpixelPositioning(true)
    context.setShouldSubpixelPositionFonts(true)

    context.setAllowsFontSubpixelQuantization(false)
    context.setShouldSubpixelQuantizeFonts(false)

    // Font smoothing is distinct from antialiasing. We don't want
    // LCD-style/screen-oriented smoothing baked into our A8 coverage.
    context.setAllowsFontSmoothing(false)
    context.setShouldSmoothFonts(false)

    context.setFillColor(
      CGColor(
        gray: 1,
        alpha: 1
      )
    )

    var glyphToDraw = glyph

    var position = CGPoint(
      x: CGFloat(baselineX) + rasterPhaseX,
      y: CGFloat(baselineY) + rasterPhaseY
    )

    CTFontDrawGlyphs(
      font,
      &glyphToDraw,
      &position,
      1,
      context
    )
  }

  return cropRenderedPixels(
    pixels,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    canvasLeft: canvasLeft,
    canvasTop: canvasTop,
    scalar: scalar,
    advance: advance
  )
}

func appendLine(
  _ line: String = "",
  to output: inout String
) {
  output += line
  output += "\n"
}

func swiftSource(
  glyphs: [RasterizedGlyph],
  font: CTFont
) -> String {
  let ascent =
    Int(
      ceil(
        CTFontGetAscent(font)
      )
    )

  let descent =
    Int(
      ceil(
        CTFontGetDescent(font)
      )
    )

  let lineHeight =
    ascent + descent

  var bitmap: [UInt8] = []
  var offsets: [Int] = []

  for glyph in glyphs {
    offsets.append(
      bitmap.count
    )

    bitmap.append(
      contentsOf: glyph.a8
    )
  }

  var output = ""

  appendLine("//", to: &output)
  appendLine("//  ClockFont.swift", to: &output)
  appendLine("//  sk-radio-clock", to: &output)
  appendLine("//", to: &output)

  appendLine(
    "//  Generated by tools/generate_clock_font.swift.",
    to: &output
  )

  appendLine(
    "//  Do not edit by hand.",
    to: &output
  )
  appendLine(
    "//  Liberation-derived glyph data: SIL OFL 1.1; see LICENSES/Liberation-OFL-1.1.txt.",
    to: &output
  )

  appendLine("//", to: &output)

  appendLine(
    "//  Font: \(fontName)",
    to: &output
  )

  appendLine(
    "//  Size: \(fontSize) px",
    to: &output
  )

  appendLine(
    "//  Rasterizer: CTFontDrawGlyphs",
    to: &output
  )

  appendLine("//", to: &output)
  appendLine(to: &output)

  appendLine(
    "enum ClockFont: Font {",
    to: &output
  )

  appendLine(
    "    static let ascent = \(ascent)",
    to: &output
  )

  appendLine(
    "    static let descent = \(descent)",
    to: &output
  )

  appendLine(
    "    static let lineHeight = \(lineHeight)",
    to: &output
  )

  appendLine(to: &output)

  appendLine(
    "    static func glyph(",
    to: &output
  )

  appendLine(
    "        for scalar: Unicode.Scalar",
    to: &output
  )

  appendLine(
    "    ) -> Glyph<ClockFont>? {",
    to: &output
  )

  appendLine(
    "        switch scalar.value {",
    to: &output
  )

  for index in glyphs.indices {
    appendLine(
      String(
        format: "        case 0x%04X: return glyphs[%d]",
        glyphs[index].scalar.value,
        index
      ),
      to: &output
    )
  }

  appendLine(
    "        default: return nil",
    to: &output
  )

  appendLine(
    "        }",
    to: &output
  )

  appendLine(
    "    }",
    to: &output
  )

  appendLine(to: &output)

  appendLine(
    "    static let bitmap: InlineArray<\(bitmap.count), UInt8> = [",
    to: &output
  )

  for start in stride(
    from: 0,
    to: bitmap.count,
    by: 16
  ) {
    let end =
      min(
        start + 16,
        bitmap.count
      )

    var line = "        "

    for index in start..<end {
      line += String(
        format: "%3d",
        bitmap[index]
      )

      if index != bitmap.count - 1 {
        line += ", "
      }
    }

    appendLine(
      line,
      to: &output
    )
  }

  appendLine(
    "    ]",
    to: &output
  )

  appendLine(to: &output)

  appendLine(
    "    static let glyphs: InlineArray<\(glyphs.count), Glyph<ClockFont>> = [",
    to: &output
  )

  for index in glyphs.indices {
    let glyph =
      glyphs[index]

    let comma =
      index == glyphs.count - 1
      ? ""
      : ","

    appendLine(
      "        Glyph(",
      to: &output
    )

    appendLine(
      "            bitmapOffset: \(offsets[index]),",
      to: &output
    )

    appendLine(
      "            width: \(glyph.width),",
      to: &output
    )

    appendLine(
      "            height: \(glyph.height),",
      to: &output
    )

    appendLine(
      "            left: \(glyph.left),",
      to: &output
    )

    appendLine(
      "            top: \(glyph.top),",
      to: &output
    )

    appendLine(
      "            advance: \(glyph.advance)",
      to: &output
    )

    appendLine(
      "        )\(comma)",
      to: &output
    )
  }

  appendLine(
    "    ]",
    to: &output
  )

  appendLine(to: &output)

  appendLine(
    """
        static func withCoverage<Result>(
            for glyph: Glyph<Self>,
            _ body: (Span<UInt8>) -> Result
        ) -> Result {
            let start = glyph.bitmapOffset
            let count = glyph.width * glyph.height

            return body(
                bitmap.span.extracting(start..<(start + count))
            )
        }
    """,
    to: &output
  )

  appendLine(
    "}",
    to: &output
  )

  return output
}

func outputPath() -> String {
  if CommandLine.arguments.count > 1 {
    return CommandLine.arguments[1]
  }

  return defaultOutputPath
}

let font = makeFont()

var glyphs: [RasterizedGlyph] = []

for scalar in glyphScalars {
  glyphs.append(
    rasterize(
      scalar: scalar,
      font: font
    )
  )
}

glyphs.append(
  makeClockColon()
)

let source =
  swiftSource(
    glyphs: glyphs,
    font: font
  )

let destination =
  outputPath()

let outputURL =
  URL(
    fileURLWithPath: destination
  )

try FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)

try source.write(
  to: outputURL,
  atomically: true,
  encoding: .utf8
)

let bitmapBytes =
  glyphs.reduce(0) {
    $0 + $1.a8.count
  }

print()
print("Generated \(glyphs.count) glyphs")
print("A8 bitmap data: \(bitmapBytes) bytes")
print("Output: \(destination)")
