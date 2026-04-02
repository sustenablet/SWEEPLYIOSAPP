# Sweeply iOS — Cursor Implementation Context

## Project Overview
Native SwiftUI iOS app for solo cleaning business owners. This is a 1-to-1 feature port of the web app at github.com/sustenablet/qikclean, rebuilt as a premium native iOS experience. UI-only for now — all data comes from MockData.swift. Supabase integration comes later.

---

## Tech Stack
- SwiftUI (iOS 17+)
- Swift Charts (native, no third-party chart libs)
- No third-party dependencies whatsoever
- MVVM pattern, ObservableObject view models
- Mock data layer in MockData.swift — structs match future Supabase schema exactly

---

## Existing Files (already created — do not recreate)

### `SWEEPLY/DesignSystem.swift`
Color tokens, spacing constants, radius constants already defined:
```swift
Color.sweeplyAccent      // amber #F9A110
Color.sweeplyNavy        // deep navy (tab bar bg)
Color.sweeplyBackground  // cool off-white page bg
Color.sweeplySuccess     // green
Color.sweeplyWarning     // amber (same as accent)
Color.sweeplyDestructive // red
Color.sweeplyTextSub     // muted gray text
Color.sweeplySurface     // white (card bg)
Color.sweeplyBorder      // light border

Spacing.xs / sm / md / base / lg / xl / xxl / xxxl
Radius.sm / md / lg / xl / full
```

### `SWEEPLY/Models.swift`
All model structs defined:
- `UserProfile` — id, fullName, businessName, email, phone
- `Client` — id, name, email, phone, address, city, state, notes
- `Job` — id, clientId, clientName, serviceType, date, duration, price, status, address, isRecurring
- `Invoice` — id, clientId, clientName, amount, status, createdAt, dueDate, invoiceNumber
- `WeeklyRevenue` — day (String), amount (Double)
- Enums: `JobStatus` (.scheduled, .inProgress, .completed, .cancelled), `InvoiceStatus` (.paid, .unpaid, .overdue), `ServiceType`

