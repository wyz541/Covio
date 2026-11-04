import Foundation

/// 文件命名前的本地内容类别。
///
/// 这是提取层自己的类别。接模型时再映射到 Covio core 的文件命名类别，
/// 这样文件读取不需要依赖旧共享模块的生成类型。
enum FileNamingContentKind: String, Sendable, Equatable {
    case text
    case pdf
    case image
    case code
    case mixed
    case unknown
}

enum FileNamingExtractionSource: String, Sendable, Hashable {
    case fileText
    case pdfText
    case pdfOCR
    case imageOCR
    case imagePixels
    case fileMetadata
    case contentSniff
}

enum FileNamingExtractionQuality: String, Sendable, Equatable {
    case high
    case medium
    case low
}

enum FileNamingExtractionWarning: String, Sendable, Hashable {
    case truncatedInput
    case partialDocument
    case lowOCR
    case mixedContent
}

enum FileNamingExtractionError: String, Error, Sendable, Equatable {
    case notRegularFile
    case symbolicLinkUnsupported
    case unreadableInput
    case fileTooLarge
    case emptyContent
    case pdfUnreadable
    case imageUnreadable
    case unsupportedType
}

extension FileNamingExtractionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notRegularFile:
            "The input is not a regular file."
        case .symbolicLinkUnsupported:
            "Symbolic links are not supported."
        case .unreadableInput:
            "The input cannot be read."
        case .fileTooLarge:
            "The input exceeds the supported size."
        case .emptyContent:
            "The input has no usable content."
        case .pdfUnreadable:
            "The PDF cannot be parsed."
        case .imageUnreadable:
            "The image cannot be decoded."
        case .unsupportedType:
            "The input has no supported content signal."
        }
    }
}

struct FileNamingExtractionPolicy: Sendable, Equatable {
    var maxTextBytes = 256 * 1024
    var maxPDFBytes = 64 * 1024 * 1024
    var maxImageBytes = 32 * 1024 * 1024
    var maxPDFTextPages = 4
    var maxScannedPDFPages = 2
    var maxImageDimension = 1_600
    var minimumOCRCharacters = FileNamingExtraction.textOnlyOCRMinimumCharacters
}

struct FileNamingExtractedImage: Sendable, Equatable {
    let data: Data
    let mimeType: String
    let pixelWidth: Int
    let pixelHeight: Int
}

struct FileNamingExtraction: Sendable, Equatable {
    static let textOnlyOCRMinimumCharacters = 24

    let candidateId: String
    let fileURL: URL
    let kind: FileNamingContentKind
    let text: String
    let images: [FileNamingExtractedImage]
    let sources: Set<FileNamingExtractionSource>
    let quality: FileNamingExtractionQuality
    let warnings: Set<FileNamingExtractionWarning>

    var canUseOCRTextWithoutImage: Bool {
        text.count >= Self.textOnlyOCRMinimumCharacters
            && (sources.contains(.imageOCR) || sources.contains(.pdfOCR))
    }
}

struct FileNamingExtractionFailure: Sendable, Equatable {
    let candidateId: String
    let fileURL: URL
    let error: FileNamingExtractionError
    let detail: String
}

enum FileNamingExtractionResult: Sendable, Equatable {
    case success(FileNamingExtraction)
    case failure(FileNamingExtractionFailure)

    var extraction: FileNamingExtraction? {
        if case .success(let extraction) = self { return extraction }
        return nil
    }

    var failure: FileNamingExtractionFailure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}

struct FileNamingTypeObservation: Sendable, Equatable {
    let kind: FileNamingContentKind
    let evidence: Set<String>
}

extension String {
    func collapsedFileNamingWhitespace() -> String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
