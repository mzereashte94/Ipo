//
//  HomeView.swift
//  AshteMobile
//
//  Created for AshteMobile
//  Merged with Friend's Safe Loading & Centralized Auto-Sign
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

// MARK: - Banner Model
struct SocialBanner: Identifiable {
    let id = UUID()
    let imageURL: URL?
    let destinationURL: URL?
}

struct HomeView: View {
    @Environment(\.openURL) var openURL
    @StateObject var viewModel = SourcesViewModel.shared
    
    @State private var _allApps: [(source: ASRepository, app: ASRepository.App)] = []
    @State private var _recentApps: [(source: ASRepository, app: ASRepository.App)] = []
    @State private var _selectedRoute: SourceAppRoute?
    @State private var isLoading = true
    @State private var _recentAppsCount = 0
    @State private var _currentStaticBannerIndex = 0
    
    private let staticBannerTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    @FetchRequest(
        entity: AltSource.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
        animation: .snappy
    ) private var _sources: FetchedResults<AltSource>
    
    // 💡 بنەرەکانی خۆت (تێلیگرام و ئینستاگرام) بە پارێزراوی لە سەرەوەن
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
                if isLoading && _recentApps.isEmpty {
                    ProgressView(.localized("Loading..."))
                } else {
                    List {
                        // MARK: - بەشی بنەرەکانی تێلیگرام و ئینستاگرام (دیزاینەکەی خۆت)
                        Section {
                            TabView(selection: $_currentStaticBannerIndex) {
                                ForEach(staticBanners.indices, id: \.self) { index in
                                    let banner = staticBanners[index]
                                    Button {
                                        if let url = banner.destinationURL {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        AsyncImage(url: banner.imageURL) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } else if phase.error != nil {
                                                Rectangle()
                                                    .fill(Color(uiColor: .secondarySystemBackground))
                                                    .overlay(Image(systemName: "photo.fill").foregroundColor(.secondary))
                                            } else {
                                                Rectangle()
                                                    .fill(Color(uiColor: .secondarySystemBackground))
                                                    .overlay(ProgressView())
                                            }
                                        }
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
                                        .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)
                                    .tag(index)
                                }
                            }
                            .frame(height: 230)
                            .tabViewStyle(.page(indexDisplayMode: .always))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .onReceive(staticBannerTimer) { _ in
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    _currentStaticBannerIndex = (_currentStaticBannerIndex + 1) % staticBanners.count
                                }
                            }
                        }

                        // MARK: - بەشی نوێترین ئەپەکان (بەهێزکراو بە کۆدی هاوڕێکەت)
                        if !_recentApps.isEmpty {
                            Section {
                                ForEach(_recentApps, id: \.app.currentUniqueId) { item in
                                    Button {
                                        _selectedRoute = SourceAppRoute(source: item.source, app: item.app)
                                    } label: {
                                        // 💡 لێرەدا ڕاستەوخۆ دەبەسترێتەوە بە DownloadButtonView و کێشەی واژووکردن نامێنێت
                                        SourceAppsCellView(source: item.source, app: item.app)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Text(.localized("Recently Updated"))
                                        .font(.title3.bold())
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(_recentAppsCount)")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .clipShape(Capsule())
                                }
                                .padding(.top, 5)
                                .textCase(nil)
                            }
                        } else if !isLoading {
                            Section {
                                if #available(iOS 17, *) {
                                    ContentUnavailableView {
                                        Label(.localized("No Applications"), systemImage: "tray.fill")
                                    } description: {
                                        Text(.localized("We couldn't find any apps currently."))
                                    }
                                } else {
                                    Text(.localized("No Applications"))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .compatNavigationDestination(item: $_selectedRoute) { route in
                SourceAppsDetailView(source: route.source, app: route.app)
            }
            .refreshable {
                do {
                    await viewModel.fetchSources(_sources, refresh: true)
                } catch {
                    print("Refreshing sources...")
                }
                _loadData()
            }
        }
        .task(id: Array(_sources)) {
            do {
                await viewModel.fetchSources(_sources)
            } catch {
                print("Loading sources...")
            }
            _loadData()
        }
    }

    // MARK: - هێنانی داتا بە سەلامەتی (دەرهێنراو لە کۆدی هاوڕێکەت)
    private func _loadData() {
        isLoading = true
        Task {
            let rawSources = _sources
            var allApps: [(source: ASRepository, app: ASRepository.App)] = []

            for rawSource in rawSources {
                guard let source = viewModel.sources[rawSource] else { continue }
                
                let sourceApps = source.apps
                for app in sourceApps {
                    allApps.append((source: source, app: app))
                }
            }

            // ڕیزکردن بەپێی کاتی زیادکردن (نوێترین لە سەرەوە)
            allApps.sort { firstItem, secondItem in
                let firstDate = firstItem.app.currentDate?.date ?? .distantPast
                let secondDate = secondItem.app.currentDate?.date ?? .distantPast
                return firstDate > secondDate
            }

            let topApps = Array(allApps.prefix(25))

            DispatchQueue.main.async {
                self._allApps = allApps
                self._recentApps = topApps
                self._recentAppsCount = topApps.count
                self.isLoading = false
            }
        }
    }
}

// MARK: - Supporting Types
struct SourceAppRoute: Identifiable, Hashable {
    let source: ASRepository
    let app: ASRepository.App
    let id: String = UUID().uuidString
}

// MARK: - Extension for Navigation
extension View {
    @ViewBuilder
    func compatNavigationDestination<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 16.0, *) {
            self.navigationDestination(isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            )) {
                if let selectedItem = item.wrappedValue {
                    destination(selectedItem)
                }
            }
        } else {
            self.background(
                NavigationLink(
                    isActive: Binding(
                        get: { item.wrappedValue != nil },
                        set: { if !$0 { item.wrappedValue = nil } }
                    )
                ) {
                    if let selectedItem = item.wrappedValue {
                        destination(selectedItem)
                    } else {
                        EmptyView()
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            )
        }
    }
}
