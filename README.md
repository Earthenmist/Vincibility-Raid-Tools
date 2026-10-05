# Vincibility Raid Tools

Vincibility Raid Tools (VRT) is a raid-leading addon for Retail World of Warcraft, created for use in the **Vincibility** guild. It is fully usable by anyone who wants to run it in their own guild: nothing in it is tied to Vincibility, and every feature works for any raid team.

It brings together raid notes, boss-map drawings, reminders, cooldown assignments, group layouts, ready-check tools and aura call-outs in one place, and keeps them in step across your raid team.

VRT works with DBM, BigWigs or Blizzard's built-in boss warnings, so nobody in the raid has to install a particular boss mod to use it.

***

## ✨ Features

VRT gives a raid leader everything needed to plan a night and run each pull, and gives raiders what they need to know at the right moment.

You can:

*   Write raid and boss **text notes** that open by themselves for the raid leader when you reach the boss.
*   Draw boss plans on the real **boss map** with raid markers, role, class and boss symbols.
*   Build **reminders** with bars, icons, big text, countdown circles, sounds and optional text-to-speech.
*   Plan **cooldown and action assignments** on boss timelines, then have each player's own assignments count down in the fight.
*   Apply **group layouts** for soaks, split teams, healer spread and melee/ranged, and invite the night's sign-ups from the calendar.
*   Run **ready checks** with a raid overview, personal gear and buff warnings, a missing food/flask chat report and a one-click consumables bar.
*   Set up **aura call-outs**, a raid debuff overview and a co-tank debuff display, with defaults for the current raids.
*   Keep notes, reminders, assignments, the team roster and aura setups **in sync** with trusted guild members.
*   Back up and restore your data and settings.

***

## 👥 For Raid Members

You don't need to lead the raid to get the most out of VRT.

Raid members can:

*   See their own assignments count down in the fight, with a voice call-out or sound.
*   Get aura call-outs when a boss debuff lands on them, with their own on/off choice for each sound.
*   Check their consumables, enchants, gems and durability on every ready check, and use a missing flask, oil or rune with one click.
*   View the night's notes and boss drawings, and pop a drawing out to keep it on screen.
*   Move, resize and restyle every display to suit their UI.
*   Switch off any part of VRT they don't use in **Settings > Modules**.

Your display positions, sizes, sound choices and module switches are yours alone and are never synced.

***

## 🛡️ For Raid Leaders

Raid leaders and assistants get the planning and control tools.

These include:

*   Notes and boss drawings that open for the leader on reaching each boss, and can be sent to the raid.
*   An assignments timeline for each boss built from real kills, with cooldown, external, movement, utility and interrupt filters and raid-group assignments.
*   A **leader view** listing everyone's upcoming assignments during the pull, and a **test pull** to rehearse them.
*   Assignment plans sent automatically with your ready check.
*   A sign-up check that flags anyone assigned who has not signed up to the raid in the calendar.
*   Six group layouts, applied only when you choose, with groups 7–8 left as bench.
*   Calendar raid invites: signed-up players first, then tentative and standby once everyone signed up is in.
*   A compact **raid panel** for ready checks, break and pull timers, world markers and Main Tank assignment, with a party and raid preview in Settings.
*   A raid **ready-check overview** of everyone's food, flask, rune, oil, raid buffs, durability, item level and ping.
*   A **Versions** list showing who has VRT and whether their data matches yours.

***

## ✅ Designed With Raid Safety in Mind

VRT respects the game's addon restrictions and keeps raid actions in the leader's hands.

That means:

*   Nothing that moves players, assigns roles or starts timers happens without a button press. Group layouts are never re-applied automatically.
*   Protected actions such as Main Tank assignment and world markers use the game's secure buttons, and controls close or pause in combat.
*   VRT only reads information the game makes public. Restricted combat data is never guessed or reconstructed, and the boss timeline's hidden ability details are not used.
*   Changes from other players apply automatically only from people you trust: your raid leader and assistants, and guild members at or above the rank you choose. Everyone else needs **Accept**.
*   A backup is made before changes from someone else are applied, and a restore can itself be undone.
*   Your settings, positions and backups stay on your computer.

The aim is to make raid leading easier without taking control away from the leader.

***

## 🧭 Main Sections

| Section          |What it's for                                                                                |
| ---------------- |-------------------------------------------------------------------------------------------- |
| <strong>Notes</strong> |Raid and boss text notes with an editor, viewer and sharing                                   |
| <strong>Visual Notes</strong> |Boss-map drawings with markers and symbols, a viewer and a pop-out                        |
| <strong>Reminders</strong> |Timed and triggered reminders, their displays and sharing                                   |
| <strong>Assignments</strong> |Boss timelines, cooldown and action assignments, test pulls, leader view and sign-up checks |
| <strong>Groups</strong> |Group layouts and calendar raid invites                                                       |
| <strong>Ready Check</strong> |Raid overview, personal warnings, chat report and consumables bar                        |
| <strong>Auras</strong> |Aura call-outs, the raid debuff overview and co-tank debuffs                                    |
| <strong>Settings</strong> |General options, Modules, Sync, Versions and Backup &amp; Restore                             |

