/* sonde-haccp — enregistreur de température autonome pour la check-list
 * petit déjeuner de l'Hôtel Ibis Sisteron.
 *
 * Carte    : ESP32-C3 (XIAO, SuperMini) ou ESP32 classique (DevKit, WROOM-32)
 *            Le brochage et le réveil s'adaptent à la puce — voir config.h.
 * Capteur  : DS18B20 étanche déporté
 * Radio    : BLE — la tablette vient chercher l'historique
 * Piles    : 3 × AA lithium, plus d'un an d'autonomie
 *
 * Le protocole est décrit dans ../../PROTOCOLE-BLE.md. Toute modification du
 * format des trames doit être reportée dans la fiche (section « Sondes »).
 *
 * Principe : le programme ne tourne pas en boucle. Chaque réveil exécute
 * setup() du début à la fin puis repart en veille profonde ; loop() n'est
 * jamais atteint. Tout ce qui doit survivre est en RTC_DATA_ATTR.
 */

#include "config.h"

#include <OneWire.h>
#include <DallasTemperature.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_sleep.h>
#include <driver/gpio.h>
#include <Preferences.h>
#if defined(CONFIG_IDF_TARGET_ESP32)
  #include <driver/rtc_io.h>
#endif

/* esp_read_mac() et ESP_MAC_BT ont déménagé : esp_mac.h depuis ESP-IDF 5
   (cœur Arduino 3.x), esp_system.h avant. On laisse le préprocesseur trancher
   plutôt que de parier sur une version. */
#if __has_include(<esp_mac.h>)
  #include <esp_mac.h>
#else
  #include <esp_system.h>
#endif

#if ALERTE_WIFI || PORTAIL_WIFI
  #include <WiFi.h>
#endif

#if ALERTE_WIFI
  #include <WiFiClientSecure.h>
  #include <HTTPClient.h>
#endif

#if PORTAIL_WIFI
  #include <WebServer.h>
  #if PORTAIL_MODE == PORTAIL_STATION
    #include <ESPmDNS.h>
  #endif
#endif

/* ============ Protocole ============ */

#define UUID_SERVICE    "e9ea0001-6d2c-4f8b-9a35-0b7c1d4e5f60"
#define UUID_ETAT       "e9ea0002-6d2c-4f8b-9a35-0b7c1d4e5f60"
#define UUID_HISTORIQUE "e9ea0003-6d2c-4f8b-9a35-0b7c1d4e5f60"
#define UUID_COMMANDE   "e9ea0004-6d2c-4f8b-9a35-0b7c1d4e5f60"

#define VERSION_PROTOCOLE 1

#define DRAPEAU_HORLOGE_OK    0x01
#define DRAPEAU_ALERTE_T      0x02
#define DRAPEAU_PILE_FAIBLE   0x04
#define DRAPEAU_TAMPON_PLEIN  0x08
#define DRAPEAU_CAPTEUR_HS    0x10
#define DRAPEAU_REVEIL_MANUEL 0x20

#define TEMPERATURE_INVALIDE ((int16_t)0x8000)

/* Marqueur écrit en mémoire RTC. S'il est absent au démarrage, c'est que
   l'alimentation a été coupée : on repart d'un tampon vide. */
#define MAGIE 0x48414331UL  /* "HAC1" */

/* ============ Persistance en mémoire RTC ============ */

/* Conservée pendant la veille profonde, perdue si les piles sont retirées.
   D'où la consigne : synchroniser avant de changer les piles. */
typedef struct {
  uint32_t tics;   /* horloge propre de la sonde, en secondes */
  int16_t  centi;  /* température × 100 */
  uint8_t  pile;   /* pourcentage */
  uint8_t  drapeaux;
} Releve;

RTC_DATA_ATTR static uint32_t rtcMagie      = 0;
RTC_DATA_ATTR static Releve   rtcTampon[CAPACITE_TAMPON];
RTC_DATA_ATTR static uint16_t rtcTete       = 0;  /* prochaine case à écrire   */
RTC_DATA_ATTR static uint16_t rtcAttente    = 0;  /* relevés non acquittés     */
RTC_DATA_ATTR static uint32_t rtcTics       = 0;  /* secondes depuis la mise sous tension */
RTC_DATA_ATTR static uint32_t rtcProchain   = 0;  /* tics de la prochaine mesure */
RTC_DATA_ATTR static uint32_t rtcUnixRef    = 0;  /* heure réglée par la tablette */
RTC_DATA_ATTR static uint8_t  rtcIntervalle = INTERVALLE_MINUTES;
RTC_DATA_ATTR static int16_t  rtcOffset     = OFFSET_ETALONNAGE_CENTI;
RTC_DATA_ATTR static int16_t  rtcSeuilMin   = SEUIL_MIN_CENTI;
RTC_DATA_ATTR static int16_t  rtcSeuilMax   = SEUIL_MAX_CENTI;
RTC_DATA_ATTR static uint8_t  rtcDrapeaux   = 0;
RTC_DATA_ATTR static uint16_t rtcTension    = 0;
RTC_DATA_ATTR static int16_t  rtcDerniere   = TEMPERATURE_INVALIDE;
RTC_DATA_ATTR static uint8_t  rtcPile       = 100;
RTC_DATA_ATTR static char     rtcNom[17]    = EMPLACEMENT;
RTC_DATA_ATTR static uint8_t  rtcHorsSeuil  = 0;  /* mesures consécutives hors seuils */
RTC_DATA_ATTR static uint8_t  rtcCyclesMuets = 0; /* réveils sans fenêtre radio */
RTC_DATA_ATTR static uint32_t rtcDerniereAlerte = 0;
RTC_DATA_ATTR static uint8_t  rtcEchecsAlerte   = 0;  /* envois ratés d'affilée */

/* ============ État de la session en cours ============ */

static OneWire           unFil(BROCHE_1WIRE);
static DallasTemperature capteur(&unFil);

static BLEServer         *serveur     = nullptr;
static BLECharacteristic *carEtat     = nullptr;
static BLECharacteristic *carHisto    = nullptr;
static BLECharacteristic *carCommande = nullptr;

static volatile bool     connecte      = false;
static volatile bool     deversementDemande = false;
static volatile uint16_t deversementDepuis  = 0xFFFF;
static volatile uint32_t finFenetreMs  = 0;
static uint16_t          mtu           = 23;

#if TRACE
  #define trace(...) do { Serial.printf(__VA_ARGS__); Serial.println(); } while (0)
#else
  #define trace(...) do {} while (0)
#endif

/* ============ Réglages qui survivent aux piles ============ */

/* La mémoire RTC survit à la veille profonde, pas au retrait des piles. Or
   l'étalonnage doit survivre à un changement de piles : une sonde qui perd
   silencieusement sa correction continue d'enregistrer, mais faux, et personne
   ne s'en aperçoit. Sur un registre sanitaire, c'est la pire des pannes.

   Ces cinq réglages — ceux qu'une tablette peut modifier à distance — vont donc
   aussi en mémoire flash, qui ne dépend d'aucune alimentation. On n'y écrit que
   lorsqu'ils changent, c'est-à-dire quelques fois dans la vie de la sonde :
   aucune usure à craindre. */

