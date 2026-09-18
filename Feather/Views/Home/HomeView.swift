//
//  HomeView.swift
//  AshteMobile
//
//  Created for AshteMobile
//

import SwiftUI
import NimbleViews
import AltSourceKit
import Foundation
import UIKit
import Combine
import CoreData

// MARK: - Models
struct AshteHomeAppResponse: Codable {
    let name: String?
    let apps: [AshteHomeAppModel]
}

struct AshteHomeAppModel: Codable, Identifiable {
    var id: Int { idNumber }
    let idNumber: Int
    let name: String
    let version: String?
    let category: String?
    let iconURL: String?
    let size: String?
    let developerName: String?
    let bundleIdentifier: String?
    let download_url: String
    
    var stringID: String {
        return "\(idNumber)"
    }
    
    var downloadURLObject: URL? {
        return URL(string: download_url)
    }
    
    enum CodingKeys: String, CodingKey {
        case idNumber = "id"
        case name, version, category, iconURL, size, developerName, bundleIdentifier, download_url
    }

    var fullImageURL: URL? {
        guard let img = iconURL else { return nil }
        if img.hasPrefix("http") { return URL(string: img) }
        return URL(string: "https://ashtemobile.site/\(img)")
    }
}

// MARK: - Main View
struct HomeView: View {
    @State private var appsList: [AshteHomeAppModel] = []
    @State private var searchText = ""
    
    @State private var _selectedInstallAppPresenting: AnyApp?
    
    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
        animation: .snappy
    ) private var _signedApps: FetchedResults<Signed>
    
    private var filteredApps: [AshteHomeAppModel] {
        appsList.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NBNavigationView(.localized("Discover")) {
            ScrollView {
                LazyVStack(spacing: 20) {
                    
                    // MARK: - Modern Telegram Banner
                    if !filteredApps.isEmpty {
                        Button(action: {
                            if let url = URL(string: "https://t.me/ashtemobile") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    LinearGradient(colors: [Color(hex: "8A2387"), Color(hex: "E94057"), Color(hex: "F27121")], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AshteMobile Channel")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                    
                                    Text("Join Telegram for the latest updates")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.purple.opacity(0.8), .purple.opacity(0.1))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // MARK: - App List Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Applications")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                Spacer()
                                Text("\(filteredApps.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.purple))
                            }
                            .padding(.horizontal, 20)
                            
                            VStack(spacing: 0) {
                                ForEach(filteredApps) { app in
                                    NavigationLink(destination: AshteHomeAppDetailView(app: app, onDownloadComplete: handleAutoSign)) {
                                        AshteHomeAppCell(app: app, onDownloadComplete: handleAutoSign)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(Color(UIColor.systemBackground))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if app.idNumber != filteredApps.last?.idNumber {
                                        Divider()
                                            .padding(.leading, 96) // Align with text
                                    }
                                }
                            }
                            .background(Color(UIColor.systemBackground))
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .overlay {
                if filteredApps.isEmpty {
                    AshteHomeEmptyView()
                }
            }
            .refreshable {
                await loadRemoteApps()
            }
        }
        .task {
            await loadRemoteApps()
        }
        .sheet(item: $_selectedInstallAppPresenting) { app in
            InstallPreviewView(app: app.base, isSharing: app.archive)
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AshteMobile.installApp"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let signedApp = _signedApps.first {
                    _selectedInstallAppPresenting = AnyApp(base: signedApp)
                }
            }
        }
    }
    
    // 💡 چارەسەری قایم: وەرگرتنی ڕاستەوخۆی کۆتا ئەپی داونلۆدکراو بێ پێویستبوون بە پشکنینی ناو
    private func handleAutoSign() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let request = NSFetchRequest<Imported>(entityName: "Imported")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
            
            guard let importedApps = try? Storage.shared.context.fetch(request),
                  let importedApp = importedApps.first else {
                print("No imported app found")
                return
            }
            
            let options = OptionsManager.shared.options
            let certRequest = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
            certRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
            let certs = try? Storage.shared.context.fetch(certRequest)
            let storedCertIndex = UserDefaults.standard.integer(forKey: "ashtemobile.selectedCert")
            let selectedCert = (certs?.indices.contains(storedCertIndex) == true) ? certs![storedCertIndex] : certs?.first
            
            FR.signPackageFile(
                importedApp,
                using: options,
                icon: nil,
                certificate: selectedCert
            ) { error in
                DispatchQueue.main.async {
                    if error == nil {
                        if options.post_deleteAppAfterSigned {
                            Storage.shared.deleteApp(for: importedApp)
                        }
                        NotificationCenter.default.post(name: Notification.Name("AshteMobile.installApp"), object: nil)
                    } else {
                        print("Signing Error: \(String(describing: error))")
                    }
                }
            }
        }
    }
    
    private func loadRemoteApps() async {
        guard let url = URL(string: "https://ashtemobile.site/Ashtemobile.json") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(AshteHomeAppResponse.self, from: data)
            DispatchQueue.main.async {
                self.appsList = decoded.apps
            }
        } catch {
            print("Error loading apps: \(error)")
        }
    }
}

