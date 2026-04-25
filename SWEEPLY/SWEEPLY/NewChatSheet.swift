import SwiftUI

struct NewChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClientsStore.self) private var clientsStore
    
    let onSelect: (Client) -> Void
    
    @State private var searchText = ""
    
    private var filteredClients: [Client] {
        let active = clientsStore.clients.filter { $0.isActive }
        if searchText.isEmpty {
            return active.sorted { $0.name < $1.name }
        }
        return active
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if clientsStore.clients.isEmpty {
                    emptyState
                } else if filteredClients.isEmpty && !searchText.isEmpty {
                    noResultsState
                } else {
                    clientList
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            .searchable(text: $searchText, prompt: "Search clients")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 32))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text("No clients yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text("Add a client first to start messaging.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
        }
    }
    
    private var noResultsState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text("No clients found")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Spacer()
        }
    }
    
    private var clientList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredClients) { client in
                    Button {
                        onSelect(client)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.sweeplyNavy)
                                    .frame(width: 44, height: 44)
                                Text(String(client.name.prefix(1)).uppercased())
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(client.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.sweeplyNavy)
                                if !client.phone.isEmpty {
                                    Text(client.phone)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sweeplyBorder)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    
                    if client.id != filteredClients.last?.id {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sweeplyBorder, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }
}