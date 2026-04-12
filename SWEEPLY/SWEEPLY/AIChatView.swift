import AVFoundation
import Speech
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

// MARK: - Chat Projects

struct ChatProject: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

// MARK: - Conversation State

enum DirectAction {
    case markJobComplete(Job)
    case markInvoicePaid(Invoice)
    case rescheduleJob(Job, Date)
}

enum ConversationState {
    case idle
    case collectingJob(JobDraft)
    case awaitingJobConfirmation(JobDraft)
    case collectingClient(ClientDraft)
    case awaitingReminder(String)
    case awaitingDirectAction(DirectAction)
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
        if clientName == nil { return "Who's this job for? Pick a client or type their name." }
        if serviceType == nil { return "What kind of clean? Pick a service type." }
        if date == nil { return "When's it happening? You can say 'tomorrow', 'next Monday', or a specific date." }
        if price == nil { return "How much are you charging? (e.g. 150 or $180)" }
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
    let id: UUID
    var projectId: UUID?
    let savedAt: Date
    let messages: [PersistedMessage]
    var title: String = ""
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
    var financeMode: Bool = false

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isAssistantTyping: Bool = false
    @State private var conversationState: ConversationState = .idle
    @State private var hasFiredProactive: Bool = false
    @State private var lastIntent: String? = nil
    @State private var showSlashMenu: Bool = false   // kept for legacy state compat
    @State private var showCommandPalette: Bool = false
    @State private var showHistory: Bool = false
    @State private var showMenu: Bool = false
    @FocusState private var isInputFocused: Bool

    // Chat title
    @State private var chatTitle: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""

    private var displayTitle: String {
        chatTitle.isEmpty ? "Untitled chat" : chatTitle
    }

    // Projects system
    @AppStorage("aiChatProjectsV1") private var projectsData: Data = Data()
    @State private var currentProjectId: UUID? = nil
    @State private var showProjectPicker: Bool = false

    @AppStorage("aiChatOnboardingDone") private var onboardingDone: Bool = false
    @State private var onboardingStep: Int = 0
    @State private var showOnboarding: Bool = false

    // Suggestion tracking
    enum MessageSource {
        case suggestion
        case manual
    }
    @State private var firstMessageSource: MessageSource? = nil
    @State private var nonSuggestionMessageCount: Int = 0
    @State private var selectedInitialSuggestion: String? = nil

