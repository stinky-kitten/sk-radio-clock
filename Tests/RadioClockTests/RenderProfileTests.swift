//
//  RenderProfileTests.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-14.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

import Testing

@testable import RadioClockLogic

@Test("Render profile starts with zero counters, durations, slack and average")
func renderProfileInitialState() {
  let statistics = RenderProfile().statistics
  #expect(statistics.received == 0)
  #expect(statistics.samples == 0)
  #expect(statistics.completed == 0)
  #expect(statistics.rejected == 0)
  #expect(statistics.durationLatestUs == 0)
  #expect(statistics.durationMinUs == 0)
  #expect(statistics.durationMaxUs == 0)
  #expect(statistics.durationTotalUs == 0)
  #expect(statistics.durationAverageUs == 0)
  #expect(statistics.slackLatestUs == 0)
  #expect(statistics.slackMinUs == 0)
  #expect(statistics.slackMaxUs == 0)
  #expect(statistics.lateStarts == 0)
  #expect(statistics.completedLate == 0)
}

@Test("Receipt counts consumed requests independently of rendering", arguments: [0, 1, 4])
func renderProfileReceivedRequests(_ count: Int) {
  var profile = RenderProfile()
  for _ in 0..<count { profile.recordReceived() }
  #expect(profile.statistics.received == UInt64(count))
  #expect(profile.statistics.samples == 0)
  #expect(profile.statistics.completed == 0)
  #expect(profile.statistics.rejected == 0)
}

@Test("Each render records exactly one sample and one completion or rejection", arguments: [false, true])
func renderProfileClassification(_ completed: Bool) {
  var profile = RenderProfile()
  profile.recordReceived()
  profile.recordRender(startedAt: 100, finishedAt: 150, deadline: 300, completed: completed)
  #expect(profile.statistics.received == 1)
  #expect(profile.statistics.samples == 1)
  #expect(profile.statistics.completed == (completed ? 1 : 0))
  #expect(profile.statistics.rejected == (completed ? 0 : 1))
}

@Test("Recording a render does not implicitly count receipt")
func renderProfileReceiptIsExplicit() {
  var profile = RenderProfile()
  profile.recordRender(startedAt: 100, finishedAt: 150, deadline: 300, completed: true)
  #expect(profile.statistics.received == 0)
  #expect(profile.statistics.samples == 1)
}

@Test(
  "First duration initializes extrema including zero, large and wrapping durations",
  arguments: [
    ProfileDurationCase(start: 100, finish: 100, duration: 0),
    ProfileDurationCase(start: 100, finish: 150, duration: 50),
    ProfileDurationCase(start: 1, finish: 5_000_000_001, duration: 5_000_000_000),
    ProfileDurationCase(start: 0xffff_ffff_ffff_fffa, finish: 4, duration: 10),
    ProfileDurationCase(start: 5, finish: 4, duration: 0xffff_ffff_ffff_ffff),
  ])
private func renderProfileFirstDuration(_ fixture: ProfileDurationCase) {
  var profile = RenderProfile()
  profile.recordRender(
    startedAt: fixture.start, finishedAt: fixture.finish,
    deadline: UInt64.max, completed: true)
  let statistics = profile.statistics
  #expect(statistics.samples == 1)
  #expect(statistics.durationLatestUs == fixture.duration)
  #expect(statistics.durationMinUs == fixture.duration)
  #expect(statistics.durationMaxUs == fixture.duration)
  #expect(statistics.durationTotalUs == fixture.duration)
  #expect(statistics.durationAverageUs == fixture.duration)
}

@Test("Archived timing observations accumulate current completed and rejected statistics")
func renderProfileArchivedObservations() {
  // The four timestamps come from the archived C test; abandonment is now rejection.
  let observations: [ProfileObservation] = [
    ProfileObservation(start: 100, finish: 150, deadline: 300, completed: true),
    ProfileObservation(start: 200, finish: 310, deadline: 300, completed: true),
    ProfileObservation(start: 400, finish: 440, deadline: 350, completed: false),
    ProfileObservation(start: 500, finish: 500, deadline: 500, completed: false),
  ]
  var profile = RenderProfile()
  for observation in observations {
    profile.recordReceived()
    profile.recordRender(
      startedAt: observation.start, finishedAt: observation.finish,
      deadline: observation.deadline, completed: observation.completed)
  }
  let statistics = profile.statistics
  #expect(statistics.received == 4)
  #expect(statistics.samples == 4)
  #expect(statistics.completed == 2)
  #expect(statistics.rejected == 2)
  #expect(statistics.durationLatestUs == 0)
  #expect(statistics.durationMinUs == 0)
  #expect(statistics.durationMaxUs == 110)
  #expect(statistics.durationTotalUs == 200)
  #expect(statistics.durationAverageUs == 50)
  #expect(statistics.slackLatestUs == 0)
  #expect(statistics.slackMinUs == -50)
  #expect(statistics.slackMaxUs == 200)
  #expect(statistics.lateStarts == 2)
  #expect(statistics.completedLate == 1)
}

