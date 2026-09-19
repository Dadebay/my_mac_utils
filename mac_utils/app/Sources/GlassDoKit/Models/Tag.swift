import SwiftData
import Foundation

@Model
public final class Tag {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "#8E8E93"
    public var tasks: [Task]? = []

    public init(name: String = "") { self.name = name }
}
