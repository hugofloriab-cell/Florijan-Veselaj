//
//  VoiceSettingsView.swift
//  HACCPPocket
//
//  La voix qui commente les modes opératoires.
//
//  ─────────────────────────────────────────────────────────────────────────
//  UNE VOIX, PAS UNE LISTE
//  ─────────────────────────────────────────────────────────────────────────
//
//  Première version de cet écran : une liste de toutes les voix françaises
//  installées, à charge pour l'utilisateur de trancher. Mauvais réflexe.
//  Quand toutes les options se valent — et les voix d'origine se valent,
//  elles sont également mécaniques —, proposer un choix ne rend service à
//  personne. Ça donne du travail sans donner de résultat.
//
//  Cet écran affiche donc **une** voix : celle que l'application retient
//  d'elle-même, la meilleure installée. Le reste est replié.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUI AMÉLIORE VRAIMENT LA VOIX, ET CE QUI N'Y CHANGE RIEN
//  ─────────────────────────────────────────────────────────────────────────
//
//  Le seul levier réel est la qualité de la voix installée. Les voix livrées
//  d'origine sont dites « compactes » : elles tiennent dans quelques
//  mégaoctets et s'entendent comme telles. Les voix « Améliorée » et
//  « Premium » sont d'une autre facture, gratuites, et pèsent plusieurs
//  centaines de mégaoctets — c'est pour ça qu'elles ne sont pas
//  préinstallées.
//
//  Une application ne peut pas les télécharger : les voix appartiennent au
//  système. Quand aucune n'est installée, cet écran ne propose donc pas un
//  choix, il donne la marche à suivre. C'est la seule chose utile à faire.
//
//  Ni la vitesse, ni la hauteur, ni le découpage en phrases ne rattrapent
//  une voix compacte. Ils rendent une bonne voix plus lisible, rien de plus.
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

    /// Les autres voix ne s'affichent que si on les demande.
    @State private var showsOtherVoices = false

    /// Phrase d'essai.
    ///
    /// Volontairement tirée d'un vrai mode opératoire, avec ses chiffres et
    /// son unité : c'est là qu'une voix médiocre s'entend, pas sur « bonjour ».
    private static let sampleText =
        "Relevez la température à cœur du produit. Elle doit descendre sous +3 °C en moins de deux heures."

    var body: some View {
        NavigationStack {
            Form {
                currentVoiceSection
                upgradeSection
                otherVoicesSection
                rateSection
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

    // MARK: - La voix employée

    private var currentVoiceSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: narrator.isSpeaking ? "waveform.circle.fill" : "speaker.wave.2.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.brand)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 3) {
                    Text(narrator.voiceName)
                        .font(.headline)

                    HStack(spacing: 6) {
                        if let quality = narrator.voiceQualityLabel {
                            Text(quality)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.brand)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.brand.opacity(0.14), in: Capsule())
                        }

                        Text(sourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)

            Button {
                Task { await narrator.speak(Self.sampleText) }
            } label: {
                Label("Écouter un exemple", systemImage: "play.circle")
            }
        } header: {
            Text("Voix utilisée")
        } footer: {
            Text("C'est elle qui commente les modes opératoires.")
        }
    }

    /// D'où vient la voix employée.
    private var sourceDescription: String {
        if narrator.usesSystemVoice { return "Voix par défaut d'iOS" }
        if narrator.usesRecommendedVoice { return "Choisie automatiquement" }
        return "Choisie par vous"
    }

    // MARK: - Installer une voix qui tienne la route

    /// Quand rien de mieux qu'une voix compacte n'est installé, cet écran ne
    /// propose pas un choix : il donne la marche à suivre.
    @ViewBuilder
    private var upgradeSection: some View {
        if !narrator.hasNaturalFrenchVoice {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Seule la voix d'origine est installée", systemImage: "exclamationmark.bubble.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brand)

                    Text("C'est elle qui sonne mécanique. Une voix « Premium » se télécharge gratuitement et change complètement le rendu :")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        instruction(1, "Réglages → Accessibilité")
                        instruction(2, "Lire et énoncer → Voix → Français")
                        instruction(3, "Touchez une voix marquée « Premium »")
                        instruction(4, "Touchez la flèche de téléchargement ⤓")
                        instruction(5, "Revenez ici : elle sera prise automatiquement")
                    }
                    .padding(.top, 2)

                    Text("Comptez quelques centaines de mégaoctets et deux à trois minutes en Wi-Fi. C'est pour ce poids qu'Apple ne les préinstalle pas.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Ouvrir les Réglages", systemImage: "gear")
                }
            } header: {
                Text("Obtenir une voix naturelle")
            } footer: {
                Text("Le bouton ouvre la fiche de l'application : iOS n'autorise pas de lien direct vers un panneau d'accessibilité. Revenez à la racine des Réglages depuis là.")
            }
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.brand, in: Circle())

            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Les autres voix, sur demande

    private var otherVoicesSection: some View {
        Section {
            DisclosureGroup("Choisir une autre voix", isExpanded: $showsOtherVoices) {
                voiceRow(
                    title: "Voix recommandée",
                    detail: recommendedDetail,
                    isSelected: narrator.usesRecommendedVoice
                ) {
                    narrator.selectedVoiceIdentifier = nil
                }

                voiceRow(
                    title: "Voix du système",
                    detail: "Celle des Réglages → Accessibilité → Lire et énoncer",
                    isSelected: narrator.usesSystemVoice
                ) {
                    narrator.selectedVoiceIdentifier = SpeechNarrator.systemVoiceIdentifier
                }

                ForEach(narrator.availableFrenchVoices, id: \.identifier) { voice in
                    voiceRow(
                        title: voice.name,
                        detail: "\(SpeechNarrator.qualityLabel(for: voice)) · \(voice.language)",
                        isSelected: narrator.selectedVoiceIdentifier == voice.identifier
                    ) {
                        narrator.selectedVoiceIdentifier = voice.identifier
                    }
                }
            }
        } footer: {
            Text("Les voix de Siri n'apparaissent pas ici : iOS les réserve au système, aucune application ne peut les employer.")
        }
    }

    private var recommendedDetail: String {
        guard let voice = narrator.recommendedVoice else {
            return "Aucune voix française installée"
        }
        return "\(voice.name) · \(SpeechNarrator.qualityLabel(for: voice))"
    }

    private func voiceRow(
        title: String,
        detail: String,
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
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
            Text("Le réglage « Débit vocal » d'iOS ne concerne que VoiceOver : il ne s'applique pas ici. La vitesse conseillée est volontairement lente, une consigne s'entend une seule fois et souvent dans le bruit.\n\nElle ne rattrape pas une voix compacte : une synthèse articule juste, elle ne joue pas. Une intonation réellement vivante demanderait des enregistrements en studio, à refaire à chaque correction de texte.")
        }
    }
}
