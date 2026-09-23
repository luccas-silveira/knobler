import SwiftUI

/// The colour a ring or bar takes at a given level of use.
///
/// The thresholds come from the mockup, which shows 21% green, 52% yellow and
/// 73% orange. (The prose table in the design spec says 50–79 is yellow, which
/// would make 73% yellow and contradict the frame it claims to describe — the
/// frame wins.)
enum UsageBand: String, Codable, Equatable {
    case ample       // under half
    case watch       // getting close
    case critical    // nearly out
    case exhausted   // limit hit, waiting for the reset

    static func band(for usedFraction: Double, watchLimit: Double = 0.50, criticalLimit: Double = 0.70) -> UsageBand {
        switch usedFraction {
        case ..<watchLimit: return .ample
        case ..<criticalLimit: return .watch
        case ..<1.0: return .critical
        default:      return .exhausted
        }
    }

    /// `accent` only ever stands in for the ample state's colour — the
    /// warning bands stay fixed regardless of the chosen accent, since their
    /// whole job is to interrupt whatever else is on screen and a
    /// customisable warning colour could be tuned into invisibility.
    func color(accent: Color = Palette.ample) -> Color {
        switch self {
        case .ample:                 return accent
        case .watch:                 return Palette.watch
        case .critical, .exhausted:  return Palette.critical
        }
    }
}

private struct UsageWatchLimitKey: EnvironmentKey {
    static let defaultValue: Double = 0.50
}

private struct UsageCriticalLimitKey: EnvironmentKey {
    static let defaultValue: Double = 0.70
}

extension EnvironmentValues {
    var usageWatchLimit: Double {
        get { self[UsageWatchLimitKey.self] }
        set { self[UsageWatchLimitKey.self] = newValue }
    }

    var usageCriticalLimit: Double {
        get { self[UsageCriticalLimitKey.self] }
        set { self[UsageCriticalLimitKey.self] = newValue }
    }
}
