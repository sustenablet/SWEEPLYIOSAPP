import SwiftUI

struct ClientChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MessagesStore.self) private var messagesStore
    @Environment(AppSession.self) private var session

    let client: Client

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var conversation: Conversation? = nil
@FocusState private var isInputFocused: Bool

    private let templates = [
        "On my way 🚗",
        "Running 15 min late ⏱",
        "Arriving now 📍",
        "Cleaning complete ✅",
        "Invoice sent 📄",
        "Payment received 💳",
        "Thanks! See you next time 👋",
        "Can we reschedule?",
        "Reminder: appointment tomorrow ⏰",
        "Confirming for tomorrow ✅"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                if !isInputFocused && inputText.isEmpty && !messages.isEmpty || messages.isEmpty {
                    templateChips
                }

                inputBar
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(client.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        if !client.phone.isEmpty {
                            Text(client.phone)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !client.phone.isEmpty {
                        Button {
                            if let url = URL(string: "tel://\(client.phone.filter { $0.isNumber })") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.sweeplyAccent)
                        }
                    }
                }
            }
            .task {
                await setupConversation()
                if let conv = conversation {
                    await messagesStore.markAsRead(conversationId: conv.id)
                }
            }
        }
    }

    // MARK: - Setup

    private func setupConversation() async {
        guard let userId = session.userId else { isLoading = false; return }
        let conv = await messagesStore.getOrCreateConversation(
            clientId: client.id,
            clientName: client.name,
            clientPhone: client.phone,
            userId: userId
        )
        self.conversation = conv
        if let conv {
            messages = await messagesStore.loadMessages(conversationId: conv.id)
        }
        isLoading = false
    }

    // MARK: - Send

    private func send() {
        let body = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let conv = conversation, let userId = session.userId else { return }
        inputText = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            if let saved = await messagesStore.sendMessage(body: body, conversationId: conv.id, userId: userId, direction: .outgoing) {
                withAnimation(.easeOut(duration: 0.2)) {
                    messages.append(saved)
                }
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
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
                Text("No messages yet")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("Start a conversation with \(client.name).")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    // MARK: - Template Chips

    private var templateChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(templates, id: \.self) { t in
                    Button {
                        inputText = t
                        isInputFocused = true
                    } label: {
                        Text(t)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.sweeplySurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message \(client.name)…", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyNavy)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sweeplyBorder, lineWidth: 1))
                .focused($isInputFocused)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.sweeplyBorder : Color.sweeplyAccent)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: Message

    private var isOutgoing: Bool { message.direction == .outgoing }

    var body: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 3) {
            HStack {
                if isOutgoing { Spacer(minLength: 60) }
                Text(message.body)
                    .font(.system(size: 15))
                    .foregroundStyle(isOutgoing ? .white : Color.sweeplyNavy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isOutgoing ? Color.sweeplyNavy : Color.sweeplySurface)
                    .clipShape(
                        RoundedCornerShape(
                            radius: 18,
                            corners: isOutgoing
                                ? [.topLeft, .topRight, .bottomLeft]
                                : [.topLeft, .topRight, .bottomRight]
                        )
                    )
                    .overlay(
                        isOutgoing ? nil :
                        RoundedCornerShape(radius: 18, corners: [.topLeft, .topRight, .bottomRight])
                            .stroke(Color.sweeplyBorder, lineWidth: 1)
                    )
                if !isOutgoing { Spacer(minLength: 60) }
            }

            HStack(spacing: 4) {
                if isOutgoing { Spacer() }
                if isOutgoing {
                    Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(message.isRead ? Color.sweeplyAccent : Color.sweeplyTextSub.opacity(0.4))
                    Text(message.isRead ? "Read" : "Sent")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(message.isRead ? Color.sweeplyAccent : Color.sweeplyTextSub.opacity(0.6))
                } else {
                    Text("Received")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.6))
                }
                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                Text(message.sentAt, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                if !isOutgoing { Spacer() }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rounded Corner Shape

private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
