//
//  HomeView.swift
//  AshteMobile
//
//  Created for AshteMobile
//  100% Pro UI with Filter Tabs & Fixed Double Install
//

import SwiftUI
import NimbleViews
import AltSourceKit
import Foundation
import UIKit
import Combine
import CoreData
import AudioToolbox 

// MARK: - Global Lock
class HomeGlobalLock {
    static var isSigningActive = false
}

// MARK: - Tab Categories
enum HomeCategoryTab: String, CaseIterable, Identifiable {
    case all = "All"
    case apps = "Apps"
    case games = "Games"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all: return "All"
        case .apps: return "Apps"
        case .games: return "Games"
        }
    }
}

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
    let type: String? 
    let iconURL: String?
    let size: String?
    let developerName: String?
    let bundleIdentifier: String?
    let download_url: String
    let descriptionText: String? 
    
    var stringID: String { return "\(idNumber)" }
    var downloadURLObject: URL? { return URL(string: download_url) }
    
    enum CodingKeys: String, CodingKey {
        case idNumber = "id"
        case name, version, category, type, iconURL, size, developerName, bundleIdentifier, download_url
        case descriptionText = "description"
    }

    var fullImageURL: URL? {
        guard let img = iconURL else { return nil }
        if img.hasPrefix("http") { return URL(string: img) }
        return URL(string: "https://ashtemobile.site/\(img)")
    }
}

// MARK: - Banner Model
struct SocialBanner: Identifiable {
    let id = UUID()
    let imageURL: URL?
    let destinationURL: URL?
}

// MARK: - Main Home View
struct HomeView: View {
    @Environment(\.openURL) var openURL
    @State private var appsList: [AshteHomeAppModel] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var selectedTab: HomeCategoryTab = .all
    
