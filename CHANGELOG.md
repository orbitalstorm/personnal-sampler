# Changelog — LifeSampler (`cloud.orbital8.personnal_sampler`)

Toutes les modifications notables de ce projet sont documentées dans ce fichier.
Respect strict du versionning `v1.x.y` (numérotation unique, aucun numéro réutilisé).

---

## [v1.1.0] - 2026-10-30 (ORB-32)

### Ajouté & Modifié
- **Rebranding complet en `LifeSampler` (« L'enregistreur bruiteur de la vie »)** :
  - Positionnement centré sur la capture et le déclenchement des sons du quotidien pour le plaisir et le fun (rire de bébé, réplique du boss, porte qui grince, bruitages maison).
  - **Splash Screen de démarrage** affichant le nom `LifeSampler`, le manifeste du projet et une **illustration cartoon originale générée par Leonardo** (`assets/images/lifesampler_splash_cartoon.png`) ainsi que les nouvelles icônes Android (`mipmap-*`).
- **Verrouillage strict en mode Portrait uniquement** :
  - Désactivation de la rotation paysage au niveau natif Android (`android:screenOrientation="portrait"` dans `AndroidManifest.xml`) et au niveau Flutter (`SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])`).
- **Réorganisation des Banques (`BANK A`, `B`, `C` : Vie • `BANK D` : Studio)** :
  - Les **Banques A, B et C** (`Vie 1`, `Vie 2`, `Vie 3`) sont dédiées à l'enregistrement des sons personnels au microphone ou par import audio.
  - Les **16 sons synthétisés Studio 808** (*Kick, Snare, Hi-Hat...*) sont déplacés sur la **Banque D (`Studio`)**.
  - La **console de BPM global (`40–220 BPM`, `TAP`) et le Séquenceur / Looper (`REC SEQ`, `LOOP`)** s'affichent **uniquement sur la Banque D (`Studio`)**, épurant l'écran principal sur les Banques A, B et C.
- **Refonte de la Fenêtre « Éditer » (`PadAssignmentSheet`)** :
  - **Suppression des pré-réglages de sons Studio** dans la fenêtre Éditer afin d'éviter tout écrasement accidentel d'un son fraîchement enregistré.
  - **Regroupement des boutons `Auto-Trim` et `Booster Micro` sur la même ligne** dans la section de capture.
  - **Bouton `EXPORTER (.WAV)` intégré directement dans la fenêtre Éditer** (export dans `Music/LifeSampler/`).
- **Validation Qualité UI/UX sur Émulateur Portrait (`1080×2400`)** :
  - Captures des 5 écrans clés (`screenshots/01_splash_screen.png` à `05_guide_dialog.png`) et audit par le Spécialiste UI/UX (alignement des boutons, lisibilité et concision des textes sans troncature).

---

## [v1.0.0] - 2026-10-30 (ORB-30)

### Ajouté
- **Grille de Sampleur Mobile 4×4 (`16 Cases` — `PAD 01` à `PAD 16`)** :
  - Affichage plein écran sans défilement de 16 pads lumineux réactifs permettant de jouer et rejouer chaque son autant de fois que souhaité (`Multi-Trigger` / `Retrigger` sans latence via `SoundPool` Android 32 voix + fallback `MediaPlayer`).
- **Bouton `RECORD` d'Assignation Audio (Microphone ou Fichier WAV / Audio)** :
  - **Enregistrement Microphone en direct (`AudioRecord` PCM 16-bit 44.1 kHz)** avec VU-mètre temps réel, chronomètre et gestion dynamique de la permission `RECORD_AUDIO`.
  - **Import de fichier WAV / Audio depuis l'appareil (`Intent.ACTION_OPEN_DOCUMENT`)** compatible `.wav`, `.mp3`, `.m4a`, `.aac`, `.ogg`.
  - **Kit Studio 808 intégré (`16 instruments synthétisés en pur Dart`)** (*Kick 808, Snare, Clap, Closed Hat, Open Hat, Tom Low, Tom Mid, Rimshot, Cowbell, Crash, Sub Bass, Acid 303, Chord Min, Stab Maj, Laser FX, Siren FX*).
- **Fonctionnalités Essentielles Analysées & Implémentées** :
  - **Auto-Trim du silence initial au micro & Normalisation automatique** : coupe automatiquement le blanc au début de la prise micro pour garantir une attaque à `0 ms` de latence et normalise le niveau sonore.
  - **Éditeur de Forme d'Onde (`Waveform`) & Découpe Non-Destructive (`Trim Début / Fin`)** : visualisation sur 32 barres sur chaque case et curseur double `RangeSlider` avec fondu anti-clic de 3 ms.
  - **3 Modes de Déclenchement par Case (`CUT`, `POLY`, `LOOP`) + Bouton `STOP` (Panic)** :
    - `CUT` (*Retrigger*) : coupe proprement la lecture précédente de la case à chaque nouvel appui ;
    - `POLY` (*One-Shot*) : superpose librement les frappes rapides ;
    - `LOOP` (*Boucle*) : maintient l'échantillon en boucle continue jusqu'au prochain appui.
  - **Réglages Audio par Case** : Volume individuel (`0%` à `150%`), Pitch / Vitesse (`0.50×` à `2.00×`), Nom personnalisé, Couleur Néon (16 teintes) et Export en `.wav`.
  - **4 Banques Persistées (`BANK A` à `BANK D`)** : sauvegarde automatique JSON + fichiers `.wav` sur l'appareil.
  - **Métronome (`40–220 BPM` + `TAP TEMPO`) & Séquenceur / Looper Live (`REC SEQ` / `LOOP`)**.
