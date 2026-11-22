#!/usr/bin/env python3
"""Ephemeral countdown to "planning done for Kernel-1 to Kernel-8".

A view, not a record: every row lives in "Outstanding actions" of 00-status.md.
This script reads that table and ticks a row once the status page strikes it.
It prints the checklist and writes nothing. Run at every session's opening and close.
Delete this script and the status page's countdown section when the count reaches
zero (row 110 of "Outstanding actions"). Zero tokens.

    python3 src/captures/kernel8_planning_countdown.py
"""
import pathlib
import re

REPOSITORY = pathlib.Path( __file__ ).resolve().parents[ 2 ]
STATUS_PAGE = REPOSITORY / "src/rnd/v0.0.1/00-status.md"

# ( stage, [ ( row, who, what ) ] ), in the order recommended on 2026-11-20
STAGES = [
    ( "Before the builder's first turn", [
        ( 107, "a session, then Rick", "how the four other `type: info` lines to a manager travel, and how loudly (Kernel-1, Pressure-2)" ),
        ( 108, "Rick", "confirm the details the row 104 amendment set without a click (Kernel-1)" ),
        ( 93, "Rick", "refresh the test VM's July global mandates from the kit, or say they stand" ),
        ( 116, "a session, then Rick", "make the plan of the Single persona kernel MVP (Phase 1) ready for PiP's cascaded review: nine phases, every module placed" ),
        ( 117, "Rick", "run PiP's cascaded review on that plan; its handoff writes the plan stub manifest; import it and approve the rows" ),
        ( 95, "Rick", "how the builder's AH4L session is launched: launch line, folder, voice" ),
        ( 92, "Rick, with the builder", "prove the builder's loader with one turn (the first turn itself)" ),
    ] ),
    ( "Before Kernel-2", [
        ( 17, "Rick", "say whether the destructive-test server on port 8000 is done" ),
        ( 21, "Rick", "admission thresholds against the usage meter's real shape" ),
        ( 22, "Rick", "whether both hosts share one Google account" ),
        ( 61, "Rick", "whether the heap setting is withdrawn" ),
        ( 106, "a session, then Rick", "wording and loudness for the sign-in and quota causes of a deferred wake" ),
        ( 9, "Rick (host run)", "the engine-account inventory, both hosts" ),
        ( 10, "Rick (host run)", "C20, the relaunch tree, on the test VM" ),
        ( 16, "Rick (host run)", "the credential inventory on the test VM" ),
    ] ),
    ( "Before Kernel-5", [
        ( 111, "Rick, then lupin's implementer", "Lupin gains the notification type `info`; the kernel sends it with no fallback (Kernel-3)" ),
        ( 114, "a session, then Rick", "what the card posted to Lupin carries beyond its three fields (Kernel-3)" ),
        ( 25, "Rick", "the ticket store lands in Phase 2 but Kernel-5's `ask` rules need it: decide the order" ),
        ( 13, "Rick (host run)", "C15, whose result goes into `launch.py` (C16 and C15b have no stated gate)" ),
        ( 14, "Rick (host run)", "C18, tool approval, after row 13" ),
    ] ),
]


def read_struck_rows():
    """Return ( every row number, the struck row numbers ) from the status page's table."""
    every, struck = set(), set()
    for line in STATUS_PAGE.read_text().split( "\n" ):
        match = re.match( r"\| (~~)?(\d+)(~~)? \|", line )
        if match:
            every.add( int( match.group( 2 ) ) )
            if match.group( 1 ):
                struck.add( int( match.group( 2 ) ) )
    return every, struck


def build_checklist():
    every, struck = read_struck_rows()
    total = sum( len( rows ) for _, rows in STAGES )
    remaining = 0
    body = []
    for stage, rows in STAGES:
        left = sum( 1 for row, _, _ in rows if row not in struck )
        remaining += left
        body.append( f"\n## {stage} ({left} of {len( rows )} left)\n" )
        for row, who, what in rows:
            assert row in every, f"row {row} is not in the status page's table"
            box = "x" if row in struck else " "
            body.append( f"- [{box}] **Row {row}** · {who} · {what}" )
    head = [
        "# Countdown: planning done for Kernel-1 to Kernel-8",
        "",
        f"**{remaining} of {total} rows left.** Ephemeral: a view of \"Outstanding actions\" in",
        "`src/rnd/v0.0.1/00-status.md`, which stays the one list. A row ticks when the status page",
        "strikes it. At zero, delete this script and the status page's countdown section (row 110).",
        "",
        "Not counted: the builder's own rows (27, 34, 35, 55, 109), which need no planning, and the",
        "relocation's rows (86, 88, 89, 100, 102), which follow Kernel-8. A row a later session adds with a",
        "Kernel-1 to Kernel-8 need must be added to `STAGES` by hand.",
    ]
    return "\n".join( head + body ), remaining, total


if __name__ == "__main__":
    checklist, remaining, total = build_checklist()
    print( checklist )
