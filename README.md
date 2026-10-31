# LifeSampler — L'Enregistreur Bruiteur de la Vie (`v1.2.0`)

Application mobile Android développée en **Flutter** (`cloud.orbital8.personnal_sampler`) transformant votre smartphone en un **enregistreur bruiteur de la vie 16 cases (grille 4×4)**, verrouillé en **mode portrait**, pour capturer les sons du quotidien (rire de bébé, réplique du boss, porte qui grince), les découper, les exporter en `.WAV` et les rejouer à volonté.

## Nouveautés & Philosophie (`v1.2.0`)

1. **En-tête Minimaliste sur Fond Noir** :
   - Logo + titre coloré **`LIFESAMPLER`** aligné à gauche sur fond noir sans encadré ni statistique, avec uniquement le picto d'information discret en haut à droite.
2. **Fenêtre « Éditer » Plein Écran Immersif & Protection Anti-Effacement** :
   - **Masquage automatique des boutons de navigation Android** (*Home, Retour, Récents*) dans l'écran Éditer pour ne jamais masquer le bouton de validation (`VALIDER LA CASE`) ;
   - **Interrupteur contre l'effacement (`Protection anti-effacement`)** activé par défaut lorsqu'on ouvre le menu Éditer après le premier enregistrement d'un pad, bloquant tout écrasement (`MICRO`, `FICHIER AUDIO`) ou suppression (`VIDER`) accidentels ;
   - Capture Microphone PCM 16-bit 44.1 kHz ou import de fichier audio avec **`Auto-Trim`** et **`Booster Micro`** sur la même ligne ;
   - Découpe sur **forme d'onde (`Waveform`)**, réglages de mode (`CUT`, `POLY`, `LOOP`), Volume (`0–150%`), Pitch (`0.5×–2.0×`), Nom & Couleur néon ;
   - Bouton **`EXPORTER (.WAV)`** directement intégré dans la fenêtre Éditer (`Music/LifeSampler/`).
3. **Priorité aux Sons de la Vie (`Banques A, B & C`) & Banque Studio (`Banque D`)** :
   - **Banques A, B et C (`Vie 1`, `Vie 2`, `Vie 3`)** : 3 banques de 16 pads dédiées à vos propres enregistrements micro et fichiers audio, sans encombrement de console BPM ;
   - **Banque D (`Studio`)** : regroupe les 16 sons synthétisés du Kit Studio 808 ainsi que la **console BPM global (`40–220 BPM`, `TAP`) et le Séquenceur / Looper (`REC SEQ`, `LOOP`)**.

## Captures d'écran validées (`1080×2400` Portrait)

- `screenshots/01_splash_screen.png` — Splash Screen avec l'illustration cartoon de Leonardo
- `screenshots/02_main_bank_a_life.png` — Grille 4×4 Banque A (Sons de la vie, sans barre BPM)
- `screenshots/03_edit_pad_window.png` — Fenêtre Éditer un pad (`Auto-Trim` + `Booster Micro` sur la même ligne, `EXPORTER (.WAV)` intégré, sans presets studio)
- `screenshots/04_bank_d_studio_bpm.png` — Grille 4×4 Banque D (Sons Studio 808 + Console BPM global)
- `screenshots/05_guide_dialog.png` — Fenêtre Guide LifeSampler

## Commandes de développement

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
