# agent instruction

**Put rig path bindings in `.gc/site.toml` not `city.toml`.** PackV2+ rejects `[[rigs]].path` in city.toml as a pre-1.0 site-binding field. The path goes into `.gc/site.toml` as a `[[rig]]` block (singular, not `[[rigs]]`). City.toml carries only the rig name + prefix + default_branch; the on-disk path is machine-local.

*Grounded in: `gc start: strict: unsupported pre-1.0 rig.path for rig "rig1"; move it to .gc/site.toml` halted startup.*

# justification

Earlier versions of gascity let `city.toml` carry rig path bindings directly via `[[rigs]] path = "/workspace/rigs/rig1"`. PackV2+ separates machine-local site bindings from portable pack/city config: the city.toml is the portable artifact, and `.gc/site.toml` is the machine-local layer that says "here's where this machine has rig1 checked out." On a working PackV2 install, `city.toml` declares `[[rigs]] name = "rig1" prefix = "r1"` and `.gc/site.toml` declares `[[rig]] name = "rig1" path = "/workspace/rigs/rig1"`. Two surprising parts: the block name is `[[rig]]` (singular) in site.toml but `[[rigs]]` (plural) in city.toml, and the file is `site.toml` inside `.gc/`, not at the city root. The controller's error message points at the fix path but doesn't tell you about the singular-vs-plural rename. This rule front-loads both surprises so the entrypoint generates the site.toml correctly on first try.
