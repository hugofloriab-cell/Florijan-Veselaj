//  VuesSondes.swift
//
//  L'écran des sondes, repris de la section 2 de la fiche web : une carte par
//  enceinte, température, bilan du jour, courbe, pile et autonomie restante.

import SwiftUI
import Charts
import UserNotifications

// MARK: - Écran principal

struct VueSondes: View {
    @StateObject private var gestionnaire = GestionnaireSondes()
    @State private var afficheAppairage = false

    private var alertes: [String] {
        gestionnaire.sondes.compactMap { s in
            if s.horsSeuils(s.derniereCenti) {
                return "\(s.nom) à \(Format.degres(s.derniereCenti)) — hors norme."
            }
            if let b = s.bilan(du: Date()), b.ecarts > 0 {
                return "\(s.nom) — \(b.ecarts) écart(s) aujourd'hui (mini \(Format.degres(b.minCenti)), maxi \(Format.degres(b.maxCenti)))."
            }
            return nil
        }
    }

    private var avertissements: [String] {
        var out: [String] = []
        for s in gestionnaire.sondes {
            if let p = s.pilePourcent, p < 20 {
                let reste = s.joursRestants.map { " — environ \(Format.duree(jours: $0)) restants" } ?? ""
                out.append("Pile de « \(s.nom) » à \(p) %\(reste). Relever la sonde avant de changer les piles.")
            }
            if let i = s.intervalleMinutes, i < 5 {
                out.append("« \(s.nom) » relève toutes les \(i) minute(s) — réglage de banc d'essai.")
            }
            if s.drapeaux.contains(.capteurHS) {
                out.append("Capteur de « \(s.nom) » illisible — vérifier le câble.")
            }
            if s.drapeaux.contains(.tamponPlein) {
                out.append("Mémoire de « \(s.nom) » saturée : des relevés anciens ont été perdus.")
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                if !alertes.isEmpty {
                    Section {
                        Bandeau(titre: "Températures non conformes", lignes: alertes,
                                couleur: .red, symbole: "exclamationmark.triangle.fill")
                    }
                }
                if !avertissements.isEmpty {
                    Section {
                        Bandeau(titre: "À prévoir", lignes: avertissements,
                                couleur: .orange, symbole: "info.circle.fill")
                    }
                }

                if gestionnaire.sondes.isEmpty {
                    ContentUnavailableView(
                        "Aucune sonde appairée",
                        systemImage: "sensor",
                        description: Text("Passez l'aimant sur le boîtier d'une sonde, puis touchez « Appairer »."))
                } else {
                    ForEach(gestionnaire.sondes) { sonde in
                        NavigationLink {
                            VueDetailSonde(sonde: sonde, gestionnaire: gestionnaire)
                        } label: {
                            CarteSonde(sonde: sonde)
                        }
                    }
                }
            }
            .navigationTitle("Sondes")
            .refreshable { gestionnaire.releverTout() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Appairer") { afficheAppairage = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        gestionnaire.releverTout()
                    } label: {
                        if gestionnaire.enRecherche { ProgressView() }
                        else { Label("Relever", systemImage: "arrow.clockwise") }
                    }
                    .disabled(gestionnaire.enRecherche)
                }
            }
            .sheet(isPresented: $afficheAppairage) {
                VueAppairage(gestionnaire: gestionnaire)
            }
            .overlay(alignment: .bottom) {
                if let m = gestionnaire.message {
                    Text(m)
                        .font(.footnote)
                        .padding(10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .task {
                // L'autorisation est demandée une fois ; sans elle, aucune alerte
                // ne peut remonter quand l'application est fermée.
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            }
        }
    }
}

// MARK: - Carte d'une sonde

private struct CarteSonde: View {
    let sonde: Sonde