    // Voice input
    @State private var isRecording: Bool = false
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)

    private var slashCommands: [(command: String, icon: String, label: String, query: String)] {
        [
            ("/jobs",     "briefcase.fill",             "My Jobs",         "Show my upcoming jobs"),
            ("/today",    "calendar",                   "Today",           "What's on my schedule today?"),
            ("/revenue",  "chart.line.uptrend.xyaxis",  "Revenue",         "What's my revenue?"),
            ("/clients",  "person.2.fill",              "Clients",         "Show my clients"),
            ("/invoice",  "doc.badge.plus",             "New Invoice",     "Create a new invoice"),
            ("/insights", "sparkles",                   "Insights",        "Give me business insights"),
            ("/overview", "square.grid.2x2.fill",       "Overview",        "Business overview"),
            ("/help",     "questionmark.circle",        "Help",            "What can you do?"),
            ("/cancel",  "xmark.circle",               "Cancel Job",      "Cancel a job"),
            ("/start",   "play.fill",                  "Start Job",       "Start my next job"),
            ("/rebook",  "arrow.counterclockwise",     "Rebook",          "Book the same job again"),
        ]
    }

    @AppStorage("sweeplyAIChatHistoryV2") private var chatHistoryData: Data = Data()
    @AppStorage("aiChatSessionsV1") private var chatSessionsData: Data = Data()
    @AppStorage("sweeplyAIChatSavedAt") private var chatSavedAt: Double = 0

    private var firstName: String {
        profileStore.profile?.fullName.components(separatedBy: " ").first ?? "there"
    }

    private var chatSuggestions: [(label: String, query: String)] {
        if financeMode {
            return [
                ("Revenue",         "What's my revenue this month?"),
                ("Overdue",         "Show my overdue invoices"),
                ("Outstanding",     "What's my outstanding balance?"),
                ("Best client",     "Who's my best paying client?"),
                ("Cash flow",       "How's my cash flow this week?"),
                ("Mark paid",       "Mark an invoice as paid"),
                ("Collection rate", "What's my collection rate?"),
                ("Year to date",    "What's my revenue year to date?"),
            ]
        }
        return [
            ("Today's jobs",   "What's on my schedule today?"),
            ("Revenue",        "What's my revenue this month?"),
            ("New job",        "I want to schedule a new job"),
            ("New client",     "Add a new client"),
            ("Invoice",        "Create a new invoice"),
            ("Insights",       "Give me business insights"),
        ]
    }

    // Dynamic suggestions based on user selection
    private var currentSuggestions: [(label: String, query: String)] {
        if let selected = selectedInitialSuggestion {
            switch selected {
            case "Revenue", "What's my revenue this month?":
                return [
                    ("Outstanding", "What's my outstanding balance?"),
                    ("Overdue", "Show my overdue invoices"),
                    ("Collection rate", "What's my collection rate?"),
                    ("Year to date", "What's my revenue year to date?"),
                    ("Cash flow", "How's my cash flow this week?"),
                ]
            case "Today's jobs", "What's on my schedule today?":
                return [
                    ("Tomorrow", "What's on my schedule tomorrow?"),
                    ("This week", "Show my jobs this week"),
                    ("Next week", "What's scheduled next week?"),
                    ("All jobs", "Show all my jobs"),
                ]
            case "New job", "I want to schedule a new job":
                return [
                    ("Add client", "Add a new client"),
                    ("View clients", "Show my clients"),
                    ("Invoice", "Create a new invoice"),
                ]
            case "New client", "Add a new client":
                return [
                    ("Schedule job", "Schedule a new job"),
                    ("View clients", "Show my clients"),
                    ("Invoice", "Create a new invoice"),
                ]
            case "Invoice", "Create a new invoice":
                return [
                    ("Unpaid", "Show my unpaid invoices"),
                    ("Overdue", "Show my overdue invoices"),
                    ("Revenue", "What's my revenue this month?"),
                ]
            case "Insights", "Give me business insights":
                return [
                    ("Revenue", "What's my revenue this month?"),
                    ("Best client", "Who's my best paying client?"),
                    ("Cash flow", "How's my cash flow this week?"),
                ]
            default:
                return chatSuggestions
            }
        }
        return chatSuggestions
    }

    // Whether to show suggestions carousel
    private var showSuggestions: Bool {
        guard firstMessageSource != nil else { return true }
        
        if firstMessageSource == .manual {
            return false
        }
        
        return nonSuggestionMessageCount < 2
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
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            messages.removeAll { $0.id == message.id }
                                            persistChat()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
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
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                if value.translation.height > 100 && isInputFocused {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    isInputFocused = false
                                }
                            }
                    )
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

                if showSuggestions {
                    suggestionsCarousel
                }

                // Quick Actions sheet (replaces slash-triggered menu)
                .sheet(isPresented: $showCommandPalette) {
                    quickActionsSheet
                        .presentationDetents([.fraction(0.5), .large])
                        .presentationDragIndicator(.visible)
                }

                Divider()
                inputBar
            }
            .background(Color.sweeplyBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sweeplyBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.sweeplyAccent, Color.sweeplyAccent.opacity(0.75)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 30, height: 30)
                                Text("S")
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.sweeplyBackground, lineWidth: 1.5))
                                .offset(x: 2, y: -2)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sweeply AI")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            if messages.contains(where: { $0.role == .user }) {
                                Button {
                                    renameText = chatTitle
                                    showRenameAlert = true
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(displayTitle)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(chatTitle.isEmpty ? Color.sweeplyTextSub.opacity(0.5) : Color.sweeplyTextSub)
                                            .lineLimit(1)
                                        Image(systemName: "pencil")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            saveToHistory()
                            messages = []
                            currentProjectId = nil
                            chatTitle = ""
                            conversationState = .idle
                            hasFiredProactive = false
                            chatHistoryData = Data()
                            // Reset suggestion tracking
                            firstMessageSource = nil
                            nonSuggestionMessageCount = 0
                            selectedInitialSuggestion = nil
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        .tint(Color.sweeplyNavy)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showHistory = true
                        } label: {
                            Label("Chat History", systemImage: "clock.arrow.circlepath")
                        }
                        .tint(Color.sweeplyNavy)

                        if messages.contains(where: { $0.role == .user }) {
                            Divider()

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showProjectPicker = true
                            } label: {
                                Label("Assign to Project", systemImage: "folder.badge.plus")
                            }
                            .tint(Color.sweeplyNavy)
                        }

                        Divider()

                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            saveToHistory()
                            messages = []
                            currentProjectId = nil
                            chatTitle = ""
                            conversationState = .idle
                            hasFiredProactive = false
                            chatHistoryData = Data()
                        } label: {
                            Label("Delete Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                            .frame(width: 36, height: 36)
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
                if !onboardingDone {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeOut(duration: 0.25)) { showOnboarding = true }
                    }
                }
            }
            .alert("Rename Chat", isPresented: $showRenameAlert) {
                TextField("Chat title", text: $renameText)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    chatTitle = trimmed.isEmpty ? chatTitle : trimmed
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Give this conversation a name.")
            }
            .onDisappear {
                persistChat()
                if !messages.isEmpty {
                    saveToHistory()
                }
            }
            .onChange(of: currentProjectId) { oldId, newId in
                // Save current conversation under the old project before switching
                if !messages.isEmpty {
                    saveToHistory()
                }
                // Load the most recent session for the new project, or start fresh
                let sessions = loadSessionHistory()
                if let match = sessions.first(where: { $0.projectId == newId }) {
                    restoreSession(match)
                } else {
                    messages = []
                    chatTitle = ""
                    hasFiredProactive = false
                    // Reset suggestion tracking for new session
                    firstMessageSource = nil
                    nonSuggestionMessageCount = 0
                    selectedInitialSuggestion = nil
                    fireProactiveMessage()
                }
            }
            .overlay(alignment: .bottom) {
                if showOnboarding {
                    aiOnboardingOverlay
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .sheet(isPresented: $showHistory) {
                let history = loadSessionHistory()
                let currentAsSession: [PersistedSession] = messages.isEmpty ? [] : [
                    PersistedSession(
                        id: UUID(),
                        projectId: currentProjectId,
                        savedAt: Date(),
                        messages: Array(messages.suffix(60).map { PersistedMessage(from: $0) }),
                        title: chatTitle
                    )
                ]
                ChatHistorySheet(
                    sessions: currentAsSession + history,
                    currentSessionId: currentAsSession.first?.id,
                    projects: loadProjects(),
                    onRestore: { session in
                        restoreSession(session)
                    },
                    onDelete: { session in
                        var sessions = loadSessionHistory()
                        sessions.removeAll { $0.id == session.id }
                        chatSessionsData = (try? JSONEncoder().encode(sessions)) ?? Data()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showProjectPicker) {
                projectPickerSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - AI Chat Menu

    private var aiChatMenu: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.sweeplyTextSub.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            VStack(spacing: 0) {
                // New Chat
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMenu = false
                    saveToHistory()
                    messages = []
                    currentProjectId = nil
                    conversationState = .idle
                    hasFiredProactive = false
                    chatHistoryData = Data()
                    // Reset suggestion tracking
                    firstMessageSource = nil
                    nonSuggestionMessageCount = 0
                    selectedInitialSuggestion = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                            .frame(width: 24)
                        Text("New Chat")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 52)

                // Chat History
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMenu = false
                    showHistory = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                            .frame(width: 24)
                        Text("Chat History")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 52)

                // Add to Project - only show when user has sent at least 1 message
                if messages.contains(where: { $0.role == .user }) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showMenu = false
                        showProjectPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                                .frame(width: 24)
                            Text("Assign to Project")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 52)
                }

                // Delete Chat (RED)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showMenu = false
                    saveToHistory()
                    messages = []
                    currentProjectId = nil
                    conversationState = .idle
                    hasFiredProactive = false
                    chatHistoryData = Data()
                    // Reset suggestion tracking
                    firstMessageSource = nil
                    nonSuggestionMessageCount = 0
                    selectedInitialSuggestion = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyDestructive)
                            .frame(width: 24)
                        Text("Delete Chat")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyDestructive)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .background(Color.sweeplySurface)
    }

    // MARK: - Project Picker Sheet

    @State private var newProjectName: String = ""

    private var projectPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Current assignment indicator
                if let projectId = currentProjectId {
                    let projects = loadProjects()
                    if let project = projects.first(where: { $0.id == projectId }) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.sweeplyAccent)
                            Text("Currently in: \(project.name)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        .padding(.top, 8)
                    }
                }

                // Create new project
                HStack(spacing: 8) {
                    TextField("New project name", text: $newProjectName)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))

                    Button {
                        guard !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        var projects = loadProjects()
                        let project = ChatProject(name: newProjectName.trimmingCharacters(in: .whitespaces))
                        projects.append(project)
                        saveProjects(projects)
                        currentProjectId = project.id
                        newProjectName = ""
                        showProjectPicker = false
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.sweeplyAccent)
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)

                Divider()

                // General option
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    currentProjectId = nil
                    showProjectPicker = false
                } label: {
                    HStack {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text("General")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.sweeplyNavy)
                        Spacer()
                        if currentProjectId == nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.sweeplyAccent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                // Existing projects
                let projects = loadProjects()
                ForEach(projects) { project in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        currentProjectId = project.id
                        showProjectPicker = false
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.sweeplyAccent)
                            Text(project.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                            Spacer()
                            if currentProjectId == project.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.sweeplyAccent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .navigationTitle("Add to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showProjectPicker = false
                    }
                }
            }
        }
    }

    // MARK: - AI Onboarding Tour

    private var aiOnboardingOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // Step indicator dots
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i == onboardingStep ? Color.sweeplyAccent : Color.sweeplyBorder)
                            .frame(width: i == onboardingStep ? 8 : 6, height: i == onboardingStep ? 8 : 6)
                            .animation(.easeOut(duration: 0.2), value: onboardingStep)
                    }
                }

                VStack(spacing: 8) {
                    Text(onboardingStepTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .multilineTextAlignment(.center)
                    Text(onboardingStepSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                HStack(spacing: 12) {
                    if onboardingStep < 2 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeOut(duration: 0.25)) { onboardingStep += 1 }
                        } label: {
                            Text("Next")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 11)
                                .background(Color.sweeplyNavy)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeOut(duration: 0.25)) { showOnboarding = false }
                            onboardingDone = true
                        } label: {
                            Text("Got it")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 11)
                                .background(Color.sweeplyNavy)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.sweeplySurface)
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color.black.opacity(0.35).ignoresSafeArea())
    }

    private var onboardingStepTitle: String {
        switch onboardingStep {
        case 0: return "Quick actions at a tap"
        case 1: return "Shortcuts for power users"
        default: return "Or just type naturally"
        }
    }

    private var onboardingStepSubtitle: String {
        switch onboardingStep {
        case 0: return "Tap any suggestion chip above to instantly get revenue summaries, today's jobs, or client insights."
        case 1: return "Type \"/\" to open the command menu with shortcuts for jobs, invoices, revenue, and more."
        default: return "Ask me anything in plain English — \"what's my revenue this month?\" or \"mark John's job as done\"."
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 32)

            // Typographic greeting — no avatar, left-aligned, warm palette
            VStack(alignment: .leading, spacing: 4) {
                Text(timeGreeting)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyAccent)
                    .tracking(0.5)
                Text("\(firstName).")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
            }

            Text("Ask me anything about your business,\nor tap + to browse quick actions.")
                .font(.system(size: 14))
                .foregroundStyle(Color.sweeplyTextSub)
                .lineSpacing(3)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sweeplyBackground)
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Suggestions Carousel

    private var suggestionsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currentSuggestions, id: \.label) { suggestion in
                    Button { sendMessage(suggestion.query) } label: {
                        Text(suggestion.label)
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
        .background(Color.sweeplyBackground)
    }

    // MARK: - Quick Actions Menu (+ button)

    private var quickActionsMenu: some View {
        Menu {
            // Show Create Actions only when suggestions are hidden
            if !showSuggestions {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    sendMessage("I want to schedule a new job")
                } label: {
                    Label("Schedule Job", systemImage: "calendar.badge.plus")
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    sendMessage("Add a new client")
                } label: {
                    Label("Add Client", systemImage: "person.badge.plus")
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    sendMessage("Create a new invoice")
                } label: {
                    Label("Create Invoice", systemImage: "doc.badge.plus")
                }

                Divider()
            }

            // Quick View Actions - always show
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sendMessage("What's on my schedule today?")
            } label: {
                Label("Today's Schedule", systemImage: "calendar.day.timeline.left")
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sendMessage("What's my revenue this month?")
            } label: {
                Label("Revenue", systemImage: "chart.line.uptrend.xyaxis")
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sendMessage("Show my clients")
            } label: {
                Label("My Clients", systemImage: "person.2.fill")
            }

            Divider()

            // Utilities - always show
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sendMessage("Give me business insights")
            } label: {
                Label("Business Insights", systemImage: "sparkles")
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sendMessage("What can you do?")
            } label: {
                Label("Help & Tips", systemImage: "questionmark.circle")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.sweeplySurface)
                    .frame(width: 36, height: 36)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Actions Sheet (legacy - kept for compatibility but no longer used)

    private var quickActionsSheet: some View {
        VStack(spacing: 0) {
            // Drag handle + header
            HStack {
                Text("Quick Actions")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showCommandPalette = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            ForEach(slashCommands, id: \.command) { cmd in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showCommandPalette = false }
                    inputText = ""
                    sendMessage(cmd.query)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.sweeplyNavy.opacity(0.08))
                                .frame(width: 32, height: 32)
                            Image(systemName: cmd.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cmd.command)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyNavy)
                            Text(cmd.label)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if cmd.command != slashCommands.last?.command {
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Quick Actions (+) button with menu
            quickActionsMenu

            TextField(isRecording ? "Listening..." : "Ask me anything...", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(
                    isRecording ? Color.red.opacity(0.4) : Color.sweeplyNavy.opacity(0.12),
                    lineWidth: isRecording ? 1.5 : 1
                ))
                .focused($isInputFocused)

            // Mic (when input is empty) or Send (when there's text)
            if inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if isRecording { stopRecording() } else { startRecording() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.12) : Color.sweeplySurface)
                            .frame(width: 36, height: 36)
                        Image(systemName: isRecording ? "waveform" : "mic")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isRecording ? Color.red : Color.sweeplyTextSub)
                            .symbolEffect(.variableColor, isActive: isRecording)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    let trimmed = inputText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.15)) { 
                        showCommandPalette = false 
                    }
                    if isRecording { stopRecording() }
                    inputText = ""
                    isInputFocused = false
                    sendMessage(trimmed)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyAccent)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: inputText.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.sweeplyBackground)
    }

    // MARK: - Voice Recording

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else { return }
                DispatchQueue.main.async { beginAudioSession() }
            }
        }
    }

    private func beginAudioSession() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result {
                DispatchQueue.main.async { inputText = result.bestTranscription.formattedString }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async { stopRecording() }
            }
        }

        do {
            try audioEngine.start()
            withAnimation { isRecording = true }
        } catch {
            stopRecording()
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        withAnimation { isRecording = false }
    }

    // MARK: - Send Logic

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Check if this message matches a suggestion (from suggestion tap)
        let isFromSuggestion = currentSuggestions.contains { $0.query == trimmed }

        // Track message source on first user message
        if firstMessageSource == nil {
            firstMessageSource = isFromSuggestion ? .suggestion : .manual
            if isFromSuggestion {
                selectedInitialSuggestion = trimmed
            }
        } else if !isFromSuggestion {
            // After first message, track non-suggestion messages
            nonSuggestionMessageCount += 1
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        inputText = ""
        withAnimation(.easeInOut(duration: 0.15)) { showSlashMenu = false }

        // Auto-title from first user message
        if chatTitle.isEmpty && !messages.contains(where: { $0.role == .user }) {
            chatTitle = generateChatTitle(from: trimmed)
        }

        let userMsg = ChatMessage(role: .user, text: trimmed)
        messages.append(userMsg)

        isAssistantTyping = true
        let delay = Double.random(in: 0.5...0.9)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // Race generateResponse against a 10-second hard timeout
            let response: ChatMessage = await withTaskGroup(of: ChatMessage.self) { group in
                group.addTask { await self.generateResponse(for: trimmed) }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    return ChatMessage(
                        role: .assistant,
                        text: "I'm having trouble connecting right now. Try again in a moment.",
                        quickReplies: ["Today's jobs", "Business overview"]
                    )
                }
                guard let first = await group.next() else {
                    group.cancelAll()
                    return ChatMessage(
                        role: .assistant,
                        text: "Something went wrong. Please try again.",
                        quickReplies: ["Today's jobs", "Business overview"]
                    )
                }
                group.cancelAll()
                return first
            }

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
            // Proactive nudges — fire after a short delay if conditions warrant
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                fireProactiveNudges(mainMessageMentionedOverdue: msg.messageStyle == .warning)
            }
        }
    }

    private func fireProactiveNudges(mainMessageMentionedOverdue: Bool) {
        guard !financeMode else { return } // Finance mode snapshot already covers all nudges
        let overdueInvoices = invoicesStore.invoices.filter { $0.status == .overdue }
        let todayJobs = jobsStore.jobs.filter { Calendar.current.isDateInToday($0.date) && $0.status == .scheduled }.sorted { $0.date < $1.date }

        // Nudge 1: overdue invoices not already mentioned
        if overdueInvoices.count >= 2 && !mainMessageMentionedOverdue {
            let total = overdueInvoices.reduce(0.0) { $0 + $1.subtotal }
            let nudge = ChatMessage(
                role: .assistant,
                text: "By the way, you have \(overdueInvoices.count) overdue invoices totaling \(total.formatted(.currency(code: "USD"))). Want me to list them?",
                style: .warning,
                quickReplies: ["Show overdue", "Remind me later"]
            )
            messages.append(nudge)
            persistChat()
            return
        }

        // Nudge 2: 3+ jobs today
        if todayJobs.count >= 3 {
            let firstName = todayJobs[0].clientName
            let timeStr = todayJobs[0].date.formatted(date: .omitted, time: .shortened)
            let nudge = ChatMessage(
                role: .assistant,
                text: "You've got a full day ahead — \(todayJobs.count) jobs scheduled. Your first job is \(firstName) at \(timeStr).",
                style: .info,
                quickReplies: ["See today's schedule"]
            )
            messages.append(nudge)
            persistChat()
        }
    }

    private func buildProactiveMessage() -> ChatMessage {
        let overdue = invoicesStore.invoices.filter { $0.status == .overdue }
        let todayJobs = jobsStore.jobs.filter { Calendar.current.isDateInToday($0.date) && $0.status == .scheduled }
        let upcomingJobs = jobsStore.jobs.filter { $0.date > Date() && $0.status == .scheduled }.sorted { $0.date < $1.date }
        let activeClients = clientsStore.clients.filter { $0.isActive }
        let isNewUser = clientsStore.clients.isEmpty && jobsStore.jobs.isEmpty

        // Finance-mode: open with an immediate financial snapshot
        if financeMode {
            let collected = invoicesStore.invoices.filter { $0.status == .paid }.reduce(0.0) { $0 + $1.subtotal }
            let outstanding = invoicesStore.invoices.filter { $0.status == .unpaid }.reduce(0.0) { $0 + $1.subtotal }
            let overdueList = invoicesStore.invoices.filter { $0.status == .overdue }
            let overdueTotal = overdueList.reduce(0.0) { $0 + $1.subtotal }
            let thisMonth = invoicesStore.invoices.filter {
                $0.status == .paid && Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month)
            }.reduce(0.0) { $0 + $1.subtotal }

            var text = "Here's your financial snapshot — \(thisMonth.formatted(.currency(code: "USD"))) collected this month, \(outstanding.formatted(.currency(code: "USD"))) outstanding."
            if !overdueList.isEmpty {
                text += " You have \(overdueList.count) overdue invoice\(overdueList.count == 1 ? "" : "s") totaling \(overdueTotal.formatted(.currency(code: "USD"))) that need attention."
            }
            let style: ChatMessage.MessageStyle = overdueList.isEmpty ? .info : .warning
            let replies = overdueList.isEmpty
                ? ["Revenue breakdown", "Outstanding invoices", "Best paying client"]
                : ["Show overdue", "Mark invoice paid", "Revenue breakdown"]
            return ChatMessage(role: .assistant, text: text, style: style, quickReplies: replies)
        }

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

    @MainActor
    private func generateResponse(for input: String) async -> ChatMessage {
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
        case .awaitingDirectAction(let action):
            return await handleDirectActionConfirmation(input: input, lowered: lowered, action: action)
        case .idle:
            break
        }

        // DIRECT ACTION: Reschedule job
        let isReschedule = (lowered.contains("reschedule") || lowered.contains("move") || lowered.contains("postpone") || lowered.contains("change date")) &&
            (lowered.contains("job") || lowered.contains("appointment") || lowered.contains("clean") ||
             clientsStore.clients.contains { c in c.name.lowercased().components(separatedBy: " ").contains { $0.count > 2 && lowered.contains($0) } })
        if isReschedule {
            for client in clientsStore.clients {
                let parts = client.name.lowercased().components(separatedBy: " ")
                if parts.contains(where: { lowered.contains($0) && $0.count > 2 }) {
                    if let job = jobsStore.jobs.first(where: { $0.clientId == client.id && ($0.status == .scheduled || $0.status == .inProgress) }) {
                        conversationState = .awaitingDirectAction(.rescheduleJob(job, Date.distantPast))
                        return ChatMessage(
                            role: .assistant,
                            text: "What date and time would you like to reschedule \(client.name)'s \(job.serviceType.rawValue) to?",
                            style: .info,
                            quickReplies: ["Tomorrow", "Next Monday", "Next Wednesday", "Next Friday"]
                        )
                    }
                }
            }
            // No client match — use next scheduled job
            if let nextJob = jobsStore.jobs.filter({ $0.status == .scheduled }).sorted(by: { $0.date < $1.date }).first {
                conversationState = .awaitingDirectAction(.rescheduleJob(nextJob, Date.distantPast))
                return ChatMessage(
                    role: .assistant,
                    text: "What date and time would you like to reschedule \(nextJob.clientName)'s \(nextJob.serviceType.rawValue) to?",
                    style: .info,
                    quickReplies: ["Tomorrow", "Next Monday", "Next Wednesday", "Next Friday"]
                )
            }
            return ChatMessage(role: .assistant, text: "No upcoming jobs found to reschedule.", quickReplies: ["Schedule a job"])
        }

        // FOCUS / PRIORITIZE
        let isFocusIntent = lowered.contains("focus") || lowered.contains("most important") || lowered.contains("what do i need to do") || lowered.contains("prioritize") || lowered.contains("what should i") || lowered == "help me focus"
        if isFocusIntent {
            return buildFocusBriefing()
        }

        // EDIT JOB THROUGH CHAT
        let isEditJob = (lowered.contains("update") || lowered.contains("change") || lowered.contains("edit")) &&
            (lowered.contains("job") || lowered.contains("price") || lowered.contains("time") ||
             clientsStore.clients.contains { c in c.name.lowercased().components(separatedBy: " ").contains { $0.count > 2 && lowered.contains($0) } })
        if isEditJob {
            for client in clientsStore.clients {
                let parts = client.name.lowercased().components(separatedBy: " ")
                if parts.contains(where: { lowered.contains($0) && $0.count > 2 }) {
                    if var job = jobsStore.jobs.filter({ $0.clientId == client.id && $0.status == .scheduled }).sorted(by: { $0.date < $1.date }).first {
                        // Detect price change
                        if let newPrice = extractPrice(from: lowered) {
                            job.price = newPrice
                            conversationState = .awaitingDirectAction(.rescheduleJob(job, job.date))
                            // Use rescheduleJob as a vessel — we override in confirmation
                            return ChatMessage(
                                role: .assistant,
                                text: "Update \(client.name)'s \(job.serviceType.rawValue) price to \(newPrice.formatted(.currency(code: "USD")))?",
                                style: .info,
                                quickReplies: ["Yes, update", "Cancel"]
                            )
                        }
                        // Detect time change
                        let timePattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#
                        if let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
                           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)) {
                            let hourRange = Range(match.range(at: 1), in: lowered)
                            let minuteRange = Range(match.range(at: 2), in: lowered)
                            let periodRange = Range(match.range(at: 3), in: lowered)
                            if let hourRange, var hour = Int(lowered[hourRange]) {
                                let minute = minuteRange.flatMap { Int(lowered[$0]) } ?? 0
                                let period = periodRange.map { String(lowered[$0]).lowercased() }
                                if period == "pm" && hour < 12 { hour += 12 }
                                if period == "am" && hour == 12 { hour = 0 }
                                let calendar = Calendar.current
                                if let newDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: job.date) {
                                    job.date = newDate
                                    conversationState = .awaitingDirectAction(.rescheduleJob(job, newDate))
                                    let timeStr = newDate.formatted(date: .omitted, time: .shortened)
                                    return ChatMessage(
                                        role: .assistant,
                                        text: "Update \(client.name)'s \(job.serviceType.rawValue) time to \(timeStr)?",
                                        style: .info,
                                        quickReplies: ["Yes, update", "Cancel"]
                                    )
                                }
                            }
                        }
                        return ChatMessage(role: .assistant, text: "What would you like to change for \(client.name)'s job? For example: \"change price to $150\" or \"update time to 2pm\".", quickReplies: ["Cancel"])
                    }
                }
            }
        }

        // DIRECT ACTION: Mark job complete
        let isMarkComplete = (lowered.contains("mark") || lowered.contains("complete") || lowered.contains("finish") || lowered.contains("done")) &&
            (lowered.contains("job") || lowered.contains("clean") || lowered.contains("appointment"))
        if isMarkComplete {
            for client in clientsStore.clients {
                let parts = client.name.lowercased().components(separatedBy: " ")
                if parts.contains(where: { lowered.contains($0) && $0.count > 2 }) {
                    if let job = jobsStore.jobs.first(where: { $0.clientId == client.id && $0.status == .scheduled }) {
                        conversationState = .awaitingDirectAction(.markJobComplete(job))
                        return ChatMessage(
                            role: .assistant,
                            text: "I found a scheduled job for \(client.name) — \(job.serviceType.rawValue) on \(job.date.formatted(date: .abbreviated, time: .shortened)).\n\nMark it as completed?",
                            style: .info,
                            quickReplies: ["Yes, mark complete", "No, cancel"]
                        )
                    }
                }
            }
            // No name found — show most recent scheduled job
            if let recentJob = jobsStore.jobs.filter({ $0.status == .scheduled }).sorted(by: { $0.date < $1.date }).first {
                conversationState = .awaitingDirectAction(.markJobComplete(recentJob))
                return ChatMessage(
                    role: .assistant,
                    text: "Your next scheduled job is \(recentJob.serviceType.rawValue) for \(recentJob.clientName) on \(recentJob.date.formatted(date: .abbreviated, time: .shortened)).\n\nMark it as completed?",
                    style: .info,
                    quickReplies: ["Yes, mark complete", "No, cancel"]
                )
            }
            return ChatMessage(role: .assistant, text: "No scheduled jobs found to mark complete.", quickReplies: ["Schedule a job"])
        }

        // DIRECT ACTION: Mark invoice paid
        let isMarkPaid = (lowered.contains("mark") || lowered.contains("paid") || lowered.contains("pay")) &&
            (lowered.contains("invoice") || lowered.contains("bill") || lowered.contains("payment"))
        if isMarkPaid {
            // Try to match invoice number
            let invoicePattern = "INV-?[0-9]+"
            if let regex = try? NSRegularExpression(pattern: invoicePattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let matchRange = Range(match.range, in: input) {
                let invoiceNum = String(input[matchRange]).uppercased().replacingOccurrences(of: "INV", with: "INV-").replacingOccurrences(of: "INV--", with: "INV-")
                if let invoice = invoicesStore.invoices.first(where: { $0.invoiceNumber.uppercased() == invoiceNum && $0.status != .paid }) {
                    conversationState = .awaitingDirectAction(.markInvoicePaid(invoice))
                    return ChatMessage(
                        role: .assistant,
                        text: "Invoice \(invoice.invoiceNumber) — \(invoice.clientName) for \(invoice.subtotal.formatted(.currency(code: "USD"))).\n\nMark it as paid?",
                        style: .info,
                        quickReplies: ["Yes, mark paid", "No, cancel"]
                    )
                }
            }
            // Try client name match
            for client in clientsStore.clients {
                let parts = client.name.lowercased().components(separatedBy: " ")
                if parts.contains(where: { lowered.contains($0) && $0.count > 2 }) {
                    if let invoice = invoicesStore.invoices.first(where: { $0.clientId == client.id && $0.status != .paid }) {
                        conversationState = .awaitingDirectAction(.markInvoicePaid(invoice))
                        return ChatMessage(
                            role: .assistant,
                            text: "Found invoice \(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.subtotal.formatted(.currency(code: "USD"))).\n\nMark it as paid?",
                            style: .info,
                            quickReplies: ["Yes, mark paid", "No, cancel"]
                        )
                    }
                }
            }
            if let oldest = invoicesStore.invoices.filter({ $0.status != .paid }).sorted(by: { $0.dueDate < $1.dueDate }).first {
                conversationState = .awaitingDirectAction(.markInvoicePaid(oldest))
                return ChatMessage(
                    role: .assistant,
                    text: "Oldest unpaid invoice is \(oldest.invoiceNumber) for \(oldest.clientName) — \(oldest.subtotal.formatted(.currency(code: "USD"))).\n\nMark it as paid?",
                    style: .warning,
                    quickReplies: ["Yes, mark paid", "No, cancel"]
                )
            }
            return ChatMessage(role: .assistant, text: "No unpaid invoices found.", style: .success, quickReplies: ["Create invoice", "Business overview"])
        }

        // FOLLOW-UP CONTEXT: "last month?", "more details", "show all", "what about this week?"
        if let intent = lastIntent {
            let isFollowUp = lowered.contains("last month") || lowered.contains("this month") || lowered == "more" || lowered == "more details" || lowered.contains("show all") || lowered.contains("what about") || lowered.contains("and this week") || lowered.contains("this week?")
            if isFollowUp {
                if intent == "revenue" {
                    if lowered.contains("last month") {
                        if let lastMonthDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) {
                            let lastMonth = invoicesStore.invoices.filter { $0.status == .paid && Calendar.current.isDate($0.createdAt, equalTo: lastMonthDate, toGranularity: .month) }.reduce(0.0) { $0 + $1.subtotal }
                            return ChatMessage(role: .assistant, text: "Last month's collected revenue was \(lastMonth.formatted(.currency(code: "USD"))).", style: .info, quickReplies: ["This month?", "Business overview"])
                        }
                    }
                    if lowered.contains("this month") {
                        let thisMonth = invoicesStore.invoices.filter { $0.status == .paid && Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }.reduce(0.0) { $0 + $1.subtotal }
                        return ChatMessage(role: .assistant, text: "This month's collected revenue is \(thisMonth.formatted(.currency(code: "USD"))).", style: .info, quickReplies: ["Last month?", "Business overview"])
                    }
                }
                if intent == "jobs" && (lowered.contains("this week") || lowered.contains("show all")) {
                    if let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: Date()) {
                        let weekJobs = jobsStore.jobs.filter { $0.date >= Date() && $0.date <= weekOut }.sorted { $0.date < $1.date }
                        let previews = weekJobs.prefix(6).map { ChatMessage.JobPreview(clientName: $0.clientName, serviceType: $0.serviceType.rawValue, date: $0.date, status: $0.status, price: $0.price, address: $0.address) }
                        return ChatMessage(role: .assistant, text: "This week's jobs (\(weekJobs.count) total):", style: .info, quickReplies: ["Next week", "Add a job"], contextCard: .jobs(Array(previews)))
                    }
                }
            }
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
            lastIntent = "jobs"
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
            let todayVariants = [
                "You have \(todayJobs.count) job\(todayJobs.count == 1 ? "" : "s") today:",
                "Here's your schedule for today (\(todayJobs.count) job\(todayJobs.count == 1 ? "" : "s")):",
                "Today's \(todayJobs.count == 1 ? "job" : "\(todayJobs.count) jobs"):"
            ]
            return ChatMessage(
                role: .assistant,
                text: todayVariants.randomElement() ?? todayVariants[0],
                style: .info,
                quickReplies: ["Add another job", "This week?"],
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

        // ARCHIVED / INACTIVE CLIENTS — must come before the general client check
        let asksAboutArchived = lowered.contains("inactive") || lowered.contains("archived") || lowered.contains("archive")
        if asksAboutArchived && (lowered.contains("client") || lowered.contains("customer")) {
            let archived = clientsStore.clients.filter { !$0.isActive }
            if archived.isEmpty {
                return ChatMessage(role: .assistant, text: "All your clients are currently active — no archived clients.", style: .success, quickReplies: ["View all clients", "Business overview"])
            }
            let names = archived.prefix(4).map { $0.name }.joined(separator: ", ")
            let overflow = archived.count > 4 ? " and \(archived.count - 4) more" : ""
            return ChatMessage(
                role: .assistant,
                text: "You have \(archived.count) archived client\(archived.count == 1 ? "" : "s"): \(names)\(overflow). You can unarchive any of them from the Clients tab.",
                style: .info,
                action: .openClients,
                actionLabel: "View Clients",
                quickReplies: ["View all clients", "How do I unarchive?"]
            )
        }

        // CLIENT LIST
        if lowered.contains("client") || lowered.contains("customer") {
            let active = clientsStore.clients.filter { $0.isActive }
            let archivedCount = clientsStore.clients.filter { !$0.isActive }.count
            var text = "You have \(active.count) active client\(active.count == 1 ? "" : "s")"
            if archivedCount > 0 { text += " (\(archivedCount) archived)" }
            text += "."
            if let first = active.first { text += " Most recent: \(first.name)." }
            return ChatMessage(
                role: .assistant,
                text: text,
                style: .info,
                action: .openClients,
                actionLabel: "View All Clients",
                quickReplies: ["Add a client", "Who's my best client?", "New clients this month"]
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
            lastIntent = "revenue"
            let paidInvoices = invoicesStore.invoices.filter { $0.status == .paid }
            let collected = paidInvoices.reduce(0.0) { $0 + $1.subtotal }
            let pipeline = invoicesStore.invoices.filter { $0.status == .unpaid }.reduce(0.0) { $0 + $1.subtotal }
            let overdueAmt = invoicesStore.invoices.filter { $0.status == .overdue }.reduce(0.0) { $0 + $1.subtotal }

            let thisMonth = paidInvoices.filter {
                Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .month)
            }.reduce(0.0) { $0 + $1.subtotal }

            let revenueVariants = [
                "Financial snapshot:\n\n• Collected: \(collected.formatted(.currency(code: "USD")))\n• This month: \(thisMonth.formatted(.currency(code: "USD")))\n• Outstanding: \(pipeline.formatted(.currency(code: "USD")))",
                "Here's where you stand financially:\n\n• Total collected: \(collected.formatted(.currency(code: "USD")))\n• This month: \(thisMonth.formatted(.currency(code: "USD")))\n• In the pipeline: \(pipeline.formatted(.currency(code: "USD")))",
                "Revenue breakdown:\n\n• \(collected.formatted(.currency(code: "USD"))) collected total\n• \(thisMonth.formatted(.currency(code: "USD"))) this month\n• \(pipeline.formatted(.currency(code: "USD"))) outstanding"
            ]
            var text = revenueVariants.randomElement() ?? revenueVariants[0]
            if overdueAmt > 0 { text += "\n• Overdue: \(overdueAmt.formatted(.currency(code: "USD")))" }

            return ChatMessage(
                role: .assistant,
                text: text,
                style: .info,
                action: .openFinances,
                actionLabel: "View Full Finances",
                quickReplies: overdueAmt > 0 ? ["Who owes me most?", "Am I on track?"] : ["Am I on track?", "Year to date", "Who's my best client?"]
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
                quickReplies: ["Who's my best client?", "Am I on track?", "Most popular services"]
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

        // TOP CLIENT BY REVENUE
        if lowered.contains("best client") || lowered.contains("top client") || lowered.contains("most valuable client") || lowered.contains("who pays me the most") || lowered.contains("highest paying") || (lowered.contains("which client") && (lowered.contains("most") || lowered.contains("revenue") || lowered.contains("pays"))) {
            let clientRevenue = clientsStore.clients.map { client -> (name: String, revenue: Double, count: Int) in
                let paid = invoicesStore.invoices.filter { $0.clientId == client.id && $0.status == .paid }
                return (name: client.name, revenue: paid.reduce(0) { $0 + $1.subtotal }, count: paid.count)
            }.sorted { $0.revenue > $1.revenue }
            if let top = clientRevenue.first, top.revenue > 0 {
                var text = "Your top client by revenue is \(top.name) — \(top.revenue.formatted(.currency(code: "USD"))) collected across \(top.count) invoice\(top.count == 1 ? "" : "s")."
                if clientRevenue.count > 1, clientRevenue[1].revenue > 0 {
                    text += " Runner-up: \(clientRevenue[1].name) (\(clientRevenue[1].revenue.formatted(.currency(code: "USD"))))."
                }
                return ChatMessage(role: .assistant, text: text, style: .success, quickReplies: ["Business overview", "Revenue breakdown", "Who owes me most?"])
            } else {
                return ChatMessage(role: .assistant, text: "No paid invoices yet — once you start collecting, I'll rank your clients by revenue.", quickReplies: ["Create invoice", "Business overview"])
            }
        }

        // MONTHLY PACE / ON TRACK
        if lowered.contains("on track") || lowered.contains("on pace") || (lowered.contains("this month") && (lowered.contains("vs") || lowered.contains("compare") || lowered.contains("last month") || lowered.contains("pace"))) || lowered.contains("how's my month") || lowered.contains("am i on pace") {
            let calendar = Calendar.current
            let now = Date()
            let dayOfMonth = calendar.component(.day, from: now)
            let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            guard let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: calendar.startOfMonth(for: now)),
                  let lastMonthEnd = calendar.date(byAdding: .month, value: 1, to: lastMonthStart) else {
                return ChatMessage(role: .assistant, text: "Couldn't calculate monthly pace right now.", quickReplies: ["Check revenue"])
            }
            let thisMonthRevenue = invoicesStore.invoices.filter { $0.status == .paid && calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }.reduce(0.0) { $0 + $1.subtotal }
            let lastMonthRevenue = invoicesStore.invoices.filter { $0.status == .paid && $0.createdAt >= lastMonthStart && $0.createdAt < lastMonthEnd }.reduce(0.0) { $0 + $1.subtotal }
            let projectedRevenue = dayOfMonth > 0 ? (thisMonthRevenue / Double(dayOfMonth)) * Double(daysInMonth) : 0
            var text = "This month so far: \(thisMonthRevenue.formatted(.currency(code: "USD"))) (\(dayOfMonth) of \(daysInMonth) days in)."
            if lastMonthRevenue > 0 {
                text += "\nLast month total: \(lastMonthRevenue.formatted(.currency(code: "USD")))."
                text += "\nAt this pace, you're projected to collect \(projectedRevenue.formatted(.currency(code: "USD"))) — \(projectedRevenue >= lastMonthRevenue ? "ahead of" : "behind") last month."
            }
            return ChatMessage(role: .assistant, text: text, style: projectedRevenue >= lastMonthRevenue ? .success : .info, quickReplies: ["Check revenue", "Business overview", "Busiest month?"])
        }

        // YEAR TO DATE
        if lowered.contains("year to date") || lowered.contains("ytd") || (lowered.contains("this year") && (lowered.contains("revenue") || lowered.contains("make") || lowered.contains("earn") || lowered.contains("collect") || lowered.contains("how much"))) || lowered.contains("all of this year") {
            let calendar = Calendar.current
            let yearStart = calendar.startOfYear(for: Date())
            let ytdRevenue = invoicesStore.invoices.filter { $0.status == .paid && $0.createdAt >= yearStart }.reduce(0.0) { $0 + $1.subtotal }
            let ytdJobs = jobsStore.jobs.filter { $0.status == .completed && $0.date >= yearStart }.count
            let ytdClients = Set(jobsStore.jobs.filter { $0.date >= yearStart }.map(\.clientId)).count
            return ChatMessage(role: .assistant, text: "Year to date (\(calendar.component(.year, from: Date()))):\n\n• Revenue collected: \(ytdRevenue.formatted(.currency(code: "USD")))\n• Jobs completed: \(ytdJobs)\n• Clients served: \(ytdClients)", style: .info, quickReplies: ["Busiest month?", "Business overview", "Check revenue"])
        }

        // WHO OWES ME MOST
        if lowered.contains("who owes me") || lowered.contains("biggest outstanding") || lowered.contains("largest unpaid") || lowered.contains("most money owed") || (lowered.contains("owes") && lowered.contains("most")) {
            let outstanding = invoicesStore.invoices.filter { $0.status == .unpaid || $0.status == .overdue }.sorted { $0.subtotal > $1.subtotal }
            if outstanding.isEmpty {
                return ChatMessage(role: .assistant, text: "Nobody owes you anything right now — all invoices are paid up!", style: .success, quickReplies: ["Business overview", "Create invoice"])
            }
            let lines = outstanding.prefix(4).map { "\($0.clientName): \($0.subtotal.formatted(.currency(code: "USD")))\($0.status == .overdue ? " (overdue)" : "")" }.joined(separator: "\n")
            let total = outstanding.reduce(0.0) { $0 + $1.subtotal }
            return ChatMessage(role: .assistant, text: "Outstanding balances (\(outstanding.count) invoice\(outstanding.count == 1 ? "" : "s"), \(total.formatted(.currency(code: "USD"))) total):\n\n\(lines)", style: outstanding.contains(where: { $0.status == .overdue }) ? .warning : .info, action: .openFinances, actionLabel: "Open Finances", quickReplies: ["Check overdue", "Business overview"])
        }

        // AVERAGE JOB PRICE
        if lowered.contains("average job") || lowered.contains("average price") || lowered.contains("average charge") || lowered.contains("average rate") || (lowered.contains("average") && (lowered.contains("job") || lowered.contains("earn") || lowered.contains("make") || lowered.contains("clean"))) || lowered.contains("what do i charge on average") {
            let completed = jobsStore.jobs.filter { $0.status == .completed }
            if completed.isEmpty {
                return ChatMessage(role: .assistant, text: "No completed jobs yet to average. Complete some jobs and I'll track your pricing.", quickReplies: ["Schedule a job"])
            }
            let avg = completed.reduce(0.0) { $0 + $1.price } / Double(completed.count)
            let highest = completed.max(by: { $0.price < $1.price })
            var text = "Your average job price is \(avg.formatted(.currency(code: "USD"))) across \(completed.count) completed job\(completed.count == 1 ? "" : "s")."
            if let h = highest, h.price > avg {
                text += " Your highest was \(h.price.formatted(.currency(code: "USD"))) for \(h.serviceType.rawValue)."
            }
            return ChatMessage(role: .assistant, text: text, style: .info, quickReplies: ["Most popular services", "Revenue breakdown", "Business overview"])
        }

        // LAST VISIT / WHEN DID I LAST CLEAN
        let isLastVisitQuery = (lowered.contains("last job") || lowered.contains("last time") || lowered.contains("last clean") || lowered.contains("when did i last") || lowered.contains("last visit")) && !lowered.contains("my last job")
        if isLastVisitQuery {
            let matchedClient = clientsStore.clients.first { client in
                let parts = client.name.lowercased().components(separatedBy: " ")
                return parts.contains { $0.count > 2 && lowered.contains($0) }
            }
            if let client = matchedClient {
                let lastJob = jobsStore.jobs.filter { $0.clientId == client.id && $0.status == .completed }.sorted { $0.date > $1.date }.first
                if let job = lastJob {
                    let daysAgo = Calendar.current.dateComponents([.day], from: job.date, to: Date()).day ?? 0
                    let daysText = daysAgo == 0 ? "today" : daysAgo == 1 ? "yesterday" : "\(daysAgo) days ago"
                    return ChatMessage(role: .assistant, text: "Last job for \(client.name) was \(job.serviceType.rawValue) on \(job.date.formatted(date: .abbreviated, time: .omitted)) — \(daysText).", style: .info, quickReplies: ["Schedule a follow-up for \(client.name.components(separatedBy: " ").first ?? client.name)", "Business overview"])
                } else {
                    return ChatMessage(role: .assistant, text: "No completed jobs found for \(client.name) yet.", quickReplies: ["Schedule a job for \(client.name.components(separatedBy: " ").first ?? client.name)"])
                }
            }
        }

        // MOST POPULAR SERVICES
        if lowered.contains("popular service") || lowered.contains("most booked") || lowered.contains("best selling") || (lowered.contains("what service") && (lowered.contains("most") || lowered.contains("popular") || lowered.contains("common"))) || lowered.contains("service breakdown") {
            var counts: [String: Int] = [:]
            for job in jobsStore.jobs { counts[job.serviceType.rawValue, default: 0] += 1 }
            if counts.isEmpty {
                return ChatMessage(role: .assistant, text: "No jobs on record yet to rank services.", quickReplies: ["Schedule a job"])
            }
            let ranked = counts.sorted { $0.value > $1.value }
            let lines = ranked.prefix(5).map { "\($0.key): \($0.value) job\($0.value == 1 ? "" : "s")" }.joined(separator: "\n")
            return ChatMessage(role: .assistant, text: "Services by booking count:\n\n\(lines)", style: .info, quickReplies: ["Average job price", "Business insights", "Business overview"])
        }

        // NEW CLIENTS THIS MONTH
        if (lowered.contains("new client") || lowered.contains("new customer")) && (lowered.contains("this month") || lowered.contains("month") || lowered.contains("recently") || lowered.contains("lately")) {
            let calendar = Calendar.current
            let monthStart = calendar.startOfMonth(for: Date())
            let recentClients = clientsStore.clients.filter { client in
                guard let firstJob = jobsStore.jobs.filter({ $0.clientId == client.id }).sorted(by: { $0.date < $1.date }).first else { return false }
                return firstJob.date >= monthStart
            }
            return ChatMessage(role: .assistant, text: "\(recentClients.count) new client\(recentClients.count == 1 ? "" : "s") this month\(recentClients.isEmpty ? ". Tip: reach out to past clients to re-book." : recentClients.count == 1 ? ": \(recentClients[0].name)." : ": \(recentClients.prefix(3).map(\.name).joined(separator: ", "))\(recentClients.count > 3 ? " and more." : ".")") ", style: .info, quickReplies: ["Add a client", "Business overview", "Inactive clients"])
        }

        // HELP
        if lowered.contains("help") || lowered.contains("what can you") || lowered.contains("what do you") || lowered.contains("capabilities") || lowered.contains("show me around") {
            return ChatMessage(
                role: .assistant,
                text: "Here's what I can help with:\n\n• Schedule and manage jobs\n• Cancel a job or mark it in progress\n• Rebook the same job for a client\n• Add and look up clients\n• Create and track invoices\n• Revenue: total, monthly, YTD, by client\n• Business pace — am I on track this month?\n• Who owes me most, average job price\n• Busiest month, most popular services\n• Last visit for any client\n• Business overview and insights\n\nJust talk to me naturally.",
                quickReplies: ["Who's my best client?", "Am I on track?", "Most popular services"]
            )
        }

        // GREETINGS
        if lowered.hasPrefix("hi") || lowered.hasPrefix("hello") || lowered.hasPrefix("hey") || lowered == "yo" || lowered.hasPrefix("good morning") || lowered.hasPrefix("good afternoon") || lowered.hasPrefix("good evening") {
            let greetingVariants = [
                "Hey \(firstName)! What can I help you with today?",
                "Hi \(firstName)! I'm here — what do you need?",
                "\(timeGreeting), \(firstName)! Ask me anything about your business.",
                "Hey! What's on your mind, \(firstName)?"
            ]
            return ChatMessage(
                role: .assistant,
                text: greetingVariants.randomElement() ?? greetingVariants[0],
                quickReplies: ["Today's jobs", "Business overview", "Check revenue"]
            )
        }

        // BUSIEST MONTH
        if lowered.contains("busiest month") || (lowered.contains("busiest") && lowered.contains("month")) || lowered.contains("what month") && lowered.contains("most") {
            let calendar = Calendar.current
            var monthCounts: [Int: (label: String, count: Int)] = [:]
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            for job in jobsStore.jobs {
                let month = calendar.component(.month, from: job.date)
                let year = calendar.component(.year, from: job.date)
                let key = year * 100 + month
                let label = formatter.string(from: job.date)
                monthCounts[key] = (label: label, count: (monthCounts[key]?.count ?? 0) + 1)
            }
            if let busiest = monthCounts.max(by: { $0.value.count < $1.value.count }) {
                let runner = monthCounts.sorted { $0.value.count > $1.value.count }.dropFirst().first
                var text = "Your busiest month was \(busiest.value.label) with \(busiest.value.count) job\(busiest.value.count == 1 ? "" : "s")."
                if let runner {
                    text += " Runner-up: \(runner.value.label) (\(runner.value.count) jobs)."
                }
                return ChatMessage(role: .assistant, text: text, style: .info, quickReplies: ["Revenue this month", "Business overview", "Business insights"])
            } else {
                return ChatMessage(role: .assistant, text: "No job history yet — schedule some jobs and I'll track your busiest months.", quickReplies: ["Schedule a job"])
            }
        }

        // SEND INVOICE TO CLIENT
        if lowered.contains("send invoice") || (lowered.contains("invoice") && lowered.contains("for") && !lowered.contains("create") && !lowered.contains("new")) {
            let matchedClient = clientsStore.clients.first { client in
                let parts = client.name.lowercased().components(separatedBy: " ")
                return parts.contains { $0.count > 2 && lowered.contains($0) }
            }
            if let client = matchedClient {
                let invoice = invoicesStore.invoices
                    .filter { $0.clientId == client.id && $0.status != .paid }
                    .sorted { $0.createdAt > $1.createdAt }
                    .first
                if let invoice {
                    return ChatMessage(role: .assistant, text: "Found an open invoice for \(client.name) — \(invoice.invoiceNumber), \(invoice.total.currency) due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted)). Head to Finances to view or share it.", action: .openFinances, actionLabel: "Open Finances", quickReplies: ["Mark as paid", "Business overview"])
                } else {
                    return ChatMessage(role: .assistant, text: "No open invoices for \(client.name). Want to create one?", quickReplies: ["Create invoice", "Business overview"])
                }
            } else {
                return ChatMessage(role: .assistant, text: "Who's the invoice for? Say the client's name and I'll look it up.", quickReplies: ["View all invoices"])
            }
        }

        // CANCEL JOB
        let isCancelIntent = lowered.contains("cancel") && (lowered.contains("job") || lowered.contains("appointment") || lowered.contains("clean") || clientsStore.clients.contains { c in c.name.lowercased().components(separatedBy: " ").contains { $0.count > 2 && lowered.contains($0) } })
        if isCancelIntent {
            let matchedJob: Job? = {
                for client in clientsStore.clients {
                    let parts = client.name.lowercased().components(separatedBy: " ")
                    if parts.contains(where: { $0.count > 2 && lowered.contains($0) }) {
                        return jobsStore.jobs.filter { $0.clientId == client.id && ($0.status == .scheduled || $0.status == .inProgress) }.sorted { $0.date < $1.date }.first
                    }
                }
                return jobsStore.jobs.filter { $0.status == .scheduled }.sorted { $0.date < $1.date }.first
            }()
            if let job = matchedJob {
                Task { await jobsStore.updateStatus(id: job.id, status: .cancelled) }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return ChatMessage(
                    role: .assistant,
                    text: "Done — I've cancelled the \(job.serviceType.rawValue) for \(job.clientName) on \(job.date.formatted(date: .abbreviated, time: .omitted)).",
                    style: .warning,
                    quickReplies: ["Schedule a new job", "Business overview"]
                )
            } else {
                return ChatMessage(
                    role: .assistant,
                    text: "I couldn't find an upcoming job to cancel. Which client's job would you like to cancel?",
                    quickReplies: ["Show upcoming jobs"]
                )
            }
        }

        // START JOB (mark in-progress)
        let isStartJobIntent = (lowered.contains("start") || lowered.contains("begin") || lowered.contains("starting") || (lowered.contains("mark") && lowered.contains("progress"))) && (lowered.contains("job") || lowered.contains("clean") || lowered.contains("appointment") || clientsStore.clients.contains { c in c.name.lowercased().components(separatedBy: " ").contains { $0.count > 2 && lowered.contains($0) } })
        if isStartJobIntent {
            let matchedJob: Job? = {
                for client in clientsStore.clients {
                    let parts = client.name.lowercased().components(separatedBy: " ")
                    if parts.contains(where: { $0.count > 2 && lowered.contains($0) }) {
                        return jobsStore.jobs.filter { $0.clientId == client.id && $0.status == .scheduled }.sorted { $0.date < $1.date }.first
                    }
                }
                let todayJobs = jobsStore.jobs.filter { Calendar.current.isDateInToday($0.date) && $0.status == .scheduled }.sorted { $0.date < $1.date }
                return todayJobs.first ?? jobsStore.jobs.filter { $0.status == .scheduled }.sorted { $0.date < $1.date }.first
            }()
            if let job = matchedJob {
                Task { await jobsStore.updateStatus(id: job.id, status: .inProgress) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return ChatMessage(
                    role: .assistant,
                    text: "Job started! \(job.serviceType.rawValue) for \(job.clientName) is now in progress. I'll be here when you're done.",
                    style: .success,
                    quickReplies: ["Mark complete", "Today's jobs"]
                )
            } else {
                return ChatMessage(
                    role: .assistant,
                    text: "No scheduled jobs found to start. Check your schedule?",
                    quickReplies: ["Today's jobs", "Upcoming schedule"]
                )
            }
        }

        // REBOOK — schedule same thing again
        let isRebookIntent = lowered.contains("rebook") || lowered.contains("book again") || lowered.contains("same again") || lowered.contains("book the same") || ((lowered.contains("schedule") || lowered.contains("book")) && lowered.contains("again"))
        if isRebookIntent {
            let matchedClient: Client? = clientsStore.clients.first { client in
                let parts = client.name.lowercased().components(separatedBy: " ")
                return parts.contains { $0.count > 2 && lowered.contains($0) }
            }
            let targetClient: Client? = matchedClient ?? {
                let lastJob = jobsStore.jobs.filter { $0.status == .completed }.sorted { $0.date > $1.date }.first
                return lastJob.flatMap { job in clientsStore.clients.first { $0.id == job.clientId } }
            }()
            if let client = targetClient {
                let lastJob = jobsStore.jobs.filter { $0.clientId == client.id }.sorted { $0.date > $1.date }.first
                if let last = lastJob {
                    return ChatMessage(
                        role: .assistant,
                        text: "Opening the job form pre-filled for \(client.name) — same service (\(last.serviceType.rawValue), \(last.price.formatted(.currency(code: "USD")))).\n\nJust pick a new date and you're set.",
                        action: .newJob,
                        actionLabel: "Open Job Form",
                        quickReplies: ["Schedule a different job"]
                    )
                } else {
                    return ChatMessage(
                        role: .assistant,
                        text: "I don't have a previous job for \(client.name) to rebook from. Want to schedule a new one?",
                        action: .newJob,
                        actionLabel: "Schedule a Job"
                    )
                }
            } else {
                return ChatMessage(
                    role: .assistant,
                    text: "Which client would you like to rebook? Say their name and I'll pull up their last job details.",
                    quickReplies: ["Show my clients"]
                )
            }
        }

        // DEFAULT — fall through to Groq AI if configured
        if AIService.shared.isConfigured {
            let context = buildBusinessContext()
            if let aiReply = await AIService.shared.chat(userMessage: input, systemPrompt: context) {
                return ChatMessage(role: .assistant, text: aiReply.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return ChatMessage(
            role: .assistant,
            text: "I'm not sure I caught that — try asking about your jobs, clients, invoices, or revenue. You can also say \"schedule a job\" or \"add a client\" to get started.",
            quickReplies: ["Today's jobs", "Business overview", "Help"]
        )
    }

    // MARK: - Business Context for AI

    private func buildBusinessContext() -> String {
        let businessName = profileStore.profile?.businessName ?? "your cleaning business"
        let clientCount = clientsStore.clients.filter { $0.isActive ?? true }.count
        let today = Calendar.current.startOfDay(for: Date())
        let todayJobs = jobsStore.jobs.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
        let overdueInvoices = invoicesStore.invoices.filter { $0.status == .overdue }
        let overdueTotal = overdueInvoices.reduce(0) { $0 + $1.amount }
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekRevenue = invoicesStore.invoices
            .filter { $0.status == .paid && $0.createdAt >= weekStart }
            .reduce(0) { $0 + $1.amount }
        let nextJob = jobsStore.jobs
            .filter { $0.status == .scheduled && $0.date >= Date() }
            .sorted { $0.date < $1.date }
            .first

        var todayJobsText = "none scheduled"
        if !todayJobs.isEmpty {
            todayJobsText = todayJobs.map { "\($0.clientName) (\($0.serviceType.rawValue))" }.joined(separator: ", ")
        }

        var nextJobText = "none upcoming"
        if let job = nextJob {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            nextJobText = "\(job.clientName) on \(formatter.string(from: job.date))"
        }

        return """
        You are Sweeply AI, a smart business assistant for \(businessName), a cleaning business.

        Current business snapshot:
        - Active clients: \(clientCount)
        - Jobs today: \(todayJobsText)
        - Revenue this week: \(weekRevenue.currency)
        - Overdue invoices: \(overdueInvoices.count) totaling \(overdueTotal.currency)
        - Next upcoming job: \(nextJobText)

        You help the owner manage their cleaning business. Be friendly, practical, and concise — 2-3 sentences max unless they ask for detail. Focus on actionable advice. If asked about specific data you don't have access to, say so briefly and suggest they check the relevant screen.
        """
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
                return ChatMessage(role: .assistant, text: "How much are you charging? (e.g. 150 or $180)")
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
            text: "Here's what I've got — does this look right?",
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
                style: .success,
                action: .newClient,
                actionLabel: "Open Client Form",
                quickReplies: ["Add another client", "Schedule a job"]
            )
        } else {
            conversationState = .collectingClient(updatedDraft)
            return ChatMessage(role: .assistant, text: updatedDraft.nextMissingField ?? "Anything else?")
        }
    }

    // MARK: - Direct Action Confirmation

    // Sentinel: when rescheduleJob's stored date == distantPast, we're still awaiting the new date from user
    private let rescheduleSentinel = Date.distantPast

    @MainActor
    private func handleDirectActionConfirmation(input: String, lowered: String, action: DirectAction) async -> ChatMessage {
        let isYes = lowered.contains("yes") || lowered == "yep" || lowered == "yup" || lowered == "ok" || lowered == "okay" || lowered.contains("confirm") || lowered.contains("mark") || lowered.contains("do it") || lowered.contains("reschedule") || lowered.contains("update")
        let isNo = lowered.contains("no") || lowered.contains("cancel") || lowered.contains("nevermind") || lowered.contains("stop")

        // Special handling: awaiting a new date for reschedule (sentinel date)
        if case .rescheduleJob(let job, let storedDate) = action, storedDate == rescheduleSentinel {
            if isNo {
                conversationState = .idle
                return ChatMessage(role: .assistant, text: "No problem — reschedule cancelled.", quickReplies: ["Today's jobs", "Business overview"])
            }
            if let newDate = parseDateFromText(lowered) {
                // Confirm with user before applying
                conversationState = .awaitingDirectAction(.rescheduleJob(job, newDate))
                return ChatMessage(
                    role: .assistant,
                    text: "Reschedule \(job.clientName)'s \(job.serviceType.rawValue) from \(job.date.formatted(date: .abbreviated, time: .shortened)) to \(newDate.formatted(date: .abbreviated, time: .shortened))?",
                    style: .info,
                    quickReplies: ["Yes, reschedule", "Cancel"]
                )
            }
            return ChatMessage(role: .assistant, text: "I couldn't parse that date. Try \"tomorrow\", \"next Monday\", or \"April 20\".", quickReplies: ["Tomorrow", "Next Monday", "Next Friday"])
        }

        conversationState = .idle

        if isNo {
            return ChatMessage(role: .assistant, text: "No problem — action cancelled. What else can I help with?", quickReplies: ["Business overview", "Today's jobs"])
        }

        if isYes {
            switch action {
            case .markJobComplete(let job):
                await jobsStore.updateStatus(id: job.id, status: .completed)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                return ChatMessage(
                    role: .assistant,
                    text: "\(job.serviceType.rawValue) for \(job.clientName) marked as completed.",
                    style: .success,
                    quickReplies: ["Create invoice for \(job.clientName.components(separatedBy: " ").first ?? job.clientName)", "View schedule"]
                )
            case .markInvoicePaid(let invoice):
                await invoicesStore.markPaid(id: invoice.id, userId: nil)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                return ChatMessage(
                    role: .assistant,
                    text: "Invoice \(invoice.invoiceNumber) for \(invoice.clientName) — \(invoice.subtotal.formatted(.currency(code: "USD"))) — marked as paid.",
                    style: .success,
                    quickReplies: ["Check all invoices", "Business overview"]
                )
            case .rescheduleJob(let job, let newDate):
                let updated = Job(id: job.id, clientId: job.clientId, clientName: job.clientName, serviceType: job.serviceType, date: newDate, duration: job.duration, price: job.price, status: job.status, address: job.address, isRecurring: job.isRecurring, recurrenceRuleId: job.recurrenceRuleId)
                _ = await jobsStore.update(updated)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                return ChatMessage(
                    role: .assistant,
                    text: "Done! Rescheduled to \(newDate.formatted(date: .abbreviated, time: .shortened)).",
                    style: .success,
                    quickReplies: ["View schedule", "Today's jobs"]
                )
            }
        }

        return ChatMessage(role: .assistant, text: "Say yes to confirm or no to cancel.", quickReplies: ["Yes", "No"])
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

    // MARK: - Focus Briefing

    private func buildFocusBriefing() -> ChatMessage {
        let calendar = Calendar.current
        var items: [String] = []

        // 1. Overdue invoices
        let overdueInvoices = invoicesStore.invoices.filter { $0.status == .overdue }
        if !overdueInvoices.isEmpty {
            let total = overdueInvoices.reduce(0.0) { $0 + $1.subtotal }
            items.append("⚠️ \(overdueInvoices.count) overdue invoice\(overdueInvoices.count == 1 ? "" : "s") totaling \(total.formatted(.currency(code: "USD"))) — collect these first")
        }

        // 2. Today's scheduled jobs
        let todayScheduled = jobsStore.jobs.filter { calendar.isDateInToday($0.date) && $0.status == .scheduled }.sorted { $0.date < $1.date }
        if !todayScheduled.isEmpty {
            let earliest = todayScheduled[0].date.formatted(date: .omitted, time: .shortened)
            items.append("📋 \(todayScheduled.count) job\(todayScheduled.count == 1 ? "" : "s") scheduled today starting at \(earliest)")
        }

        // 3. In-progress jobs
        let inProgress = jobsStore.jobs.filter { $0.status == .inProgress }
        if !inProgress.isEmpty {
            let names = inProgress.prefix(2).map { $0.clientName }.joined(separator: " and ")
            items.append("🔄 \(names)\(inProgress.count > 2 ? " and more" : "") currently in progress")
        }

        // 4. Invoices due within 3 days
        let threeDaysOut = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        let dueSoon = invoicesStore.invoices.filter { $0.status == .unpaid && $0.dueDate <= threeDaysOut && $0.dueDate >= Date() }
        if !dueSoon.isEmpty {
            items.append("📅 \(dueSoon.count) invoice\(dueSoon.count == 1 ? "" : "s") due within 3 days")
        }

        // 5. Inactive clients (30+ days, more than 2)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentClientIds = Set(jobsStore.jobs.filter { $0.date >= thirtyDaysAgo }.map { $0.clientId })
        let inactiveClients = clientsStore.clients.filter { $0.isActive && !recentClientIds.contains($0.id) }
        if inactiveClients.count > 2 {
            items.append("👥 \(inactiveClients.count) clients haven't booked in 30+ days")
        }

        if items.isEmpty {
            return ChatMessage(
                role: .assistant,
                text: "You're in great shape — no overdue invoices, no urgent items. Keep up the momentum!",
                style: .success,
                quickReplies: ["Today's schedule", "Business overview", "New job"]
            )
        }

        let text = "Here's what matters most right now:\n\n" + items.map { "\($0)" }.joined(separator: "\n")
        return ChatMessage(
            role: .assistant,
            text: text,
            style: .info,
            quickReplies: ["Show overdue invoices", "Today's schedule", "New job"]
        )
    }

    // MARK: - Date Parser

    private func parseDateFromText(_ text: String) -> Date? {
        let lowered = text.lowercased()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Relative days
        if lowered.contains("today") { return combineDateAndTime(base: today, text: lowered) }
        if lowered.contains("day after tomorrow") { return combineDateAndTime(base: calendar.date(byAdding: .day, value: 2, to: today) ?? today, text: lowered) }
        if lowered.contains("tomorrow") { return combineDateAndTime(base: calendar.date(byAdding: .day, value: 1, to: today) ?? today, text: lowered) }
        if lowered.contains("next week") { return combineDateAndTime(base: calendar.date(byAdding: .weekOfYear, value: 1, to: today) ?? today, text: lowered) }
        if lowered.contains("next month") {
            return combineDateAndTime(base: calendar.date(byAdding: .month, value: 1, to: today) ?? today, text: lowered)
        }
        if lowered.contains("end of month") || lowered.contains("end of the month") {
            var comps = calendar.dateComponents([.year, .month], from: today)
            comps.month = (comps.month ?? 1) + 1
            comps.day = 0
            return combineDateAndTime(base: calendar.date(from: comps) ?? today, text: lowered)
        }

        // "in N days/weeks"
        if let inMatch = lowered.range(of: #"in\s+(\d+)\s+(day|days|week|weeks)"#, options: .regularExpression) {
            let matched = String(lowered[inMatch])
            let parts = matched.components(separatedBy: .whitespaces).compactMap { Int($0) }
            let isWeeks = matched.contains("week")
            if let n = parts.first {
                let base = calendar.date(byAdding: isWeeks ? .weekOfYear : .day, value: n, to: today) ?? today
                return combineDateAndTime(base: base, text: lowered)
            }
        }

        // Named weekdays
        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
        for (name, weekday) in weekdays {
            if lowered.contains(name) {
                let currentWeekday = calendar.component(.weekday, from: today)
                var daysAhead = weekday - currentWeekday
                if daysAhead <= 0 { daysAhead += 7 }
                if lowered.contains("next \(name)") && daysAhead < 7 { daysAhead += 7 }
                let base = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
                return combineDateAndTime(base: base, text: lowered)
            }
        }

        let formatter = DateFormatter()
        for format in ["MMMM d", "MMM d", "M/d", "M/d/yyyy"] {
            formatter.dateFormat = format
            formatter.defaultDate = today
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                var components = calendar.dateComponents([.month, .day], from: date)
                components.year = calendar.component(.year, from: Date())
                if let result = calendar.date(from: components), result >= today {
                    return combineDateAndTime(base: result, text: lowered)
                }
                components.year = (components.year ?? 2025) + 1
                return combineDateAndTime(base: calendar.date(from: components) ?? today, text: lowered)
            }
        }
        return nil
    }

    /// Parses a time from text like "at 9am", "at 2:30pm", "at noon", and merges it into the base date.
    private func combineDateAndTime(base: Date, text: String) -> Date {
        let calendar = Calendar.current
        let lowered = text.lowercased()

        if lowered.contains("noon") {
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: base) ?? base
        }
        if lowered.contains("midnight") {
            return calendar.date(bySettingHour: 0, minute: 0, second: 0, of: base) ?? base
        }
        if lowered.contains("morning") && !lowered.contains("at") {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
        }
        if lowered.contains("afternoon") && !lowered.contains("at") {
            return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: base) ?? base
        }
        if lowered.contains("evening") && !lowered.contains("at") {
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: base) ?? base
        }

        // "at H:MMam/pm" or "at Ham/pm"
        let timePattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)) {
            let hourRange = Range(match.range(at: 1), in: lowered)
            let minuteRange = Range(match.range(at: 2), in: lowered)
            let periodRange = Range(match.range(at: 3), in: lowered)
            if let hourRange, var hour = Int(lowered[hourRange]) {
                let minute = minuteRange.flatMap { Int(lowered[$0]) } ?? 0
                let period = periodRange.map { String(lowered[$0]).lowercased() }
                if period == "pm" && hour < 12 { hour += 12 }
                if period == "am" && hour == 12 { hour = 0 }
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            }
        }

        return base
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

    // MARK: - Chat Title

    private func generateChatTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(5)
        let title = words.joined(separator: " ")
        return title.count > 32 ? String(title.prefix(30)) + "…" : title
    }

    // MARK: - Chat Persistence

    private func persistChat() {
        let toSave = messages.suffix(60).map { PersistedMessage(from: $0) }
        let session = PersistedSession(
            id: UUID(),
            projectId: currentProjectId,
            savedAt: Date(),
            messages: toSave,
            title: chatTitle
        )
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
        currentProjectId = session.projectId
        chatTitle = session.title
        hasFiredProactive = true
    }

    // MARK: - Chat History (multi-session)

    private func saveToHistory() {
        guard !messages.isEmpty else { return }
        var sessions = loadSessionHistory()
        let session = PersistedSession(
            id: UUID(),
            projectId: currentProjectId,
            savedAt: Date(),
            messages: Array(messages.suffix(60).map { PersistedMessage(from: $0) }),
            title: chatTitle
        )
        sessions.insert(session, at: 0)
        if sessions.count > 10 { sessions = Array(sessions.prefix(10)) }
        chatSessionsData = (try? JSONEncoder().encode(sessions)) ?? Data()
    }

    private func loadSessionHistory() -> [PersistedSession] {
        (try? JSONDecoder().decode([PersistedSession].self, from: chatSessionsData)) ?? []
    }

    private func loadProjects() -> [ChatProject] {
        (try? JSONDecoder().decode([ChatProject].self, from: projectsData)) ?? []
    }

    private func saveProjects(_ projects: [ChatProject]) {
        projectsData = (try? JSONEncoder().encode(projects)) ?? Data()
    }

    private func restoreSession(_ session: PersistedSession) {
        messages = session.messages.map { $0.toChatMessage() }
        currentProjectId = session.projectId
        chatTitle = session.title
        hasFiredProactive = true
        showHistory = false
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let onAction: (ChatMessage.ActionType) -> Void
    let onQuickReply: (String) -> Void

    @State private var displayedText: String = ""
    @State private var typewriterTask: Task<Void, Never>? = nil
    @AppStorage("aiMessageRatings") private var ratingsData: Data = Data()

    private func saveRating(messageId: UUID, helpful: Bool) {
        var ratings: [String: Bool] = (try? JSONDecoder().decode([String: Bool].self, from: ratingsData)) ?? [:]
        ratings[messageId.uuidString] = helpful
        ratingsData = (try? JSONEncoder().encode(ratings)) ?? Data()
    }

    private func rating(for messageId: UUID) -> Bool? {
        let ratings: [String: Bool] = (try? JSONDecoder().decode([String: Bool].self, from: ratingsData)) ?? [:]
        return ratings[messageId.uuidString]
    }

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
                        HStack(spacing: 8) {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.sweeplyNavy)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 280)
                        .background(Color.sweeplyAccent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.sweeplyAccent.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 4) {
                    Text(message.timestamp.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    if message.role == .assistant, let rated = rating(for: message.id) {
                        Image(systemName: rated ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(rated ? Color.sweeplyAccent : Color.sweeplyTextSub.opacity(0.4))
                    }
                }
            }

            if message.role == .user {
                userAvatar
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            } else {
                Spacer(minLength: 60)
            }
        }
        .onAppear { startTypewriter() }
        .onDisappear { typewriterTask?.cancel() }
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
            if message.role == .assistant {
                Divider()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    saveRating(messageId: message.id, helpful: true)
                } label: {
                    Label("Helpful", systemImage: "hand.thumbsup")
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    saveRating(messageId: message.id, helpful: false)
                } label: {
                    Label("Not Helpful", systemImage: "hand.thumbsdown")
                }
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
                .font(.system(size: 15))
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
        typewriterTask?.cancel()
        typewriterTask = Task { @MainActor in
            let chars = Array(message.text)
            var index = 0
            let batchSize = 3
            while index < chars.count {
                guard !Task.isCancelled else {
                    displayedText = message.text
                    return
                }
                let endIndex = min(index + batchSize, chars.count)
                displayedText.append(contentsOf: chars[index..<endIndex])
                index = endIndex
                try? await Task.sleep(nanoseconds: 25_000_000) // 0.025s
            }
        }
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

