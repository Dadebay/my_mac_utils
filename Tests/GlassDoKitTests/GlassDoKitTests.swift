import Testing
@testable import GlassDoKit

@Test("GlassDoKit versiyon bilgisi dolu")
func versionIsSet() {
    #expect(!GlassDoKit.version.isEmpty)
}