// MARK: - Empty State View
struct AshteHomeEmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.3x3.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("No Applications Found")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("Check your connection or pull to refresh.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - App Cell View (Modernized)
struct AshteHomeAppCell: View {
    let app: AshteHomeAppModel
    var onDownloadComplete: () -> Void
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var isDownloading = false

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: app.fullImageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color(UIColor.secondarySystemBackground)
                    ProgressView()
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(app.developerName ?? "AshteMobile")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            ZStack {
                if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                    ZStack {
                        Circle()
                            .stroke(Color.purple.opacity(0.2), lineWidth: 3)
                            .frame(width: 32, height: 32)
                        
                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 32, height: 32)
                            .animation(.spring(), value: downloadProgress)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.purple)
                    }
                    .onTapGesture {
                        downloadManager.cancelDownload(currentDownload)
                    }
                } else {
                    Button(action: { triggerDownload() }) {
                        Text(isDownloading ? "..." : "GET")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(width: 72, height: 32)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .onAppear(perform: setupObserver)
        .onDisappear { cancellable?.cancel() }
        .onChange(of: downloadManager.downloads.count) { _ in
            let isCurrentlyDownloading = downloadManager.getDownload(by: app.stringID) != nil
            
            if isCurrentlyDownloading {
                isDownloading = true
                setupObserver()
            } else if isDownloading && !isCurrentlyDownloading {
                isDownloading = false
                onDownloadComplete()
            }
        }
    }
    
    private func triggerDownload() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if let dlURL = app.downloadURLObject {
            _ = DownloadManager.shared.startDownload(from: dlURL, id: app.stringID)
        }
    }
    
    private func setupObserver() {
        cancellable?.cancel()
        guard let download = downloadManager.getDownload(by: app.stringID) else {
            downloadProgress = 0
            return
        }
        downloadProgress = download.overallProgress

        let publisher = Publishers.CombineLatest(
            download.$progress,
            download.$unpackageProgress
        )

        cancellable = publisher.sink { _, _ in
            downloadProgress = download.overallProgress
        }
    }
}

// MARK: - App Detail View (Modernized)
struct AshteHomeAppDetailView: View {
    let app: AshteHomeAppModel
    var onDownloadComplete: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var isDownloading = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Modern Header with fade and glassmorphism
                ZStack(alignment: .bottom) {
                    GeometryReader { proxy in
                        let minY = proxy.frame(in: .global).minY
                        let height = max(280 + minY, 280)
                        
                        AsyncImage(url: app.fullImageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill).blur(radius: 40)
                        } placeholder: {
                            LinearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        }
                        .frame(width: proxy.size.width, height: height)
                        .offset(y: minY > 0 ? -minY : 0)
                        .clipped()
                    }
                    .frame(height: 280)
                    
                    LinearGradient(colors: [Color(UIColor.systemBackground).opacity(0), Color(UIColor.systemBackground)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 100)
                    
                    // Floating Back Button
                    VStack {
                        HStack {
                            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 50)
                        Spacer()
                    }
                }
                
                // App Profile Info
                VStack(spacing: 16) {
                    AsyncImage(url: app.fullImageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(UIColor.secondarySystemBackground)
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .offset(y: -55)
                    .padding(.bottom, -55)
                    
                    VStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text(app.developerName ?? "AshteMobile")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    // Download Button
                    ZStack {
                        if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Downloading...")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 180, height: 44)
                            .background(Color.purple)
                            .clipShape(Capsule())
                            .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 5)
                            .onTapGesture {
                                downloadManager.cancelDownload(currentDownload)
                            }
                        } else {
                            Button(action: { triggerDownload() }) {
                                Text(isDownloading ? "..." : "GET APP")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 160, height: 44)
                                    .background(Color.purple)
                                    .clipShape(Capsule())
                                    .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 5)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                
                // Information Cards
                VStack(alignment: .leading, spacing: 16) {
                    Text("Information")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .padding(.top, 30)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 0) {
                        AshteHomeInfoRow(title: "Version", value: app.version ?? "1.0", isLast: false)
                        AshteHomeInfoRow(title: "Category", value: app.category ?? "Apps", isLast: false)
                        AshteHomeInfoRow(title: "Developer", value: app.developerName ?? "AshteMobile", isLast: false)
                        AshteHomeInfoRow(title: "Identifier", value: app.bundleIdentifier ?? "com.ashtemobile", isLast: true)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 50)
            }
        }
        .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        .edgesIgnoringSafeArea(.top)
        .navigationBarHidden(true)
        .onAppear(perform: setupObserver)
        .onDisappear { cancellable?.cancel() }
        .onChange(of: downloadManager.downloads.count) { _ in
            let isCurrentlyDownloading = downloadManager.getDownload(by: app.stringID) != nil
            
            if isCurrentlyDownloading {
                isDownloading = true
                setupObserver()
            } else if isDownloading && !isCurrentlyDownloading {
                isDownloading = false
                onDownloadComplete()
            }
        }
    }
    
    private func triggerDownload() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if let dlURL = app.downloadURLObject {
            _ = DownloadManager.shared.startDownload(from: dlURL, id: app.stringID)
        }
    }
    
    private func setupObserver() {
        cancellable?.cancel()
        guard let download = downloadManager.getDownload(by: app.stringID) else {
            downloadProgress = 0
            return
        }
        downloadProgress = download.overallProgress

        let publisher = Publishers.CombineLatest(
            download.$progress,
            download.$unpackageProgress
        )

        cancellable = publisher.sink { _, _ in
            downloadProgress = download.overallProgress
        }
    }
}

struct AshteHomeInfoRow: View {
    let title: String
    let value: String
    let isLast: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            if !isLast {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}

// Helper extension بۆ بەکارهێنانی ڕەنگی HEX ئەگەر پێویست بوو بۆ باکگراوندی تێلیگرام
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
