import SwiftUI

/// Palette et constantes visuelles.
///
/// Deux exigences guident ces choix : l'écran doit rester lisible en plein
/// soleil sur un guidon, et les couleurs doivent tenir en mode clair comme en
/// mode sombre. Toutes les teintes sont définies par rapport aux couleurs
/// système, qui s'adaptent automatiquement au thème et aux réglages
/// d'accessibilité (contraste augmenté, inversion intelligente).
extension Color {
    /// Couleur d'accentuation de l'application.
    static let veloAccent = Color.accentColor

    /// Tracé du circuit sélectionné.
    static let veloRoute = Color.blue
    /// Tracé des circuits alternatifs, en retrait.
    static let veloRouteAlternate = Color.gray
    /// Trace réellement parcourue pendant la sortie.
    static let veloTrack = Color.orange
    /// Départ et arrivée.
    static let veloStart = Color.green
    static let veloFinish = Color.red
    /// Avertissement non bloquant.
    static let veloWarning = Color.orange
}

/// Dimensions partagées, pensées pour une utilisation à vélo.
enum VeloMetrics {
    /// Hauteur minimale d'un bouton principal.
    ///
    /// Bien au-dessus des 44 pt recommandés par Apple : on vise une cible
    /// atteignable avec des gants, sans regarder l'écran plus d'une seconde.
    static let primaryButtonHeight: CGFloat = 60
    /// Taille de la grande flèche de manœuvre.
    static let maneuverArrowSize: CGFloat = 64
    static let cardCornerRadius: CGFloat = 16
    static let mapCornerRadius: CGFloat = 12
}

/// Bouton principal : grand, contrasté, impossible à manquer.
struct PrimaryButtonStyle: ButtonStyle {
    var isProminent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: VeloMetrics.primaryButtonHeight)
            .foregroundStyle(isProminent ? Color.white : Color.accentColor)
            .background(
                RoundedRectangle(cornerRadius: VeloMetrics.cardCornerRadius, style: .continuous)
                    .fill(isProminent ? Color.accentColor : Color.accentColor.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Carte à fond neutre, utilisée pour les blocs d'information.
    func veloCard() -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: VeloMetrics.cardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}