    private var enAlerte: Bool {
        sonde.horsSeuils(sonde.derniereCenti) || (sonde.bilan(du: Date())?.ecarts ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sonde.nom).font(.headline)
                    Text(sonde.type.libelle)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Pastille(sonde: sonde, enAlerte: enAlerte)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.degres(sonde.derniereCenti))
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .foregroundStyle(enAlerte ? .red : .primary)
                if let s = sonde.derniereSynchro {
                    Text(s, format: .relative(presentation: .named))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if let b = sonde.bilan(du: Date()) {
                HStack(spacing: 14) {
                    Etiquette("mini", Format.degres(b.minCenti))
                    Etiquette("maxi", Format.degres(b.maxCenti))
                    Etiquette("moy.", Format.degres(b.moyenneCenti))
                    if b.ecarts > 0 {
                        Text("\(b.ecarts) écart(s)")
                            .font(.caption.monospaced().bold())
                            .foregroundStyle(.red)
                    }
                }
            }

            Courbe(sonde: sonde).frame(height: 46)

            if let p = sonde.pilePourcent {
                JaugePile(sonde: sonde, pourcent: p)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct Etiquette: View {
    let titre: String, valeur: String
    init(_ t: String, _ v: String) { titre = t; valeur = v }
    var body: some View {
        HStack(spacing: 4) {
            Text(titre).foregroundStyle(.secondary)
            Text(valeur).bold()
        }
        .font(.caption.monospaced())
    }
}

private struct Pastille: View {
    let sonde: Sonde
    let enAlerte: Bool

    var body: some View {
        let (texte, couleur): (String, Color) =
            enAlerte                              ? ("ÉCART T°", .red)
          : sonde.estMuette                       ? ("HORS LIGNE", .gray)
          : (sonde.pilePourcent ?? 100) < 20      ? ("PILE FAIBLE", .orange)
          : ("CONFORME", .green)

        Text(texte)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(couleur.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(couleur)
    }
}

private struct JaugePile: View {
    let sonde: Sonde
    let pourcent: UInt8

    var body: some View {
        HStack(spacing: 8) {
            Text("Pile").foregroundStyle(.secondary)
            ProgressView(value: Double(pourcent), total: 100)
                .tint(pourcent < 10 ? .red : (pourcent < 20 ? .orange : .green))
            Text("\(pourcent) %")
            if let mv = sonde.millivolts {
                Text(String(format: "%.2f V", Double(mv) / 1000)
                        .replacingOccurrences(of: ".", with: ","))
                    .foregroundStyle(.secondary)
            }
            Text(sonde.joursRestants.map { "~" + Format.duree(jours: $0) } ?? "estimation en cours")
                .foregroundStyle(.secondary)
        }
        .font(.caption.monospaced())
    }
}

// MARK: - Courbe des 24 heures

private struct Courbe: View {
    let sonde: Sonde

    var body: some View {
        let depuis = Date().addingTimeInterval(-24 * 3600)
        let points = sonde.releves.filter {
            $0.date >= depuis && $0.centi != Protocole.temperatureInvalide
        }
        if points.count < 2 {
            Text("Courbe affichée après quelques relevés")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Chart {
                // Les deux bornes de conformité : on voit d'un coup d'œil ce
                // qui en sort, et de combien.
                RuleMark(y: .value("mini", Double(sonde.bornes.min) / 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                RuleMark(y: .value("maxi", Double(sonde.bornes.max) / 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                ForEach(points) { r in
                    LineMark(x: .value("Heure", r.date), y: .value("°C", r.celsius))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        }
    }
}

// MARK: - Appairage

private struct VueAppairage: View {
    @ObservedObject var gestionnaire: GestionnaireSondes
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Passez l'aimant sur le boîtier de la sonde : elle ouvre une fenêtre de deux minutes et apparaît ci-dessous.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Sondes détectées") {
                    if gestionnaire.detectees.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Recherche…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(gestionnaire.detectees.sorted { $0.nom < $1.nom }) { d in
                        Button {
                            gestionnaire.appairer(d)
                            fermer()
                        } label: {
                            Label(d.nom, systemImage: "sensor.tag.radiowaves.forward")
                        }
                    }
                }
            }
            .navigationTitle("Appairer une sonde")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { gestionnaire.arreterRecherche(); fermer() }
                }
            }
            .onAppear { gestionnaire.chercher(pendant: 30) }
            .onDisappear { gestionnaire.arreterRecherche() }
        }
    }
}

// MARK: - Détail

struct VueDetailSonde: View {
    let sonde: Sonde
    @ObservedObject var gestionnaire: GestionnaireSondes

    @State private var nom = ""
    @State private var type: TypeEnceinte = .positif
    @State private var ecart = ""

    private var courante: Sonde {
        gestionnaire.sondes.first(where: { $0.id == sonde.id }) ?? sonde
    }

    var body: some View {
        Form {
            Section("Emplacement") {
                TextField("Chambre froide", text: $nom)
                Picker("Type d'enceinte", selection: $type) {
                    ForEach(TypeEnceinte.allCases) { t in Text(t.libelle).tag(t) }
                }
                Button("Enregistrer") {
                    gestionnaire.renommer(courante, nom: nom, type: type)
                }
                .disabled(nom.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Étalonnage") {
                LabeledContent("Correction appliquée",
                               value: Format.degres(courante.offsetCenti))
                if let d = courante.etalonneeLe {
                    LabeledContent("Dernier étalonnage", value: d.formatted(date: .abbreviated, time: .omitted))
                }
                TextField("Écart lu en bain d'eau glacée, ex. -0,4", text: $ecart)
                    .keyboardType(.numbersAndPunctuation)
                Button("Envoyer la correction") {
                    if let v = Double(ecart.replacingOccurrences(of: ",", with: ".")),
                       (-20...20).contains(v) {
                        gestionnaire.etalonner(courante, ecartCelsius: v)
                        ecart = ""
                    }
                }
                .disabled(ecart.isEmpty)
            }

            Section("Relevés") {
                LabeledContent("Enregistrés", value: "\(courante.releves.count)")
                LabeledContent("Cadence",
                               value: courante.intervalleMinutes.map { "\($0) min" } ?? "—")
                if let s = courante.derniereSynchro {
                    LabeledContent("Dernière synchro",
                                   value: s.formatted(date: .abbreviated, time: .shortened))
                }
                if let e = courante.derniereErreur {
                    Text(e).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                Button("Retirer cette sonde", role: .destructive) {
                    gestionnaire.retirer(courante)
                }
            } footer: {
                Text("Les relevés déjà rapatriés seront effacés de l'appareil. Exportez-les d'abord si besoin.")
            }
        }
        .navigationTitle(courante.nom)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nom = courante.nom; type = courante.type }
    }
}

// MARK: - Bandeau d'alerte

private struct Bandeau: View {
    let titre: String
    let lignes: [String]
    let couleur: Color
    let symbole: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbole).foregroundStyle(couleur)
            VStack(alignment: .leading, spacing: 6) {
                Text(titre).font(.subheadline.bold()).foregroundStyle(couleur)
                ForEach(lignes, id: \.self) { l in
                    Text("• " + l).font(.footnote)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(couleur.opacity(0.08))
    }
}
