//
//  OnboardingView.swift
//  HACCPPocket
//
//  Première ouverture : de quoi l'application a besoin pour servir à quelque
//  chose dès le premier relevé.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CE QUE CET ÉCRAN N'EST PAS
//  ─────────────────────────────────────────────────────────────────────────
//
//  Ce n'est pas une page de connexion, et il ne faut pas le présenter comme
//  telle. Vérifier qu'une adresse électronique appartient bien à celui qui la
//  saisit suppose d'envoyer un message et d'en attendre la réponse, donc un
//  serveur, donc un abonnement mensuel. L'application a été construite sans
//  serveur, délibérément, et personne n'a envie de payer tous les mois pour
//  une case à cocher.
//
//  Ce que cet écran fait réellement : il recueille l'identité de
//  l'établissement, le nom du responsable et une adresse de contact, il les
//  écrit dans les réglages, et il s'efface. Tout y reste modifiable ensuite.
//
//  Pourquoi malgré tout le montrer d'emblée : sans nom d'établissement, les
//  documents produits — registre mensuel, fiche allergènes, affichage des
//  viandes — sortent anonymes et ne valent rien en contrôle. Les demander au
//  premier lancement évite de les découvrir manquants le jour de l'inspection.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(UserPreferences.self) private var preferences

    @Query private var establishments: [Establishment]

    @State private var step: Step = .welcome

    @State private var establishmentName = ""
    @State private var address = ""
    @State private var siret = ""
    @State private var managerName = ""
    @State private var contactEmail = ""
    @State private var operatorName = ""

    @FocusState private var focusedField: Field?

    private enum Step: Int, CaseIterable {
        case welcome
        case establishment
        case people
        case ready
    }

    private enum Field: Hashable {
        case name, address, siret, manager, email, operatorName
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome:       welcomeStep
                case .establishment: establishmentStep
                case .people:        peopleStep
                case .ready:         readyStep
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Retour") { goBack() }
                    }
                }
                // Passer reste possible à chaque étape : forcer une saisie au
                // premier lancement, c'est perdre l'utilisateur avant qu'il
                // ait vu à quoi sert l'application.
                if step != .ready {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Passer") { finish() }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: loadExisting)
    }

    // MARK: - Étapes

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            BrandLogo(size: 84)

            Text("Bienvenue dans \(BrandAssets.productName)")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Votre plan de maîtrise sanitaire, dans votre poche. Températures, nettoyage, réceptions, traçabilité : tout se note en quelques gestes, et le registre mensuel se produit tout seul.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                "Tout reste sur votre appareil. Aucune donnée n'est envoyée sur Internet.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            Spacer(minLength: 0)

            Button {
                advance()
            } label: {
                Text("Commencer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .readableWidth()
    }

    private var establishmentStep: some View {
        Form {
            Section {
                TextField("Nom de l'établissement", text: $establishmentName)
                    .focused($focusedField, equals: .name)
                    .textInputAutocapitalization(.words)

                TextField("Adresse", text: $address, axis: .vertical)
                    .focused($focusedField, equals: .address)
                    .lineLimit(1...3)

                TextField("SIRET (facultatif)", text: $siret)
                    .focused($focusedField, equals: .siret)
                    .keyboardType(.numberPad)
            } header: {
                Text("Votre entreprise")
            } footer: {
                Text("Ces informations apparaissent en tête de chaque document produit : registre mensuel, fiche allergènes, affichage de l'origine des viandes. Sans elles, ces documents sortent anonymes et ne valent rien en contrôle.")
            }

            Section {
                Button {
                    advance()
                } label: {
                    Text("Continuer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Votre entreprise")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusedField = .name }
    }

    private var peopleStep: some View {
        Form {
            Section {
                TextField("Nom du responsable", text: $managerName)
                    .focused($focusedField, equals: .manager)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Responsable")
            } footer: {
                Text("Le nom qui figure au bas des documents, en face de la signature.")
            }

            Section {
                TextField("Votre prénom", text: $operatorName)
                    .focused($focusedField, equals: .operatorName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Qui utilise l'application")
            } footer: {
                Text("Pré-rempli à chaque relevé. Vous ajouterez le reste de l'équipe dans les réglages : la traçabilité impose de savoir qui a fait quoi.")
            }

            Section {
                TextField("Adresse électronique", text: $contactEmail)
                    .focused($focusedField, equals: .email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Contact")
            } footer: {
                // Dit sans détour : c'est une adresse de contact, pas un
                // compte. Laisser croire à une connexion serait mentir.
                Text("Ce n'est pas un compte : l'application fonctionne sans connexion et sans serveur, et rien ne vous sera demandé pour l'ouvrir. Cette adresse sert à retrouver votre abonnement si vous changez de téléphone, et à nous joindre en cas de problème.")
            }

            Section {
                Button {
                    advance()
                } label: {
                    Text("Continuer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Vous")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusedField = .manager }
    }

    private var readyStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Tout est prêt")
                .font(.title2.weight(.bold))

            Text("L'application est livrée avec un plan de nettoyage, des enceintes et des rappels par défaut. Modifiez-les à votre installation : ce sont des points de départ, pas des obligations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                "Tout ce que vous venez de saisir se retrouve dans Réglages, et s'y modifie à tout moment.",
                systemImage: "gearshape"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                finish()
            } label: {
                Text("Ouvrir mon registre")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .readableWidth()
    }

    // MARK: - Navigation

    private func advance() {
        focusedField = nil
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation { step = next }
    }

    private func goBack() {
        focusedField = nil
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation { step = previous }
    }

    // MARK: - Persistance

    /// Reprend ce qui existe déjà : l'écran peut être rouvert depuis les
    /// réglages, et il ne doit pas présenter des champs vides à quelqu'un qui
    /// a déjà tout renseigné.
    private func loadExisting() {
        if let establishment = establishments.first {
            if establishmentName.isEmpty { establishmentName = establishment.name }
            if address.isEmpty { address = establishment.address }
            if siret.isEmpty { siret = establishment.siret }
            if managerName.isEmpty { managerName = establishment.managerName }
        }
        if operatorName.isEmpty { operatorName = preferences.operatorName }
        if contactEmail.isEmpty { contactEmail = preferences.contactEmail }
    }

    private func finish() {
        focusedField = nil
        persist()
        preferences.hasCompletedOnboarding = true
    }

    private func persist() {
        let trimmedName = establishmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedManager = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOperator = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        // Rien de saisi : on ne crée pas une fiche établissement vide qui
        // ferait croire à un réglage fait.
        if !trimmedName.isEmpty || !trimmedManager.isEmpty || !address.isEmpty {
            let establishment = establishments.first ?? {
                let created = Establishment()
                modelContext.insert(created)
                return created
            }()

            establishment.name = trimmedName
            establishment.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            establishment.siret = siret.trimmingCharacters(in: .whitespacesAndNewlines)
            establishment.managerName = trimmedManager
            establishment.updatedAt = .now

            try? modelContext.save()
        }

        if !trimmedOperator.isEmpty {
            preferences.operatorName = trimmedOperator
            preferences.rememberOperator(trimmedOperator)
        }

        preferences.contactEmail = trimmedEmail
    }
}