static void reglagesCharger() {
  Preferences p;
  if (!p.begin("sonde", true)) return;          /* lecture seule */
  rtcOffset     = p.getShort("offset",     OFFSET_ETALONNAGE_CENTI);
  rtcSeuilMin   = p.getShort("seuilmin",   SEUIL_MIN_CENTI);
  rtcSeuilMax   = p.getShort("seuilmax",   SEUIL_MAX_CENTI);
  rtcIntervalle = p.getUChar("intervalle", INTERVALLE_MINUTES);
  char nom[sizeof(rtcNom)] = { 0 };
  if (p.getString("nom", nom, sizeof(nom)) > 0 && nom[0]) {
    strncpy(rtcNom, nom, sizeof(rtcNom) - 1);
    rtcNom[sizeof(rtcNom) - 1] = '\0';
  }
  p.end();
  trace("reglages relus de la flash : offset %d, seuils %d/%d, %u min, \"%s\"",
        (int)rtcOffset, (int)rtcSeuilMin, (int)rtcSeuilMax,
        (unsigned)rtcIntervalle, rtcNom);
}

static void reglagesEnregistrer() {
  Preferences p;
  if (!p.begin("sonde", false)) { trace("flash indisponible"); return; }
  p.putShort("offset",     rtcOffset);
  p.putShort("seuilmin",   rtcSeuilMin);
  p.putShort("seuilmax",   rtcSeuilMax);
  p.putUChar("intervalle", rtcIntervalle);
  p.putString("nom",       rtcNom);
  p.end();
  trace("reglages ecrits en flash");
}

/* ============ Mesures ============ */

/* Le DS18B20 est alimenté par une broche : hors mesure il ne consomme rien,
   pas même son microampère de veille. */
static int16_t lireTemperature() {
#if BROCHE_CAPTEUR_VCC >= 0
  pinMode(BROCHE_CAPTEUR_VCC, OUTPUT);
  digitalWrite(BROCHE_CAPTEUR_VCC, HIGH);
  delay(12);                       /* le capteur a besoin de se stabiliser */
#endif

  capteur.begin();
  capteur.setResolution(12);       /* 0,0625 °C, conversion 750 ms */
  capteur.requestTemperatures();
  float c = capteur.getTempCByIndex(0);

#if BROCHE_CAPTEUR_VCC >= 0
  digitalWrite(BROCHE_CAPTEUR_VCC, LOW);
  pinMode(BROCHE_CAPTEUR_VCC, INPUT);
#endif

  if (c == DEVICE_DISCONNECTED_C || c < -60.0f || c > 125.0f) {
    rtcDrapeaux |= DRAPEAU_CAPTEUR_HS;
    return TEMPERATURE_INVALIDE;
  }
  rtcDrapeaux &= ~DRAPEAU_CAPTEUR_HS;
  return (int16_t)lroundf(c * 100.0f) + rtcOffset;
}

/* Le pont diviseur n'est fermé que le temps de la mesure : en permanence, ses
   2 MΩ consommeraient plus que l'ESP32 endormi. */
static uint16_t lireTensionPile() {
#if PILE_SIMULEE
  /* Banc d'essai : le pont diviseur n'est pas câblé et la broche flotte.
     Mieux vaut annoncer une batterie pleine qu'une valeur fantaisiste. */
  return PILE_PLEINE_MV;
#else
  pinMode(BROCHE_PONT, OUTPUT);
  digitalWrite(BROCHE_PONT, HIGH);
  /* Pas de réglage d'atténuation : le cœur Arduino ESP32 est déjà sur la plus
     large (11 dB), et le nom de cette valeur a changé d'une version à l'autre.
     analogReadMilliVolts() applique de toute façon l'étalonnage d'usine. */
  delay(3);                        /* charge du condensateur de filtrage */

  uint32_t somme = 0;
  for (int i = 0; i < 8; i++) { somme += analogReadMilliVolts(BROCHE_PILE); delay(1); }

  digitalWrite(BROCHE_PONT, LOW);
  pinMode(BROCHE_PONT, INPUT);

  return (uint16_t)((somme / 8.0f) * PONT_RAPPORT);
#endif
}

/* Conversion tension → pourcentage. La courbe d'une pile lithium AA est très
   plate : une interpolation linéaire sur la plage utile suffit, et le suivi
   d'autonomie de la fiche travaille de toute façon sur la pente mesurée. */
static uint8_t pourcentagePile(uint16_t mv) {
  if (mv >= PILE_PLEINE_MV) return 100;
  if (mv <= PILE_VIDE_MV)   return 0;
  return (uint8_t)(100UL * (mv - PILE_VIDE_MV) / (PILE_PLEINE_MV - PILE_VIDE_MV));
}

/* ============ Tampon circulaire ============ */

static void rangerReleve(int16_t centi, uint8_t pile, uint8_t drapeaux) {
  rtcTampon[rtcTete].tics     = rtcTics;
  rtcTampon[rtcTete].centi    = centi;
  rtcTampon[rtcTete].pile     = pile;
  rtcTampon[rtcTete].drapeaux = drapeaux;
  rtcTete = (rtcTete + 1) % CAPACITE_TAMPON;

  if (rtcAttente < CAPACITE_TAMPON) {
    rtcAttente++;
  } else {
    /* Le tampon a fait le tour sans synchronisation : le plus ancien relevé
       vient d'être écrasé. On le signale, la fiche affichera un trou. */
    rtcDrapeaux |= DRAPEAU_TAMPON_PLEIN;
  }
}

/* Les relevés en attente, du plus ancien au plus récent. */
static const Releve *releveEnAttente(uint16_t index) {
  uint16_t debut = (rtcTete + CAPACITE_TAMPON - rtcAttente) % CAPACITE_TAMPON;
  return &rtcTampon[(debut + index) % CAPACITE_TAMPON];
}

static void acquitter(uint16_t jusqua) {
  uint16_t n = jusqua + 1;
  if (n > rtcAttente) n = rtcAttente;
  rtcAttente -= n;
  if (rtcAttente == 0) rtcDrapeaux &= ~DRAPEAU_TAMPON_PLEIN;
  trace("acquitte %u, reste %u", n, rtcAttente);
}

/* ============ Trames BLE ============ */

