import HospitalityDomainProfile
import SwiftUI
import OpenOatsKit

@main
enum OpenOatsApp {
    @MainActor
    static func main() {
        OpenOatsRootApp.run(
            profileRegistry: KnowledgeDomainProfileRegistry(
                profiles: [HospitalityDomainProfile()]
            )
        )
    }
}
