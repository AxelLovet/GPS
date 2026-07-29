import XCTest
@testable import VeloCore

/// Les consignes sont lues à voix haute et affichées en grand sur un guidon :
/// leur formulation fait partie de la sécurité du parcours, pas de l'esthétique.
final class InstructionPhrasingTests: XCTestCase {
    func testCoversEveryManeuverInFrench() {
        for maneuver in ManeuverType.allCases {
            let text = InstructionPhrasing.maneuverText(maneuver)
            XCTAssertFalse(text.isEmpty, "\(maneuver)")
            XCTAssertFalse(text.contains("turn"), "texte non traduit : \(text)")
        }
    }

    func testExamplesFromTheSpecification() {
        XCTAssertEqual(InstructionPhrasing.maneuverText(.right), "Tournez à droite")
        XCTAssertEqual(InstructionPhrasing.maneuverText(.left), "Tournez à gauche")
        XCTAssertEqual(InstructionPhrasing.maneuverText(.straight), "Continuez tout droit")
        XCTAssertEqual(InstructionPhrasing.maneuverText(.uTurn), "Faites demi-tour")
        XCTAssertEqual(InstructionPhrasing.maneuverText(.arrive), "Vous êtes arrivé")
        XCTAssertEqual(
            InstructionPhrasing.maneuverText(.roundaboutEnter, roundaboutExit: 2),
            "Au rond-point, prenez la 2e sortie"
        )
        XCTAssertEqual(
            InstructionPhrasing.maneuverText(.roundaboutEnter, roundaboutExit: 1),
            "Au rond-point, prenez la 1re sortie"
        )
    }

    func testDistanceIsPrefixedForUpcomingManeuvers() {
        let instruction = NavigationInstruction(
            maneuver: .right, roadName: "Route de Berne", distance: 800, duration: 120,
            startPointIndex: 0, endPointIndex: 10
        )
        let text = InstructionPhrasing.instructionText(instruction, distanceToManeuver: 100)
        XCTAssertEqual(text, "Dans 100 mètres, tournez à droite sur Route de Berne")
    }

    func testImminentManeuverDropsTheDistance() {
        let instruction = NavigationInstruction(
            maneuver: .left, roadName: "Chemin du Lac", distance: 300, duration: 60,
            startPointIndex: 0, endPointIndex: 5
        )
        XCTAssertEqual(
            InstructionPhrasing.instructionText(instruction, distanceToManeuver: 10),
            "Tournez à gauche sur Chemin du Lac"
        )
    }

    func testSpokenVariantOmitsRoadNameWhenVeryClose() {
        let instruction = NavigationInstruction(
            maneuver: .right, roadName: "Avenue de la Gare", distance: 300, duration: 60,
            startPointIndex: 0, endPointIndex: 5
        )
        XCTAssertEqual(
            InstructionPhrasing.spokenText(instruction, distanceToManeuver: 40),
            "Tournez à droite"
        )
        XCTAssertTrue(
            InstructionPhrasing.spokenText(instruction, distanceToManeuver: 200)
                .contains("Avenue de la Gare")
        )
    }

    func testSpokenDistancesAreRoundedToNaturalValues() {
        XCTAssertEqual(InstructionPhrasing.spokenDistance(12), "quelques mètres")
        XCTAssertEqual(InstructionPhrasing.spokenDistance(47), "50 mètres")
        XCTAssertEqual(InstructionPhrasing.spokenDistance(187), "200 mètres")
        XCTAssertEqual(InstructionPhrasing.spokenDistance(1_240), "1,2 kilomètres")
        XCTAssertEqual(InstructionPhrasing.spokenDistance(12_400), "12 kilomètres")
    }

    func testDisplayedValuesUseFrenchDecimalComma() {
        XCTAssertEqual(InstructionPhrasing.displayDistance(850), "850 m")
        XCTAssertEqual(InstructionPhrasing.displayDistance(12_400), "12,4 km")
        XCTAssertEqual(InstructionPhrasing.displaySpeed(metersPerSecond: 6.94), "25,0")
    }

    func testDisplayedDurations() {
        XCTAssertEqual(InstructionPhrasing.displayDuration(42 * 60), "42 min")
        XCTAssertEqual(InstructionPhrasing.displayDuration(3_600), "1 h")
        XCTAssertEqual(InstructionPhrasing.displayDuration(85 * 60), "1 h 25")
        XCTAssertEqual(InstructionPhrasing.displayDuration(-5), "—")
    }

    func testArrivalWordingDependsOnDistance() {
        let arrival = NavigationInstruction(
            maneuver: .arrive, roadName: nil, distance: 0, duration: 0,
            startPointIndex: 10, endPointIndex: 10
        )
        XCTAssertEqual(
            InstructionPhrasing.instructionText(arrival, distanceToManeuver: 10),
            "Vous êtes arrivé"
        )
        XCTAssertTrue(
            InstructionPhrasing.instructionText(arrival, distanceToManeuver: 500)
                .hasPrefix("Arrivée dans")
        )
    }

    func testEveryWarningHasAFrenchLabel() {
        for warning in RouteWarning.allCases {
            let text = InstructionPhrasing.warningText(warning)
            XCTAssertFalse(text.isEmpty, "\(warning)")
        }
    }

    func testEveryManeuverHasADistinctArrowSymbol() {
        // Une flèche erronée pendant une navigation à vélo est un problème de
        // sécurité : on vérifie que chaque manœuvre en a bien une.
        for maneuver in ManeuverType.allCases {
            XCTAssertFalse(maneuver.symbolName.isEmpty, "\(maneuver)")
        }
        XCTAssertNotEqual(
            ManeuverType.left.symbolName,
            ManeuverType.right.symbolName
        )
        XCTAssertNotEqual(
            ManeuverType.slightLeft.symbolName,
            ManeuverType.sharpLeft.symbolName
        )
    }

    func testStraightAheadDoesNotRequireAdvanceWarning() {
        XCTAssertFalse(ManeuverType.straight.requiresAdvanceWarning)
        XCTAssertFalse(ManeuverType.depart.requiresAdvanceWarning)
        XCTAssertTrue(ManeuverType.right.requiresAdvanceWarning)
        XCTAssertTrue(ManeuverType.roundaboutEnter.requiresAdvanceWarning)
    }
}