static void ecrireU16(uint8_t *p, uint16_t v) { p[0] = v & 0xFF; p[1] = v >> 8; }
static void ecrireU32(uint8_t *p, uint32_t v) {
  p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; p[2] = (v >> 16) & 0xFF; p[3] = (v >> 24) & 0xFF;
}
static uint16_t lireU16(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t lireU32(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void publierEtat(bool notifier) {
  uint8_t t[20];
  t[0] = VERSION_PROTOCOLE;
  t[1] = rtcDrapeaux;
  ecrireU16(t + 2, rtcTension);
  t[4] = rtcPile;
  t[5] = rtcIntervalle;
  ecrireU16(t + 6, (uint16_t)rtcDerniere);
  ecrireU16(t + 8, rtcAttente);
  ecrireU32(t + 10, rtcTics);
  ecrireU32(t + 14, rtcUnixRef);
  ecrireU16(t + 18, (uint16_t)rtcOffset);

  if (!carEtat) return;
  carEtat->setValue(t, sizeof(t));
  if (notifier && connecte) carEtat->notify();
}

/* Déversement de l'historique : paquets de relevés jusqu'à épuisement, puis
   un paquet vide qui marque la fin. La tablette n'acquitte qu'après avoir
   écrit ; en cas de coupure, rien n'est perdu. */
static void deverserHistorique(uint16_t depuis) {
  if (depuis == 0xFFFF) depuis = 0;

  uint16_t parPaquet = (mtu > 30) ? (uint16_t)((mtu - 3 - 4) / 8) : 2;
  if (parPaquet > 20) parPaquet = 20;

  uint8_t paquet[4 + 20 * 8];
  uint16_t i = depuis;

  trace("deversement depuis %u sur %u (mtu %u, %u/paquet)", depuis, rtcAttente, mtu, parPaquet);

  while (i < rtcAttente && connecte) {
    uint16_t n = rtcAttente - i;
    if (n > parPaquet) n = parPaquet;

    ecrireU16(paquet, i);
    ecrireU16(paquet + 2, n);
    for (uint16_t k = 0; k < n; k++) {
      const Releve *r = releveEnAttente(i + k);
      uint8_t *c = paquet + 4 + k * 8;
      ecrireU32(c, r->tics);
      ecrireU16(c + 4, (uint16_t)r->centi);
      c[6] = r->pile;
      c[7] = r->drapeaux;
    }
    carHisto->setValue(paquet, 4 + n * 8);
    carHisto->notify();
    i += n;
    delay(14);   /* laisse la pile BLE écouler sa file d'attente */
  }

  if (!connecte) return;
  ecrireU16(paquet, i);
  ecrireU16(paquet + 2, 0);
  carHisto->setValue(paquet, 4);
  carHisto->notify();
  trace("deversement termine");
}

/* ============ Rappels BLE ============ */

/* Les cœurs Arduino ESP32 ont fait varier la signature de ces rappels : selon
   la version, la bibliothèque appelle la forme à un ou à deux arguments. On
   déclare les deux, sans « override » — ainsi le code compile quelle que soit
   la version, et reçoit l'appel dans tous les cas. */
class RappelsServeur : public BLEServerCallbacks {
  void connexion() {
    connecte = true;
    /* Tant qu'une tablette est là, on ne repart pas en veille. */
    finFenetreMs = millis() + 60000UL;
    trace("connecte");
  }
  void deconnexion() {
    connecte = false;
    /* Petite fenêtre de repêchage : une déconnexion accidentelle en pleine
       synchronisation ne doit pas obliger à attendre 30 minutes. */
    finFenetreMs = millis() + 20000UL;
    BLEDevice::startAdvertising();
    trace("deconnecte");
  }
 public:
  void onConnect(BLEServer *s) { connexion(); }
  void onConnect(BLEServer *s, esp_ble_gatts_cb_param_t *param) { connexion(); }
  void onDisconnect(BLEServer *s) { deconnexion(); }
  void onDisconnect(BLEServer *s, esp_ble_gatts_cb_param_t *param) { deconnexion(); }
  void onMtuChanged(BLEServer *s, esp_ble_gatts_cb_param_t *param) {
    mtu = param->mtu.mtu;
    trace("mtu %u", mtu);
  }
};

class RappelsCommande : public BLECharacteristicCallbacks {
 public:
  void onWrite(BLECharacteristic *c) { traiter(c); }
  void onWrite(BLECharacteristic *c, esp_ble_gatts_cb_param_t *param) { traiter(c); }

 private:
  void traiter(BLECharacteristic *c) {
    uint8_t *d = c->getData();
    size_t   n = c->getLength();
    if (n < 1) return;

    /* La fenêtre est repoussée à chaque commande : une synchronisation longue
       ne se fait pas couper par l'expiration du minuteur. */
    finFenetreMs = millis() + 60000UL;

    switch (d[0]) {
      case 0x01:                                   /* régler l'horloge */
        if (n >= 5) {
          rtcUnixRef   = lireU32(d + 1);
          rtcDrapeaux |= DRAPEAU_HORLOGE_OK;
          trace("horloge %lu", (unsigned long)rtcUnixRef);
        }
        break;

      case 0x02:                                   /* déverser l'historique */
        deversementDepuis  = (n >= 3) ? lireU16(d + 1) : 0xFFFF;
        deversementDemande = true;
        break;

      case 0x03:                                   /* acquitter */
        if (n >= 3) acquitter(lireU16(d + 1));
        break;

      case 0x04:                                   /* changer l'intervalle */
        if (n >= 2 && d[1] >= 1 && d[1] <= 240) {
          rtcIntervalle = d[1];
          rtcProchain   = rtcTics + (uint32_t)rtcIntervalle * 60UL;
          reglagesEnregistrer();
        }
        break;

      case 0x05:                                   /* offset d'étalonnage */
        if (n >= 3) {
          rtcOffset = (int16_t)lireU16(d + 1);
          reglagesEnregistrer();
        }
        break;

      case 0x06:                                   /* seuils d'alerte */
        if (n >= 5) {
          rtcSeuilMin = (int16_t)lireU16(d + 1);
          rtcSeuilMax = (int16_t)lireU16(d + 3);
          reglagesEnregistrer();
        }
        break;

      case 0x07:                                   /* rester éveillé */
        finFenetreMs = millis() + 300000UL;
        break;

      case 0x08: {                                 /* nommer l'emplacement */
        size_t len = n - 1;
        if (len > 16) len = 16;
        memcpy(rtcNom, d + 1, len);
        rtcNom[len] = '\0';
        reglagesEnregistrer();
        break;
      }
    }
    publierEtat(true);
  }
};

/* ============ Fenêtre radio ============ */

static void nomSonde(char *sortie, size_t taille) {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  snprintf(sortie, taille, "HACCP-%02X%02X", mac[4], mac[5]);
}

/* Le paquet d'annonce ne fait que 31 octets : l'UUID 128 bits en occupe déjà
   18. Le nom et les données constructeur passent donc dans la réponse au
   scan, que Chrome fusionne avec l'annonce. */
static void demarrerAnnonce() {
  char nom[16];
  nomSonde(nom, sizeof(nom));

  BLEDevice::init(nom);
  /* Avant toute émission : brider la puissance limite le pic de courant, qui
     est la cause habituelle d'une carte qui redémarre pendant l'annonce. */
  BLEDevice::setPower(PUISSANCE_BLE);
  BLEDevice::setMTU(517);

  serveur = BLEDevice::createServer();
  serveur->setCallbacks(new RappelsServeur());

  BLEService *service = serveur->createService(BLEUUID(UUID_SERVICE), 20, 0);

  carEtat = service->createCharacteristic(
      UUID_ETAT, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  carEtat->addDescriptor(new BLE2902());

  carHisto = service->createCharacteristic(
      UUID_HISTORIQUE, BLECharacteristic::PROPERTY_NOTIFY);
  carHisto->addDescriptor(new BLE2902());

  carCommande = service->createCharacteristic(
      UUID_COMMANDE, BLECharacteristic::PROPERTY_WRITE);
  carCommande->setCallbacks(new RappelsCommande());

  publierEtat(false);
  service->start();

  BLEAdvertisementData annonce;
  annonce.setFlags(0x06);                          /* découvrable, BLE seul */
  annonce.setCompleteServices(BLEUUID(UUID_SERVICE));

  /* Données constructeur : la température est lisible dans le résultat de
     scan, sans même se connecter. */
  uint8_t brut[9];
  ecrireU16(brut, 0xFFFF);                         /* identifiant d'usage privé */
  brut[2] = VERSION_PROTOCOLE;
  ecrireU16(brut + 3, (uint16_t)rtcDerniere);
  brut[5] = rtcPile;
  ecrireU16(brut + 6, rtcAttente);
  brut[8] = rtcDrapeaux;

  BLEAdvertisementData reponse;
  reponse.setName(nom);
  reponse.setManufacturerData(String((char *)brut, sizeof(brut)));

  BLEAdvertising *pub = BLEDevice::getAdvertising();
  pub->setAdvertisementData(annonce);
  pub->setScanResponseData(reponse);
  pub->setScanResponse(true);
  /* 200 ms : compromis entre la vitesse à laquelle Chrome trouve la sonde et
     le courant moyen pendant la fenêtre. */
  pub->setMinInterval(0x0140);
  pub->setMaxInterval(0x0190);
  BLEDevice::startAdvertising();

  trace("annonce %s", nom);
}

static void tenirFenetre(uint32_t dureeS) {
  finFenetreMs = millis() + dureeS * 1000UL;

  while ((int32_t)(millis() - finFenetreMs) < 0) {
    if (deversementDemande) {
      deversementDemande = false;
      deverserHistorique(deversementDepuis);
    }
    delay(20);
  }

  if (connecte && serveur) serveur->disconnect(0);
  delay(60);
  BLEDevice::deinit(true);
}

/* ============ Degrés lisibles ============ */

/* La température circule partout en centièmes entiers — jamais de virgule
   flottante, voir PROTOCOLE-HTTP.md § 7. Mais une notification qui annonce
   « 1863 » sur un téléphone ne sert à personne : on convertit ici, au dernier
   moment, et sans flottant. */
#if ALERTE_WIFI || PORTAIL_WIFI
static void centiEnTexte(int16_t centi, char *sortie, size_t taille) {
  if (centi == TEMPERATURE_INVALIDE) {
    snprintf(sortie, taille, "capteur muet");
    return;
  }
  int32_t a = centi < 0 ? -(int32_t)centi : (int32_t)centi;
  snprintf(sortie, taille, "%s%ld,%02ld", centi < 0 ? "-" : "",
           (long)(a / 100), (long)(a % 100));
}
#endif

/* ============ Alerte Wi-Fi ============ */

#if ALERTE_WIFI
/* N'allume le Wi-Fi que pour une alerte réelle. En marche normale, la radio
   Wi-Fi n'est jamais alimentée : elle ne coûte rien. */
/* Renvoie vrai si ntfy a réellement accepté le message. Ça compte : une alerte
   perdue ne doit pas être comptée comme envoyée, sinon la sonde se tairait deux
   heures sur un congélateur en train de lâcher. */
static bool pousserAlerte(const char *titre, const char *corps, const char *priorite) {
  bool reussi = false;

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_MDP);

  uint32_t debut = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - debut < 15000UL) delay(150);

  if (WiFi.status() == WL_CONNECTED) {
    /* Une URL https ne suffit pas : HTTPClient::begin(url) seul ne sait pas
       ouvrir de connexion chiffrée, et la requête échoue sans explication. Il
       faut lui passer un client TLS explicite.

       setInsecure() n'authentifie pas le serveur. C'est un choix assumé :
       vérifier le certificat demanderait d'embarquer une autorité de
       certification et de la tenir à jour dans une sonde censée vivre des
       années sans maintenance. Le risque encouru est qu'un intrus sur le
       réseau puisse intercepter ou falsifier un message disant qu'un
       congélateur est trop chaud — pas un secret d'exploitation. */
    WiFiClientSecure client;
    client.setInsecure();

    HTTPClient http;
    http.setConnectTimeout(8000);
    http.setTimeout(8000);
    if (http.begin(client, "https://ntfy.sh/" NTFY_SUJET)) {
      http.addHeader("Title", titre);
      http.addHeader("Priority", priorite);
      http.addHeader("Tags", "warning,thermometer");
      int code = http.POST((uint8_t *)corps, strlen(corps));
      http.end();
      trace("alerte poussee, code http %d", code);   /* 200 = accepte */
      if (code >= 200 && code < 300) reussi = true;
    } else {
      trace("ouverture https impossible");
    }
  } else {
    trace("wifi indisponible (etat %d)", (int)WiFi.status());
  }

  /* Un seul appel : le premier « true » coupe déjà la radio. Y ajouter un
     WiFi.mode(WIFI_OFF) faisait apparaître ESP_ERR_WIFI_STOP_STATE dans la
     trace — voir le même correctif dans tenirPortail(). */
  WiFi.disconnect(true, true);
  return reussi;
}

/* Une alerte partie se tait deux heures. Une alerte ratée doit repartir au
   prochain relevé — mais pas indéfiniment : si le réseau est durablement absent,
   rallumer le Wi-Fi 48 fois par jour viderait les piles en quelques semaines pour
   rien. Trois essais, puis on attend comme si elle était passée. */
static void alerteTentee(bool reussi) {
  if (reussi) {
    rtcDerniereAlerte = rtcTics;
    rtcEchecsAlerte   = 0;
    return;
  }
  if (rtcEchecsAlerte < 255) rtcEchecsAlerte++;
  trace("alerte ratee (%u essai%s)", (unsigned)rtcEchecsAlerte,
        rtcEchecsAlerte > 1 ? "s" : "");
  if (rtcEchecsAlerte >= 3) {
    trace("reseau durablement absent, mise au repos");
    rtcDerniereAlerte = rtcTics;
    rtcEchecsAlerte   = 0;
  }
}

static void examinerAlertes(int16_t centi) {
  bool horsSeuil = (centi != TEMPERATURE_INVALIDE) &&
                   (centi < rtcSeuilMin || centi > rtcSeuilMax);

  if (horsSeuil) { if (rtcHorsSeuil < 255) rtcHorsSeuil++; }
  else           { rtcHorsSeuil = 0; }

  bool repos = (rtcDerniereAlerte != 0) &&
               (rtcTics - rtcDerniereAlerte < (uint32_t)ALERTE_REPOS_MINUTES * 60UL);

  /* Sans ça, une alerte qui ne part pas laisse le programme muet, et on ne sait
     pas s'il a décidé de se taire ou s'il n'a jamais tourné. */
  trace("alertes: hors seuils %u/%u, pile %u%%, repos %d",
        (unsigned)rtcHorsSeuil, (unsigned)ALERTE_MESURES_CONSECUTIVES,
        (unsigned)rtcPile, (int)repos);

  if (repos) return;

  char corps[200];

  if (rtcHorsSeuil >= ALERTE_MESURES_CONSECUTIVES) {
    char t[16], tmin[16], tmax[16];
    centiEnTexte(centi, t, sizeof(t));
    centiEnTexte(rtcSeuilMin, tmin, sizeof(tmin));
    centiEnTexte(rtcSeuilMax, tmax, sizeof(tmax));
    snprintf(corps, sizeof(corps),
             "%s : %s C depuis %u releves (seuils %s a %s C). Verifier l'enceinte.",
             rtcNom, t, rtcHorsSeuil, tmin, tmax);
    alerteTentee(pousserAlerte("Temperature non conforme", corps, "urgent"));
    return;
  }

  if (rtcPile < PILE_FAIBLE_PCT) {
    snprintf(corps, sizeof(corps),
             "%s : pile a %u%% (%u mV). Prevoir le remplacement des piles.",
             rtcNom, rtcPile, rtcTension);
    alerteTentee(pousserAlerte("Pile de sonde faible", corps, "default"));
  }
}
#endif

/* ============ Portail Wi-Fi ============ */

/* Le même principe qu'une petite caméra d'inspection : l'appareil porte son
   propre réseau (ou rejoint celui de la maison), on s'y connecte, on lit en
   direct, et rien n'est enregistré ailleurs.
 *
 * La différence avec une caméra, et c'est elle qui dicte tout le reste : une
 * caméra sert deux minutes puis retourne dans son tiroir. Une sonde HACCP doit
 * tenir des mois sur des piles. Le portail ne peut donc pas rester allumé — il
 * s'ouvre à la demande, sur l'aimant, et se referme dès que l'application a
 * fini. D'où PORTAIL_ARRET_APRES_ACQUIT : une consultation de vingt secondes
 * coûte vingt secondes de radio, pas trois minutes.
 *
 * Le contrat HTTP est décrit dans ../../PROTOCOLE-HTTP.md. Toute modification
 * du format JSON doit y être reportée.
 */

#if PORTAIL_WIFI

static WebServer  portail(80);
static bool       portailOuvert = false;
static bool       portailFini   = false;   /* l'application a acquitté       */
static uint32_t   portailFinMs  = 0;

/* Le libellé d'emplacement est modifiable à distance — commande 0x08 en
   Bluetooth. Un guillemet ou une barre oblique inverse dedans casserait le JSON
   de toutes les requêtes suivantes, et la synchronisation avec lui, jusqu'à ce
   que quelqu'un comprenne pourquoi. On échappe donc, plutôt que de faire
   confiance à ce que la sonde a bien voulu qu'on lui écrive.
   Les octets de contrôle sont remplacés par un espace : les guillemets \uXXXX
   coûteraient six octets là où le libellé n'en a que seize. */
static void jsonTexte(const char *entree, char *sortie, size_t taille) {
  size_t j = 0;
  for (size_t i = 0; entree[i] && j + 2 < taille; i++) {
    unsigned char c = (unsigned char)entree[i];
    if (c == '"' || c == '\\') { sortie[j++] = '\\'; sortie[j++] = (char)c; }
    else if (c < 0x20)           { sortie[j++] = ' '; }
    else                         { sortie[j++] = (char)c; }
  }
  sortie[j] = '\0';
}

/* Même raison, autre langage : un « < » dans le libellé transformerait la page
   de secours en balise ouverte. */
static void htmlTexte(const char *entree, char *sortie, size_t taille) {
  static const char *codes[] = { "&lt;", "&gt;", "&amp;", "&quot;" };
  static const char  bruts[] = { '<', '>', '&', '"' };
  size_t j = 0;
  for (size_t i = 0; entree[i]; i++) {
    const char *remplacement = nullptr;
    for (int k = 0; k < 4; k++) if (entree[i] == bruts[k]) remplacement = codes[k];
    if (remplacement) {
      size_t n = strlen(remplacement);
      if (j + n >= taille) break;
      memcpy(sortie + j, remplacement, n);
      j += n;
    } else {
      if (j + 1 >= taille) break;
      sortie[j++] = entree[i];
    }
  }
  sortie[j] = '\0';
}

/* Une mesure ratée se dit « null » en JSON, pas -32768. */
static const char *centiJson(int16_t centi, char *tampon, size_t taille) {
  if (centi == TEMPERATURE_INVALIDE) return "null";
  snprintf(tampon, taille, "%d", (int)centi);
  return tampon;
}

static void entetesPortail() {
#if TRACE
  trace("portail: requete %s", portail.uri().c_str());
#endif
  /* Sans ça, une page web servie depuis une autre origine — la fiche du petit
     déjeuner publiée sur GitHub Pages, par exemple — ne pourrait pas lire la
     réponse. Une application native n'en a pas besoin, un navigateur si. */
  portail.sendHeader("Access-Control-Allow-Origin", "*");
  portail.sendHeader("Cache-Control", "no-store");
}

static void servirEtat() {
  char nom[16];
  nomSonde(nom, sizeof(nom));

  char tampon[12];
  char lieu[40];                 /* 16 caractères, tous échappés : 32 + marge */
  jsonTexte(rtcNom, lieu, sizeof(lieu));
  char corps[480];
  snprintf(corps, sizeof(corps),
    "{\"version\":%u,"
    "\"sonde\":\"%s\","
    "\"emplacement\":\"%s\","
    "\"centi\":%s,"
    "\"capteur_ok\":%s,"
    "\"pile\":%u,"
    "\"tension_mv\":%u,"
    "\"tics\":%lu,"
    "\"unix_ref\":%lu,"
    "\"intervalle_min\":%u,"
    "\"attente\":%u,"
    "\"offset_centi\":%d,"
    "\"seuil_min_centi\":%d,"
    "\"seuil_max_centi\":%d,"
    "\"drapeaux\":%u,"
    "\"alerte\":%s,"
    "\"pile_faible\":%s,"
    "\"tampon_plein\":%s,"
    "\"reveil_manuel\":%s}",
    (unsigned)VERSION_PROTOCOLE, nom, lieu,
    /* Un capteur muet vaut null, jamais -32768 : un client qui oublierait de
       vérifier tracerait une chambre froide à -327,68 °C. En JSON, l'absence de
       mesure se dit avec le mot du langage. */
    centiJson(rtcDerniere, tampon, sizeof(tampon)),
    rtcDerniere == TEMPERATURE_INVALIDE ? "false" : "true",
    (unsigned)rtcPile, (unsigned)rtcTension,
    (unsigned long)rtcTics, (unsigned long)rtcUnixRef,
    (unsigned)rtcIntervalle, (unsigned)rtcAttente,
    (int)rtcOffset, (int)rtcSeuilMin, (int)rtcSeuilMax,
    (unsigned)rtcDrapeaux,
    (rtcDrapeaux & DRAPEAU_ALERTE_T)      ? "true" : "false",
    (rtcDrapeaux & DRAPEAU_PILE_FAIBLE)   ? "true" : "false",
    (rtcDrapeaux & DRAPEAU_TAMPON_PLEIN)  ? "true" : "false",
    (rtcDrapeaux & DRAPEAU_REVEIL_MANUEL) ? "true" : "false");

  entetesPortail();
  portail.send(200, "application/json", corps);
}

/* L'historique peut faire plusieurs dizaines de milliers d'octets : on
   l'envoie en morceaux plutôt que de le fabriquer entier en mémoire. */
static void servirReleves() {
  char nom[16];
  nomSonde(nom, sizeof(nom));

  entetesPortail();
  portail.setContentLength(CONTENT_LENGTH_UNKNOWN);
  portail.send(200, "application/json", "");

  char tete[200];
  snprintf(tete, sizeof(tete),
    "{\"version\":%u,\"sonde\":\"%s\",\"tics\":%lu,\"nombre\":%u,\"releves\":[",
    (unsigned)VERSION_PROTOCOLE, nom, (unsigned long)rtcTics, (unsigned)rtcAttente);
  portail.sendContent(tete);

  String lot;
  lot.reserve(1024);
  for (uint16_t i = 0; i < rtcAttente; i++) {
    const Releve *r = releveEnAttente(i);
    char tampon[12], ligne[150];
    snprintf(ligne, sizeof(ligne),
      "%s{\"index\":%u,\"tics\":%lu,\"centi\":%s,\"capteur_ok\":%s,"
      "\"pile\":%u,\"drapeaux\":%u}",
      i ? "," : "", (unsigned)i, (unsigned long)r->tics,
      centiJson(r->centi, tampon, sizeof(tampon)),
      r->centi == TEMPERATURE_INVALIDE ? "false" : "true",
      (unsigned)r->pile, (unsigned)r->drapeaux);
    lot += ligne;
    if (lot.length() > 768) { portail.sendContent(lot); lot = ""; }
  }
  if (lot.length()) portail.sendContent(lot);

  portail.sendContent("]}");
  portail.sendContent("");
  trace("portail: %u releves servis", (unsigned)rtcAttente);
}

/* Acquittement. C'est la seule requête qui fait perdre des données à la sonde :
   elle ne doit donc arriver qu'après écriture chez le client. Même contrat
   qu'en Bluetooth (commande 0x03). */
static void servirAcquitter() {
  if (!portail.hasArg("jusqua")) {
    entetesPortail();
    portail.send(400, "application/json", "{\"erreur\":\"jusqua manquant\"}");
    return;
  }
  long jusqua = portail.arg("jusqua").toInt();
  if (jusqua < 0 || jusqua >= (long)rtcAttente) {
    entetesPortail();
    portail.send(409, "application/json", "{\"erreur\":\"index hors des relevés en attente\"}");
    return;
  }

  acquitter((uint16_t)jusqua);

  char corps[80];
  snprintf(corps, sizeof(corps), "{\"acquitte\":true,\"attente\":%u}", (unsigned)rtcAttente);
  entetesPortail();
  portail.send(200, "application/json", corps);

#if PORTAIL_ARRET_APRES_ACQUIT
  /* Le travail est fait : on coupe la radio sans attendre le plafond. C'est ce
     qui rend le portail compatible avec des mois d'autonomie. */
  portailFini = true;
#endif
}

static void servirHeure() {
  if (!portail.hasArg("unix")) {
    entetesPortail();
    portail.send(400, "application/json", "{\"erreur\":\"unix manquant\"}");
    return;
  }
  rtcUnixRef   = (uint32_t)strtoul(portail.arg("unix").c_str(), nullptr, 10);
  rtcDrapeaux |= DRAPEAU_HORLOGE_OK;

  char corps[96];
  snprintf(corps, sizeof(corps), "{\"unix_ref\":%lu,\"tics\":%lu}",
           (unsigned long)rtcUnixRef, (unsigned long)rtcTics);
  entetesPortail();
  portail.send(200, "application/json", corps);
}

static void servirEtalonner() {
  if (!portail.hasArg("centi")) {
    entetesPortail();
    portail.send(400, "application/json", "{\"erreur\":\"centi manquant\"}");
    return;
  }
  long v = portail.arg("centi").toInt();
  if (v < -5000 || v > 5000) {
    entetesPortail();
    portail.send(400, "application/json", "{\"erreur\":\"offset invalide\"}");
    return;
  }
  rtcOffset = (int16_t)v;
  reglagesEnregistrer();

  char corps[64];
  snprintf(corps, sizeof(corps), "{\"offset_centi\":%d}", (int)rtcOffset);
  entetesPortail();
  portail.send(200, "application/json", corps);
}

static void servirProlonger() {
  portailFini  = false;
  portailFinMs = millis() + 300000UL;   /* cinq minutes, comme la commande 0x07 */
  entetesPortail();
  portail.send(200, "application/json", "{\"prolonge_s\":300}");
  trace("portail prolonge");
}

/* Page lisible dans un navigateur. Elle n'est pas là pour faire joli : elle
   permet de vérifier la sonde depuis n'importe quel téléphone, sans aucune
   application — y compris depuis Safari sur iPhone, ce que le Bluetooth web ne
   permettra jamais. */
static void servirAccueil() {
  char nom[16], t[16];
  nomSonde(nom, sizeof(nom));
  centiEnTexte(rtcDerniere, t, sizeof(t));

  String page;
  page.reserve(1600);
  page += F("<!doctype html><meta charset=utf-8>"
            "<meta name=viewport content='width=device-width,initial-scale=1'>"
            "<title>Sonde ");
  page += nom;
  page += F("</title><style>"
            "body{font:16px/1.5 -apple-system,system-ui,sans-serif;margin:0;"
            "padding:24px;background:#f6f6f4;color:#1a1a18}"
            "h1{font-size:1.1rem;margin:0 0 4px}"
            ".t{font-size:3rem;font-weight:600;margin:16px 0 4px}"
            ".a{color:#a4262c}small{color:#6a6a66}"
            "table{border-collapse:collapse;margin-top:20px;width:100%}"
            "td{padding:4px 0;border-bottom:1px solid #e3e3e0}"
            "td+td{text-align:right;font-variant-numeric:tabular-nums}"
            "</style>");
  char lieu[80];
  htmlTexte(rtcNom, lieu, sizeof(lieu));
  page += F("<h1>");
  page += lieu;
  page += F("</h1><small>");
  page += nom;
  page += F("</small><div class='t");
  if (rtcDrapeaux & DRAPEAU_ALERTE_T) page += F(" a");
  page += F("'>");
  page += t;
  page += F(" °C</div>");
  if (rtcDrapeaux & DRAPEAU_ALERTE_T) page += F("<div class=a>Hors des seuils</div>");

  char lignes[560];
  snprintf(lignes, sizeof(lignes),
    "<table>"
    "<tr><td>Pile</td><td>%u %% (%u mV)</td></tr>"
    "<tr><td>Relevés en attente</td><td>%u</td></tr>"
    "<tr><td>Intervalle</td><td>%u min</td></tr>"
    "<tr><td>Seuils</td><td>%d à %d centi-°C</td></tr>"
    "<tr><td>Étalonnage</td><td>%d centi-°C</td></tr>"
    "<tr><td>Horloge interne</td><td>%lu s</td></tr>"
    "</table>",
    (unsigned)rtcPile, (unsigned)rtcTension, (unsigned)rtcAttente,
    (unsigned)rtcIntervalle, (int)rtcSeuilMin, (int)rtcSeuilMax,
    (int)rtcOffset, (unsigned long)rtcTics);
  page += lignes;
  page += F("<p><small>Relevés bruts : <a href=/releves>/releves</a> · "
            "État : <a href=/etat>/etat</a></small>");

  entetesPortail();
  portail.send(200, "text/html; charset=utf-8", page);
}

/* iOS et Android testent tout réseau rejoint en appelant une page connue. Sans
   réponse, iOS affiche « Aucune connexion Internet » et peut quitter le réseau
   au milieu d'une lecture. On répond donc exactement ce qu'il attend.
   La sonde ne prétend pas donner accès à Internet : elle dit que le lien
   fonctionne, ce qui est vrai pour ce qu'on lui demande. */
static void servirInconnu() {
#if PORTAIL_REPONDRE_CAPTIF
  String hote = portail.hostHeader();
  if (hote.indexOf("captive.apple.com") >= 0 ||
      hote.indexOf("connectivitycheck") >= 0 ||
      hote.indexOf("gstatic.com")       >= 0 ||
      hote.indexOf("msftconnecttest")   >= 0) {
    portail.send(200, "text/html",
      F("<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"));
    return;
  }
#endif
  entetesPortail();
  portail.send(404, "application/json", "{\"erreur\":\"inconnu\"}");
}

static void demarrerPortail() {
  char nom[16];
  nomSonde(nom, sizeof(nom));

#if PORTAIL_MODE == PORTAIL_AP
  char ssid[24];
  snprintf(ssid, sizeof(ssid), "SONDE-%s", nom + 6);   /* SONDE-C456 */
  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(ssid, PORTAIL_MDP)) {
    trace("portail: softAP refuse (mot de passe de moins de 8 caracteres ?)");
    WiFi.mode(WIFI_OFF);
    return;
  }
  /* Après softAP() et pas avant : le pilote Wi-Fi doit tourner, sinon le
     réglage est ignoré sans rien dire. */
  WiFi.setTxPower(PUISSANCE_WIFI);
  trace("portail: reseau %s, http://%s", ssid, WiFi.softAPIP().toString().c_str());
#if TRACE
  /* Le démarrage de la radio fait perdre des octets au port série : sans ce
     vidage, la ligne ci-dessus arrive tronquée ou pas du tout, et on croit que
     le portail ne s'est pas ouvert. */
  Serial.flush();
#endif
#else
  WiFi.mode(WIFI_STA);
  WiFi.begin(PORTAIL_SSID, PORTAIL_MDP_STATION);
  WiFi.setTxPower(PUISSANCE_WIFI);
  uint32_t limite = millis() + 12000UL;
  while (WiFi.status() != WL_CONNECTED && (int32_t)(millis() - limite) < 0) delay(150);
  if (WiFi.status() != WL_CONNECTED) {
    trace("portail: %s injoignable", PORTAIL_SSID);
    WiFi.mode(WIFI_OFF);
    return;
  }
  /* « sonde-c456.local » évite d'avoir à connaître l'adresse distribuée par la
     box, qui change à chaque bail DHCP. En minuscules : un nom mDNS est
     insensible à la casse, mais les outils qui l'affichent, non. */
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  char hote[24];
  snprintf(hote, sizeof(hote), "sonde-%02x%02x", mac[4], mac[5]);
  if (MDNS.begin(hote)) MDNS.addService("http", "tcp", 80);
  trace("portail: http://%s.local (%s)", hote, WiFi.localIP().toString().c_str());
#endif

  portail.on("/",           HTTP_GET,  servirAccueil);
  portail.on("/etat",       HTTP_GET,  servirEtat);
  portail.on("/releves",    HTTP_GET,  servirReleves);
  portail.on("/acquitter",  HTTP_POST, servirAcquitter);
  portail.on("/heure",      HTTP_POST, servirHeure);
  portail.on("/etalonner",  HTTP_POST, servirEtalonner);
  portail.on("/prolonger",  HTTP_POST, servirProlonger);
  portail.onNotFound(servirInconnu);
  portail.begin();

  portailOuvert = true;
  portailFini   = false;
}

