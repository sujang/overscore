import SwiftUI

struct ContentView: View {
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            MatchListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .sportSelect:
                        SportSelectView()
                    case .matchSetup(let sportType):
                        MatchSetupView(sportType: sportType)
                    case .resumeMatchSetup:
                        if let draft = MatchDraftStore.load() {
                            MatchSetupView(sportType: draft.sportType, restoring: draft)
                        } else {
                            SportSelectView()
                        }
                    case .scoreEditor(let match):
                        ScoreEditorView(match: match)
                    case .matchDetail(let match):
                        MatchDetailView(match: match)
                    case .export(let match):
                        ExportView(match: match)
                    }
                }
        }
        .environment(router)
    }
}
