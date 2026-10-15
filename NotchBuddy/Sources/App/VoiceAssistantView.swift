import SwiftUI

// MARK: - Voice assistant island view

struct VoiceAssistantView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .cyan)

            VStack(alignment: .leading, spacing: 0) {
                // Phase header
                HStack(spacing: 6) {
                    Image(systemName: phaseIcon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(phaseColor)
                    Text(phaseLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(phaseColor)
                    if state.voicePhase == .responding {
                        SpeakingPulsingIndicator()
                    }
                    Spacer()
                    // Dismiss
                    Button {
                        VoiceCoordinator.shared.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color(hex: "#5F646D"))
                            .frame(width: 14, height: 14)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)

                // Live content
                switch state.voicePhase {
                case .listening:
                    WaveformBarsView(level: state.voiceAudioLevel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .padding(.bottom, 6)
                    Text(state.voiceTranscript.isEmpty ? "Listening… speak to Cruno" : "\"\(state.voiceTranscript)\"")
                        .font(.system(size: 11))
                        .foregroundColor(state.voiceTranscript.isEmpty ? Color(hex: "#8E939C") : Color(hex: "#E8ECF0"))
                        .lineLimit(2)
                case .thinking:
                    VoiceDotsView()
                        .frame(height: 28)
                        .padding(.bottom, 6)
                    Text(state.voiceTranscript.isEmpty ? "Thinking…" : "\"\(state.voiceTranscript)\"")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(2)
                case .responding, .idle:
                    ScrollView(showsIndicators: false) {
                        Text(state.voiceResponse.isEmpty ? "…" : state.voiceResponse)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#E8ECF0"))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 80)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 78)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
        .animation(.easeInOut(duration: 0.18), value: state.voicePhase)
    }

    private var phaseLabel: String {
        switch state.voicePhase {
        case .listening:  "Listening"
        case .thinking:   "Thinking"
        case .responding: "Cruno"
        case .idle:       "Done"
        }
    }

    private var phaseIcon: String {
        switch state.voicePhase {
        case .listening:  "waveform"
        case .thinking:   "ellipsis"
        case .responding: "sparkles"
        case .idle:       "checkmark"
        }
    }

    private var phaseColor: Color {
        switch state.voicePhase {
        case .listening:  Color(hex: "#22D3A0")
        case .thinking:   Color(hex: "#A78BFA")
        case .responding: Color(hex: "#4ADEBD")
        case .idle:       Color(hex: "#6B7280")
        }
    }
}

// MARK: - Waveform bars (audio level + living wave driven)

struct WaveformBarsView: View {
    let level: Float

    private let barCount = 18

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let barW: CGFloat = max(3, (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let phase = Double(i) * 0.55
                        let wave = (sin(time * 6.0 + phase) + 1.0) * 0.5 // 0.0 ... 1.0
                        let idleH: CGFloat = 5.0 + CGFloat(wave) * 12.0   // 5 ... 17pt living idle wave
                        let center = CGFloat(barCount - 1) / 2.0
                        let centerDist = abs(CGFloat(i) - center) / center
                        let voiceBoost: CGFloat = CGFloat(min(1.0, max(0.0, level))) * 24.0 * (1.0 - centerDist * 0.4)
                        let totalH = min(geo.size.height, max(5.0, idleH + voiceBoost))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#22D3A0"), Color(hex: "#4ADEBD")],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .frame(width: barW, height: totalH)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Typing dots

struct VoiceDotsView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let offset = sin(time * 6.0 - Double(i) * 0.8) * 4.0
                    Circle()
                        .fill(Color(hex: "#A78BFA"))
                        .frame(width: 5, height: 5)
                        .offset(y: CGFloat(offset))
                }
            }
        }
    }
}

// MARK: - Responding mini audio indicator

struct SpeakingPulsingIndicator: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let h = 4.0 + (sin(time * 8.0 + Double(i) * 1.2) + 1.0) * 3.0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: "#4ADEBD"))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
            .frame(height: 12)
        }
    }
}