static void tenirPortail(uint32_t dureeS) {
  if (!portailOuvert) return;
  portailFinMs = millis() + dureeS * 1000UL;

#if TRACE && PORTAIL_MODE == PORTAIL_AP
  /* Savoir où ça casse sans multimètre : un téléphone qui rejoint le réseau
     sans jamais demander de page, ce n'est pas le même défaut qu'un téléphone
     qui ne rejoint rien. */
  uint8_t stationsVues = 0;
#endif

  while (!portailFini && (int32_t)(millis() - portailFinMs) < 0) {
    portail.handleClient();
#if TRACE && PORTAIL_MODE == PORTAIL_AP
    uint8_t n = WiFi.softAPgetStationNum();
    if (n != stationsVues) {
      trace("portail: %u appareil(s) connecte(s) au reseau", (unsigned)n);
      stationsVues = n;
    }
#endif
    delay(2);
  }

  trace(portailFini ? "portail ferme (acquitte)" : "portail ferme (delai)");
  portail.stop();
  /* Le premier argument « true » coupe déjà la radio. Y ajouter un
     WiFi.mode(WIFI_OFF) revenait à éteindre deux fois, et ESP-IDF le disait
     dans la trace :

       E (42849) wifi_init_default: netstack cb reg failed with 12308

     12308, c'est 0x3014, ESP_ERR_WIFI_STOP_STATE — « on ne peut pas arrêter ce
     qui est déjà arrêté ». Sans conséquence, mais une ligne d'erreur rouge
     dans une trace fait douter d'un montage qui marche. */
#if PORTAIL_MODE == PORTAIL_STATION
  MDNS.end();
  WiFi.disconnect(true, true);
#else
  WiFi.softAPdisconnect(true);
#endif
  portailOuvert = false;
}

