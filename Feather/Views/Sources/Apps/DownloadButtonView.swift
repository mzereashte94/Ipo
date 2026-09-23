//
//  DownloadButtonView.swift
//  AshteMobile
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import Combine
import AltSourceKit
import NimbleViews
import CoreData 
import UIKit 

struct DownloadButtonView: View {
	let app: ASRepository.App
	@ObservedObject private var downloadManager = DownloadManager.shared

	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?
    
    @State private var isDownloading = false
    @State private var isSigning = false
    
	var body: some View {
		ZStack {
            if isSigning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(.localized("Signing..."))
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(uiColor: .quaternarySystemFill))
                .clipShape(Capsule())
            } else if let currentDownload = downloadManager.getDownload(by: app.currentUniqueId) {
				ZStack {
					Circle()
						.trim(from: 0, to: downloadProgress)
						.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.frame(width: 31, height: 31)
						.animation(.smooth, value: downloadProgress)

					Image(systemName: downloadProgress >= 0.75 ? "archivebox" : "square.fill")
						.foregroundStyle(.tint)
						.font(.footnote).bold()
				}
				.onTapGesture {
					if downloadProgress <= 0.75 {
						downloadManager.cancelDownload(currentDownload)
					}
				}
				.compatTransition()
			} else {
				Button {
					if let url = app.currentDownloadUrl {
						_ = downloadManager.startDownload(from: url, id: app.currentUniqueId)
					}
				} label: {
					Text(.localized("Get"))
						.lineLimit(0)
						.font(.headline.bold())
						.foregroundStyle(Color.accentColor)
						.padding(.horizontal, 24)
						.padding(.vertical, 6)
						.background(Color(uiColor: .quaternarySystemFill))
						.clipShape(Capsule())
				}
				.buttonStyle(.borderless)
				.compatTransition()
			}
		}
		.onAppear(perform: setupObserver)
		.onDisappear { cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in
			setupObserver()
            
            let isCurrentlyDownloading = downloadManager.getDownload(by: app.currentUniqueId) != nil
            if isCurrentlyDownloading {
                isDownloading = true
            } else if isDownloading && !isCurrentlyDownloading {
                isDownloading = false
                
                if downloadProgress >= 0.98 {
                    isSigning = true
                    handleDownloadCompletion()
                }
            }
		}
		.animation(.easeInOut(duration: 0.3), value: downloadManager.getDownload(by: app.currentUniqueId) != nil)
        .animation(.easeInOut(duration: 0.3), value: isSigning)
	}

	private func setupObserver() {
		cancellable?.cancel()
		guard let download = downloadManager.getDownload(by: app.currentUniqueId) else {
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
    
    private func handleDownloadCompletion() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // دەست دەکەین بە گەڕان بەدوای ئەپەکەدا
        pollForImportedApp(attempts: 0)
    }
    
    // 💡 ئەم فەنکشنە نوێیە بەردەوام دەگەڕێت تا ئەپەکە دەگاتە ناو Library
    private func pollForImportedApp(attempts: Int) {
        // ئەگەر دوای ١٥ چرکە نەیگواستەوە، واز دەهێنێت (واتە ٣٠ هەوڵ)
        guard attempts < 30 else {
            self.isSigning = false
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let request = NSFetchRequest<Imported>(entityName: "Imported")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
            request.fetchLimit = 1
            
            if let importedApps = try? Storage.shared.context.fetch(request),
               let newestApp = importedApps.first,
               let appDate = newestApp.date {
                
                // دڵنیا دەبینەوە کە ئەمە ئەپێکی تازەیە (لە ماوەی ٦٠ چرکەی ڕابردوودا هاتووە)
                if abs(appDate.timeIntervalSinceNow) < 60 {
                    self.startSigningProcess(for: newestApp)
                    return
                }
            }
            
            // ئەگەر نەیدۆزیەوە، دووبارە هەوڵ دەداتەوە
            self.pollForImportedApp(attempts: attempts + 1)
        }
    }
    
    private func startSigningProcess(for importedApp: Imported) {
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
                self.isSigning = false
                
                if error == nil {
                    if options.post_deleteAppAfterSigned {
                        Storage.shared.deleteApp(for: importedApp)
                    }
                    NotificationCenter.default.post(name: Notification.Name("AshteMobile.installApp"), object: nil)
                } else {
                    let errorGenerator = UINotificationFeedbackGenerator()
                    errorGenerator.notificationOccurred(.error)
                }
            }
        }
    }
}
