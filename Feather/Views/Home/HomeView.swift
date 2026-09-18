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
import Combine // پێویستە بۆ چاودێریکردنی داونلۆد

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
    
    private var filteredApps: [AshteHomeAppModel] {
        appsList.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NBNavigationView(.localized("Discover")) {
            List {
                if !filteredApps.isEmpty {
                    Section {
                        Button(action: {
                            if let url = URL(string: "https://t.me/ashtemobile") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AshteMobile Channel")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text("Join our Telegram for updates")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                    
                    NBSection(
                        .localized("Applications"),
                        secondary: filteredApps.count.description
                    ) {
                        ForEach(filteredApps) { app in
                            NavigationLink(destination: AshteHomeAppDetailView(app: app)) {
                                AshteHomeAppCell(app: app)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .platform())
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
        if #available(iOS 17, *) {
            ContentUnavailableView {
                Label(.localized("No Applications"), systemImage: "square.grid.3x3.slash.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.purple)
            } description: {
                Text(.localized("Check your connection or refresh to load apps."))
            }
        } else {
            Text("No Applications")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - App Cell View (ئێرە نوێکراوەتەوە بۆ چاودێریکردنی ئۆتۆماتیکی)
struct AshteHomeAppCell: View {
    let app: AshteHomeAppModel
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var hasTriggeredInstall = false

    var body: some View {
        HStack(spacing: 15) {
            AsyncImage(url: app.fullImageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(UIColor.secondarySystemBackground)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(app.version ?? "1.0") • \(app.developerName ?? "AshteMobile")")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // پیشاندانی دوگمەی Get یان هێڵکاری داونلۆد
            ZStack {
                if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                    ZStack {
                        Circle()
                            .trim(from: 0, to: downloadProgress)
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 31, height: 31)
                            .animation(.smooth, value: downloadProgress)

                        Image(systemName: downloadProgress >= 0.75 ? "signature" : "square.fill")
                            .foregroundStyle(.purple)
                            .font(.footnote).bold()
                    }
                    .onTapGesture {
                        if downloadProgress <= 0.75 {
                            downloadManager.cancelDownload(currentDownload)
                        }
                    }
                } else {
                    Button(action: { triggerDownload() }) {
                        Text("Get")
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
        .onChange(of: downloadManager.downloads.description) { _ in
            setupObserver()
        }
    }
    
    private func triggerDownload() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        hasTriggeredInstall = false // سفرکردنەوەی باری ئینستاڵ
        
        if let dlURL = app.downloadURLObject {
            _ = DownloadManager.shared.startDownload(from: dlURL, id: app.stringID)
        }
    }
    
    // ئێرە کرۆکی جادوەکەیە: چاودێری هێڵکاری دەکات و نۆتیفیکەیشن دەنێرێت
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
            
            // کاتێک داونلۆد و واژووکردن تەواو دەبێت (دەگاتە 1.0) بە ئۆتۆماتیکی فەرمانی ئینستاڵ دەنێرێت
            if downloadProgress >= 1.0 && !hasTriggeredInstall {
                hasTriggeredInstall = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: Notification.Name("AshteMobile.installApp"), object: nil)
                }
            }
        }
    }
}

// MARK: - App Detail View
struct AshteHomeAppDetailView: View {
    let app: AshteHomeAppModel
    @Environment(\.presentationMode) var presentationMode
    
    // هەمان لۆژیکی ئۆتۆماتیکی بۆ ناو پەڕەی وردەکاریش
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var downloadProgress: Double = 0
    @State private var cancellable: AnyCancellable?
    @State private var hasTriggeredInstall = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: app.fullImageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill).blur(radius: 30)
                    } placeholder: {
                        Color.purple.opacity(0.6)
                    }
                    .frame(height: 240)
                    .clipped()
                    
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)
                }
                
                HStack(alignment: .center, spacing: 16) {
                    AsyncImage(url: app.fullImageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(UIColor.secondarySystemBackground)
                    }
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .offset(y: -25)
                    .padding(.bottom, -25)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(app.developerName ?? "AshteMobile")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                ZStack {
                    if let currentDownload = downloadManager.getDownload(by: app.stringID) {
                        ZStack {
                            Capsule().fill(Color.purple.opacity(0.12))
                            HStack {
                                Text("Signing...")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.purple)
                                Spacer()
                                ProgressView()
                            }
                            .padding(.horizontal, 20)
                        }
                        .frame(width: 150, height: 38)
                    } else {
                        Button(action: { triggerDownload() }) {
                            Text("Get")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 110, height: 38)
                                .background(Color.purple)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 126)
                .padding(.top, 5)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("Information")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.top, 20)
                    
                    AshteHomeInfoRow(title: "Version", value: app.version ?? "1.0")
                    AshteHomeInfoRow(title: "Category", value: app.category ?? "Apps")
                    AshteHomeInfoRow(title: "Developer", value: app.developerName ?? "AshteMobile")
                    AshteHomeInfoRow(title: "Identifier", value: app.bundleIdentifier ?? "com.ashtemobile")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .edgesIgnoringSafeArea(.top)
        .navigationBarHidden(true)
        .onAppear(perform: setupObserver)
        .onDisappear { cancellable?.cancel() }
        .onChange(of: downloadManager.downloads.description) { _ in
            setupObserver()
        }
    }
    
    private func triggerDownload() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        hasTriggeredInstall = false
        
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
            
            if downloadProgress >= 1.0 && !hasTriggeredInstall {
                hasTriggeredInstall = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: Notification.Name("AshteMobile.installApp"), object: nil)
                }
            }
        }
    }
}

struct AshteHomeInfoRow: View {
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
