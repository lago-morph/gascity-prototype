# agent instruction

**Do not directly import a pack that is already transitively imported.** Before adding `[imports.<name>]` to a pack.toml, check whether any pack you're already importing transitively imports it. If yes, the city will refuse to start with a 'duplicate agent name' error and the fix is to remove your direct import, not rename the transitive one.

*Grounded in: directly importing maintenance alongside gastown collided gastown.dog (defined twice — once via direct import, once via gastown's own `../maintenance` import).*

# justification

Pack composition in Gas City is transitive: `[imports.gastown]` brings in everything gastown imports too. The bundled gastown pack already imports `maintenance`, which defines a `dog` agent. Declaring our own `[imports.maintenance]` alongside it produced the error `agent "gastown.dog": duplicate name (from .../maintenance and .../maintenance)` and the controller refused to start. The fix is a one-line removal: drop the redundant direct import. The cost of the rule is one extra glance at the imported pack's pack.toml at composition time. The cost of skipping is "the city won't start and the error message points at the imported pack rather than at the duplicate-import in your own pack.toml."
