# Baselines

The accepted screenshots of the Story: one **Baseline** per **Capture** per
device, which every Studio playtest compares its Captures with (plan
section 4, level 2; brief mac-003; docs/GLOSSARY.md).

```
docs/screens/<device>/<nn>-<kind>-<name>.png
```

`<device>` is a device of the playthrough (`pc`, `phone-landscape`,
`phone-portrait`, `tablet-landscape`, `tablet-portrait`); `<kind>` is
`shot`, `card`, `scene` or `title`; `<name>` is the Shot, Chapter card,
Scene or `title`, in lower case with hyphens. The files are exactly what
the playthrough on the Mac wrote (`docs/MAC_RUNNER.md`, "The playthrough").

**How they are made.** Never by hand, and never pushed by a job. Run the
**Baselines** workflow (`.github/workflows/baselines.yml`) from `main`:
it takes the latest passing Studio playtest of `main` (or the run whose id
it is given), checks that every device played to the end, and opens or
updates one pull request titled "Baselines" that replaces every PNG here
with that run's Captures. Its Files changed tab shows each changed image
before and after. Merging it accepts them.

**How they are used.** After every playtest, the `sheets` job of
`studio-playtest.yml` pairs each Capture with the Baseline of the same
device, kind and name (the number is ignored, so a new Capture does not
unpair the rest) and compares them with ImageMagick: a Capture has changed
when more than 1% of its pixels moved by more than 10%, or its size
changed (`tools/lib/screens.luau`). The pull request's comment shows each
changed Capture's before, after and difference
(`docs/MAC_RUNNER.md`, "Screenshots on a pull request").

**When to change them:** when a pull request changes what is on screen on
purpose. After it merges, a playtest of `main` and a Baselines pull
request make its look the new Baseline, as plan section 4 asks: baselines
change deliberately, and the change is reviewed as a picture.

Until the first Baselines pull request merges (brief mac-003, Must B8)
this folder holds only this file, and every Capture shows as new.
