#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum LocalDate {
    nonisolated(unsafe) static var secondsFromUTC: (Date) -> Int = { TimeZone.current.secondsFromGMT(for: $0) }

    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let secondsPerDay = 86_400

    static func startOfDay(_ date: Date) -> Date {
        let offset = secondsFromUTC(date)
        let local = Int(date.timeIntervalSince1970.rounded(.down)) + offset
        let midnight = local - mod(local, secondsPerDay)
        return Date(timeIntervalSince1970: Double(midnight - offset))
    }

    static func day(_ date: Date) -> String {
        let p = parts(date)
        return "\(weekdays[p.weekday]) \(p.day) \(months[p.month - 1])"
    }

    static func dayAndTime(_ date: Date) -> String {
        let p = parts(date)
        let hour = p.hour % 12 == 0 ? 12 : p.hour % 12
        let minute = p.minute < 10 ? "0\(p.minute)" : "\(p.minute)"
        return "\(day(date)), \(hour):\(minute)\(p.hour < 12 ? "AM" : "PM")"
    }

    private static func parts(_ date: Date) -> (weekday: Int, day: Int, month: Int, hour: Int, minute: Int) {
        let local = Int(date.timeIntervalSince1970.rounded(.down)) + secondsFromUTC(date)
        let days = (local - mod(local, secondsPerDay)) / secondsPerDay
        let seconds = mod(local, secondsPerDay)
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (mod(days + 4, 7), day, month, seconds / 3600, seconds % 3600 / 60)
    }

    private static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
}
