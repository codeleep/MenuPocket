// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuPocket",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MenuPocket", targets: ["MenuPocket"])],
    targets: [.executableTarget(name: "MenuPocket")],
    swiftLanguageModes: [.v5]
)
