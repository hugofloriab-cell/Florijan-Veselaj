//  GestionnaireSondes.swift
//
//  Dialogue CoreBluetooth avec les sondes. Rejoue la séquence décrite au § 5 de
//  PROTOCOLE-BLE.md :
//
//      connexion → lecture de l'état → réglage de l'horloge → souscription
//      → demande de déversement → réception des paquets → ÉCRITURE SUR DISQUE
//      → acquittement → déconnexion
//
//  Deux règles qui gouvernent tout ce fichier :
//
//  1. L'acquittement n'est envoyé qu'APRÈS l'écriture sur disque. Si la
//     synchronisation casse en route, la sonde garde tout et on recommencera :
//     aucun relevé n'est perdu.
//  2. On ne se déconnecte qu'APRÈS confirmation de l'écriture de
//     l'acquittement. Couper plus tôt annulerait l'écriture en file d'attente,
//     et la sonde redéverserait indéfiniment le même historique.

import Foundation
import CoreBluetooth
import UserNotifications

/// Une sonde vue à l'instant mais pas encore appairée.
struct SondeDetectee: Identifiable, Hashable {
    let id: UUID
    let nom: String
}

@MainActor
final class GestionnaireSondes: NSObject, ObservableObject {

    @Published private(set) var sondes: [Sonde] = []
    @Published private(set) var enRecherche = false
    @Published private(set) var message: String?
    @Published private(set) var detectees: [SondeDetectee] = []

    private var central: CBCentralManager!
    private let depot = Depot()

    private var enCours: [UUID: Session] = [:]
    /// CoreBluetooth exige qu'on retienne fortement les périphériques utilisés.
    private var peripheriques: [UUID: CBPeripheral] = [:]

    /// État d'une synchronisation en cours avec une sonde.
    private final class Session {
        let peripherique: CBPeripheral
        var etat: EtatSonde?
        var carCommande: CBCharacteristic?
        var recus: [ReleveBrut] = []
        var dernierIndex: Int = -1
        var attendAcquittement = false
        var termine = false
        let debut = Date()
        var chien: Task<Void, Never>?
        init(_ p: CBPeripheral) { peripherique = p }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        Task { sondes = await depot.charger() }
    }

    private func sauver() {
        let copie = sondes
        Task { await depot.enregistrer(copie) }
    }

    // MARK: - Actions

    /// Cherche les sondes à portée. Une sonde n'émet que 15 s toutes les
    /// 30 minutes : passez l'aimant sur le boîtier pour ouvrir une fenêtre
    /// immédiate de deux minutes.
    func chercher(pendant secondes: TimeInterval = 25) {
        guard central.state == .poweredOn else {
            message = messageEtat(central.state); return
        }
        detectees.removeAll()
        enRecherche = true
        central.scanForPeripherals(withServices: [Protocole.service],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Task {
            try? await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
            arreterRecherche()
        }
    }

    func arreterRecherche() {
        guard enRecherche else { return }
        central.stopScan()
        enRecherche = false
    }

    /// Relève toutes les sondes appairées. On tente d'abord les périphériques
    /// connus, puis on lance un scan qui ramassera celles qui dormaient.
    func releverTout() {
        guard central.state == .poweredOn else {
            message = messageEtat(central.state); return
        }
        guard !sondes.isEmpty else {
            message = "Aucune sonde appairée. Utilisez « Appairer »."; return
        }
        for p in central.retrievePeripherals(withIdentifiers: sondes.map(\.id)) {
            connecter(p)
        }
        chercher(pendant: 25)
    }

    func appairer(_ detectee: SondeDetectee) {
        if !sondes.contains(where: { $0.id == detectee.id }) {
            sondes.append(Sonde(id: detectee.id, nom: detectee.nom))
            sauver()
        }
        if let p = central.retrievePeripherals(withIdentifiers: [detectee.id]).first {
            connecter(p)
        }
    }

    func retirer(_ sonde: Sonde) {
        sondes.removeAll { $0.id == sonde.id }
        sauver()
    }

    func renommer(_ sonde: Sonde, nom: String, type: TypeEnceinte) {
        guard let i = sondes.firstIndex(where: { $0.id == sonde.id }) else { return }
        sondes[i].nom = nom
        sondes[i].type = type
        sauver()
        let b = type.bornes
        envoyer(.nommer(nom), a: sonde.id)
        envoyer(.seuils(minCenti: b.min, maxCenti: b.max), a: sonde.id)
    }

    func etalonner(_ sonde: Sonde, ecartCelsius: Double) {
        guard let i = sondes.firstIndex(where: { $0.id == sonde.id }) else { return }
        let centi = Int16(clamping: Int((ecartCelsius * 100).rounded()))
        sondes[i].offsetCenti = centi
        sondes[i].etalonneeLe = Date()
        sauver()
        envoyer(.etalonnage(centi: centi), a: sonde.id)
    }

    /// Écrit une commande si la sonde est connectée à cet instant. Sinon la
    /// tentative est sans effet : la valeur est déjà enregistrée sur le
    /// téléphone et repartira à la prochaine synchronisation.
    private func envoyer(_ commande: Commande, a identifiant: UUID) {
        guard let s = enCours[identifiant], let c = s.carCommande else { return }
        s.peripherique.writeValue(commande.trame, for: c, type: .withResponse)
    }

    private func connecter(_ p: CBPeripheral) {
        guard enCours[p.identifier] == nil else { return }
        peripheriques[p.identifier] = p
        p.delegate = self
        let session = Session(p)
        enCours[p.identifier] = session
        // Un connect CoreBluetooth n'expire jamais de lui-même : sans ce chien
        // de garde, une sonde repartie en veille bloquerait sa fiche pour de bon.
        session.chien = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.terminer(p.identifier, erreur: "sonde hors de portée ou endormie")
        }
        central.connect(p, options: nil)
    }

