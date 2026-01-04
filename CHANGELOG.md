### Version 0.08-ALPHA [ January 04 2026 ]

#### Bugfixes

- [Breaking] Addressed an issue where addon configuration and saved data may persist across profiles/characters when it should not
  - Updating to this version of the addon will likley cause loss of some configuration. If you are encountering errors, please use the new function to clear addon data in: `Developer Tools` -> `Databases` -> `Danger Zone` -> `Clear ALL Addon Data`

#### Improvements/New Features

- Completely refactored the synchronization logic of the Mythic+ run recordings used for development purposes
- Added a button to completely clear the run recording database
- Refactored developer configuration to make more sense; a new "Mythic+" tab is available with sub-tabs for each section
- Added new fonts: Exo2 and Inter (Google Fonts)
- Added ability to reset all addon data to start "clean"
