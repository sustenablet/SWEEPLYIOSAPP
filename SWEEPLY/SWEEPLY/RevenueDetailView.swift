import SwiftUI
import Charts

struct RevenueDetailView: View {
    @Environment(ProfileStore.self) private var profileStore
    @State private var selectedRange: RangeFilter = .all

    let revenueByService: [(service: String, revenue: Double, jobCount: Int)]
    let completedJobs: [Job]
    let customJobs: [Job]
    let serviceColorAt: (Int) -> Color

    private enum RangeFilter: String, CaseIterable {
        case month = "Month"
        case sixMonths = "6 Months"
        case all = "All"
    }

    private var profile: UserProfile { profileStore.profile ?? MockData.profile }
    private var serviceCatalog: [BusinessService] { profile.settings.hydratedServiceCatalog }
    private var primaryServiceCatalog: [BusinessService] {
        serviceCatalog.filter { !$0.isAddon && ServiceType(rawValue: $0.name) != nil }
    }
    private var extraServiceCatalog: [BusinessService] {
        serviceCatalog.filter { $0.isAddon || ServiceType(rawValue: $0.name) == nil }
    }
    private var filteredCompletedJobs: [Job] {
        let calendar = Calendar.current
        let now = Date()

        switch selectedRange {
        case .all:
            return completedJobs
        case .month:
            guard let start = calendar.date(byAdding: .month, value: -1, to: now) else { return completedJobs }
            return completedJobs.filter { $0.date >= start && $0.date <= now }
        case .sixMonths:
            guard let start = calendar.date(byAdding: .month, value: -6, to: now) else { return completedJobs }
            return completedJobs.filter { $0.date >= start && $0.date <= now }
        }
    }
    private var filteredCustomJobs: [Job] {
        filteredCompletedJobs.filter {
            if case .custom = $0.serviceType { return true }
            return false
        }
    }
    private var filteredRevenueByService: [(service: String, revenue: Double, jobCount: Int)] {
        var grouped: [String: (Double, Int)] = [:]
        for job in filteredCompletedJobs {
            let key = job.serviceType.rawValue
            let current = grouped[key] ?? (0, 0)
            grouped[key] = (current.0 + job.price, current.1 + 1)
        }
        return grouped.map { (service: $0.key, revenue: $0.value.0, jobCount: $0.value.1) }
            .sorted { $0.revenue > $1.revenue }
    }
    private var revenueLookup: [String: (revenue: Double, jobCount: Int)] {
        Dictionary(uniqueKeysWithValues: filteredRevenueByService.map {
            (normalizedServiceName($0.service), (revenue: $0.revenue, jobCount: $0.jobCount))
        })
    }
    private var breakdownEntries: [(service: BusinessService, revenue: Double, jobCount: Int)] {
        serviceCatalog.map { service in
            let metrics = revenueLookup[normalizedServiceName(service.name)]
            return (service: service, revenue: metrics?.revenue ?? 0, jobCount: metrics?.jobCount ?? 0)
        }
    }
    private var avgTicketEntries: [(service: BusinessService, avg: Double)] {
        primaryServiceCatalog.map { service in
            let metrics = revenueLookup[normalizedServiceName(service.name)]
            let revenue = metrics?.revenue ?? 0
            let jobCount = metrics?.jobCount ?? 0
            let avg = jobCount > 0 ? revenue / Double(jobCount) : service.price
            return (service: service, avg: avg)
        }
        .sorted { $0.avg > $1.avg }
    }

    private var totalRevenue: Double { filteredRevenueByService.reduce(0) { $0 + $1.revenue } }
    private var totalJobs: Int      { filteredRevenueByService.reduce(0) { $0 + $1.jobCount } }
    private var avgTicket: Double   { totalJobs > 0 ? totalRevenue / Double(totalJobs) : 0 }

    private var maxRevenue: Double {
        max(breakdownEntries.map { max($0.revenue, $0.service.price) }.max() ?? 0, 1)
    }