***

## 🔄 How Sync Works

After you log in, and shortly after you edit something, VRT compares its data with trusted guild members who also run it and transfers only what differs. Text notes, visual notes, reminders, assignment plans, the team roster and aura setups are covered. Group layouts and your personal settings are not synced.

The newest edit wins, timed by the realm's clock so a wrong computer clock cannot win. Deleting something removes it for everyone who syncs. Sync pauses in combat and during encounters, then resumes.

**Settings > Sync** sets which guild rank you trust and lets you send any kind of data to a player, your raid or the guild. **Settings > Versions** shows who has VRT and whether their data matches yours.

***

## 💬 Slash Commands

| Command         |What it does                                |
| --------------- |------------------------------------------- |
| <code>/vincui</code> |Open the main window                    |
| <code>/vincui notes</code> |Open a page directly (also <code>visual</code>, <code>reminders</code>, <code>assignments</code>, <code>groups</code>, <code>readycheck</code>, <code>auras</code>, <code>settings</code>) |
| <code>/vincui hide</code> |Close the main window              |
| <code>/vinc</code> |Open the raid panel                         |
| <code>/vinc hide</code> |Hide the raid panel                    |
| <code>/vincgroups</code> |Show the group layout status          |
| <code>/vincgroups stop</code> |Cancel pending group moves       |

The minimap button opens the main window on left-click and the raid panel on right-click.

***

## 📦 Installation

### CurseForge

The easiest way to install Vincibility Raid Tools is through the CurseForge app.

You can also download releases from CurseForge, Wago or the [GitHub releases page](https://github.com/Earthenmist/Vincibility-Raid-Tools/releases).

### Manual Installation

1.  Download the latest Vincibility Raid Tools `.zip`.

2.  Extract it into:

    `World of Warcraft/_retail_/Interface/AddOns/`

3.  Make sure the addon folder is called:

    `VincRaidTools`

4.  Restart World of Warcraft if it is already running.

***

## 🧩 Compatibility

*   **Client:** Retail World of Warcraft (Midnight).
*   **Boss mods:** DBM, BigWigs or Blizzard's built-in boss warnings. Everything loads and works without a boss mod, with the limits below.
*   **Voice call-outs:** VRT includes its own voice call-outs and countdowns. If a DBM voice pack is installed, DBM's lines are used where available.
*   **Language:** English. Boss-room detection for notes uses English room names.
*   **Dependencies:** None required. The libraries VRT uses are included with the addon.

### Without DBM or BigWigs

VRT still works with only Blizzard's built-in boss warnings, but a few things are more limited:

*   **Assignment timing:** countdowns run on each boss's typical timings and do not speed up or slow down with the kill. With DBM or BigWigs they follow the boss mod's own timers for each ability.
*   **Reminder triggers:** triggers based on boss phases, boss-mod messages or boss-mod timers do not fire. The reminder editor marks them "(DBM/BigWigs)" and warns you when neither is installed. Other triggers work normally.
*   **Blizzard's boss warnings:** the game hides which ability its timeline and warnings refer to, so VRT cannot react to them.
*   **Pull and break timers:** the pull countdown uses Blizzard's own countdown, and breaks show VRT's own break bar. Players running DBM or BigWigs still see your breaks, and you see theirs.
*   **Ping and durability:** the ready-check overview only shows these for players running VRT, DBM, BigWigs or another addon that shares them.

***

## 💬 Support

If you've found a bug, have a feature suggestion, want to see upcoming changes or would like access to beta builds, you're welcome to join the official Discord:

**Earthenmist - Addon Hub**

[https://discord.gg/U8mKfHpeeP](https://discord.gg/U8mKfHpeeP)

***

## 📜 License

All Rights Reserved.

Bundled third-party files keep their own licences, included beside them: LibStub (public domain), LibDurability and LibLatency (BSD-style), and the sound files in `Media/Sounds` (CC0 or CC BY 3.0, as noted with each set).

***

## ❤️ Credits

**Author:** Earthenmist

Vincibility Raid Tools is developed, tested and maintained by Earthenmist for the Vincibility guild. AI-assisted development tools are used where helpful for coding, debugging and documentation, but the direction, decisions and final implementation remain human-led.

Sounds: VRT's own voice call-outs, countdowns and alerts were made for VRT (see `Media/Sounds/VRT`); additional sounds by Kenney (CC0), soundbible.com authors Mike Koenig and Mr Smith (CC BY 3.0), and countdown voices by davidbain and tekgnosis (CC0).
