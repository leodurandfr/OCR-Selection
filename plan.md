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
| Sandbox | **désactivé** en MVP (à cause de `screencapture` CLI). Réactivé en Phase 14 après migration ScreenCaptureKit (Phase 13). |

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

- [x] `Services/OCRService.swift`
- [x] Méthode `func recognizeText(in image: CGImage) async throws -> String`
  - `VNRecognizeTextRequest`
  - `automaticallyDetectsLanguage = true` (en dur)
  - `usesLanguageCorrection = true` (en dur)
  - `recognitionLevel = .accurate`
  - Joindre les `VNRecognizedTextObservation` avec `\n` dans l'ordre vertical
- [x] Enum `OCRError`: `noTextFound`, `visionFailed(Error)`
- [x] Test unitaire avec une image fixture contenant du texte connu *(traité en Phase 10 — image générée à la volée via `CGContext` + `CTLineDraw`, pas de PNG bundlé)*

## Phase 4 — Écriture dans le presse-papier

- [x] `Services/PasteboardService.swift`
- [x] Méthode `func copyText(_ text: String)` → `NSPasteboard.general.clearContents()` puis `setString(_:forType: .string)`
- [x] Coordinateur `CaptureCoordinator.swift` qui orchestre : `capture → OCR → paste`
- [x] Câbler le bouton « Capturer une zone » du menu à ce coordinateur
- [x] Test end-to-end : sélectionner un texte à l'écran → texte dans le presse-papier *(validation manuelle à faire par l'utilisateur — build OK)*

## Phase 5 — Notifications

- [x] `Services/NotificationService.swift`
- [x] Demander la permission `UNUserNotificationCenter` au premier lancement (`applicationDidFinishLaunching`)
- [x] Notification de succès : titre « Texte copié », corps = aperçu du texte (50 premiers caractères)
- [x] Notification d'erreur selon le cas :
  - « Aucun texte détecté » (OCR vide)
  - « Capture annulée » — on choisit de ne PAS notifier si l'utilisateur fait Échap (silence attendu)
  - « Erreur lors de la capture » (autres erreurs)
- [x] Intégrer dans `CaptureCoordinator`

## Phase 6 — Localisation EN / FR / ES

- [x] Créer un `Localizable.xcstrings` (String Catalog, format moderne Xcode 15+)
- [x] Extraire toutes les chaînes UI (menu items, notifications, labels prefs à venir)
- [x] Fournir les 3 traductions (base: EN, traduire FR & ES)
- [x] `Info.plist` : `CFBundleLocalizations = [en, fr, es]`, `CFBundleDevelopmentRegion = en` *(géré implicitement — voir notes : `knownRegions` + `.lproj` auto-compilés remplacent la clé manuelle ; `CFBundleDevelopmentRegion = en` présent via `developmentRegion`)*
- [ ] Tester en changeant la langue système *(validation manuelle à faire par l'utilisateur — build OK, `.lproj` générés pour en/fr/es)*
- [x] Vérifier que les raccourcis ⌘ restent cohérents

## Phase 7 — Fenêtre Préférences (structure)

- [x] `Preferences/PreferencesView.swift` avec `TabView` (style `.automatic`)
- [x] 3 onglets (icônes SF Symbol + labels localisés) :
  - **Général** (`gear`)
  - **Raccourci** (`command`)
  - **Historique** (`clock`)
- [x] Onglet **Général** :
  - `Toggle("Lancer au démarrage")` → `SMAppService.mainApp.register()/unregister()`
- [x] Onglets Raccourci & Historique : placeholders (remplis Phases 8 & 9)
- [x] Vérifier l'ouverture depuis le menu bar, fermeture propre *(build OK ; validation visuelle à faire par l'utilisateur)*

## Phase 8 — Raccourci global

