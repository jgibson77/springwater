// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpringwaterSyntax",
    products: [
        .library(name: "SpringwaterSyntax", targets: ["SpringwaterSyntax"]),
        .library(name: "SpringwaterSchema", targets: ["SpringwaterSchema"]),
        .library(name: "SpringwaterRender", targets: ["SpringwaterRender"]),
        .library(name: "SpringwaterExport", targets: ["SpringwaterExport"])
    ],
    targets: [
        .target(name: "SpringwaterSyntax"),
        .testTarget(
            name: "SpringwaterSyntaxTests",
            dependencies: ["SpringwaterSyntax"]
        ),
        .target(
            name: "SpringwaterSchema",
            dependencies: ["SpringwaterSyntax"]
        ),
        .testTarget(
            name: "SpringwaterSchemaTests",
            dependencies: ["SpringwaterSchema"]
        ),
        .target(
            name: "SpringwaterRender",
            dependencies: ["SpringwaterSyntax"]
        ),
        .testTarget(
            name: "SpringwaterRenderTests",
            dependencies: ["SpringwaterRender"]
        ),
        .target(
            name: "SpringwaterExport",
            dependencies: ["SpringwaterSyntax"]
        ),
        .testTarget(
            name: "SpringwaterExportTests",
            dependencies: ["SpringwaterExport", "SpringwaterSchema"]
        )
    ]
)
