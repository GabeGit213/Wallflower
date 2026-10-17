<h1 align="center">🌿 Wallflower</h1>

<p align="center">
  <em>An artist's survivor for Don't Starve Together.<br>
  She studies the world, gets inspired, and draws it into existence.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/game-Don't%20Starve%20Together-8b5a2b?style=for-the-badge" alt="Don't Starve Together">
  <img src="https://img.shields.io/badge/type-character%20mod-6b8e23?style=for-the-badge" alt="Character mod">
  <img src="https://img.shields.io/badge/gameplay-fully%20playable-4f8a5b?style=for-the-badge" alt="Fully playable">
  <img src="https://img.shields.io/badge/art-in%20progress-c9a227?style=for-the-badge" alt="Art in progress">
</p>

<p align="center">
  <img src="assets/screenshot-ingame.png" alt="Wallflower standing next to Wilson in-game" width="85%">
</p>

---

## ✨ About

**Wallflower** is a from-scratch custom character for *Don't Starve Together*, drawn in the same ink-and-parchment style as the base game.

She's an artist, and a weak fighter. Her whole kit revolves around **observing** the world, getting **inspired** by it, and turning that inspiration into things she **conjures** into existence, including small helper creatures called **Doodle Warriors** who fight on her behalf.

<table>
  <tr>
    <td align="center" width="35%">
      <img src="assets/character-preview.png" alt="Wallflower character sprite" width="220"><br>
      <sub>Wallflower's sprite</sub>
    </td>
    <td valign="top">
      <h3>At a glance</h3>
      <ul>
        <li>🎨 <b>Role:</b> artist and summoner</li>
        <li>💡 <b>Special meter:</b> Inspiration (0–100)</li>
        <li>🔍 <b>Head slot:</b> The Artist's Monocle</li>
        <li>🖌️ <b>Hand slot:</b> The Visionary's Brush</li>
        <li>⚔️ <b>Combat:</b> deals only 0.75× damage, so she relies on her Doodle Warriors</li>
      </ul>
    </td>
  </tr>
</table>

---

## 🎮 How she plays

### 💡 Inspiration

A fourth HUD meter next to Health, Hunger, and Sanity, ranging from 0 to 100. It is the currency for everything Wallflower can create.

### 🔍 The Artist's Monocle (head slot)

Right-click an entity in the world to **Study** it.

- Every study grants **+5 Inspiration**.
- You can't gain Inspiration from the same *kind* of thing twice in one day. Two different trees on the same day only pay out once. This resets every in-game day.
- The **first time ever** you study something, it **permanently unlocks** something new to conjure:

| Studied | Unlocks |
|---|---|
| Natural resources (trees, boulders, berry bushes, grass, saplings, …) | **Everything they can drop.** Studying a tree unlocks logs *and* pinecones. |
| Structures and craftable items (campfires, chests, sculptures, anything with a normal recipe) | **Themselves** |
| The 9 replica animals (see below) | Their **Doodle Warrior** replica |
| 10 trees, 10 berry bushes, or 10 boulders (repeats count) | One of the 3 **achievement** Doodle Warriors |

### 🖌️ The Visionary's Brush (hand slot)

The Brush is also her weapon, though it hits softer than a normal one. Its **right-click** depends on where you aim:

| Aim at | Action | What happens |
|---|---|---|
| **Wallflower herself** | **Conjure Item** | Opens a menu of everything you've unlocked by studying. Pick one to spend Inspiration and receive the item (structures open the normal placement UI). |
| **Empty ground** | **Summon Warrior** | Opens a menu of your unlocked Doodle Warriors. Pick one to spend Inspiration and summon it next to her. |
| **Any other entity** | none | Normal actions like Study or Attack still appear as usual. |

### 🐾 Doodle Warriors

Temporary or standing combat allies summoned with the Brush.

- They **follow Wallflower** and fight whatever she fights, whatever hits her, or whatever hits them.
- They also engage genuinely hostile monsters on sight, but won't pick fights she hasn't started.
- They **drop no loot** when killed.
- The **Dismiss All Warriors** button in the Summon menu removes every active warrior at once.

**9 basic replicas.** Unlocked by studying the live animal. Each reuses the real creature's stats and behavior, with 1 active at a time.

| | | | |
|---|---|---|---|
| 🐝 Bee *(group of 5)* | 🐷 Pig Man | 🐸 Frog | 🧜 Merm |
| 🐃 Beefalo | 🐰 Bunnyman | 🐱 Catcoon | 🐧 Pengull *(group of 5)* |
| ⚡ Volt Goat | | | |

**3 achievement warriors.** Unlocked by the 10-of-a-kind study tallies. They have custom stats, a capped count, and a limited lifespan.

