//
//  GeometryTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test(
  "Pixel rectangles use origin plus dimensions as exclusive upper bounds",
  arguments: [
    (PixelRect(x: 2, y: 3, width: 4, height: 5), 2, 3, 6, 8),
    (PixelRect(x: -3, y: -2, width: 4, height: 3), -3, -2, 1, 1),
    (PixelRect(x: 0, y: 0, width: 1, height: 1), 0, 0, 1, 1),
    (PixelRect.zero, 0, 0, 0, 0),
  ])
func pixelRectangleBounds(_ rect: PixelRect, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
  #expect(rect.minX == left && rect.minY == top)
  #expect(rect.maxX == right && rect.maxY == bottom)
  #expect(rect.width == right - left && rect.height == bottom - top)
  #expect(rect == PixelRect(origin: PixelPoint(x: left, y: top), size: rect.size))
}

@Test(
  "Pixel rectangles with either zero dimension are empty",
  arguments: [
    (PixelRect.zero, true), (PixelRect(x: 3, y: 2, width: 0, height: 4), true),
    (PixelRect(x: 3, y: 2, width: 4, height: 0), true),
    (PixelRect(x: -2, y: -2, width: 1, height: 1), false),
    (PixelRect(x: 0, y: 0, width: 64, height: 64), false),
  ])
func pixelRectangleEmptiness(_ rect: PixelRect, _ empty: Bool) {
  #expect(rect.isEmpty == empty)
}

@Test(
  "Pixel rectangle intersections contain only positive-area shared pixels",
  arguments: [
    ("identical", PixelRect(x: 1, y: 1, width: 4, height: 3), Optional(PixelRect(x: 1, y: 1, width: 4, height: 3))),
    ("contained", PixelRect(x: 2, y: 2, width: 1, height: 1), PixelRect(x: 2, y: 2, width: 1, height: 1)),
    ("containing", PixelRect(x: -1, y: -1, width: 8, height: 8), PixelRect(x: 1, y: 1, width: 4, height: 3)),
    ("left", PixelRect(x: 0, y: 2, width: 3, height: 3), PixelRect(x: 1, y: 2, width: 2, height: 2)),
    ("right", PixelRect(x: 4, y: 0, width: 3, height: 3), PixelRect(x: 4, y: 1, width: 1, height: 2)),
    ("top", PixelRect(x: 2, y: 0, width: 2, height: 2), PixelRect(x: 2, y: 1, width: 2, height: 1)),
    ("bottom", PixelRect(x: 2, y: 3, width: 2, height: 3), PixelRect(x: 2, y: 3, width: 2, height: 1)),
    ("touch left", PixelRect(x: 0, y: 1, width: 1, height: 3), nil),
    ("touch right", PixelRect(x: 5, y: 1, width: 1, height: 3), nil),
    ("touch top", PixelRect(x: 1, y: 0, width: 4, height: 1), nil),
    ("touch bottom", PixelRect(x: 1, y: 4, width: 4, height: 1), nil),
    ("touch corner", PixelRect(x: 5, y: 4, width: 1, height: 1), nil),
    ("disjoint", PixelRect(x: 6, y: 6, width: 1, height: 1), nil),
    ("zero width", PixelRect(x: 2, y: 2, width: 0, height: 1), nil),
    ("zero height", PixelRect(x: 2, y: 2, width: 1, height: 0), nil),
    ("empty", PixelRect.zero, nil),
  ] as [(String, PixelRect, PixelRect?)])
func pixelRectangleIntersection(_ name: String, _ other: PixelRect, _ expected: PixelRect?) {
  let rect = PixelRect(x: 1, y: 1, width: 4, height: 3)
  #expect(rect.intersection(other) == expected)
  #expect(other.intersection(rect) == expected)
}

@Test(
  "Pixel rectangle insets move the origin and shrink both edges",
  arguments: [
    (0, 0, PixelRect(x: 2, y: 3, width: 8, height: 6)),
    (1, 2, PixelRect(x: 3, y: 5, width: 6, height: 2)),
    (4, 3, PixelRect(x: 6, y: 6, width: 0, height: 0)),
    (-1, -2, PixelRect(x: 1, y: 1, width: 10, height: 10)),
  ])
func pixelRectangleInset(_ dx: Int, _ dy: Int, _ expected: PixelRect) {
  #expect(PixelRect(x: 2, y: 3, width: 8, height: 6).insetBy(dx: dx, dy: dy) == expected)
}
