import SwiftUI

struct BusinessView: View {
    @Environment(AppSession.self)    private var session
    @Environment(ClientsStore.self)  private var clientsStore
    @Environment(JobsStore.self)     private var jobsStore
    @Environment(InvoicesStore.self) private var invoicesStore

    private var profile: UserProfile { MockData.profile }

    @State private var appeared = false
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header (Professional and Bold)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.businessName.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .tracking(1.4)
                    Text("Business Overview")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                }
                .padding(.top, 24)

                // 1. Performance Overview
                HStack(spacing: 12) {
                    KPIBlock(title: "Total Clients", value: "\(clientsStore.clients.count)", icon: "person.2.fill")
                    KPIBlock(title: "Jobs (Mtd)", value: "48", icon: "briefcase.fill")
                    KPIBlock(title: "Revenue", value: "$12.4k", icon: "dollarsign.circle.fill")
                }

                // 2. Service Distribution (Internal Growth)
                SectionCard {
                    VStack(alignment: .leading, spacing: 18) {
                        CardHeader(title: "Service Mix", subtitle: "Breakdown of active contracts", action: nil)
                        
                        VStack(spacing: 16) {
                            ServiceMixRow(label: "Standard Clean", percentage: 0.65, count: 31)
                            ServiceMixRow(label: "Deep Clean", percentage: 0.25, count: 12)
                            ServiceMixRow(label: "Office/Commercial", percentage: 0.10, count: 5)
                        }
                    }
                }

                // 3. Top Clients (Visualizing Value)
                SectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: "Top Clients", subtitle: "Based on monthly job volume", action: nil)
                        Divider()
                        ForEach(MockData.clients.prefix(3)) { client in
                            HStack {
                                Text(client.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("4 Visits/Mo").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // 4. Managed Profile Card
                SectionCard {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.sweeplyNavy)
                                .frame(width: 50, height: 50)
                            Text(businessInitials)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.fullName)
                                .font(.system(size: 16, weight: .semibold))
                            Text(profile.email)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sweeplyTextSub)
                        }
                        Spacer()
                        Button { showSettings = true } label: {
                            Text("Edit")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.sweeplyAccent)
                        }
                    }
                }
                .padding(.bottom, 60) // Extra padding for FAB
            }
            .padding(.horizontal, 20)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var businessInitials: String {
        let parts = profile.businessName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
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
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(count) jobs").font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.sweeplyBorder.opacity(0.3))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.sweeplyNavy)
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 8)
        }
    }
}

#Preview {
    BusinessView()
        .environment(AppSession())
}
