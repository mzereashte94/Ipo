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
    let news: [AshteHomeNewsModel]? // زیادکرا بۆ خوێندنەوەی هەواڵ/لینكەكان لە JSON
}

struct AshteHomeNewsModel: Codable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let title: String
    let caption: String
    let url: String
    let imageURL: String?
    let tintColor: String?

    var fullImageURL: URL? {
        guard let img = imageURL else { return nil }
        return URL(string: img)
    }
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
    @State private var newsList: [AshteHomeNewsModel] = [] // لیستی هەواڵەکان
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
            List {
                // MARK: - Dynamic News Banner (Carousel TabView)
                if !newsList.isEmpty && searchText.isEmpty {
                    Section {
                        TabView {
                            ForEach(newsList) { news in
                                Button(action: {
                                    if let url = URL(string: news.url) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 16) {
                                        AsyncImage(url: news.fullImageURL) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            ZStack {
                                                LinearGradient(colors: [Color(red: 138/255, green: 35/255, blue: 135/255), Color(red: 233/255, green: 64/255, blue: 87/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                Image(systemName: "link")
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(news.title)
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(.primary)
                                            
                                            Text(news.caption)
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.purple.opacity(0.8))
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never)) // شێوازی تاب/سلایدەر
                        .frame(height: 80)
                        .listRowInsets(EdgeInsets()) // پڕکردنەوەی تەواوی لاکان
                    }
                    .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                }
                
                // MARK: - Applications List
                if !filteredApps.isEmpty {
                    NBSection(
                        .localized("Applications"),
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
                // خوێندنەوەی بەشی News بۆ تابەکان
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
        if #available(iOS 17, *) {
            ContentUnavailableView {
                Label(.localized("No Applications"), systemImage: "square.grid.3x3.slash.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.purple)
            } description: {
                Text(.localized("Check your connection or refresh to load apps."))
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "square.grid.3x3.slash.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)
                Text("No Applications")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.secondary)
            }
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
                ZStack {
                    Color(UIColor.secondarySystemBackground)
                    ProgressView()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                            .stroke(Color.purple.opacity(0.2), lineWidth: 2.5)
                            .frame(width: 31, height: 31)
                        
                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 31, height: 31)
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
                            .frame(width: 68, height: 30)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
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
                ZStack(alignment: .bottom) {
                    GeometryReader { proxy in
                        let minY = proxy.frame(in: .global).minY
                        let height = max(280 + minY, 280)
                        
                        AsyncImage(url: app.fullImageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill).blur(radius: 40)
                        } placeholder: {
                            Color.purple.opacity(0.6)
                        }
                        .frame(width: proxy.size.width, height: height)
                        .offset(y: minY > 0 ? -minY : 0)
                        .clipped()
                    }
                    .frame(height: 280)
                    
                    LinearGradient(colors: [Color(UIColor.systemBackground).opacity(0), Color(UIColor.systemBackground)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 100)
                    
                    VStack {
                        HStack {
                            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .background(Color(UIColor.systemBackground).opacity(0.8))
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
                
                VStack(spacing: 16) {
                    AsyncImage(url: app.fullImageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(UIColor.secondarySystemBackground)
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .offset(y: -50)
                    .padding(.bottom, -50)
                    
                    VStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text(app.developerName ?? "AshteMobile")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    ZStack {
                        if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Downloading...")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 180, height: 42)
                            .background(Color.purple)
                            .clipShape(Capsule())
                            .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                            .onTapGesture {
                                downloadManager.cancelDownload(currentDownload)
                            }
                        } else {
                            Button(action: { triggerDownload() }) {
                                Text(isDownloading ? "..." : "GET APP")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 140, height: 42)
                                    .background(Color.purple)
                                    .clipShape(Capsule())
                                    .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Information")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.top, 30)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 0) {
                        AshteHomeInfoRow(title: "Version", value: app.version ?? "1.0", isLast: false)
                        AshteHomeInfoRow(title: "Category", value: app.category ?? "Apps", isLast: false)
                        AshteHomeInfoRow(title: "Developer", value: app.developerName ?? "AshteMobile", isLast: false)
                        AshteHomeInfoRow(title: "Identifier", value: app.bundleIdentifier ?? "com.ashtemobile", isLast: true)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .padding(.vertical, 12)
            
            if !isLast {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}
