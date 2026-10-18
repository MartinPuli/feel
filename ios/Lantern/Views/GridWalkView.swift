import SwiftUI
import FeelCore

/// Full-screen grid with no camera image, for walking a space by the pin grid alone (no puck needed).
/// Hold the phone landscape-left, upright at chest height, camera facing forward, and look only at
/// the screen while a spotter walks beside you. Trials record depth (and camera video if enabled)
/// so each walk can be replayed on /replay with its bump and arrival marks.
struct GridWalkView: View {
    @ObservedObject var model: LanternModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                leftRail.frame(width: 132)
                ZStack {
                    grid(size: geometry.size)
                    if model.mode == .simulation {
                        Text("SIMULATION · synthetic scene").font(FeelTypography.caption).foregroundStyle(.white.opacity(0.6))
                            .frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
                    } else if model.guidanceState != .live { noGuidance }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightRail.frame(width: 132)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { if model.mode == .stopped && !model.isStarting { model.startLive() } }
    }

    // MARK: Grid

    private func grid(size: CGSize) -> some View {
        let bands = model.packet.bands, highlight = model.packet.effectiveHighlight
        let pin = min((size.width - 264 - 6 * 14 - 48) / 7, (size.height - 70) / 4 - 14)
        return VStack(spacing: 14) {
            ForEach((1...4).reversed(), id: \.self) { band in
                HStack(spacing: 14) {
                    ForEach(0..<7, id: \.self) { column in
                        let up = bands.indices.contains(column) && Int(bands[column]) == band
                        let tapping = up && (Int(highlight) == column || model.targetColumns?.contains(column) == true)
                        Circle()
                            .fill(up ? (band == 1 ? Color(red: 1, green: 0.42, blue: 0.17) : Color.white) : Color.white.opacity(0.08))
                            .overlay(Circle().strokeBorder(Color.white.opacity(up ? 0 : 0.18), lineWidth: 1.5))
                            .overlay(tapping ? Circle().strokeBorder(Color(red: 0.32, green: 0.66, blue: 1), lineWidth: 5).padding(-9) : nil)
                            .frame(width: pin, height: pin)
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(["L3", "L2", "L1", "C", "R1", "R2", "R3"], id: \.self) { label in
                    Text(label).font(FeelTypography.caption).foregroundStyle(.white.opacity(0.45)).frame(width: pin)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.06), value: model.packet.bands)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pin grid")
        .accessibilityValue(bands.enumerated().map { "column \($0.offset + 1) \($0.element == 0 ? "down" : "band \($0.element)")" }.joined(separator: ", "))
    }

    private var noGuidance: some View {
        VStack(spacing: 10) {
            Text("NO GUIDANCE").font(FeelTypography.title2)
            Text(reason).font(FeelTypography.subheadline).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            if model.mode == .live && !model.calibrated {
                Button(String(format: "Calibrate floor (%.2f m)", model.cameraHeight)) { model.calibrate() }
                    .buttonStyle(FeelPrimaryButtonStyle()).frame(maxWidth: 280)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.16).opacity(0.94))
        .accessibilityElement(children: .combine)
    }

    private var reason: String {
        switch model.guidanceState {
        case .uncalibrated: return "Stand still, phone upright at chest height, then calibrate."
        case .trackingLost: return "Tracking lost. Stop and hold still."
        case .staleDepth: return model.mode == .live ? "Waiting for depth. Stop until the grid returns." : "Camera is off."
        default: return model.status
        }
    }

    // MARK: Trial rails (thumb reach in landscape)

    private var leftRail: some View {
        VStack(spacing: 12) {
            Button { model.stopGridWalk(); dismiss() } label: { Image(systemName: "xmark").frame(width: 52, height: 52) }
                .background(Color.white.opacity(0.1), in: Circle())
                .accessibilityLabel("Close grid walk")
            Spacer()
            if model.trialStart != nil {
                railButton("Bump", systemImage: "exclamationmark.triangle.fill", tint: Color(red: 1, green: 0.42, blue: 0.17)) { model.markTrial("bump") }
                    .accessibilityHint("Marks a contact with an obstacle at this moment.")
                railButton("Unsure", systemImage: "questionmark", tint: .white.opacity(0.18)) { model.markTrial("hesitated") }
            }
            Spacer()
        }
        .padding(.vertical, 18)
    }

    private var rightRail: some View {
        VStack(spacing: 12) {
            if let start = model.trialStart {
                TimelineView(.periodic(from: start, by: 0.1)) { context in
                    Text(String(format: "%.1f s", context.date.timeIntervalSince(start))).font(FeelTypography.mono).monospacedDigit()
                }
                Text("\(model.trialEvents.filter { $0.kind == "bump" }.count) bumps").font(FeelTypography.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                railButton("Arrived", systemImage: "flag.checkered", tint: Color(red: 0.25, green: 0.81, blue: 0.5)) { model.endTrial("arrived") }
                railButton("End", systemImage: "stop.fill", tint: .white.opacity(0.18)) { model.endTrial("ended") }
            } else {
                Spacer()
                railButton("Start trial", systemImage: "record.circle", tint: Color(red: 0.32, green: 0.66, blue: 1)) { model.startTrial() }
                    .disabled(model.mode != .live)
                    .accessibilityHint("Records depth and camera for replay and starts the timer.")
                if let summary = model.lastTrialSummary {
                    Text(summary).font(FeelTypography.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding(.vertical, 18)
    }

    private func railButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(); action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 22, weight: .semibold))
                Text(title).font(FeelTypography.label)
            }
            .frame(width: 108, height: 92)
            .background(tint, in: RoundedRectangle(cornerRadius: 18))
        }
        .foregroundStyle(.white)
    }
}
