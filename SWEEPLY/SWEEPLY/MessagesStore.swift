import Foundation
import Supabase
import Observation

// MARK: - Domain Models

enum MessageDirection: String, Codable {
    case outgoing, incoming
}

struct Conversation: Identifiable {
    let id: UUID
    let clientId: UUID
    let clientName: String
    let clientPhone: String
    var lastMessage: String?
    var lastMessageAt: Date
    let createdAt: Date
}

struct Message: Identifiable {
    let id: UUID
    let conversationId: UUID
    let body: String
    let direction: MessageDirection
    let sentAt: Date
}

// MARK: - Store

@Observable
final class MessagesStore {
    var conversations: [Conversation] = []
    var messagesByConversation: [UUID: [Message]] = [:]
    var lastError: String? = nil

    func loadConversations(userId: UUID) async {
        guard let client = SupabaseManager.shared else { return }
        do {
            let rows: [ConversationRow] = try await client.database
                .from("conversations")
                .select()
                .eq("user_id", value: userId)
                .order("last_message_at", ascending: false)
                .execute()
                .value
            self.conversations = rows.map { $0.toConversation() }
            self.lastError = nil
        } catch {
            self.lastError = "Failed to load conversations."
        }
    }

    func loadMessages(conversationId: UUID) async -> [Message] {
        guard let client = SupabaseManager.shared else { return [] }
        do {
            let rows: [MessageRow] = try await client.database
                .from("messages")
                .select()
                .eq("conversation_id", value: conversationId)
                .order("sent_at", ascending: true)
                .execute()
                .value
            let messages = rows.map { $0.toMessage() }
            messagesByConversation[conversationId] = messages
            return messages
        } catch {
            return messagesByConversation[conversationId] ?? []
        }
    }

    @discardableResult
    func getOrCreateConversation(clientId: UUID, clientName: String, clientPhone: String, userId: UUID) async -> Conversation? {
        // Check local cache first
        if let existing = conversations.first(where: { $0.clientId == clientId }) {
            return existing
        }
        guard let client = SupabaseManager.shared else { return nil }
        do {
            let insert = ConversationInsert(userId: userId, clientId: clientId, clientName: clientName, clientPhone: clientPhone)
            let row: ConversationRow = try await client.database
                .from("conversations")
                .upsert(insert, onConflict: "user_id,client_id")
                .select()
                .single()
                .execute()
                .value
            let conv = row.toConversation()
            if !conversations.contains(where: { $0.id == conv.id }) {
                conversations.insert(conv, at: 0)
            }
            return conv
        } catch {
            self.lastError = "Failed to open conversation."
            return nil
        }
    }

    @discardableResult
    func sendMessage(body: String, conversationId: UUID, userId: UUID, direction: MessageDirection) async -> Message? {
        let optimistic = Message(id: UUID(), conversationId: conversationId, body: body, direction: direction, sentAt: Date())
        messagesByConversation[conversationId, default: []].append(optimistic)
        updateLastMessage(conversationId: conversationId, body: body)

        guard let client = SupabaseManager.shared else { return optimistic }
        do {
            let insert = MessageInsert(conversationId: conversationId, userId: userId, body: body, direction: direction.rawValue)
            let row: MessageRow = try await client.database
                .from("messages")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value
            let saved = row.toMessage()
            // Replace optimistic with saved
            if var msgs = messagesByConversation[conversationId],
               let idx = msgs.firstIndex(where: { $0.id == optimistic.id }) {
                msgs[idx] = saved
                messagesByConversation[conversationId] = msgs
            }
            return saved
        } catch {
            return optimistic
        }
    }

    func deleteConversation(id: UUID) async {
        conversations.removeAll { $0.id == id }
        messagesByConversation.removeValue(forKey: id)
        guard let client = SupabaseManager.shared else { return }
        try? await client.database.from("conversations").delete().eq("id", value: id).execute()
    }

    private func updateLastMessage(conversationId: UUID, body: String) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].lastMessage = body
            conversations[idx].lastMessageAt = Date()
            let updated = conversations.remove(at: idx)
            conversations.insert(updated, at: 0)
        }
    }
}

// MARK: - DTOs

private struct ConversationRow: Decodable {
    let id: UUID
    let userId: UUID
    let clientId: UUID
    let clientName: String
    let clientPhone: String
    let lastMessage: String?
    let lastMessageAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId         = "user_id"
        case clientId       = "client_id"
        case clientName     = "client_name"
        case clientPhone    = "client_phone"
        case lastMessage    = "last_message"
        case lastMessageAt  = "last_message_at"
        case createdAt      = "created_at"
    }

    func toConversation() -> Conversation {
        Conversation(id: id, clientId: clientId, clientName: clientName, clientPhone: clientPhone,
                     lastMessage: lastMessage, lastMessageAt: lastMessageAt, createdAt: createdAt)
    }
}

private struct ConversationInsert: Encodable {
    let userId: UUID
    let clientId: UUID
    let clientName: String
    let clientPhone: String

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case clientId    = "client_id"
        case clientName  = "client_name"
        case clientPhone = "client_phone"
    }
}

private struct MessageRow: Decodable {
    let id: UUID
    let conversationId: UUID
    let userId: UUID
    let body: String
    let direction: String
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, direction
        case conversationId = "conversation_id"
        case userId         = "user_id"
        case sentAt         = "sent_at"
    }

    func toMessage() -> Message {
        Message(id: id, conversationId: conversationId, body: body,
                direction: MessageDirection(rawValue: direction) ?? .outgoing, sentAt: sentAt)
    }
}

private struct MessageInsert: Encodable {
    let conversationId: UUID
    let userId: UUID
    let body: String
    let direction: String

    enum CodingKeys: String, CodingKey {
        case body, direction
        case conversationId = "conversation_id"
        case userId         = "user_id"
    }
}
