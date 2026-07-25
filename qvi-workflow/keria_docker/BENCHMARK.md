# KERIA Docker workflow benchmark

## Method

The serial baseline is merged PR 56 at `04e1659`, with the PR 55 challenge
matrix restored to all eight relationships and 16 directed exchanges. Each
sample started after a clean Compose teardown and used the same fixture data,
image cache, timeout, and Docker allocation.

The optimized workflow retains the complete challenge, delegated rotation,
credential, reporting, and revocation assertions. Its first clean full proof
completed in 606 seconds. A subsequent focused run through final QVI
convergence measured the hardened query and member-sync lanes without paying
for the unchanged credential tail.

Measurements were taken on:

- MacBook Pro `MacBookPro18,2`;
- Apple M1 Max, 10 cores and 64 GB host memory;
- Docker Engine 29.6.2 with 8 CPUs and 10,418,937,856 bytes of memory.

## Results

| Variant | Clean wall-clock samples | Median or result |
| --- | --- | --- |
| Serial `04e1659` plus full challenge matrix | 827.56 s, 830 s, 828 s | 828 s median |
| First clean optimized full workflow | 606 s | 606 s |
| Hardened optimized setup through final QVI convergence | 307 s | 307 s |

The first complete optimized proof reduced wall time by 222 seconds, or
26.8%, against the serial median. The hardened QVI-focused run reduced the
same setup-plus-delegation section from 381 seconds to 307 seconds, a further
74-second or 19.4% reduction on that critical path.

The focused timing file reports 35 seconds for setup and 272 seconds for the
complete GEDA/QVI phase. Remaining slow operations are protocol or transport
waits rather than hidden shell sleeps:

- per-GAR QAR state-query lanes: up to 24 seconds;
- Signify member synchronization: 6–8 seconds;
- delegator refresh: 5–9 seconds;
- QVI endpoint authorization: 11 seconds.

## Behavioral evidence

The clean full optimized run proved:

- all 16 directed challenge exchanges;
- delegated QVI convergence at sequences 0–3 with final QAR1/QAR2/QAR4
  membership;
- all six credentials issued and admitted;
- active QVI, LE, and OOR callbacks;
- OOR and ECR convergence at TEL sequence `1`;
- Person observation of the revoked OOR;
- exact Sally rejection of the revoked OOR and the matching `rev` callback;
- clean teardown.

The later QVI-focused run re-proved the complete challenge matrix and QVI
sequences 0–3 after parallelizing only actor-disjoint GAR query lanes and
Signify observer lanes.