### `SWEEPLY/MockData.swift`
Static mock data: 5 clients, 6 jobs (including today's jobs), 5 invoices, weeklyRevenue array.
Access via: `MockData.profile`, `MockData.clients`, `MockData.makeJobs()`, `MockData.makeInvoices()`, `MockData.weeklyRevenue`

### `SWEEPLY/RootView.swift`
TabView shell with 5 tabs: Dashboard, Schedule, Clients, Invoices, Finances.
Tab bar styled dark navy bg + amber active tint.
**FAB needs to be added here as a ZStack overlay above the TabView.**

### `SWEEPLY/DashboardView.swift`
Exists but needs full rewrite per this spec. Replace it entirely.

### `SWEEPLY/SWEEPLYApp.swift`
Clean entry point — just `RootView()` in a `WindowGroup`. No SwiftData.

---

## Custom Font: Bricolage Grotesque
Download from Google Fonts and add to Xcode project:
- `BricolageGrotesque-Bold.ttf`
- `BricolageGrotesque-SemiBold.ttf`

Register in `Info.plist`:
```xml
<key>UIAppFonts</key>
<array>
  <string>BricolageGrotesque-Bold.ttf</string>
  <string>BricolageGrotesque-SemiBold.ttf</string>
</array>
```

Use in code:
```swift
Font.custom("BricolageGrotesque-Bold", size: 22)
```

If font isn't bundled yet, fall back to:
```swift
.font(.system(size: 22, weight: .bold, design: .default))
```

---

## Dashboard Page — Full Spec

File to rewrite: `SWEEPLY/DashboardView.swift`

The dashboard is a single `ScrollView` with a `VStack(spacing: 20)` inside. Page padding is `20pt` horizontal. Sections are spaced `20pt` apart.

---

### Section 1: Header

```
[Good morning, João]          [🔔] [JL]
[Tuesday, April 1]
```

- Left stack:
  - "Good morning, [firstName]" — `Font.custom("BricolageGrotesque-Bold", size: 22)`, foreground primary
  - Today's date — `DateFormatter` with format `"EEEE, MMMM d"`, 13pt, `Color.sweeplyTextSub`

- Right stack (HStack):
  - Bell icon: `Image(systemName: "bell")`, 20pt, foreground primary
    - Has a badge dot if there are notifications (mock: always show 1 unread)
  - Avatar circle: 38pt diameter, `Color.sweeplyNavy` fill, white text initials (first+last initial), 1pt white border
  - Tapping avatar opens an `.actionSheet` or `confirmationDialog` or a custom sheet with:
    - User's full name (bold)
    - Business name (muted)
    - "Settings" option
    - "Sign Out" option (destructive red)

---

### Section 2: Mobile Quick Stats Row

Horizontally scrollable row. Bleeds past page edges.

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 12) {
        QuickStatCard(...)
        QuickStatCard(...)
        QuickStatCard(...)
        QuickStatCard(...)
    }
    .padding(.horizontal, 20)
}
.padding(.horizontal, -20) // bleed trick
```

Each `QuickStatCard`:
- Width: 140pt fixed
- Height: ~90pt
- Background: `Color.sweeplySurface`
- Border: `.overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sweeplyBorder, lineWidth: 1))`
- Corner radius: 12pt
- Padding: 14pt
- Content (top to bottom):
  - SF Symbol icon, 18pt
  - Large bold number, 24pt, monospaced
  - Tiny uppercase label, 10pt, `Color.sweeplyTextSub`, tracking 0.5

The 4 cards:
| Label | Icon | Value Source | Color |
|---|---|---|---|
| Total Clients | `person.2.fill` | `MockData.clients.count` | primary |
| Upcoming Jobs | `calendar` | jobs where status == .scheduled | primary |
| Revenue | `dollarsign.circle.fill` | sum of paid invoices | `Color.sweeplySuccess` |
| Outstanding | `exclamationmark.triangle.fill` | sum of unpaid+overdue | `Color.sweeplyWarning` |

---

### Section 3: Getting Started Checklist (Conditional)

Component: `DashboardPlaybook`

Show when `@State var showPlaybook: Bool = true` (mock — pretend user is new).
Hide entire view when all steps are checked OR when user dismisses it.

Card with border. Header: "Get started" (15pt semibold) + X dismiss button (top right).

4 checklist steps:
1. "Add your first client" — `person.badge.plus`
2. "Schedule your first job" — `calendar.badge.plus`
3. "Create your first invoice" — `doc.badge.plus`
4. "Set up your business profile" — `building.2`

Each step row:
- Left: checkmark circle (filled green if done, empty gray outline if not)
- Center: step title (14pt, strikethrough if done, muted if done)
- Tapping a step navigates to the relevant tab (use `@Binding var selectedTab`)

Progress: show "X of 4 complete" in muted text below the list.

---

### Section 4: Mobile Stats Grid (2×2)

```swift
LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
    MobileStatTile(label: "This Week", value: "3 jobs")
    MobileStatTile(label: "Completed", value: "\(completedCount)")
    MobileStatTile(label: "Remaining", value: "\(remainingCount)")
    MobileStatTile(label: "Week Earned", value: weekEarned.currency)
}
```

Each `MobileStatTile`:
- Background: `Color.sweeplyBackground` (secondary surface)
- Corner radius: 16pt
- Padding: 16pt
- Content:
  - Label: 11pt, `Color.sweeplyTextSub`, medium weight, on top
  - Value: 22pt, bold, monospaced for financial values, primary color

Data:
- This Week: count of jobs this week (scheduled + in-progress + completed)
- Completed: jobs with `.completed` status
- Remaining: jobs with `.scheduled` or `.inProgress` status today
- Week Earned: sum of `price` for completed jobs this week

---

### Section 5: Today's Schedule Card

Full-width card. Border. No shadow.

**Header row:**
```
Today's Schedule          View all →
```
- "Today's Schedule": 15pt semibold
- "View all →": ghost button, `Color.sweeplyTextSub`, `chevron.right` SF symbol 10pt, no bg

**Job rows** (for each job today, sorted by time):
```
09:00  ●  Sarah Mitchell              $180  [···]
AM        Standard Clean · 2.5h · 142 Coral Way
```

Layout:
```swift
HStack(spacing: 12) {
    // Time column
    VStack(alignment: .trailing, spacing: 1) {
        Text("9:00").font(.system(size: 13, weight: .semibold, design: .monospaced))
        Text("AM").font(.system(size: 10)).foregroundStyle(Color.sweeplyTextSub)
    }
    .frame(width: 36, alignment: .trailing)
    
    // Status dot
    Circle().fill(statusColor).frame(width: 7, height: 7)
    
    // Info
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            Text(job.clientName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer()
            Text(job.price.currency).font(.system(size: 13, weight: .semibold, design: .monospaced))
            Menu { /* actions */ } label: {
                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Color.sweeplyTextSub)
            }
        }
        Text("\(job.serviceType.rawValue) · \(durationString) · \(job.address)")
            .font(.system(size: 12))
            .foregroundStyle(Color.sweeplyTextSub)
            .lineLimit(1)
    }
}
.padding(.vertical, 10)
```

Status dot colors:
- `.completed` → `Color.sweeplySuccess`
- `.inProgress` → `Color(red: 0.4, green: 0.45, blue: 0.95)` (blue-purple)
- `.scheduled` → `Color.sweeplyTextSub.opacity(0.5)`
- `.cancelled` → `Color.sweeplyDestructive`

`Menu` actions per job:
- "Start Job" (play.fill icon) → changes status to .inProgress
- "Mark Complete" (checkmark icon) → changes status to .completed
- "Cancel Job" (xmark icon, destructive) → changes status to .cancelled

Divider between rows (`Divider().padding(.leading, 56)`).

**Empty state:**
```swift
VStack(spacing: 8) {
    Image(systemName: "calendar.badge.exclamationmark")
        .font(.system(size: 32))
        .foregroundStyle(Color.sweeplyTextSub.opacity(0.4))
    Text("No jobs scheduled for today")
        .font(.system(size: 14))
        .foregroundStyle(Color.sweeplyTextSub)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 24)
