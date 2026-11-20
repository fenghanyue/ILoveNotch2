// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Testing

@testable import NotchFeatures

@MainActor
struct TimerFeatureTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func aCountdownPausesAndResumesWhereItLeftOff() throws {
        let timer = TimerFeature()
        timer.start(300, now: start)
        #expect(timer.countdown?.remaining(at: start.addingTimeInterval(100)) == 200)
        timer.pause(now: start.addingTimeInterval(100))
        let paused = try #require(timer.countdown)
        #expect(!paused.isRunning && paused.remaining(at: start.addingTimeInterval(999)) == 200)
        #expect(!timer.alarmPending, "a paused countdown has no deadline")
        timer.resume(now: start.addingTimeInterval(500))
        #expect(timer.countdown?.remaining(at: start.addingTimeInterval(550)) == 150)
        #expect(timer.alarmPending)
        timer.cancel()
        #expect(timer.countdown == nil && !timer.alarmPending)
    }

    @Test func addingAMinuteExtendsTheCountdown() {
        let timer = TimerFeature()
        timer.start(60, now: start)
        timer.addMinute()
        #expect(timer.countdown?.total == 120)
        #expect(timer.countdown?.remaining(at: start) == 120)
    }

    @Test func startingAnotherCountdownCanBeUndone() {
        let timer = TimerFeature()
        timer.start(600, now: start)
        timer.start(1500, now: start + 100)
        #expect(timer.countdown?.total == 1500 && timer.countdown?.startedAt == start + 100)
        timer.undoSwap()
        #expect(timer.countdown?.total == 600, "the first one is back")
        #expect(timer.countdown?.remaining(at: start + 400) == 200, "as if it had kept going")
        #expect(timer.replaced == nil && timer.alarmPending)
        timer.start(60)
        timer.cancel()
        #expect(timer.replaced == nil, "nothing to bring back once cancelled")
    }

    @Test func typedMinutesBecomeALength() {
        #expect(TimerView.seconds(fromMinutes: " 25 ") == 1500)
        #expect(TimerView.seconds(fromMinutes: "1,5") == 90)
        #expect(TimerView.seconds(fromMinutes: "0") == nil)
        #expect(TimerView.seconds(fromMinutes: "-3") == nil)
        #expect(TimerView.seconds(fromMinutes: "abc") == nil)
        #expect(TimerView.seconds(fromMinutes: "2000") == nil, "a day at most")
    }

    @Test func aFinishedCountdownRingsOnceThroughItsDeadline() async throws {
        let timer = TimerFeature()
        var activities: [Activity] = []
        timer.onActivity = { activities.append($0) }
        timer.start(0.2)
        #expect(await eventually { !activities.isEmpty })
        #expect(activities.map(\.title) == ["Timer done"])
        #expect(timer.countdown == nil && !timer.alarmPending)
    }

    @Test func theStopwatchBanksTimeAcrossPausesAndRecordsLaps() {
        var watch = Stopwatch()
        watch.start(at: start)
        watch.lap(at: start.addingTimeInterval(10))
        watch.pause(at: start.addingTimeInterval(15))
        #expect(watch.elapsed(at: start.addingTimeInterval(100)) == 15, "paused time doesn't count")
        watch.start(at: start.addingTimeInterval(100))
        #expect(watch.elapsed(at: start.addingTimeInterval(105)) == 20)
        watch.lap(at: start.addingTimeInterval(105))
        #expect(watch.laps == [10, 20])
        watch.reset()
        #expect(watch == Stopwatch())
    }

    @Test func keepingAwakeHoldsOneAssertionAndShowsInTheClosedNotchUntilTurnedOff() {
        let timer = TimerFeature()
        var ongoing: [Activity?] = []
        timer.onOngoing = { ongoing.append($0) }
        timer.keepAwake(for: nil, now: start)
        #expect(timer.keepsAwake && timer.awakeUntil == .distantFuture && timer.holdsAssertion)
        #expect(ongoing.last??.title == "Awake" && ongoing.last??.countdown == nil, "no end, so no countdown")
        timer.keepAwake(for: 3600, now: start)
        #expect(timer.awakeUntil == start + 3600 && ongoing.last??.countdown == start + 3600)
        timer.extendAwake(now: start + 600)
        #expect(timer.awakeUntil == start + 5400, "half an hour more")
        timer.allowSleep()
        #expect(!timer.keepsAwake && !timer.holdsAssertion)
        #expect(ongoing.count == 4 && ongoing.last == .some(nil), "and the closed notch lets it go")
    }

    @Test func aTimedKeepAwakeRunsOutAndSaysSo() async {
        let timer = TimerFeature()
        var activities: [Activity] = []
        timer.onActivity = { activities.append($0) }
        timer.keepAwake(for: 0.2)
        #expect(await eventually { !timer.keepsAwake })
        #expect(activities.map(\.title) == ["Can sleep"] && !timer.holdsAssertion)
    }

    @Test func sleepingAnywayEndsKeepAwake() async {
        // Its own center: tests run side by side, and a real sleep notice would reach every timer.
        let workspace = NotificationCenter()
        let timer = TimerFeature(workspace: workspace)
        timer.keepAwake(for: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(await eventually { !timer.keepsAwake })
        #expect(!timer.holdsAssertion)
    }

    @Test func timesAreFormattedForHumans() {
        #expect(formatTime(0) == "0:00")
        #expect(formatTime(59.2) == "1:00", "countdowns round up so 0:00 means done")
        #expect(formatTime(59.8, roundingUp: false) == "0:59", "counters round down")
        #expect(formatTime(3725) == "1:02:05")
        #expect(formatTime(65.37, tenths: true) == "1:05.3")
    }
}
