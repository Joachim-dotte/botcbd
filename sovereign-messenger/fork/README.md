# Sovereign Messenger v0.2.0 alpha

Overlay source ciblant exclusivement SimpleX Chat `v7.0.0`, commit :

```text
e11128ce5b0df538c57a0d0b6911de0e88fdb652
```

Cette alpha conserve la messagerie SimpleX complète et ajoute :

- un **Registre Sovereign** dans les réglages ;
- une synthèse fail-closed et un journal pour chaque contact/conversation ;
- un registre Android persistant, chaîné par SHA-256 et authentifié par une clé
  HMAC StrongBox non exportable ;
- un mode développeur dont l'ouverture du journal Sovereign exige
  l'authentification locale ;
- GrapheneOS Auditor embarqué comme activité non exportée pour l'attestation QR
  locale entre deux Pixel ;
- des états séparés `QR LOCAL BASIQUE/FORT`, volontairement orange tant que la
  preuve n'est pas liée cryptographiquement au code de sécurité SimpleX ;
- des tests communs pour l'agrégation fail-closed et le filtrage des métadonnées.

## Frontière de sécurité honnête

L'attestation embarquée vérifie localement les preuves GrapheneOS/Android de
l'autre téléphone avec un challenge frais, StrongBox, l'état de démarrage et
l'identité exacte de l'APK. Le résultat est limité au contact sélectionné par un
jeton opaque HMAC. Cette sélection locale **ne lie pas encore** le challenge au
ratchet ni au code de sécurité du contact : scanner le mauvais Pixel valide peut
donc produire une preuve locale valide dans le mauvais périmètre. Pour cette
raison, ce résultat ne devient jamais le vert global `VÉRIFIÉ`.

Le registre ne stocke aucun texte de message, nom, adresse, URI, jeton, certificat
ou identifiant de contact en clair. Il détecte une modification locale des
enregistrements, mais un attaquant capable de restaurer ensemble un ancien
snapshot de la base, du fichier et de la clé peut encore provoquer un rollback.
L'ancrage pair-à-pair nécessaire pour détecter ce cas est spécifié dans `core/`,
mais ce lot Haskell reste source-only et n'est pas intégré à l'APK avant ses portes
CI SQLite/PostgreSQL.

Il s'agit d'une alpha de test, signée avec une clé Android debug. Ce n'est ni une
release de production, ni une garantie de sécurité totale.

## Préparer et appliquer

```bash
bash fork/apply.sh /path/to/simplex-chat-v7.0.0
bash fork/attestation/prepare-auditor.sh
bash fork/attestation/integrate-simplex.sh /path/to/simplex-chat-v7.0.0
```

Les scripts vérifient les commits et arbres épinglés, puis refusent une base
inconnue. Ils sont idempotents. Ne pas exécuter `core/apply.sh` pour cette alpha.

## Compiler

Prérequis : JDK 17, Android SDK 36, Build Tools 36.1.0, NDK 23.1.7779620 et les
bibliothèques natives SimpleX arm64 officielles vérifiées.

```bash
cd /path/to/simplex-chat-v7.0.0/apps/multiplatform
./gradlew \
  -PsovereignAuditorModuleDir=/absolute/path/to/fork/attestation/vendor/Auditor/app \
  :common:desktopTest :android:assembleDebug
```

Aucune clé privée de signature n'est fournie ou stockée dans ce dépôt.

## Fichiers upstream modifiés

- `views/usersettings/SettingsView.kt`
- `views/usersettings/DeveloperView.kt`
- `views/chat/ChatInfoView.kt`
- `views/chat/ChatView.kt`
- fichiers Gradle Android/common/settings pour le module Auditor.

Les autres fichiers Kotlin sont ajoutés par `overlay/`. Les détails, le commit
Auditor épinglé, les licences et les limites figurent dans `attestation/README.md`.
