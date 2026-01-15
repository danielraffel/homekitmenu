import SwiftUI

/// A row displaying a single HomeKit accessory with toggle control
struct AccessoryRow: View {
    let accessory: HomeAccessory
    let customIcon: String?
    let onToggle: () -> Void

    private var effectiveIcon: String {
        customIcon ?? accessory.type.icon
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: effectiveIcon)
                    .font(.title2)
                    .foregroundStyle(accessory.isOn ? .yellow : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accessory.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if let room = accessory.roomName {
                        Text(room)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Circle()
                    .fill(accessory.isOn ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row for selecting accessories in preferences with icon customization
struct AccessorySelectionRow: View {
    let accessory: HomeAccessory
    let isSelected: Bool
    let customIcon: String?
    let onToggle: () -> Void
    let onIconChange: (String?) -> Void

    @State private var showingIconPicker = false

    private var effectiveIcon: String {
        customIcon ?? accessory.type.icon
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                showingIconPicker = true
            } label: {
                Image(systemName: effectiveIcon)
                    .font(.title3)
                    .foregroundStyle(customIcon != nil ? .blue : .secondary)
                    .frame(width: 28)
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(accessory.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        if let room = accessory.roomName {
                            Text(room)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(accessory.type.rawValue)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(
                accessoryName: accessory.name,
                currentIcon: effectiveIcon,
                onSelect: { icon in
                    onIconChange(icon == accessory.type.icon ? nil : icon)
                    showingIconPicker = false
                }
            )
        }
    }
}

/// Icon picker sheet
struct IconPickerView: View {
    let accessoryName: String
    let currentIcon: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 60))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(HomeAccessory.AccessoryType.availableIcons, id: \.icon) { item in
                        Button {
                            onSelect(item.icon)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.title)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(currentIcon == item.icon ? Color.blue.opacity(0.2) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(currentIcon == item.icon ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                                Text(item.label)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(currentIcon == item.icon ? .blue : .primary)
                    }
                }
                .padding()
            }
            .navigationTitle("Icon for \(accessoryName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 350, minHeight: 400)
        #endif
    }
}
