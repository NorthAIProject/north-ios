import Foundation
import NorthAPI

extension Error {
    /// The server's own sentence for a refused file or draft ("This PDF is
    /// password-protected…") rather than the generic summary.
    var importMessage: String {
        if let api = self as? APIError, case .fieldValidation(let message, let fields) = api {
            return fields["file"] ?? fields["plan"] ?? message
        }
        return localizedDescription
    }
}
