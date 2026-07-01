import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

// MARK: - AlarmKit Live Activity Implementation (Official WWDC 2025 Pattern)

// AlarmMetadata for our alarm app - must match exactly with main app
nonisolated struct EmptyAlarmMetadata: AlarmMetadata, Sendable, Codable {
    let title: String
    
    nonisolated init(title: String = "Alarm") {
        self.title = title
    }
}

// Type alias to match main app
typealias AlarmAppMetadata = EmptyAlarmMetadata

// MARK: - Live Activity Widget
struct CalarmWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        // Using official AlarmKit ActivityConfiguration pattern from WWDC 2025
        ActivityConfiguration(for: AlarmAttributes<AlarmAppMetadata>.self) { context in
            // Lock Screen View - Minimal design as requested
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .font(.headline)
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.metadata?.title ?? "Alarm")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Show countdown using official AlarmKit state
                    switch context.state.mode {
                    case .countdown(let countdown):
                        let fireDate = countdown.startDate.addingTimeInterval(
                            countdown.totalCountdownDuration - countdown.previouslyElapsedDuration
                        )
                        Text(timerInterval: Date()...fireDate, countsDown: true)
                            .font(.caption)
                            .foregroundColor(.red)
                            .monospacedDigit()
                    case .paused:
                        Text("Paused")
                            .font(.caption)
                            .foregroundColor(.orange)
                    case .alert:
                        Text("Alerting")
                            .font(.caption)
                            .foregroundColor(.red)
                    @unknown default:
                        Text("Unknown")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
            
        } dynamicIsland: { context in
            // Dynamic Island Configuration - Minimal and compact
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: "alarm.fill")
                            .foregroundColor(.red)
                        Text(context.attributes.metadata?.title ?? "Alarm")
                            .font(.headline)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    // Show countdown state
                    switch context.state.mode {
                    case .countdown(let countdown):
                        let fireDate = countdown.startDate.addingTimeInterval(
                            countdown.totalCountdownDuration - countdown.previouslyElapsedDuration
                        )
                        Text(timerInterval: Date()...fireDate, countsDown: true)
                            .font(.caption)
                            .foregroundColor(.red)
                            .monospacedDigit()
                    case .paused:
                        Text("Paused")
                            .font(.caption)
                            .foregroundColor(.orange)
                    case .alert:
                        Text("Alerting")
                            .font(.caption)
                            .foregroundColor(.red)
                    @unknown default:
                        Text("Unknown")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
            } compactLeading: {
                // Compact leading - just icon
                Image(systemName: "alarm.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    
            } compactTrailing: {
                // Show compact countdown timer in Dynamic Island
                switch context.state.mode {
                case .countdown(let countdown):
                    let fireDate = countdown.startDate.addingTimeInterval(
                        countdown.totalCountdownDuration - countdown.previouslyElapsedDuration
                    )
                    Text(timerInterval: Date()...fireDate, countsDown: true)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.red)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .frame(maxWidth: 40)
                case .paused:
                    Text("Paused")
                        .font(.caption2)
                        .foregroundColor(.orange)
                case .alert:
                    Text("Alerting")
                        .font(.caption2)
                        .foregroundColor(.red)
                @unknown default:
                    Text("Unknown")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                
            } minimal: {
                // Minimal view - just small icon
                Image(systemName: "alarm.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }
}

// Preview is simplified for now - will be properly configured once AlarmKit types are fully available
// #Preview will be added back once all AlarmKit types compile properly