    private func messageEtat(_ e: CBManagerState) -> String {
        switch e {
        case .poweredOff:   return "Le Bluetooth est désactivé. Activez-le dans Réglages."
        case .unauthorized: return "L'application n'a pas l'autorisation Bluetooth. Réglages → Sondes HACCP."
        case .unsupported:  return "Cet appareil ne gère pas le Bluetooth à basse consommation."
        case .resetting:    return "Le Bluetooth redémarre, réessayez dans un instant."
        default:            return "Bluetooth indisponible."
        }
    }

    // MARK: - Fin de synchronisation

    /// Enregistre ce qui a été reçu, puis demande l'acquittement. La fermeture
    /// effective attend la confirmation d'écriture (voir didWriteValueFor).
    private func terminer(_ identifiant: UUID, erreur: String? = nil) {
        guard let session = enCours[identifiant], !session.termine else { return }
        session.termine = true
        session.chien?.cancel()

        guard let i = sondes.firstIndex(where: { $0.id == identifiant }) else {
            fermer(identifiant); return
        }

        if let erreur {
            sondes[i].derniereErreur = erreur
            sauver()
            message = "« \(sondes[i].nom) » : \(erreur)"
            fermer(identifiant)
            return
        }
        guard let etat = session.etat else { fermer(identifiant); return }

        // 1. Dater les relevés dans l'heure réelle — AVANT de déplacer le repère.
        let dateur = Dateur(sonde: sondes[i], ticsActuels: etat.tics, maintenant: session.debut)
        let nouveaux = session.recus
            .filter { $0.centi != Protocole.temperatureInvalide }
            .map { Releve(date: dateur.date(pourTics: $0.tics),
                          centi: $0.centi, pilePourcent: $0.pilePourcent) }
        sondes[i].ranger(nouveaux)

        // 2. Mémoriser l'état et le nouveau repère d'horloge.
        sondes[i].referenceTics = etat.tics
        sondes[i].referenceDate = session.debut
        sondes[i].derniereCenti = etat.derniereCenti
        sondes[i].pilePourcent = etat.pilePourcent
        sondes[i].millivolts = etat.millivolts
        sondes[i].intervalleMinutes = etat.intervalleMinutes
        sondes[i].offsetCenti = etat.offsetCenti
        sondes[i].drapeauxBruts = etat.drapeaux.rawValue
        sondes[i].derniereSynchro = Date()
        sondes[i].derniereErreur = nil

        // 3. Écrire sur disque, et seulement ensuite libérer la sonde.
        sauver()
        message = "« \(sondes[i].nom) » : \(nouveaux.count) relevé(s) rapatrié(s)."
        prevenirSiEcart(sondes[i])

        if session.dernierIndex >= 0, let c = session.carCommande {
            session.attendAcquittement = true
            session.peripherique.writeValue(
                Commande.acquitter(jusqua: UInt16(clamping: session.dernierIndex)).trame,
                for: c, type: .withResponse)
            // Filet : si la confirmation n'arrive pas, on ferme quand même.
            session.chien = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.fermer(identifiant)
            }
        } else {
            fermer(identifiant)
        }
    }

    private func fermer(_ identifiant: UUID) {
        guard let session = enCours[identifiant] else { return }
        session.chien?.cancel()
        enCours[identifiant] = nil
        if session.peripherique.state != .disconnected {
            central.cancelPeripheralConnection(session.peripherique)
        }
        peripheriques[identifiant] = nil
    }

    /// Notification locale en cas d'écart. Elle part même si la synchronisation
    /// a eu lieu en arrière-plan — c'est la seule façon d'être prévenu sans
    /// ouvrir l'application. Pour être réveillé la nuit, téléphone rangé et
    /// sonde hors de portée, il faut l'option Wi-Fi (README des sondes, § 7).
    private func prevenirSiEcart(_ sonde: Sonde) {
        let ecarts = sonde.bilan(du: Date())?.ecarts ?? 0
        guard sonde.horsSeuils(sonde.derniereCenti) || ecarts > 0 else { return }

        let contenu = UNMutableNotificationContent()
        contenu.title = "Température non conforme"
        contenu.body = "\(sonde.nom) : \(Format.degres(sonde.derniereCenti)) — norme \(sonde.type.libelle)."
        contenu.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "ecart-\(sonde.id.uuidString)",
                                  content: contenu, trigger: nil))
    }
}

