#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>

// =====================================================
// WIFI & MQTT CONFIG (SAMA DENGAN FILE 1)
// =====================================================
const char* ssid = "WATON1";
const char* password = "yalalwaton";

const char* mqtt_server = "007d3469a2244841a48f1259a6b6494e.s1.eu.hivemq.cloud";
const int mqtt_port = 8883;
const char* mqtt_user = "Test123";
const char* mqtt_password = "Test1234";

// =====================================================
// SENSOR PIN
// =====================================================
#define PH_PIN          34
#define DO_PIN          35 
#define SUHU_PIN        4

// =====================================================
// RELAY PIN
// =====================================================
#define RELAY_AERATOR_UTAMA     16
#define RELAY_AERATOR_BACKUP    17
#define RELAY_PENGADUK_DOLOMIT  5
#define RELAY_POMPA_DOLOMIT     18
#define RELAY_SOLENOID_IN       19
#define RELAY_SOLENOID_OUT      23

#define RELAY_ON   LOW   
#define RELAY_OFF  HIGH

// =====================================================
// I2C PIN (DARI FILE 1)
// =====================================================
#define SDA_PIN 21
#define SCL_PIN 22

// =====================================================
// I2C LCD CONFIG
// =====================================================
#define LCD_ADDR  0x27  
#define LCD_COLS  20
#define LCD_ROWS   4

// =====================================================
// PH CALIBRATION
// =====================================================
float calibration_value = 21.34 + 0.6;

// =====================================================
// DO SENSOR CALIBRATION & CONFIG
// =====================================================
#define VREF 3300       
#define ADC_RES 4096    

#define TWO_POINT_CALIBRATION 0

#define CAL1_V (922) 
#define CAL1_T (26)  
#define CAL2_V (1300) 
#define CAL2_T (15)   

const uint16_t DO_Table[41] = {
    14460, 14220, 13820, 13440, 13090, 12740, 12420, 12110, 11810, 11530,
    11260, 11010, 10770, 10530, 10300, 10080, 9860, 9660, 9460, 9270,
    9080, 8900, 8730, 8570, 8410, 8250, 8110, 7960, 7820, 7690,
    7560, 7430, 7300, 7180, 7070, 6950, 6840, 6730, 6630, 6530, 6410};

// =====================================================
// THRESHOLD PARAMETER (LOGIKA FILE 2)
// =====================================================
const float SUHU_MIN        = 25.0;
const float SUHU_MAX        = 32.0;

const float DO_KRITIS       =  4.0;
const float DO_RENDAH       =  5.0;
const float DO_HISTERESIS   =  0.3;

const float PH_RENDAH       =  7.0;
const float PH_OPTIMAL_LOW  =  7.5;
const float PH_OPTIMAL_HIGH =  8.0;
const float PH_TINGGI       =  8.5;

const float PH_MIN_VALID    =  0.0;
const float PH_MAX_VALID    = 14.0;
const float DO_MIN_VALID    =  0.0;
const float DO_MAX_VALID    = 20.0;
const float SUHU_MIN_VALID  =  5.0;
const float SUHU_MAX_VALID  = 45.0;

// TIMING PARAMETERS
const unsigned long INTERVAL_SAMPLING_NORMAL  = 60000; // 60 detik
const unsigned long INTERVAL_SAMPLING_KRITIS  = 10000; // 10 detik
const unsigned long INTERVAL_LCD_UPDATE       = 2000;  // 2 detik
const unsigned long TIMEOUT_INJEKSI_KAPUR     = 20000; // Maks pompa ON
const unsigned long TIMEOUT_AGITATOR          = 60000; // Agitator ON
const unsigned long DELAY_STABILISASI         = 900000;// 15 menit stabilisasi
const unsigned long WATCHDOG_ACTUATOR_MAX     = 1800000;// 30 menit cutoff

const int MAX_SENSOR_RETRY = 3;