```

---

### Section 6: Business Health Card

Full-width card. Border.

**Header:**
```
Business Health          [week range]          View all →
```
- Week range: e.g. "Mar 31 – Apr 6", 12pt muted

**Two rows divided by Divider:**

Row 1 — Job Value:
```swift
HStack(spacing: 12) {
    // Icon square
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.sweeplySuccess.opacity(0.12))
        .frame(width: 36, height: 36)
        .overlay(Image(systemName: "dollarsign").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.sweeplySuccess))
    
    VStack(alignment: .leading, spacing: 2) {
        Text("Job Value").font(.system(size: 13, weight: .semibold))
        Text("Total value of this week's jobs").font(.system(size: 11)).foregroundStyle(Color.sweeplyTextSub)
    }
    
    Spacer()
    
    VStack(alignment: .trailing, spacing: 4) {
        Text(weekJobValue.currency).font(.system(size: 15, weight: .bold, design: .monospaced))
        TrendBadge(value: "+18%", isPositive: true)
    }
}
.padding(.vertical, 12)
```

Row 2 — Visits Scheduled (same layout):
- Icon: `calendar` in dark navy tinted square (`Color.sweeplyNavy.opacity(0.08)`)
- Value: job count this week as integer string
- Trend badge

`TrendBadge` component:
```swift
struct TrendBadge: View {
    let value: String
    let isPositive: Bool
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text(value).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isPositive ? Color.sweeplySuccess : Color.sweeplyDestructive)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background((isPositive ? Color.sweeplySuccess : Color.sweeplyDestructive).opacity(0.1))
        .clipShape(Capsule())
    }
}
```

---

### Section 7: Outstanding Invoices Card

Full-width card. Border.

**Header:** "Outstanding Invoices" + "View all →"

Show up to 3 invoices where `status != .paid`, sorted: `.overdue` first, then `.unpaid`.

**Each invoice row:**
```swift
HStack(spacing: 0) {
    VStack(alignment: .leading, spacing: 3) {
        Text(invoice.clientName)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
        Text("Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
            .font(.system(size: 12))
            .foregroundStyle(Color.sweeplyTextSub)
    }
    Spacer()
    HStack(spacing: 8) {
        Text(invoice.amount.currency)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
        InvoiceStatusBadge(status: invoice.status)  // existing component
        Button("Mark Paid") { /* action */ }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.sweeplyNavy)
            .clipShape(Capsule())
    }
}
.padding(.vertical, 10)
```

Divider between rows.

**Status badge styling (update InvoiceStatusBadge):**
```swift
// Background: 10% opacity of status color
// Text: status color
// Border: status color at 20% opacity via .overlay stroke
.background(color.opacity(0.10))
.overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 1))
```

**Empty state:**
```swift
VStack(spacing: 8) {
    Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 32))
        .foregroundStyle(Color.sweeplySuccess.opacity(0.4))
    Text("All caught up — no outstanding invoices")
        .font(.system(size: 14))
        .foregroundStyle(Color.sweeplyTextSub)
}
.frame(maxWidth: .infinity).padding(.vertical, 24)
```

---

## Floating Action Button (FAB)

Add to `RootView.swift` as a ZStack overlay.

```swift
ZStack(alignment: .bottomTrailing) {
    TabView(selection: $selectedTab) { ... }
    
    FABView(selectedTab: $selectedTab)
        .padding(.trailing, 20)
        .padding(.bottom, 80) // above tab bar
}
```

`FABView` component (new file: `SWEEPLY/Components/FABView.swift`):

```swift
struct FABView: View {
    @State private var isExpanded = false
    @Binding var selectedTab: RootView.Tab
    
