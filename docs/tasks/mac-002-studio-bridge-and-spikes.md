# mac-002 — Studio bridge, device emulation and the asset-fetch spike

**Kind:** environment and spikes. Run on the MacBook after mac-001.

## Goal

The Mac can run a scripted playthrough with screenshots per device class,
and the two spikes the plan leaves to the Mac are decided.

## Must

1. **Playthrough script** in `tools/studio-playtest/`: open the built
   place, start Play, drive the fake-player walkthrough through the Studio
   MCP server, capture a screenshot at every Shot, chapter card and Scene
   entry with `screencapture`, stop Play, write a JSON report; exit
   non-zero on failure.
2. **Device emulation spike.** Can Studio's device emulation be switched
   from a script? If yes, capture for a phone and a tablet preset in both
   orientations. If no, resize the Studio window to each aspect ratio by
   AppleScript and record that DPI-dependent checks use the emulated
   scale from `feel.md`. Write the decision into `docs/MAC_RUNNER.md` and
   the plan's section 4.
3. **Asset-fetch spike** (plan 5.5): from the Mac, insert a free Creator
   Store model through the MCP server and save it as `.rbxm` under
   `assets/meshes/` with a manifest entry; compare with the Luau Execution
   path the cloud agent tried; record the winner in the plan.
4. **Workflow** `studio-playtest.yml` on `workflow_dispatch` and on the
   `needs-playtest` label, `continue-on-error` on PRs, uploading the
   screenshots and report; Studio version pinned and reported.

## Done when

The coordinator triggers the workflow from the cloud and receives
screenshots for PC, phone and tablet.
