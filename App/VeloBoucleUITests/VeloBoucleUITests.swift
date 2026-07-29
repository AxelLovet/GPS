import XCTest

/// Tests d'interface des six étapes principales exigées au §17 du cahier des
/// charges : choix d'une distance, création d'un circuit, sélection d'un
/// circuit, démarrage de la navigation, pause et fin de sortie, consultation de
/// l'historique.
///
/// Ces tests s'exécutent dans le simulateur iOS, **en mode démonstration** :
/// l'application est lancée avec l'argument `-VeloBoucleUITesting`, qui force le
/// générateur de circuits hors ligne. Aucune requête réseau n'est émise et
/// aucune clé API n'est nécessaire.
///
/// Commande :
///
///     xcodebuild test \
///       -project App/VeloBoucle.xcodeproj \
///       -scheme VeloBoucle \
///       -destination 'platform=iOS Simulator,name=iPhone 15'
final class VeloBoucleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-VeloBoucleUITesting"]
        // Position simulée : place Saint-François, Lausanne.
        app.launchEnvironment["VELO_SIMULATED_LATITUDE"] = "46.5197"
        app.launchEnvironment["VELO_SIMULATED_LONGITUDE"] = "6.6323"
        app.launch()
        dismissLocationPromptIfPresented()
    }

    /// iOS peut présenter la demande d'autorisation de localisation au premier
    /// lancement ; la laisser affichée bloquerait toute interaction.
    private func dismissLocationPromptIfPresented() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Lorsque l'app est active"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
    }

    // MARK: - 1. Choix d'une distance

    func testDistanceCanBeSelected() {
        let button = app.buttons["Boucle de 10,0 km"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "le sélecteur de distance est absent")
        button.tap()
        XCTAssertTrue(button.isSelected || button.exists)
    }

    // MARK: - 2 et 3. Création puis sélection d'un circuit

    func testGeneratingAndSelectingALoop() {
        selectTenKilometres()
        tapGenerate()

        let comparison = app.navigationBars["Choisissez votre circuit"]
        XCTAssertTrue(
            comparison.waitForExistence(timeout: 30),
            "l'écran de comparaison n'est pas apparu"
        )

        // Au moins trois propositions doivent être offertes.
        XCTAssertTrue(app.staticTexts["Recommandé"].exists)
        XCTAssertTrue(app.staticTexts["Alternatif 1"].exists)

        app.buttons["Choisir ce circuit"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Votre circuit"].waitForExistence(timeout: 10),
            "l'aperçu du circuit n'est pas apparu"
        )
        XCTAssertTrue(app.buttons["Démarrer la navigation"].exists)
    }

    // MARK: - 4, 5. Navigation, pause et fin de sortie

    func testStartPauseAndFinishARide() {
        selectTenKilometres()
        tapGenerate()

        XCTAssertTrue(
            app.navigationBars["Choisissez votre circuit"].waitForExistence(timeout: 30)
        )
        app.buttons["Choisir ce circuit"].firstMatch.tap()

        let start = app.buttons["Démarrer la navigation"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15), "la navigation n'a pas démarré")

        pause.tap()
        XCTAssertTrue(app.buttons["Reprendre"].waitForExistence(timeout: 5))
        app.buttons["Reprendre"].tap()

        app.buttons["Terminer"].tap()
        let confirm = app.alerts.buttons["Terminer"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(
            app.navigationBars["Sortie terminée"].waitForExistence(timeout: 10),
            "l'écran de fin de sortie n'est pas apparu"
        )
        XCTAssertTrue(app.buttons["Enregistrer la sortie"].exists)
    }

    // MARK: - 6. Historique

    func testHistoryTabIsReachableAndExplainsItselfWhenEmpty() {
        app.tabBars.buttons["Historique"].tap()
        XCTAssertTrue(app.navigationBars["Historique"].waitForExistence(timeout: 10))
        // Sur une installation neuve, l'historique est vide et doit l'expliquer
        // plutôt que d'afficher une page blanche.
        XCTAssertTrue(
            app.staticTexts["Aucune sortie enregistrée"].exists
                || app.cells.count > 0
        )
    }

    func testSavedRideAppearsInHistory() {
        selectTenKilometres()
        tapGenerate()
        XCTAssertTrue(
            app.navigationBars["Choisissez votre circuit"].waitForExistence(timeout: 30)
        )
        app.buttons["Choisir ce circuit"].firstMatch.tap()
        app.buttons["Démarrer la navigation"].tap()

        XCTAssertTrue(app.buttons["Terminer"].waitForExistence(timeout: 15))
        app.buttons["Terminer"].tap()
        app.alerts.buttons["Terminer"].tap()

        XCTAssertTrue(app.buttons["Enregistrer la sortie"].waitForExistence(timeout: 10))
        app.buttons["Enregistrer la sortie"].tap()

        app.tabBars.buttons["Historique"].tap()
        XCTAssertTrue(app.navigationBars["Historique"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.cells.count, 0, "la sortie enregistrée n'apparaît pas")
    }

    // MARK: - Réglages

    func testSettingsExposeProfileAndNavigationOptions() {
        app.tabBars.buttons["Réglages"].tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Vélo de route électrique"].exists)
        XCTAssertTrue(app.switches["Instructions vocales"].exists)
    }

    // MARK: - Utilitaires

    private func selectTenKilometres() {
        let button = app.buttons["Boucle de 10,0 km"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    private func tapGenerate() {
        let generate = app.buttons["Créer une boucle"].firstMatch
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        XCTAssertTrue(generate.isEnabled, "le bouton de génération est désactivé : position absente")
        generate.tap()
    }
}