// =====================================================
// SYSTEM STATE & GLOBAL VARIABLES
// =====================================================
struct SensorData {
  float pH;
  float DO;
  float suhu;
  int   errorCount;
};

struct ActuatorState {
  bool aeratorUtama;
  bool aeratorBackup;
  bool pompaDolomit;
  bool pengadukDolomit;
  bool solenoidIn;
  bool solenoidOut;
  unsigned long aeratorBackupOnTime;
  unsigned long pengadukDolomitOnTime;
  unsigned long pompaDolomitOnTime;
};

SensorData    sensor    = {0, 0, 0, 0};
ActuatorState aktuator  = {false, false, false, false, false, false, 0, 0, 0};

bool autoMode = false;
bool safeMode = false;
bool sedangStabilisasi    = false;
bool injeksiKapurAktif    = false;
bool kondisiKritis        = false;

unsigned long lastSampling   = 0;
unsigned long lastLCDUpdate  = 0;
unsigned long stabilisasiStart = 0;

int  lcdPage = 0; 
char lcdBuf[21];

// =====================================================
// OBJECT LIBRARIES
// =====================================================
OneWire oneWire(SUHU_PIN);
DallasTemperature sensors(&oneWire);

LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);

WiFiClientSecure espClient;
PubSubClient client(espClient);

// =====================================================
// FORWARD DECLARATIONS
// =====================================================
void setup_wifi();
void reconnect();
void callback(char* topic, byte* payload, unsigned int length);
void setAktuator(int pin, bool status, bool &stateVar, const char* nama, const char* mqttTopic = NULL);
void publishRelayStatus(const char* topic, bool state);
void publishModeStatus();
void publishSafeModeStatus();
void publishSystemStatus(String status);
void publishSensor(const char* topic, float value, const char* unit);
void bacaSensor();
float readPH();
float readDO(float currentTempC);
int16_t calculateDO(uint32_t voltage_mv, uint8_t temperature_c);
float readTemperature();
bool validasiSensor(float pH, float DO, float suhu);
void kontrolSuhu();
void kontrolDO();
void kontrolpH();
void injeksiKapur();
void cekWatchdogAktuator();
void activateSafeMode();
void updateLCD();
void printSerial();

// =====================================================
// SETUP
// =====================================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n=== SISTEM BIOFLOK NILA ===");

  analogReadResolution(12);
  sensors.begin();

  // Inisialisasi pin relay (Semua OFF di awal)
  pinMode(RELAY_AERATOR_UTAMA, OUTPUT);    digitalWrite(RELAY_AERATOR_UTAMA, RELAY_OFF);
  pinMode(RELAY_AERATOR_BACKUP, OUTPUT);   digitalWrite(RELAY_AERATOR_BACKUP, RELAY_OFF);
  pinMode(RELAY_PENGADUK_DOLOMIT, OUTPUT); digitalWrite(RELAY_PENGADUK_DOLOMIT, RELAY_OFF);
  pinMode(RELAY_POMPA_DOLOMIT, OUTPUT);    digitalWrite(RELAY_POMPA_DOLOMIT, RELAY_OFF);
  pinMode(RELAY_SOLENOID_IN, OUTPUT);      digitalWrite(RELAY_SOLENOID_IN, RELAY_OFF);
  pinMode(RELAY_SOLENOID_OUT, OUTPUT);     digitalWrite(RELAY_SOLENOID_OUT, RELAY_OFF);

  // Inisialisasi I2C dan LCD
  Wire.begin(SDA_PIN, SCL_PIN);
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("BIOFLOK NILA v2.0");
  lcd.setCursor(0, 1);
  lcd.print("Inisialisasi...");

  setup_wifi();

  espClient.setInsecure();
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);

  // Aerator Utama selalu ON saat startup
  setAktuator(RELAY_AERATOR_UTAMA, true, aktuator.aeratorUtama, "AeratorUtama");
  
  delay(2000);
  lcd.clear();
}

