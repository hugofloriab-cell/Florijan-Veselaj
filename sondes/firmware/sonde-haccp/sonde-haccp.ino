/* sonde-haccp — enregistreur de température autonome pour la check-list
 * petit déjeuner de l'Hôtel Ibis Sisteron.
 *
 * Carte    : Seeed XIAO ESP32C3 (ou tout module ESP32-C3)
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

#if ALERTE_WIFI
  #include <WiFi.h>
  #include <HTTPClient.h>
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
RTC_DATA_ATTR static uint32_t rtcDerniereAlerte = 0;

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

/* ============ Mesures ============ */

/* Le DS18B20 est alimenté par une broche : hors mesure il ne consomme rien,
   pas même son microampère de veille. */
static int16_t lireTemperature() {
  pinMode(BROCHE_CAPTEUR_VCC, OUTPUT);
  digitalWrite(BROCHE_CAPTEUR_VCC, HIGH);
  delay(12);                       /* le capteur a besoin de se stabiliser */

  capteur.begin();
  capteur.setResolution(12);       /* 0,0625 °C, conversion 750 ms */
  capteur.requestTemperatures();
  float c = capteur.getTempCByIndex(0);

  digitalWrite(BROCHE_CAPTEUR_VCC, LOW);
  pinMode(BROCHE_CAPTEUR_VCC, INPUT);

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
  pinMode(BROCHE_PONT, OUTPUT);
  digitalWrite(BROCHE_PONT, HIGH);
  analogSetPinAttenuation(BROCHE_PILE, ADC_11db);
  delay(3);                        /* charge du condensateur de filtrage */

  uint32_t somme = 0;
  for (int i = 0; i < 8; i++) { somme += analogReadMilliVolts(BROCHE_PILE); delay(1); }

  digitalWrite(BROCHE_PONT, LOW);
  pinMode(BROCHE_PONT, INPUT);

  return (uint16_t)((somme / 8.0f) * PONT_RAPPORT);
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

class RappelsServeur : public BLEServerCallbacks {
  void onConnect(BLEServer *s) override {
    connecte = true;
    /* Tant qu'une tablette est là, on ne repart pas en veille. */
    finFenetreMs = millis() + 60000UL;
    trace("connecte");
  }
  void onDisconnect(BLEServer *s) override {
    connecte = false;
    /* Petite fenêtre de repêchage : une déconnexion accidentelle en pleine
       synchronisation ne doit pas obliger à attendre 30 minutes. */
    finFenetreMs = millis() + 20000UL;
    BLEDevice::startAdvertising();
    trace("deconnecte");
  }
  void onMtuChanged(BLEServer *s, esp_ble_gatts_cb_param_t *param) {
    mtu = param->mtu.mtu;
    trace("mtu %u", mtu);
  }
};

class RappelsCommande : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
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
        }
        break;

      case 0x05:                                   /* offset d'étalonnage */
        if (n >= 3) rtcOffset = (int16_t)lireU16(d + 1);
        break;

      case 0x06:                                   /* seuils d'alerte */
        if (n >= 5) {
          rtcSeuilMin = (int16_t)lireU16(d + 1);
          rtcSeuilMax = (int16_t)lireU16(d + 3);
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

/* ============ Alerte Wi-Fi ============ */

#if ALERTE_WIFI
/* N'allume le Wi-Fi que pour une alerte réelle. En marche normale, la radio
   Wi-Fi n'est jamais alimentée : elle ne coûte rien. */
static void pousserAlerte(const char *titre, const char *corps, const char *priorite) {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_MDP);

  uint32_t debut = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - debut < 15000UL) delay(150);

  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin("https://ntfy.sh/" NTFY_SUJET);
    http.addHeader("Title", titre);
    http.addHeader("Priority", priorite);
    http.addHeader("Tags", "warning,thermometer");
    http.POST((uint8_t *)corps, strlen(corps));
    http.end();
    trace("alerte poussee");
  } else {
    trace("wifi indisponible");
  }

  WiFi.disconnect(true, true);
  WiFi.mode(WIFI_OFF);
}

static void examinerAlertes(int16_t centi) {
  bool horsSeuil = (centi != TEMPERATURE_INVALIDE) &&
                   (centi < rtcSeuilMin || centi > rtcSeuilMax);

  if (horsSeuil) { if (rtcHorsSeuil < 255) rtcHorsSeuil++; }
  else           { rtcHorsSeuil = 0; }

  bool repos = (rtcDerniereAlerte != 0) &&
               (rtcTics - rtcDerniereAlerte < (uint32_t)ALERTE_REPOS_MINUTES * 60UL);
  if (repos) return;

  char corps[160];

  if (rtcHorsSeuil >= ALERTE_MESURES_CONSECUTIVES) {
    snprintf(corps, sizeof(corps),
             "%s : %.1f C depuis %u releves (seuils %.1f a %.1f C). Verifier l'enceinte.",
             rtcNom, centi / 100.0f, rtcHorsSeuil,
             rtcSeuilMin / 100.0f, rtcSeuilMax / 100.0f);
    pousserAlerte("Temperature non conforme", corps, "urgent");
    rtcDerniereAlerte = rtcTics;
    return;
  }

  if (rtcPile < PILE_FAIBLE_PCT) {
    snprintf(corps, sizeof(corps),
             "%s : pile a %u%% (%u mV). Prevoir le remplacement des piles.",
             rtcNom, rtcPile, rtcTension);
    pousserAlerte("Pile de sonde faible", corps, "default");
    rtcDerniereAlerte = rtcTics;
  }
}
#endif

/* ============ Veille ============ */

static void dormir(uint32_t secondes) {
  if (secondes < 5) secondes = 5;

  /* Réveil manuel : ILS ou bouton tirant la broche à la masse. Seules les
     GPIO 0 à 5 en sont capables sur l'ESP32-C3. */
  gpio_set_direction((gpio_num_t)BROCHE_ILS, GPIO_MODE_INPUT);
  gpio_pullup_en((gpio_num_t)BROCHE_ILS);
  gpio_pulldown_dis((gpio_num_t)BROCHE_ILS);
  esp_deep_sleep_enable_gpio_wakeup(1ULL << BROCHE_ILS, ESP_GPIO_WAKEUP_GPIO_LOW);

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
    rtcDerniereAlerte = 0;
    strncpy(rtcNom, EMPLACEMENT, sizeof(rtcNom) - 1);
    rtcNom[sizeof(rtcNom) - 1] = '\0';
    trace("demarrage a froid");
  }

  bool manuel = (esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_GPIO);
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

  trace("T=%d centi, pile=%u%% (%u mV), attente=%u, manuel=%d",
        centi, rtcPile, rtcTension, rtcAttente, (int)manuel);

  /* Fenêtre radio : longue si quelqu'un a passé l'aimant, courte sinon. */
  uint32_t fenetre = manuel ? FENETRE_MANUELLE_S : FENETRE_ANNONCE_S;
  demarrerAnnonce();
  tenirFenetre(fenetre);

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
