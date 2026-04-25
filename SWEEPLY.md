# SWEEPLY — Cleaning Business Made Simple

---

## What Is SWEEPLY?

SWEEPLY is an all-in-one iOS app designed specifically for cleaning professionals and small cleaning businesses. It replaces the chaos of spreadsheets, sticky notes, and scattered paperwork with one streamlined tool that handles everything from booking jobs to getting paid.

Whether you're a solo cleaner running your own business or managing a small team, SWEEPLY helps you stay organized, professional, and in control of your day-to-day operations.

---

## Current Features

### 💼 Client Management
- **Full client profiles** — Store names, emails, phone numbers, addresses, and detailed notes for every customer
- **Entry instructions** — Remember how to access each home (gate codes, alarm details, preferred entry)
- **Preferred services** — Track what each client usually orders (standard clean, deep clean, etc.)
- **Activity tracking** — See which clients are active and which you haven't heard from in a while

### 📅 Job Scheduling & Tracking
- **Create and manage jobs** — Schedule cleanings with date, time, service type, duration, and price
- **Job statuses** — Track jobs as Scheduled, In Progress, Completed, or Cancelled
- **Recurring jobs** — Set up weekly, biweekly, or monthly recurring appointments (auto-generates future jobs)
- **Job assignment** — Assign jobs to yourself or team members
- **Filtering** — Quickly find jobs by status, date, or client

### 💰 Invoicing & Payments
- **Professional invoices** — Generate itemized invoices for every job
- **Payment tracking** — Mark invoices as Paid/Unpaid/Overdue
- **Payment methods** — Record how clients paid (Check, Zelle, Venmo, Cash, Card)
- **Partial payments** — Track partial payments and see what's still owed
- **Invoice numbering** — Auto-generated invoice numbers keep things organized

### 📊 Finances & Reporting
- **Revenue dashboard** — See your weekly and monthly earnings at a glance
- **Expense tracking** — Log business expenses (supplies, fuel, equipment, insurance, marketing)
- **Financial overview** — Understand your profit margins and business health

### 👥 Team Management
- **Add team members** — Bring cleaners onto your account
- **Role management** — Owners and team members with different access levels
- **Pay rates** — Set up per-job, per-day, per-week, or custom pay rates for each team member
- **Team payments** — Track and manage what you owe your team

### 💬 Client Communication
- **SMS messaging** — Send text messages directly from the app
- **Conversation history** — Keep a record of all client communications
- **Quick actions** — Message clients with one tap

### 📱 Notifications & Reminders
- **Push notifications** — Get reminded about upcoming jobs
- **In-app notifications** — Alerts for new messages, invoice updates, and team activity
- **Background refresh** — App stays updated even when closed

### 🔍 Search & Discovery
- **Spotlight search** — Find clients and jobs from your phone's search bar
- **Quick shortcuts** — Launch directly into New Job or New Client from the home screen

### ⚙️ Settings & Customization
- **Business profile** — Set your business name, address, and contact info
- **Service catalog** — Customize your services and pricing (Standard Clean, Deep Clean, Move In/Out, Post Construction, Office Clean, and add-ons)
- **Default rates** — Set your standard hourly rate and duration
- **Tax configuration** — Add tax rate to invoices if needed
- **Payment terms** — Set due dates (e.g., Net 14)

---

## Design & Visual Style

### Color Palette

| Color | Usage | Light Mode | Dark Mode |
|-------|-------|------------|-----------|
| **Sweeply Accent** | Primary actions, highlights | Deep Blue-Gray (#28536B) | Lighter Blue-Gray (#6987A0) |
| **Sweeply Navy** | Text, tab bar, dark elements | Slate Charcoal (#262829) | Dark Navy (#141416) |
| **Sweeply Background** | Page backgrounds | Warm Stone (#F6F5F2) | Near Black (#0D0D0F) |
| **Sweeply Surface** | Cards, sheets, modals | White | Dark Gray (#1C1C21) |
| **Sweeply Success** | Paid status, positive actions | Teal (#268080) | Lighter Teal |
| **Sweeply Warning** | Overdue, attention needed | Warm Amber (#BF8040) | Lighter Amber |
| **Sweeply Destructive** | Errors, cancellations | Deep Coral (#B34040) | Lighter Coral |

### Design Philosophy

- **Warm, professional aesthetic** — Avoids cold corporate blues in favor of a warm, approachable feel that reflects the personal nature of cleaning businesses
- **Clean typography** — Clear hierarchy with system fonts, monospace for numbers and currency
- **Card-based layout** — Information organized in clean, tappable cards
- **Generous spacing** — Easy to read and interact with, even with wet hands or on the go
- **Dark mode support** — Full dark mode that maintains the warm aesthetic

### Typography

- **Display** — System default, bold for headings
- **Monospace** — Used for currency, numbers, invoice numbers, dates
- **Size scale** — Consistent sizing: xs, sm, md, base, lg, xl, xxl, xxxl

### Corner Radius

- **Small** (8pt) — Buttons, small elements
- **Medium** (12pt) — Cards, inputs
- **Large** (16pt) — Sheets, modals
- **Full** (999pt) — Pills, badges

---

## Technology Overview

- **Platform** — Native iOS (SwiftUI)
- **Backend** — Supabase (PostgreSQL, Authentication, Realtime)
- **Architecture** — MVVM with Observable macros
- **Storage** — Local caching with Cloud sync
- **Background tasks** — Background App Refresh for updates
- **Widgets** — iOS Home Screen widgets (coming soon)

---

## Summary

SWEEPLY gives cleaning professionals everything they need to run their business from their phone:

- ✅ Book and track cleaning jobs
- ✅ Manage client information
- ✅ Create and send invoices
- ✅ Track payments
- ✅ Monitor revenue and expenses
- ✅ Manage a small team
- ✅ Communicate with clients via SMS

All wrapped in a beautiful, warm, professional design that feels as good to use as it looks.

---

*Built for cleaners, by people who understand cleaning businesses.*