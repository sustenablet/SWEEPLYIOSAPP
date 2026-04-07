import SwiftUI
import UserNotifications

// MARK: - Models

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }

    enum MessageStyle { case `default`, warning, info, success }

    enum ActionType: String {
        case newJob, newClient, newInvoice
        case openSchedule, openFinances, openClients
    }

    enum ContextCard {
        case jobs([JobPreview])
        case invoices([InvoicePreview])
        case confirmJob(JobDraft)
        case confirmClient(ClientDraft)
    }

    struct JobPreview {
        let clientName: String
        let serviceType: String
        let date: Date
        let status: JobStatus
        let price: Double
        let address: String
    }

    struct InvoicePreview {
        let invoiceNumber: String
        let clientName: String
        let amount: Double
        let status: InvoiceStatus
        let dueDate: Date
    }

    let id: UUID
    let role: Role
    var text: String
    var timestamp: Date
    var messageStyle: MessageStyle
    var action: ActionType?
    var actionLabel: String?
    var quickReplies: [String]
    var contextCard: ContextCard?
    var isNew: Bool

    init(role: Role, text: String, style: MessageStyle = .default,
         action: ActionType? = nil, actionLabel: String? = nil,
         quickReplies: [String] = [], contextCard: ContextCard? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
        self.messageStyle = style
        self.action = action
        self.actionLabel = actionLabel
        self.quickReplies = quickReplies
        self.contextCard = contextCard
        self.isNew = true
    }
}

// MARK: - Conversation State

enum ConversationState {
    case idle
    case collectingJob(JobDraft)
    case awaitingJobConfirmation(JobDraft)
    case collectingClient(ClientDraft)
    case awaitingReminder(String)
}

struct JobDraft {
    var clientName: String? = nil
    var matchedClientId: UUID? = nil
    var serviceType: ServiceType? = nil
    var date: Date? = nil
    var price: Double? = nil
    var duration: Double = 2.0
    var address: String? = nil

    var nextMissingField: String? {
        if clientName == nil { return "Which client is this job for?" }
        if serviceType == nil { return "What type of service? (Standard Clean, Deep Clean, Move In/Out, Post Construction, Office Clean)" }
        if date == nil { return "What date? (e.g. tomorrow, next Thursday, April 15)" }
        if price == nil { return "What's the price for this job?" }
        return nil
    }

    var isComplete: Bool { nextMissingField == nil }

    var summary: String {
        var parts: [String] = []
        if let n = clientName { parts.append("Client: \(n)") }
        if let s = serviceType { parts.append("Service: \(s.rawValue)") }
        if let d = date { parts.append("Date: \(d.formatted(date: .abbreviated, time: .shortened))") }
        if let p = price { parts.append("Price: \(p.formatted(.currency(code: "USD")))") }
        return parts.joined(separator: "\n")
    }
}

struct ClientDraft {
    var name: String? = nil
    var phone: String? = nil
    var email: String? = nil
    var address: String? = nil

    var nextMissingField: String? {
        if name == nil { return "What's the client's name?" }
        if phone == nil { return "What's their phone number? (or say 'skip' to leave blank)" }
        return nil
    }

    var isComplete: Bool { nextMissingField == nil }
}

// MARK: - Persistence

private struct PersistedMessage: Codable {
    enum Role: String, Codable { case user, assistant }
    enum Style: String, Codable { case `default`, warning, info, success }

    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date
    let style: Style
    let action: String?
    let actionLabel: String?
    let quickReplies: [String]

    init(from message: ChatMessage) {
        self.id = message.id
        self.role = message.role == .user ? .user : .assistant
        self.text = message.text
        self.timestamp = message.timestamp
        switch message.messageStyle {
        case .warning: self.style = .warning
        case .info: self.style = .info
        case .success: self.style = .success
        case .default: self.style = .default
        }
        self.action = message.action?.rawValue
        self.actionLabel = message.actionLabel
        self.quickReplies = message.quickReplies
    }

    func toChatMessage() -> ChatMessage {
        let resolvedStyle: ChatMessage.MessageStyle = {
            switch style {
            case .warning: return .warning
            case .info: return .info
            case .success: return .success
            case .default: return .default
            }
        }()
        var msg = ChatMessage(
            role: role == .user ? .user : .assistant,
            text: text,
            style: resolvedStyle,
            action: action.flatMap { ChatMessage.ActionType(rawValue: $0) },
            actionLabel: actionLabel,
            quickReplies: quickReplies
        )
        msg.isNew = false
        return msg
    }
}

private struct PersistedSession: Codable {
    let savedAt: Date
    let messages: [PersistedMessage]
}

