import SwiftUI

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    enum ActionType {
        case newJob
        case newClient
        case newInvoice
        case openSchedule
        case openFinances
        case openClients
    }

    let id = UUID()
    let role: Role
    let text: String
    var timestamp: Date = Date()
    var action: ActionType? = nil
    var actionLabel: String? = nil
    var isTyping: Bool = false
}

// MARK: - AI Chat View

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JobsStore.self) private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self) private var profileStore

    var onNewJob: (() -> Void)? = nil
    var onNewClient: (() -> Void)? = nil
    var onNewInvoice: (() -> Void)? = nil

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isAssistantTyping: Bool = false
    @State private var showSuggestions: Bool = true

    private let suggestions = [
        "What jobs are coming up?",
        "How is my revenue looking?",
        "Add a new client",
        "Create an invoice",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Welcome header
                            if messages.isEmpty {
                                welcomeHeader
                            }

                            // Messages
                            LazyVStack(spacing: 12) {
                                ForEach(messages) { message in
                                    MessageBubble(
                                        message: message,
                                        onAction: { actionType in
                                            handleAction(actionType)
                                        }
                                    )
                                    .id(message.id)
                                }

                                if isAssistantTyping {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, messages.isEmpty ? 0 : 16)
                            .padding(.bottom, 16)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            if let last = messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isAssistantTyping) { _, typing in
                        if typing {
                            withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                        }
                    }
                }

                // Suggestions
                if showSuggestions && messages.isEmpty {
                    suggestionChips
                }

                Divider()

                // Input bar
                inputBar
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.sweeplyNavy)
                                .frame(width: 28, height: 28)
                            Text("S")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Sweeply AI")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            Text("Your business assistant")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                    }
                }
            }
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 32)

            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy)
                    .frame(width: 72, height: 72)
                Text("S")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Hi, I'm Sweeply AI")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)

                Text("Ask me anything about your business.\nI can schedule jobs, manage clients,\ncheck finances, and more.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        sendMessage(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.sweeplySurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Sweeply AI anything...", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sweeplyBorder, lineWidth: 1))

            Button {
                guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                sendMessage(inputText)
            } label: {
                ZStack {
                    Circle()
                        .fill(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? Color.sweeplyBorder
                              : Color.sweeplyNavy)
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
    }

    // MARK: - Logic

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showSuggestions = false
        inputText = ""

        let userMsg = ChatMessage(role: .user, text: trimmed)
        messages.append(userMsg)

        isAssistantTyping = true
        let delay = Double.random(in: 0.8...1.4)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let response = generateResponse(for: trimmed)
            await MainActor.run {
                isAssistantTyping = false
                messages.append(response)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func handleAction(_ type: ChatMessage.ActionType) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch type {
            case .newJob: onNewJob?()
            case .newClient: onNewClient?()
            case .newInvoice: onNewInvoice?()
            default: break
            }
        }
    }

    // MARK: - Response Engine

    private func generateResponse(for input: String) -> ChatMessage {
        let lowered = input.lowercased()

        // Job-related queries
        if lowered.contains("job") || lowered.contains("schedule") || lowered.contains("upcoming") || lowered.contains("appointment") || lowered.contains("booking") {
            if lowered.contains("add") || lowered.contains("new") || lowered.contains("create") || lowered.contains("book") || lowered.contains("schedule a") {
                return ChatMessage(role: .assistant,
                    text: "I'll open the new job form for you. Fill in the client, service type, date, and price — takes about 30 seconds.",
                    action: .newJob,
                    actionLabel: "Schedule New Job")
            }
            let upcoming = jobsStore.jobs.filter { $0.date >= Date() && $0.status == .scheduled }.sorted { $0.date < $1.date }
            if upcoming.isEmpty {
                return ChatMessage(role: .assistant,
                    text: "You have no upcoming jobs scheduled right now. Want to book one?",
                    action: .newJob,
                    actionLabel: "Schedule a Job")
            }
            let next = upcoming.prefix(3)
            let list = next.map { "• \($0.clientName) — \($0.serviceType.rawValue) on \($0.date.formatted(date: .abbreviated, time: .shortened))" }.joined(separator: "\n")
            return ChatMessage(role: .assistant,
                text: "You have \(upcoming.count) upcoming job\(upcoming.count == 1 ? "" : "s"). Here are the next \(next.count):\n\n\(list)",
                action: upcoming.count > 3 ? .openSchedule : nil,
                actionLabel: upcoming.count > 3 ? "View All on Schedule" : nil)
        }

        // Client-related
        if lowered.contains("client") || lowered.contains("customer") {
            if lowered.contains("add") || lowered.contains("new") || lowered.contains("create") {
                return ChatMessage(role: .assistant,
                    text: "Let's add a new client. I'll open the client form — you'll need their name, address, and contact info.",
                    action: .newClient,
                    actionLabel: "Add New Client")
            }
            let active = clientsStore.clients.filter { $0.isActive }
            return ChatMessage(role: .assistant,
                text: "You have \(active.count) active client\(active.count == 1 ? "" : "s") out of \(clientsStore.clients.count) total. Your most recent: \(clientsStore.clients.first?.name ?? "none yet").",
                action: .openClients,
                actionLabel: "View All Clients")
        }

        // Invoice-related
        if lowered.contains("invoice") || lowered.contains("bill") || lowered.contains("billing") {
            if lowered.contains("add") || lowered.contains("new") || lowered.contains("create") || lowered.contains("send") {
                return ChatMessage(role: .assistant,
                    text: "Opening the invoice builder. Select a client, add line items, and set the due date.",
                    action: .newInvoice,
                    actionLabel: "Create Invoice")
            }
            let unpaid = invoicesStore.invoices.filter { $0.status == .unpaid || $0.status == .overdue }
            let overdue = invoicesStore.invoices.filter { $0.status == .overdue }
            var text = "You have \(unpaid.count) unpaid invoice\(unpaid.count == 1 ? "" : "s")"
            if !overdue.isEmpty { text += " (\(overdue.count) overdue)" }
            text += "."
            return ChatMessage(role: .assistant,
                text: text,
                action: .openFinances,
                actionLabel: "Open Finances")
        }

        // Revenue/money queries
        if lowered.contains("revenue") || lowered.contains("money") || lowered.contains("earn") || lowered.contains("income") || lowered.contains("paid") || lowered.contains("finance") || lowered.contains("how much") {
            let paid = invoicesStore.invoices.filter { $0.status == .paid }.reduce(0.0) { $0 + $1.subtotal }
            let pipeline = invoicesStore.invoices.filter { $0.status == .unpaid }.reduce(0.0) { $0 + $1.subtotal }
            return ChatMessage(role: .assistant,
                text: "Here's your financial snapshot:\n\n• Collected: \(paid.formatted(.currency(code: "USD")))\n• Outstanding pipeline: \(pipeline.formatted(.currency(code: "USD")))\n• Total invoices: \(invoicesStore.invoices.count)",
                action: .openFinances,
                actionLabel: "View Full Finances")
        }

        // Greetings
        if lowered.hasPrefix("hi") || lowered.hasPrefix("hello") || lowered.hasPrefix("hey") || lowered == "yo" {
            let name = profileStore.profile?.fullName.components(separatedBy: " ").first ?? "there"
            return ChatMessage(role: .assistant,
                text: "Hey \(name)! What can I help you with today? I can look up your jobs, pull up client info, check finances, or help you create something new.")
        }

        // Help
        if lowered.contains("help") || lowered.contains("what can you") || lowered.contains("what do you") {
            return ChatMessage(role: .assistant,
                text: "I can help you with:\n\n• Scheduling and managing jobs\n• Adding and viewing clients\n• Creating and tracking invoices\n• Checking your revenue and finances\n• Getting a quick business overview\n\nJust ask me naturally — like \"show me upcoming jobs\" or \"what's my revenue this month\".")
        }

        // Stats / overview
        if lowered.contains("overview") || lowered.contains("summary") || lowered.contains("stats") || lowered.contains("business") || lowered.contains("how am i doing") {
            let upcoming = jobsStore.jobs.filter { $0.date >= Date() && $0.status == .scheduled }.count
            let activeClients = clientsStore.clients.filter { $0.isActive }.count
            let unpaidAmount = invoicesStore.invoices.filter { $0.status == .unpaid || $0.status == .overdue }.reduce(0.0) { $0 + $1.subtotal }
            return ChatMessage(role: .assistant,
                text: "Here's your business at a glance:\n\n• \(upcoming) upcoming job\(upcoming == 1 ? "" : "s") scheduled\n• \(activeClients) active client\(activeClients == 1 ? "" : "s")\n• \(unpaidAmount.formatted(.currency(code: "USD"))) in outstanding invoices\n\nLooking solid! Want me to help with anything specific?")
        }

        // Default
        return ChatMessage(role: .assistant,
            text: "I'm not sure I caught that. Try asking me about your jobs, clients, invoices, or revenue. You can also say things like \"schedule a job\", \"add a client\", or \"what's my revenue\".")
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let onAction: (ChatMessage.ActionType) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy)
                        .frame(width: 28, height: 28)
                    Text("S")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .alignmentGuide(.bottom) { d in d[.bottom] }
            } else {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 8) {
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(message.role == .assistant ? Color.sweeplyNavy : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .assistant ? Color.sweeplySurface : Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(message.role == .assistant ? Color.sweeplyBorder : Color.clear, lineWidth: 1)
                    )

                if let action = message.action, let label = message.actionLabel {
                    Button {
                        onAction(action)
                    } label: {
                        HStack(spacing: 6) {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.sweeplyAccent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.sweeplyAccent.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if message.role == .user {
                ZStack {
                    Circle()
                        .fill(Color.sweeplyNavy.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                .alignmentGuide(.bottom) { d in d[.bottom] }
            } else {
                Spacer(minLength: 48)
            }
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy)
                    .frame(width: 28, height: 28)
                Text("S")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.sweeplyTextSub)
                        .frame(width: 6, height: 6)
                        .scaleEffect(phase == i ? 1.3 : 0.8)
                        .opacity(phase == i ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.3).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.sweeplyBorder, lineWidth: 1))
            Spacer()
        }
        .onAppear {
            phase = 1
        }
    }
}
