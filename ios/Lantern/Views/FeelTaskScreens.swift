import SwiftUI
import FeelCore

enum FeelTask: String, CaseIterable, Identifiable {
    case surroundings, find, places
    var id: String { rawValue }
    var title: String {
        switch self {
        case .surroundings: return "Surroundings"
        case .find: return "Find"
        case .places: return "My places"
        }
    }
    var symbol: String {
        switch self {
        case .surroundings: return "viewfinder"
        case .find: return "magnifyingglass"
        case .places: return "mappin.and.ellipse"
        }
    }
    var identifier: String { "task_" + rawValue }
}

struct FeelTaskHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.compact) {
            Text(title).font(FeelTypography.title2).accessibilityAddTraits(.isHeader)
            Text(detail).font(FeelTypography.body).foregroundStyle(FeelTheme.secondary)
        }
    }
}

/// Searches dispatch the existing validated commands; this screen never manufactures detections.
struct FeelFindScreen: View {
    @ObservedObject var model: LanternModel
    @Binding var query: String
    @AccessibilityFocusState.Binding var commandsFocused: Bool
    var wide: Bool
    let openLocalCommands: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var requestResult = ""
    @State private var typeRequestExpanded = false
    @State private var showsResult = false
    @State private var resultDetail = ""
    @FocusState private var queryFocused: Bool
    private let targets: [FinderMode] = [.person, .exit, .door, .chair, .barcode, .teammate]

    var body: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: 180), spacing: FeelSpacing.section)], spacing: FeelSpacing.section) {
                ForEach(targets) { target in
                    Button { select(target) } label: {
                        HStack {
                            Text(target.rawValue)
                            Spacer(minLength: 4)
                            if model.finder == target { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .disabled(model.mode != .live || (target == .chair && !model.detectorAvailable))
                    .accessibilityAddTraits(model.finder == target ? [.isSelected] : [])
                    .accessibilityHint(targetHint(target))
                    .accessibilityIdentifier("find_" + String(describing: target))
                }
            }
            if model.mode == .live {
                Button("Stop finding") { select(.none) }.buttonStyle(FeelSecondaryButtonStyle())
                    .accessibilityIdentifier("stopFinding")
            }
            Button("Result") {
                queryFocused = false
                resultDetail = resultMessage
                showsResult = true
            }
            .buttonStyle(FeelSecondaryButtonStyle())
            .accessibilityLabel("Search result")
            .accessibilityValue(resultMessage)
            .accessibilityHint("Opens the full current result. A match does not confirm identity or a clear path.")
            .accessibilityIdentifier("findResult")
            Button { typeRequestExpanded.toggle() } label: {
                Label("Type a request", systemImage: typeRequestExpanded ? "chevron.up" : "chevron.down")
            }.buttonStyle(FeelSecondaryButtonStyle())
            .accessibilityIdentifier("typeFindRequest")
            .accessibilityValue(typeRequestExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Enter an object or place to look for with the live camera.")
            if typeRequestExpanded { searchForm }
            Button("Local commands", action: openLocalCommands)
                .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("openLocalCommands")
                .accessibilityHint("Type or speak a command processed on this iPhone.")
                .accessibilityFocused($commandsFocused)
            DisclosureGroup {
                Text("FEEL can look for a type of object; a match does not identify it as yours. A door candidate is a visual shape, not a confirmed passage. Remembered locations may have changed. Some searches and descriptions need a configured online service.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                    .padding(.top, 8)
            } label: {
                Text("About recognition").font(FeelTypography.label).frame(minHeight: 44)
            }
        }
        .alert("Search result", isPresented: $showsResult) {
            if model.mode != .stopped || model.isStarting {
                Button("Stop sensing", role: .destructive) { model.stop() }
            }
            Button("Close", role: .cancel) {}
        } message: { Text(resultDetail) }
        .onChange(of: model.whereIsNotice) { notice in
            if let notice { UIAccessibility.post(notification: .announcement, argument: notice) }
        }
        .onChange(of: model.mode) { mode in
            if mode != .live { requestResult = "" }
        }
        .onChange(of: typeRequestExpanded) { expanded in
            if !expanded { queryFocused = false }
        }
    }

    private var availabilityMessage: String {
        model.mode == .simulation ? "Recognition needs the live camera."
            : model.mode == .stopped ? "Start the camera to search."
            : "Waiting for fresh sensing."
    }

    private var resultMessage: String {
        var messages: [String] = []
        if let notice = model.whereIsNotice { messages.append(notice) }
        else if !requestResult.isEmpty { messages.append(requestResult) }
        if model.mode == .live { messages.append(model.targetDescription) }
        if !model.whereIsAvailable { messages.append(availabilityMessage) }
        return messages.isEmpty ? "No search result yet." : messages.joined(separator: " ")
    }

    private func targetHint(_ target: FinderMode) -> String {
        if model.mode != .live { return "Start the live camera to search." }
        if target == .chair && !model.detectorAvailable { return "Local chair recognition is unavailable in this build." }
        return "Searches for this type of target. A match does not confirm identity or a clear path."
    }

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.compact) {
            TextField("For example, a chair", text: $query)
                .feelField().submitLabel(.search)
                .focused($queryFocused).onSubmit(findRequestedObject)
                .accessibilityLabel("Object to find").accessibilityIdentifier("findQuery")
                .id("findQuery")
            Button(action: findRequestedObject) { Label("Find", systemImage: "magnifyingglass") }
                .buttonStyle(FeelPrimaryButtonStyle())
                .disabled(!model.whereIsAvailable || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint(!model.whereIsAvailable ? availabilityMessage
                                   : query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter what you want to find first."
                                   : "Looks for the requested object or place. A match does not confirm identity or a clear path.")
                .accessibilityIdentifier("findRequestedObject")
        }
    }

    private func findRequestedObject() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        queryFocused = false
        guard model.whereIsAvailable, !value.isEmpty else { return }
        let result = model.performVoiceCommand(.whereIs(value))
        requestResult = result["error"] as? String
            ?? (result["remembered"] as? Bool == true ? result["status"] as? String : nil)
            ?? "Looking for \(value). This is not a confirmed match yet."
        UIAccessibility.post(notification: .announcement, argument: requestResult)
    }

    private func select(_ target: FinderMode) {
        queryFocused = false
        let result = model.performVoiceCommand(.find(target))
        requestResult = result["error"] as? String
            ?? (target == .none ? "Object finding stopped. Frontal sensing continues."
                : "Searching for \(target.rawValue.lowercased()). No match confirmed yet.")
        UIAccessibility.post(notification: .announcement, argument: requestResult)
    }
}
