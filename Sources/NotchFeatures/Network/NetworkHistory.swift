// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import SQLite3

/// Bytes down and up.
public struct Traffic: Hashable, Sendable {
    public var down: Int64
    public var up: Int64

    public init(down: Int64 = 0, up: Int64 = 0) {
        self.down = down
        self.up = up
    }

    public static func + (a: Traffic, b: Traffic) -> Traffic { Traffic(down: a.down + b.down, up: a.up + b.up) }
    public static func += (a: inout Traffic, b: Traffic) { a = a + b }
    public var total: Int64 { down + up }
}

/// What the history chart shows, a calendar page at a time: a day by the hour, a week or a month by
/// the day, or a year by the month.
public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year

    public var id: Self { self }

    public var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    /// As Health's charts write them, for a narrow switch.
    public var shortTitle: String {
        switch self {
        case .day: "D"
        case .week: "W"
        case .month: "M"
        case .year: "Y"
        }
    }

    public var caption: String {
        switch self {
        case .day: "A day by the hour"
        case .week: "A week by the day"
        case .month: "A month by the day"
        case .year: "A year by the month"
        }
    }

    /// What a page covers.
    var period: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// What one bar covers.
    var unit: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        }
    }

    /// The page `page` periods away from the one `now` is in: 0 for today, this week, this month, or
    /// this year, -1 for the one before. A week starts on the calendar's first weekday.
    func interval(page: Int, now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let day = calendar.date(byAdding: period, value: page, to: now) else { return nil }
        return calendar.dateInterval(of: period, for: day)
    }

    /// The starts of a page's bars, oldest first: 23 to 25 hours, 7 days, 28 to 31 days, or 12 months.
    func starts(in page: DateInterval, calendar: Calendar = .current) -> [Date] {
        var starts: [Date] = []
        var start = page.start
        while start < page.end {
            starts.append(start)
            guard let next = calendar.date(byAdding: unit, value: 1, to: start), next > start else { break }
            start = next
        }
        return starts
    }

    /// Groups rows into bars in SQL, on the local clock, so a day is the user's midnight to midnight.
    fileprivate var groupFormat: String {
        switch self {
        case .day: "%Y-%m-%d %H"
        case .week, .month: "%Y-%m-%d"
        case .year: "%Y-%m"
        }
    }
}

/// One bar of the history chart.
public struct TrafficBucket: Hashable, Identifiable, Sendable {
    public var start: Date
    public var traffic: Traffic
    /// It starts after now: an empty slot on the page.
    public var upcoming = false
    public var id: Date { start }
}

