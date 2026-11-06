#!/usr/bin/env python3
"""
t32_credential_inventory.py -- T32: check one host for the two credential assumptions behind the design (framework Section 8.1).

    1. owner section      does `~/.lupin/config` carry an `[owner]` section, and does it hold a password? The old
                          notification listener logs in as the human with it to learn the owner's user id; a persona
                          that reads it can mint a human approval. Expected: absent.
    2. service as approver is any per-project hook login (`[lupin]`, `[cosa]`, ... `email = claude.code@...`) on
                          Lupin's approver-account map? That map is what `authenticated_account_email` is checked
                          against when a human answers a task or ticket. Expected: no.

Requires:
    - run on the host under inspection (dev server, test VM), from the lupin virtual environment with lupin's `src`
      as the working directory, because `cosa.rest.task_approval_settings` resolves the stored override from the
      `approval_settings` table before falling back to `lupin-app.ini`
Ensures:
    - reads only; prints no password or key material, only whether a password is present
    - exit 0 when both expectations hold, 1 when either fails, 2 when the check could not run
"""
import configparser, json, os, sys

CONFIG = os.path.expanduser( "~/.lupin/config" )


def config_report():
    parser = configparser.ConfigParser()
    if not parser.read( CONFIG ):
        return { "config_found": False, "config_path": CONFIG }
    report = {
        "config_found"  : True,
        "config_path"   : CONFIG,
        "sections"      : parser.sections(),
        "owner_section" : "owner" in parser,
        "service_emails": { section: parser[ section ].get( "email", "" ).strip()
                            for section in parser.sections() if parser[ section ].get( "email" ) },
    }
    if "owner" in parser:
        report[ "owner_email"        ] = parser[ "owner" ].get( "email", "" ).strip()
        report[ "owner_has_password" ] = bool( parser[ "owner" ].get( "password", "" ).strip() )
    return report


def approver_report( service_emails ):
    from cosa.rest.task_approval_settings import get_approver_accounts, get_approvers
    accounts = get_approver_accounts()   # stored override wins over the INI key, exactly as the server resolves it
    return {
        "approver_accounts"        : accounts,
        "approver_personas"        : sorted( get_approvers() ),
        "service_email_is_approver": { email: email.lower() in accounts for email in service_emails.values() },
    }


if __name__ == "__main__":
    config = config_report()
    print( json.dumps( config, indent=2 ) )
    if not config[ "config_found" ]:
        print( "no ~/.lupin/config on this host; nothing to inspect", file=sys.stderr )
        sys.exit( 2 )
    try:
        approvers = approver_report( config[ "service_emails" ] )
    except Exception as error:
        print( f"could not resolve the approver map: {type( error ).__name__}: {error}", file=sys.stderr )
        print( "run from the lupin virtual environment with lupin's src as the working directory", file=sys.stderr )
        sys.exit( 2 )
    print( json.dumps( approvers, indent=2 ) )

    failures = [ ]
    if config[ "owner_section" ]:
        failures.append( "an [owner] section is present" + ( " with a password" if config.get( "owner_has_password" ) else "" ) )
    for email, is_approver in approvers[ "service_email_is_approver" ].items():
        if is_approver:
            failures.append( f"service login {email} is on the approver-account map" )
    print( "verdict: " + ( "both expectations hold" if not failures else "; ".join( failures ) ) )
    sys.exit( 1 if failures else 0 )