// =====================================================
// MAIN LOOP
// =====================================================
void loop() {
  unsigned long now = millis();

  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  cekWatchdogAktuator();

  // Cek periode stabilisasi pasca-injeksi dolomit
  if (sedangStabilisasi) {
    if (now - stabilisasiStart >= DELAY_STABILISASI) {
      sedangStabilisasi = false;
      Serial.println("[INFO] Stabilisasi selesai. Kembali ke monitoring normal.");
    }
  }

  // Update LCD Handler (Setiap 2 Detik)
  if (now - lastLCDUpdate >= INTERVAL_LCD_UPDATE) {
    lastLCDUpdate = now;
    if (sedangStabilisasi) {
      unsigned long sisaMs = DELAY_STABILISASI - (now - stabilisasiStart);
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("STABILISASI KAPUR");
      lcd.setCursor(0, 1);
      snprintf(lcdBuf, sizeof(lcdBuf), "Sisa: %lu menit", sisaMs / 60000);
      lcd.print(lcdBuf);
    } else if (safeMode) {
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("!! SAFE MODE !!");
      lcd.setCursor(0, 1);
      lcd.print("Cek sensor segera");
      lcd.setCursor(0, 2);
      lcd.print("Aerator ON default");
    } else {
      updateLCD();
    }
  }

  // Jika sistem sedang dalam masa tunggu stabilisasi, lewati pembacaan dan kontrol otomatis
  if (sedangStabilisasi) {
    return;
  }

  // Penentuan interval sampling berdasarkan status kondisi
  unsigned long intervalSampling = kondisiKritis ? INTERVAL_SAMPLING_KRITIS : INTERVAL_SAMPLING_NORMAL;

  if (now - lastSampling >= intervalSampling) {
    lastSampling = now;

    bacaSensor();

    // Validasi Plausibilitas Sensor
    if (!validasiSensor(sensor.pH, sensor.DO, sensor.suhu)) {
      sensor.errorCount++;
      Serial.printf("[WARN] Data sensor tidak valid! Error ke-%d\n", sensor.errorCount);

      if (sensor.errorCount >= MAX_SENSOR_RETRY) {
        Serial.println("[CRIT] Sensor gagal 3x berturut-turut! Masuk SAFE MODE.");
        activateSafeMode();
      }
      return;
    }

    sensor.errorCount = 0;
    safeMode = false;
    publishSafeModeStatus();

    // Publish Telemetri Sensor ke Topik MQTT File 1
    publishSensor("kolam1/sensor/suhu", sensor.suhu, "C");
    publishSensor("kolam1/sensor/ph", sensor.pH, "pH");
    publishSensor("kolam1/sensor/do", sensor.DO, "mg/L");
    printSerial();

    kondisiKritis = false;
    
    // Eksekusi Logika Otomasi (Hanya Berjalan Jika Mode AUTO Aktif)
    if (autoMode) {
      kontrolSuhu();
      kontrolDO();
      kontrolpH();
    }

    // Publish System Status Ke Topik MQTT File 1
    if (safeMode) {
      publishSystemStatus("SAFE_MODE");
    } else if (sensor.DO < 4.0) {
      publishSystemStatus("LOW_DO");
    } else if (sensor.pH < 7.0) {
      publishSystemStatus("LOW_PH");
    } else if (sensor.pH > 8.0) {
      publishSystemStatus("HIGH_PH");
    } else if (injeksiKapurAktif) {
      publishSystemStatus("DOSING");
    } else {
      publishSystemStatus("NORMAL");
    }
  }
}

// =====================================================
// READ SENSORS
// =====================================================
void bacaSensor() {
  sensor.suhu = readTemperature();
  sensor.DO   = readDO(sensor.suhu);
  sensor.pH   = readPH();
}

