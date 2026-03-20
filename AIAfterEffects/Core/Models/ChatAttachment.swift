//
//  ChatAttachment.swift
//  AIAfterEffects
//
//  Image attachment model for chat messages
//

import Foundation

struct ChatAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let mimeType: String
    let base64Data: String
    let sizeBytes: Int
    
    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        data: Data
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.base64Data = data.base64EncodedString()
        self.sizeBytes = data.count
    }
    
    var data: Data? {
        Data(base64Encoded: base64Data)
    }
    
    var dataURL: String {
        "data:\(mimeType);base64,\(base64Data)"
    }
}