// MARK: - Chat History Sheet

private struct ChatHistorySheet: View {
    let sessions: [PersistedSession]
    let currentSessionId: UUID?
    let projects: [ChatProject]
    let onRestore: (PersistedSession) -> Void
    let onDelete: (PersistedSession) -> Void

    @State private var selectedFilter: String = "All"

    private var filteredSessions: [PersistedSession] {
        switch selectedFilter {
        case "General":
            return sessions.filter { $0.projectId == nil }
        default:
            if let project = projects.first(where: { $0.name == selectedFilter }) {
                return sessions.filter { $0.projectId == project.id }
            }
            return sessions
        }
    }

    private var filterOptions: [String] {
        var options = ["All", "General"]
        options.append(contentsOf: projects.map { $0.name })
        return options
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            return "Today · \(f.string(from: date))"
        } else if cal.isDateInYesterday(date) {
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            return "Yesterday · \(f.string(from: date))"
        }
        return dateFormatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterOptions, id: \.self) { option in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedFilter = option
                            } label: {
                                Text(option)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(selectedFilter == option ? .white : Color.sweeplyNavy)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedFilter == option ? Color.sweeplyAccent : Color.sweeplyNavy.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.sweeplySurface)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.sweeplyBorder), alignment: .bottom)

                if filteredSessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.sweeplyTextSub.opacity(0.3))
                        Text("No chats here yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sweeplyNavy)
                        Text(selectedFilter == "All"
                             ? "Your conversations will appear here as you chat."
                             : "No chats in \(selectedFilter) yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sweeplyTextSub)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.sweeplyBackground)
                } else {
                    List {
                        ForEach(Array(filteredSessions.enumerated()), id: \.offset) { _, session in
                            let isCurrent = session.id == currentSessionId
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onRestore(session)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Badge + date row
                                    HStack(spacing: 6) {
                                        if isCurrent {
                                            HStack(spacing: 4) {
                                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                                Text("Active").font(.system(size: 10, weight: .bold))
                                            }
                                            .foregroundStyle(Color.green)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.1))
                                            .clipShape(Capsule())
                                        } else if let projectId = session.projectId,
                                           let project = projects.first(where: { $0.id == projectId }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "folder.fill").font(.system(size: 9))
                                                Text(project.name).font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundStyle(Color.sweeplyAccent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.sweeplyAccent.opacity(0.1))
                                            .clipShape(Capsule())
                                        } else {
                                            HStack(spacing: 4) {
                                                Image(systemName: "tray.fill").font(.system(size: 9))
                                                Text("General").font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundStyle(Color.sweeplyTextSub)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.sweeplyNavy.opacity(0.06))
                                            .clipShape(Capsule())
                                        }
                                        Spacer()
                                        Text(relativeDate(session.savedAt))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                    }

                                    // Title or first-message fallback
                                    if !session.title.isEmpty {
                                        Text(session.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.sweeplyNavy)
                                            .lineLimit(1)
                                    } else if let firstUser = session.messages.first(where: { $0.role == .user }) {
                                        Text(firstUser.text)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.sweeplyNavy)
                                            .lineLimit(1)
                                    } else {
                                        Text("New conversation")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                    }

                                    // Last AI snippet + count + CTA
                                    HStack(alignment: .bottom) {
                                        if let lastReply = session.messages.last(where: { $0.role == .assistant }) {
                                            Text(lastReply.text)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.sweeplyTextSub)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        let userCount = session.messages.filter { $0.role == .user }.count
                                        HStack(spacing: 4) {
                                            Text("\(userCount) \(userCount == 1 ? "msg" : "msgs")")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                                            Text(isCurrent ? "Continue →" : "Open →")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(Color.sweeplyAccent)
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: !isCurrent) {
                                if !isCurrent {
                                    Button(role: .destructive) {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        onDelete(session)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.sweeplyBackground)
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Calendar Helpers

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }

    func startOfYear(for date: Date) -> Date {
        let components = dateComponents([.year], from: date)
        return self.date(from: components) ?? date
    }
}
