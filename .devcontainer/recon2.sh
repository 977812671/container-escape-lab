#!/usr/bin/env bash
# Codespace recon round 2: token boundary, localhost services, host partitions.
OUT=/workspaces/container-escape-lab/codespace-recon2.txt
{
echo "== [A] GITHUB_TOKEN (ghu_ user-to-server) boundary probe - own resources only"
GT="$GITHUB_TOKEN"
gh_call() { curl -sS -m 15 -o /tmp/g.out -w "%{http_code}" -H "Authorization: Bearer $GT" "$@"; }
echo "GET /user: $(gh_call https://api.github.com/user)"; head -c 100 /tmp/g.out; echo
echo "GET /user/repos?type=private:"; gh_call 'https://api.github.com/user/repos?type=private&per_page=100' >/dev/null; python3 -c "
import json
try:
    d = json.load(open('/tmp/g.out'))
    print('  private repos visible via ghu_ token:', [r['name'] for r in d] if isinstance(d, list) else d)
except Exception as e:
    print('  parse err', e)
"
echo "GET /user/orgs: $(gh_call https://api.github.com/user/orgs)"; head -c 100 /tmp/g.out; echo
echo "GET private repo escape-lab-cross: $(gh_call https://api.github.com/repos/977812671/escape-lab-cross)"; head -c 100 /tmp/g.out; echo
echo "GET escape-lab-cross private file (contents API): $(gh_call https://api.github.com/repos/977812671/escape-lab-cross/contents/README.md)"; head -c 100 /tmp/g.out; echo


echo "== [A2] ghu_ write boundary (own private repo, harmless probe file, cleaned up)"
WT=$(curl -sS -m 15 -o /tmp/w.out -w "%{http_code}" -X PUT \
  -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  -d '{"message":"boundary-probe","content":"NDA0IG5vdCBmb3VuZA==","branch":"main"}' \
  https://api.github.com/repos/977812671/escape-lab-cross/contents/.boundary-probe)
echo "PUT escape-lab-cross/.boundary-probe: $WT"; head -c 120 /tmp/w.out; echo
if [ "$WT" = "201" ]; then
  echo "  <<< ghu_ token CAN WRITE to non-mother private repo"
  curl -sS -m 15 -X DELETE -H "Authorization: Bearer $GITHUB_TOKEN" \
    https://api.github.com/repos/977812671/escape-lab-cross/contents/.boundary-probe \
    -d '{"message":"cleanup","sha":"'"$(python3 -c "import json;d=json.load(open('/tmp/w.out'));print(d['content']['sha'])")"'"}' \
    -H "Accept: application/vnd.github+json" -o /dev/null -w 'cleanup: %{http_code}\n'
fi

echo "== [B] GITHUB_CODESPACE_TOKEN probe"
echo "GET /user with cs-token: $(curl -sS -m 15 -o /tmp/c.out -w '%{http_code}' -H "Authorization: Bearer $GITHUB_CODESPACE_TOKEN" https://api.github.com/user)"; head -c 100 /tmp/c.out; echo

echo "== [C] localhost services fingerprint"
for p in 2000 13005 12563 16634 16635 16636 44169; do
  for path in / /health /status /version /metrics; do
    C=$(curl -sS -m 3 -o /tmp/s.out -w "%{http_code}" "http://127.0.0.1:$p$path" 2>/dev/null || echo 000)
    b=$(head -c 90 /tmp/s.out | tr '\n' ' ' | tr -d '\r')
    [ "$C" != "000" ] && echo "port $p $path: $C :: $b"
  done
done

echo "== [D] codespaces shared dirs (names only)"
sudo ls -la /workspaces/.codespaces/shared 2>/dev/null | head -20
echo "-- persistedshare:"
sudo ls -la /workspaces/.codespaces/.persistedshare 2>/dev/null | head -10

echo "== [E] host-root partitions mounted in container"
echo "-- /.codespaces/bin:"; ls /.codespaces/bin 2>/dev/null | head -15
echo "-- /vscode:"; ls /vscode 2>/dev/null | head -15
echo "-- / (via sudo, container root):"; sudo ls / 2>/dev/null | head -8

echo "== [F] devices"
ls -la /dev | head -30

echo "== [G] IMDS identity probe (no token grab)"
curl -sS -m 3 -o /tmp/i.out -w "identity: %{http_code}\n" -H 'Metadata:true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' 2>/dev/null
python3 -c "
import json
try:
    d = json.load(open('/tmp/i.out'))
    print('error field:', d.get('error'))
    print('has access_token:', 'access_token' in json.dumps(d))
except Exception:
    pass
" 2>/dev/null

echo "== [H] mountinfo host-path leak check"
grep -cE 'overlay2|/var/lib' /proc/self/mountinfo >/dev/null && echo "host docker overlay paths VISIBLE in mountinfo" || echo "host paths not visible"
} > "$OUT" 2>&1

cd /workspaces/container-escape-lab || exit 0
git config user.email "recon@codespace.local"; git config user.name "recon"
git checkout -b codespace-recon2 2>/dev/null || git checkout codespace-recon2
git add -f codespace-recon2.txt
git commit -m "recon2: token boundary + services" || true
git push origin codespace-recon2 -f 2>&1 | tail -3
