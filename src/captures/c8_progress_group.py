#!/usr/bin/env python3
"""
c8_progress_group.py -- is every in-place update of a progress card spoken, or only the first?

    PYTHONPATH=$LUPIN_ROOT/src python3 c8_progress_group.py      (from the lupin venv)

Requires:
    - LUPIN_DEV_EMAIL set, the :7999 server up, a client open with TTS above 0%
    - the fresh sender this script mints is not in quiet mode (it never was: the id is new)
Ensures:
    - series A: three high-priority progress notifications sharing one progress_group_id, 10 s apart
    - series B (control): the same with a fresh progress_group_id each
    - prints what to listen and look for; nothing is decided automatically
"""
import os, time, uuid

from lupin_cli.notifications.notify_user_async import notify_user_async
from lupin_cli.notifications.notification_models import AsyncNotificationRequest

SENDER = f"claude.code@lupin.deepily.ai#{uuid.uuid4().hex[ :8 ]}"     # the format parseSenderId expects


def send( message, group ):
    request = AsyncNotificationRequest( message=message, notification_type="progress", priority="high",
                                        target_user=os.environ[ "LUPIN_DEV_EMAIL" ], sender_id=SENDER,
                                        progress_group_id=group )
    response = notify_user_async( request )
    print( f"{time.strftime( '%H:%M:%S' )}  {group}  {message}  -> {getattr( response, 'status', response )}", flush=True )
    time.sleep( 10 )


shared = f"pg-{uuid.uuid4().hex[ :8 ]}"
print( f"sender {SENDER}\nSeries A: one progress_group_id. Listen: are all three spoken, or only the first?" )
for word in ( "one", "two", "three" ):
    send( f"Capture C8 series A, update {word}", shared )
print( "Series B (control): a new progress_group_id each time. All three should be spoken." )
for word in ( "one", "two", "three" ):
    send( f"Capture C8 series B, update {word}", f"pg-{uuid.uuid4().hex[ :8 ]}" )
print( "Record: A spoken ?/3 · B spoken ?/3 · series A updated one card in place? (yes/no)" )
