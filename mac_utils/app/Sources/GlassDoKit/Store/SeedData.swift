import SwiftData
import Foundation

public enum SeedData {

    static let tasks: [String] = [
        "Todo app for myself — https://github.com/dickwu/apple-design-skill",
        "Shipaton",
        "Bottom nav bar üzerinde arabalar geçsin — modeller video lazım veya animation",
        "Firebase landing page gerek",
        "Klima çalıştırma animasyonu",
        "Araba çalıştırma animasyonu",
        "Splash screen — logo in / sonky logo çalışması",
        "carDX",
        "Maşyn işletyän aparat tapmaly",
        "React Native (Zafer Ayan) — 4 ders",
        "React Native (Zafer Ayan) — 5 ders",
        "YouTube channel açmaly",
        "Rysgal bankdan kart almaly",
        "Samalyot project — waiting — meeting",
        "Food delivery tabşyrmaly",
        "Aykitap — publish",
        "Atelyam — 100$",
        "Whats app erişim izni — Pulse Transfer app",
        "Salon app design etmeli",
        "Zagran uzatmaly",
    ]

    @MainActor
    public static func populateIfNeeded(container: ModelContainer) {
        let context = container.mainContext
        let existingCount = (try? context.fetchCount(FetchDescriptor<Task>())) ?? 0
        guard existingCount == 0 else { return }

        for (index, title) in tasks.enumerated() {
            let task = Task(title: title)
            task.sortIndex = index
            context.insert(task)
        }

        try? context.save()
    }
}