- [x] Ajouter le package SPM `https://github.com/sindresorhus/KeyboardShortcuts`
- [x] `KeyboardShortcuts.Name.captureRegion` avec défaut `.init(.two, modifiers: [.command, .shift])`
- [x] Dans `OCRSelectionApp` : `KeyboardShortcuts.onKeyUp(for: .captureRegion) { ... }` → appelle `CaptureCoordinator`
- [x] Onglet **Raccourci** :
  - `KeyboardShortcuts.Recorder("Capturer une zone", name: .captureRegion)`
  - Bouton « Réinitialiser » qui appelle `KeyboardShortcuts.reset(.captureRegion)`
- [ ] Tester : le raccourci fonctionne même quand une autre app a le focus *(validation manuelle à faire par l'utilisateur — build OK)*

## Phase 9 — Historique avec SwiftData

- [x] `Models/OCREntry.swift` : `@Model` avec `id: UUID`, `text: String`, `createdAt: Date`
- [x] `ModelContainer` injecté via `.modelContainer(for: OCREntry.self)` dans `OCRSelectionApp`
- [x] Sauvegarder dans `CaptureCoordinator` après chaque OCR réussi (ne rien sauvegarder si texte vide)
- [x] `HistoryService.swift` : enforcement du cap (supprimer les plus anciennes au-delà de N)
- [x] `@AppStorage("historyMaxCount")` avec défaut 30
- [x] Menu bar : section « Récents » listant les N dernières entrées
  - Chaque ligne : aperçu tronqué (40 chars) + heure relative (il y a X min)
  - Clic = recopie le texte complet dans le presse-papier + notification
  - Limite d'affichage dans le menu : 10 entrées max (scroll sinon)
  - ~~Bouton « Effacer l'historique » en bas de la liste~~ (retiré — uniquement dans Préférences > Historique, cf. note Phase 9-bis)
- [x] Onglet **Historique** :
  - `Slider(value: maxCount, in: 10...50, step: 5)` + label dynamique
  - Bouton destructif « Effacer l'historique »

## Phase 10 — Tests unitaires

- [x] Ajouter une target de tests (`OCRSelectionTests`)
- [x] Test `OCRService` : OCR sur une image fixture (PNG bundlé) → vérifie le contenu attendu *(fixture générée via `CGContext` + `CTLineDraw` — pas de binaire dans le repo)*
- [x] Test `PasteboardService` : écrire puis relire, vérifier égalité
- [x] Test `HistoryService` : ajout au-delà du cap → les anciennes sont supprimées
- [x] Test `OCREntry` : création, tri par date
- [x] Vérifier que `cmd+U` passe au vert *(validé via `xcodebuild test` : 9 tests sur 4 suites, `TEST SUCCEEDED`)*

## Phase 11 — Polish & UX

- [x] `AppIcon.appiconset` : générer les tailles macOS (16 à 1024) — demander à l'utilisateur un design ou utiliser un placeholder SF Symbol rendu
- [x] Menu item « À propos d'OCR Selection » → fenêtre About standard (`NSApp.orderFrontStandardAboutPanel`)
- [x] Gestion de la permission Screen Recording si elle est demandée par `screencapture` (macOS 14+) : afficher un message clair avec lien vers Réglages
- [x] Cas d'erreur : capture OK mais OCR lève → notification spécifique
- [x] Tooltips / `.accessibilityLabel` sur les éléments critiques
- [x] Revue finale : toute la UI passe en FR/EN/ES correctement

## Phase 12 — Distribution Developer ID

- [x] Configurer la Team Developer ID dans Xcode
- [x] Archive → Distribute App → Developer ID (flux "Direct Distribution" : signature + notarization + stapler automatisés par Xcode)
- [x] Notarization (réalisée par le flux Direct Distribution, équivaut à `xcrun notarytool submit --wait` + `xcrun stapler staple`)
- [ ] Créer un DMG (script `create-dmg` ou manuel)
- [ ] Tester l'install sur une autre machine / un compte utilisateur vierge

## Phase 13 — Migration ScreenCaptureKit (prérequis App Store)

> Objectif : remplacer `screencapture -i -c` par une implémentation native compatible avec App Sandbox. Bloquant pour la Phase 14.

- [ ] Ajouter `import ScreenCaptureKit` et vérifier la permission via `SCShareableContent.current` (déclenche le prompt standard macOS, plus besoin de `CGPreflightScreenCaptureAccess` custom)
- [ ] Nouveau `SelectionOverlayController` :
  - `NSPanel` borderless plein écran (un par `NSScreen`), `level = .screenSaver`, `isOpaque = false`, background `NSColor.black.withAlphaComponent(0.25)`
  - Capture `mouseDown` / `mouseDragged` / `mouseUp` pour dessiner un `NSBezierPath` rectangulaire (bordure blanche + intérieur transparent via `NSCompositingOperation.destinationOut`)
  - Échap → `CaptureError.userCancelled` ; release souris → renvoie le `CGRect` sélectionné en coordonnées écran
  - Cacher le curseur pendant la sélection (`NSCursor.hide()` / `unhide()`)
- [ ] Réécrire `ScreenCaptureService.captureRegion()` :
  - Présenter l'overlay, attendre le `CGRect`
  - `SCScreenshotManager.captureImage(contentFilter:configuration:)` sur l'écran concerné (filtre = `SCContentFilter(display:excludingWindows:)` pour exclure notre propre overlay)
  - Crop du `CGImage` retourné avec le rect → passé à `OCRService` (inchangé)
- [ ] Supprimer le code `Process` + `NSPasteboard` intermédiaire + parsing stderr
- [ ] Mettre à jour `CaptureError` : retirer `screenCaptureFailed` / `screenRecordingPermissionDenied` obsolètes, ajouter ce qui vient de ScreenCaptureKit
- [ ] Mettre à jour `CaptureCoordinator.presentScreenRecordingAlert()` : ScreenCaptureKit gère le prompt système nativement, l'alerte custom peut être supprimée ou simplifiée en « ouvrir Réglages » après un refus confirmé
- [ ] Tester **avec App Sandbox activé localement** (entitlement à true temporairement) avant la Phase 14 — c'est le seul mode qui révèle les bugs sandbox

## Phase 14 — Soumission App Store

- [ ] Activer App Sandbox dans `OCRSelection.entitlements` : `com.apple.security.app-sandbox = true`
- [ ] Ajouter `INFOPLIST_KEY_NSScreenCaptureUsageDescription` (3 langues via le String Catalog ou `InfoPlist.xcstrings`)
- [ ] Vérifier les autres dépendances en mode sandbox :
  - SwiftData → container migre vers `~/Library/Containers/com.leodurand.ocr-selection/Data/Library/Application Support/` (⚠️ pas de migration auto depuis l'ancien emplacement — prévoir une export/import si des utilisateurs Developer ID existent)
  - `KeyboardShortcuts` SPM → compatible sandbox
  - `SMAppService.mainApp` (login item) → compatible sandbox
  - `UNUserNotificationCenter` → compatible sandbox
  - `NSPasteboard.general.setString` → compatible sandbox (pas besoin d'entitlement supplémentaire)
- [ ] Créer l'app dans **App Store Connect** (même Bundle ID `com.leodurand.ocr-selection`, même Team ID `7C2S8B9978`)
- [ ] Fournir les assets de la fiche App Store :
  - Description EN / FR / ES (reprendre le pitch de l'app)
  - Mots-clés ≤ 100 caractères / langue
  - Screenshots (min 1280×800, recommandé 1440×900 ou 2880×1800 @2x)
  - Icône marketing 1024×1024 PNG sans canal alpha (la même que `AppIcon.appiconset`, mais aplatie)
  - Catégorie primaire : Utilities
- [ ] Privacy Nutrition Labels dans App Store Connect : déclarer **Data Not Collected** (aucune collecte, aucun tracking, aucun réseau)
- [ ] URL de support + URL de politique de confidentialité (obligatoire — une page GitHub Pages minimaliste suffit)
- [ ] Age rating (4+) + export compliance : aucun chiffrement custom → cocher **No**
- [ ] Archive → Distribute App → **App Store Connect** → Upload (nouveau flux, différent du Developer ID de la Phase 12)
- [ ] Soumettre pour review depuis App Store Connect (review typique 24–48h)

---

## État actuel

**Phase en cours** : Phase 12 — Distribution Developer ID (export & notarization OK via « Direct Distribution » ; reste DMG + test sur machine vierge en option). Phases 13–14 planifiées pour une future soumission App Store, non bloquantes.

**Dernière phase complétée** : Phase 12 (partielle) — flux « Direct Distribution » utilisé dans Xcode Organizer : Xcode signe avec le certificat Developer ID Application, uploade à Apple pour notarization, staple le ticket et renvoie un `.app` prêt à distribuer. Équivaut en une étape à `xcodebuild -exportArchive` + `xcrun notarytool submit --wait` + `xcrun stapler staple`, sans app-specific password à gérer. Erreur rencontrée au premier essai (« App Sandbox not enabled ») = preuve qu'on a d'abord sélectionné à tort le flux **App Store** ; corrigé en choisissant **Direct Distribution** → validation immédiate. Reste à produire un DMG et valider l'install sur un compte utilisateur vierge avant de cocher la Phase 12 comme 100 % complète. Phases 13 (migration ScreenCaptureKit + overlay de sélection custom) et 14 (soumission App Store avec sandbox réactivé) ajoutées au plan comme chemin optionnel vers le Mac App Store.

**Phase 11 récap** — Polish & UX : (1) **AppIcon** : icône fournie par l'utilisateur (1024×1024, PNG, coins de cadre blancs sur fond noir) redimensionnée via `sips -z` en 7 tailles (16/32/64/128/256/512/1024) ; `Contents.json` mis à jour pour référencer les filenames (l'icône @2x = deux fois le pixel count de la @1x, donc `icon_32.png` sert de 16×16@2x ET de 32×32@1x, etc.). `icon.png` à la racine du repo ajouté au `.gitignore` — seules les copies bundlées dans `Assets.xcassets/AppIcon.appiconset/` restent sous versioning. (2) **About** : `Button("About OCR Selection")` dans le `MenuBarExtra` appelle `NSApp.activate(ignoringOtherApps:)` + `orderFrontStandardAboutPanel(nil)` — la fenêtre About standard reprend automatiquement le nom du bundle, la version, l'icône et le copyright (`NSHumanReadableCopyright` posé en Phase 0). (3) **Permission Screen Recording** : nouveau cas `CaptureError.screenRecordingPermissionDenied` dans `ScreenCaptureService` — lorsque `screencapture` sort sans image, on preflight via `CGPreflightScreenCaptureAccess()` avant de décider entre `userCancelled` / `screenCaptureFailed` / `screenRecordingPermissionDenied`. Si refusée, `CaptureCoordinator.presentScreenRecordingAlert()` (statique, `@MainActor`) affiche un `NSAlert` avec deux boutons : **Open System Settings** → `NSWorkspace.shared.open` sur `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`, et **Cancel**. `NSApp.activate(ignoringOtherApps:)` appelé avant `runModal` pour que l'alerte prenne le focus même si l'app est en arrière-plan. (4) **Notification OCR distincte** : `NotificationService.notifyOCRFailed()` (titre « Unable to read text », body « The capture succeeded but text recognition failed. ») — déclenchée dans `CaptureCoordinator.run()` sur `OCRError.visionFailed(_)` en plus de logger l'erreur sous-jacente via `NSLog`. Le cas `noTextFound` reste sur `notifyNoText()` (pas d'erreur Vision, juste zéro observation), et `notifyFailure()` reste le fallback générique. (5) **Accessibilité** : `.help(Text("…"))` ajouté sur les contrôles clés des Préférences (toggle login, recorder, bouton Reset, slider historique, bouton Clear) — `.help` rend un tooltip natif au survol ET est exposé à VoiceOver comme description. Slider : `.accessibilityLabel(Text("Entries kept"))` + `.accessibilityValue(Text("\(maxCount)"))` pour que VoiceOver annonce à la fois l'élément et la valeur courante (le `Text("Entries kept: \(maxCount)")` juste au-dessus est visuel, pas accessibility-liable au slider). (6) **Localisation** : 13 nouvelles clés ajoutées à `Localizable.xcstrings` (About OCR Selection, Screen Recording permission required + body, Open System Settings, Cancel, Unable to read text, The capture succeeded but text recognition failed., + 5 tooltips). Toutes traduites EN/FR/ES en une passe. `String(localized: …)` utilisé dans `NSAlert` et `NotificationService` (contexte impératif) ; `Text(LocalizedStringKey)` partout ailleurs. `xcodebuild build` + `xcodebuild test` (9 tests / 4 suites) → SUCCEEDED.

**Notes / décisions en cours de route** :

- `project.pbxproj` construit à la main en utilisant `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ / objectVersion 77) : les fichiers sous `OCRSelection/` sont automatiquement inclus dans la target, pas besoin de les lister un par un. Ajouter un nouveau fichier = juste créer le fichier.
- `Info.plist` auto-généré via `GENERATE_INFOPLIST_FILE = YES` + clés `INFOPLIST_KEY_*`. Pas de `Info.plist` manuel.
- Entitlements actuels : uniquement `com.apple.security.app-sandbox = false` (cf. Phase 12 pour réactivation).
- Ouverture de la fenêtre Préférences via `SettingsLink` (macOS 14+) — pas besoin de `@Environment(\.openSettings)` ni de gymnastique `NSApp.activate`.
- Chaînes UI en français en dur pour le moment ; la localisation EN/FR/ES arrive en Phase 6 via String Catalog.
- `xcodebuild` nécessite `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (la CLI pointe par défaut sur les Command Line Tools).
- Détection d'annulation dans `ScreenCaptureService` via `NSPasteboard.changeCount` (snapshot avant/après) plutôt que de vider le presse-papier : on ne perturbe pas le contenu existant si l'utilisateur fait Échap.
- `stderr` de `screencapture` capturé via `Pipe` → distingue annulation utilisateur (stderr vide) d'un échec réel (`CaptureError.screenCaptureFailed`).
- `DEVELOPMENT_TEAM = 7C2S8B9978` dans `project.pbxproj` (Debug & Release) → signature stable entre les rebuilds, indispensable pour que TCC conserve la permission Enregistrement d'écran en dev.
- `OCRService` : tri vertical via `boundingBox.midY` décroissant — Vision utilise des coordonnées normalisées avec origine en bas-gauche, donc un `midY` élevé correspond au haut de l'image. Exécution du `VNImageRequestHandler.perform` sur `DispatchQueue.global(.userInitiated)` pour ne pas bloquer l'appelant ; `VNRecognizedTextObservation` vide → `OCRError.noTextFound`.
- Test unitaire du Phase 3 reporté en Phase 10 : la target `OCRSelectionTests` n'existe pas encore. Validation manuelle via le bouton debug suffisante pour le MVP.
- `CaptureCoordinator` placé à la racine de `OCRSelection/` (et non sous `Services/`) : il orchestre les services mais n'en est pas un. Instance unique détenue par `OCRSelectionApp` (`let coordinator = CaptureCoordinator()`) — Phase 8 réutilisera cette même instance pour le raccourci global.
- Phase 4 : feedback utilisateur volontairement absent (pas d'alerte de succès, `NSLog` sur erreurs) — les notifications système arrivent en Phase 5 et remplaceront les `NSLog`. `CaptureError.userCancelled` reste silencieux de manière permanente (silence attendu sur Échap, cf. Phase 5 du plan).
- Phase 5 : `CaptureCoordinator.run()` n'est plus `throws` — il avale les erreurs lui-même après avoir déclenché la notification appropriée. L'appelant (bouton menu, bientôt raccourci global Phase 8) n'a plus à gérer de `catch`. `NSLog` conservé en plus de `notifyFailure()` pour le debug Console.app.
- Phase 5 : corps d'aperçu nettoyé (newlines → espaces, trim) et tronqué à 50 caractères + « … » — garde la notification système lisible sans débordement visuel.
- Phase 5 : `UNUserNotificationCenter.requestAuthorization` appelée via un `Task` depuis `applicationDidFinishLaunching` plutôt qu'à l'init du coordinateur → respecte la formulation du plan et centralise le cycle de vie app-level dans l'`AppDelegate`.
- Phase 6 : pas de clé `INFOPLIST_KEY_CFBundleLocalizations` (non supportée par Xcode avec `GENERATE_INFOPLIST_FILE = YES`). À la place, on s'appuie sur la mécanique recommandée par Apple : `knownRegions` + `.xcstrings` → Xcode compile automatiquement des `.lproj` dans le bundle, et le système détermine `CFBundleLocalizations` à partir de ces répertoires à l'exécution. Effet identique à une clé manuelle. `CFBundleDevelopmentRegion = en` est écrit par Xcode à partir de `developmentRegion = en` du `project.pbxproj` (déjà présent).
- Phase 6 : chaînes UI passées en anglais comme langue source (le projet a `developmentRegion = en` depuis la Phase 0). `Button("Capture Area")` / `Text("Preferences…")` / `Button("Quit OCR Selection")` — SwiftUI traite les littéraux comme `LocalizedStringKey` et les résout via le catalogue. Dans `NotificationService`, `String(localized: "…")` car on est en contexte impératif (pas de `LocalizedStringKey` implicite). Le label `MenuBarExtra("OCR Selection", …)` reste inchangé : c'est le nom de marque, pas localisé.
- Phase 7 : `PreferencesView` sort de `OCRSelectionApp.swift` vers `Preferences/PreferencesView.swift` (les sous-vues `GeneralSettingsView`/`ShortcutSettingsView`/`HistorySettingsView` sont `private` dans le même fichier — pas de fichier séparé tant qu'elles restent légères). La scene `Settings { PreferencesView() }` n'a pas changé : `SettingsLink` continue de l'ouvrir. `SMAppService.mainApp` suffit pour un Login Item d'app principale (pas besoin de helper tool ni d'agent LaunchDaemon). L'état initial du `Toggle` est synchronisé via `.onAppear` : utiliser un initializer `@State = SMAppService.mainApp.status == .enabled` serait évalué trop tôt (la view struct est recréée à chaque changement de parent, l'init @State ne se déclenche qu'à la première apparition — OK, mais `.onAppear` rend l'intention plus explicite et permet de re-synchroniser si l'utilisateur modifie l'état depuis Réglages Système). Les placeholders Raccourci/Historique utilisent `Text(verbatim:)` pour éviter d'ajouter des clés transitoires au catalogue — seront remplacés en Phases 8 & 9.
- Phase 8 : SPM ajouté manuellement au `project.pbxproj` (pas d'UI Xcode dispo en mode CLI) — 3 nouvelles sections (`XCRemoteSwiftPackageReference`, `XCSwiftPackageProductDependency`, `PBXBuildFile`) + mises à jour de `packageReferences` (PBXProject), `packageProductDependencies` (PBXNativeTarget) et du Frameworks build phase. `Package.resolved` vit dans `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` — déjà ignoré par `.gitignore` (cohérent avec une app solo : chaque checkout re-résout).
- Phase 8 : `CaptureCoordinator` déplacé de `OCRSelectionApp` (struct) vers `AppDelegate` (classe). Raison : le handler `KeyboardShortcuts.onKeyUp` doit s'enregistrer après `applicationDidFinishLaunching` (sinon le moniteur d'événements NSEvent peut être installé avant que le run loop soit prêt), et il faut que le menu bar et le handler global partagent la *même* instance. Alternative écartée : `init()` de la struct App — appelée trop tôt pour enregistrer un monitor système. Référence via `appDelegate.coordinator` dans le body SwiftUI (l'adaptor `@NSApplicationDelegateAdaptor` garantit que l'AppDelegate existe avant le premier rendu du body).
- Phase 8 : l'API `KeyboardShortcuts.Recorder` a deux overloads — `init(_ title:, name:)` et `init(for:)`. On utilise `Recorder(for: .captureRegion)` dans un `LabeledContent("Capture Area") { … }` pour que le label suive automatiquement la taille du Form macOS (aligné à gauche, recorder aligné à droite), au lieu du label intégré du Recorder qui n'a pas le même comportement dans `.grouped`. Même rendu visuel, plus cohérent avec le reste des préférences.
- Phase 9 : `AppDelegate` marqué `@MainActor` et passé de `init()` par défaut à un `override init()` explicite pour créer le `ModelContainer` et construire le `CaptureCoordinator` avec sa dépendance `HistoryService`. Cohérent avec le fait que `ModelContainer.mainContext` est main-actor-bound et que les delegate callbacks AppKit sont appelés sur le main thread. `@NSApplicationDelegateAdaptor` instancie l'AppDelegate avant la première évaluation du body SwiftUI, donc `appDelegate.container` est valide pour `.modelContainer(…)` sur les scenes.
- Phase 9 : le cap d'historique (`historyMaxCount`) est lu dans `HistoryService.prune(in:)` via `UserDefaults.standard.integer(forKey:)` plutôt que passé en paramètre — `@AppStorage` ne fonctionne qu'en contexte View, et un default est enregistré une fois pour toutes au boot via `UserDefaults.register(defaults:)` dans `AppDelegate.init()` pour garantir 30 si la clé n'a jamais été écrite. `max(1, …)` défensif au cas où une valeur invalide se glisserait.
- Phase 9 : le menu bar est refactoré dans une View privée `MenuBarContent` pour pouvoir y utiliser `@Query` et `@Environment(\.modelContext)` — SwiftUI ne peut pas injecter le `ModelContext` directement dans un closure de `MenuBarExtra { … }` sans passer par un type View. Le clic sur une entrée récente capture `entry.text` côté main actor (`let text = entry.text` hors `Task`), puis `Task { await coordinator.recopy(text) }` évite de passer l'instance `@Model` (non-Sendable) à un contexte asynchrone non-isolé.
- Phase 9 : pour les labels de lignes récentes, on utilise `Text(verbatim: "<preview> — <relative time>")` plutôt que `Button(_:action:)` avec interpolation → pas d'ajout au String Catalog d'une clé `"%@ — %@"` inutile. La localisation provient de `Date.formatted(.relative(presentation: .named))` qui gère "il y a 2 min" / "2 minutes ago" via la locale courante.
- Phase 9 : `clearHistory()` appelle `context.delete(model: OCREntry.self)` puis `context.save()` — `delete(model:)` supprime en batch sans avoir à fetch+iter+delete, ce qui évite de matérialiser 30 objets pour rien. Dupliqué dans `MenuBarContent` et `HistorySettingsView` (3 lignes chaque) — pas de helper partagé tant que c'est si court.
- Phase 10 : framework de tests choisi = **Swift Testing** (pas XCTest). Xcode 26.3 / Swift 6, macroset natif, plus expressif (`@Test`, `#expect(...)`) et pas de boilerplate de classe `XCTestCase`. Le bundle charge `libXCTestSwiftSupport.dylib` automatiquement via `TEST_HOST` + `BUNDLE_LOADER` ; aucune autre dépendance à linker côté test.
- Phase 10 : fixture OCR **générée en mémoire** (`CGContext` + `NSAttributedString` + `CTLineDraw`) plutôt qu'un PNG bundlé. Raison : évite un binaire dans le repo, rend le test auto-contenu, et la génération à 80pt de NSFont.systemFont (.bold) est reconnue de façon fiable par Vision (testé à `recognitionLevel = .accurate` + `usesLanguageCorrection = true`).
- Phase 10 : `HistoryService` lit `UserDefaults.standard` (cf. Phase 9) — les tests setent la clé `historyMaxCount` en début de test, avec `defer { UserDefaults.standard.removeObject(forKey: ...) }` pour ne pas polluer les defaults du host app entre runs. Pas d'injection d'un `UserDefaults` custom dans `HistoryService` (YAGNI — la ceinture-bretelles via defer suffit).
- Phase 10 : `pruningEnforcesMaxCount` insère les entrées pré-existantes directement via `context.insert(OCREntry(createdAt: Date(timeIntervalSince1970: Double(i))))` plutôt que via `HistoryService.record()`. Raison : donne des timestamps déterministes (pas de collision possible à 5 `Date.now` consécutifs), et on teste isolément le comportement de prune quand il est déclenché par un nouvel ajout.
- Phase 10 : `PBXFileSystemSynchronizedRootGroup` étendu à `OCRSelectionTests/` — cohérent avec la décision Phase 0 (`PBXSourcesBuildPhase.files = ()` pour les deux targets, ajout de fichiers = simple création dans le dossier).
- Phase 10 : nouvelles sections `PBXContainerItemProxy` et `PBXTargetDependency` ajoutées au pbxproj (absentes jusque-là, puisqu'il n'y avait qu'une seule target). `PBXTargetDependency` garantit que l'app host est reconstruite avant le bundle de tests.
- Phase 10 : scheme partagé — ajout d'une `BuildActionEntry` avec `buildForTesting = "YES"` seulement (pas de Run/Profile/Archive/Analyze pour le bundle .xctest) + `TestableReference` dans `<Testables>`. `⌘U` dans Xcode déclenche désormais la suite entière.
- Phase 11 : `CGPreflightScreenCaptureAccess()` préféré à `CGRequestScreenCaptureAccess()` — preflight ne déclenche PAS le prompt système (on ne veut pas re-prompter à chaque capture ; l'utilisateur est guidé vers Réglages Système via l'alerte explicite). `screencapture -i -c` n'échoue silencieusement (stderr vide, changeCount inchangé) que lorsque la permission est refusée → la branche `!CGPreflightScreenCaptureAccess()` distingue ce cas de `userCancelled` (Échap) qui partageait le même signal. La permission Screen Recording est nécessaire sur macOS 14+ seulement pour capturer le **contenu** (pas pour l'UI de sélection).
- Phase 11 : `orderFrontStandardAboutPanel(nil)` — pas besoin de passer un dictionnaire `options` car les champs standard (app name, version, build, copyright, icon) sont tous présents dans l'`Info.plist` généré (`CFBundleName`, `CFBundleShortVersionString`, `CFBundleVersion`, `NSHumanReadableCopyright`, `CFBundleIconFile` implicite via `AppIcon.appiconset`). Un bundle d'app LSUIElement nécessite `NSApp.activate(ignoringOtherApps:)` avant d'ouvrir une fenêtre — sinon la fenêtre apparaît derrière l'app au premier plan.
- Phase 11 : `.help(Text("…"))` préféré à `.accessibilityHint` — `.help` fait double emploi (tooltip visuel sur macOS + description VoiceOver), alors que `.accessibilityHint` ne donne pas de tooltip. Pour le slider historique, on couple `.accessibilityLabel` (nom de l'élément) + `.accessibilityValue` (valeur courante) : `labelsHidden()` masque le label visuel mais le laisse exposé à VoiceOver via `.accessibilityLabel`.
- Phase 11 : `presentScreenRecordingAlert()` est `static @MainActor` — l'alerte n'a pas besoin d'état du coordinateur, et la marquer statique évite de capturer `self` dans `await`. `@MainActor` obligatoire car `NSAlert.runModal()` doit être appelé sur le main thread ; le `CaptureCoordinator.run()` étant invoqué depuis un `Task` non-isolé, on `await` la méthode pour hopper au main actor.
- Phase 11 : icône source `icon.png` à la racine du repo volontairement gitignorée — seules les copies bundlées dans `Assets.xcassets/AppIcon.appiconset/` (générées via `sips`) sont versionnées. Si l'icône change, la procédure est : `for size in 16 32 64 128 256 512 1024; do sips -z $size $size icon.png --out OCRSelection/Assets.xcassets/AppIcon.appiconset/icon_${size}.png; done`.
