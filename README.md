# EasyFind: HandyNotes Extension

HandyNotes and its plugins put thousands of pins on the map with no way to search them. This extension puts them in EasyFind's search bar: type a pin's name to find it, and a click asks EasyFind's GPS for directions to it. In development.

Requires HandyNotes and EasyFind.

## Dependencies

- EasyFind, with its extension API (EasyFind.API version 1).
- HandyNotes 1.6, which this addon reads at runtime through its plugin interface. Nothing of HandyNotes' or any plugin's is copied into this addon.

## How it reads HandyNotes

The addon reads pins the way HandyNotes' own map does, through each plugin's pin iterator, so a plugin's own settings apply to the search too. If a function it needs is missing in the installed HandyNotes version, pin search turns itself off with one line in chat and nothing else changes. HandyNotes' and its plugins' settings are never written.
