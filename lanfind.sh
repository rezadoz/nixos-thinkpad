# lanfind — find machines on the LAN by hostname.
#
#   lanfind HOST [HOST...]
#
# Prints "HOST IP" for every host found; exits 1 if any are missing.
# Packaged by zsh.nix with writeShellApplication (which adds the shebang,
# `set -euo pipefail`, and runs shellcheck at build time).
#
# Tries, fastest first:
#   1. mDNS        HOST.local via avahi (target must publish; see avahi config)
#   2. DNS         many home routers register DHCP clients' hostnames
#   3. sweep       nmap the private /24(s) we're on, then match each live
#                  host's router reverse-DNS name or mDNS reverse name
# Only private (RFC1918) IPv4 addresses are ever returned.

if (( $# == 0 )); then
  echo "usage: lanfind HOST [HOST...]" >&2
  exit 2
fi

wanted=()
for h in "$@"; do wanted+=("${h,,}"); done

declare -A found=()

is_private() {
  case "$1" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
    *) return 1 ;;
  esac
}

# "IdeaPad.lan" / "ideapad.local." -> "ideapad"
short_name() {
  local n="${1,,}"
  echo "${n%%.*}"
}

# record NAME IP — keep it if NAME is one we're looking for
record() {
  local name ip w
  name=$(short_name "$1")
  ip=$2
  is_private "$ip" || return 0
  for w in "${wanted[@]}"; do
    if [[ $name == "$w" && -z ${found[$w]:-} ]]; then
      found[$w]=$ip
    fi
  done
}

missing() {
  local w
  for w in "${wanted[@]}"; do
    [[ -n ${found[$w]:-} ]] || echo "$w"
  done
}

# --- 1 & 2: name lookups ---------------------------------------------------
for w in "${wanted[@]}"; do
  ip=$(timeout 3 avahi-resolve-host-name -4 "$w.local" 2>/dev/null | awk 'NR==1 {print $2}' || true)
  if [[ -z $ip ]] || ! is_private "$ip"; then
    ip=$(getent ahostsv4 "$w" 2>/dev/null | awk 'NR==1 {print $1}' || true)
  fi
  if [[ -n $ip ]]; then record "$w" "$ip"; fi
done

# --- 3: subnet sweep -------------------------------------------------------
if [[ -n $(missing) ]]; then
  # Private IPv4 networks on real interfaces (skip container/VM bridges).
  # Anything wider than /24 is clamped to our own /24 to keep it quick.
  nets=()
  while read -r ifname cidr; do
    case "$ifname" in lo|docker*|br-*|virbr*|veth*|vnet*|tailscale*|wg*) continue ;; esac
    addr=${cidr%/*}
    prefix=${cidr#*/}
    is_private "$addr" || continue
    if (( prefix < 24 )); then prefix=24; fi
    nets+=("$addr/$prefix")
  done < <(ip -4 -o addr show scope global | awk '{print $2, $4}')

  if (( ${#nets[@]} > 0 )); then
    echo "lanfind: name lookup failed, sweeping ${nets[*]} ..." >&2

    # Unprivileged nmap can't ARP/ICMP, so probe TCP 22 (sshd, open to the
    # LAN on both boxes) plus 80/443. Router reverse-DNS names come along.
    unnamed=()
    while read -r ip name; do
      if [[ -n $name ]]; then
        record "$name" "$ip"
      else
        unnamed+=("$ip")
      fi
    done < <(nmap -sn -PS22,80,443 -oG - "${nets[@]}" 2>/dev/null \
               | awk '/Status: Up/ { n = $3; gsub(/[()]/, "", n); print $2, n }')

    # Hosts the router couldn't name: ask mDNS (one call, resolved in parallel).
    if [[ -n $(missing) ]] && (( ${#unnamed[@]} > 0 )); then
      while read -r ip name; do
        if [[ -n $name ]]; then record "$name" "$ip"; fi
      done < <(timeout 5 avahi-resolve-address "${unnamed[@]}" 2>/dev/null || true)
    fi
  fi
fi

# --- report ----------------------------------------------------------------
rc=0
for w in "${wanted[@]}"; do
  if [[ -n ${found[$w]:-} ]]; then
    echo "$w ${found[$w]}"
  else
    echo "lanfind: $w not found on the LAN" >&2
    rc=1
  fi
done
exit "$rc"