float readPH() {
  const int samples = 10;
  float total = 0;
  for (int i = 0; i < samples; i++) {
    int adcValue = analogRead(PH_PIN);
    float voltage = adcValue * (3.3 / 4095.0);
    float phValue = calibration_value - (voltage * 5.70);
    total += phValue;
    delay(20);
  }
  return total / samples;
}

int16_t calculateDO(uint32_t voltage_mv, uint8_t temperature_c) {
#if TWO_POINT_CALIBRATION == 0
  uint16_t V_saturation = (uint32_t)CAL1_V + (uint32_t)35 * temperature_c - (uint32_t)CAL1_T * 35;
  return (voltage_mv * DO_Table[temperature_c] / V_saturation);
#else
  uint16_t V_saturation = (int16_t)((int8_t)temperature_c - CAL2_T) * ((uint16_t)CAL1_V - CAL2_V) / ((uint8_t)CAL1_T - CAL2_T) + CAL2_V;
  return (voltage_mv * DO_Table[temperature_c] / V_saturation);
#endif
}

float readDO(float currentTempC) {
  if (currentTempC == DEVICE_DISCONNECTED_C || isnan(currentTempC)) {
    currentTempC = 26.0;
  }
  
  uint8_t Temperaturet = (uint8_t)currentTempC;
  const int samples = 10;
  uint32_t totalVoltage = 0;

  for (int i = 0; i < samples; i++) {
    int adcValue = analogRead(DO_PIN);
    uint32_t ADC_Voltage = uint32_t(VREF) * adcValue / ADC_RES;
    totalVoltage += ADC_Voltage;
    delay(20);
  }
  
  uint32_t avgVoltage = totalVoltage / samples;
  float doValue = calculateDO(avgVoltage, Temperaturet) / 1000.0;
  return doValue;
}

float readTemperature() {
  const int samples = 3;
  float total = 0;
  for (int i = 0; i < samples; i++) {
    sensors.requestTemperatures();
    float temp = sensors.getTempCByIndex(0);
    total += temp;
    delay(100);
  }
  return total / samples;
}

// =====================================================
// KONTROL LOGIC & VALIDATION
// =====================================================
bool validasiSensor(float pH, float DO, float suhu) {
  bool valid = true;
  if (pH   < PH_MIN_VALID   || pH   > PH_MAX_VALID)   { valid = false; }
  if (DO   < DO_MIN_VALID   || DO   > DO_MAX_VALID)   { valid = false; }
  if (suhu < SUHU_MIN_VALID || suhu > SUHU_MAX_VALID) { valid = false; }
  return valid;
}

void kontrolSuhu() {
  if (sensor.suhu < SUHU_MIN || sensor.suhu > SUHU_MAX) {
    kondisiKritis = true;
  }
}

void kontrolDO() {
  if (sensor.DO < DO_RENDAH) {
    kondisiKritis = true;
    if (!aktuator.aeratorBackup) {
      setAktuator(RELAY_AERATOR_BACKUP, true, aktuator.aeratorBackup, "AeratorBackup", "kolam1/status/aerator_backup");
      aktuator.aeratorBackupOnTime = millis();
    }
  } else if (sensor.DO >= (DO_RENDAH + DO_HISTERESIS)) {
    if (aktuator.aeratorBackup) {
      setAktuator(RELAY_AERATOR_BACKUP, false, aktuator.aeratorBackup, "AeratorBackup", "kolam1/status/aerator_backup");
    }
  }
}

void kontrolpH() {
  if (sensor.pH < PH_RENDAH) {
    kondisiKritis = true;
    
    if (sensor.DO <= DO_KRITIS) {
      Serial.println("[WARN] DO terlalu rendah! Injeksi kapur dolomit ditunda.");
      return;
    }
    injeksiKapur();

  } else if (sensor.pH > PH_TINGGI) {
    kondisiKritis = true;
  }
}