    @State private var _selectedInstallAppPresenting: AnyApp?
    @AppStorage("AshteMobile.installationMethod") private var installationMethod: Int = 0
    
    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
        animation: .snappy
    ) private var _signedApps: FetchedResults<Signed>
    
    private var filteredApps: [AshteHomeAppModel] {
        appsList.filter { app in
            let matchesSearch = searchText.isEmpty || app.name.localizedCaseInsensitiveContains(searchText)
            guard matchesSearch else { return false }
            
            let appType = (app.type ?? "").lowercased()
            switch selectedTab {
            case .all:
                return true
            case .apps:
                return appType == "apps"
            case .games:
                return appType == "games"
            }
        }
    }
    
    @State private var _currentBannerIndex = 0
    private let bannerTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
    
    let staticBanners = [
        SocialBanner(
            imageURL: URL(string: "https://ashtemobile.site/img/t.png"),
            destinationURL: URL(string: "https://t.me/ashtemobile")
        ),
        SocialBanner(
            imageURL: URL(string: "https://ashtemobile.site/img/i.png"),
            destinationURL: URL(string: "https://instagram.com/ashtemobile")
        )
    ]
    
    var body: some View {
        NBNavigationView(.localized("Discover")) {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                if isLoading && appsList.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(.localized("Loading..."))
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            
                            // MARK: - Banners Section
                            if searchText.isEmpty {
                                TabView(selection: $_currentBannerIndex) {
                                    ForEach(staticBanners.indices, id: \.self) { index in
                                        let banner = staticBanners[index]
                                        Button {
                                            if let url = banner.destinationURL {
                                                UIApplication.shared.open(url)
                                            }
                                        } label: {
                                            AsyncImage(url: banner.imageURL) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else if phase.error != nil {
                                                    Rectangle().fill(Color(uiColor: .secondarySystemBackground))
                                                        .overlay(Image(systemName: "photo.fill").foregroundColor(.secondary))
                                                } else {
                                                    Rectangle().fill(Color(uiColor: .secondarySystemBackground))
                                                        .overlay(ProgressView())
                                                }
                                            }
                                            .frame(height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
                                            .padding(.horizontal, 20)
                                        }
                                        .buttonStyle(.plain)
                                        .tag(index)
                                    }
                                }
                                .frame(height: 230)
                                .tabViewStyle(.page(indexDisplayMode: .always))
                                .onReceive(bannerTimer) { _ in
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        _currentBannerIndex = (_currentBannerIndex + 1) % staticBanners.count
                                    }
                                }
                                .padding(.top, 10)
                            }
                            
                            // MARK: - Filter Tabs
                            HStack(spacing: 10) {
                                ForEach(HomeCategoryTab.allCases) { tab in
                                    Button {
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = tab
                                        }
                                    } label: {
                                        Text(tab.title)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(selectedTab == tab ? .white : .primary)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 8)
                                            .background(
                                                ZStack {
                                                    if selectedTab == tab {
                                                        Capsule()
                                                            .fill(Color.accentColor)
                                                            .matchedGeometryEffect(id: "activeTabBadge", in: tabAnimation)
                                                    } else {
                                                        Capsule()
                                                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                                                    }
                                                }
                                            )
                                            .shadow(color: selectedTab == tab ? Color.accentColor.opacity(0.3) : .black.opacity(0.03), radius: 5, x: 0, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            // MARK: - Apps List
                            if !filteredApps.isEmpty {
                                VStack(spacing: 14) {
                                    HStack {
                                        Text(selectedTab.title)
                                            .font(.system(.title2, design: .rounded).bold())
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("\(filteredApps.count)")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .clipShape(Capsule())
                                    }
                                    .padding(.horizontal, 22)
                                    
                                    VStack(spacing: 0) {
                                        ForEach(filteredApps) { app in
                                            NavigationLink(destination: AshteHomeAppDetailView(app: app, onDownloadComplete: handleAutoSign)) {
                                                AshteHomeAppCell(app: app, onDownloadComplete: handleAutoSign)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 14)
                                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                            }
                                            .buttonStyle(.plain)
                                            
                                            if app.idNumber != filteredApps.last?.idNumber {
                                                Divider()
                                                    .padding(.leading, 95)
                                            }
                                        }
                                    }
                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .padding(.horizontal, 16)
                                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                                }
                            } else if !searchText.isEmpty || !isLoading {
                                AshteHomeEmptyView()
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: .localized("Search apps..."))
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
        // 💡 قفڵی گشتی بە UserDefaults بۆ بەشی Homeیش
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AshteMobile.installApp"))) { _ in
            let now = Date().timeIntervalSince1970
            let lastTime = UserDefaults.standard.double(forKey: "AshteMobile.GlobalInstallLock")
            
            if now - lastTime > 2.0 {
                UserDefaults.standard.set(now, forKey: "AshteMobile.GlobalInstallLock")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let signedApp = _signedApps.first {
                        _selectedInstallAppPresenting = AnyApp(base: signedApp)
                    }
                }
            }
        }
    }
    
    @Namespace private var tabAnimation
    
    // MARK: - Auto-Sign Logic
    private func handleAutoSign() {
        if HomeGlobalLock.isSigningActive { return }
        HomeGlobalLock.isSigningActive = true
        
        if installationMethod == 1 {
            HomeGlobalLock.isSigningActive = false
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let request = NSFetchRequest<Imported>(entityName: "Imported")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
            request.fetchLimit = 1 
            
            guard let importedApps = try? Storage.shared.context.fetch(request),
                  let importedApp = importedApps.first else {
                HomeGlobalLock.isSigningActive = false
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
                    HomeGlobalLock.isSigningActive = false
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
        isLoading = true
        guard let url = URL(string: "https://ashtemobile.site/Ashtemobile.json") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(AshteHomeAppResponse.self, from: data)
            DispatchQueue.main.async {
                self.appsList = decoded.apps
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async { self.isLoading = false }
        }
    }
}

// MARK: - Empty State View
struct AshteHomeEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text(.localized("No Applications Found"))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.primary)
            Text(.localized("Try selecting another category or searching again."))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Sleek App Cell
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
                Color(UIColor.tertiarySystemGroupedBackground)
            }
            .frame(width: 65, height: 65)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(app.type == "games" ? "Game" : "App") • v\(app.version ?? "1.0")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 10)
            
            ZStack {
                if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                    ZStack {
                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 32, height: 32)
                            .animation(.smooth, value: downloadProgress)

                        Image(systemName: downloadProgress >= 0.75 ? "archivebox.fill" : "stop.fill")
                            .foregroundStyle(.tint)
                            .font(.system(size: 11, weight: .black))
                    }
                    .onTapGesture {
                        if downloadProgress <= 0.75 {
                            downloadManager.cancelDownload(currentDownload)
                        }
                    }
                } else {
                    Button(action: { triggerDownload() }) {
                        Text(.localized("Get"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 5, x: 0, y: 3)
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
                if downloadProgress >= 0.98 {
                    AudioServicesPlaySystemSound(1300)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onDownloadComplete()
                }
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
        let publisher = Publishers.CombineLatest(download.$progress, download.$unpackageProgress)
        cancellable = publisher.sink { _, _ in downloadProgress = download.overallProgress }
    }
}

// MARK: - Premium Detail View
struct AshteHomeAppDetailView: View {
    let app: AshteHomeAppModel
    var onDownloadComplete: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var isDownloading = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    GeometryReader { proxy in
                        let minY = proxy.frame(in: .global).minY
                        AsyncImage(url: app.fullImageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height + (minY > 0 ? minY : 0))
                        .clipped()
                        .offset(y: minY > 0 ? -minY : 0)
                        .blur(radius: 30, opaque: true)
                        .overlay(Color.black.opacity(0.3))
                    }
                    .frame(height: 250)
                    
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 50)
                }
                
                VStack(spacing: 16) {
                    AsyncImage(url: app.fullImageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(UIColor.secondarySystemBackground)
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                    .padding(.top, -55)
                    
                    VStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text(app.developerName ?? "AshteMobile")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 16) {
                        if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Downloading...")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                        } else {
                            Button(action: { triggerDownload() }) {
                                Text(isDownloading ? "..." : .localized("Get"))
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Color.accentColor)
                                    .clipShape(Capsule())
                                    .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                    
                    HStack(spacing: 15) {
                        AshteInfoCard(title: "Version", value: app.version ?? "1.0", icon: "v.circle.fill")
                        AshteInfoCard(title: "Size", value: app.size ?? "N/A", icon: "shippingbox.fill")
                        AshteInfoCard(title: "Category", value: app.type == "games" ? "Game" : "App", icon: "square.grid.2x2.fill")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 15)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About this app")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(app.descriptionText ?? "No description available for \(app.name). Discover the amazing features inside.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .lineSpacing(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .padding(.bottom, 50)
            }
        }
        .edgesIgnoringSafeArea(.top)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
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
                if downloadProgress >= 0.98 {
                    AudioServicesPlaySystemSound(1300)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onDownloadComplete()
                }
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
        let publisher = Publishers.CombineLatest(download.$progress, download.$unpackageProgress)
        cancellable = publisher.sink { _, _ in downloadProgress = downloadManager.getDownload(by: app.stringID)?.overallProgress ?? 0 }
    }
}

// MARK: - Modern Info Card
struct AshteInfoCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}
