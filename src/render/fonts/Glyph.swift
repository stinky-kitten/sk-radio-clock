//
//  Glyph.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-09.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct Glyph<Owner: Font> {
  let bitmapOffset: Int

  let width: Int
  let height: Int

  // Offset from the pen position to the glyph bitmap origin.
  let left: Int
  let top: Int

  let advance: Int
}
