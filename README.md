# IPTV Player für iOS – Anleitung für Windows

Werbefrei und kostenlos. Unterstützt **Xtream Codes** (Live-TV, Filme, Serien, EPG), **M3U** und **Downloads zum Offline-Schauen**.

Ablauf: **GitHub** baut die App gratis auf einem Mac in der Cloud → du lädst die fertige `IPTVPlayer.ipa` herunter → **Sideloadly** installiert sie vom PC aufs iPhone.

---

## 1. App bauen lassen (GitHub, einmalig ca. 10 Min.)
1. Kostenloses Konto auf **github.com** anlegen.
2. Oben rechts **+ › New repository** → Name z. B. `iptv-player` → **Create repository**.
   - *Public* = unbegrenzt gratis bauen (der Code ist dann öffentlich sichtbar, deine Zugangsdaten sind NICHT drin).
   - *Private* = geht auch, reicht für ca. 20–30 Builds im Monat.
3. Auf der leeren Repo-Seite: **uploading an existing file** anklicken.
4. Den **Inhalt** des entpackten ZIP-Ordners hineinziehen: die Ordner `IPTVPlayer` und `.github` sowie `project.yml` und `README.md`.
   - Wichtig: der Ordner `.github` muss mit! (Im Explorer ggf. unter *Ansicht › Ausgeblendete Elemente* einblenden.)
5. **Commit changes** drücken.
6. Reiter **Actions** öffnen → der Build „iOS-App bauen (IPA)“ startet automatisch (ca. 5–10 Min.).
7. Grüner Haken → Build anklicken → unten unter **Artifacts** `IPTVPlayer-ipa` herunterladen und entpacken → du hast `IPTVPlayer.ipa`.
   - Roter Haken? Den Fehlertext kopieren und mir schicken, dann fixen wir das.

## 2. Aufs iPhone installieren (Sideloadly)
1. Am PC installieren:
   - **iTunes** und **iCloud** – die Versionen **direkt von apple.com**, nicht aus dem Microsoft Store
   - **Sideloadly** von sideloadly.io
2. iPhone per Kabel anschließen, am iPhone „Diesem Computer vertrauen“ bestätigen.
3. Sideloadly öffnen → `IPTVPlayer.ipa` ins Fenster ziehen → deine **Apple-ID** eintragen → **Start**.
   (Tipp: Viele nehmen dafür eine zweite, eigene Apple-ID.)
4. Am iPhone:
   - **Einstellungen › Datenschutz & Sicherheit › Entwicklermodus** einschalten (iPhone startet neu)
   - **Einstellungen › Allgemein › VPN & Geräteverwaltung** → deine Apple-ID → **Vertrauen**
5. Fertig – die App „IPTV“ ist am Homescreen.

### Wichtig: 7-Tage-Grenze
Mit einer kostenlosen Apple-ID läuft die App **7 Tage**, dann muss sie erneuert werden (Daten und Downloads bleiben erhalten):
- In Sideloadly **„Automatic refresh“** aktivieren → erneuert automatisch über WLAN, wenn der PC an ist.
- Oder alle paar Tage einfach nochmal auf **Start** drücken.
- Dauerhaft (1 Jahr) geht es nur mit dem Apple-Entwicklerkonto (99 €/Jahr).

---

## Funktionen
- **Xtream-Login** → Tabs Live, Filme, Serien, Downloads
- Kategorien-Filter, Suche, Favoriten (nach links wischen oder Stern im Player)
- EPG „Jetzt/Danach“ bei Live-Sendern
- **Downloads**: Film oder Folge öffnen → ↓-Pfeil oben, oder in der Filmliste nach links wischen
  - laufen auch im Hintergrund weiter
  - im Tab „Downloads“ offline abspielen, nach links wischen zum Löschen
  - fehlt das Internet, ist der Downloads-Tab trotzdem nutzbar
- Nativer Apple-Player: Vollbild, AirPlay, Bild-in-Bild
- Zugangsdaten im Schlüsselbund

## Grenzen
- Live-TV kann man nicht herunterladen (es ist ein laufender Stream).
- Der iOS-Player spielt **MP4** und **HLS (.m3u8)**, aber kein **.mkv** oder **.ts**. Ein .mkv-Film lädt zwar herunter, spielt aber noch nicht → nächster Schritt: **VLCKit** einbauen.
- Viele Anbieter erlauben nur 1 Verbindung gleichzeitig: Während ein Download läuft, kann Live-TV deshalb abbrechen.

## Alternativ mit Mac
`brew install xcodegen && xcodegen generate`, dann `IPTVPlayer.xcodeproj` öffnen, unter *Signing* dein Team wählen und ▶︎ drücken.
