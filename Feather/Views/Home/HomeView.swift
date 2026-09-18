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
    let news: [AshteHomeNewsModel]?
}

struct AshteHomeNewsModel: Codable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let title: String
    let caption: String?
    let url: String
    let imageURL: String?
    let tintColor: String?

    var customImageURL: URL? {
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("telegram") {
            return URL(string: "https://ashtemobile.site/img/t.png")
        } else if lowerTitle.contains("instagram") {
            return URL(string: "https://ashtemobile.site/img/i.png")
        }
        guard let img = imageURL else { return nil }
        return URL(string: img)
    }
}

struct AshteAppVersionInfo: Codable {
    let version: String?
    let date: String?
    let minOSVersion: String?
}

// 💡 مۆدێلەکە گەڕێنرایەوە بۆ دۆخە ڕەسەنەکەی خۆی بۆ ئەوەی هیچ ئێرۆرێک لە فایلەکانی تر دروست نەکات
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
    
    // زیادکراوەکان تەنها وەک هەڵبژاردە (Optional) زیادکراون
    let icon: String?
    let type: String?
    let subtitle: String?
    let localizedDescription: String?
    let versions: [AshteAppVersionInfo]?
    
    var stringID: String {
        return "\(idNumber)"
    }
    
    var downloadURLObject: URL? {
        return URL(string: download_url)
    }
    
    enum CodingKeys: String, CodingKey {
        case idNumber = "id"
        case name, version, category, iconURL, size, developerName, bundleIdentifier, download_url
        case icon, type, subtitle, localizedDescription, versions
    }

    var fullImageURL: URL? {
        if let img = iconURL, !img.isEmpty {
            if img.hasPrefix("http") { return URL(string: img) }
            return URL(string: "https://ashtemobile.site/\(img)")
        } else if let img = icon, !img.isEmpty {
            if img.hasPrefix("http") { return URL(string: img) }
            return URL(string: "https://ashtemobile.site/\(img)")
        }
        return nil
    }
    
    var safeCategory: String {
        return category ?? type ?? "Apps"
    }
}

// MARK: - Main View
struct HomeView: View {
    @State private var appsList: [AshteHomeAppModel] = []
    @State private var newsList: [AshteHomeNewsModel] = []
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
        NBNavigationView(.localized("Home")) {
            List {
                // MARK: - Banner Slider
                if !newsList.isEmpty && searchText.isEmpty {
                    Section {
                        TabView {
                            ForEach(newsList) { news in
                                Button(action: {
                                    if let url = URL(string: news.url) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    AsyncImage(url: news.customImageURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            Color(UIColor.secondarySystemBackground)
                                            ProgressView()
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
                
                // MARK: - Applications List
                if !filteredApps.isEmpty {
                    NBSection(
                        .localized("Recently Updated"),
                        secondary: filteredApps.count.description
                    ) {
                        ForEach(filteredApps) { app in
                            NavigationLink(destination: AshteHomeAppDetailView(app: app, onDownloadComplete: handleAutoSign)) {
                                AshteHomeAppCell(app: app, onDownloadComplete: handleAutoSign)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .platform())
            .overlay {
                if filteredApps.isEmpty && appsList.isEmpty {
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
    
    private func handleAutoSign() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let request = NSFetchRequest<Imported>(entityName: "Imported")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
            
            guard let importedApps = try? Storage.shared.context.fetch(request),
                  let importedApp = importedApps.first else {
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
                self.newsList = decoded.news ?? []
            }
        } catch {
            print("Error loading apps: \(error)")
        }
    }
}

// MARK: - Empty State View
struct AshteHomeEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.slash.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            Text("No Applications")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - App Cell View
struct AshteHomeAppCell: View {
    let app: AshteHomeAppModel
    var onDownloadComplete: () -> Void
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var isDownloading = false

    var body: some View {
        HStack(spacing: 15) {
            AsyncImage(url: app.fullImageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(UIColor.secondarySystemBackground)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(app.version ?? "1.0") • \(app.subtitle ?? app.developerName ?? "AshteMobile")")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(app.safeCategory.capitalized)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            ZStack {
                if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                    ZStack {
                        Circle()
                            .stroke(Color.blue.opacity(0.2), lineWidth: 2.5)
                            .frame(width: 31, height: 31)
                        
                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 31, height: 31)
                            .animation(.spring(), value: downloadProgress)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.blue)
                    }
                    .onTapGesture {
                        downloadManager.cancelDownload(currentDownload)
                    }
                } else {
                    Button(action: { triggerDownload() }) {
                        Text("Get")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 68, height: 30)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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

// MARK: - App Detail View
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
                // Top Blurred Background Header
                ZStack(alignment: .bottom) {
                    GeometryReader { proxy in
                        let minY = proxy.frame(in: .global).minY
                        let height = max(200 + minY, 200)
                        
                        AsyncImage(url: app.fullImageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill).blur(radius: 30)
                        } placeholder: {
                            Color(UIColor.secondarySystemBackground)
                        }
                        .frame(width: proxy.size.width, height: height)
                        .offset(y: minY > 0 ? -minY : 0)
                        .clipped()
                        .overlay(Color.black.opacity(0.2))
                    }
                    .frame(height: 200)
                    
                    VStack {
                        HStack {
                            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 50)
                        Spacer()
                    }
                }
                
                // App Info Profile
                VStack(spacing: 20) {
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
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            
                            Text(app.safeCategory.capitalized)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.yellow)
                                }
                                Text("(1.2K)")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .padding(.left, 4)
                            }
                            .padding(.top, 2)
                            
                            HStack(spacing: 12) {
                                if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                                    Button(action: { downloadManager.cancelDownload(currentDownload) }) {
                                        HStack {
                                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        }
                                        .frame(width: 70, height: 30)
                                        .background(Color.blue)
                                        .clipShape(Capsule())
                                    }
                                } else {
                                    Button(action: { triggerDownload() }) {
                                        Text("Get")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 70, height: 30)
                                            .background(Color.blue)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Version & Size Pills
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundColor(.secondary)
                            Text(app.version ?? "1.0")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        HStack {
                            Image(systemName: "shippingbox")
                                .foregroundColor(.secondary)
                            Text(app.size ?? "Unknown")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                    
                    // Screenshots Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Screenshots")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                AsyncImage(url: app.fullImageURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color(UIColor.secondarySystemBackground)
                                }
                                .frame(width: 260, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 10)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.system(size: 20, weight: .bold))
                        
                        Text(app.localizedDescription ?? app.subtitle ?? "No description provided.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Divider().padding(.horizontal, 20).padding(.top, 10)
                    
                    // Information Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Information")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.bottom, 4)
                        
                        AshteAppInfoRow(title: "Developer", value: app.developerName ?? "AshteMobile")
                        if let updatedDate = app.versions?.first?.date {
                            let formattedDate = String(updatedDate.prefix(10))
                            AshteAppInfoRow(title: "Updated", value: formattedDate)
                        } else {
                            AshteAppInfoRow(title: "Updated", value: "Unknown")
                        }
                        AshteAppInfoRow(title: "Identifier", value: app.bundleIdentifier ?? "Unknown")
                        AshteAppInfoRow(title: "Minimum iOS", value: app.versions?.first?.minOSVersion ?? "14.0")
                        AshteAppInfoRow(title: "Languages", value: "EN, AR, KU", hideDivider: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
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

// Helper Row for Information Section
struct AshteAppInfoRow: View {
    let title: String
    let value: String
    var hideDivider: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !hideDivider {
                Divider()
            }
        }
    }
}
