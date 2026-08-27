//
//  AppRootView.swift
//  HACCPPocket
//
//  Racine réelle de l'application : elle ouvre le registre de l'établissement
//  actif et le rouvre à chaque bascule.
//
//  Le conteneur SwiftData vit ici plutôt que dans la scène, parce qu'il doit
//  pouvoir être remplacé : changer d'établissement, c'est ouvrir un autre
//  fichier de base. Le `.id` force la reconstruction complète de l'interface,
//  faute de quoi les `@Query` continueraient d'interroger l'ancien registre.
//

import SwiftUI
import SwiftData

struct AppRootView: View {

    @Environment(EstablishmentDirectory.self) private var directory

    @State private var store: AppSchema.StoreResult?
    @State private var loadedSiteID: UUID?

    var body: some View {
        Group {
            if let store, loadedSiteID == directory.activeSiteID {
                RootView()
                    .modelContainer(store.container)
                    .environment(\.storeOutcome, store.outcome)
                    .id(directory.activeSiteID)
            } else {
                loadingView
            }
        }
        .task(id: directory.activeSiteID) {
            openActiveSite()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            BrandLogo(size: 64)
            ProgressView()
            Text("Ouverture du registre…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @MainActor
    private func openActiveSite() {
        let site = directory.activeSite
        store = AppSchema.openStore(for: site)
        loadedSiteID = site.id
    }
}
