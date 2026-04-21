# OCR Selection — Plan d'implémentation

Application macOS de barre de menu qui capture une zone d'écran, en extrait le texte via OCR (Vision) et le copie dans le presse-papier. Équivalent gratuit de TextSniper.

## Comment utiliser ce plan

- Chaque phase est un lot cohérent et testable isolément.
- Les cases à cocher suivent une progression : **ne pas sauter une phase**.
- À chaque nouvelle conversation : demander `Implémenter la prochaine étape du plan PLAN.md` (ou une phase précise).
- Cocher `- [x]` chaque étape terminée avant de passer à la suivante.
- Mettre à jour la section **État actuel** en bas après chaque phase.

## Paramètres du projet (référence)

| Clé | Valeur |
|---|---|
| Nom de l'app | OCR Selection |
| Bundle ID | `com.leodurand.ocr-selection` |
| Min macOS | 14.0 (Sonoma) |
| Langages UI | 🇬🇧 EN · 🇫🇷 FR · 🇪🇸 ES |
| Raccourci par défaut | ⌘⇧2 |
| Historique max | 30 (configurable 10–50) |
| Sandbox | **désactivé** en MVP (à cause de `screencapture` CLI). Réactivé en Phase 12 avec ScreenCaptureKit. |

---

## Phase 0 — Setup du projet Xcode

- [x] Créer un projet Xcode à la racine : App · SwiftUI · Swift · macOS · min 14.0
- [x] Nom : `OCRSelection` · Bundle ID : `com.leodurand.ocr-selection`
- [x] `Info.plist` : `LSUIElement = YES` (app barre de menu uniquement)
- [x] `Info.plist` : `NSHumanReadableCopyright` → `© 2026 Leo Durand`
- [x] Category : `public.app-category.utilities`
- [x] Entitlements : désactiver App Sandbox pour le MVP (`com.apple.security.app-sandbox = NO`). Laisser hardened runtime activé.
- [x] `.gitignore` (xcuserdata, DerivedData, .DS_Store)
- [x] Compile, lance — icône visible en barre de menu, pas dans le Dock

## Phase 1 — Scaffold barre de menu