@Test("Later positive durations can lower minimum or raise maximum without resetting either")
func renderProfileDurationExtrema() {
  var profile = RenderProfile()
  profile.recordRender(startedAt: 100, finishedAt: 150, deadline: 300, completed: true)
  profile.recordRender(startedAt: 200, finishedAt: 220, deadline: 300, completed: true)
  #expect(profile.statistics.durationLatestUs == 20)
  #expect(profile.statistics.durationMinUs == 20)
  #expect(profile.statistics.durationMaxUs == 50)
  profile.recordRender(startedAt: 300, finishedAt: 410, deadline: 500, completed: true)
  #expect(profile.statistics.durationLatestUs == 110)
  #expect(profile.statistics.durationMinUs == 20)
  #expect(profile.statistics.durationMaxUs == 110)
  #expect(profile.statistics.durationTotalUs == 180)
  #expect(profile.statistics.durationAverageUs == 60)
}

@Test("A first zero duration stays the minimum after a positive observation")
func renderProfileZeroMinimum() {
  var profile = RenderProfile()
  profile.recordRender(startedAt: 10, finishedAt: 10, deadline: 20, completed: false)
  profile.recordRender(startedAt: 30, finishedAt: 80, deadline: 100, completed: true)
  #expect(profile.statistics.durationMinUs == 0)
  #expect(profile.statistics.durationMaxUs == 50)
  #expect(profile.statistics.durationTotalUs == 50)
  #expect(profile.statistics.durationAverageUs == 25)
}

@Test(
  "Duration averages truncate integer fractions",
  arguments: [
    ProfileAverageCase(durations: [1, 2], total: 3, average: 1),
    ProfileAverageCase(durations: [0, 1, 1], total: 2, average: 0),
    ProfileAverageCase(durations: [5, 5, 7], total: 17, average: 5),
  ])
private func renderProfileIntegerAverage(_ fixture: ProfileAverageCase) {
  var profile = RenderProfile()
  for duration in fixture.durations {
    profile.recordRender(startedAt: 0, finishedAt: duration, deadline: UInt64.max, completed: true)
  }
  #expect(profile.statistics.durationTotalUs == fixture.total)
  #expect(profile.statistics.durationAverageUs == fixture.average)
}

@Test("Duration totals wrap without saturating or trapping")
func renderProfileDurationTotalWrap() {
  var profile = RenderProfile()
  profile.recordRender(startedAt: 0, finishedAt: UInt64.max, deadline: UInt64.max, completed: true)
  profile.recordRender(startedAt: 0, finishedAt: 2, deadline: UInt64.max, completed: true)
  #expect(profile.statistics.samples == 2)
  #expect(profile.statistics.durationLatestUs == 2)
  #expect(profile.statistics.durationMinUs == 2)
  #expect(profile.statistics.durationMaxUs == UInt64.max)
  #expect(profile.statistics.durationTotalUs == 1)
  #expect(profile.statistics.durationAverageUs == 0)
}

@Test(
  "Start-time slack is signed and saturates symmetrically without unsafe timestamp conversions",
  arguments: [
    ProfileSlackCase(start: 100, deadline: 300, slack: 200),
    ProfileSlackCase(start: 100, deadline: 100, slack: 0),
    ProfileSlackCase(start: 300, deadline: 100, slack: -200),
    ProfileSlackCase(start: 0, deadline: 0x7fff_ffff_ffff_fffe, slack: 9_223_372_036_854_775_806),
    ProfileSlackCase(start: 0, deadline: 0x7fff_ffff_ffff_ffff, slack: Int64.max),
    ProfileSlackCase(start: 0, deadline: 0x8000_0000_0000_0000, slack: Int64.max),
    ProfileSlackCase(start: 0, deadline: UInt64.max, slack: Int64.max),
    ProfileSlackCase(start: 0x7fff_ffff_ffff_fffe, deadline: 0, slack: -9_223_372_036_854_775_806),
    ProfileSlackCase(start: 0x7fff_ffff_ffff_ffff, deadline: 0, slack: -Int64.max),
    ProfileSlackCase(start: 0x8000_0000_0000_0000, deadline: 0, slack: -Int64.max),
    ProfileSlackCase(start: UInt64.max, deadline: 0, slack: -Int64.max),
    ProfileSlackCase(start: 0xffff_ffff_ffff_fff0, deadline: 0xffff_ffff_ffff_fffa, slack: 10),
    ProfileSlackCase(start: 0xffff_ffff_ffff_fffa, deadline: 0xffff_ffff_ffff_fff0, slack: -10),
    ProfileSlackCase(start: UInt64.max, deadline: UInt64.max, slack: 0),
  ])
