"""
engine_account.py: what the kernel knows about the vendor account a fleet of engines shares.

Pure: no process, no clock, no file. The Jetski-family adapter supplies three reads (the usage
meter's JSON, a turn's error text, the sign-in probe's exit) and this module turns them into
facts and decisions. Shapes are from the public record for AGY 1.4.7 (spec Section 2); a shape
this module does not know is `other` or `unknown`, and unknown never refuses.
"""

import re
from dataclasses import dataclass, field
from typing      import Optional

# ---- pools -------------------------------------------------------------------------------------

# The meter's group names, as AGY prints them, keyed by the pool name the kernel uses.
POOL_BY_GROUP_NAME = {
    "gemini models"         : "gemini",
    "claude and gpt models" : "third_party",
    "gemini 4 argon"        : "argon",
}

def pool_for_model( model_id ):
    """
    Requires: model_id is an engine model identifier, for example "opus-5.5-high"
    Ensures : returns "argon", "gemini" or "third_party"; a model that is not Gemini is third_party
    """
    name = model_id.lower()
    if name.startswith( "gemini-4-argon" ): return "argon"
    if name.startswith( "gemini" )        : return "gemini"
    return "third_party"

# ---- the meter ---------------------------------------------------------------------------------

@dataclass
class Bucket:
    pool               : str
    window             : str              # "five_hour" | "weekly"
    remaining_fraction : float
    reset_time         : Optional[ str ]  # as the engine printed it; the kernel parses it at the edge

WINDOW_NAMES = { "5h": "five_hour", "weekly": "weekly" }

def parse_usage( reply ):
    """
    Requires: reply is the parsed JSON of `agy -p "/usage" --output-format json`
    Ensures : returns a list of Bucket, empty when the reply is not a usage answer;
              an unknown group or window is skipped, never guessed
    """
    command = ( reply or {} ).get( "command" ) or {}
    if command.get( "name", "usage" ) not in ( "usage", "quota" ): return []
    buckets = []
    for group in ( command.get( "data" ) or {} ).get( "groups" ) or []:
        pool = POOL_BY_GROUP_NAME.get( str( group.get( "name", "" ) ).strip().lower() )
        if pool is None: continue
        for bucket in group.get( "buckets" ) or []:
            window   = WINDOW_NAMES.get( bucket.get( "window" ) )
            fraction = bucket.get( "remaining_fraction" )
            if window is None or not isinstance( fraction, ( int, float ) ): continue
            buckets.append( Bucket( pool, window, float( fraction ), bucket.get( "reset_time" ) ) )
    return buckets

# ---- errors ------------------------------------------------------------------------------------

RESET_PATTERN = re.compile( r"Resets in\s+((?:\d+h)?(?:\d+m)?(?:\d+(?:\.\d+)?s)?)" )
PART_PATTERN  = re.compile( r"(\d+(?:\.\d+)?)([hms])" )

def parse_reset_seconds( error_text ):
    """
    Ensures: returns the seconds in "Resets in 148h49m28s", or None when no reset is stated
    """
    match = RESET_PATTERN.search( error_text or "" )
    if not match or not match.group( 1 ): return None
    scale = { "h": 3600, "m": 60, "s": 1 }
    return int( sum( float( amount ) * scale[ unit ] for amount, unit in PART_PATTERN.findall( match.group( 1 ) ) ) )

def classify_error( error_text, response="", saw_new_error_step=True ):
    """
    Requires: error_text is a result's `error`, an error step's text, or a stderr line
              response is the result's `response` for the same turn
              saw_new_error_step is False when the turn's own steps held no error
    Ensures : returns ( kind, reset_seconds ); kind is one of
              login_lapsed, quota_exhausted, rate_limited, unavailable, refused_429, stale_error, other
              only quota_exhausted carries reset_seconds, and only it may block a pool
    """
    text = error_text or ""
    if not text.strip(): return ( "other", None )
    if re.search( r"authentication required", text, re.I ): return ( "login_lapsed", None )
    if response.strip() and not saw_new_error_step       : return ( "stale_error", None )
    is_429 = bool( re.search( r"RESOURCE_EXHAUSTED|\bcode 429\b|quota reached", text, re.I ) )
    reset  = parse_reset_seconds( text )
    if is_429 and reset is not None                        : return ( "quota_exhausted", reset )
    if is_429 and re.search( r"per.minute|rate limit", text, re.I ): return ( "rate_limited", None )
    if is_429                                              : return ( "refused_429", None )
    if re.search( r"\bcode 50[234]\b|UNAVAILABLE", text )  : return ( "unavailable", None )
    return ( "other", None )

