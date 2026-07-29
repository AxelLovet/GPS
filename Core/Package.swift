// swift-tools-version: 5.9
import PackageDescription

// VeloCore regroupe toute la logique de VéloBoucle qui ne dépend d'aucun
// framework Apple : modèles, géodésie, client de routage, génération de boucles,
// suivi de parcours, statistiques et GPX.
//
// Cette séparation permet de compiler et d'exécuter la suite de tests sur Linux,
// sans Xcode ni simulateur. L'application iOS (App/) ajoute par-dessus les
// couches SwiftUI, MapKit, CoreLocation, SwiftData et AVFoundation.
let package = Package(
    name: "VeloCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VeloCore", targets: ["VeloCore"])
    ],
    targets: [
        .target(
            name: "VeloCore",
            path: "Sources/VeloCore"
        ),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"],
            path: "Tests/VeloCoreTests"
        )
    ]
)
