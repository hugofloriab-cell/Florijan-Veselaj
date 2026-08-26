//
//  SiteSwitcherView.swift
//  HACCPPocket
//
//  Bascule entre établissements, et profils d'utilisation.
//

import SwiftUI

// MARK: - Établissements

struct SiteSwitcherView: View {

    @Environment(EstablishmentDirectory.self) private var directory
    @Environment(RoleSession.self) private var roles

    @State private var newSiteName = ""
    @State private var renamedSite: SiteReference?
    @State private var renameText = ""
    @State private var siteToRemove: SiteReference?

    var body: some View {
        List {
            Section {
                ForEach(directory.sites) { site in
                    Button {
                        directory.select(site)
                    } label: {
                        HStack(spacing: 12) {
                            RowIcon(
                                systemImage: "building.2",
                                tint: site.id == directory.activeSiteID ? .brand : .secondary
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if site.id == directory.activeSiteID {
                                    Text("Registre ouvert")
                                        .font(.caption)
                                        .foregroundStyle(.brand)
                                }
                            }

                            Spacer(minLength: 8)

                            if site.id == directory.activeSiteID {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.brand)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing) {
                        if directory.sites.count > 1 {
                            Button(role: .destructive) {
                                siteToRemove = site
                            } label: {
                                Label("Retirer", systemImage: "minus.circle")
                            }
                        }

                        Button {
                            renamedSite = site
                            renameText = site.name
                        } label: {
                            Label("Renommer", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
                }
            } header: {
                Text("Établissements")
            } footer: {
                Text("Chaque établissement possède son propre registre. Les données ne se mélangent jamais : basculer revient à ouvrir un autre classeur. La sauvegarde, les clôtures et le registre mensuel portent sur l'établissement ouvert.")
            }

            if roles.role.canAdminister {
                Section {
                    HStack {
                        TextField("Nom du nouvel établissement", text: $newSiteName)
                        Button {
                            addSite()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.brand)
                        }
                        .buttonStyle(.plain)
                        .disabled(newSiteName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Ajouter")
                } footer: {
                    Text("Le nouvel établissement démarre sur un registre vierge, avec son propre plan de nettoyage et ses propres enceintes.")
                }
            }
        }
        .navigationTitle("Établissements")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Renommer", isPresented: renameBinding) {
            TextField("Nom", text: $renameText)
            Button("Renommer") { commitRename() }
            Button("Annuler", role: .cancel) { renamedSite = nil }
        }
        .alert(
            "Retirer cet établissement ?",
            isPresented: removeBinding,
            presenting: siteToRemove
        ) { site in
            Button("Retirer de la liste", role: .destructive) {
                directory.removeSite(site)
                siteToRemove = nil
            }
            Button("Annuler", role: .cancel) { siteToRemove = nil }
        } message: { _ in
            Text("Le registre n'est pas supprimé : ces enregistrements doivent être conservés plusieurs années. Le fichier reste sur l'appareil et l'établissement pourra être remis dans la liste.")
        }
    }

    private func addSite() {
        let site = directory.addSite(named: newSiteName)
        newSiteName = ""
        directory.select(site)
    }

    private func commitRename() {
        if let renamedSite {
            directory.rename(renamedSite, to: renameText)
        }
        renamedSite = nil
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamedSite != nil }, set: { if !$0 { renamedSite = nil } })
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { siteToRemove != nil }, set: { if !$0 { siteToRemove = nil } })
    }
}

// MARK: - Profils

struct RoleSwitcherView: View {

    @Environment(RoleSession.self) private var roles

    @State private var pendingRole: UserRole?
    @State private var code = ""
    @State private var failed = false
    @State private var newCode = ""
    @State private var codeSaved = false

    var body: some View {
        List {
            Section {
                ForEach(UserRole.allCases) { role in
                    Button {
                        select(role)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RowIcon(
                                systemImage: role.systemImage,
                                tint: role == roles.role ? .brand : .secondary
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(role.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(role.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            if role == roles.role {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.brand)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Profil en cours")
            } footer: {
                Text("Ce ne sont pas des comptes, et ce n'est pas de la sécurité : une application posée sur un téléphone de cuisine partagé ne peut authentifier personne. Ce sont des garde-fous, qui évitent qu'un geste distrait n'atteigne un écran sensible.")
            }

            if roles.role.canAdminister {
                Section {
                    HStack {
                        SecureField(
                            roles.hasManagerCode ? "Modifier le code Gérant" : "Définir un code (4 chiffres minimum)",
                            text: $newCode
                        )
                        .keyboardType(.numberPad)

                        Button {
                            roles.setManagerCode(newCode)
                            newCode = ""
                            codeSaved = true
                        } label: {
                            Text("Définir")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.brand)
                        .disabled(newCode.trimmingCharacters(in: .whitespaces).count < 4)
                    }

                    if codeSaved {
                        Label("Code enregistré", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if roles.hasManagerCode {
                        Button(role: .destructive) {
                            roles.removeManagerCode()
                            codeSaved = false
                        } label: {
                            Label("Retirer le code", systemImage: "lock.open")
                        }
                    }
                } header: {
                    Text("Code du profil Gérant")
                } footer: {
                    Text("Sans code, n'importe qui peut repasser en Gérant. Avec, il faut le saisir — ce qui suffit à décourager le geste distrait, et rien de plus.")
                }
            }
        }
        .navigationTitle("Profils")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Code Gérant", isPresented: codeBinding) {
            SecureField("Code", text: $code)
            Button("Valider") { confirm() }
            Button("Annuler", role: .cancel) { pendingRole = nil; code = "" }
        } message: {
            Text(failed ? "Code incorrect." : "Saisissez le code du profil Gérant.")
        }
    }

    private func select(_ role: UserRole) {
        guard role != roles.role else { return }

        if role == .manager && roles.requiresCodeToBecomeManager {
            pendingRole = role
            failed = false
            return
        }

        roles.switchTo(role)
    }

    private func confirm() {
        guard let pendingRole else { return }

        if roles.switchTo(pendingRole, code: code) {
            self.pendingRole = nil
            failed = false
        } else {
            failed = true
        }
        code = ""
    }

    private var codeBinding: Binding<Bool> {
        Binding(get: { pendingRole != nil }, set: { if !$0 { pendingRole = nil } })
    }
}