void injeksiKapur() {
  if (injeksiKapurAktif) return;
  injeksiKapurAktif = true;

  float defisitpH = PH_OPTIMAL_LOW - sensor.pH;
  unsigned long durasiPompa = (unsigned long)(defisitpH * 50000);
  durasiPompa = constrain(durasiPompa, 5000, TIMEOUT_INJEKSI_KAPUR);

  Serial.println("[AKSI] Memulai prosedur injeksi kapur dolomit...");
  
  // Langkah 1: Nyalakan agitator (aerator pengaduk) selama 60 detik
  setAktuator(RELAY_PENGADUK_DOLOMIT, true, aktuator.pengadukDolomit, "PengadukDolomit", "kolam1/status/pengaduk_dolomit");
  delay(TIMEOUT_AGITATOR);

  // Langkah 2: Jalankan pompa dolomit sesuai durasi proporsional
  setAktuator(RELAY_POMPA_DOLOMIT, true, aktuator.pompaDolomit, "PompaDolomit", "kolam1/status/pompa_dolomit");
  aktuator.pompaDolomitOnTime = millis();
  delay(durasiPompa);

  // Langkah 3: Matikan pompa dan agitator
  setAktuator(RELAY_POMPA_DOLOMIT, false, aktuator.pompaDolomit, "PompaDolomit", "kolam1/status/pompa_dolomit");
  setAktuator(RELAY_PENGADUK_DOLOMIT, false, aktuator.pengadukDolomit, "PengadukDolomit", "kolam1/status/pengaduk_dolomit");

  // Langkah 4: Aktifkan aerator backup untuk membantu pencampuran air kolam
  setAktuator(RELAY_AERATOR_BACKUP, true, aktuator.aeratorBackup, "AeratorBackup(Mixing)", "kolam1/status/aerator_backup");
  aktuator.aeratorBackupOnTime = millis();

  // Langkah 5: Masuk ke periode tunggu stabilisasi air kolam
  sedangStabilisasi  = true;
  stabilisasiStart   = millis();
  injeksiKapurAktif  = false;
}

// =====================================================
// UTILS & SAFETY FUNCTIONS
// =====================================================
void setAktuator(int pin, bool status, bool &stateVar, const char* nama, const char* mqttTopic) {
  if (stateVar == status) return;
  digitalWrite(pin, status ? RELAY_ON : RELAY_OFF);
  stateVar = status;
  Serial.printf("[RELAY] %s → %s\n", nama, status ? "ON" : "OFF");
  if (mqttTopic != NULL) {
    publishRelayStatus(mqttTopic, status);
  }
}

void cekWatchdogAktuator() {
  unsigned long now = millis();

  if (aktuator.aeratorBackup && (now - aktuator.aeratorBackupOnTime > WATCHDOG_ACTUATOR_MAX)) {
    setAktuator(RELAY_AERATOR_BACKUP, false, aktuator.aeratorBackup, "AeratorBackup", "kolam1/status/aerator_backup");
  }
  if (aktuator.pompaDolomit && (now - aktuator.pompaDolomitOnTime > WATCHDOG_ACTUATOR_MAX)) {
    setAktuator(RELAY_POMPA_DOLOMIT, false, aktuator.pompaDolomit, "PompaDolomit", "kolam1/status/pompa_dolomit");
  }
  if (aktuator.pengadukDolomit && (now - aktuator.pengadukDolomitOnTime > 300000)) {
    setAktuator(RELAY_PENGADUK_DOLOMIT, false, aktuator.pengadukDolomit, "PengadukDolomit", "kolam1/status/pengaduk_dolomit");
  }
}

