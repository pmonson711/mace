----------------------------- MODULE MaceStoreETS ----------------------------
EXTENDS Naturals, Sequences, FiniteSets, TLC

(***************************************************************************)
(* Model of Mace.Store with ETS-backed config storage (no Registry).       *)
(*                                                                         *)
(* Key differences from Registry-based approach:                           *)
(*   1. Config stored in a passive ETS table — no GenServer, no IPC.       *)
(*   2. No Registry PID to exclude from candidate_pids.                    *)
(*   3. A background monitor process watches config-owning PIDs.           *)
(*      On DOWN it removes both config (ETS delete) and cache (flush).     *)
(*   4. Fallthrough fetch: walk continues when ancestor lacks the key.     *)
(*                                                                         *)
(* Design doc: doc/specs/2025-07-18-tla-store-model-design.md              *)
(***************************************************************************)

\* -------------------------------------------------------------------------
\* CONSTANTS — model values defined in .cfg
\* -------------------------------------------------------------------------
CONSTANTS
  Pids,          \* Set of process IDs (e.g. {p1, p2, p3})
  Apps,          \* Set of application names (e.g. {a1})
  Keys,          \* Set of config keys (e.g. {k1, k2})
  Values         \* Set of config values (e.g. {v1, v2})

\* Special sentinel config values
NoConfig  == "no_config"
Tombstone == "tombstone"

\* Fetch result sentinels (must not collide with Values)
FetchErr  == "FETCH_ERROR"
FetchNil  == "FETCH_NIL"

\* All possible config values a key can hold
ConfigVals == Values \cup {NoConfig, Tombstone}

\* Source-tag labels for BFS queue entries
SrcLinks       == "links"
SrcMonitoredBy == "monitored_by"

\* Pseudo-NONE for tree walk
WalkNone == "WALK_NONE"

\* -------------------------------------------------------------------------
\* VARIABLES
\* -------------------------------------------------------------------------
VARIABLES links, monitors, config, terminated, cache

vars == <<links, monitors, config, terminated, cache>>

\* -------------------------------------------------------------------------
\* TYPE INVARIANT (checked in .cfg)
\* -------------------------------------------------------------------------
TypeOK ==
  /\ links     \in [Pids -> SUBSET Pids]
  /\ monitors  \in [Pids -> SUBSET Pids]
  /\ config    \in [Pids -> [Apps -> [Keys -> ConfigVals]]]
  /\ terminated \subseteq Pids
  /\ cache     \subseteq (Pids \X Apps \X Keys)

\* -------------------------------------------------------------------------
\* TOPOLOGY CONSTRAINT (ExUnit-realistic)
\*
\* Constraint 1: links are symmetric
\* Constraint 2: no self-edges (simplifying assumption)
\* Constraint 3: monitors form a DAG — no cycles (simplifying assumption)
\* Constraint 4: if p monitors q, they are also linked
\* Constraint 5: every link crosses a monitor boundary (no orphan sibling links)
\* -------------------------------------------------------------------------

(* Transitive closure of monitor relation from pid, bounded by |Pids| steps *)
MonitorsTC(m, p) ==
  LET RECURSIVE Recurse(_, _)
      Recurse(from, depth) ==
        IF depth = 0 THEN {}
        ELSE
          LET nxt == {q \in Pids : q \in m[from]}
          IN  nxt \cup UNION {Recurse(r, depth-1) : r \in nxt}
  IN  Recurse(p, Cardinality(Pids))

ExUnitRealistic ==
  (* 1 *)  /\ \A p, q \in Pids : q \in links[p] <=> p \in links[q]
  (* 2 *)  /\ \A p \in Pids : p \notin links[p] /\ p \notin monitors[p]
  (* 3 *)  /\ \A p \in Pids : p \notin MonitorsTC(monitors, p)
  (* 4 *)  /\ \A p, q \in Pids : q \in monitors[p] => q \in links[p]
  (* 5 *)  /\ \A p, q \in Pids : (q \in links[p] /\ p /= q)
                => (q \in monitors[p] \/ p \in monitors[q])

\* -------------------------------------------------------------------------
\* CONFIG PREDICATES
\* -------------------------------------------------------------------------

HasConfig(pid) ==
  \E app \in Apps, key \in Keys : config[pid][app][key] /= NoConfig

