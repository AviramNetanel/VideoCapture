//
//  VideoStore.swift
//  videoCapture
//
//  Created by Aviram Netanel on 14/08/2025.
//

import Foundation

enum VideoStore {
    private static let folderName = "CapturedVideos"

    static var directoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      var dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Optional: exclude from iCloud backup
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? dir.setResourceValues(rv)
        }
        return dir
    }

    /// Unique destination for a new recording (e.g., VID_2025-08-14_12-30-55.mov)
    static func newRecordingURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "VID_\(df.string(from: Date())).mov"
        return directoryURL.appendingPathComponent(name)
    }

    /// List saved videos (newest first)
    static func listVideos() -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directoryURL,
                                                includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        let vids = urls.filter { ["mov","mp4","m4v"].contains($0.pathExtension.lowercased()) }
        return vids.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