    let actions: [(label: String, icon: String, tab: RootView.Tab)] = [
        ("New Invoice", "doc.badge.plus", .invoices),
        ("New Client", "person.badge.plus", .clients),
        ("New Job", "briefcase.fill", .schedule),
    ]
    
    var body: some View {
        ZStack {
            // Scrim when expanded
            if isExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(duration: 0.3)) { isExpanded = false } }
            }
            
            VStack(alignment: .trailing, spacing: 12) {
                // Expanded action buttons
                if isExpanded {
                    ForEach(actions, id: \.label) { action in
                        FABActionButton(label: action.label, icon: action.icon) {
                            withAnimation(.spring(duration: 0.3)) { isExpanded = false }
                            selectedTab = action.tab
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                
                // Main FAB
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.sweeplyNavy)
                            .frame(width: 56, height: 56)
                            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                        Image(systemName: isExpanded ? "xmark" : "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                            .animation(.spring(response: 0.3), value: isExpanded)
                    }
                }
            }
        }
    }
}

struct FABActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.sweeplyNavy)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
        }
    }
}
```

---

## Card Wrapper Component

Use this for all section cards to keep styling consistent:

```swift
struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(16)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
    }
}
```

---

## Card Header Component

Use this for all "Title + View all →" headers:

```swift
struct CardHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text("View all")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                }
            }
        }
    }
}
```

---

## Entrance Animation

Apply to the main VStack in DashboardView:
```swift
.opacity(appeared ? 1 : 0)
.offset(y: appeared ? 0 : 8)
.onAppear {
    withAnimation(.easeOut(duration: 0.3)) { appeared = true }
}
```

---

## Number Formatting

Financial values (already in DashboardView.swift as extension):
```swift
extension Double {
    var currency: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
}
```

Duration formatting:
```swift
func durationString(_ hours: Double) -> String {
    if hours == 1 { return "1h" }
    if hours == floor(hours) { return "\(Int(hours))h" }
    let h = Int(hours)
    let m = Int((hours - Double(h)) * 60)
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}
```

---

## Git Workflow (After Each Screen)

After completing the dashboard:
```bash
git add .
git commit -m "feat: rebuild dashboard — quick stats, schedule card, business health, outstanding invoices, FAB"
git push origin main
```

Then pull in Xcode: Source Control → Pull.

---

## What NOT to Build Yet

- Schedule, Clients, Invoices, Finances, Settings screens
- Supabase / real data
- iPad layout adaptations
- Auth screen
- Push notifications
- Dark mode adaptations (come after all screens are done)