void activateSafeMode() {
  safeMode = true;
  Serial.println("SAFE MODE ACTIVE");
  
  setAktuator(RELAY_AERATOR_BACKUP, true, aktuator.aeratorBackup, "AeratorBackup", "kolam1/status/aerator_backup");
  
  setAktuator(RELAY_PENGADUK_DOLOMIT, false, aktuator.pengadukDolomit, "PengadukDolomit", "kolam1/status/pengaduk_dolomit");
  setAktuator(RELAY_POMPA_DOLOMIT, false, aktuator.pompaDolomit, "PompaDolomit", "kolam1/status/pompa_dolomit");
  setAktuator(RELAY_SOLENOID_IN, false, aktuator.solenoidIn, "SolenoidIn", "kolam1/status/solenoid_in");
  setAktuator(RELAY_SOLENOID_OUT, false, aktuator.solenoidOut, "SolenoidOut", "kolam1/status/solenoid_out");

  publishSafeModeStatus();
  publishSystemStatus("SAFE_MODE");
}

// =====================================================
// I2C LCD ROTATION MENU
// =====================================================
void updateLCD() {
  lcd.clear();
  switch (lcdPage) {
    case 0: 
      lcd.setCursor(0, 0);
      lcd.print("=== SENSOR DATA ===");
      snprintf(lcdBuf, sizeof(lcdBuf), "pH  : %.2f", sensor.pH);
      lcd.setCursor(0, 1); lcd.print(lcdBuf);
      snprintf(lcdBuf, sizeof(lcdBuf), "DO  : %.2f mg/L", sensor.DO);
      lcd.setCursor(0, 2); lcd.print(lcdBuf);
      snprintf(lcdBuf, sizeof(lcdBuf), "Suhu: %.1f C", sensor.suhu);
      lcd.setCursor(0, 3); lcd.print(lcdBuf);
      break;

    case 1: 
      lcd.setCursor(0, 0); lcd.print("=== STATUS AIR ===");
      lcd.setCursor(0, 1);
      lcd.print(sensor.pH < PH_RENDAH ? "pH: RENDAH <7.0" :
                sensor.pH > PH_TINGGI ? "pH: TINGGI >8.5" : "pH: NORMAL OK");
      lcd.setCursor(0, 2);
      lcd.print(sensor.DO < DO_RENDAH ? "DO: RENDAH <5.0" : "DO: NORMAL OK");
      lcd.setCursor(0, 3);
      lcd.print(kondisiKritis ? "!! KONDISI KRITIS !!" : "Semua Parameter OK");
      break;

    case 2: 
      lcd.setCursor(0, 0); lcd.print("=== AKTUATOR ===");
      snprintf(lcdBuf, sizeof(lcdBuf), "Utm:%s Bkp:%s",
               aktuator.aeratorUtama ? "ON " : "OFF",
               aktuator.aeratorBackup ? "ON " : "OFF");
      lcd.setCursor(0, 1); lcd.print(lcdBuf);
      snprintf(lcdBuf, sizeof(lcdBuf), "Pmp:%s Agt:%s",
               aktuator.pompaDolomit  ? "ON " : "OFF",
               aktuator.pengadukDolomit ? "ON " : "OFF");
      lcd.setCursor(0, 2); lcd.print(lcdBuf);
      snprintf(lcdBuf, sizeof(lcdBuf), "SolI:%s SolO:%s",
               aktuator.solenoidIn  ? "ON " : "OFF",
               aktuator.solenoidOut ? "ON " : "OFF");
      lcd.setCursor(0, 3); lcd.print(lcdBuf);
      break;

    case 3: 
      lcd.setCursor(0, 0);
      lcd.print("=== KONEKSI MENU ===");
      snprintf(lcdBuf, sizeof(lcdBuf), "WiFi: %s", WiFi.status() == WL_CONNECTED ? "OK" : "PUTUS");
      lcd.setCursor(0, 1); lcd.print(lcdBuf);
      snprintf(lcdBuf, sizeof(lcdBuf), "MQTT: %s", client.connected() ? "OK" : "PUTUS");
      lcd.setCursor(0, 2); lcd.print(lcdBuf);
      snprintf(lcdBuf, sizeof(lcdBuf), "Mode: %s", autoMode ? "AUTO" : "MANUAL");
      lcd.setCursor(0, 3); lcd.print(lcdBuf);
      break;
  }

  static int updateCount = 0;
  updateCount++;
  if (updateCount >= 4) { // Rotasi halaman setiap 8 detik (4 * 2 detik)
    updateCount = 0;
    lcdPage = (lcdPage + 1) % 4;
  }
}

