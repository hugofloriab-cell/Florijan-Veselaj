//
//  PhotoCaptureSheet.swift
//  HACCPPocket
//
//  Petite feuille réutilisable pour joindre une photo : appareil photo quand
//  il existe, photothèque sinon.
//

import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

struct PhotoCaptureSheet: View {

    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    /// Reçoit l'image en JPEG. La feuille se ferme ensuite.
    let onCapture: (Data) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var isPresentingCamera = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    #if canImport(UIKit)
                    if CameraPicker.isAvailable {
                        Button {
                            isPresentingCamera = true
                        } label: {
                            Label("Prendre une photo", systemImage: "camera")
                        }
                    }
                    #endif

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choisir dans la photothèque", systemImage: "photo.on.rectangle")
                    }

                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Chargement…").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(message)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, newItem in
                Task { await load(newItem) }
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isPresentingCamera) {
                CameraPicker(
                    onCapture: { data in
                        onCapture(data)
                    },
                    onFinish: {
                        isPresentingCamera = false
                        dismiss()
                    }
                )
                .ignoresSafeArea()
            }
            #endif
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoading = true
        defer { isLoading = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        onCapture(data)
        dismiss()
    }
}
