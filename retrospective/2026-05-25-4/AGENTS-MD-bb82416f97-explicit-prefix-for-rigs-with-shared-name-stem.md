# agent instruction

**Set an explicit rig prefix when rig names share an auto-derivable stem.** `gc` auto-derives a 2-letter bead-ID prefix from a rig's name; rigs whose names share the same stem (e.g., `rig1` and `rig2` both derive `ri`) collide and refuse startup. Add `prefix = "r1"` / `prefix = "r2"` in city.toml's `[[rigs]]` block.

*Grounded in: `gc start: rig "rig2": prefix "ri" collides with rig1` blocked controller startup until explicit prefixes were added.*

# justification

`gc` derives a 2-character bead-ID prefix from a rig name so the bead store can scope beads per-rig (`r1-abc` for rig1, `r2-xyz` for rig2). When two rig names share their first two characters, both auto-derive the same prefix and the controller refuses to start with `prefix "<X>" collides with <rigA>`. The error names rigB (the second one) rather than the actual collision pair, which is confusing on first read. The fix is one line per rig in city.toml: `prefix = "r1"` and `prefix = "r2"`. Cost of the rule: one extra config line per rig. Cost of skipping: a startup failure whose error message doesn't obviously point at the fix.
