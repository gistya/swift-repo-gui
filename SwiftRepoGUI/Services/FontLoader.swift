import CoreText
import Foundation

enum FontLoader {
    static func registerFonts() {
        register("12-segment-display", ext: "ttf")
    }

    private static func register(_ name: String, ext: String) {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: ext)
        else {
            fatalError("Missing font \(name)")
        }

        var error: Unmanaged<CFError>?

        if !CTFontManagerRegisterFontsForURL(url as CFURL,
                                            .process,
                                            &error) {

            if let error {
                print(error.takeRetainedValue())
            }
        }
    }
}
