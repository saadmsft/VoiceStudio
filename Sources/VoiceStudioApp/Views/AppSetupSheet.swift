import SwiftUI

struct AppSetupSheet: View {
    @ObservedObject var vm: StudioViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(StudioTheme.accentCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect VoiceStudio to Any macOS App")
                        .font(.system(size: 17, weight: .bold))
                    Text(vm.isBlackHoleSelected
                         ? "Active: \(vm.selectedInputName) → Studio DSP → BlackHole 2ch"
                         : "Select 'BlackHole 2ch' in Virtual Mic Output, then pick it inside any app below")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                appRow(
                    badge: "Discord",
                    title: "Settings → Voice & Video → Input Device: 'BlackHole 2ch'",
                    detail: "Keep Output Device on your Headphones/Speakers. Turn OFF Krisp Noise Suppression & Echo Cancellation if you want full warm sub-bass & 10 kHz studio air."
                )

                appRow(
                    badge: "Zoom",
                    title: "Settings → Audio → Microphone: 'BlackHole 2ch'",
                    detail: "Enable 'Original Sound for Musicians' (High-Fidelity Music Mode off) for uncompressed studio broadcast tone."
                )

                appRow(
                    badge: "Teams",
                    title: "Settings → Devices → Microphone: 'BlackHole 2ch'",
                    detail: "Set Noise Suppression to 'Low' or 'Off' so your 125 Hz chest warmth and crisp condenser sheen aren't filtered out."
                )

                appRow(
                    badge: "Slack / Meet",
                    title: "Audio & Video Settings → Microphone: 'BlackHole 2ch'",
                    detail: "Works across Slack Huddles, Google Meet, Webex, WhatsApp, Telegram, FaceTime, and Steam Voice."
                )

                appRow(
                    badge: "OBS / DAWs",
                    title: "Audio Input Capture / Mic Aux → 'BlackHole 2ch'",
                    detail: "Stream or record studio-ready vocals directly in OBS Studio, Twitch Studio, QuickTime, Riverside, Descript, Logic Pro, or Audacity."
                )
            }

            HStack {
                Text("Never set an app's Speaker / Output to BlackHole 2ch — always keep Speakers on your normal headphones or monitors.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Got It") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580)
    }

    private func appRow(badge: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(badge)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 82, height: 24)
                .background(StudioTheme.accentCyan.opacity(0.18))
                .foregroundStyle(StudioTheme.accentCyan)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
