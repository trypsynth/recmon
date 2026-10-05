# Recmon

Recmon is a [Hammerspoon](http://hammerspoon.org) spoon that allows you to obtain information about your CPU load, drive usage, etc at the press of a button.

## Installation

First, download and install Hammerspoon. You can do so either [from their Github](https://github.com/Hammerspoon/hammerspoon/releases/latest), or if you have it installed, through homebrew simply by running:

```bash
$ brew install Hammerspoon
```

in the terminal. Once you have it installed, run it, and follow the prompts to grant accessibility permissions (I also choose to hide the app from the dock here so it stays out of your command-tab switcher)

You also need to allow external apps to control VoiceOver through Apple Script. To do so, open VoiceOver utility with VO + f8, navigate to the "General" section and check the "Allow VoiceOver to be controlled with AppleScript" checkbox.

Once Hammerspoon is installed and configured, navigate into the folder where you cloned this repository with Finder or another file manager, and open "Recmon.spoon" which should cause Hammerspoon to install it into the right place. Finally, from the Hammerspoon menu extra select the open configuration option which should open your default text editor with your init.lua file. To make Recmon work and do its thing, simply add the following 2 lines:

```lua
hs.loadSpoon("recmon")
spoon.recmon:start()
```

Save the file, return to the Hammerspoon menu extra but this time click the reload configuration option for your new changes to take effect. Mac OS will warn you that Hammerspoon is trying to control Voice Over. Grant it permission and the spoon should start working.

## Features

To use each feature, simply press ctrl+shift+the number next to it.

1. Speak average CPU load, and how its distributed.
2. Speak RAM usage (not working yet, see todo).
3. Speak storage information about all connected drives.
4. Speak the macOS version: its name, version number and build, e.g. "macOS Golden Gate, 27.0.1, build 26A434". The name comes from a table in the spoon, as macOS doesn't store it anywhere readable; add new releases there.
5. Speak system uptime.
6. Speak battery percentage, state, and time remaining.
7. Speak your default output device, its volume, and whether it's muted.
8. Speak your default input device, its volume, and whether it's muted.
9. Speak the text that's currently on your clipboard/pasteboard (if any).
0. Speak the five processes using the most CPU, with their percentages. This takes about a second, as it samples CPU use fresh, like Activity Monitor does. Percentages can go over 100%, since a process can use more than one core. An app with several processes can appear more than once: Safari, for example, runs separate "Safari Web Content" processes for different web pages, so two busy pages show as two entries.

## Todo

* Add RAM usage. I couldn't find a reliable way to obtain RAM usage like Activity Monitor does, because the Mac had to be a special snowflake and introduce app memory and document no way to obtain it other than activity monitor. The outline for RAM usage is there, and the hotkey is bound, it just doesn't do anything yet.

## Contributing

If there's a feature you'd like to see added, feel free to open a pull request/issue. I'd prefer issues get opened before forging ahead with huge pull requests, unless the feature is already on the todo list.

## Credits

Instillation instructions adapted from [Indent Beeper](https://github.com/pitermach/IndentBeeper), and [Speech History](http://github.com/mikolysz/speech-history).
