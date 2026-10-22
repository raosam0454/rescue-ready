import WidgetKit
import SwiftUI

/// One open batch as the widget shows it.
struct WidgetBatch: Identifiable {
    var id = UUID()
    let foodDescription: String
    let weightText: String
    let expiresAt: Date

    func isUrgent(at date: Date) -> Bool { expiresAt.timeIntervalSince(date) < 30 * 60 }
    func hasExpired(at date: Date) -> Bool { expiresAt <= date }
}

struct BatchEntry: TimelineEntry {
    let date: Date
    /// Open batches, soonest expiry first.
    let batches: [WidgetBatch]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BatchEntry {
        BatchEntry(date: .now, batches: WidgetBatch.samples(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (BatchEntry) -> Void) {
        // The widget gallery shows sample batches so people can see what it looks like.
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            completion(BatchEntry(date: .now, batches: await loadBatches(now: .now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatchEntry>) -> Void) {
        Task {
            let now = Date.now
            let batches = await loadBatches(now: now)
            completion(timeline(for: batches, now: now))
        }
    }

    private func timeline(for batches: [WidgetBatch], now: Date) -> Timeline<BatchEntry> {

        // One entry now, plus one each time a batch expires or hits the 30 minute mark,
        // so the widget changes colour and shows "Expired" on time.
        let changeDates = batches.flatMap { [$0.expiresAt.addingTimeInterval(-30 * 60), $0.expiresAt] }
            .filter { $0 > now }
        let entries = ([now] + changeDates).sorted().map { BatchEntry(date: $0, batches: batches) }

        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
    }

    /// Reads open batches from the Core Data store the app shares through the App Group.
    /// Shows nothing rather than failing if the store can't be read.
    private func loadBatches(now: Date) async -> [WidgetBatch] {
        let persistence = PersistenceController()
        guard persistence.isAvailable else { return [] }

        let fetch = FetchExpiringBatchesUseCase(batches: CoreDataBatchRepository(container: persistence.container),
                                                now: { now })
        let expiring = (try? await fetch.execute()) ?? []
        return expiring.map { WidgetBatch($0.batch) }
    }
}

// MARK: - Views

struct RescueReadyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BatchEntry

    var body: some View {
        if entry.batches.isEmpty {
            EmptyBatchesView()
        } else if family == .systemSmall {
            SmallBatchView(batch: entry.batches[0], moreCount: entry.batches.count - 1, date: entry.date)
        } else {
            MediumBatchView(batches: Array(entry.batches.prefix(3)), totalCount: entry.batches.count, date: entry.date)
        }
    }
}

/// The batch that runs out first, with a big countdown.
private struct SmallBatchView: View {
    let batch: WidgetBatch
    let moreCount: Int
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next to expire", systemImage: "timer")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(batch.foodDescription)
                .font(.headline)
                .lineLimit(2)
            TimeLeftText(batch: batch, date: date)
                .font(.title2.weight(.bold))
            Spacer(minLength: 0)
            Text(moreCount > 0 ? "+\(moreCount) more open" : batch.weightText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Up to three open batches, soonest first.
private struct MediumBatchView: View {
    let batches: [WidgetBatch]
    let totalCount: Int
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Open batches", systemImage: "tray.full")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(totalCount) open")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            ForEach(batches) { batch in
                HStack {
                    Circle()
                        .fill(StatusColor.of(batch, at: date))
                        .frame(width: 8, height: 8)
                    Text(batch.foodDescription)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    TimeLeftText(batch: batch, date: date)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: 80, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct EmptyBatchesView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title)
                .foregroundStyle(.green)
            Text("No open batches")
                .font(.headline)
            Text("All food handed over")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

/// A live countdown that the system keeps ticking, or "Expired".
private struct TimeLeftText: View {
    let batch: WidgetBatch
    let date: Date

    var body: some View {
        if batch.hasExpired(at: date) {
            Text("Expired")
                .foregroundStyle(.red)
        } else {
            Text(timerInterval: date...batch.expiresAt, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(batch.isUrgent(at: date) ? .orange : .primary)
        }
    }
}

private enum StatusColor {
    static func of(_ batch: WidgetBatch, at date: Date) -> Color {
        if batch.hasExpired(at: date) { return .red }
        return batch.isUrgent(at: date) ? .orange : .green
    }
}

// MARK: - Widget

struct RescueReadyWidget: Widget {
    let kind: String = "RescueReadyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RescueReadyWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Expiring Batches")
        .description("See which rescued food runs out of safe hold time next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension WidgetBatch {
    init(_ batch: FoodBatch) {
        self.init(id: batch.id.rawValue,
                  foodDescription: batch.foodDescription,
                  weightText: "\(batch.weight.kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg",
                  expiresAt: batch.holdWindow.expiresAt)
    }
}

// MARK: - Sample data

extension WidgetBatch {
    /// Sample batches for previews and the widget gallery.
    static func samples(now: Date) -> [WidgetBatch] {
        [
            WidgetBatch(foodDescription: "Chicken skewers", weightText: "5.5 kg", expiresAt: now.addingTimeInterval(20 * 60)),
            WidgetBatch(foodDescription: "Vegetable fried rice", weightText: "8 kg", expiresAt: now.addingTimeInterval(95 * 60)),
            WidgetBatch(foodDescription: "Garden salad", weightText: "3 kg", expiresAt: now.addingTimeInterval(150 * 60)),
            WidgetBatch(foodDescription: "Fruit platter", weightText: "4 kg", expiresAt: now.addingTimeInterval(200 * 60)),
        ]
    }
}

#Preview("Small", as: .systemSmall) {
    RescueReadyWidget()
} timeline: {
    BatchEntry(date: .now, batches: WidgetBatch.samples(now: .now))
    BatchEntry(date: .now, batches: [])
}

#Preview("Medium", as: .systemMedium) {
    RescueReadyWidget()
} timeline: {
    BatchEntry(date: .now, batches: WidgetBatch.samples(now: .now))
}