#endif  /* PORTAIL_WIFI */

/* ============ Veille ============ */

static void dormir(uint32_t secondes) {
  if (secondes < 5) secondes = 5;

  /* Réveil manuel : ILS ou bouton tirant la broche à la masse. Les deux
     familles de puces n'offrent pas la même interface — l'ESP32-C3 réveille
     sur n'importe laquelle de ses GPIO 0 à 5, l'ESP32 classique passe par
     le comparateur ext0 d'une broche RTC. */
#if REVEIL_MANUEL_ACTIF
  #if defined(CONFIG_IDF_TARGET_ESP32C3)
    gpio_set_direction((gpio_num_t)BROCHE_ILS, GPIO_MODE_INPUT);
    gpio_pullup_en((gpio_num_t)BROCHE_ILS);
    gpio_pulldown_dis((gpio_num_t)BROCHE_ILS);
    esp_deep_sleep_enable_gpio_wakeup(1ULL << BROCHE_ILS, ESP_GPIO_WAKEUP_GPIO_LOW);
  #else
    rtc_gpio_pullup_en((gpio_num_t)BROCHE_ILS);
    rtc_gpio_pulldown_dis((gpio_num_t)BROCHE_ILS);
    esp_sleep_enable_ext0_wakeup((gpio_num_t)BROCHE_ILS, 0);   /* 0 = niveau bas */
  #endif
#endif

  esp_sleep_enable_timer_wakeup((uint64_t)secondes * 1000000ULL);

  rtcTics += secondes;
  trace("veille %lu s (tics %lu)", (unsigned long)secondes, (unsigned long)rtcTics);

#if TRACE
  Serial.flush();
#endif
  esp_deep_sleep_start();   /* ne revient jamais : le réveil relance setup() */
}