HasSpecificConfig(pid, app, key) ==
  config[pid][app][key] \notin {NoConfig, Tombstone}

(* Whether the key is explicitly set (value or tombstone), not missing *)
HasKeySet(pid, app, key) == config[pid][app][key] /= NoConfig

\* -------------------------------------------------------------------------
\* CANDIDATE PIDS (matching store.ex:210-225)
\* -------------------------------------------------------------------------

Candidates(pid, source) ==
  IF source = SrcLinks THEN
    ({<<q, SrcLinks>>       : q \in links[pid]}
      \cup
     {<<q, SrcMonitoredBy>> : q \in monitors[pid]})
  ELSE
    {<<q, SrcMonitoredBy>> : q \in monitors[pid]}

\* -------------------------------------------------------------------------
\* TREE WALK (BFS matching store.ex:193-208)
\* -------------------------------------------------------------------------

(* Convert a set of <<pid, src>> pairs to a sequence.
   Non-deterministic ordering models Registry insertion order. *)
RECURSIVE SeqFromSet(_)
SeqFromSet(S) ==
  IF S = {} THEN <<>>
  ELSE LET elem == CHOOSE e \in S : TRUE
       IN  <<elem>> \o SeqFromSet(S \ {elem})

RECURSIVE BFS(_, _)
BFS(queue, seen) ==
  IF queue = <<>> THEN WalkNone
  ELSE
    LET entry == Head(queue)
        pid   == entry[1]
        src   == entry[2]
    IN
      IF pid \in seen
      THEN BFS(Tail(queue), seen)
      ELSE
        IF HasConfig(pid)
        THEN pid
        ELSE
          LET newQ == Tail(queue)
                        \o SeqFromSet(Candidates(pid, src))
          IN  BFS(newQ, seen \cup {pid})

\* -------------------------------------------------------------------------
\* FETCH OPERATORS
\* -------------------------------------------------------------------------

(* Fetch without cache — fallthrough on key miss.
   Continues walking when an ancestor has config but lacks the specific key.
   Returns: value from Values, FetchNil for tombstones, FetchErr on miss. *)

RECURSIVE FetchWalk(_, _, _, _, _)
FetchWalk(pid, app, key, queue, seen) ==
  IF queue = <<>> THEN FetchErr
  ELSE
    LET entry == Head(queue)
        cur   == entry[1]
        src   == entry[2]
    IN
      IF cur \in seen
      THEN FetchWalk(pid, app, key, Tail(queue), seen)
      ELSE
        IF HasConfig(cur)
        THEN
          CASE config[cur][app][key] = Tombstone -> FetchNil
            [] HasSpecificConfig(cur, app, key) -> config[cur][app][key]
            [] OTHER -> FetchWalk(pid, app, key,
                            Tail(queue) \o SeqFromSet(Candidates(cur, src)),
                            seen \cup {cur})
        ELSE
          FetchWalk(pid, app, key,
            Tail(queue) \o SeqFromSet(Candidates(cur, src)),
            seen \cup {cur})

FetchRaw(pid, app, key) ==
  IF pid \in terminated THEN FetchErr
  ELSE FetchWalk(pid, app, key, <<<<pid, SrcLinks>>>>, {})

(* Fetch with negative cache *)
FetchCached(pid, app, key) ==
  IF <<pid, app, key>> \in cache
  THEN FetchErr
  ELSE FetchRaw(pid, app, key)

\* -------------------------------------------------------------------------
\* REFERENCE REACHABILITY (free transitive closure over links + monitors,
\*                         excluding terminated PIDs)
\* -------------------------------------------------------------------------

LiveAncestors(p) ==
  LET G(q) == {r \in Pids : (r \in links[q] \/ r \in monitors[q]) /\ r \notin terminated}
      RECURSIVE Reach(_, _)
      Reach(q, depth) ==
        IF depth = 0 THEN {}
        ELSE
          LET nxt == G(q)
          IN  nxt \cup UNION {Reach(r, depth-1) : r \in nxt}
  IN  {p} \cup Reach(p, Cardinality(Pids))

\* -------------------------------------------------------------------------
\* ACTIONS
\* -------------------------------------------------------------------------

