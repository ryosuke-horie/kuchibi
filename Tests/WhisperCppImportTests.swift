import Testing
import WhisperCppKit

@Suite("WhisperCppKit Import")
struct WhisperCppImportTests {
    @Test("WhisperCppKit module can be imported")
    func canImport() {
        // XCFramework が module として import できれば pass
        #expect(Bool(true))
    }
}
