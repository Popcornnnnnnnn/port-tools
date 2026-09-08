import SwiftUI

func portToolsLocale(_ preference: String) -> Locale {
    preference == "system" ? .current : Locale(identifier: preference)
}

func portToolsString(_ key: String) -> String {
    let preference = UserDefaults.standard.string(forKey: "language") ?? "system"
    guard preference != "system",
          let path = Bundle.main.path(forResource: preference, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return NSLocalizedString(key, comment: "") }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

struct LocalizedInventoryView: View {
    @ObservedObject var store: InventoryStore
    @AppStorage("language") private var language = "system"

    var body: some View {
        InventoryView(store: store)
            .environment(\.locale, portToolsLocale(language))
    }
}
