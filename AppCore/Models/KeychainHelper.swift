import Foundation
import Security

// MARK: - Gestor Seguro de Tokens en iOS Keychain (Sin dependencias externas)
/// Seguridad y Cifrado:
/// - El token se almacena en el Keychain estándar del sistema operativo iOS
///   utilizando el nivel de protección `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
/// - IMPORTANTE: El token NO está almacenado en el Secure Enclave (el Secure Enclave está
///   reservado para claves asimétricas de 256 bits y biometría FaceID/TouchID, no para contraseñas simétricas).
/// - ADVERTENCIA DE RED: La comunicación con el servidor local del PC se realiza a través de HTTP sin TLS,
///   por lo que el token viaja en texto claro en la cabecera `Authorization: Bearer <token>` dentro de la red local.
public enum KeychainHelper {
    private static let service = "com.cryptowidget.portfolio"
    private static let tokenAccount = "pc_server_api_token"

    /// Guarda o elimina el token en el Keychain comprobando rigurosamente los códigos de retorno.
    @discardableResult
    public static func saveToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
        ]

        if trimmed.isEmpty {
            let deleteStatus = SecItemDelete(query as CFDictionary)
            return deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
        }

        guard let data = trimmed.data(using: .utf8) else { return false }

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            return addStatus == errSecSuccess
        default:
            // Preserve the existing Keychain item on unexpected errors.
            // Deleting it here could permanently lose a valid token if the retry also fails.
            return false
        }
    }

    /// Carga el token almacenado de forma segura desde el Keychain.
    public static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Elimina el token del Keychain.
    @discardableResult
    public static func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
