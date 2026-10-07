# Project Viewpoint ADS + Gael Gun Store Compatibility

A work-in-progress compatibility mod for Project Zomboid Build 42.21. It adds Viewpoint ADS profiles for 50 Gael Gun Store optics, improves eye relief on large scopes, provides a sight-line baseline for Gael's AK-74, and adds provisional ADS baselines for 22 pistols. Existing player calibrations can override these defaults.

**Maintenance:** One person maintains this project and updates it sporadically. Fixes, tested calibration data, and documentation improvements are welcome through [GitHub issues and pull requests](https://github.com/AlhuayOscar/Viewpoint-ADS-Gael-Gun-Store-Compatibility).

## Requirements

- Project Zomboid Build 42.21 or newer
- Gael Gun Store B42 (`GaelGunStore_B42`)
- Project Viewpoint ADS (`ProjectViewpointADS`)

Enable the dependency mods before this compatibility mod. This package is client-side. It does not include either dependency.

## Installation

Subscribe to all required Workshop items and enable the mod ID `PVADSGaelOptics`. For a manual install, copy `Contents/mods/PVADSGaelOptics` into `Zomboid/mods/` and restart the game. Disable older local copies of this compatibility mod and the separate `PVADSGaelPistolBaseline` test mod to avoid duplicate profile registration.

## Status and limitations

This is a WIP. Many weapon and optic offsets are provisional and still need in-game calibration. The [weapon checklist](docs/GaelGunStore_B42_checklist_EN.xlsx) tracks manually completed entries separately from automated baselines. A yellow **Done/Automated** row means a default profile exists; it does not claim that the weapon has been individually verified in game. Gael Gun Store's own sight overlays should be disabled when using Viewpoint ADS to avoid overlapping views. Results can vary by weapon model, optic, animation, and Viewpoint ADS version.

Report a problem with the game build, versions of both required mods, weapon and optic item IDs, screenshots, and `Zomboid/console.txt` errors. Include an F9 Viewpoint calibration when possible.

## Workshop upload

This repository contains the Workshop-ready `workshop.txt`, `preview.png`, and `Contents/mods/PVADSGaelOptics` layout. Copy `workshop.txt`, `preview.png`, and `Contents/` to one folder under `Zomboid/Workshop/`, open Project Zomboid's Workshop uploader, and create or update the item. Keep `id=` empty until Steam assigns an item ID. Steam publication has not been performed from this repository.

The cover image was supplied by the project owner. Project Zomboid, Project Viewpoint ADS, and Gael Gun Store belong to their respective owners. This compatibility project is independent and does not redistribute those mods.

