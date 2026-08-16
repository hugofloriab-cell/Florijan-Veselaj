// swift-tools-version: 5.9
import PackageDescription

// Spike n°1 de la Phase 1 : lecture de 4 stems synchronisés avec AVAudioEngine.
//
// Prototype jetable. Il n'a pas vocation à devenir le lecteur de production —
// son rôle est de produire des mesures sur iPhone physique avant qu'on
// construise l'éditeur autour d'hypothèses non vérifiées.

let package = Package(
    name: "StemPlayerSpike",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StemPlayerKit", targets: ["StemPlayerKit"])
    ],
    targets: [
        .target(name: "StemPlayerKit"),
        .testTarget(
            name: "StemPlayerKitTests",
            dependencies: ["StemPlayerKit"]
        ),
    ]
)
