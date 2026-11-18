import Combine
import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "virtualNotch.todos.v1"
    private let maxItems = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let storedItems = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = storedItems
        } else {
            items = []
        }
    }

    var remainingCount: Int {
        items.lazy.filter { !$0.isCompleted }.count
    }

    var hasCompletedItems: Bool {
        items.contains(where: \TodoItem.isCompleted)
    }

    /// Soonest-due pending task (tasks with a due date sort first); falls back
    /// to insertion order for tasks without a due date.
    var soonestPendingTask: TodoItem? {
        items
            .filter { !$0.isCompleted }
            .min { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    @discardableResult
    func add(
        _ rawTitle: String,
        dueDate: Date? = nil,
        reminder: TodoReminder? = nil
    ) -> Bool {
        let title = rawTitle
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }

        let item = TodoItem(title: title, dueDate: dueDate, reminder: reminder)
        items.insert(item, at: 0)
        scheduleReminder(for: item)
        if items.count > maxItems {
            let trimmed = Array(items.suffix(items.count - maxItems))
            items.removeLast(items.count - maxItems)
            trimmed.forEach { cancelReminder(for: $0) }
        }
        return true
    }

    func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
        if items[index].isCompleted {
            cancelReminder(for: items[index])
        } else {
            scheduleReminder(for: items[index])
        }
    }

    func remove(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        cancelReminder(for: item)
    }

    func clearCompleted() {
        let completed = items.filter(\.isCompleted)
        items.removeAll { $0.isCompleted }
        completed.forEach { cancelReminder(for: $0) }
    }

    // MARK: - Reminders

    private func scheduleReminder(for item: TodoItem) {
        guard !item.isCompleted,
              let dueDate = item.dueDate,
              let reminder = item.reminder else { return }
        let fireDate = dueDate.addingTimeInterval(-reminder.offset)
        guard fireDate > Date() else { return }
        NotificationService.shared.scheduleTodoReminder(
            title: item.title,
            at: fireDate,
            identifier: item.notificationIdentifier
        )
    }

    private func cancelReminder(for item: TodoItem) {
        NotificationService.shared.cancelScheduled(item.notificationIdentifier)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
