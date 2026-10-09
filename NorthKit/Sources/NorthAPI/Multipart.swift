import Foundation
import HTTPTypes
import OpenAPIRuntime

extension MultipartRawPart {
    /// A file part labelled with its own media type.
    ///
    /// The generated `.file` case labels every `format: binary` part
    /// `text/plain`, whatever it holds. Send this as the operation's
    /// `.undocumented` case instead: it still counts as the required part,
    /// since the client checks parts by name.
    public static func file(field: String = "file", filename: String, contentType: String, data: Data) -> MultipartRawPart {
        MultipartRawPart(
            name: field,
            filename: filename,
            headerFields: [.contentType: contentType],
            body: HTTPBody(data)
        )
    }
}
