import Testing

@testable import RadioClockLogic

@Test("Optional zones remain distinct and advancement retains them", arguments: [Optional<TimeZone>.none, .gmt, .bst])
func optionalCalendarZones(_ zone: TimeZone?) throws {
  let calendar = CalendarDateTimeComponents(
    year: 2026, month: 10, dayOfMonth: 25, dayOfWeek: 0,
    hour: 1, minute: 59, second: 12, timeZone: zone)
  let next = try #require(calendar.advanced(byMinutes: 1))
  #expect(next.timeZone == zone)
  #expect(next.dayOfMonth == 25 && next.hour == 2 && next.minute == 0)
  #expect(calendar.settingTimeZone(nil) != calendar.settingTimeZone(.gmt))
  #expect(calendar.settingTimeZone(.gmt) != calendar.settingTimeZone(.bst))
  #expect(TimeZone.gmt.secondsFromGMT == 0)
  #expect(TimeZone.bst.secondsFromGMT == 3600)
  #expect(TimeZone.gmt.abbreviation.description == "GMT")
  #expect(TimeZone.bst.abbreviation.description == "BST")
}

@Test("Incomplete calendars cannot advance or fabricate expected parity", arguments: 0..<6)
func optionalCalendarFields(_ missing: Int) {
  var fields: [Int?] = [2026, 10, 29, 4, 12, 20]
  fields[missing] = nil
  let calendar = CalendarDateTimeComponents(
    year: fields[0], month: fields[1], dayOfMonth: fields[2],
    dayOfWeek: fields[3], hour: fields[4], minute: fields[5], second: nil, timeZone: nil)
  #expect(calendar.advanced(byMinutes: 1) == nil)
  let expected = MSFExpectedFrame(calendarDateTime: calendar)
  let field: MSFField = [.year, .month, .dayOfMonth, .dayOfWeek, .hour, .minute][missing]
  for position in field.positions { #expect(expected.bit(at: position, channel: .a) == nil) }
  let parity = [54, 55, 55, 56, 57, 57][missing]
  #expect(expected.bit(at: parity, channel: .b) == nil)
  #expect(expected.bit(at: 58, channel: .b) == nil)
}
