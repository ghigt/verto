# Verto

Petite fenêtre flottante (façon Spotlight) pour traduire / reformuler / corriger du texte avec un LLM local.

## Lancer

```sh
./build.sh && open Verto.app   # app autonome (icône ✨ dans la barre de menus, pas de Dock)
# ou, sans bundle :
swift run -c release
```

Pré-requis : un serveur OpenAI-compatible local, par ex. `ollama serve` (Ollama), LM Studio (`http://localhost:1234/v1`), llama.cpp server…

Pour le lancer à l'ouverture de session : Réglages Système → Général → Ouverture → ajouter `Verto.app`.

## Raccourcis

| Touche | Action |
|---|---|
| `⌥Space` | ouvrir / fermer (configurable) |
| `⌘1`…`⌘9` | choisir l'action (relance sur le texte d'origine si déjà traité) |
| `⏎` / `⇧⏎` | envoyer / nouvelle ligne |
| `⏎` après un résultat | envoyer un ajustement (« plus formel », « plus court »…) |
| `⌘⏎` ou `⌘C` | copier le résultat et fermer |
| `⌘.` | stopper la génération |
| `⌘N` | nouvelle conversation |
| `esc` | fermer (la conversation est conservée jusqu'à la copie) |

## Config

`~/.config/verto/config.json` (créé au premier lancement ; menu ✨ → « Éditer la config » puis « Recharger la config ») :

- `baseURL` : endpoint OpenAI-compatible (défaut Ollama `http://localhost:11434/v1`)
- `model` : vide = premier modèle listé par le serveur
- `apiKey`, `temperature`
- `hotkey` : ex. `option+space`, `ctrl+option+t`, `cmd+shift+space`
- `prefillFromClipboard` : pré-remplir le champ avec le presse-papiers
- `actions` : liste `{ "name", "prompt" }` — `prompt` vide = le texte saisi sert de prompt (« Libre »)

> Note : `⌥Space` sert à taper l'espace insécable sur clavier français ; change `hotkey` si tu l'utilises.