private func renderProfileSlackBoundaries(_ fixture: ProfileSlackCase) {
  var profile = RenderProfile()
  profile.recordRender(
    startedAt: fixture.start, finishedAt: fixture.start,
    deadline: fixture.deadline, completed: false)
  #expect(profile.statistics.slackLatestUs == fixture.slack)
  #expect(profile.statistics.slackMinUs == fixture.slack)
  #expect(profile.statistics.slackMaxUs == fixture.slack)
  #expect(profile.statistics.slackLatestUs != Int64.min)
}

@Test("Slack measures the start even when completion is after the deadline")
func renderProfileSlackUsesStart() {
  var profile = RenderProfile()
  profile.recordRender(startedAt: 100, finishedAt: 350, deadline: 300, completed: true)
  #expect(profile.statistics.slackLatestUs == 200)
  #expect(profile.statistics.lateStarts == 0)
  #expect(profile.statistics.completedLate == 1)
}

@Test("Slack extrema preserve a first negative maximum and subsequent signed observations")
func renderProfileSlackExtrema() {
  var profile = RenderProfile()
  profile.recordRender(startedAt: 400, finishedAt: 440, deadline: 350, completed: false)
  #expect(profile.statistics.slackMinUs == -50)
  #expect(profile.statistics.slackMaxUs == -50)
  profile.recordRender(startedAt: 500, finishedAt: 510, deadline: 480, completed: false)
  #expect(profile.statistics.slackMinUs == -50)
  #expect(profile.statistics.slackMaxUs == -20)
  profile.recordRender(startedAt: 600, finishedAt: 610, deadline: 800, completed: true)
  #expect(profile.statistics.slackLatestUs == 200)
  #expect(profile.statistics.slackMinUs == -50)
  #expect(profile.statistics.slackMaxUs == 200)
}

@Test(
  "Late counters use equality and only successful renders count late completion",
  arguments: [
    ProfileLateCase(start: 100, finish: 299, deadline: 300, completed: true, lateStarts: 0, completedLate: 0),
    ProfileLateCase(start: 100, finish: 300, deadline: 300, completed: true, lateStarts: 0, completedLate: 1),
    ProfileLateCase(start: 100, finish: 301, deadline: 300, completed: true, lateStarts: 0, completedLate: 1),
    ProfileLateCase(start: 300, finish: 300, deadline: 300, completed: true, lateStarts: 1, completedLate: 1),
    ProfileLateCase(start: 301, finish: 310, deadline: 300, completed: true, lateStarts: 1, completedLate: 1),
    ProfileLateCase(start: 300, finish: 300, deadline: 300, completed: false, lateStarts: 1, completedLate: 0),
    ProfileLateCase(start: 301, finish: 310, deadline: 300, completed: false, lateStarts: 1, completedLate: 0),
    ProfileLateCase(start: 100, finish: 301, deadline: 300, completed: false, lateStarts: 0, completedLate: 0),
    ProfileLateCase(start: UInt64.max, finish: 0, deadline: 1, completed: true, lateStarts: 1, completedLate: 0),
  ])
private func renderProfileLateClassification(_ fixture: ProfileLateCase) {
  var profile = RenderProfile()
  profile.recordRender(
    startedAt: fixture.start, finishedAt: fixture.finish,
    deadline: fixture.deadline, completed: fixture.completed)
  #expect(profile.statistics.lateStarts == fixture.lateStarts)
  #expect(profile.statistics.completedLate == fixture.completedLate)
}

@Test("Received counter wraps independently")
func renderProfileReceivedWrap() {
  var profile = RenderProfile(statistics: RenderProfile.Statistics(received: UInt64.max))
  profile.recordReceived()
  #expect(profile.statistics.received == 0)
  #expect(profile.statistics.samples == 0)
}

