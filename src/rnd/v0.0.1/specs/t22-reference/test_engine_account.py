import unittest
from engine_account import *

USAGE = { "num_turns": 0, "command": { "name": "usage", "data": { "groups": [
    { "name": "Gemini Models", "buckets": [
        { "id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.917, "reset_time": "2026-10-31T15:04:28Z" },
        { "id": "gemini-5h",     "window": "5h",     "remaining_fraction": 0.714, "reset_time": "2026-10-26T00:56:59Z" } ] },
    { "name": "Claude and GPT models", "buckets": [
        { "id": "3p-weekly", "window": "weekly", "remaining_fraction": 0.40, "reset_time": None },
        { "id": "3p-5h",     "window": "5h",     "remaining_fraction": 0.10, "reset_time": None } ] },
    { "name": "Something New", "buckets": [ { "id": "x", "window": "monthly", "remaining_fraction": 1.0 } ] } ] } } }

QUOTA = "API error (attempt 3): RESOURCE_EXHAUSTED (code 429): Individual quota reached. Contact your administrator to enable overages. Resets in 148h49m28s."
BARE  = "RESOURCE_EXHAUSTED (code 429): Resource has been exhausted (e.g. check quota)."

def account( now=1000.0 ):
    return EngineAccount( login="ok", buckets=parse_usage( USAGE ), sampled_at=now )

class EngineAccountTests( unittest.TestCase ):

    def test_meter_parses_known_groups_and_skips_unknown( self ):
        buckets = parse_usage( USAGE )
        self.assertEqual( len( buckets ), 4 )
        self.assertEqual( account().remaining( "third_party", "five_hour" ), 0.10 )
        self.assertEqual( parse_usage( { "command": { "name": "help" } } ), [] )
        self.assertEqual( parse_usage( None ), [] )

    def test_pool_for_model( self ):
        self.assertEqual( pool_for_model( "opus-5.5-high" ), "third_party" )
        self.assertEqual( pool_for_model( "fable-5.1-high" ), "third_party" )
        self.assertEqual( pool_for_model( "gemini-3.8-flash-high" ), "gemini" )
        self.assertEqual( pool_for_model( "gemini-4-argon-high" ), "argon" )

    def test_reset_durations( self ):
        self.assertEqual( parse_reset_seconds( QUOTA ), 148 * 3600 + 49 * 60 + 28 )
        self.assertEqual( parse_reset_seconds( "Resets in 2h38m3s" ), 9483 )
        self.assertEqual( parse_reset_seconds( "Resets in 45s." ), 45 )
        self.assertIsNone( parse_reset_seconds( BARE ) )

    def test_only_a_stated_reset_is_exhaustion( self ):
        self.assertEqual( classify_error( QUOTA )[ 0 ], "quota_exhausted" )
        self.assertEqual( classify_error( BARE ), ( "refused_429", None ) )
        self.assertEqual( classify_error( "RESOURCE_EXHAUSTED (code 429): per-minute rate limit" )[ 0 ], "rate_limited" )
        self.assertEqual( classify_error( "UNAVAILABLE (code 503): try later" )[ 0 ], "unavailable" )
        self.assertEqual( classify_error( "Error: authentication required. Run 'agy' to log in, then retry." )[ 0 ], "login_lapsed" )
        self.assertEqual( classify_error( "something else" )[ 0 ], "other" )

    def test_a_stale_error_on_a_good_turn_is_ignored( self ):
        self.assertEqual( classify_error( "Individual quota reached. Resets in 3h.", response="RESUME_OK\n", saw_new_error_step=False ), ( "stale_error", None ) )
        self.assertEqual( classify_error( QUOTA, response="", saw_new_error_step=False )[ 0 ], "quota_exhausted" )

    def test_admission_low_meter_refuses_a_spawn_not_a_wake( self ):
        refusal = admission_check( account(), QuotaPolicy(), "opus-5.5-high", now=1000.0 )
        self.assertEqual( ( refusal[ "check" ], refusal[ "reason" ], refusal[ "window" ] ), ( "engine_quota", "low", "five_hour" ) )
        self.assertIsNone( admission_check( account(), QuotaPolicy(), "opus-5.5-high", now=1000.0, is_wake=True ) )
        self.assertIsNone( admission_check( account(), QuotaPolicy(), "gemini-3.8-flash-high", now=1000.0 ) )

    def test_admission_exhaustion_outranks_the_meter_until_its_reset( self ):
        state = account()
        state.note_exhaustion( "gemini", 9483, now=1000.0 )
        refusal = admission_check( state, QuotaPolicy(), "gemini-3.8-flash-high", now=1100.0, is_wake=True )
        self.assertEqual( ( refusal[ "reason" ], refusal[ "retry_after_seconds" ] ), ( "exhausted", 9383 ) )
        self.assertIsNone( admission_check( state, QuotaPolicy(), "gemini-3.8-flash-high", now=1000.0 + 9484 ) )

    def test_unknown_never_refuses_and_lapsed_always_does( self ):
        self.assertIsNone( admission_check( EngineAccount(), QuotaPolicy(), "opus-5.5-high", now=5.0 ) )
        stale = account( now=0.0 )
        self.assertIsNone( admission_check( stale, QuotaPolicy(), "opus-5.5-high", now=2000.0 ) )
        lapsed = account(); lapsed.login = "lapsed"
        self.assertEqual( admission_check( lapsed, QuotaPolicy(), "gemini-3.8-flash-high", now=1000.0, is_wake=True )[ "check" ], "engine_login" )

    def test_reserve_holds_workers_and_lets_managers_through( self ):
        state = account()
        self.assertEqual( turn_gate( state, QuotaPolicy(), "implementer", "opus-5.5-high", 1000.0 ), ( "would_defer", "reserve" ) )
        self.assertEqual( turn_gate( state, QuotaPolicy( reserve_mode="enforce" ), "implementer", "opus-5.5-high", 1000.0 ), ( "defer", "reserve" ) )
        self.assertEqual( turn_gate( state, QuotaPolicy( reserve_mode="enforce" ), "manager", "opus-5.5-high", 1000.0 ), ( "start", "reserved_role" ) )
        self.assertEqual( turn_gate( state, QuotaPolicy( reserve_mode="enforce" ), "implementer", "gemini-3.8-flash-high", 1000.0 ), ( "start", None ) )
        state.note_exhaustion( "third_party", 60, now=1000.0 )
        self.assertEqual( turn_gate( state, QuotaPolicy(), "manager", "opus-5.5-high", 1001.0 ), ( "defer", "exhausted" ) )

    def test_second_bare_429_in_a_row_raises_once( self ):
        state = account()
        self.assertFalse( state.note_refused_429( "a1b2c3d4" ) )
        self.assertTrue(  state.note_refused_429( "a1b2c3d4" ) )
        self.assertFalse( state.note_refused_429( "a1b2c3d4" ) )
        state.note_good_turn( "a1b2c3d4" )
        self.assertFalse( state.note_refused_429( "a1b2c3d4" ) )

if __name__ == "__main__":
    unittest.main()
