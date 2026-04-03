import SwiftUI

struct BusinessView: View {
    @Environment(AppSession.self)    private var session
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore
    @Environment(ProfileStore.self)  private var profileStore

    @AppStorage("businessRemindersEnabled") private var remindersOn = true
    @AppStorage("businessJobConfirmations") private var jobConfirmationsOn = true
    @AppStorage("businessMarketingEmails")  private var marketingEmailsOn = false

    @State private var appeared = false
    @State private var showSignOutConfirm = false
    @State private var showSettings = false

    private var profile: UserProfile {
        profileStore.profile ?? MockData.profile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.businessName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(1.4)
                    Text("Operational Overview")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                .padding(.top, 16)

                // 1. Performance KPIs
                HStack(spacing: 12) {
                    KPIBlock(title: "Total Clients", value: "\(clientsStore.clients.count)", icon: "person.2.fill")
                    KPIBlock(title: "Jobs (Mtd)", value: "48", icon: "briefcase.fill")
                    KPIBlock(title: "Revenue", value: "$12.4k", icon: "dollarsign.circle.fill")
                }

                // 2. Service Distribution
                SectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        CardHeader(title: "Service Distribution", subtitle: "Most popular offerings", action: nil)
                        
                        VStack(spacing: 14) {
                            ServiceMixRow(label: "Standard Clean", percentage: 0.65, count: 31)
                            ServiceMixRow(label: "Deep Clean", percentage: 0.25, count: 12)
                            ServiceMixRow(label: "Office/Commercial", percentage: 0.10, count: 5)
                        }
                    }
                }

                // 3. Top Clients
                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Top Clients", subtitle: "Based on monthly job volume", action: nil)
                        Divider()
                        ForEach(clientsStore.clients.prefix(3)) { client in
                            HStack {
                                Text(client.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("4 Visits/Mo").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // 4. Quick Actions (Condensed)
                VStack(alignment: .leading, spacing: 12) {
                    Text("PREFERENCES & SUPPORT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(1.2)
                    
                    SectionCard {
                        VStack(spacing: 0) {
                            NavigationRow(title: "Settings", icon: "gearshape.fill") { showSettings = true }
                            Divider().padding(.leading, 36)
                            NavigationRow(title: "Help & Support", icon: "questionmark.circle.fill") { /* Help */ }
                        }
                        .padding(-16) // full bleed
                    }
                }

                // Sign Out
                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .confirmationDialog("Sign out of Sweeply?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Subviews

private struct KPIBlock: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ServiceMixRow: View {
    let label: String
    let percentage: Double
    let count: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(count) jobs").font(.system(size: 11)).foregroundStyle(Color.sweeplyTextSub)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.sweeplyBorder.opacity(0.5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.sweeplyNavy.opacity(0.8))
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct NavigationRow: View {
    let title: String
    let icon: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(Color.sweeplyNavy.opacity(0.7))
                Text(title).font(.system(size: 15))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sweeplyBorder)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BusinessView()
        .environment(AppSession())
        .environment(ProfileStore())
}
