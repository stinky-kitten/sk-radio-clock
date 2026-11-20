//
//  WiFiConfigurationValidation.swift
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-28.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

enum WiFiConfigurationValidation {
  static func hasNTPServer(_ server: StaticString?) -> Bool {
    guard let server, server.hasPointerRepresentation else { return false }
    return server.withUTF8Buffer { bytes in
      !bytes.isEmpty && bytes.allSatisfy { (33...126).contains($0) }
    }
  }

  // Never include the supplied values in an error or diagnostic.
  static func error<SSID: Collection, Password: Collection>(ssid: SSID, password: Password) -> StaticString?
  where SSID.Element == UInt8, Password.Element == UInt8 {
    let placeholderSSID: StaticString = "YOUR_WIFI_SSID"
    let placeholderPassword: StaticString = "YOUR_WIFI_PASSWORD"
    let isPlaceholderSSID = placeholderSSID.withUTF8Buffer { ssid.elementsEqual($0) }
    let isPlaceholderPassword = placeholderPassword.withUTF8Buffer { password.elementsEqual($0) }
    if isPlaceholderSSID || isPlaceholderPassword {
      return "replace the placeholders in Config/WiFiCredentials.swift"
    }
    if ssid.isEmpty || ssid.count > 32 || ssid.contains(0) {
      return "SSID must contain 1...32 UTF-8 bytes without NUL"
    }
    if password.count < 8 || password.count > 63
      || !password.allSatisfy({ $0 >= 32 && $0 <= 126 })
    {
      return "WPA2 passphrase must contain 8...63 printable ASCII bytes"
    }
    return nil
  }
}
