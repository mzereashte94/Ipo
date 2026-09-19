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
import AudioToolbox 

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
    let descriptionText: String? 
    
    var stringID: String {
        return "\(idNumber)"
    }
    
    var downloadURLObject: URL? {
        return URL(string: download_url)
    }
    
    enum CodingKeys: String, CodingKey {
        case idNumber = "id"
        case name, version, category, iconURL, size, developerName, bundleIdentifier, download_url
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

// MARK: - Main View
struct HomeView: View {
    @State private var appsList: [AshteHomeAppModel] = []
    @State private var searchText = ""
    
    @State private var _selectedInstallAppPresenting: AnyApp?
    
    // 💡 زیادکردنی خوێندنەوەی جۆری ئینستاڵکردن لە ڕێکخستنەکانەوە
    @AppStorage("AshteMobile.installationMethod") private var installationMethod: Int = 0
    
    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
        animation: .snappy
    ) private var _signedApps: FetchedResults<Signed>
    
    private var filteredApps: [AshteHomeAppModel] {
        appsList.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    let banners = [
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
            ScrollView {
                VStack(spacing: 0) {
                    if searchText.isEmpty {
                        TabView {
                            ForEach(banners) { banner in
                                Button(action: {
                                    if let url = banner.destinationURL {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    AsyncImage(url: banner.imageURL) { image in
                                        image.resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color(UIColor.secondarySystemBackground))
                                            .overlay(ProgressView())
                                    }
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .frame(height: 210)
                        .padding(.top, 10)
                    }
                    
                    if !filteredApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(.localized("Recently Updated"))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(filteredApps.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 15)
                            .padding(.bottom, 5)
                            
                            LazyVStack(spacing: 0) {
                                ForEach(filteredApps) { app in
                                    NavigationLink(destination: AshteHomeAppDetailView(app: app, onDownloadComplete: handleAutoSign)) {
                                        AshteHomeAppCell(app: app, onDownloadComplete: handleAutoSign)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if app.idNumber != filteredApps.last?.idNumber {
                                        Divider()
                                            .padding(.leading, 90)
                                    }
                                }
                            }
                        }
                    } else if !searchText.isEmpty {
                        AshteHomeEmptyView()
                            .padding(.top, 50)
                    }
                }
            }
            .background(Color(UIColor.systemBackground))
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
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
    
    private func handleAutoSign() {
        // 💡 ئەگەر لەسەر idevice بێت (1)، تەنها دەچێتە لایبری و واژووی ناکات
        if installationMethod == 1 {
            return
        }
        
        // 💡 ئەگەر لەسەر Server بێت (0)، پڕۆسەی واژووکردنەکە بەردەوام دەبێت
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

struct AshteHomeEmptyView: View {
    var body: some View {
        if #available(iOS 17, *) {
            ContentUnavailableView {
                Label(.localized("No Applications"), systemImage: "magnifyingglass")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.blue)
            } description: {
                Text(.localized("We couldn't find any apps matching your search."))
            }
        } else {
            VStack {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No Applications")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }
}

struct AshteHomeAppCell: View {
    let app: AshteHomeAppModel
    var onDownloadComplete: () -> Void
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var isDownloading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AsyncImage(url: app.fullImageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(UIColor.secondarySystemBackground)
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(app.version ?? "1.0") • \(app.category ?? "Apps")")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                ZStack {
                    if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                        ZStack {
                            Circle()
                                .trim(from: 0, to: downloadProgress)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 30, height: 30)
                                .animation(.smooth, value: downloadProgress)

                            Image(systemName: "stop.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 10, weight: .black))
                        }
                        .onTapGesture {
                            downloadManager.cancelDownload(currentDownload)
                        }
                    } else {
                        Button(action: { triggerDownload() }) {
                            Text("Get")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 72, height: 32)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
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

        let publisher = Publishers.CombineLatest(
            download.$progress,
            download.$unpackageProgress
        )

        cancellable = publisher.sink { _, _ in
            downloadProgress = download.overallProgress
        }
    }
}

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
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: app.fullImageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill).blur(radius: 40)
                    } placeholder: {
                        Color(UIColor.secondarySystemBackground)
                    }
                    .frame(height: 220)
                    .clipped()
                    .overlay(Color.black.opacity(0.2))
                    
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        Spacer()
                        
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 50)
                }
                
                HStack(alignment: .top, spacing: 16) {
                    AsyncImage(url: app.fullImageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(UIColor.secondarySystemBackground)
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .offset(y: -30)
                    .padding(.bottom, -30)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Text(app.category ?? "Apps")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                
                HStack(spacing: 12) {
                    ZStack {
                        if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                            ZStack {
                                Capsule().fill(Color.blue.opacity(0.1))
                                HStack {
                                    Text("Downloading...")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.blue)
                                    Spacer()
                                    ProgressView()
                                }
                                .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Button(action: { triggerDownload() }) {
                                Text(isDownloading ? "..." : "Get")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    
                    Button(action: {}) {
                        Text("Share")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                HStack(spacing: 10) {
                    AshtePillView(icon: "tag", text: app.version ?? "1.0")
                    AshtePillView(icon: "shippingbox", text: app.size ?? "Unknown")
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                
                Divider()
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Description")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text(app.descriptionText ?? "No description available for \(app.name). Enjoy the app!")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Divider()
                    .padding(.vertical, 20)
                    .padding(.horizontal, 20)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("Information")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.bottom, 5)
                    
                    AshteDetailInfoRow(title: "Developer", value: app.developerName ?? "AshteMobile")
                    AshteDetailInfoRow(title: "Identifier", value: app.bundleIdentifier ?? "com.ashtemobile")
                    AshteDetailInfoRow(title: "Category", value: app.category ?? "Applications")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
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

        let publisher = Publishers.CombineLatest(
            download.$progress,
            download.$unpackageProgress
        )

        cancellable = publisher.sink { _, _ in
            downloadProgress = download.overallProgress
        }
    }
}

struct AshtePillView: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.blue)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct AshteDetailInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.secondary)
        }
        Divider()
    }
}