/* ============ Programme ============ */

void setup() {
#if TRACE
  Serial.begin(115200);
  delay(80);
#endif

  uint32_t debutMs = millis();

  /* Démarrage à froid : piles neuves ou remise à zéro complète. */
  if (rtcMagie != MAGIE) {
    rtcMagie      = MAGIE;
    rtcTete       = 0;
    rtcAttente    = 0;
    rtcTics       = 0;
    rtcProchain   = 0;
    rtcUnixRef    = 0;
    rtcIntervalle = INTERVALLE_MINUTES;
    rtcOffset     = OFFSET_ETALONNAGE_CENTI;
    rtcSeuilMin   = SEUIL_MIN_CENTI;
    rtcSeuilMax   = SEUIL_MAX_CENTI;
    rtcDrapeaux   = 0;
    rtcDerniere   = TEMPERATURE_INVALIDE;
    rtcHorsSeuil  = 0;
    rtcCyclesMuets = 0;
    rtcDerniereAlerte = 0;
    rtcEchecsAlerte   = 0;
    strncpy(rtcNom, EMPLACEMENT, sizeof(rtcNom) - 1);
    rtcNom[sizeof(rtcNom) - 1] = '\0';
    trace("demarrage a froid");

    /* Les valeurs ci-dessus sont celles d'usine. Si la sonde a déjà été
       étalonnée, la flash a le dernier mot : c'est ce qui fait qu'un
       changement de piles ne lui fait pas oublier sa correction. */
    reglagesCharger();
  }

  esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
  bool manuel = (cause == ESP_SLEEP_WAKEUP_GPIO)    /* ESP32-C3 */
             || (cause == ESP_SLEEP_WAKEUP_EXT0);   /* ESP32 classique */
  if (manuel) rtcDrapeaux |= DRAPEAU_REVEIL_MANUEL;
  else        rtcDrapeaux &= ~DRAPEAU_REVEIL_MANUEL;

  /* Mesure de la pile à chaque réveil : elle sert au drapeau, à l'annonce et
     au suivi d'autonomie. */
  rtcTension = lireTensionPile();
  rtcPile    = pourcentagePile(rtcTension);
  if (rtcPile < PILE_FAIBLE_PCT) rtcDrapeaux |= DRAPEAU_PILE_FAIBLE;
  else                           rtcDrapeaux &= ~DRAPEAU_PILE_FAIBLE;

  /* Un réveil manuel mesure aussi — c'est ce qui permet d'étalonner en direct —
     mais ne range un relevé que si la cadence l'appelle. La régularité des
     30 minutes est ainsi préservée quel que soit le nombre de synchronisations. */
  int16_t centi = lireTemperature();
  rtcDerniere = centi;

  if (centi != TEMPERATURE_INVALIDE && (centi < rtcSeuilMin || centi > rtcSeuilMax))
    rtcDrapeaux |= DRAPEAU_ALERTE_T;
  else
    rtcDrapeaux &= ~DRAPEAU_ALERTE_T;

  bool cadence = (rtcTics >= rtcProchain);
  if (cadence) {
    rangerReleve(centi, rtcPile, rtcDrapeaux);
    /* On repart de l'instant courant plutôt que d'accumuler : après un long
       réveil manuel, la cadence ne se met pas à rattraper son retard. */
    rtcProchain = rtcTics + (uint32_t)rtcIntervalle * 60UL;
#if ALERTE_WIFI
    examinerAlertes(centi);
#endif
  }

  /* La température circule en centièmes de degré partout — entiers seulement,
     jamais de virgule flottante. Mais une trace qui affiche « 2750 » se lit mal
     à 18 h sur un établi : on écrit aussi les degrés. */
#if TRACE
  if (centi == TEMPERATURE_INVALIDE) {
    trace("T=capteur muet, pile=%u%% (%u mV), attente=%u, manuel=%d",
          rtcPile, rtcTension, rtcAttente, (int)manuel);
  } else {
    int entier = (centi < 0 ? -centi : centi) / 100;
    int cents  = (centi < 0 ? -centi : centi) % 100;
    trace("T=%s%d,%02d C (%d centi), pile=%u%% (%u mV), attente=%u, manuel=%d",
          centi < 0 ? "-" : "+", entier, cents, centi,
          rtcPile, rtcTension, rtcAttente, (int)manuel);
  }
#endif

  /* Le portail Wi-Fi passe avant le Bluetooth, et coupe complètement sa radio
     avant de rendre la main : les deux piles protocolaires ne cohabitent pas en
     mémoire, et deux radios allumées ensemble, c'est le pic de courant doublé.

     Il ne s'ouvre que sur l'aimant — ou à chaque réveil au banc d'essai, faute
     d'ILS soudé. Jamais sur la simple cadence : ce serait 48 allumages Wi-Fi
     par jour et quelques jours d'autonomie. */
  bool portailAcquitte = false;
#if PORTAIL_WIFI
  if (manuel || PORTAIL_A_CHAQUE_REVEIL) {
    demarrerPortail();
    tenirPortail(PORTAIL_DUREE_S);
    portailAcquitte = portailFini;
  }
#endif

  /* Faut-il parler à ce réveil ? Mesurer ne coûte presque rien, émettre coûte
     tout : on saute des fenêtres pour tenir plus longtemps. Mais jamais quand
     quelqu'un passe l'aimant, ni quand la température sort des clous.

     Sauf si le portail vient de faire le travail : dans ce cas les relevés sont
     partis et acquittés, et ouvrir une fenêtre Bluetooth par-dessus ne servirait
     qu'à consommer. */
  bool annoncer = !portailAcquitte
               && (manuel
                || (rtcDrapeaux & DRAPEAU_ALERTE_T)
                || (ANNONCE_UN_CYCLE_SUR <= 1));

  if (!annoncer && !portailAcquitte) {
    if (cadence && ++rtcCyclesMuets >= ANNONCE_UN_CYCLE_SUR) annoncer = true;
  }
  if (annoncer || portailAcquitte) rtcCyclesMuets = 0;

  if (annoncer) {
    uint32_t fenetre = manuel ? FENETRE_MANUELLE_S : FENETRE_ANNONCE_S;
    demarrerAnnonce();
    tenirFenetre(fenetre);
  } else if (portailAcquitte) {
    trace("pas d'annonce : le portail a deja tout transmis");
  } else {
    trace("pas d'annonce ce cycle (%u/%u)", rtcCyclesMuets, ANNONCE_UN_CYCLE_SUR);
  }

  /* Le temps passé éveillé compte dans l'horloge de la sonde. */
  uint32_t eveilS = (millis() - debutMs + 999) / 1000;
  rtcTics += eveilS;

  uint32_t reste = (rtcProchain > rtcTics) ? (rtcProchain - rtcTics)
                                           : 5;
  dormir(reste);
}

void loop() {
  /* Jamais atteint : setup() se termine toujours par une veille profonde,
     dont le réveil relance le programme depuis le début. */
}