// MARK: - Main View

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
    @State private var conversationState: ConversationState = .idle
    @State private var hasFiredProactive: Bool = false

    @AppStorage("sweeplyAIChatHistoryV2") private var chatHistoryData: Data = Data()
    @AppStorage("sweeplyAIChatSavedAt") private var chatSavedAt: Double = 0

    private var firstName: String {
        profileStore.profile?.fullName.components(separatedBy: " ").first ?? "there"
    }

    private var dynamicSuggestions: [String] {
        var chips: [String] = []
        let overdueCount = invoicesStore.invoices.filter { $0.status == .overdue }.count
        let todayJobs = jobsStore.jobs.filter { Calendar.current.isDateInToday($0.date) && $0.status == .scheduled }.count
        if overdueCount > 0 { chips.append("Check overdue invoices") }
        if todayJobs > 0 { chips.append("Today's jobs") }
        let upcoming = jobsStore.jobs.filter { $0.date > Date() && $0.status == .scheduled }.count
        if upcoming > 0 { chips.append("Upcoming schedule") }
        chips.append("Business overview")
        chips.append("Add a new job")
        return Array(chips.prefix(4))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            if messages.isEmpty && !isAssistantTyping {
                                welcomeHeader
                            }
                            LazyVStack(spacing: 12) {
                                ForEach(messages) { message in
                                    MessageBubble(
                                        message: message,
                                        onAction: handleAction,
                                        onQuickReply: sendMessage
                                    )
                                    .id(message.id)
                                }
                                if isAssistantTyping {
                                    TypingIndicatorView()
                                        .id("typing")
                                        .padding(.horizontal, 16)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, messages.isEmpty ? 0 : 16)
                            .padding(.bottom, 20)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.3)) {
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

                if messages.isEmpty && !isAssistantTyping {
                    suggestionChipsRow
                }

                quickActionsBar

                Divider()
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
                                .frame(width: 30, height: 30)
                            Text("S")
                                .font(.system(size: 15, weight: .black, design: .rounded))
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
                ToolbarItem(placement: .navigationBarLeading) {
                    if !messages.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            messages = []
                            conversationState = .idle
                            hasFiredProactive = false
                            chatHistoryData = Data()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 13, weight: .medium))
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
            .onAppear {
                loadPersistedChat()
                if !hasFiredProactive {
                    fireProactiveMessage()
                }
            }
            .onDisappear {
                persistChat()
            }
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 28)
            ZStack {
                Circle()
                    .fill(Color.sweeplyNavy.opacity(0.08))
                    .frame(width: 100, height: 100)
                Circle()
                    .fill(Color.sweeplyNavy)
                    .frame(width: 76, height: 76)
                Text("S")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text(timeGreeting + ", \(firstName)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Text("I'm your Sweeply business assistant.\nAsk me anything or tap a quick action below.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Suggestion Chips

    private var suggestionChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dynamicSuggestions, id: \.self) { suggestion in
                    Button { sendMessage(suggestion) } label: {
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
            .padding(.vertical, 10)
        }
    }

    // MARK: - Quick Actions Bar

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                QuickActionChip(icon: "calendar", label: "Today") { sendMessage("What's on my schedule today?") }
                QuickActionChip(icon: "chart.line.uptrend.xyaxis", label: "Revenue") { sendMessage("What's my revenue?") }
                QuickActionChip(icon: "briefcase.fill", label: "New Job") { sendMessage("I want to schedule a new job") }
                QuickActionChip(icon: "person.badge.plus", label: "New Client") { sendMessage("Add a new client") }
                QuickActionChip(icon: "doc.badge.plus", label: "Invoice") { sendMessage("Create a new invoice") }
                QuickActionChip(icon: "sparkles", label: "Insights") { sendMessage("Give me business insights") }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.sweeplyBackground)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Sweeply AI anything...", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.sweeplyBorder, lineWidth: 1))

            Button { } label: {
                Image(systemName: "mic")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                    .frame(width: 36, height: 36)
            }
            .disabled(true)

            Button {
                let trimmed = inputText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                sendMessage(trimmed)
            } label: {
                ZStack {
                    Circle()
                        .fill(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                              ? Color.sweeplyBorder
                              : Color.sweeplyAccent)
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
    }

    // MARK: - Send Logic

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        inputText = ""

        let userMsg = ChatMessage(role: .user, text: trimmed)
        messages.append(userMsg)

        isAssistantTyping = true
        let delay = Double.random(in: 0.7...1.2)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let response = generateResponse(for: trimmed)
            await MainActor.run {
                isAssistantTyping = false
                messages.append(response)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                persistChat()
            }
        }
    }

    private func handleAction(_ type: ChatMessage.ActionType) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch type {
        case .openSchedule, .openClients, .openFinances:
            dismiss()
        case .newJob:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onNewJob?() }
        case .newClient:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onNewClient?() }
        case .newInvoice:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onNewInvoice?() }
        }
    }

    // MARK: - Proactive First Message

    private func fireProactiveMessage() {
        guard !hasFiredProactive else { return }
        hasFiredProactive = true

        isAssistantTyping = true
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            let msg = buildProactiveMessage()
            await MainActor.run {
                isAssistantTyping = false
                messages.append(msg)
            }
        }
    }

    private func buildProactiveMessage() -> ChatMessage {
        let overdue = invoicesStore.invoices.filter { $0.status == .overdue }
        let todayJobs = jobsStore.jobs.filter { Calendar.current.isDateInToday($0.date) && $0.status == .scheduled }
        let upcomingJobs = jobsStore.jobs.filter { $0.date > Date() && $0.status == .scheduled }.sorted { $0.date < $1.date }
        let activeClients = clientsStore.clients.filter { $0.isActive }
        let isNewUser = clientsStore.clients.isEmpty && jobsStore.jobs.isEmpty

        if isNewUser {
            return ChatMessage(
                role: .assistant,
                text: "Welcome to Sweeply, \(firstName)! Looks like you're just getting started. Let me help you set up your business — start by adding your first client, then we can book your first job and send your first invoice.",
                quickReplies: ["Add my first client", "Show me around", "What can you do?"]
            )
        }

        if !overdue.isEmpty {
            let total = overdue.reduce(0.0) { $0 + $1.subtotal }
            return ChatMessage(
                role: .assistant,
                text: "Hey \(firstName) — heads up, you have \(overdue.count) overdue invoice\(overdue.count == 1 ? "" : "s") totaling \(total.formatted(.currency(code: "USD"))). Worth following up on those today.",
                style: .warning,
                action: .openFinances,
                actionLabel: "View Overdue Invoices",
                quickReplies: ["Show me", "Create a reminder", "What else?"]
            )
        }

        if !todayJobs.isEmpty {
            let names = todayJobs.prefix(2).map { $0.clientName }.joined(separator: " and ")
            let greetingWord = timeGreeting.replacingOccurrences(of: "Good ", with: "")
            return ChatMessage(
                role: .assistant,
                text: "Good \(greetingWord), \(firstName)! You have \(todayJobs.count) job\(todayJobs.count == 1 ? "" : "s") today — \(names)\(todayJobs.count > 2 ? " and more" : ""). Have a great day out there.",
                style: .info,
                quickReplies: ["Today's full schedule", "What's next?", "Business overview"]
            )
        }

        let thisWeekJobs = upcomingJobs.filter {
            guard let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else { return false }
            return $0.date <= weekFromNow
        }

        if !thisWeekJobs.isEmpty {
            return ChatMessage(
                role: .assistant,
                text: "Hey \(firstName)! You have \(thisWeekJobs.count) job\(thisWeekJobs.count == 1 ? "" : "s") coming up this week. \(activeClients.count) active client\(activeClients.count == 1 ? "" : "s") on your roster. How can I help you today?",
                quickReplies: ["Show this week's jobs", "Check revenue", "Business overview"]
            )
        }

        return ChatMessage(
            role: .assistant,
            text: "Hey \(firstName)! Your schedule looks clear right now — good time to reach out to clients or get ahead on invoicing. What can I help you with?",
            quickReplies: ["Add a job", "Check finances", "View clients"]
        )
    }

    // MARK: - Response Engine

    private func generateResponse(for input: String) -> ChatMessage {
        let lowered = input.lowercased()

        // Conversational state handling
        switch conversationState {
        case .collectingJob(let draft):
            return handleJobCollection(input: input, lowered: lowered, draft: draft)
        case .awaitingJobConfirmation(let draft):
            if lowered.contains("yes") || lowered.contains("confirm") || lowered.contains("create") || lowered.contains("book") || lowered.contains("looks good") || lowered == "yep" || lowered == "yup" || lowered == "ok" || lowered == "okay" {
                conversationState = .idle
                return ChatMessage(
                    role: .assistant,
                    text: "I'll open the job form with those details ready to go. Just tap Save to confirm.",
                    style: .success,
                    action: .newJob,
                    actionLabel: "Open Job Form",
                    quickReplies: ["Add another job", "Check my schedule"]
                )
            } else if lowered.contains("no") || lowered.contains("cancel") || lowered.contains("nevermind") || lowered.contains("stop") {
                conversationState = .idle
                return ChatMessage(role: .assistant, text: "No worries — job creation cancelled. What else can I help with?", quickReplies: ["Business overview", "Today's jobs"])
            } else {
                return ChatMessage(role: .assistant, text: "Ready to create that job? Say yes to open the form, or no to cancel.", quickReplies: ["Yes, create it", "No thanks"])
            }
        case .collectingClient(let draft):
            return handleClientCollection(input: input, lowered: lowered, draft: draft)
        case .awaitingReminder(let note):
            return handleReminderDate(input: input, note: note)
        case .idle:
            break
        }

        // REMIND ME
        if lowered.contains("remind me") || (lowered.contains("reminder") && !lowered.contains("schedule")) {
            if let date = parseDateFromText(lowered) {
                let cleaned = input
                    .replacingOccurrences(of: "remind me to ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "remind me ", with: "", options: .caseInsensitive)
                scheduleReminder(text: cleaned, at: date)
                return ChatMessage(
                    role: .assistant,
                    text: "Done — I'll remind you \"\(cleaned)\" on \(date.formatted(date: .abbreviated, time: .omitted)).",
                    style: .success,
                    quickReplies: ["Add another reminder", "What else?"]
                )
            } else {
                conversationState = .awaitingReminder(input)
                return ChatMessage(
                    role: .assistant,
                    text: "Sure, I'll set a reminder. When should I remind you? (e.g. tomorrow, next Friday, April 20)"
                )
            }
        }

        // TODAY'S JOBS
        if (lowered.contains("today") && (lowered.contains("job") || lowered.contains("schedule") || lowered.contains("what"))) || lowered == "today's jobs" || lowered == "today's schedule" || lowered == "what's on my schedule today?" {
            let todayJobs = jobsStore.jobs.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date < $1.date }
            if todayJobs.isEmpty {
                return ChatMessage(
                    role: .assistant,
                    text: "Nothing scheduled for today. Want to book something?",
                    action: .newJob,
                    actionLabel: "Schedule a Job",
                    quickReplies: ["Show upcoming jobs", "Business overview"]
                )
            }
            let previews = todayJobs.map {
                ChatMessage.JobPreview(clientName: $0.clientName, serviceType: $0.serviceType.rawValue, date: $0.date, status: $0.status, price: $0.price, address: $0.address)
            }
            return ChatMessage(
                role: .assistant,
                text: "You have \(todayJobs.count) job\(todayJobs.count == 1 ? "" : "s") today:",
                style: .info,
                quickReplies: ["Add another job", "View full schedule"],
                contextCard: .jobs(previews)
            )
        }

        // THIS WEEK / UPCOMING
        if lowered.contains("this week") || lowered.contains("next 7") || (lowered.contains("upcoming") && !lowered.contains("add")) || lowered == "upcoming schedule" {
            if let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: Date()) {
                let weekJobs = jobsStore.jobs.filter { $0.date >= Date() && $0.date <= weekOut && $0.status == .scheduled }.sorted { $0.date < $1.date }
                if weekJobs.isEmpty {
                    return ChatMessage(role: .assistant, text: "Nothing scheduled this week. Want to book some jobs?", action: .newJob, actionLabel: "Schedule a Job", quickReplies: ["Check next week", "View all jobs"])
                }
                let previews = weekJobs.prefix(5).map { ChatMessage.JobPreview(clientName: $0.clientName, serviceType: $0.serviceType.rawValue, date: $0.date, status: $0.status, price: $0.price, address: $0.address) }
                return ChatMessage(role: .assistant, text: "Here are your jobs this week (\(weekJobs.count) total):", style: .info, quickReplies: ["Add more jobs", "View schedule"], contextCard: .jobs(Array(previews)))
            }
        }

        // NEW JOB (guided flow)
        let isJobIntent = (lowered.contains("add") || lowered.contains("new") || lowered.contains("create") || lowered.contains("book") || lowered.contains("schedule a") || lowered.contains("want to schedule")) && (lowered.contains("job") || lowered.contains("appointment") || lowered.contains("booking") || lowered.contains("clean"))
        if isJobIntent {
            var draft = JobDraft()

            for client in clientsStore.clients where client.isActive {
                let nameLower = client.name.lowercased()
                let nameParts = nameLower.components(separatedBy: " ")
                if nameParts.contains(where: { lowered.contains($0) && $0.count > 2 }) {
                    draft.clientName = client.name
                    draft.matchedClientId = client.id
                    draft.address = client.address
                    if let pref = client.preferredService { draft.serviceType = pref }
                    break
                }
            }

            if draft.serviceType == nil {
                for service in ServiceType.allCases {
                    if lowered.contains(service.rawValue.lowercased()) {
                        draft.serviceType = service
                        break
                    }
                }
                if draft.serviceType == nil {
                    if lowered.contains("deep") { draft.serviceType = .deep }
                    else if lowered.contains("standard") { draft.serviceType = .standard }
                    else if lowered.contains("move") { draft.serviceType = .moveInOut }
                    else if lowered.contains("office") { draft.serviceType = .office }
                }
            }

            if let date = parseDateFromText(lowered) { draft.date = date }
            if let price = extractPrice(from: lowered) { draft.price = price }

            if draft.isComplete {
                conversationState = .awaitingJobConfirmation(draft)
                return buildJobConfirmation(draft)
            } else {
                conversationState = .collectingJob(draft)
                let nextQ = draft.nextMissingField ?? "Any other details?"
                let clientSuggestions = draft.clientName == nil
                    ? clientsStore.clients.filter { $0.isActive }.prefix(3).map { $0.name }
                    : []
                return ChatMessage(
                    role: .assistant,
                    text: "Let's set up the job.\(draft.clientName != nil ? " I found \(draft.clientName!) in your clients." : "")\(draft.date != nil ? " Date: \(draft.date!.formatted(date: .abbreviated, time: .omitted))." : "")\n\n\(nextQ)",
                    quickReplies: Array(clientSuggestions)
                )
            }
        }

        // JOBS GENERAL
        if lowered.contains("job") || lowered.contains("schedule") || lowered.contains("appointment") {
            let upcoming = jobsStore.jobs.filter { $0.date >= Date() && $0.status == .scheduled }.sorted { $0.date < $1.date }
            if upcoming.isEmpty {
                return ChatMessage(role: .assistant, text: "No upcoming jobs scheduled. Ready to book one?", action: .newJob, actionLabel: "Schedule a Job", quickReplies: ["Add a job", "View completed jobs"])
            }
            let previews = upcoming.prefix(4).map { ChatMessage.JobPreview(clientName: $0.clientName, serviceType: $0.serviceType.rawValue, date: $0.date, status: $0.status, price: $0.price, address: $0.address) }
            return ChatMessage(
                role: .assistant,
                text: "You have \(upcoming.count) upcoming job\(upcoming.count == 1 ? "" : "s"):",
                style: .info,
                action: upcoming.count > 4 ? .openSchedule : nil,
                actionLabel: upcoming.count > 4 ? "View All on Schedule" : nil,
                quickReplies: ["Add a job", "Today's jobs", "This week"],
                contextCard: .jobs(Array(previews))
            )
        }

        // CLIENT LOOKUP by name
        for client in clientsStore.clients {
            let nameParts = client.name.lowercased().components(separatedBy: " ")
            let matchesName = nameParts.contains(where: { lowered.contains($0) && $0.count > 2 })
            if matchesName && (lowered.contains("about") || lowered.contains("client") || lowered.contains("job") || lowered.contains("invoice") || lowered.contains("tell")) {
                let clientJobs = jobsStore.jobs.filter { $0.clientId == client.id }
                let completedJobs = clientJobs.filter { $0.status == .completed }.count
                let upcomingCount = clientJobs.filter { $0.status == .scheduled }.count
                let revenue = invoicesStore.invoices.filter { $0.clientId == client.id && $0.status == .paid }.reduce(0.0) { $0 + $1.subtotal }
                return ChatMessage(
                    role: .assistant,
                    text: "\(client.name)\n\n• \(completedJobs) completed job\(completedJobs == 1 ? "" : "s")\n• \(upcomingCount) upcoming\n• \(revenue.formatted(.currency(code: "USD"))) total revenue\n• \(client.phone.isEmpty ? "No phone" : client.phone)",
                    style: .info,
                    quickReplies: [
                        "Schedule a job for \(client.name.components(separatedBy: " ").first ?? client.name)",
                        "Create invoice for \(client.name.components(separatedBy: " ").first ?? client.name)"
                    ]
                )
            }
        }

        // NEW CLIENT (guided flow)
        let isNewClientIntent = (lowered.contains("add") || lowered.contains("new") || lowered.contains("create")) && (lowered.contains("client") || lowered.contains("customer"))
        if isNewClientIntent {
            conversationState = .collectingClient(ClientDraft())
            return ChatMessage(
                role: .assistant,
                text: "Let's add a new client. What's their name?",
                quickReplies: []
            )
        }

        // CLIENT LIST
        if lowered.contains("client") || lowered.contains("customer") {
            let active = clientsStore.clients.filter { $0.isActive }
            let inactive = clientsStore.clients.filter { !$0.isActive }.count
            var text = "You have \(active.count) active client\(active.count == 1 ? "" : "s")"
            if inactive > 0 { text += " (\(inactive) archived)" }
            text += "."
            if let first = active.first { text += " Most recent: \(first.name)." }
            return ChatMessage(
                role: .assistant,
                text: text,
                style: .info,
                action: .openClients,
                actionLabel: "View All Clients",
                quickReplies: ["Add a client", "Who's most active?"]
            )
        }

        // OVERDUE INVOICES
        if lowered.contains("overdue") || lowered.contains("late") || (lowered.contains("unpaid") && lowered.contains("invoice")) {
            let overdue = invoicesStore.invoices.filter { $0.status == .overdue }
            if overdue.isEmpty {
                return ChatMessage(role: .assistant, text: "No overdue invoices right now — you're all caught up on billing.", style: .success, quickReplies: ["Check all invoices", "Create invoice"])
            }
            let previews = overdue.map { ChatMessage.InvoicePreview(invoiceNumber: $0.invoiceNumber, clientName: $0.clientName, amount: $0.subtotal, status: $0.status, dueDate: $0.dueDate) }
            return ChatMessage(
                role: .assistant,
                text: "\(overdue.count) overdue invoice\(overdue.count == 1 ? "" : "s") need attention:",
                style: .warning,
                action: .openFinances,
                actionLabel: "Open Finances",
                quickReplies: ["Create a new invoice", "Check all invoices"],
                contextCard: .invoices(previews)
            )
        }

        // INVOICE CREATE
        let isNewInvoiceIntent = (lowered.contains("add") || lowered.contains("new") || lowered.contains("create") || lowered.contains("send")) && (lowered.contains("invoice") || lowered.contains("bill"))
        if isNewInvoiceIntent {
            return ChatMessage(role: .assistant, text: "Opening the invoice builder for you. Select a client, add line items, and set the due date.", action: .newInvoice, actionLabel: "Create Invoice", quickReplies: ["Check existing invoices"])
        }

        // INVOICE LIST / BILLING
        if lowered.contains("invoice") || lowered.contains("bill") || lowered.contains("billing") {
            let unpaid = invoicesStore.invoices.filter { $0.status == .unpaid }
            let overdue = invoicesStore.invoices.filter { $0.status == .overdue }
            let paid = invoicesStore.invoices.filter { $0.status == .paid }
            var text = "Invoice status:"
            text += "\n• \(paid.count) paid"
            text += "\n• \(unpaid.count) unpaid"
            if !overdue.isEmpty { text += "\n• \(overdue.count) overdue" }
            let outstanding = (unpaid + overdue).reduce(0.0) { $0 + $1.subtotal }
            text += "\n\nOutstanding: \(outstanding.formatted(.currency(code: "USD")))"

            let recentUnpaid = (unpaid + overdue).sorted { $0.dueDate < $1.dueDate }.prefix(3)
            let previews = recentUnpaid.map { ChatMessage.InvoicePreview(invoiceNumber: $0.invoiceNumber, clientName: $0.clientName, amount: $0.subtotal, status: $0.status, dueDate: $0.dueDate) }

            return ChatMessage(
                role: .assistant,
                text: text,
                style: overdue.isEmpty ? .info : .warning,
                action: .openFinances,
                actionLabel: "Open Finances",
                quickReplies: ["Create invoice", "Check overdue"],
                contextCard: previews.isEmpty ? nil : .invoices(Array(previews))
            )
        }

        // REVENUE / MONEY
        if lowered.contains("revenue") || lowered.contains("money") || lowered.contains("earn") || lowered.contains("income") || lowered.contains("finance") || lowered.contains("how much") || lowered.contains("what's my revenue") || lowered.contains("check revenue") || (lowered.contains("paid") && !lowered.contains("job")) {
            let paidInvoices = invoicesStore.invoices.filter { $0.status == .paid }
            let collected = paidInvoices.reduce(0.0) { $0 + $1.subtotal }
            let pipeline = invoicesStore.invoices.filter { $0.status == .unpaid }.reduce(0.0) { $0 + $1.subtotal }
            let overdueAmt = invoicesStore.invoices.filter { $0.status == .overdue }.reduce(0.0) { $0 + $1.subtotal }

            let thisMonth = paidInvoices.filter {
                Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month)
            }.reduce(0.0) { $0 + $1.subtotal }

            var text = "Financial snapshot:\n\n"
            text += "• Collected: \(collected.formatted(.currency(code: "USD")))\n"
            text += "• This month: \(thisMonth.formatted(.currency(code: "USD")))\n"
            text += "• Outstanding: \(pipeline.formatted(.currency(code: "USD")))"
            if overdueAmt > 0 { text += "\n• Overdue: \(overdueAmt.formatted(.currency(code: "USD")))" }

            return ChatMessage(
                role: .assistant,
                text: text,
                style: .info,
                action: .openFinances,
                actionLabel: "View Full Finances",
                quickReplies: overdueAmt > 0 ? ["Check overdue invoices", "Create invoice"] : ["Create invoice", "Business overview"]
            )
        }

        // COMPLETED JOBS
        if lowered.contains("completed") || lowered.contains("done") || lowered.contains("finished") || lowered.contains("how many jobs did") {
            let completed = jobsStore.jobs.filter { $0.status == .completed }
            let thisMonth = completed.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            let revenue = completed.reduce(0.0) { $0 + $1.price }
            return ChatMessage(
                role: .assistant,
                text: "Completed jobs:\n\n• All time: \(completed.count) jobs\n• This month: \(thisMonth.count) jobs\n• Total revenue from completed: \(revenue.formatted(.currency(code: "USD")))",
                style: .info,
                quickReplies: ["View upcoming jobs", "Check revenue"]
            )
        }

        // BUSINESS OVERVIEW
        if lowered.contains("overview") || lowered.contains("summary") || lowered.contains("stats") || lowered.contains("how am i doing") || lowered.contains("business overview") {
            let upcoming = jobsStore.jobs.filter { $0.date >= Date() && $0.status == .scheduled }.count
            let activeClients = clientsStore.clients.filter { $0.isActive }.count
            let completed = jobsStore.jobs.filter { $0.status == .completed }.count
            let outstanding = invoicesStore.invoices.filter { $0.status == .unpaid || $0.status == .overdue }.reduce(0.0) { $0 + $1.subtotal }
            let collected = invoicesStore.invoices.filter { $0.status == .paid }.reduce(0.0) { $0 + $1.subtotal }
            let overdueCt = invoicesStore.invoices.filter { $0.status == .overdue }.count

            var text = "Business overview:\n\n"
            text += "• \(upcoming) upcoming job\(upcoming == 1 ? "" : "s")\n"
            text += "• \(completed) jobs completed\n"
            text += "• \(activeClients) active client\(activeClients == 1 ? "" : "s")\n"
            text += "• \(collected.formatted(.currency(code: "USD"))) collected\n"
            text += "• \(outstanding.formatted(.currency(code: "USD"))) outstanding"
            if overdueCt > 0 { text += "\n• \(overdueCt) overdue invoice\(overdueCt == 1 ? "" : "s")" }

            return ChatMessage(
                role: .assistant,
                text: text,
                style: .info,
                quickReplies: ["Business insights", "Check finances", "Today's jobs"]
            )
        }

        // BUSINESS INSIGHTS
        if lowered.contains("insight") || lowered.contains("analytics") || lowered.contains("best day") || lowered.contains("pattern") || lowered.contains("trend") || lowered.contains("give me business insights") {
            return buildInsightsResponse()
        }

        // NEXT JOB
        if lowered.contains("next job") || lowered.contains("next appointment") || lowered.contains("when is my next") || lowered.contains("what's next") {
            let next = jobsStore.jobs.filter { $0.date >= Date() && $0.status == .scheduled }.sorted { $0.date < $1.date }.first
            if let job = next {
                return ChatMessage(
                    role: .assistant,
                    text: "Your next job is \(job.serviceType.rawValue) for \(job.clientName) on \(job.date.formatted(date: .complete, time: .shortened)).\n\nAddress: \(job.address)\nPrice: \(job.price.formatted(.currency(code: "USD")))",
                    style: .info,
                    quickReplies: ["Add another job", "View full schedule"]
                )
            } else {
                return ChatMessage(role: .assistant, text: "No upcoming jobs scheduled.", action: .newJob, actionLabel: "Schedule a Job", quickReplies: ["View all jobs"])
            }
        }

        // CANCELLED JOBS
        if lowered.contains("cancelled") || lowered.contains("cancellation") {
            let cancelled = jobsStore.jobs.filter { $0.status == .cancelled }.count
            return ChatMessage(role: .assistant, text: "You have \(cancelled) cancelled job\(cancelled == 1 ? "" : "s") on record.", quickReplies: ["Schedule a new job", "View all jobs"])
        }

        // INACTIVE CLIENTS
        if lowered.contains("inactive") || lowered.contains("haven't booked") || lowered.contains("re-engage") {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let recentClientIds = Set(jobsStore.jobs.filter { $0.date >= thirtyDaysAgo }.map { $0.clientId })
            let inactive = clientsStore.clients.filter { $0.isActive && !recentClientIds.contains($0.id) }
            if inactive.isEmpty {
                return ChatMessage(role: .assistant, text: "All your active clients have had jobs in the last 30 days — great retention!", style: .success, quickReplies: ["Business overview"])
            }
            let names = inactive.prefix(3).map { $0.name }.joined(separator: ", ")
            return ChatMessage(role: .assistant, text: "\(inactive.count) client\(inactive.count == 1 ? "" : "s") haven't booked in 30+ days: \(names)\(inactive.count > 3 ? " and more" : "").", style: .info, action: .openClients, actionLabel: "View Clients", quickReplies: ["Schedule a job", "View all clients"])
        }

        // HELP
        if lowered.contains("help") || lowered.contains("what can you") || lowered.contains("what do you") || lowered.contains("capabilities") || lowered.contains("show me around") {
            return ChatMessage(
                role: .assistant,
                text: "Here's what I can help with:\n\n• Schedule and manage jobs (guided)\n• Add new clients (guided)\n• Create and track invoices\n• Check revenue and finances\n• Business overview and insights\n• Set reminders\n• Look up specific clients\n• Today's schedule, this week's jobs\n\nJust talk to me naturally.",
                quickReplies: ["Schedule a job", "Check revenue", "Business overview"]
            )
        }

        // GREETINGS
        if lowered.hasPrefix("hi") || lowered.hasPrefix("hello") || lowered.hasPrefix("hey") || lowered == "yo" || lowered.hasPrefix("good morning") || lowered.hasPrefix("good afternoon") || lowered.hasPrefix("good evening") {
            return ChatMessage(
                role: .assistant,
                text: "Hey \(firstName)! What can I help you with today?",
                quickReplies: ["Today's jobs", "Business overview", "Check revenue"]
            )
        }

        // DEFAULT
        return ChatMessage(
            role: .assistant,
            text: "I'm not sure I caught that — I'm still learning! Try asking about your jobs, clients, invoices, or revenue. You can also say \"schedule a job\" or \"add a client\" to get started.",
            quickReplies: ["Today's jobs", "Business overview", "Help"]
        )
    }

    // MARK: - Guided Job Collection

    private func handleJobCollection(input: String, lowered: String, draft: JobDraft) -> ChatMessage {
        var updatedDraft = draft

        if lowered == "cancel" || lowered == "stop" || lowered == "nevermind" {
            conversationState = .idle
            return ChatMessage(role: .assistant, text: "No problem — job creation cancelled. What else can I help with?", quickReplies: ["Business overview", "Today's jobs"])
        }

        if draft.clientName == nil {
            let matched = clientsStore.clients.first { client in
                let parts = client.name.lowercased().components(separatedBy: " ")
                return parts.contains(where: { lowered.contains($0) && $0.count > 2 }) || lowered.contains(client.name.lowercased())
            }
            if let client = matched {
                updatedDraft.clientName = client.name
                updatedDraft.matchedClientId = client.id
                updatedDraft.address = client.address
                if let pref = client.preferredService, updatedDraft.serviceType == nil { updatedDraft.serviceType = pref }
            } else {
                updatedDraft.clientName = input.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if draft.serviceType == nil {
            if lowered.contains("deep") { updatedDraft.serviceType = .deep }
            else if lowered.contains("standard") { updatedDraft.serviceType = .standard }
            else if lowered.contains("move") { updatedDraft.serviceType = .moveInOut }
            else if lowered.contains("office") { updatedDraft.serviceType = .office }
            else if lowered.contains("construction") { updatedDraft.serviceType = .postConstruction }
            else { updatedDraft.serviceType = ServiceType(rawValue: input.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .standard }
        } else if draft.date == nil {
            if let date = parseDateFromText(lowered) {
                updatedDraft.date = date
            } else {
                return ChatMessage(role: .assistant, text: "I couldn't parse that date. Try saying something like \"tomorrow\", \"next Thursday\", or \"April 15\".")
            }
        } else if draft.price == nil {
            if let price = extractPrice(from: lowered) {
                updatedDraft.price = price
            } else if let price = Double(input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "$", with: "")) {
                updatedDraft.price = price
            } else {
                return ChatMessage(role: .assistant, text: "What's the price for this job? (e.g. 150 or $200)")
            }
        }

        if updatedDraft.isComplete {
            conversationState = .awaitingJobConfirmation(updatedDraft)
            return buildJobConfirmation(updatedDraft)
        } else {
            conversationState = .collectingJob(updatedDraft)
            let nextQ = updatedDraft.nextMissingField ?? "Anything else to add?"
            let serviceOptions: [String] = updatedDraft.serviceType == nil ? ["Standard Clean", "Deep Clean", "Move In/Out", "Office Clean"] : []
            let clientOptions: [String] = updatedDraft.clientName == nil ? clientsStore.clients.filter { $0.isActive }.prefix(3).map { $0.name } : []
            return ChatMessage(
                role: .assistant,
                text: nextQ,
                quickReplies: serviceOptions.isEmpty ? clientOptions : serviceOptions
            )
        }
    }

    private func buildJobConfirmation(_ draft: JobDraft) -> ChatMessage {
        return ChatMessage(
            role: .assistant,
            text: "Here's the job summary — ready to create it?",
            style: .info,
            action: .newJob,
            actionLabel: "Open Job Form",
            quickReplies: ["Yes, create it", "No thanks"],
            contextCard: .confirmJob(draft)
        )
    }

    // MARK: - Guided Client Collection

    private func handleClientCollection(input: String, lowered: String, draft: ClientDraft) -> ChatMessage {
        var updatedDraft = draft

        if lowered == "cancel" || lowered == "stop" {
            conversationState = .idle
            return ChatMessage(role: .assistant, text: "Client creation cancelled. What else can I help with?")
        }

        if draft.name == nil {
            updatedDraft.name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if draft.phone == nil {
            updatedDraft.phone = lowered == "skip" ? "" : input.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if updatedDraft.isComplete {
            conversationState = .idle
            return ChatMessage(
                role: .assistant,
                text: "I'll open the client form with \(updatedDraft.name ?? "their") details pre-filled. You can add more info before saving.",
                action: .newClient,
                actionLabel: "Open Client Form",
                style: .success,
                quickReplies: ["Add another client", "Schedule a job"]
            )
        } else {
            conversationState = .collectingClient(updatedDraft)
            return ChatMessage(role: .assistant, text: updatedDraft.nextMissingField ?? "Anything else?")
        }
    }

    // MARK: - Reminder Date Collection

    private func handleReminderDate(input: String, note: String) -> ChatMessage {
        conversationState = .idle
        let lowered = input.lowercased()
        if let date = parseDateFromText(lowered) {
            scheduleReminder(text: note, at: date)
            return ChatMessage(
                role: .assistant,
                text: "Reminder set for \(date.formatted(date: .abbreviated, time: .omitted)).",
                style: .success,
                quickReplies: ["Set another reminder", "What else?"]
            )
        }
        return ChatMessage(role: .assistant, text: "I couldn't parse that date. Try saying \"tomorrow\" or \"next Friday\".")
    }

    // MARK: - Insights

    private func buildInsightsResponse() -> ChatMessage {
        let completed = jobsStore.jobs.filter { $0.status == .completed }
        var insights: [String] = []

        if completed.count >= 3 {
            let grouped = Dictionary(grouping: completed) { Calendar.current.component(.weekday, from: $0.date) }
            if let busiest = grouped.max(by: { $0.value.count < $1.value.count }) {
                let name = Calendar.current.weekdaySymbols[busiest.key - 1]
                insights.append("Busiest day: \(name) (\(busiest.value.count) jobs)")
            }
        }

        if !completed.isEmpty {
            let avg = completed.reduce(0.0) { $0 + $1.price } / Double(completed.count)
            insights.append("Average job price: \(avg.formatted(.currency(code: "USD")))")
        }

        if !jobsStore.jobs.isEmpty {
            let grouped = Dictionary(grouping: jobsStore.jobs) { $0.clientName }
            if let top = grouped.max(by: { $0.value.count < $1.value.count }) {
                insights.append("Most active client: \(top.key) (\(top.value.count) jobs)")
            }
        }

        let thisMonth = invoicesStore.invoices.filter { $0.status == .paid && Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }.reduce(0.0) { $0 + $1.subtotal }
        if let lastMonthDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) {
            let lastMonth = invoicesStore.invoices.filter { $0.status == .paid && Calendar.current.isDate($0.createdAt, equalTo: lastMonthDate, toGranularity: .month) }.reduce(0.0) { $0 + $1.subtotal }
            if lastMonth > 0 {
                let diff = ((thisMonth - lastMonth) / lastMonth) * 100
                let direction = diff >= 0 ? "up" : "down"
                insights.append("Revenue vs last month: \(direction) \(abs(diff).rounded())%")
            }
        }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentIds = Set(jobsStore.jobs.filter { $0.date >= thirtyDaysAgo }.map { $0.clientId })
        let inactiveCount = clientsStore.clients.filter { $0.isActive && !recentIds.contains($0.id) }.count
        if inactiveCount > 0 { insights.append("\(inactiveCount) client\(inactiveCount == 1 ? "" : "s") inactive 30+ days") }

        if insights.isEmpty {
            return ChatMessage(role: .assistant, text: "Add more jobs to your history and I'll start surfacing patterns and insights for you.", quickReplies: ["Schedule a job", "Business overview"])
        }

        let text = "Business insights:\n\n" + insights.map { "• \($0)" }.joined(separator: "\n")
        return ChatMessage(role: .assistant, text: text, style: .info, quickReplies: ["Business overview", "Check finances"])
    }

    // MARK: - Date Parser

    private func parseDateFromText(_ text: String) -> Date? {
        let lowered = text.lowercased()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if lowered.contains("today") { return today }
        if lowered.contains("day after tomorrow") { return calendar.date(byAdding: .day, value: 2, to: today) }
        if lowered.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: today) }
        if lowered.contains("next week") { return calendar.date(byAdding: .weekOfYear, value: 1, to: today) }

        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
        for (name, weekday) in weekdays {
            if lowered.contains(name) {
                let currentWeekday = calendar.component(.weekday, from: today)
                var daysAhead = weekday - currentWeekday
                if daysAhead <= 0 { daysAhead += 7 }
                if lowered.contains("next \(name)") && daysAhead < 7 { daysAhead += 7 }
                return calendar.date(byAdding: .day, value: daysAhead, to: today)
            }
        }

        let formatter = DateFormatter()
        for format in ["MMMM d", "MMM d", "M/d", "M/d/yyyy"] {
            formatter.dateFormat = format
            formatter.defaultDate = today
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                var components = calendar.dateComponents([.month, .day], from: date)
                components.year = calendar.component(.year, from: Date())
                if let result = calendar.date(from: components), result >= today { return result }
                components.year = (components.year ?? 2025) + 1
                return calendar.date(from: components)
            }
        }
        return nil
    }

    // MARK: - Price Extractor

    private func extractPrice(from text: String) -> Double? {
        let patterns = ["\\$([0-9]+(?:\\.[0-9]{1,2})?)", "([0-9]+(?:\\.[0-9]{1,2})?)\\s*(?:dollars|bucks|usd)"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range),
                   let captureRange = Range(match.range(at: 1), in: text),
                   let value = Double(text[captureRange]) {
                    return value
                }
            }
        }
        return nil
    }

    // MARK: - Reminder Scheduling

    private func scheduleReminder(text: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Sweeply Reminder"
        content.body = text
        content.sound = .default
        let interval = max(date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Chat Persistence

    private func persistChat() {
        let toSave = messages.suffix(60).map { PersistedMessage(from: $0) }
        let session = PersistedSession(savedAt: Date(), messages: toSave)
        if let data = try? JSONEncoder().encode(session) {
            chatHistoryData = data
            chatSavedAt = Date().timeIntervalSince1970
        }
    }

    private func loadPersistedChat() {
        guard !chatHistoryData.isEmpty else { return }
        guard let session = try? JSONDecoder().decode(PersistedSession.self, from: chatHistoryData) else { return }
        let hoursSince = Date().timeIntervalSince(session.savedAt) / 3600
        guard hoursSince < 12 else {
            chatHistoryData = Data()
            return
        }
        messages = session.messages.map { $0.toChatMessage() }
        hasFiredProactive = true
    }
}

// MARK: - Quick Action Chip

private struct QuickActionChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
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

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let onAction: (ChatMessage.ActionType) -> Void
    let onQuickReply: (String) -> Void

    @State private var displayedText: String = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                assistantAvatar
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            } else {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 8) {
                bubbleContent

                if let card = message.contextCard {
                    contextCardView(card)
                }

                if let action = message.action, let label = message.actionLabel {
                    Button { onAction(action) } label: {
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

                if !message.quickReplies.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(message.quickReplies, id: \.self) { reply in
                                Button { onQuickReply(reply) } label: {
                                    Text(reply)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.sweeplyNavy)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.sweeplyNavy.opacity(0.06))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.sweeplyBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Text(message.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
            }

            if message.role == .user {
                userAvatar
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            } else {
                Spacer(minLength: 60)
            }
        }
        .onAppear { startTypewriter() }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                let text = message.text
                let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let vc = scene.windows.first?.rootViewController {
                    vc.present(av, animated: true)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        let bubbleBg: Color = {
            if message.role == .user { return Color.sweeplyNavy }
            switch message.messageStyle {
            case .warning: return Color.sweeplyDestructive.opacity(0.08)
            case .info: return Color.sweeplyAccent.opacity(0.06)
            case .success: return Color.green.opacity(0.08)
            case .default: return Color.sweeplySurface
            }
        }()
        let textColor: Color = message.role == .user ? .white : Color.sweeplyNavy
        let borderColor: Color = {
            if message.role == .user { return Color.clear }
            switch message.messageStyle {
            case .warning: return Color.sweeplyDestructive.opacity(0.25)
            case .info: return Color.sweeplyAccent.opacity(0.2)
            case .success: return Color.green.opacity(0.2)
            case .default: return Color.sweeplyBorder
            }
        }()

        HStack(spacing: 0) {
            if message.role == .assistant && message.messageStyle != .default {
                Rectangle()
                    .fill(styleBorderColor)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            Text(displayedText.isEmpty && !message.isNew ? message.text : displayedText)
                .font(.system(size: 14))
                .foregroundStyle(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
        .background(bubbleBg)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var styleBorderColor: Color {
        switch message.messageStyle {
        case .warning: return Color.sweeplyDestructive
        case .info: return Color.sweeplyAccent
        case .success: return Color.green
        case .default: return Color.clear
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle().fill(Color.sweeplyNavy).frame(width: 28, height: 28)
            Text("S").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(.white)
        }
    }

    private var userAvatar: some View {
        ZStack {
            Circle().fill(Color.sweeplyNavy.opacity(0.12)).frame(width: 28, height: 28)
            Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(Color.sweeplyNavy)
        }
    }

    @ViewBuilder
    private func contextCardView(_ card: ChatMessage.ContextCard) -> some View {
        switch card {
        case .jobs(let previews):
            VStack(spacing: 6) {
                ForEach(previews, id: \.clientName) { preview in
                    JobPreviewCard(preview: preview)
                }
            }
        case .invoices(let previews):
            VStack(spacing: 6) {
                ForEach(previews, id: \.invoiceNumber) { preview in
                    InvoicePreviewCard(preview: preview)
                }
            }
        case .confirmJob(let draft):
            JobConfirmCard(draft: draft)
        case .confirmClient:
            EmptyView()
        }
    }

    private func startTypewriter() {
        guard message.isNew && message.role == .assistant else {
            displayedText = message.text
            return
        }
        displayedText = ""
        let chars = Array(message.text)
        var index = 0
        func next() {
            guard index < chars.count else { return }
            displayedText.append(chars[index])
            index += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { next() }
        }
        next()
    }
}

// MARK: - Job Preview Card

private struct JobPreviewCard: View {
    let preview: ChatMessage.JobPreview

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.clientName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                HStack(spacing: 6) {
                    Text(preview.serviceType)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text(preview.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            Spacer()
            Text(preview.price.formatted(.currency(code: "USD")))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
    }

    private var statusColor: Color {
        switch preview.status {
        case .scheduled: return Color.sweeplyAccent
        case .inProgress: return Color.sweeplyWarning
        case .completed: return Color.green
        case .cancelled: return Color.sweeplyDestructive
        }
    }
}

// MARK: - Invoice Preview Card

private struct InvoicePreviewCard: View {
    let preview: ChatMessage.InvoicePreview

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preview.invoiceNumber)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy)
                    statusBadge
                }
                HStack(spacing: 4) {
                    Text(preview.clientName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                    Text("• Due \(preview.dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sweeplyTextSub)
                }
            }
            Spacer()
            Text(preview.amount.formatted(.currency(code: "USD")))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(preview.status == .overdue ? Color.sweeplyDestructive : Color.sweeplyNavy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(preview.status == .overdue ? Color.sweeplyDestructive.opacity(0.04) : Color.sweeplyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(preview.status == .overdue ? Color.sweeplyDestructive.opacity(0.2) : Color.sweeplyBorder, lineWidth: 1))
    }

    private var statusBadge: some View {
        let color: Color = {
            switch preview.status {
            case .overdue: return Color.sweeplyDestructive
            case .paid: return Color.green
            case .unpaid: return Color.sweeplyTextSub
            }
        }()
        return Text(preview.status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Job Confirmation Card

private struct JobConfirmCard: View {
    let draft: JobDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JOB SUMMARY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(0.8)

            VStack(spacing: 8) {
                if let name = draft.clientName {
                    confirmRow(icon: "person.fill", label: "Client", value: name)
                }
                if let service = draft.serviceType {
                    confirmRow(icon: "sparkles", label: "Service", value: service.rawValue)
                }
                if let date = draft.date {
                    confirmRow(icon: "calendar", label: "Date", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                if let price = draft.price {
                    confirmRow(icon: "dollarsign.circle", label: "Price", value: price.formatted(.currency(code: "USD")))
                }
            }
        }
        .padding(14)
        .background(Color.sweeplyAccent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyAccent.opacity(0.2), lineWidth: 1))
    }

    private func confirmRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.sweeplyTextSub)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().fill(Color.sweeplyNavy).frame(width: 28, height: 28)
                Text("S").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.sweeplyTextSub)
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1.3 : 0.7)
                        .opacity(animating ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.sweeplyBorder, lineWidth: 1))
            Spacer()
        }
        .onAppear { animating = true }
    }
}
