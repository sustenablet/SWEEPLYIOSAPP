# SWEEPLY iOS — Agent Instructions

## Project Type
Native SwiftUI iOS app (iOS 17+) for cleaning business management. MVVM + Observable pattern.

## Build & Run
```bash
# Build simulator (note: project is inside SWEEPLY/ subdirectory)
xcodebuild -project SWEEPLY/SWEEPLY.xcodeproj -scheme SWEEPLY -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build

# Or with the Xcode MCP tools (already configured in .xcodebuildmcp/config.yaml)
xcodebuild_build_run_sim
```

## Key Files
- `SWEEPLY/SWEEPLY/SWEEPLYApp.swift` — Entry point
- `SWEEPLY/SWEEPLY/RootView.swift` — Main TabView (5 tabs: Dashboard, Schedule, Clients, Invoices, Finances)
- `SWEEPLY/SWEEPLY/DesignSystem.swift` — Color/Spacing/Radius tokens (sweeplyAccent, sweeplyNavy, sweeplySuccess, etc.)
- `SWEEPLY/SWEEPLY/Models.swift` — All data models (UserProfile, Client, Job, Invoice, etc.)
- `SWEEPLY/SWEEPLY/MockData.swift` — Static mock data for development

## Data Layer
- Currently uses MockData.swift (mock profiles, clients, jobs, invoices)
- Supabase integration planned (schema in `supabase/schema.sql`, migrations in `supabase/migrations/`)
- SupabaseConfig.plist required for real backend

## Architecture Notes
- Two user types: Owner (full access) and Cleaner (limited)
- Stores: JobsStore, ClientsStore, InvoicesStore, ProfileStore, TeamStore, ExpensesStore
- Custom components in `SWEEPLY/SWEEPLY/Components/`

## Existing Context
- `SWEEPLY.md` — Feature overview and design system reference
- `CURSOR_CONTEXT.md` — Detailed UI specs and implementation details

## Testing
- Unit tests: `SWEEPLYTests/`
- UI tests: `SWEEPLYUITests/`
- Widgets: `SweeplyWIdgets/`

## Git
Standard workflow. Push to origin main after completing features.