/// The history in SQLite: one row per hour of the local clock (its start, bytes down, bytes up), or
/// about 9,000 rows and 250 KB a year. Writing an hour again adds to it, so a partial hour saved on
/// sleep and the rest saved later add up. NetSpeed kept a row a minute, 60 times as many, and never
/// drew anything finer than an hour.
final class NetworkHistory {
    private var db: OpaquePointer?

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            Log.features.error(
                "Network history didn't open: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            sqlite3_close(db)
            db = nil
            return
        }
        // WAL writes each hour as a page appended to the log, and survives a crash.
        exec("PRAGMA journal_mode=WAL")
        exec("CREATE TABLE IF NOT EXISTS hours (start INTEGER PRIMARY KEY, down INTEGER NOT NULL, up INTEGER NOT NULL)")
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    private func exec(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    var isEmpty: Bool { query("SELECT COUNT(*) FROM hours").first.map { $0[0] == 0 } ?? true }

    /// Adds each hour's traffic to what's stored for it, in one transaction.
    func add(_ hours: [Date: Traffic]) {
        guard db != nil, !hours.isEmpty else { return }
        let sql = """
            INSERT INTO hours (start, down, up) VALUES (?, ?, ?)
            ON CONFLICT(start) DO UPDATE SET down = down + excluded.down, up = up + excluded.up
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        exec("BEGIN")
        for (hour, traffic) in hours {
            sqlite3_bind_int64(statement, 1, Int64(hour.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, traffic.down)
            sqlite3_bind_int64(statement, 3, traffic.up)
            sqlite3_step(statement)
            sqlite3_reset(statement)
        }
        exec("COMMIT")
    }

    /// A page's bars, a unit of the range each, oldest first, with empty ones as zeros so the chart
    /// keeps its shape; those that start after `now` are still to come.
    func buckets(for range: HistoryRange, in page: DateInterval, now: Date = .now, calendar: Calendar = .current)
        -> [TrafficBucket]
    {
        // Each group's earliest hour lands in its bar, whatever time zone the rows were written in.
        let sql = """
            SELECT MIN(start), SUM(down), SUM(up) FROM hours \(Self.within(page))
            GROUP BY strftime('\(range.groupFormat)', start, 'unixepoch', 'localtime')
            """
        var totals: [Date: Traffic] = [:]
        for row in query(sql) {
            let date = Date(timeIntervalSince1970: TimeInterval(row[0]))
            guard let start = calendar.dateInterval(of: range.unit, for: date)?.start else { continue }
            totals[start, default: Traffic()] += Traffic(down: row[1], up: row[2])
        }
        return range.starts(in: page, calendar: calendar).map {
            TrafficBucket(start: $0, traffic: totals[$0] ?? Traffic(), upcoming: $0 > now)
        }
    }

    /// What moved in `interval`.
    func traffic(in interval: DateInterval) -> Traffic {
        query("SELECT IFNULL(SUM(down), 0), IFNULL(SUM(up), 0) FROM hours \(Self.within(interval))").first.map {
            Traffic(down: $0[0], up: $0[1])
        } ?? Traffic()
    }

    /// When the first hour recorded began, if there is one.
    func earliest() -> Date? {
        query("SELECT start FROM hours ORDER BY start LIMIT 1").first.map {
            Date(timeIntervalSince1970: TimeInterval($0[0]))
        }
    }

    /// Everything ever recorded.
    func total() -> Traffic {
        query("SELECT IFNULL(SUM(down), 0), IFNULL(SUM(up), 0) FROM hours").first.map {
            Traffic(down: $0[0], up: $0[1])
        } ?? Traffic()
    }

    private static func within(_ interval: DateInterval) -> String {
        "WHERE start >= \(Int64(interval.start.timeIntervalSince1970)) "
            + "AND start < \(Int64(interval.end.timeIntervalSince1970))"
    }

    func clear() { exec("DELETE FROM hours") }

    /// Adds NetSpeed's history (a row a minute, `samples(ts, down, up)`) by the hour of the local clock.
    /// Returns how many hours it added.
    func importNetSpeed(from url: URL, calendar: Calendar = .current) -> Int {
        var source: OpaquePointer?
        defer { sqlite3_close(source) }
        guard FileManager.default.fileExists(atPath: url.path),
            sqlite3_open_v2(url.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { return 0 }
        let sql = """
            SELECT MIN(ts), SUM(down), SUM(up) FROM samples
            GROUP BY strftime('%Y-%m-%d %H', ts, 'unixepoch', 'localtime')
            """
        var hours: [Date: Traffic] = [:]
        for row in Self.query(sql, in: source) {
            let minute = Date(timeIntervalSince1970: TimeInterval(row[0]))
            guard let hour = calendar.dateInterval(of: .hour, for: minute)?.start else { continue }
            hours[hour, default: Traffic()] += Traffic(down: row[1], up: row[2])
        }
        add(hours)
        return hours.count
    }

    private func query(_ sql: String) -> [[Int64]] { Self.query(sql, in: db) }

    /// Every row of integer columns.
    private static func query(_ sql: String, in db: OpaquePointer?) -> [[Int64]] {
        var statement: OpaquePointer?
        guard db != nil, sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [[Int64]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { sqlite3_column_int64(statement, $0) })
        }
        return rows
    }
}