# ---- the account -------------------------------------------------------------------------------

@dataclass
class EngineAccount:
    """What the kernel holds for one engine's account on one host."""
    login          : str   = "unknown"                     # "ok" | "lapsed" | "unknown"
    buckets        : list  = field( default_factory=list ) # the last meter read
    sampled_at     : Optional[ float ] = None
    blocked_until  : dict  = field( default_factory=dict ) # pool -> epoch seconds, from an observed exhaustion
    bare_429_count : dict  = field( default_factory=dict ) # persona_id -> consecutive refused_429

    def remaining( self, pool, window ):
        for bucket in self.buckets:
            if bucket.pool == pool and bucket.window == window: return bucket.remaining_fraction
        return None

    def pool_blocked_until( self, pool, now ):
        """An observed exhaustion outranks the meter until its stated reset has passed."""
        until = self.blocked_until.get( pool )
        return until if until is not None and until > now else None

    def note_exhaustion( self, pool, reset_seconds, now ):
        self.blocked_until[ pool ] = max( self.blocked_until.get( pool, 0 ), now + reset_seconds )

    def note_refused_429( self, persona_id ):
        """Ensures: returns True when this is the second in a row for the persona (raise the alert once)"""
        count = self.bare_429_count.get( persona_id, 0 ) + 1
        self.bare_429_count[ persona_id ] = count
        return count == 2

    def note_good_turn( self, persona_id ):
        self.bare_429_count.pop( persona_id, None )

# ---- decisions ---------------------------------------------------------------------------------

@dataclass
class QuotaPolicy:
    spawn_floor_five_hour : float = 0.15
    spawn_floor_weekly    : float = 0.05
    reserve_five_hour     : float = 0.25
    reserved_roles        : tuple = ( "chief_of_staff", "manager" )
    reserve_mode          : str   = "observe"              # "enforce" | "observe" | "off"
    sample_max_age        : float = 900.0

def admission_check( account, policy, model_id, now, is_wake=False ):
    """
    Check 5 of admission (after skeleton crew, batch cap, fleet cap, host capacity).

    Ensures: returns None to admit, or a refusal dict { check, pool, reason, retry_after_seconds, ... }
             login lapsed refuses a spawn and a wake alike
             a blocked pool refuses a spawn and defers a wake
             a low meter refuses a spawn only; a wake is never refused for a low meter
             a missing or stale meter admits (unknown never refuses)
    """
    if account.login == "lapsed":
        return { "check": "engine_login", "reason": "login_lapsed", "retry_after_seconds": None }
    pool  = pool_for_model( model_id )
    until = account.pool_blocked_until( pool, now )
    if until is not None:
        return { "check": "engine_quota", "pool": pool, "reason": "exhausted", "retry_after_seconds": int( until - now ) }
    if is_wake: return None
    if account.sampled_at is None or now - account.sampled_at > policy.sample_max_age: return None
    for window, floor in ( ( "five_hour", policy.spawn_floor_five_hour ), ( "weekly", policy.spawn_floor_weekly ) ):
        left = account.remaining( pool, window )
        if left is not None and left < floor:
            return { "check": "engine_quota", "pool": pool, "reason": "low", "window": window,
                     "remaining_fraction": left, "floor": floor, "retry_after_seconds": None }
    return None

def turn_gate( account, policy, role, model_id, now ):
    """
    Whether a persona may start a new turn now.

    Ensures: returns ( decision, reason ); decision is "start", "defer" or "would_defer"
             a blocked pool or a lapsed login defers every role
             under the five-hour reserve only reserved roles start; in observe mode the rest
             start too and the kernel logs would_defer
    """
    if account.login == "lapsed": return ( "defer", "login_lapsed" )
    pool = pool_for_model( model_id )
    if account.pool_blocked_until( pool, now ) is not None: return ( "defer", "exhausted" )
    left = account.remaining( pool, "five_hour" )
    if policy.reserve_mode == "off" or left is None or left >= policy.reserve_five_hour: return ( "start", None )
    if role in policy.reserved_roles: return ( "start", "reserved_role" )
    return ( "defer", "reserve" ) if policy.reserve_mode == "enforce" else ( "would_defer", "reserve" )