- [x] `OCRSelectionApp.swift` : `@main` avec `MenuBarExtra`
- [x] Icône SF Symbol : `text.viewfinder` (style `.titleBarExtraStyle`)
- [x] Menu statique :
  - Bouton « Capturer une zone » (désactivé pour l'instant, juste l'entrée)
  - Divider
  - Bouton « Préférences… » (ouvre `Settings` scene vide pour l'instant)
  - Divider
  - Bouton « Quitter OCR Selection » (`NSApplication.shared.terminate`)
- [x] `Settings` scene vide (placeholder `Text("Préférences")`)
- [x] Lancer : le menu s'ouvre au clic, Quitter fonctionne

## Phase 2 — Capture d'écran via CLI

- [x] `Services/ScreenCaptureService.swift`
- [x] Méthode `async func captureRegion() throws -> CGImage`
  - Lance `/usr/sbin/screencapture -i -c` via `Process`
  - Attend la fin du process
  - Lit l'image depuis `NSPasteboard.general` (type `.png` ou `.tiff`)
  - Retourne un `CGImage`
  - Lève `CaptureError.userCancelled` si l'utilisateur a fait Échap (rien dans le clipboard après `screencapture`)
- [x] Enum `CaptureError`: `userCancelled`, `clipboardEmpty`, `decodingFailed`
- [x] Test manuel : bouton debug qui capture et affiche les dimensions de l'image

## Phase 3 — OCR via Vision

- [ ] `Services/OCRService.swift`
- [ ] Méthode `func recognizeText(in image: CGImage) async throws -> String`
  - `VNRecognizeTextRequest`
  - `automaticallyDetectsLanguage = true` (en dur)
  - `usesLanguageCorrection = true` (en dur)
  - `recognitionLevel = .accurate`
  - Joindre les `VNRecognizedTextObservation` avec `\n` dans l'ordre vertical
- [ ] Enum `OCRError`: `noTextFound`, `visionFailed(Error)`
- [ ] Test unitaire avec une image fixture contenant du texte connu

## Phase 4 — Écriture dans le presse-papier

- [ ] `Services/PasteboardService.swift`
- [ ] Méthode `func copyText(_ text: String)` → `NSPasteboard.general.clearContents()` puis `setString(_:forType: .string)`
- [ ] Coordinateur `CaptureCoordinator.swift` qui orchestre : `capture → OCR → paste`
- [ ] Câbler le bouton « Capturer une zone » du menu à ce coordinateur
- [ ] Test end-to-end : sélectionner un texte à l'écran → texte dans le presse-papier

## Phase 5 — Notifications

- [ ] `Services/NotificationService.swift`
- [ ] Demander la permission `UNUserNotificationCenter` au premier lancement (`applicationDidFinishLaunching`)
- [ ] Notification de succès : titre « Texte copié », corps = aperçu du texte (50 premiers caractères)
- [ ] Notification d'erreur selon le cas :
  - « Aucun texte détecté » (OCR vide)
  - « Capture annulée » — on choisit de ne PAS notifier si l'utilisateur fait Échap (silence attendu)
  - « Erreur lors de la capture » (autres erreurs)
- [ ] Intégrer dans `CaptureCoordinator`

## Phase 6 — Localisation EN / FR / ES

- [ ] Créer un `Localizable.xcstrings` (String Catalog, format moderne Xcode 15+)
- [ ] Extraire toutes les chaînes UI (menu items, notifications, labels prefs à venir)
- [ ] Fournir les 3 traductions (base: EN, traduire FR & ES)
- [ ] `Info.plist` : `CFBundleLocalizations = [en, fr, es]`, `CFBundleDevelopmentRegion = en`
- [ ] Tester en changeant la langue système
- [ ] Vérifier que les raccourcis ⌘ restent cohérents

## Phase 7 — Fenêtre Préférences (structure)

- [ ] `Preferences/PreferencesView.swift` avec `TabView` (style `.automatic`)
- [ ] 3 onglets (icônes SF Symbol + labels localisés) :
  - **Général** (`gear`)
  - **Raccourci** (`command`)
  - **Historique** (`clock`)
- [ ] Onglet **Général** :
  - `Toggle("Lancer au démarrage")` → `SMAppService.mainApp.register()/unregister()`
- [ ] Onglets Raccourci & Historique : placeholders (remplis Phases 8 & 9)
- [ ] Vérifier l'ouverture depuis le menu bar, fermeture propre

## Phase 8 — Raccourci global

- [ ] Ajouter le package SPM `https://github.com/sindresorhus/KeyboardShortcuts`
- [ ] `KeyboardShortcuts.Name.captureRegion` avec défaut `.init(.two, modifiers: [.command, .shift])`
- [ ] Dans `OCRSelectionApp` : `KeyboardShortcuts.onKeyUp(for: .captureRegion) { ... }` → appelle `CaptureCoordinator`
- [ ] Onglet **Raccourci** :
  - `KeyboardShortcuts.Recorder("Capturer une zone", name: .captureRegion)`
  - Bouton « Réinitialiser » qui appelle `KeyboardShortcuts.reset(.captureRegion)`
- [ ] Tester : le raccourci fonctionne même quand une autre app a le focus

## Phase 9 — Historique avec SwiftData

- [ ] `Models/OCREntry.swift` : `@Model` avec `id: UUID`, `text: String`, `createdAt: Date`
- [ ] `ModelContainer` injecté via `.modelContainer(for: OCREntry.self)` dans `OCRSelectionApp`
- [ ] Sauvegarder dans `CaptureCoordinator` après chaque OCR réussi (ne rien sauvegarder si texte vide)
- [ ] `HistoryService.swift` : enforcement du cap (supprimer les plus anciennes au-delà de N)
- [ ] `@AppStorage("historyMaxCount")` avec défaut 30
- [ ] Menu bar : section « Récents » listant les N dernières entrées
  - Chaque ligne : aperçu tronqué (40 chars) + heure relative (il y a X min)
  - Clic = recopie le texte complet dans le presse-papier + notification
  - Limite d'affichage dans le menu : 10 entrées max (scroll sinon)
  - Bouton « Effacer l'historique » en bas de la liste
- [ ] Onglet **Historique** :
  - `Slider(value: maxCount, in: 10...50, step: 5)` + label dynamique
  - Bouton destructif « Effacer l'historique »

## Phase 10 — Tests unitaires

- [ ] Ajouter une target de tests (`OCRSelectionTests`)
- [ ] Test `OCRService` : OCR sur une image fixture (PNG bundlé) → vérifie le contenu attendu
- [ ] Test `PasteboardService` : écrire puis relire, vérifier égalité
- [ ] Test `HistoryService` : ajout au-delà du cap → les anciennes sont supprimées
- [ ] Test `OCREntry` : création, tri par date
- [ ] Vérifier que `cmd+U` passe au vert

## Phase 11 — Polish & UX

- [ ] `AppIcon.appiconset` : générer les tailles macOS (16 à 1024) — demander à l'utilisateur un design ou utiliser un placeholder SF Symbol rendu
- [ ] Menu item « À propos d'OCR Selection » → fenêtre About standard (`NSApp.orderFrontStandardAboutPanel`)
- [ ] Gestion de la permission Screen Recording si elle est demandée par `screencapture` (macOS 14+) : afficher un message clair avec lien vers Réglages
- [ ] Cas d'erreur : capture OK mais OCR lève → notification spécifique
- [ ] Tooltips / `.accessibilityLabel` sur les éléments critiques
- [ ] Revue finale : toute la UI passe en FR/EN/ES correctement

## Phase 12 — Distribution

- [ ] Configurer la Team Developer ID dans Xcode
- [ ] Archive → Distribute App → Developer ID
- [ ] Notarization (`xcrun notarytool submit` + `stapler staple`)
- [ ] Créer un DMG (script `create-dmg` ou manuel)
- [ ] Tester l'install sur une autre machine / un compte utilisateur vierge
- [ ] **Optionnel — passage App Store** :
  - Remplacer `screencapture -i -c` par une implémentation native `ScreenCaptureKit` + overlay de sélection custom
  - Réactiver App Sandbox
  - Soumettre à App Store Connect

---

## État actuel

**Phase en cours** : Phase 3 — OCR via Vision.

**Dernière phase complétée** : Phase 2 — Capture d'écran via CLI. `Services/ScreenCaptureService.swift` lance `/usr/sbin/screencapture -i -c` via `Process`, détecte l'annulation utilisateur via `NSPasteboard.changeCount`, relit l'image (TIFF ou PNG) depuis le presse-papier et la décode en `CGImage`. Un bouton « Debug : tester la capture » dans le menu bar affiche les dimensions via `NSAlert`. Build OK (`BUILD SUCCEEDED`).

**Notes / décisions en cours de route** :

- `project.pbxproj` construit à la main en utilisant `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ / objectVersion 77) : les fichiers sous `OCRSelection/` sont automatiquement inclus dans la target, pas besoin de les lister un par un. Ajouter un nouveau fichier = juste créer le fichier.
- `Info.plist` auto-généré via `GENERATE_INFOPLIST_FILE = YES` + clés `INFOPLIST_KEY_*`. Pas de `Info.plist` manuel.
- Entitlements actuels : uniquement `com.apple.security.app-sandbox = false` (cf. Phase 12 pour réactivation).
- Ouverture de la fenêtre Préférences via `SettingsLink` (macOS 14+) — pas besoin de `@Environment(\.openSettings)` ni de gymnastique `NSApp.activate`.
- Chaînes UI en français en dur pour le moment ; la localisation EN/FR/ES arrive en Phase 6 via String Catalog.
- `xcodebuild` nécessite `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (la CLI pointe par défaut sur les Command Line Tools).
- Détection d'annulation dans `ScreenCaptureService` via `NSPasteboard.changeCount` (snapshot avant/après) plutôt que de vider le presse-papier : on ne perturbe pas le contenu existant si l'utilisateur fait Échap.
- Le bouton « Debug : tester la capture » est temporaire — il sera retiré en Phase 4 quand le vrai bouton « Capturer une zone » sera câblé au `CaptureCoordinator`.
