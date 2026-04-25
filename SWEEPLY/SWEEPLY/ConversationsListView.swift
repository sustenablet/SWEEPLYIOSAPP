import SwiftUI

struct ConversationsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MessagesStore.self) private var messagesStore
    @Environment(AppSession.self) private var session
    @Environment(ClientsStore.self) private var clientsStore

    @State private var selectedConversation: Conversation? = nil
    @State private var isLoading = true
    @State private var selectedClientForChat: Client? = nil
    @State private var searchText = ""
    @State private var showNewChat = false

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return messagesStore.conversations
        }
        return messagesStore.conversations.filter { $0.clientName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messagesStore.conversations.isEmpty && searchText.isEmpty {
                    noConversationsView
                } else if filteredConversations.isEmpty && !searchText.isEmpty {
                    noSearchResultsView
                } else {
                    conversationList
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations")
            .sheet(item: $selectedConversation) { conv in
                if let client = clientsStore.clients.first(where: { $0.id == conv.clientId }) {
                    ClientChatView(client: client)
                        .environment(messagesStore)
                        .environment(session)
                }
            }
            .sheet(item: $selectedClientForChat) { client in
                ClientChatView(client: client)
                    .environment(messagesStore)
                    .environment(session)
            }
            .sheet(isPresented: $showNewChat) {
                NewChatSheet(onSelect: { client in
                    selectedClientForChat = client
                    showNewChat = false
                })
                .environment(clientsStore)
            }
            .task {
                if let userId = session.userId {
                    await messagesStore.loadConversations(userId: userId)
                }
                isLoading = false
            }
            .refreshable {
                if let userId = session.userId {
                    await messagesStore.loadConversations(userId: userId)
                }
            }
        }
    }

    // MARK: - No Search Results

    private var noSearchResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
            Text("No conversations found")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
            Text("Try searching for a different client.")
                .font(.system(size: 13))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
        }
    }

    // MARK: - No Conversations View

    private var noConversationsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyNavy.opacity(0.08))
                            .frame(width: 80, height: 80)
                        Image(systemName: "message.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Color.sweeplyNavy.opacity(0.4))
                    }
                    VStack(spacing: 6) {
                        Text("No conversations yet")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("Start a conversation with a client.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Clients")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .padding(.horizontal, 20)

                    let activeClients = clientsStore.clients.filter { $0.isActive }
                    if activeClients.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                            Text("No clients yet")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(activeClients) { client in
                                Button {
                                    selectedClientForChat = client
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.sweeplyNavy)
                                                .frame(width: 40, height: 40)
                                            Text(String(client.name.prefix(1)).uppercased())
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(client.name)
                                                .font(.system(size: 14, weight: .semibold))
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

                                if client.id != activeClients.last?.id {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sweeplyBorder, lineWidth: 1))
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - List

    private var conversationList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredConversations) { conv in
                    ConversationRow(conversation: conv) {
                        selectedConversation = conv
                    }
                    Divider().padding(.leading, 68)
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

// MARK: - Conversation Row

private struct ConversationRow: View {
    let conversation: Conversation
    let onTap: () -> Void

    private var initials: String {
        conversation.clientName
            .split(separator: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .prefix(2)
            .joined()
            .uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy)
                        .frame(width: 44, height: 44)
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    if conversation.unreadCount > 0 {
                        Circle()
                            .fill(Color.sweeplyAccent)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Text("\(min(conversation.unreadCount, 9))")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 16, y: -16)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(conversation.clientName)
                            .font(.system(size: 14, weight: conversation.unreadCount > 0 ? .bold : .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Text(conversation.lastMessageAt, format: .relative(presentation: .named))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    }
                    HStack(spacing: 6) {
                        if let last = conversation.lastMessage {
                            Text(last)
                                .font(.system(size: 13))
                                .foregroundStyle(conversation.unreadCount > 0 ? Color.sweeplyNavy : Color.sweeplyTextSub)
                                .lineLimit(1)
                        } else {
                            Text("No messages yet")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                        }
                        Spacer()
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyBorder)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

extension Conversation: @retroactive Hashable {
    public static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