@Test("Completed and late counters wrap while rejected count is untouched")
func renderProfileCompletedCountersWrap() {
  var profile = RenderProfile(
    statistics: RenderProfile.Statistics(
      completed: UInt64.max, rejected: 7, lateStarts: UInt64.max, completedLate: UInt64.max))
  profile.recordRender(startedAt: 100, finishedAt: 100, deadline: 100, completed: true)
  #expect(profile.statistics.completed == 0)
  #expect(profile.statistics.rejected == 7)
  #expect(profile.statistics.lateStarts == 0)
  #expect(profile.statistics.completedLate == 0)
  #expect(profile.statistics.samples == 1)
}

@Test("Rejected and late-start counters wrap without counting a late completion")
func renderProfileRejectedCountersWrap() {
  var profile = RenderProfile(
    statistics: RenderProfile.Statistics(
      completed: 7, rejected: UInt64.max, lateStarts: UInt64.max, completedLate: UInt64.max))
  profile.recordRender(startedAt: 100, finishedAt: 101, deadline: 100, completed: false)
  #expect(profile.statistics.completed == 7)
  #expect(profile.statistics.rejected == 0)
  #expect(profile.statistics.lateStarts == 0)
  #expect(profile.statistics.completedLate == UInt64.max)
  #expect(profile.statistics.samples == 1)
}

@Test("Sample wrap makes average zero then resets minimum and slack but retains duration maximum")
func renderProfileSampleWrap() {
  var profile = RenderProfile(
    statistics: RenderProfile.Statistics(
      samples: UInt64.max, durationMinUs: 9, durationMaxUs: 40, durationTotalUs: 12,
      slackMinUs: -80, slackMaxUs: 60))
  profile.recordRender(startedAt: 100, finishedAt: 101, deadline: 100, completed: true)
  #expect(profile.statistics.samples == 0)
  #expect(profile.statistics.durationMinUs == 1)
  #expect(profile.statistics.durationMaxUs == 40)
  #expect(profile.statistics.durationTotalUs == 13)
  #expect(profile.statistics.durationAverageUs == 0)
  #expect(profile.statistics.slackMinUs == -80)
  #expect(profile.statistics.slackMaxUs == 60)

  profile.recordRender(startedAt: 200, finishedAt: 202, deadline: 210, completed: false)
  #expect(profile.statistics.samples == 1)
  #expect(profile.statistics.durationLatestUs == 2)
  #expect(profile.statistics.durationMinUs == 2)
  #expect(profile.statistics.durationMaxUs == 40)
  #expect(profile.statistics.durationTotalUs == 15)
  #expect(profile.statistics.durationAverageUs == 15)
  #expect(profile.statistics.slackLatestUs == 10)
  #expect(profile.statistics.slackMinUs == 10)
  #expect(profile.statistics.slackMaxUs == 10)
}

@Test("A post-wrap sample can still raise the retained maximum", arguments: [UInt64(0), 41])
func renderProfilePostWrapMaximum(_ duration: UInt64) {
  var profile = RenderProfile(
    statistics: RenderProfile.Statistics(
      durationMinUs: 9, durationMaxUs: 40, slackMinUs: -80, slackMaxUs: 60))
  profile.recordRender(startedAt: 0, finishedAt: duration, deadline: 10, completed: false)
  #expect(profile.statistics.durationMinUs == duration)
  #expect(profile.statistics.durationMaxUs == (duration == 0 ? 40 : 41))
  #expect(profile.statistics.slackMinUs == 10)
  #expect(profile.statistics.slackMaxUs == 10)
}

@Test(
  "Initial report time is zero and empty reports are allowed when due",
  arguments: [
    ProfileReportCase(now: 0, due: false),
    ProfileReportCase(now: 999_999, due: false),
    ProfileReportCase(now: 1_000_000, due: true),
    ProfileReportCase(now: 1_000_001, due: true),
    ProfileReportCase(now: 10_000_000, due: true),
  ])
private func renderProfileInitialReportThreshold(_ fixture: ProfileReportCase) {
  var profile = RenderProfile()
  let report = profile.takeReport(at: fixture.now)
  #expect((report != nil) == fixture.due)
  if let report {
    #expect(report.samples == 0)
    #expect(report.durationAverageUs == 0)
  }
}

@Test("Reports advance to actual report time without catch-up or early timestamp updates")
func renderProfileReportIntervals() {
  var profile = RenderProfile()
  let cases: [ProfileReportCase] = [
    ProfileReportCase(now: 999_999, due: false),
    ProfileReportCase(now: 1_000_000, due: true),
    ProfileReportCase(now: 1_000_001, due: false),
    ProfileReportCase(now: 1_999_999, due: false),
    ProfileReportCase(now: 2_000_000, due: true),
    ProfileReportCase(now: 2_000_000, due: false),
    ProfileReportCase(now: 10_123_456, due: true),
    ProfileReportCase(now: 10_123_456, due: false),
    ProfileReportCase(now: 11_123_455, due: false),
    ProfileReportCase(now: 11_123_456, due: true),
  ]
  for fixture in cases {
    #expect((profile.takeReport(at: fixture.now) != nil) == fixture.due)
  }
}

