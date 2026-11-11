import SwiftUI

struct TeamsSetupSheet: View {
    @ObservedObject var vm: StudioViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(StudioTheme.accentCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect VoiceStudio to Microsoft Teams")
                        .font(.system(size: 17, weight: .bold))
                    Text("One-time 10-second setup — your Mac Already Has BlackHole 2ch Installed")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                stepRow(
                    num: "1",
                    title: "Keep VoiceStudio Output set to 'BlackHole 2ch'",
                    detail: vm.isBlackHoleSelected
                        ? "Active right now: \(vm.selectedInputName) → Studio DSP → BlackHole 2ch."
                        : "Select 'BlackHole 2ch' in VoiceStudio's Teams Output dropdown."
                )

                stepRow(
                    num: "2",
                    title: "In Microsoft Teams → Settings → Devices",
                    detail: "Set Microphone to 'BlackHole 2ch'. Keep Teams Speaker set to your normal Speakers or Headphones (never BlackHole)."
                )

                stepRow(
                    num: "3",
                    title: "Turn Off Teams 'Voice Isolation' Over-Processing (Optional Tip)",
                    detail: "Set Teams Noise Suppression to 'Low' or 'Off' if you want your full warm studio low-end and crisp 10 kHz condenser air preserved."
                )
            }

            HStack {
                Spacer()
                Button("Got It") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func stepRow(num: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 24, height: 24)
                .background(StudioTheme.accentCyan.opacity(0.2))
                .foregroundStyle(StudioTheme.accentCyan)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
