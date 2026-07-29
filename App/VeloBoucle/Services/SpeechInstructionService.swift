import Foundation
import AVFoundation
import VeloCore

/// Annonce vocale des consignes de navigation.
protocol SpeechInstructionServicing: AnyObject, Sendable {
    /// Annonce un texte. Une annonce urgente interrompt celle en cours.
    func announce(_ text: String, priority: AnnouncementPriority)
    /// Interrompt toute annonce et libère la session audio.
    func stop()
}

/// Implémentation reposant sur `AVSpeechSynthesizer`.
///
/// Deux points méritent attention pour un usage à vélo :
///
/// - la session audio est configurée en `.duckOthers`, ce qui **baisse** la
///   musique en cours au lieu de la couper ; personne n'a envie que sa playlist
///   s'arrête à chaque virage ;
/// - la session n'est activée que le temps de l'annonce, puis désactivée, afin
///   de rendre la main aux autres applications et d'éviter de maintenir la
///   chaîne audio sous tension pendant toute la sortie.
@MainActor
final class SpeechInstructionService: NSObject, SpeechInstructionServicing {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "fr-FR")
    private var hasActiveSession = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    nonisolated func announce(_ text: String, priority: AnnouncementPriority) {
        Task { @MainActor in perform(text, priority: priority) }
    }

    private func perform(_ text: String, priority: AnnouncementPriority) {
        guard !text.isEmpty else { return }

        if priority == .urgent, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        } else if synthesizer.isSpeaking {
            // Une consigne normale ne bouscule pas celle en cours : deux voix
            // qui se chevauchent sont inintelligibles au bord d'une route.
            return
        }

        activateSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // Légèrement plus lent que la valeur par défaut : on écoute avec le
        // bruit du vent et de la circulation.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    nonisolated func stop() {
        Task { @MainActor in
            synthesizer.stopSpeaking(at: .immediate)
            deactivateSession()
        }
    }

    private func activateSessionIfNeeded() {
        guard !hasActiveSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true)
            hasActiveSession = true
        } catch {
            // L'échec de la session audio ne doit jamais interrompre la
            // navigation : les consignes restent affichées à l'écran.
            AppLog.navigation.notice("Session audio indisponible, annonces vocales muettes")
        }
    }

    private func deactivateSession() {
        guard hasActiveSession else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        hasActiveSession = false
    }
}

extension SpeechInstructionService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard !synthesizer.isSpeaking else { return }
            deactivateSession()
        }
    }
}

/// Double silencieux, utilisé quand les annonces vocales sont désactivées et
/// dans les tests.
final class SilentSpeechService: SpeechInstructionServicing {
    func announce(_ text: String, priority: AnnouncementPriority) {}
    func stop() {}
}
