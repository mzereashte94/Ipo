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

struct DownloadButtonView: View {
	let app: ASRepository.App
	@ObservedObject private var downloadManager = DownloadManager.shared

	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?
    
    @State private var isDownloading = false
    @AppStorage("AshteMobile.installationMethod") private var installationMethod: Int = 0
    
    @State private var isCancelled = false

	var body: some View {
		ZStack {
			if let currentDownload = downloadManager.getDownload(by: app.currentUniqueId) {
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
                        isCancelled = true
						downloadManager.cancelDownload(currentDownload)
					}
				}
				.compatTransition()
			} else {
				Button {
					if let url = app.currentDownloadUrl {
                        isCancelled = false
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
                
                if !isCancelled {
                    handleDownloadCompletion()
                }
                
                isCancelled = false
            }
		}
		.animation(.easeInOut(duration: 0.3), value: downloadManager.getDownload(by: app.currentUniqueId) != nil)
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
        if installationMethod == 1 {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            return
        }
        
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
                        // ✅ لێرەدا وامان لێکردووە کە ڕاستەوخۆ بەبێ مەرج فایلەکە لە بەشی Imported بسڕێتەوە
                        Storage.shared.deleteApp(for: importedApp)
                        
                        NotificationCenter.default.post(name: Notification.Name("AshteMobile.installApp"), object: nil)
                    }
                }
            }
        }
    }
}