// MARK: - CBCentralManagerDelegate
//
//  Le gestionnaire central est créé avec `queue: .main` : ces rappels arrivent
//  donc déjà sur la file principale. On utilise `MainActor.assumeIsolated`
//  plutôt qu'un `Task { @MainActor in }`, qui introduirait un saut asynchrone —
//  et l'ordre d'arrivée des paquets d'historique ne serait plus garanti.

extension GestionnaireSondes: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state != .poweredOn { self.message = self.messageEtat(central.state) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let nom = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                ?? peripheral.name ?? "Sonde"
            if self.sondes.contains(where: { $0.id == peripheral.identifier }) {
                self.connecter(peripheral)          // sonde connue : on la relève
            } else if !self.detectees.contains(where: { $0.id == peripheral.identifier }) {
                self.detectees.append(SondeDetectee(id: peripheral.identifier, nom: nom))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([Protocole.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            self.terminer(peripheral.identifier,
                          erreur: error?.localizedDescription ?? "connexion impossible")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            // Une déconnexion avant le paquet de fin est un échec : rien n'a été
            // acquitté, la sonde a tout gardé.
            if self.enCours[peripheral.identifier]?.termine == true {
                self.fermer(peripheral.identifier)
            } else {
                self.terminer(peripheral.identifier, erreur: "synchronisation interrompue")
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension GestionnaireSondes: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil,
                  let s = peripheral.services?.first(where: { $0.uuid == Protocole.service })
            else {
                self.terminer(peripheral.identifier, erreur: "service HACCP introuvable")
                return
            }
            peripheral.discoverCharacteristics(
                [Protocole.etat, Protocole.historique, Protocole.commande], for: s)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let cars = service.characteristics,
                  let etat = cars.first(where: { $0.uuid == Protocole.etat }),
                  let histo = cars.first(where: { $0.uuid == Protocole.historique }),
                  let cmd = cars.first(where: { $0.uuid == Protocole.commande })
            else {
                self.terminer(peripheral.identifier, erreur: "caractéristiques incomplètes")
                return
            }
            self.enCours[peripheral.identifier]?.carCommande = cmd
            peripheral.setNotifyValue(true, for: histo)
            peripheral.readValue(for: etat)      // la suite s'enchaîne à la lecture
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let valeur = characteristic.value,
                  let session = self.enCours[peripheral.identifier],
                  !session.termine else { return }

            if characteristic.uuid == Protocole.etat {
                guard let etat = EtatSonde(valeur) else {
                    self.terminer(peripheral.identifier, erreur: "état illisible"); return
                }
                guard etat.version == Protocole.version else {
                    self.terminer(peripheral.identifier,
                                  erreur: "sonde en version \(etat.version), non reconnue")
                    return
                }
                session.etat = etat
                guard let cmd = session.carCommande else { return }
                peripheral.writeValue(Commande.reglerHorloge(Date()).trame,
                                      for: cmd, type: .withResponse)
                peripheral.writeValue(Commande.deverser(depuis: 0xFFFF).trame,
                                      for: cmd, type: .withResponse)

            } else if characteristic.uuid == Protocole.historique {
                guard let paquet = PaquetHistorique(valeur) else { return }
                if paquet.estFin { self.terminer(peripheral.identifier); return }
                session.recus.append(contentsOf: paquet.releves)
                // Un max plutôt qu'une affectation : on n'acquitte jamais
                // au-delà de ce qu'on a réellement reçu.
                session.dernierIndex = max(session.dernierIndex,
                                           Int(paquet.premierIndex) + paquet.releves.count - 1)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let session = self.enCours[peripheral.identifier],
                  session.attendAcquittement else { return }
            // L'acquittement est parti et confirmé : on peut couper.
            self.fermer(peripheral.identifier)
        }
    }
}