// =====================================================
// MQTT FUNCTIONS
// =====================================================
void publishRelayStatus(const char* topic, bool state) {
  StaticJsonDocument<200> doc;
  doc["state"] = state;
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish(topic, buffer, true);
}

void publishModeStatus() {
  StaticJsonDocument<200> doc;
  doc["mode"] = autoMode ? "AUTO" : "MANUAL";
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish("kolam1/status/mode", buffer, true);
}

void publishSafeModeStatus() {
  StaticJsonDocument<200> doc;
  doc["safe_mode"] = safeMode;
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish("kolam1/status/safe_mode", buffer, true);
}

void publishSystemStatus(String status) {
  StaticJsonDocument<200> doc;
  doc["status"] = status;
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish("kolam1/status/system", buffer, true);
  
  Serial.print("SYSTEM STATUS : ");
  Serial.println(status);
}

void publishSensor(const char* topic, float value, const char* unit) {
  StaticJsonDocument<200> doc;
  doc["value"] = value;
  doc["unit"] = unit;
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish(topic, buffer, true);
}

void callback(char* topic, byte* payload, unsigned int length) {
  String message;
  for (int i = 0; i < length; i++) {
    message += (char)payload[i];
  }

  StaticJsonDocument<200> doc;
  DeserializationError error = deserializeJson(doc, message);
  if (error) return;

  if (String(topic) == "kolam1/system/mode") {
    String mode = doc["mode"];
    autoMode = (mode == "AUTO");
    publishModeStatus();
    return;
  }

  // Kendali Manual dari MQTT Dashboard (Hanya aktif jika !autoMode dan !safeMode)
  if (!autoMode && !safeMode) {
    bool state = doc["state"];
    
    if (String(topic) == "kolam1/control/aerator_backup") {
      setAktuator(RELAY_AERATOR_BACKUP, state, aktuator.aeratorBackup, "AeratorBackup", "kolam1/status/aerator_backup");
    }
    if (String(topic) == "kolam1/control/pengaduk_dolomit") {
      setAktuator(RELAY_PENGADUK_DOLOMIT, state, aktuator.pengadukDolomit, "PengadukDolomit", "kolam1/status/pengaduk_dolomit");
    }
    if (String(topic) == "kolam1/control/pompa_dolomit") {
      setAktuator(RELAY_POMPA_DOLOMIT, state, aktuator.pompaDolomit, "PompaDolomit", "kolam1/status/pompa_dolomit");
    }
  }
}

void reconnect() {
  while (!client.connected()) {
    String clientId = "ESP32_KOLAM_";
    clientId += String(random(0xffff), HEX);

    if (client.connect(clientId.c_str(), mqtt_user, mqtt_password)) {
      client.subscribe("kolam1/control/#");
      client.subscribe("kolam1/system/#");
      publishModeStatus();
      publishSafeModeStatus();
    } else {
      delay(5000);
    }
  }
}

void setup_wifi() {
  delay(10);
  Serial.println();
  Serial.print("Connecting WiFi: ");
  Serial.println(ssid);

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected");
  Serial.println(WiFi.localIP());
}

void printSerial() {
  Serial.println("------------------------------------");
  Serial.printf("  pH   : %.2f\n", sensor.pH);
  Serial.printf("  DO   : %.2f mg/L\n", sensor.DO);
  Serial.printf("  Suhu : %.1f °C\n", sensor.suhu);
  Serial.printf("  Kritis: %s\n", kondisiKritis ? "Ya" : "Tidak");
  Serial.println("------------------------------------");
}
