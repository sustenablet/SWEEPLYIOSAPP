import SwiftUI

struct ConversationsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MessagesStore.self) private var messagesStore
    @Environment(AppSession.self) private var session
    @Environment(ClientsStore.self) private var clientsStore

    @State private var selectedConversation: Conversation? = nil
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messagesStore.conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }
            .sheet(item: $selectedConversation) { conv in
                if let client = clientsStore.clients.first(where: { $0.id == conv.clientId }) {
                    ClientChatView(client: client)
                        .environment(messagesStore)
                        .environment(session)
                }
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

    // MARK: - List

    private var conversationList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(messagesStore.conversations) { conv in
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
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
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
                Text("Open a client and tap Message to start a conversation.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
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
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(conversation.clientName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        Text(conversation.lastMessageAt, format: .relative(presentation: .named))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                    }
                    if let last = conversation.lastMessage {
                        Text(last)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .lineLimit(1)
                    } else {
                        Text("No messages yet")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
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
