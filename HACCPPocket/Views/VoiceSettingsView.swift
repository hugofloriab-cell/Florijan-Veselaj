//
//  VoiceSettingsView.swift
//  HACCPPocket
//
//  Choix de la voix qui commente les modes opératoires.
//
//  ─────────────────────────────────────────────────────────────────────────
//  POURQUOI CET ÉCRAN EXISTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Parce qu'une voix choisie dans les réglages d'iOS peut très bien ne pas
//  se faire entendre ici, pour des raisons que rien n'expliquait :
//
//  • une voix de Siri est réservée au système, aucune application tierce ne
//    peut la lire ;
//  • une voix « améliorée » ou « premium » dont le téléchargement n'est pas
//    terminé n'existe pas encore pour l'application ;
//  • et, jusqu'à cette version, l'application imposait elle-même une voix,
//    ce qui écrasait purement et simplement le choix fait dans les réglages.
//
//  Le troisième point est corrigé dans `SpeechNarrator` : la voix du système
//  est désormais respectée par défaut. Restent les deux premiers, qui ne
//  dépendent pas de nous. Cet écran les rend visibles : il liste les voix
//  réellement utilisables, dit laquelle parle, et permet de la forcer.
//
//  On y règle aussi la vitesse. Le curseur « Débit vocal » des réglages
//  système ne s'applique qu'à VoiceOver et à « Lire l'écran » : une
//  application ne peut ni le lire ni le suivre.
//

import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

struct VoiceSettingsView: View {

    /// Le narrateur est fourni par l'écran appelant : c'est lui qui parle,
    /// donc c'est sur lui qu'on règle, et l'essai s'entend avec la voix qui
    /// servira réellement.
    let narrator: SpeechNarrator

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Phrase d'essai.
    ///
    /// Volontairement tirée d'un vrai mode opératoire, avec ses chiffres et
    /// son unité : c'est là qu'une voix médiocre s'entend, pas sur « bonjour ».
    private static let sampleText =
        "Relevez la température à cœur du produit. Elle doit descendre sous trois degrés en moins de deux heures."

    var body: some View {
        NavigationStack {
            Form {
                qualityAdviceSection
                currentVoiceSection
                voiceChoiceSection
                rateSection
                downloadSection
            }
            .navigationTitle("Voix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .onDisappear { narrator.stop() }
        }
    }

    // MARK: - Ce qu'on peut attendre d'une voix de synthèse

    /// Dit franchement où est le plafond, et le seul levier qui existe.
    ///
    /// Reproche entendu, et fondé : « elles sont toutes les mêmes, des
    /// génériques, aucune émotion ». C'est exact pour les voix d'origine.
    /// Une application ne peut pas les rendre expressives : elle peut
    /// seulement dire que les voix téléchargeables sont d'une autre facture,
    /// et que le reste demanderait une comédienne en studio.
    @ViewBuilder
    private var qualityAdviceSection: some View {
        if !narrator.hasNaturalFrenchVoice {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Seules les voix d'origine sont installées", systemImage: "exclamationmark.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brand)

                    Text("Ce sont elles qui sonnent mécaniques et interchangeables. Les voix « Améliorée » et « Premium » sont d'une tout autre qualité, gratuites, et se téléchargent depuis les Réglages — voir plus bas.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Voix employée

    private var currentVoiceSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: narrator.isSpeaking ? "waveform.circle.fill" : "speaker.wave.2.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.brand)

                VStack(alignment: .leading, spacing: 2) {
                    Text(narrator.voiceName)
                        .font(.headline)
                    Text(sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                Task { await narrator.speak(Self.sampleText) }
            } label: {
                Label("Écouter un exemple", systemImage: "play.circle")
            }
        } header: {
            Text("Voix utilisée")
        } footer: {
            Text("C'est cette voix qui commente les modes opératoires.")
        }
    }

    /// D'où vient la voix employée : des réglages, ou d'un choix fait ici.
    private var sourceDescription: String {
        if narrator.selectedVoiceIdentifier != nil {
            return "Choisie dans l'application"
        }
        return "Voix par défaut du système"
    }

    // MARK: - Choix de la voix

    private var voiceChoiceSection: some View {
        Section {
            Button {
                narrator.selectedVoiceIdentifier = nil
            } label: {
                voiceRow(
                    title: "Voix du système",
                    detail: "Celle des Réglages → Accessibilité → Lire et énoncer",
                    isSelected: narrator.selectedVoiceIdentifier == nil
                )
            }

            ForEach(narrator.availableFrenchVoices, id: \.identifier) { voice in
                Button {
                    narrator.selectedVoiceIdentifier = voice.identifier
                } label: {
                    voiceRow(
                        title: voice.name,
                        detail: "\(SpeechNarrator.qualityLabel(for: voice)) · \(voice.language)",
                        isSelected: narrator.selectedVoiceIdentifier == voice.identifier
                    )
                }
            }
        } header: {
            Text("Voix disponibles")
        } footer: {
            Text(voiceChoiceFooter)
        }
    }

    private var voiceChoiceFooter: String {
        if narrator.availableFrenchVoices.isEmpty {
            return "Aucune voix française n'est installée sur cet appareil. Ajoutez-en une depuis les Réglages, plus bas."
        }
        if !narrator.hasNaturalFrenchVoice {
            return "Seule la voix française d'origine est installée. Une voix « Améliorée » ou « Premium » se télécharge gratuitement et sonne nettement plus naturelle."
        }
        return "Les voix de Siri n'apparaissent pas ici : iOS les réserve au système, aucune application ne peut les utiliser. Si vous en avez choisi une dans les Réglages, sélectionnez ci-dessus la voix que l'application doit employer à la place."
    }

    private func voiceRow(title: String, detail: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Vitesse

    private var rateSection: some View {
        Section {
            Slider(
                value: Binding(
                    get: { Double(narrator.rate) },
                    set: { narrator.rate = Float($0) }
                ),
                in: Double(SpeechNarrator.minimumRate)...Double(SpeechNarrator.maximumRate)
            ) {
                Text("Vitesse")
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
            }

            Button {
                narrator.rate = SpeechNarrator.defaultRate
            } label: {
                Label("Vitesse conseillée", systemImage: "arrow.counterclockwise")
            }
            .disabled(narrator.rate == SpeechNarrator.defaultRate)
        } header: {
            Text("Vitesse de lecture")
        } footer: {
            Text("Le réglage « Débit vocal » d'iOS ne concerne que VoiceOver : il ne s'applique pas ici. La vitesse conseillée est volontairement lente, une consigne s'entend une seule fois et souvent dans le bruit.\n\nUne voix de synthèse reste une voix de synthèse : elle articule juste, elle ne joue pas. Une intonation réellement vivante demanderait des enregistrements en studio, à refaire à chaque correction de texte.")
        }
    }

    // MARK: - Télécharger une voix

    private var downloadSection: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Ouvrir les Réglages", systemImage: "gear")
            }
        } header: {
            Text("Installer une autre voix")
        } footer: {
            Text("Les voix appartiennent au système, l'application ne peut pas les télécharger. Le bouton ouvre les Réglages sur la fiche de l'application — iOS n'autorise pas de lien direct vers un panneau d'accessibilité. De là, revenez à la racine puis Accessibilité → Lire et énoncer → Voix → Français, et touchez la flèche de téléchargement d'une voix « Améliorée » ou « Premium ». Elle apparaîtra ensuite dans la liste ci-dessus.")
        }
    }
}
