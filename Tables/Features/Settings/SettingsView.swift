import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ZStack {
                Color.canvas.ignoresSafeArea()

                VStack(spacing: Metrics.space2 + 2) {
                    Card {
                        VStack(spacing: 0) {
                            toggleRow("Sound", isOn: $settings.soundEnabled)
                            Divider().overlay(Color.divider)
                            toggleRow("Haptics", isOn: $settings.hapticsEnabled)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Metrics.space3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Multiple choice options")
                                    .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                                    .foregroundStyle(Color.ink)
                                Text("How many tiles to choose between.")
                                    .font(Typography.ui(12, relativeTo: .caption))
                                    .foregroundStyle(Color.inkSoft)
                            }

                            HStack(spacing: Metrics.space2) {
                                ForEach(AppSettings.optionCountChoices, id: \.self) { count in
                                    Chip(
                                        "\(count)",
                                        isSelected: settings.multipleChoiceOptionCount == count
                                    ) {
                                        settings.multipleChoiceOptionCount = count
                                    }
                                }
                            }
                        }
                        .padding(Metrics.space4)
                    }

                    Spacer()
                }
                .padding(.horizontal, Metrics.space5 + 2)
                .padding(.top, Metrics.space5)
                .frame(maxWidth: Metrics.contentMaxWidth)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Typography.ui(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.skyText)
                }
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.ink)
        }
        .tint(Color.sage)
        .padding(Metrics.space4)
    }
}
