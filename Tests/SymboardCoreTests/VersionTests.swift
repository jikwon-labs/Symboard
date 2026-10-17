import Testing
@testable import SymboardCore
@Test func version() { #expect(!Symboard.version.isEmpty) }
