#!/usr/bin/env python3
"""
operator_ping.py: one spoken notification from a planning session to Rick, through Lupin.

A "ping" (Rick, 2026-11-23) is a notification Lupin speaks aloud. A session under Antigravity has
no voice tool server, so it posts to Lupin's own route from the shell: sign in as this checkout's
Lupin account, then POST /api/notify. One way only: nothing is read back, and no reply is awaited.

Usage:
    src/captures/operator_ping.py "Row 21: the narrative is ready for you."
    src/captures/operator_ping.py --priority urgent --title "Blocked" "I need a ruling before I can go on."
    src/captures/operator_ping.py --dry-run "what would be sent"

Reads `~/.lupin/config`: the default environment's `api_url` and `global_notification_recipient`
(the operator's account), and the email and password of the section named after this checkout's
folder. It prints no secret, token or email address, and writes nothing.

Priority: `high` is spoken (measured 2026-11-23); `medium` was heard as a ding with no speech;
`urgent` is for a session that cannot go on without Rick. Exit status 0 when Lupin queued it.
"""

import argparse
import configparser
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

CONFIGURATION_PATH = os.path.expanduser( "~/.lupin/config" )
SENDER_ENGINE      = "agy.cli"
SPOKEN_PRIORITIES  = ( "high", "urgent" )
TIMEOUT_SECONDS    = 15


def get_project_name():
    """
    Ensures: returns the name of the checkout's folder, which is also its section in ~/.lupin/config
    """
    return os.path.basename( os.path.dirname( os.path.dirname( os.path.dirname( os.path.abspath( __file__ ) ) ) ) )


def read_settings( project ):
    """
    Requires: ~/.lupin/config holds [environments], the default environment's section and a section named project
    Ensures : returns ( api_url, recipient, email, password )
    Raises  : KeyError naming the section or key that is missing
    """
    configuration = configparser.ConfigParser()
    if not configuration.read( CONFIGURATION_PATH ): raise KeyError( f"{CONFIGURATION_PATH} is missing or unreadable" )
    environment = configuration[ configuration[ "environments" ][ "default" ] ]
    account     = configuration[ project ]
    return environment[ "api_url" ].rstrip( "/" ), environment[ "global_notification_recipient" ], account[ "email" ], account[ "password" ]


def post_json( url, body=None, headers=None ):
    """
    Ensures: returns ( http status, parsed JSON reply or {} ); never raises for an HTTP error status
    """
    data    = json.dumps( body ).encode() if body is not None else b""
    request = urllib.request.Request( url, data=data, method="POST", headers={ "Content-Type": "application/json", **( headers or {} ) } )
    try:
        with urllib.request.urlopen( request, timeout=TIMEOUT_SECONDS ) as reply: status, text = reply.status, reply.read().decode()
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode()
    try: return status, json.loads( text )
    except ValueError: return status, {}


def send_ping( message, priority="high", title=None, session_name=None, dry_run=False ):
    """
    Requires: message is a non-empty string; priority is low, medium, high or urgent
    Ensures : returns ( queued, detail ), where queued is True when Lupin answered `queued`
              and detail is one line that holds no secret
    """
    project = get_project_name()
    api_url, recipient, email, password = read_settings( project )
    query = { "message": message, "type": "custom", "priority": priority, "target_user": recipient,
              "sender_id": f"{SENDER_ENGINE}@{project}.deepily.ai" }
    if title        : query[ "title" ]        = title
    if session_name : query[ "session_name" ] = session_name
    if dry_run:
        return True, f"dry run: {priority} to the operator's account at {api_url} as {query[ 'sender_id' ]}: {message}"

    status, reply = post_json( f"{api_url}/auth/login", { "email": email, "password": password } )
    if status != 200: return False, f"sign-in refused: HTTP {status}"
    token = reply[ "tokens" ][ "access_token" ]

    status, reply = post_json( f"{api_url}/api/notify?" + urllib.parse.urlencode( query ), headers={ "Authorization": f"Bearer {token}" } )
    queued = status == 200 and reply.get( "status" ) == "queued"
    return queued, f"HTTP {status} | status {reply.get( 'status' )} | delivered {reply.get( 'delivered' )} | connections {reply.get( 'connection_count' )} | priority {priority}"


def main():
    parser = argparse.ArgumentParser( description="Send Rick one spoken notification through Lupin." )
    parser.add_argument( "message" )
    parser.add_argument( "--priority", default="high", choices=( "low", "medium", "high", "urgent" ) )
    parser.add_argument( "--title" )
    parser.add_argument( "--session-name" )
    parser.add_argument( "--dry-run", action="store_true" )
    arguments = parser.parse_args()
    if not arguments.message.strip(): parser.error( "the message is empty" )
    if arguments.priority not in SPOKEN_PRIORITIES: print( f"note: {arguments.priority} is not spoken; a ping is high or urgent", file=sys.stderr )
    try:
        queued, detail = send_ping( arguments.message, arguments.priority, arguments.title, arguments.session_name, arguments.dry_run )
    except ( KeyError, urllib.error.URLError, OSError ) as error:
        queued, detail = False, f"not sent: {type( error ).__name__}: {error}"
    print( detail )
    return 0 if queued else 1


if __name__ == "__main__":
    sys.exit( main() )
