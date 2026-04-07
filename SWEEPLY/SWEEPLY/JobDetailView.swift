import PhotosUI
import SwiftUI

struct JobDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JobsStore.self) private var jobsStore
    @Environment(ClientsStore.self) private var clientsStore

    let jobId: UUID
    @State private var showInvoiceSheet = false

    // Photo attachments
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoFilenames: [String] = []
    @State private var selectedPhotoIndex: PhotoIndex? = nil
    @State private var showPhotoPicker = false

    private var job: Job? {
        jobsStore.jobs.first(where: { $0.id == jobId })
    }

    private var client: Client? {
        guard let job else { return nil }
        return clientsStore.clients.first(where: { $0.id == job.clientId })
    }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        jobHeader(job: job)
                        actionButtons(job: job)
                        
                        if let client {
                            clientProfileCard(client: client)
                        }

                        if let client = client, !client.entryInstructions.isEmpty || !client.notes.isEmpty {
                            propertyNotesCard(client: client)
                        }
                        
                        jobDetailsCard(job: job)
                        jobPhotosSection(job: job)

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
                .background(Color.sweeplyBackground.ignoresSafeArea())
                .navigationTitle("Job Details")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showInvoiceSheet) {
                    NewInvoiceView(prefill: job)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.square")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.sweeplyTextSub.opacity(0.5))
                    Text("Job not found")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Button("Go Back") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sweeplyBackground)
            }
        }
    }

    // MARK: - Header
    private func jobHeader(job: Job) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.serviceType.rawValue)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                    Text(job.price.currency)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sweeplyNavy.opacity(0.8))
                        .monospacedDigit()
                }
                Spacer()
                StatusBadge(status: job.status)
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.sweeplyAccent)
                Text(job.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sweeplyNavy)
                Spacer()
                if job.isRecurring {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Recurring")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.sweeplyAccent)
                }
            }
            .padding(12)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.sweeplyBorder, lineWidth: 1))
        }
    }

    // MARK: - Action Buttons
    private func actionButtons(job: Job) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if job.status != .completed {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task { await jobsStore.updateStatus(id: job.id, status: .completed) }
                    } label: {
                        Label("Complete Job", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sweeplySuccess)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await jobsStore.updateStatus(id: job.id, status: .scheduled) }
                    } label: {
                        Label("Re-open Job", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sweeplySurface)
                            .foregroundStyle(Color.sweeplyNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyBorder, lineWidth: 1))
                    }
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let addr = job.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(addr)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Navigate", systemImage: "location.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplyNavy)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            // Create Invoice — visible once the job is completed
            if job.status == .completed {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showInvoiceSheet = true
                } label: {
                    Label("Create Invoice", systemImage: "doc.text.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.sweeplyAccent.opacity(0.12))
                        .foregroundStyle(Color.sweeplyNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sweeplyAccent.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Client Profile Card
    private func clientProfileCard(client: Client) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT PROFILE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            
            NavigationLink(destination: ClientDetailView(clientId: client.id)) {
                SectionCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.sweeplyNavy.opacity(0.1))
                                .frame(width: 48, height: 48)
                            Text(String(client.name.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(client.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.sweeplyNavy)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 10))
                                Text(client.phone.isEmpty ? "No phone listed" : client.phone)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(Color.sweeplyTextSub)
                        }
                        
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sweeplyBorder)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Property Notes
    private func propertyNotesCard(client: Client) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROPERTY INSTRUCTIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    if !client.entryInstructions.isEmpty {
                        JobInfoRow(icon: "key.fill", title: "Entry", value: client.entryInstructions)
                    }
                    if !client.entryInstructions.isEmpty && !client.notes.isEmpty {
                        Divider()
                    }
                    if !client.notes.isEmpty {
                        JobInfoRow(icon: "doc.text.fill", title: "Internal Notes", value: client.notes)
                    }
                }
            }
        }
    }

    // MARK: - Job Details
    private func jobDetailsCard(job: Job) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JOB DETAILS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sweeplyTextSub)
                .tracking(1.0)
            
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    JobInfoRow(icon: "mappin.and.ellipse", title: "Location", value: job.address.isEmpty ? "No address provided" : job.address)
                    Divider()
                    JobInfoRow(icon: "clock.fill", title: "Est. Duration", value: "\(Int(job.duration)) Hours")
                    Divider()
                    JobInfoRow(icon: "tag.fill", title: "Price", value: job.price.currency)
                }
            }
        }
    }
}

private struct JobInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.sweeplyAccent)
                .frame(width: 20)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sweeplyTextSub)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sweeplyNavy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Job Photos

    private func jobPhotosSection(job: Job) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PHOTOS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .tracking(1.0)
                Spacer()
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add Photo")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.sweeplyAccent)
                }
                .onChange(of: photoItems) { _, items in
                    Task { await saveNewPhotos(items, jobId: job.id) }
                }
            }

            if photoFilenames.isEmpty {
                Text("No photos yet. Tap \"Add Photo\" to attach images.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sweeplyTextSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photoFilenames.indices, id: \.self) { idx in
                            let filename = photoFilenames[idx]
                            if let img = loadPhoto(filename: filename, jobId: job.id) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .onTapGesture { selectedPhotoIndex = PhotoIndex(idx) }

                                    Button {
                                        deletePhoto(filename: filename, jobId: job.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 2)
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { photoFilenames = loadPhotoMap()[job.id.uuidString] ?? [] }
        .fullScreenCover(item: $selectedPhotoIndex) { pi in
            if pi.value < photoFilenames.count, let img = loadPhoto(filename: photoFilenames[pi.value], jobId: job.id) {
                PhotoFullScreenView(image: img)
            }
        }
    }

    private func saveNewPhotos(_ items: [PhotosPickerItem], jobId: UUID) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let filename = UUID().uuidString + ".jpg"
            let url = photosDirectory(for: jobId).appendingPathComponent(filename)
            try? data.write(to: url)
            await MainActor.run { photoFilenames.append(filename) }
        }
        savePhotoMap(jobId: jobId, filenames: photoFilenames)
    }

    private func deletePhoto(filename: String, jobId: UUID) {
        let url = photosDirectory(for: jobId).appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        photoFilenames.removeAll { $0 == filename }
        savePhotoMap(jobId: jobId, filenames: photoFilenames)
    }

    private func photosDirectory(for jobId: UUID) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jobPhotos/\(jobId.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func loadPhoto(filename: String, jobId: UUID) -> UIImage? {
        let url = photosDirectory(for: jobId).appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    private func loadPhotoMap() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: "jobPhotoMap"),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return map
    }

    private func savePhotoMap(jobId: UUID, filenames: [String]) {
        var map = loadPhotoMap()
        map[jobId.uuidString] = filenames
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: "jobPhotoMap")
        }
    }
}

// MARK: - Helpers

private struct PhotoIndex: Identifiable {
    let id = UUID()
    let value: Int
    init(_ value: Int) { self.value = value }
}

// MARK: - Full screen photo viewer

private struct PhotoFullScreenView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnificationGesture()
                    .onChanged { scale = max(1.0, $0) }
                    .onEnded { _ in withAnimation { scale = 1.0 } }
                )
                .gesture(TapGesture(count: 2).onEnded { withAnimation { scale = scale == 1 ? 2 : 1 } })
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
            }
            .buttonStyle(.plain)
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if abs(v.translation.height) > 100 { dismiss() }
        })
    }
}
