# Changelog — PulsePad 16 (`cloud.orbital8.personnal_sampler`)

Toutes les modifications notables de ce projet sont documentées dans ce fichier.
Respect strict du versionning `v1.x.y` (numérotation unique, aucun numéro réutilisé).

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
  - **Réglages Audio par Case** : Volume individuel (`0%` à `150%`), Pitch / Vitesse (`0.50×` à `2.00×`), Nom personnalisé, Couleur Néon (16 teintes) et Export en `.wav` dans `Music/PersonalSampler/`.
  - **4 Banques Persistées (`BANK A` à `BANK D`)** : sauvegarde automatique JSON + fichiers `.wav` sur l'appareil.
  - **Métronome (`40–220 BPM` + `TAP TEMPO`) & Séquenceur / Looper Live (`REC SEQ` / `LOOP`)** : enregistrement et lecture en boucle d'une séquence de frappes sur les 16 pads.