Init ==
  \E lFn \in [Pids -> SUBSET Pids],
      mFn \in [Pids -> SUBSET Pids] :
    /\ links     = lFn
    /\ monitors  = mFn
    /\ ExUnitRealistic
  /\ \E cfgFn \in [Pids -> [Apps -> [Keys -> ConfigVals]]] :
       config = cfgFn
  /\ terminated = {}
  /\ cache = {}

Terminate(pid) ==
  \* BEAM: when a process exits, links break bidirectionally and
  \* monitors are dropped from the surviving processes.
  /\ pid \notin terminated
  /\ terminated' = terminated \cup {pid}
  \* Clear the dead pid's config (Registry cleanup)
  /\ config' = [p \in Pids |->
       IF p = pid
       THEN [app \in Apps |-> [key \in Keys |-> NoConfig]]
       ELSE config[p]]
  \* Break all links involving the dead pid (bidirectional)
  /\ links' = [p \in Pids |->
       IF p = pid THEN {}
       ELSE links[p] \ {pid}]
  \* Remove the dead pid from all monitored_by lists.
  \* The dead pid's own monitors list also clears (it monitors nobody).
  /\ monitors' = [p \in Pids |->
       IF p = pid THEN {}
       ELSE monitors[p] \ {pid}]
  /\ cache' = {}  \* flush stale cache on termination (topology changed)

FetchAction(pid, app, key) ==
  /\ pid \notin terminated
  /\ LET result == FetchCached(pid, app, key)
     IN  /\ IF result = FetchErr
            THEN cache' = cache \cup {<<pid, app, key>>}
            ELSE UNCHANGED cache
         /\ UNCHANGED <<links, monitors, config, terminated>>

Next ==
  \E p \in Pids : Terminate(p)
  \/ \E q \in Pids, a \in Apps, k \in Keys : FetchAction(q, a, k)

Spec == Init /\ [][Next]_vars

\* -------------------------------------------------------------------------
\* INVARIANTS
\* -------------------------------------------------------------------------

(* I1 — Link Inheritance *)
LinkInheritance ==
  \A p, q \in Pids, a \in Apps, k \in Keys :
    (p \notin terminated /\ q \in links[p] /\ q \notin terminated
     /\ HasSpecificConfig(q, a, k))
    => FetchRaw(p, a, k) /= FetchErr

(* I2 — Monitor Inheritance:
   If q monitors p (so q is in p's monitored_by list) and q has config,
   then p's fetch must return q's config. *)
MonitorInheritance ==
  \A p, q \in Pids, a \in Apps, k \in Keys :
    (p \notin terminated /\ q \in monitors[p] /\ q \notin terminated
     /\ HasSpecificConfig(q, a, k))
    => FetchRaw(p, a, k) /= FetchErr

(* I3 — Isolation (no cross-chain leak):
   If no live ancestor has the key set (neither value nor tombstone),
   then fetch must return error. *)
Isolation ==
  \A p \in Pids, a \in Apps, k \in Keys :
    (p \notin terminated
     /\ \A q \in LiveAncestors(p) : ~HasKeySet(q, a, k))
    => FetchRaw(p, a, k) = FetchErr

(* I4 — No False Negatives:
   If any live ancestor has config for (a,k) (value or tombstone),
   fetch must not return error. *)
NoFalseNegatives ==
  \A p \in Pids, a \in Apps, k \in Keys :
    (p \notin terminated
     /\ \E q \in LiveAncestors(p) : HasKeySet(q, a, k))
    => FetchRaw(p, a, k) /= FetchErr

(* Combined: I1-I4 *)
Reachability ==
  /\ LinkInheritance
  /\ MonitorInheritance
  /\ Isolation
  /\ NoFalseNegatives

(* I7 — Terminated PIDs Stay Dead *)
TerminationPermanent ==
  \A p \in terminated, q \in Pids \ terminated :
    BFS(<<<<q, SrcLinks>>>>, {}) /= p

(* I8 — No Cache Staleness *)
NoStaleCache ==
  \A p \in Pids, a \in Apps, k \in Keys :
    (p \notin terminated /\ <<p, a, k>> \in cache)
    => FetchRaw(p, a, k) = FetchErr

(* Combined: all invariants *)
AllInvariants ==
  /\ TypeOK
  /\ Reachability
  /\ TerminationPermanent
  /\ NoStaleCache

=============================================================================
