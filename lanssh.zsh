# lanssh.zsh — sourced by zsh.nix; backs the ssh-* aliases.
#
#   lanscan [HOST...]   find hosts with `lanfind` and export <HOST>_IP for each
#                       (no args = both boxes). uss-enterprise -> USS_ENTERPRISE_IP,
#                       ideapad -> IDEAPAD_IP
#   _lan_ensure HOST    keep the exported IP if it still answers on :22,
#                       otherwise rescan. Used by the aliases.

_lan_var() { print -r -- "${${1:u}//-/_}_IP" }

lanscan() {
  (( $# )) || set -- uss-enterprise ideapad
  local out line host ip rc
  out=$(lanfind "$@"); rc=$?
  for line in ${(f)out}; do
    host=${line%% *} ip=${line##* }
    export "$(_lan_var $host)=$ip"
    print -r -- "$host → $ip"
  done
  return rc
}

_lan_ensure() {
  local var=$(_lan_var $1)
  local ip=${(P)var}
  # Cheap liveness check: can we open TCP 22 within a second?
  if [[ -n $ip ]] && timeout 1 bash -c "exec 3<>/dev/tcp/$ip/22" 2>/dev/null; then
    return 0
  fi
  unset $var
  lanscan $1 && [[ -n ${(P)var} ]]
}
