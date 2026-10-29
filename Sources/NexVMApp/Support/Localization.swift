import Foundation

/// Looks a key up in the app's `.strings` tables (en, pt-BR, pt-PT). Falls back to the key.
func L(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

/// Formatted variant: the table value is a `String(format:)` template.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
