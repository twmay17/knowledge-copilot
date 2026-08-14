import HospitalityDomainProfile
import SwiftUI
import OpenOatsKit

@main
struct OpenOatsApp: App {
    var body: some Scene {
        OpenOatsRootApp(
            profileRegistry: KnowledgeDomainProfileRegistry(
                profiles: [HospitalityDomainProfile()]
            )
        ).body
    }
}
