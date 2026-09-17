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

// MARK: - Models
struct AshteSourceResponse: Codable {
    let name: String?
    let apps: [HomeApp]
}

struct HomeApp: Codable, Identifiable {
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

// MARK: - View
struct HomeView: View {
    @State private var _apps: [HomeApp] = []
    @State private var _searchText = ""
    
    private var _filteredApps: [HomeApp] {
        _apps.filter { _searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(_searchText) }
    }
    
    var body: some View {
        NBNavigationView(.localized("Discover")) {
            List {
                if !_filteredApps.isEmpty {
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
                        secondary: _filteredApps.count.description
                    ) {
                        ForEach(_filteredApps) { app in
                            NavigationLink(destination: AppDetailView(app: app)) {
                                HomeAppCellView(app: app)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $_searchText, placement: .platform())
            .overlay {
                if _filteredApps.isEmpty {
                    _emptyStateView()
                }
            }
            .refreshable {
                await _loadApps()
            }
        }
        .task {
            await _loadApps()
        }
    }
    
    private func _loadApps() async {
        guard let url = URL(string: "https://ashtemobile.site/Ashtemobile.json") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(AshteSourceResponse.self, from: data)
            DispatchQueue.main.async {
                self._apps = decoded.apps
            }
        } catch {
            print("Error loading apps: \(error)")
        }
    }
}

extension HomeView {
    @ViewBuilder
    private func _emptyStateView() -> some View {
        if #available(iOS 17, *) {
            ContentUnavailableView {
                Label(.localized("No Applications"), systemImage: "square.grid.3x3.slash.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.purple)
            } description: {
                Text(.localized("Check your connection or refresh to load apps."))
            } actions: {
                Button(action: {
                    Task { await _loadApps() }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(.localized("Refresh"))
                    }
                    .fontWeight(.bold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Home App Cell View
struct HomeAppCellView: View {
    let app: HomeApp
    
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
            
            Button(action: {
                startDownload(app)
            }) {
                Text("Get")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(width: 68, height: 30)
                    .background(Color.purple.opacity(0.12))
                    .foregroundColor(.purple)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func startDownload(_ app: HomeApp) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        guard let downloadURL = URL(string: app.download_url) else { return }
        
        // ئێرە کێشەکە بوو کە ڕاستم کردەوە: idـم بۆ زیاد کردووە وەکو سۆرسەکان
        _ = DownloadManager.shared.startDownload(from: downloadURL, id: String(app.idNumber))
    }
}

// MARK: - App Detail View
struct AppDetailView: View {
    let app: HomeApp
    @Environment(\.presentationMode) var presentationMode
    
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
                
                Button(action: { startDownload(app) }) {
                    Text("Get")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 110, height: 38)
                        .background(Color.purple)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 126)
                .padding(.top, 5)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("Information")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.top, 20)
                    
                    InfoRow(title: "Version", value: app.version ?? "1.0")
                    InfoRow(title: "Category", value: app.category ?? "Apps")
                    InfoRow(title: "Developer", value: app.developerName ?? "AshteMobile")
                    InfoRow(title: "Identifier", value: app.bundleIdentifier ?? "com.ashtemobile")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .edgesIgnoringSafeArea(.top)
        .navigationBarHidden(true)
    }
    
    private func startDownload(_ app: HomeApp) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        guard let downloadURL = URL(string: app.download_url) else { return }
        
        // ئێرە کێشەکە بوو کە ڕاستم کردەوە: idـم بۆ زیاد کردووە وەکو سۆرسەکان
        _ = DownloadManager.shared.startDownload(from: downloadURL, id: String(app.idNumber))
    }
}

struct InfoRow: View {
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
