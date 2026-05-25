# agent instruction

**Set `init: true` in docker-compose for stacks that fork many short-lived children.** Any container whose PID 1 spawns lots of short-lived subprocesses (bd shelling out to dolt, build tools, polling daemons) must run under `tini` (via compose `init: true` or `docker run --init`). Otherwise the process table fills with zombies within seconds because PID 1 doesn't reap.

*Grounded in: bd's frequent dolt subprocess shells produced 50+ zombies within minutes when the controller ran as PID 1 without an init wrapper.*

# justification

PID 1 in a Linux container has a special responsibility: it inherits orphan processes when their original parent dies, and it must `wait()` on them to release their entries in the process table. A typical user-process (a controller binary, a webserver) wasn't designed for this and doesn't reap. The result is "defunct" entries piling up — first dozens, then hundreds, until the kernel's PID limit is hit. In this session, `gc start --foreground` running as PID 1 plus `bd`'s habit of shell-outing to `dolt` for every bead operation produced 50+ zombies in under a minute. Adding `init: true` to compose (which inserts `tini` as the real PID 1 and runs the controller as PID 7) fixed it on the next restart with zero application changes. The marginal cost of `init: true` is two tokens and a +1 MB image surface. The cost of skipping it is "the city silently degrades within an hour."
