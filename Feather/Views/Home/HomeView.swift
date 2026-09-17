//
//  HomeView.swift
//  AshteMobile
//
//  Created for AshteMobile
//

import SwiftUI
import NimbleViews
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

struct HomeCustomBanner: Identifiable {
    let id = UUID()
    let title: String
    let image: String
    let link: String
}

// MARK: - Main Home View
struct HomeView: View {
    @State private var apps: [HomeApp] = []
    @State private var _searchText: String = ""
    
    private let banners = [
        HomeCustomBanner(title: "Telegram", image: "https://ashtemobile.site/img/t.png", link: "https://t.me/ashtemobile"),
        HomeCustomBanner(title: "Instagram", image: "https://ashtemobile.site/img/i.png", link: "https://www.instagram.com/ashtemobile")
    ]
    
    private var filteredApps: [HomeApp] {
        if _searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(_searchText) }
    }
    
    var body: some View {
        NBNavigationView(.localized("Discover")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    if _searchText.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                ForEach(banners) { banner in
                                    BannerCardView(banner: banner)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 15) {
                        if _searchText.isEmpty {
                            Text("\(apps.count) Apps")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                        
                        if filteredApps.isEmpty && !_searchText.isEmpty {
                            Text("هیچ بەرنامەیەک نەدۆزرایەوە بۆ '\(_searchText)'")
                                .foregroundColor(.gray)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredApps) { app in
                                    NavigationLink(destination: AppDetailView(app: app)) {
                                        AppRowView(app: app)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                        .padding(.leading, 85)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.bottom, 40)
            }
            .searchable(text: $_searchText)
            .refreshable {
                await loadApps()
            }
            .onAppear {
                Task { await loadApps() }
            }
        }
    }
    
    private func loadApps() async {
        guard let url = URL(string: "https://ashtemobile.site/Ashtemobile.json") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(AshteSourceResponse.self, from: data)
            DispatchQueue.main.async {
                self.apps = decoded.apps
            }
        } catch {
            print("Error loading apps: \(error)")
        }
    }
    
    // MARK: - Nested Views
    
    struct BannerCardView: View {
        let banner: HomeCustomBanner
        
        var body: some View {
            Button(action: {
                if let url = URL(string: banner.link) {
                    UIApplication.shared.open(url)
                }
            }) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: banner.image)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.purple.opacity(0.8)
                    }
                    
                    LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                    
                    Text(banner.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(15)
                }
                .frame(width: 280, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    
    struct AppRowView: View {
        let app: HomeApp
        
        var body: some View {
            HStack(spacing: 15) {
                AsyncImage(url: app.fullImageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(UIColor.secondarySystemBackground)
                }
                .frame(width: 65, height: 65)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(app.version ?? "1.0") • Awesome App")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    installApp(app)
                }) {
                    Text("Get")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 70, height: 32)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(Color(UIColor.systemPurple))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        
        private func installApp(_ app: HomeApp) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            let urlString = app.download_url
            let finalURLString: String
            
            if urlString.hasSuffix(".plist") && !urlString.hasPrefix("itms-services") {
                let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
                finalURLString = "itms-services://?action=download-manifest&url=\(encodedURL)"
            } else {
                finalURLString = urlString
            }
            
            if let url = URL(string: finalURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    struct AppDetailView: View {
        let app: HomeApp
        @Environment(\.presentationMode) var presentationMode
        
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        AsyncImage(url: app.fullImageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill).blur(radius: 40)
                        } placeholder: {
                            Color.purple.opacity(0.6)
                        }
                        .frame(height: 250)
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
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                        .offset(y: -30)
                        .padding(.bottom, -30)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(app.name)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Awesome App")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Button(action: { installApp(app) }) {
                        Text("Get")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color(UIColor.systemPurple))
                            .frame(width: 100, height: 35)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 136)
                    .padding(.top, 5)
                    
                    HStack {
                        Image(systemName: "tag")
                        Text(app.version ?? "1.0")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.systemGray6))
                    .clipShape(Capsule())
                    .padding(.horizontal, 20)
                    .padding(.top, 25)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Description")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("Downloaded from AshteMobile Source.")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 25)
                    
                    Divider().padding(.vertical, 15).padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Information")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .padding(.bottom, 5)
                        
                        InfoRow(title: "Source", value: "Ashtemobile")
                        InfoRow(title: "Developer", value: app.developerName ?? "AshteMobile")
                        InfoRow(title: "Category", value: app.category ?? "Games")
                        InfoRow(title: "Version", value: app.version ?? "1.0")
                        InfoRow(title: "Identifier", value: app.bundleIdentifier ?? "com.ashtemobile")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .edgesIgnoringSafeArea(.top)
            .navigationBarHidden(true)
        }
        
        private func installApp(_ app: HomeApp) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            let urlString = app.download_url
            let finalURLString: String
            
            if urlString.hasSuffix(".plist") && !urlString.hasPrefix("itms-services") {
                let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
                finalURLString = "itms-services://?action=download-manifest&url=\(encodedURL)"
            } else {
                finalURLString = urlString
            }
            
            if let url = URL(string: finalURLString) {
                UIApplication.shared.open(url)
            }
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
}
