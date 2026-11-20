//
//  CalendarDateTimeComponents+Formatting.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-11-02.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

extension CalendarDateTimeComponents {

  var shortDayOfWeek: StaticString? {
    switch dayOfWeek {
    case 0: return "Sun"
    case 1: return "Mon"
    case 2: return "Tue"
    case 3: return "Wed"
    case 4: return "Thu"
    case 5: return "Fri"
    case 6: return "Sat"
    default: return nil
    }
  }

  var longDayOfWeek: StaticString? {
    switch dayOfWeek {
    case 0: return "Sunday"
    case 1: return "Monday"
    case 2: return "Tuesday"
    case 3: return "Wednesday"
    case 4: return "Thursday"
    case 5: return "Friday"
    case 6: return "Saturday"
    default: return nil
    }
  }

  var shortDayOfMonth: String? {
    guard let dayOfMonth else { return nil }
    return String(dayOfMonth)
  }

  var longDayOfMonth: String? {
    guard let dayOfMonth else { return nil }
    return dayOfMonth < 10 ? "0" + String(dayOfMonth) : String(dayOfMonth)
  }

  var shortMonth: StaticString? {
    switch month {
    case 1: return "Jan"
    case 2: return "Feb"
    case 3: return "Mar"
    case 4: return "Apr"
    case 5: return "May"
    case 6: return "June"
    case 7: return "July"
    case 8: return "Aug"
    case 9: return "Sept"
    case 10: return "Oct"
    case 11: return "Nov"
    case 12: return "Dec"
    default: return nil
    }
  }

  var shortYear: String? {
    guard let year else { return nil }
    let shortYear = year % 100
    return String(shortYear)
  }

  var longYear: String? {
    guard let year else { return nil }
    return String(year)
  }

  var hour24hour: String? {
    guard let hour else { return nil }
    return hour < 10 ? "0" + String(hour) : String(hour)
  }

  var short12Hour: String? {
    guard let hour else { return nil }
    let hour12 = hour % 12
    return String(hour12)
  }

  var long12Hour: String? {
    guard let hour else { return nil }
    let hour12 = hour % 12
    return hour12 < 10 ? "0" + String(hour12) : String(hour12)
  }

  var shortMinute: String? {
    guard let minute else { return nil }
    return String(minute)
  }

  var longMinute: String? {
    guard let minute else { return nil }
    return minute < 10 ? "0" + String(minute) : String(minute)
  }

  var amPm: StaticString? {
    guard let hour else { return nil }
    return hour < 12 ? "AM" : "PM"
  }
}
