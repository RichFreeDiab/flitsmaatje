import ActivityKit
import SwiftUI
import WidgetKit

struct FlitsMaatjeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlitsMaatjeAttributes.self) { context in
            LiveActivityLockView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.icon).font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.distanceMeters)m")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.label)
                        .font(.headline)
                }
            } compactLeading: {
                Text(context.state.icon)
            } compactTrailing: {
                Text("\(context.state.distanceMeters)m")
                    .font(.caption.monospacedDigit().bold())
            } minimal: {
                Text("📷")
            }
        }
    }
}

private struct LiveActivityLockView: View {
    let state: FlitsMaatjeAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            Text(state.icon)
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 4) {
                Text("FlitsMaatje")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.label)
                    .font(.headline)
                Text("over \(state.distanceMeters) m")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
    }
}
