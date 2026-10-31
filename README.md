# LifeSampler — L'Enregistreur Bruiteur de la Vie (`v1.3.0` — iPhone iOS & Android)

Application mobile **iPhone (iOS)**, **PWA iOS Safari** et **Android** développée en **Flutter** (`cloud.orbital8.personnal_sampler`) transformant votre smartphone en un **enregistreur bruiteur de la vie 16 cases (grille 4×4)**, verrouillé en **mode portrait**, pour capturer les sons du quotidien (rire de bébé, réplique du boss, porte qui grince), les découper, les exporter en `.WAV` et les rejouer à volonté.

---

## 📱 Comment installer et tester LifeSampler sur iPhone (3 méthodes)

### Méthode 1 — Test immédiat sur iPhone sans Mac ni câble (Safari PWA)
1. Ouvrez **Safari** sur votre iPhone et accédez à :
   👉 **`https://orbitalstorm.github.io/personnal-sampler/`**
2. Appuyez sur le bouton **Partager** (icône carré avec flèche vers le haut en bas de Safari).
3. Choisissez **« Sur l'écran d'accueil »** (*Add to Home Screen*) puis appuyez sur **Ajouter**.
4. Lancez **LifeSampler** depuis votre écran d'accueil iPhone : l'application s'ouvre en plein écran natif (mode portrait verrouillé) avec support de la grille 4×4, du microphone iPhone, de l'import audio, des 16 sons Studio 808 et de l'export `.WAV`.

### Méthode 2 — Installation de l'application native `.ipa` sur iPhone (Sideloadly / AltStore / SideStore)
Le fichier **`lifesampler-v1.3.0-ios.ipa`** est compilé automatiquement sur macOS par GitHub Actions et publié dans les [Releases GitHub (`v1.3.0`)](https://github.com/orbitalstorm/personnal-sampler/releases/tag/v1.3.0).
1. Téléchargez **`lifesampler-v1.3.0-ios.ipa`** depuis la page [Release `v1.3.0`](https://github.com/orbitalstorm/personnal-sampler/releases/tag/v1.3.0).
2. Connectez votre iPhone à votre ordinateur (Windows ou Mac) et ouvrez **[Sideloadly](https://sideloadly.io/)** (ou **AltStore** / **SideStore**).
3. Glissez-déposez `lifesampler-v1.3.0-ios.ipa` dans Sideloadly, renseignez votre identifiant Apple (compte gratuit accepté) et cliquez sur **Start**.
4. Sur votre iPhone, allez dans **Réglages > Général > Gestion des appareils et VPN**, validez votre certificat développeur, puis activez le **Mode développeur** (*Réglages > Confidentialité et sécurité > Mode développeur*) si vous êtes sous iOS 16+.
5. Vos sons exportés en `.WAV` sont accessibles directement dans l'application **Fichiers (Files)** de l'iPhone sous **`Sur mon iPhone > LifeSampler > Exports`** ou via **AirDrop**.

### Méthode 3 — Build & Debug direct depuis Xcode sur Mac (`ios/Runner.xcworkspace`)
```bash
git clone https://github.com/orbitalstorm/personnal-sampler.git
cd personnal-sampler
flutter pub get
open ios/Runner.xcworkspace
```
- Dans Xcode, sélectionnez la cible **Runner**, onglet **Signing & Capabilities**, cochez **Automatically manage signing**, choisissez votre **Team** (Personal Team Apple ID gratuit), sélectionnez votre iPhone connecté en USB et cliquez sur **Run (▶)** (`flutter run -d iphone`).

---

## Nouveautés & Philosophie (`v1.3.0`)

1. **Moteur Natif iPhone / iOS (`AVFoundation` Swift) & Android (`SoundPool` / `AudioRecord` Kotlin)** :
   - Enregistrement microphone PCM 16-bit 44.1 kHz (`AVAudioRecorder` sur iOS / `AudioRecord` sur Android) avec VU-mètre temps réel ;
   - Lecture polyphonique basse latence avec modes `CUT`, `POLY`, `LOOP`, Pitch (`0.5×–2.0×`) et Volume (`0–150%`) ;
   - Import de fichiers audio (`UIDocumentPickerViewController` sur iOS / `ACTION_OPEN_DOCUMENT` sur Android) et export `.WAV` vers l'app **Fichiers** iPhone / AirDrop ou `Music/LifeSampler/`.
2. **En-tête Minimaliste sur Fond Noir** :
   - Logo + titre coloré **`LIFESAMPLER`** aligné à gauche sur fond noir sans encadré ni statistique, avec uniquement le picto d'information discret en haut à droite.
3. **Fenêtre « Éditer » Plein Écran Immersif & Protection Anti-Effacement** :
   - **Masquage automatique des barres système** (boutons de navigation Android et Home Indicator iOS) dans l'écran Éditer pour ne jamais masquer le bouton de validation (`VALIDER LA CASE`) ;
   - **Interrupteur contre l'effacement (`Protection anti-effacement`)** activé par défaut lorsqu'on ouvre le menu Éditer après le premier enregistrement d'un pad, bloquant tout écrasement (`MICRO`, `FICHIER AUDIO`) ou suppression (`VIDER`) accidentels ;
   - Capture Microphone ou import de fichier audio avec **`Auto-Trim`** et **`Booster Micro`** sur la même ligne ;
   - Découpe sur **forme d'onde (`Waveform`)**, réglages de mode (`CUT`, `POLY`, `LOOP`), Volume (`0–150%`), Pitch (`0.5×–2.0×`), Nom & Couleur néon ;
   - Bouton **`EXPORTER (.WAV)`** directement intégré dans la fenêtre Éditer.
4. **Priorité aux Sons de la Vie (`Banques A, B & C`) & Banque Studio (`Banque D`)** :
   - **Banques A, B et C (`Vie 1`, `Vie 2`, `Vie 3`)** : 3 banques de 16 pads dédiées à vos propres enregistrements micro et fichiers audio, sans encombrement de console BPM ;
   - **Banque D (`Studio`)** : regroupe les 16 sons synthétisés du Kit Studio 808 ainsi que la **console BPM global (`40–220 BPM`, `TAP`) et le Séquenceur / Looper (`REC SEQ`, `LOOP`)**.

## Captures d'écran validées (iPhone 16 Pro `1179×2556` & Android `1080×2400` Portrait)

- `screenshots/06_iphone_bank_a_life.png` — Vue iPhone 16 Pro (Dynamic Island + Home Indicator) Grille 4×4 Banque A
- `screenshots/07_iphone_edit_pad.png` — Vue iPhone 16 Pro Fenêtre Éditer un pad avec protection anti-effacement active
- `screenshots/01_splash_screen.png` — Splash Screen avec l'illustration cartoon de Leonardo
- `screenshots/02_main_bank_a_life.png` — Grille 4×4 Banque A (Sons de la vie, sans barre BPM)
- `screenshots/03_edit_pad_window.png` — Fenêtre Éditer un pad (`Auto-Trim` + `Booster Micro` sur la même ligne, `EXPORTER (.WAV)` intégré)
- `screenshots/04_bank_d_studio_bpm.png` — Grille 4×4 Banque D (Sons Studio 808 + Console BPM global)
- `screenshots/05_guide_dialog.png` — Fenêtre Guide LifeSampler

## Commandes de développement

```bash
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign
flutter build web --release
flutter build apk --release
```
