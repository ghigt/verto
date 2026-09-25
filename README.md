# Verto

Petite fenêtre flottante (façon Spotlight) pour réécrire, traduire ou corriger du texte avec un LLM local.

Mode par défaut **Réécrire** : reformule ton texte (souvent un anglais approximatif) en un texte bien tourné, dans la même langue, sans rien ajouter ni retirer. Ensuite, comme le « Ajuster » de Copilot dans Teams, des préréglages en un clic (Pro, Détendu, Confiant, Enthousiaste, Plus court, Plus long) ou une consigne libre. Chaque résultat est gardé comme une version : on compare en basculant de l'une à l'autre sans rien regénérer. Les préréglages partent toujours de la version par défaut ; une consigne libre s'applique à la version affichée.

## Lancer

```sh
./build.sh && open Verto.app   # app autonome (icône ✨ dans la barre de menus, pas de Dock)
# ou, sans bundle :
swift run -c release
```

Pré-requis : un serveur OpenAI-compatible local, par ex. `ollama serve` (Ollama), LM Studio (`http://localhost:1234/v1`), llama.cpp server…

L'icône de la barre de menus peut être masquée (menu → « Masquer l'icône… »). Pour la retrouver : `⌘,` dans la fenêtre → « Afficher l'icône… », ou relancer `Verto.app` (ce qui la réaffiche).

Pour le lancer à l'ouverture de session : Réglages Système → Général → Ouverture → ajouter `Verto.app`.

## Raccourcis

| Touche | Action |
|---|---|
| `⌥Space` | ouvrir / fermer (configurable) |
| `⌘1`…`⌘9` | choisir l'action (relance sur le texte d'origine si déjà traité) |
| `⏎` / `⇧⏎` | envoyer / nouvelle ligne |
| `⏎` sur un résultat | copier (idem `⌘⏎` / `⌘C`) ; la fenêtre reste ouverte |
| `tab` sur un résultat | ouvrir la palette d'ajustement : tape « pro », « court », « esp »… une liste filtrée apparaît, `↑↓` pour choisir, `⏎` pour appliquer ; sans correspondance, `⏎` envoie ta saisie comme consigne libre. `✓` = déjà généré (affiché sans regénérer). `esc` pour masquer |
| `⌥1`…`⌥9` | appliquer directement un préréglage d'ajustement |
| `←` `→` | basculer entre les versions déjà générées (Défaut, Pro, Plus court…) sans regénérer |
| `⌘.` | stopper la génération |
| `⌘N` | nouvelle conversation |
| `⌘Y` | historique : le champ devient une recherche, `↑↓` naviguer, `⏎` rouvrir (pour ré-ajuster), `⌘⏎` copier, `⌘⌫` supprimer |
| `⌘,` ou `⋯` | menu de Verto : config, afficher/masquer l'icône de la barre de menus, quitter |
| `esc` | fermer (la conversation est conservée jusqu'à `⌘N`) ; dans l'historique : retour |

## Config

`~/.config/verto/config.json` (créé au premier lancement ; menu ✨ → « Éditer la config » puis « Recharger la config ») :

- `baseURL` : endpoint OpenAI-compatible (défaut Ollama `http://localhost:11434/v1`)
- `model` : vide = premier modèle listé par le serveur
- `apiKey`, `temperature`
- `hotkey` : ex. `option+space`, `ctrl+option+t`, `cmd+shift+space`
- `prefillFromClipboard` : pré-remplir le champ avec le presse-papiers
- `actions` : liste `{ "name", "prompt" }` — `prompt` vide = le texte saisi sert de prompt (« Libre »). Le texte est envoyé entre balises `<text>` pour que le modèle ne réponde pas à une question qu'il contiendrait.
  - `languages` (optionnel), ex. `["fr", "en"]` : traduction automatique. La langue du texte est détectée par macOS ; un texte dans la 1re langue est traduit dans la 2e, tout le reste dans la 1re. `{target}` dans le prompt est remplacé par la langue cible. C'est le cas de l'action « Traduire » (FR ↔ EN).
  - `targets` (optionnel) : langues proposées dans la palette d'ajustement (`tab`, puis taper « esp », « allemand »…) pour forcer une autre cible, ex. `["en", "fr", "es", "de", "it", "pt"]` — proposées en premier ; toute autre langue connue de macOS est trouvée en tapant son nom (« chin », « en japonais », « into Korean »). Chaque langue devient une version, comparable sans regénérer ; les préréglages (Pro, Plus court…) s'appliquent à la langue affichée.
- `historyLimit` : nombre de conversations gardées (défaut 200, `0` = désactivé). Stockées en clair dans `~/.config/verto/history.json`.
- `adjustments` : préréglages d'ajustement `{ "name", "prompt" }`
- `temperature` : 0.1 par défaut (plus haut = plus varié mais moins fidèle)

Avec un modèle 8B (llama3.1) le résultat est correct ; un modèle plus gros (ex. `qwen2.5:14b`, `mistral-small`) sera nettement meilleur en anglais.

> Note : `⌥Space` sert à taper l'espace insécable sur clavier français ; change `hotkey` si tu l'utilises.
