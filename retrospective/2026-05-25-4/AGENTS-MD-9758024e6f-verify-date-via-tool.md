# agent instruction

**Verify today's UTC date via a tool call.** Never write a date into a filename, commit message, or ADR header from memory. Run `date -u +%Y-%m-%d` (or the python3 / node equivalents) and use that value. If the environment supports more than one, run two and confirm they agree.

*Grounded in: every filename and frontmatter date in this session was driven from a verified `date -u` invocation per the self-retrospective skill's Step 0.*

# justification

Models routinely guess "today" off by years. This session's training data is from a period that doesn't match the actual UTC date, and a guessed-from-memory date would have produced wrong filenames in `retrospective/`, wrong dates in ADR headers, and a wrong link in the README's lookup index. The cost of verifying is one shell call (<1 s) returning a string. The cost of getting it wrong is silent: a retrospective filed under a date that doesn't match any PR, or an ADR whose date drifts a year. The self-retrospective skill mandated this check at Step 0 and saved the day for this very retrospective.
