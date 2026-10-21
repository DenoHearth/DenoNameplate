# Changelog

## v1.5.1 — 2026-10-22

- Fixed: "DenoNameplate was forbidden from calling UNKNOWN()" every time a spell button was clicked with the mouse (key presses were fine). The Friendly and Enemy options handed the game's settings panel a function as their default value; the game ran it inside its own protected setup, and every mouse click on an action button read that setting list afterwards. The defaults are now plain values
- After switching between Standard and Modern style, the addon now tells you in chat to type /reload before pressing Defaults on the Friendly or Enemy page; until then Defaults puts back the sizes of the style you had before. The Style options say the same in their tooltips

## v1.5.0 — 2026-10-21

- New: incoming heals show on the health bar as a green part after the health
- New: absorb shields (Power Word: Shield and others) show as a white striped part after the health; a shield bigger than the missing health makes the end of the bar glow
- Both have a switch on the General page ("Show Incoming Heals", "Show Absorb Shields"), on by default
- The amounts come from the game's own heal prediction, the way Blizzard's raid frames draw them, so they work in combat

## v1.4.1 — 2026-10-19

- Fixed: "DenoNameplate was blocked from calling StanceButton:SetShown()" in fights (warriors and other classes with a stance bar). The addon now does its login setup a moment after login instead of during it, which tainted the game's own action bars for the whole session
- Fixed: pressing an ability with no target sometimes gave "forbidden from calling UNKNOWN()"; the click area is only changed while the game allows it, and set again after combat
- Fixed: the game's own nameplate could show under ours when a mob was engaged. The hidden game plate is now held invisible every frame and its own updates are switched off, as EllesmereUI and Tempus do
- View Distance tops out at 40 yards, the most Forever allows (a saved 60 becomes 40). The addon only writes the game's settings when the value really changes
- Diminishing returns no longer switch Blizzard's "diminishing returns on PvP enemies" option on by themselves; if it is off, one chat line per session says where to turn it on
- Fixed: an "attempt to call a nil value" error every frame in restricted combat

## v1.4.0 — 2026-10-19

- New Style choice (General): Standard, the familiar compact look and still the default, or Modern: the name above a tall health bar with one-decimal percent, a power bar under it (mana, energy or rage, following druid forms) and the cast bar with spell name, time left and the spell icon. The old Classic Style is gone; a saved Classic choice goes back to Standard
- "Modern Style On" puts Modern on enemy plates only (default) or on friendly plates too; "Modern Power Bar" shows the power bar on all units or players only. Mobs without a second resource get no empty bar
- Modern keeps its own Friendly and Enemy settings: with Modern picked, those pages change only Modern's look (including a new Power Bar Height), and Standard's settings stay as they were, and the other way round
- Enemy page: with Use Class Color off, enemy players take a colour you pick ("Enemy Player Color", in place of the background colour buttons). Mobs keep their usual colours

## v1.3.7 — 2026-10-19

- Click a nameplate to target: the plate itself is now the click area (the size set by Clickable Width and Height); before, you had to click the body. "Show Clickable Box" draws exactly that area
- Stacking nameplates work again: with stacking switched on in the game's settings, plates move apart instead of piling up
- Text outlines are smooth on every screen: the jagged Monochrome outlines are gone, and a saved Monochrome setting turns into its smooth version
- The addon no longer changes the game's name settings by itself. "Hide The Game's Large Names" (General) is off by default and now also covers player names; switching it off puts your own name settings back

## v1.3.2 — 2026-10-13

- New option "Hide The Game's Names On Mobs" (on by default): the game no longer writes its own large name over creatures that have no nameplate, so a mob is named once, on its nameplate. Quest givers, vendors and trainers keep their name; switching it off brings your own name settings back
- A mob tagged by another player has a clearly grey bar instead of a nearly white one

## v1.3.1 — 2026-10-12

- The crowd control icon over an enemy plate now shows anybody's crowd control, not only your own: a mob another player stunned or feared is marked too
- Diminishing returns count every kind of crowd control, whoever applied it, not only the kinds your own class has

## v1.3.0 — 2026-10-11

- Crowd control diminishing returns, left of the enemy plate: one icon per kind of crowd control, framed yellow (the next one lasts half), orange (a quarter) or red (immune), with the seconds until it resets; a grey icon is partly an estimate. Enemy players by default, hostile NPCs with a switch. The tracking is Forever Simple DR by Tarolg (MIT), built in with his licence
- Removable enemy buffs (right of the plate) show only while you can remove one: a Felhunter out, or a Shaman or Priest

## v1.2.1 — 2026-10-11

- Enemy bars keep their plain colour in a fight: the red threat glow no longer lies over every enemy you are fighting (it washed the bar out to pink). The target highlight takes the bar colour on friendly plates.

## v1.2.0 — 2026-10-08

- Enemy health bar turns orange in execute range (25% by default); enemy magic buffs that can be removed show in a blue frame beside the plate

## v1.1.0 — 2026-10-08

- Your own crowd control (Fear, Polymorph, Sap ...) shows as a larger icon over the middle of the enemy plate, with a glow and a red number in its last seconds; the small debuff row leaves it out

## v1.0.1 — 2026-10-07

- Fix aura timer text: the font it asked for does not exist on WoW: Forever, now the tiny game font with an outline

## v1.0.0 — 2026-10-06

- First release for WoW: Forever.
