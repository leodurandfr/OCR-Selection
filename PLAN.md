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

- [x] `Services/OCRService.swift`
- [x] Méthode `func recognizeText(in image: CGImage) async throws -> String`
  - `VNRecognizeTextRequest`
  - `automaticallyDetectsLanguage = true` (en dur)
  - `usesLanguageCorrection = true` (en dur)
  - `recognitionLevel = .accurate`
  - Joindre les `VNRecognizedTextObservation` avec `\n` dans l'ordre vertical
- [x] Enum `OCRError`: `noTextFound`, `visionFailed(Error)`
- [ ] Test unitaire avec une image fixture contenant du texte connu *(reporté en Phase 10 — la target de tests n'existe pas encore ; validation manuelle via le bouton debug)*

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

**Phase en cours** : Phase 10 — Tests unitaires.

**Post-phase-9 (retours utilisateur)** : (1) bouton « Effacer l'historique » retiré du menu bar (laisse la section Recents à un rôle purement consultatif) — reste disponible dans l'onglet Historique des préférences. (2) Fenêtre Préférences refactorisée : `TabView` + 3 sous-vues privées → un seul `Form.grouped` scrollable avec 4 `Section` (General, Shortcut, History, About). Raison : 1 seul contrôle par onglet rendait la structure tabulaire disproportionnée. (3) Nouvelle section **About** : `LabeledContent("Designed by") { Link(destination: https://leodurand.com) { Text(verbatim: "leodurand.com") } }`. 2 clés ajoutées au catalogue : `About`, `Designed by` + traduction de `Entries kept` (détecté par Xcode comme clé du Slider label accessibility).

**Dernière phase complétée** : Phase 9 — Historique avec SwiftData. Nouveau `OCRSelection/Models/OCREntry.swift` : `@Model final class OCREntry` avec `id: UUID`, `text: String`, `createdAt: Date`. Nouveau `OCRSelection/Services/HistoryService.swift` (`@MainActor struct`) prenant un `ModelContainer` — `record(_:)` insère une entrée puis appelle `prune(in:)` qui lit le cap via `UserDefaults.standard.integer(forKey: "historyMaxCount")` et `context.delete` les entrées au-delà ; `clear()` fait un `context.delete(model: OCREntry.self)` global. `CaptureCoordinator` : nouvelle dépendance `let history: HistoryService`, appelle `await history.record(text)` après un OCR réussi (skip si texte trim vide), nouvelle méthode `recopy(_ text:)` = copy + `notifySuccess` utilisée depuis les entrées du menu. `AppDelegate` (marqué `@MainActor`) : crée le `ModelContainer(for: OCREntry.self)` dans `init()`, construit le `CaptureCoordinator` avec `HistoryService(container:)`, et enregistre `UserDefaults.standard.register(defaults: ["historyMaxCount": 30])` au plus tôt. `OCRSelectionApp` : le contenu `MenuBarExtra` est extrait dans une view privée `MenuBarContent` (`@Query(sort: \OCREntry.createdAt, order: .reverse)`) avec une section `Section("Recents")` limitée à `entries.prefix(10)` — chaque ligne affiche `"<preview 40 chars> — <relative time named>"` via `Date.formatted(.relative(presentation: .named))` et `Text(verbatim:)` (pas de pollution du catalogue), clic = `coordinator.recopy(text)` ; bouton `"Clear History"` sous la liste. Le container est injecté avec `.modelContainer(appDelegate.container)` sur chaque scene (MenuBarExtra + Settings). Nouvel onglet Historique `HistorySettingsView` : `Form` avec un `Slider(value: Binding<Double>, in: 10...50, step: 5)` + label dynamique `Text("Entries kept: \(maxCount)")` (via `@AppStorage("historyMaxCount") var maxCount: Int = 30`) + bouton destructif `Button("Clear History", role: .destructive)`. 3 clés ajoutées au catalogue : `Recents`, `Clear History`, `Entries kept: %lld` (EN/FR/ES). Build OK (`BUILD SUCCEEDED`).

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
