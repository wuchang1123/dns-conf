#!/usr/bin/env bash
# Download felixonmars dnsmasq-china-list conf files, strip # comment lines,
# and emit dnsmasq, SmartDNS, and AdGuard Home snippets.
set -euo pipefail

BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/refs/heads/master}"
FILES=(
  "accelerated-domains.china.conf"
  "google.china.conf"
  "apple.china.conf"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_DIR="${INPUT_DIR:-${SCRIPT_DIR}/upstream}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/out}"

usage() {
  echo "Usage: ${0##*/} [options] [<dns_ip> [<dns_alias>]]"
  echo "  Options: --no-download, -h, --help"
  echo "  With dns_ip only: use that upstream for all domains; SmartDNS group defaults to g_a_b_c_d from IP."
  echo "  With dns_ip + dns_alias: same, but SmartDNS -g uses dns_alias."
  echo "  Without: use IP from each dnsmasq line and auto group names per upstream."
  echo "  Env: BASE_URL, INPUT_DIR, OUT_DIR"
  echo "       AG_BATCH (default 8: AdGuard + dnsmasq domains per line, same upstream IP)"
  echo "       SMARTDNS_DOMAINSET=yes|no (default yes: domain-set + list files, compact)"
  echo "       SMARTDNS_LIST_BASENAME (default china-domains: full domain list basename, not DNS-related)"
  exit "${1:-0}"
}

DOWNLOAD=1
POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --no-download) DOWNLOAD=0 ;;
    -*)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
    *) POS+=("$1") ;;
  esac
  shift
done