@Test("Reports remain cumulative and previous snapshots retain their values")
func renderProfileCumulativeReports() throws {
  var profile = RenderProfile()
  profile.recordReceived()
  profile.recordRender(startedAt: 100, finishedAt: 150, deadline: 300, completed: true)
  let firstReport = profile.takeReport(at: 1_000_000)
  let first = try #require(firstReport)
  profile.recordReceived()
  profile.recordRender(startedAt: 400, finishedAt: 410, deadline: 350, completed: false)
  let secondReport = profile.takeReport(at: 2_000_000)
  let second = try #require(secondReport)
  #expect(first.received == 1 && first.samples == 1)
  #expect(first.completed == 1 && first.rejected == 0)
  #expect(first.durationTotalUs == 50 && first.durationAverageUs == 50)
  #expect(second.received == 2 && second.samples == 2)
  #expect(second.completed == 1 && second.rejected == 1)
  #expect(second.durationTotalUs == 60 && second.durationAverageUs == 30)
  #expect(second.slackMinUs == -50 && second.slackMaxUs == 200)
  #expect(profile.statistics.samples == 2)
}

@Test(
  "Report elapsed time wraps across UInt64 and retains unsigned backwards-time semantics",
  arguments: [
    ProfileReportWrapCase(last: 0xffff_ffff_fff8_5ee0, now: 499_999, due: false),
    ProfileReportWrapCase(last: 0xffff_ffff_fff8_5ee0, now: 500_000, due: true),
    ProfileReportWrapCase(last: UInt64.max, now: 0, due: false),
    ProfileReportWrapCase(last: 1_000_000, now: 999_999, due: true),
  ])
private func renderProfileReportTimeWrap(_ fixture: ProfileReportWrapCase) {
  var profile = RenderProfile(lastReportedAt: fixture.last)
  #expect((profile.takeReport(at: fixture.now) != nil) == fixture.due)
  if fixture.due {
    #expect(profile.takeReport(at: fixture.now) == nil)
    #expect(profile.takeReport(at: fixture.now + 999_999) == nil)
    #expect(profile.takeReport(at: fixture.now + 1_000_000) != nil)
  }
}

@Test("Statistics copies cannot modify the profiler's private state")
func renderProfileStatisticsOwnership() {
  var profile = RenderProfile()
  profile.recordReceived()
  var copy = profile.statistics
  copy.received = 99
  #expect(profile.statistics.received == 1)
  profile.recordReceived()
  #expect(copy.received == 99)
  #expect(profile.statistics.received == 2)
}

@Test("Fresh instances have independent statistics and report clocks")
func renderProfileFreshInstance() {
  var first = RenderProfile()
  first.recordReceived()
  first.recordRender(startedAt: 100, finishedAt: 150, deadline: 300, completed: true)
  #expect(first.takeReport(at: 1_000_000) != nil)
  var fresh = RenderProfile()
  #expect(fresh.statistics.received == 0 && fresh.statistics.samples == 0)
  #expect(fresh.statistics.durationTotalUs == 0)
  #expect(fresh.takeReport(at: 999_999) == nil)
  #expect(fresh.takeReport(at: 1_000_000) != nil)
  #expect(first.takeReport(at: 1_000_000) == nil)
  #expect(first.statistics.received == 1 && first.statistics.samples == 1)
}

private struct ProfileDurationCase {
  let start: UInt64
  let finish: UInt64
  let duration: UInt64
}

private struct ProfileObservation {
  let start: UInt64
  let finish: UInt64
  let deadline: UInt64
  let completed: Bool
}

private struct ProfileAverageCase {
  let durations: [UInt64]
  let total: UInt64
  let average: UInt64
}

private struct ProfileSlackCase {
  let start: UInt64
  let deadline: UInt64
  let slack: Int64
}

private struct ProfileLateCase {
  let start: UInt64
  let finish: UInt64
  let deadline: UInt64
  let completed: Bool
  let lateStarts: UInt64
  let completedLate: UInt64
}

private struct ProfileReportCase {
  let now: UInt64
  let due: Bool
}

private struct ProfileReportWrapCase {
  let last: UInt64
  let now: UInt64
  let due: Bool
}