    private func normalizedServiceName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryStrip
                revenueBreakdownSection
                serviceMixSection
                if !extraServiceCatalog.isEmpty { addOnsSection }
                avgTicketSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 80)
        }
        .background(Color.sweeplyBackground.ignoresSafeArea())
        .navigationTitle("Revenue by Service".translated())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(RangeFilter.allCases, id: \.self) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            if selectedRange == range {
                                Label(range.rawValue.translated(), systemImage: "checkmark")
                            } else {
                                Text(range.rawValue.translated())
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedRange.rawValue.translated())
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.sweeplyAccent)
                }
            }
        }
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(label: "Total Revenue".translated(), value: totalRevenue.currency, color: .sweeplyAccent)
            Divider().frame(height: 44).padding(.horizontal, 16)
            summaryCell(label: "Jobs Completed".translated(), value: "\(totalJobs)", color: .sweeplyNavy)
            Divider().frame(height: 44).padding(.horizontal, 16)
            summaryCell(label: "Avg Ticket".translated(), value: avgTicket.currency, color: .sweeplySuccess)
        }
        .padding(.vertical, 20)
    }

    private func summaryCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.translated())
                .font(.system(size: 11))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Revenue breakdown

    private var revenueBreakdownSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(label: "REVENUE BREAKDOWN".translated(), title: "By service type".translated())

                VStack(spacing: 14) {
                    ForEach(Array(breakdownEntries.enumerated()), id: \.element.service.id) { idx, item in
                        let displayValue = item.revenue > 0 ? item.revenue : item.service.price
                        VStack(spacing: 5) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.service.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.sweeplyNavy)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text("\(item.jobCount) \(item.jobCount == 1 ? "job".translated() : "jobs".translated())")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                        let avg = item.jobCount > 0 ? item.revenue / Double(item.jobCount) : item.service.price
                                        Text("avg %@".translated(with: avg.currency))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.sweeplyTextSub)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(displayValue.currency)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyNavy)
                                    let pct = totalRevenue > 0 ? Int(item.revenue / totalRevenue * 100) : 0
                                    Text("\(pct)%")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(serviceColorAt(idx))
                                }
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.sweeplyBorder.opacity(0.5)).frame(height: 6)
                                    Capsule().fill(serviceColorAt(idx))
                                        .frame(width: geo.size.width * CGFloat(item.revenue / maxRevenue), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Service mix pie

    @ViewBuilder
    private var serviceMixSection: some View {
        if #available(iOS 17.0, *) {
            let chartEntries = Array(filteredRevenueByService.enumerated())
            let listEntries = Array(primaryServiceCatalog.enumerated())
            SectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(label: "SERVICE MIX".translated(), title: "Jobs by type".translated())

                    HStack(alignment: .center, spacing: 20) {
                        Chart(chartEntries, id: \.element.service) { idx, item in
                            SectorMark(
                                angle: .value("Jobs", item.jobCount),
                                innerRadius: .ratio(0.52),
                                angularInset: 1.8
                            )
                            .foregroundStyle(serviceColorAt(idx))
                            .cornerRadius(4)
                        }
                        .frame(width: 140, height: 140)
                        .overlay(
                            VStack(spacing: 1) {
                                Text("\(totalJobs)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.sweeplyNavy)
                                Text("jobs".translated())
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.sweeplyTextSub)
                            }
                        )

                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(listEntries, id: \.element.id) { idx, service in
                                let metrics = revenueLookup[normalizedServiceName(service.name)]
                                let pct = totalJobs > 0 ? Int(Double(metrics?.jobCount ?? 0) / Double(totalJobs) * 100) : 0
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(serviceColorAt(idx))
                                        .frame(width: 10, height: 10)
                                    Text(service.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.sweeplyNavy)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(pct)%")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.sweeplyTextSub)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Add-ons

    private var addOnsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(label: "EXTRAS & ADD-ONS".translated(),
                              title: filteredCustomJobs.isEmpty ? "Catalog services".translated() : "Custom services".translated(),
                              badge: "\(extraServiceCatalog.count)")

                let addOnTotal = filteredCustomJobs.reduce(0) { $0 + $1.price }
                let addOnAvg = filteredCustomJobs.isEmpty
                    ? (extraServiceCatalog.isEmpty ? 0 : extraServiceCatalog.reduce(0) { $0 + $1.price } / Double(extraServiceCatalog.count))
                    : addOnTotal / Double(filteredCustomJobs.count)

                HStack(spacing: 0) {
                    addonStat(label: filteredCustomJobs.isEmpty ? "Add-Ons".translated() : "Total".translated(),
                              value: filteredCustomJobs.isEmpty ? "\(extraServiceCatalog.count)" : addOnTotal.currency,
                              color: .sweeplyAccent)
                    Divider().frame(height: 38).padding(.horizontal, 14)
                    addonStat(label: filteredCustomJobs.isEmpty ? "Avg Price".translated() : "Avg Ticket".translated(),
                              value: addOnAvg.currency,
                              color: .sweeplyNavy)
                    Divider().frame(height: 38).padding(.horizontal, 14)
                    addonStat(label: "Jobs".translated(),
                              value: "\(filteredCustomJobs.count)",
                              color: .sweeplyWarning)
                }
                .padding(12)
                .background(Color.sweeplyAccent.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sweeplyAccent.opacity(0.15), lineWidth: 1))

                VStack(spacing: 0) {
                    if filteredCustomJobs.isEmpty {
                        ForEach(Array(extraServiceCatalog.sorted { $0.price > $1.price }.enumerated()), id: \.element.id) { idx, service in
                            AddOnCatalogRow(service: service)
                            if idx < extraServiceCatalog.count - 1 {
                                Divider().padding(.leading, 12)
                            }
                        }
                    } else {
                        ForEach(Array(filteredCustomJobs.sorted { $0.price > $1.price }.enumerated()), id: \.element.id) { idx, job in
                            AddOnJobRow(job: job)
                            if idx < filteredCustomJobs.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
        }
    }

    private func addonStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.sweeplyTextSub)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Avg ticket per service

    private var avgTicketSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(label: "AVG TICKET".translated(), title: "Per service type".translated())

                VStack(spacing: 0) {
                    ForEach(Array(avgTicketEntries.enumerated()), id: \.element.service.id) { idx, item in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.sweeplyTextSub)
                                .frame(width: 18, alignment: .center)
                            Text(item.service.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.sweeplyNavy)
                                .lineLimit(1)
                            Spacer()
                            Text(item.avg.currency)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(serviceColorAt(idx))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        if idx < avgTicketEntries.count - 1 {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
                .background(Color.sweeplySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sweeplyBorder, lineWidth: 1))
            }
        }
    }

    // MARK: - Shared helpers

    private func sectionHeader(label: String, title: String, badge: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(0.8)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
            }
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.sweeplyAccent)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Add-on row

private struct AddOnJobRow: View {
    let job: Job

    private var dateStr: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: job.date)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.sweeplyAccent.opacity(0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(job.serviceType.rawValue.translated())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                    .lineLimit(1)
                Text(job.clientName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(job.price.currency)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.sweeplyNavy)
                Text(dateStr)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.sweeplyTextSub)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct AddOnCatalogRow: View {
    let service: BusinessService

    var body: some View {
        HStack(spacing: 10) {
            Text(service.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sweeplyNavy)
                .lineLimit(1)
            Spacer()
            Text(service.price.currency)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.sweeplyNavy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}
