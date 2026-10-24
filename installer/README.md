# Install Overlapse on a Steam Deck

1. Switch the Deck to **Desktop Mode** (Steam button → Power → Switch to Desktop).
2. Open **Konsole** (app launcher → System → Konsole).
3. Paste this line (Ctrl+Shift+V) and press Enter:

   ```
   curl -fsSL https://raw.githubusercontent.com/mremad/overlapse-builds/main/installer/install.sh | bash
   ```

4. When it says **Done**, go back to **Gaming Mode**. Overlapse is in your library with its art.

**Updating:** run the same line again, or in the game open *Settings → Updates → Check for updates online*.

**No terminal?** Download `Install Overlapse.desktop` from this folder to the desktop, right-click it →
*Properties → Permissions →* tick *Is executable*, then double-click it.

The installer puts the game in `~/Games/Overlapse`, adds it to Steam as a non-Steam game (once) with its
capsule, banner, hero, logo and icon, and never touches your saves. Steam closes for a moment while
the library entry is added and starts again by itself.
