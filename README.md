# PulsePad 16 — Personal Sampler 4×4 (`v1.0.0`)

Application mobile Android développée en **Flutter** (`cloud.orbital8.personnal_sampler`) transformant le téléphone en un **sampleur 16 cases (grille 4×4)** avec assignation par **enregistrement microphone** ou **import de fichier WAV/audio depuis l'appareil**, éditeur de forme d'onde et lecture multi-trigger instantanée.

## Fonctionnalités Principales (`v1.0.0`)

1. **Grille 4×4 (16 Cases) Haute Réactivité** :
   - 16 pads (`PAD 01` à `PAD 16`) visibles simultanément sur un seul écran ;
   - Appui illimité sur chaque touche pour rejouer le son autant de fois que souhaité (`SoundPool` 32 voix basse latence + `MediaPlayer`).
2. **Bouton `RECORD` — 2 Sources d'Assignation + Kit Studio** :
   - **Enregistrer avec le Micro** : capture PCM 16-bit 44.1 kHz en direct avec VU-mètre temps réel ;
   - **Fichier WAV / Audio depuis l'appareil** : import natif Android (`.wav`, `.mp3`, `.m4a`, `.aac`, `.ogg`) ;
   - **Kit Studio 808 intégré** : 16 instruments synthétisés prêts à l'emploi sur la `Banque A`.
3. **Fonctionnalités Studio Complètes (Analyse Produit)** :
   - **Auto-Trim Silence & Normalisation Micro** : supprime automatiquement le silence au début d'un enregistrement micro pour une attaque immédiate sans retard ;
   - **Découpe Waveform (`Trim Début / Fin`)** : aperçu graphique de l'onde sonore sur chaque pad et découpe précise avec fondu anti-clic ;
   - **Modes `CUT` (Redéclencher), `POLY` (Superposer), `LOOP` (Boucle continue)** et bouton global **`STOP`** ;
   - **Contrôles par Pad** : Volume (`0–150%`), Pitch / Vitesse (`0.5×–2.0×`), Nom personnalisé, 16 couleurs néon, Export `.wav` (`Music/PersonalSampler/`) ;
   - **4 Banques Persistées (`BANK A..D`)**, **Métronome (`40–220 BPM` + `TAP`)** et **Séquenceur / Looper Live (`REC SEQ`)**.

## Commandes de développement

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
