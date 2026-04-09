import SwiftUI
import MapKit

// MARK: - Address Search ViewModel

@Observable
final class AddressSearchViewModel: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String) {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
            isSearching = false
        } else {
            isSearching = true
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(5))
        isSearching = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
        isSearching = false
    }

    /// Resolve a completion into structured address fields
    func resolve(_ completion: MKLocalSearchCompletion) async -> (street: String, city: String, state: String, zip: String)? {
        let request = MKLocalSearch.Request(completion: completion)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let placemark = response.mapItems.first?.placemark else { return nil }
            let street: String = {
                var parts: [String] = []
                if let num = placemark.subThoroughfare { parts.append(num) }
                if let name = placemark.thoroughfare { parts.append(name) }
                return parts.joined(separator: " ")
            }()
            return (
                street: street,
                city:   placemark.locality ?? placemark.subAdministrativeArea ?? "",
                state:  placemark.administrativeArea ?? "",
                zip:    placemark.postalCode ?? ""
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Address Autocomplete Field (for NewClientForm)

struct AddressAutocompleteTF: View {
    let label: String
    @Binding var street: String
    @Binding var city: String
    @Binding var state: String
    @Binding var zip: String

    @State private var vm = AddressSearchViewModel()
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isFocused ? Color.sweeplyAccent : Color.sweeplyTextSub)
                    .animation(.easeOut(duration: 0.15), value: isFocused)

                TextField("123 Main St", text: $street)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isFocused ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: 1)
                    )
                    .onChange(of: street) { _, newValue in
                        if isFocused {
                            vm.search(newValue)
                            showSuggestions = !newValue.isEmpty
                        }
                    }
            }

            // Suggestions dropdown
            if showSuggestions && !vm.results.isEmpty && isFocused {
                VStack(spacing: 0) {
                    ForEach(vm.results, id: \.self) { result in
                        Button {
                            Task {
                                if let resolved = await vm.resolve(result) {
                                    street = resolved.street.isEmpty ? result.title : resolved.street
                                    if !resolved.city.isEmpty  { city  = resolved.city  }
                                    if !resolved.state.isEmpty { state = resolved.state }
                                    if !resolved.zip.isEmpty   { zip   = resolved.zip   }
                                }
                                showSuggestions = false
                                isFocused = false
                                vm.results = []
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.sweeplyAccent)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.sweeplyNavy)
                                        .lineLimit(1)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if result != vm.results.last {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeOut(duration: 0.15), value: vm.results.count)
                .zIndex(100)
            }
        }
    }
}

// MARK: - Settings Address Autocomplete Field

/// Variant for SettingsView that binds directly to settings properties
struct SettingsAddressField: View {
    let label: String
    @Binding var street: String
    @Binding var city: String
    @Binding var state: String
    @Binding var zip: String

    @State private var vm = AddressSearchViewModel()
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)

                TextField("", text: $street)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.sweeplyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(isFocused ? Color.sweeplyAccent : Color.sweeplyBorder, lineWidth: 1))
                    .onChange(of: street) { _, newValue in
                        if isFocused {
                            vm.search(newValue)
                            showSuggestions = !newValue.isEmpty
                        }
                    }
            }

            if showSuggestions && !vm.results.isEmpty && isFocused {
                VStack(spacing: 0) {
                    ForEach(vm.results, id: \.self) { result in
                        Button {
                            Task {
                                if let resolved = await vm.resolve(result) {
                                    street = resolved.street.isEmpty ? result.title : resolved.street
                                    if !resolved.city.isEmpty  { city  = resolved.city  }
                                    if !resolved.state.isEmpty { state = resolved.state }
                                    if !resolved.zip.isEmpty   { zip   = resolved.zip   }
                                }
                                showSuggestions = false
                                isFocused = false
                                vm.results = []
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.sweeplyAccent)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.sweeplyNavy)
                                        .lineLimit(1)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if result != vm.results.last {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.sweeplyBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeOut(duration: 0.15), value: vm.results.count)
                .zIndex(100)
            }
        }
    }
}

// MARK: - US State Picker

private let usStates: [String] = [
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC"
]

/// A tappable state field that opens a compact picker sheet.
/// Styled to match FormTextField (used in NewClientForm).
struct StatePickerField: View {
    let label: String
    @Binding var state: String
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showPicker = true
            } label: {
                HStack {
                    Text(state.isEmpty ? "State" : state)
                        .font(.system(size: 15))
                        .foregroundStyle(state.isEmpty ? Color.sweeplyTextSub : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) {
            StatePickerSheet(selected: $state)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Variant styled to match SettingsField (used in SettingsView).
struct SettingsStatePickerField: View {
    let label: String
    @Binding var state: String
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyTextSub)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showPicker = true
            } label: {
                HStack {
                    Text(state.isEmpty ? "State" : state)
                        .font(.system(size: 15))
                        .foregroundStyle(state.isEmpty ? Color.sweeplyTextSub : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.sweeplyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) {
            StatePickerSheet(selected: $state)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct StatePickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty ? usStates : usStates.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { abbr in
                Button {
                    selected = abbr
                    dismiss()
                } label: {
                    HStack {
                        Text(abbr)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        if selected == abbr {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sweeplyAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search states")
            .navigationTitle("Select State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }
}