DNS_IP="${POS[0]:-}"
DNS_ALIAS="${POS[1]:-}"
if [[ ${#POS[@]} -gt 2 ]]; then
  echo "Too many arguments: ${POS[*]}" >&2
  usage 1
fi
if [[ -z "$DNS_IP" && -n "$DNS_ALIAS" ]]; then
  echo "<dns_alias> requires <dns_ip> first." >&2
  exit 1
fi

mkdir -p "$INPUT_DIR"

if [[ "$DOWNLOAD" -eq 1 ]]; then
  for f in "${FILES[@]}"; do
    echo "Downloading $f ..."
    curl -fsSL -o "$INPUT_DIR/$f" "$BASE_URL/$f"
  done
fi

# Strip lines whose first non-space char is #; drop blanks; strip inline # comments.
# Emit domain<TAB>ip (first occurrence wins on duplicate domains).
clean_stream() {
  sed -e 's/^[[:space:]]*//' -e '/^#/d' -e '/^$/d' -e 's/[[:space:]]*#.*$//' "$@"
}

# After the same cleaning as merge, every line must be server=/domain/target (target = IP or host, no spaces).
validate_dnsmasq_conf() {
  local path=$1
  local name
  name=$(basename "$path")
  if [[ ! -f "$path" ]] || [[ ! -s "$path" ]]; then
    echo "${0##*/}: source missing or empty: $path" >&2
    return 1
  fi
  if head -n 40 "$path" | LC_ALL=C grep -qiE '<!DOCTYPE[[:space:]]|<html[[:space:]]|<head[[:space:]]|<body[[:space:]]'; then
    echo "${0##*/}: not dnsmasq text (looks like HTML): $name" >&2
    return 1
  fi
  local tmp
  tmp=$(mktemp)
  clean_stream "$path" >"$tmp"
  if [[ ! -s "$tmp" ]]; then
    echo "${0##*/}: no lines left after stripping comments: $name" >&2
    rm -f "$tmp"
    return 1
  fi
  if grep -Ev '^server=/[^/]+/[^[:space:]#]+$' "$tmp" | grep -q .; then
    echo "${0##*/}: invalid dnsmasq in $name (expect server=/domain/ip per line):" >&2
    grep -Ev '^server=/[^/]+/[^[:space:]#]+$' "$tmp" | head -n 8 >&2
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  return 0
}

merge_domains() {
  clean_stream "$@" | awk '
    /^server=\// {
      line = $0
      sub(/^server=/, "", line)
      if (substr(line, 1, 1) != "/") next
      sub(/^\//, "", line)
      idx = index(line, "/")
      if (idx == 0) next
      d = substr(line, 1, idx - 1)
      ip = substr(line, idx + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", ip)
      if (d == "" || ip == "") next
      if (!(d in seen)) {
        seen[d] = ip
        order[++n] = d
      }
      next
    }
    END {
      for (i = 1; i <= n; i++) {
        dd = order[i]
        print dd "\t" seen[dd]
      }
    }
  '
}

TMP_MERGED="$(mktemp)"
OUT_GEN=""
cleanup_on_exit() {
  rm -f "$TMP_MERGED"
  [[ -n "${OUT_GEN:-}" && -d "$OUT_GEN" ]] && rm -rf "$OUT_GEN"
}
trap cleanup_on_exit EXIT

for f in "${FILES[@]}"; do
  p="$INPUT_DIR/$f"
  if [[ ! -f "$p" ]]; then
    echo "Missing: $p (run without --no-download or place files there)" >&2
    exit 1
  fi
  echo "Validating $f ..."
  validate_dnsmasq_conf "$p" || exit 1
done

merge_domains "$INPUT_DIR/${FILES[0]}" "$INPUT_DIR/${FILES[1]}" "$INPUT_DIR/${FILES[2]}" >"$TMP_MERGED"

AG_BATCH="${AG_BATCH:-8}"
SMARTDNS_DOMAINSET="${SMARTDNS_DOMAINSET:-yes}"
SMARTDNS_LIST_BASENAME="${SMARTDNS_LIST_BASENAME:-china-domains}"

case "$SMARTDNS_DOMAINSET" in
  yes|true|1|on|ON) SMARTDNS_DOMAINSET=1 ;;
  no|false|0|off|OFF) SMARTDNS_DOMAINSET=0 ;;
  *)
    echo "SMARTDNS_DOMAINSET must be yes or no, got: $SMARTDNS_DOMAINSET" >&2
    exit 1
    ;;
esac

OUT_GEN="$(mktemp -d)"

shopt -s nullglob 2>/dev/null || true
# Build in OUT_GEN; promote to OUT_DIR only after all steps succeed (atomic replace).
rm -f "$OUT_GEN"/smartdns-domains_*.list "$OUT_GEN/${SMARTDNS_LIST_BASENAME}"-*.list \
  "$OUT_GEN"/cn_*.list 2>/dev/null || true

# Full domain column only (for download / reference); independent of SmartDNS upstream grouping.
awk -F'\t' '{print $1}' "$TMP_MERGED" >"$OUT_GEN/${SMARTDNS_LIST_BASENAME}.list"

awk -v out_smart="$OUT_GEN/smartdns-china.conf" -v out_smart_ref="$OUT_DIR/smartdns-china.conf" \
  -v outdir="$OUT_GEN" -v outdir_ref="$OUT_DIR" \
  -v override_ip="$DNS_IP" -v override_alias="$DNS_ALIAS" \
  -v domainset="$SMARTDNS_DOMAINSET" -v listbase="$SMARTDNS_LIST_BASENAME" '
function group_name(ip,   a, n, i, s) {
  n = split(ip, a, ".")
  if (n == 4) {
    s = "g"
    for (i = 1; i <= 4; i++) s = s "_" a[i]
    return s
  }
  gsub(/[^0-9A-Za-z]/, "_", ip)
  return "g_" ip
}
function override_group() {
  if (override_alias != "") return override_alias
  return group_name(override_ip)
}
function ds_path_file_for_group(gg,   s) {
  s = gg
  gsub(/[^a-zA-Z0-9._-]/, "_", s)
  return outdir "/smartdns-domains_" s ".list"
}
function ds_path_file_for_group_ref(gg,   s) {
  s = gg
  gsub(/[^a-zA-Z0-9._-]/, "_", s)
  return outdir_ref "/smartdns-domains_" s ".list"
}
function ds_path(idx, ngrp) {
  if (ngrp == 1) return outdir "/" listbase ".list"
  return ds_path_file_for_group(order[idx])
}
function ds_path_ref(idx, ngrp) {
  if (ngrp == 1) return outdir_ref "/" listbase ".list"
  return ds_path_file_for_group_ref(order[idx])
}
function ds_setname(idx, ngrp,   t) {
  t = listbase
  gsub(/-/, "_", t)
  if (ngrp == 1) return t
  return t "_" idx
}
BEGIN {
  print "# Generated by convert-dnsmasq-china.sh - include in smartdns.conf, e.g." > out_smart
  print "#   conf-file " out_smart_ref > out_smart
  print "" > out_smart
  print "# Upstream servers for China list (one group per address, excluded from default)" > out_smart
  if (domainset) {
    print "# Domain lists are China domain names only; -g GROUP ties to server lines below." > out_smart
  }
  if (override_ip != "") {
    print "# Override: server " override_ip " group " override_group() > out_smart
    print "server " override_ip ":53 -g " override_group() " -e" > out_smart
  }
}
{
  domain = $1
  ip = $2
  if (override_ip != "") {
    ip = override_ip
    g = override_group()
  } else {
    g = group_name(ip)
  }
  if (domainset) {
    lines[++L] = $0
    next
  }
  if (override_ip == "") {
    if (!(ip in groups)) {
      groups[ip] = g
      print "server " ip ":53 -g " g " -e" > out_smart
    }
  }
  print "nameserver /" domain "/" g > out_smart
}
END {
  if (!domainset) exit
  for (i = 1; i <= L; i++) {
    split(lines[i], a, "\t")
    domain = a[1]
    ip = a[2]
    if (override_ip != "") {
      ip = override_ip
      g = override_group()
    } else {
      g = group_name(ip)
    }
    if (!(g in seen)) {
      seen[g] = ip
      order[++n] = g
      gidx[g] = n
    }
  }
  for (i = 1; i <= L; i++) {
    split(lines[i], a, "\t")
    domain = a[1]
    ip = a[2]
    if (override_ip != "") {
      g = override_group()
    } else {
      g = group_name(ip)
    }
    path = ds_path(gidx[g], n)
    fulllist = outdir "/" listbase ".list"
    if (n == 1 && path == fulllist) continue
    print domain >> path
    listpath[path] = 1
  }
  for (p in listpath) close(p)
  if (override_ip == "") {
    for (i = 1; i <= n; i++) {
      gg = order[i]
      print "server " seen[gg] ":53 -g " gg " -e" >> out_smart
    }
  }
  print "" >> out_smart
  for (i = 1; i <= n; i++) {
    gg = order[i]
    dn = ds_setname(i, n)
    print "domain-set -name " dn " -type list -file " ds_path_ref(i, n) >> out_smart
  }
  print "" >> out_smart
  for (i = 1; i <= n; i++) {
    gg = order[i]
    dn = ds_setname(i, n)
    print "nameserver /domain-set:" dn "/" gg >> out_smart
  }
}
' "$TMP_MERGED"

awk -v out_adg="$OUT_GEN/adguard-upstream-china.txt" -v override_ip="$DNS_IP" -v batch="$AG_BATCH" '
function emit(   i, s) {
  s = "[/"
  for (i = 1; i <= nbuf; i++) {
    s = s buf[i]
    s = s "/"
  }
  s = s "]" cur_ip
  print s > out_adg
}
BEGIN {
  FS = "\t"
  if (batch < 1) batch = 8
  print "# AdGuard Home: paste as upstreams or use as upstream_dns_file" > out_adg
  print "# Syntax: [/d1/d2/.../]upstream - up to " batch " domains per line (same upstream)" > out_adg
  if (override_ip != "") {
    print "# Override upstream: " override_ip > out_adg
  }
  print "" > out_adg
}
{
  domain = $1
  ip = (override_ip != "" ? override_ip : $2)
  if (ip != cur_ip) {
    if (nbuf > 0) emit()
    cur_ip = ip
    nbuf = 0
  }
  buf[++nbuf] = domain
  if (nbuf >= batch) {
    emit()
    nbuf = 0
  }
}
END {
  if (nbuf > 0) emit()
}
' "$TMP_MERGED"

awk -v out_dm="$OUT_GEN/dnsmasq-china.conf" -v override_ip="$DNS_IP" -v batch="$AG_BATCH" '
function emit(   i, s) {
  s = "server=/"
  for (i = 1; i <= nbuf; i++) {
    s = s buf[i]
    s = s "/"
  }
  s = s cur_ip
  print s > out_dm
}
BEGIN {
  FS = "\t"
  if (batch < 1) batch = 8
  print "# Generated by convert-dnsmasq-china.sh - dnsmasq server=/d1/d2/.../ip" > out_dm
  print "# Up to " batch " domains per line when upstream IP matches (see dnsmasq --server)." > out_dm
  print "# Merged china lists (comments stripped); first occurrence wins on duplicate domains." > out_dm
  if (override_ip != "") {
    print "# Override upstream: " override_ip > out_dm
  }
  print "" > out_dm
}
{
  domain = $1
  ip = (override_ip != "" ? override_ip : $2)
  if (ip != cur_ip) {
    if (nbuf > 0) emit()
    cur_ip = ip
    nbuf = 0
  }
  buf[++nbuf] = domain
  if (nbuf >= batch) {
    emit()
    nbuf = 0
  }
}
END {
  if (nbuf > 0) emit()
}
' "$TMP_MERGED"

# Replace out/ by renaming the staging dir (atomic); old out/ removed only after success.
mkdir -p "$(dirname "$OUT_DIR")" 2>/dev/null || true
rm -rf "${OUT_DIR}.replaced"
if [[ -d "$OUT_DIR" ]]; then
  mv "$OUT_DIR" "${OUT_DIR}.replaced"
fi
mv "$OUT_GEN" "$OUT_DIR"
OUT_GEN=""
rm -rf "${OUT_DIR}.replaced"
trap - EXIT
trap 'rm -f "$TMP_MERGED"' EXIT

echo "Wrote:"
echo "  $OUT_DIR/dnsmasq-china.conf"
echo "  $OUT_DIR/smartdns-china.conf"
echo "  $OUT_DIR/${SMARTDNS_LIST_BASENAME}.list"
if [[ "$SMARTDNS_DOMAINSET" -eq 1 ]]; then
  shopt -s nullglob
  for _f in "$OUT_DIR"/smartdns-domains_*.list; do
    [[ -f "$_f" ]] && echo "  $_f"
  done
fi
echo "  $OUT_DIR/adguard-upstream-china.txt"
echo "Domains: $(wc -l <"$TMP_MERGED" | tr -d " ")"
