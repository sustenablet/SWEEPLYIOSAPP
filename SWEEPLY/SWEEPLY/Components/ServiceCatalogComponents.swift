import SwiftUI

struct ServiceCatalogRow: View {
    let service: BusinessService
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(service.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .lineLimit(1)
                    if service.isAddon {
                        Text("+ EXTRA")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.sweeplyAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.sweeplyAccent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                Text(service.price.currency)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
            }

            Spacer()

            Button("Edit", action: onEdit)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.sweeplyBackground)
                .clipShape(Capsule())

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyDestructive)
                    .frame(width: 30, height: 30)
                    .background(Color.sweeplyDestructive.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.sweeplyBorder, lineWidth: 1)
        )
    }
}

struct ServiceCatalogEditorState: Identifiable {
    let id = UUID()
    let serviceID: UUID?
    var name: String
    var priceText: String
    var isAddon: Bool
    var lockedAddon: Bool?

    var isEditing: Bool { serviceID != nil }

    init(service: BusinessService? = nil, defaultAddon: Bool = false, lockedAddon: Bool? = nil) {
        self.serviceID = service?.id
        self.name = service?.name ?? ""
        self.isAddon = service?.isAddon ?? defaultAddon
        self.lockedAddon = lockedAddon
        if let price = service?.price {
            self.priceText = price == floor(price) ? "\(Int(price))" : String(format: "%.2f", price)
        } else {
            self.priceText = ""
        }
    }
}

struct ServiceCatalogEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ServiceCatalogEditorState
    let onSave: (ServiceCatalogEditorState) -> Void

    init(
        state: ServiceCatalogEditorState,
        onSave: @escaping (ServiceCatalogEditorState) -> Void
    ) {
        _draft = State(initialValue: state)
        self.onSave = onSave
    }

    private var canSave: Bool {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        Double(draft.priceText) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Service Name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    TextField("Deep Clean", text: $draft.name)
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.sweeplyBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Price")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                    HStack(spacing: 10) {
                        Text("$")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.sweeplyNavy)
                        TextField("150", text: $draft.priceText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                    )
                }

                // Extra cost toggle — hidden when type is locked by context
                if draft.lockedAddon == nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { draft.isAddon.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Extra Cost")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyNavy)
                                Text("Add-on charged on top of the main service")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                            Spacer()
                            ZStack {
                                Capsule()
                                    .fill(draft.isAddon ? Color.sweeplyAccent : Color.sweeplyBorder)
                                    .frame(width: 44, height: 26)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 20, height: 20)
                                    .offset(x: draft.isAddon ? 9 : -9)
                            }
                            .animation(.easeInOut(duration: 0.15), value: draft.isAddon)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.sweeplyBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(draft.isAddon ? Color.sweeplyAccent.opacity(0.4) : Color.sweeplyBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.sweeplySurface.ignoresSafeArea())
            .navigationTitle(draft.isEditing ? "Edit Service" : "New Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .foregroundStyle(Color.sweeplyNavy)
                    .disabled(!canSave)
                }
            }
        }
    }
}
