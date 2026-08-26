//
//  SignaturePad.swift
//  HACCPPocket
//
//  Signature tracée au doigt.
//
//  L'émargement papier reste la norme en cuisine, et c'est précisément le
//  problème : la feuille se mouille, se perd, ou se remplit d'un coup le jour
//  du contrôle. Une signature tracée à l'écran est datée par l'application
//  elle-même — ce qui vaut nettement mieux qu'une colonne remplie après coup.
//
//  Ce n'est pas une signature électronique au sens juridique du terme, et
//  l'application ne prétend pas le contraire : c'est un émargement, comme sur
//  papier, avec l'horodatage en plus.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Zone de signature

struct SignaturePad: View {

    @Binding var signatureData: Data?

    /// Nom affiché sous le trait, comme sur un registre papier.
    var signerName: String = ""

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    private let lineWidth: CGFloat = 2.5
    private let padHeight: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if isEmpty {
                    Text("Signez ici")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                SignatureDrawing(
                    strokes: strokes + (currentStroke.isEmpty ? [] : [currentStroke]),
                    lineWidth: lineWidth
                )

                GeometryReader { proxy in
                    // La taille sert au rendu de l'image : elle doit être
                    // exactement celle où l'utilisateur a tracé.
                    Color.clear
                        .onAppear { canvasSize = proxy.size }
                        .onChange(of: proxy.size) { _, newValue in canvasSize = newValue }
                }
            }
            .frame(height: padHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        guard !currentStroke.isEmpty else { return }
                        strokes.append(currentStroke)
                        currentStroke = []
                        render()
                    }
            )

            HStack {
                if !signerName.isEmpty {
                    Text(signerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isEmpty {
                    Button(role: .destructive) {
                        clear()
                    } label: {
                        Label("Effacer", systemImage: "eraser")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
        .onAppear(perform: loadExisting)
    }

    private var isEmpty: Bool {
        strokes.isEmpty && currentStroke.isEmpty
    }

    // MARK: - Rendu

    /// Le tracé est converti en image dès qu'un trait se termine : la donnée
    /// enregistrée reste ainsi toujours en phase avec ce qui est à l'écran.
    @MainActor
    private func render() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        let renderer = ImageRenderer(
            content: SignatureDrawing(strokes: strokes, lineWidth: lineWidth)
                .frame(width: canvasSize.width, height: canvasSize.height)
        )
        renderer.scale = 3

        #if canImport(UIKit)
        signatureData = renderer.uiImage?.pngData()
        #endif
    }

    private func clear() {
        strokes = []
        currentStroke = []
        signatureData = nil
    }

    /// Une signature déjà enregistrée n'est pas rechargée comme un tracé
    /// modifiable : elle s'affiche telle quelle via `SignatureView`. Ici, on
    /// se contente de repartir d'une zone vierge.
    private func loadExisting() {
        strokes = []
        currentStroke = []
    }
}

// MARK: - Tracé

private struct SignatureDrawing: View {

    let strokes: [[CGPoint]]
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes where stroke.count > 1 {
                var path = Path()
                path.move(to: stroke[0])
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(.primary),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

// MARK: - Affichage d'une signature enregistrée

/// Relecture seule, pour les écrans de consultation et les fiches déjà
/// signées.
struct SignatureView: View {

    let data: Data
    var height: CGFloat = 90

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: height)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("Signature illisible", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        #else
        Label("Signature enregistrée", systemImage: "signature")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}

// MARK: - Ligne de formulaire

/// Section prête à poser dans un formulaire : elle bascule entre la relecture
/// d'une signature existante et la zone de tracé.
struct SignatureField: View {

    @Binding var signatureData: Data?
    var signerName: String = ""

    @State private var isEditing = false

    var body: some View {
        if let signatureData, !isEditing {
            VStack(alignment: .leading, spacing: 8) {
                SignatureView(data: signatureData)

                HStack {
                    Label("Signé", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Spacer()

                    Button {
                        isEditing = true
                    } label: {
                        Label("Signer à nouveau", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.brand)
                }
            }
            .padding(.vertical, 4)
        } else {
            SignaturePad(signatureData: $signatureData, signerName: signerName)
                .padding(.vertical, 4)
        }
    }
}

#Preview {
    Form {
        Section("Émargement") {
            SignatureField(signatureData: .constant(nil), signerName: "Marc")
        }
    }
}