| Warrior | Borrowed from | HP | Damage | Max active | Lifespan |
|---|---|---|---|---|---|
| 🌳 **Treevor** | Treeguard | 300 | 50 | 2 | 15 s |
| 🦃 **Berrtha** | Gobbler | 100 | 20 | 3 | 30 s, and grants nearby passive HP regen while alive |
| 🪨 **Bouuldozer** | Clockwork Rook | 500 | 60 *(slower attacks)* | 1 | 10 s |

---

## 📦 Installation

1. Download this repository (**Code → Download ZIP**) or clone it:
   ```bash
   git clone https://github.com/<your-username>/<your-repo>.git
   ```
2. Copy the mod folder into your DST mods directory:
   - **Windows:** `Documents\Klei\DoNotStarveTogether\mods\`
   - **macOS:** `~/Documents/Klei/DoNotStarveTogether/mods/`
   - **Linux:** `~/.klei/DoNotStarveTogether/mods/`
3. Launch the game, open **Mods**, and enable **Wallflower**.
4. Create or join a world with the mod enabled and pick Wallflower on the character select screen.

> 💡 For multiplayer, the host and every player need the mod enabled (or subscribed to, if it's on the Steam Workshop).

---

## 🗂️ Project structure

```
wallflower/
├── anim/                    # Compiled animation bundles (wallflower.zip, ghost_wallflower_build.zip)
├── exported/                # Spriter source projects (esctemplate, ghost rig)
├── images/                  # Portraits, avatars, minimap icon, name graphics
├── bigportraits/            # Big portrait art
├── scripts/
│   ├── prefabs/             # Character, skin, Monocle, Brush
│   ├── components/          # inspiration.lua: Study, unlock, and cost logic
│   ├── screens/             # Conjure Item and Summon Warrior menus
│   ├── brains/              # Shared Doodle Warrior AI
│   ├── util/                # Doodle Warrior spawn, caps, and save/load logic
│   └── speech_wallflower.lua
├── modinfo.lua              # Mod metadata
└── modmain.lua              # Recipes, HUD badge, actions, RPC handlers, strings
```

---

## 🛠️ Development

Wallflower is built with Klei's official **Don't Starve Mod Tools** (free on Steam):

- **Spriter** for the character's animation rig. The art is drawn on top of Klei's ESC Template rig, which already includes every survivor animation.
- **Autocompiler** for turning exported art into the `.zip` animation bundles and `.tex`/`.xml` image files the game reads.

Tips:

1. Clone the repo straight into your DST `mods` folder so the game picks up changes.
2. In-game, press `Ctrl + R` to reload the world and test changes quickly.
3. Check `client_log.txt` in the Klei folder if something doesn't load.

---

## 🗺️ Roadmap

### ✅ Done

- [x] Inspiration meter and HUD badge
- [x] Study system: daily limits and permanent unlocks
- [x] The Artist's Monocle
- [x] The Visionary's Brush with context-sensitive Conjure and Summon actions
- [x] Conjure Item menu
- [x] Summon Warrior menu, including **Dismiss All**
- [x] 9 replica Doodle Warriors
- [x] 3 achievement Doodle Warriors (Treevor, Berrtha, Bouuldozer)
- [x] Shared Doodle Warrior AI: follow Wallflower and fight her fights
- [x] Warrior caps, lifespans, and save/load support
- [x] Weaker-fighter balancing (0.75× damage, softer Brush)
- [x] Wallflower's character art drawn and imported
- [x] Save-slot portrait, minimap icon, and HUD avatars

### 🔧 In progress

- [ ] Character-select screen portraits, silhouette, and name graphics
- [ ] Fine-tune character assets position, size and scale in-game
- [ ] Character-select title, quote, and description
- [ ] Custom speech lines (`speech_wallflower.lua`)

### 📝 To do

- [ ] Ghost form art
- [ ] Final crafting recipes for the Monocle and Brush
- [ ] Custom art for the Monocle and Brush (currently reusing the Gardeneer Hat and Spear)
- [ ] Custom inventory icons for the Monocle and Brush
- [ ] Icons for the Summon Warrior menu (only Bee has one so far)
- [ ] Steam Workshop release

### 💭 Maybe someday

- [ ] Sketchy, crayon-style reskins of the Doodle Warriors, so they look like her drawings
- [ ] Further balance tuning of Inspiration costs and warrior stats
- [ ] Rename the compiled build from `esctemplate` to `wallflower`

---

## 🤝 Contributing

Bug reports, feedback, and ideas are welcome. Feel free to open an [issue](../../issues).

---

## 🙏 Credits

- **Concept, writing, and art:** Șalvar Gabriel
- **Code:** implemented with [Claude](https://claude.com) via Claude Code
- Built for *Don't Starve Together* by [Klei Entertainment](https://www.klei.com/)

*This is an unofficial fan-made mod and is not affiliated with or endorsed by Klei Entertainment.*

---

## 📄 License

Released under the [Klei License](LICENSE).
