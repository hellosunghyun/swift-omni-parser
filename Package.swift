// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "OmniParser",
  platforms: [.iOS("27.0")],
  products: [
    .library(name: "OmniParser", targets: ["OmniParser"])
  ],
  dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3"),
    .package(
      url: "https://github.com/hellosunghyun/OpenDocument.core.git",
      revision: "b302cc85311490676986a2b731971473ad21efac"
    ),
    .package(url: "https://github.com/sboh1214/hwp-swift.git", exact: "0.19.0"),
    .package(url: "https://github.com/CoreOffice/OLEKit.git", exact: "0.3.1")
  ],
  targets: [
    .testTarget(
      name: "OmniParserTests",
      dependencies: ["OmniParser"],
      resources: [.copy("Fixtures")]
    ),
    .binaryTarget(
      name: "OfficeOxide",
      path: "ThirdParty/OfficeOxide/OfficeOxide.xcframework"
    ),
    .target(
      name: "OmniParser",
      dependencies: [
        .product(name: "SwiftSoup", package: "SwiftSoup"),
        .product(name: "OdrCore", package: "OpenDocument.core"),
        .product(name: "CoreHwp", package: "hwp-swift"),
        .product(name: "OLEKit", package: "OLEKit"),
        "OfficeOxide"
      ],
      linkerSettings: [.linkedLibrary("z"), .linkedLibrary("c++")]
    )
  ],
  swiftLanguageModes: [.v5]
)
