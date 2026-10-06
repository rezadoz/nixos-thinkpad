{ config, pkgs, ... }:

let
  # LAN host finder — see lanfind.sh. Exported to zsh via lanssh.zsh.
  lanfind = pkgs.writeShellApplication {
    name = "lanfind";
    runtimeInputs = with pkgs; [ avahi nmap iproute2 gawk coreutils ];
    text = builtins.readFile ./lanfind.sh;
  };
in
{
  # (home.sessionVariables live in home.nix)

  home.packages = [ lanfind ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "history"
        "dirhistory"
        "z"
      ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    shellAliases = {
      update     = "sh /etc/nixos/update.sh";             # git tracked system update script
      goongit    = "~/code/workspace/goongit/goongit";    # git wizard
      catnips    = "catnip -d alsa_output.pci-0000_00_1f.3.analog-stereo";  # visualizer, L460 onboard audio (check: pactl list short sinks)
      rsclok     = "rsclock -S -c";                       # digital clock
      rain       = "mpv --volume=150 --loop ~/media/rainstorm8h.m4a";  # rain audio for sleep
      siren      = "mpv --loop ~/media/warsiren.mp3";     # audio for alarm
      weather    = "weather --forecast --no-cache 32958 | head -7"; # local weather
      forecast   = "weather --forecast --no-cache 32958"; # local forecast

      # --- Nix ---
      #nrs    = "sudo nixos-rebuild switch --upgrade --flake /etc/nixos#runabout";
      #nrt    = "sudo nixos-rebuild test --flake /etc/nixos#runabout";
      #nrb    = "sudo nixos-rebuild boot --flake /etc/nixos#runabout";
      cfg    = "$EDITOR /etc/nixos/";
#       jogger = "go run /etc/nixos/jogger";  # alias browser + launcher `/home/bryan/.config/jogger.toml
      ns     = "nix search nixpkgs";
      nsp    = "nix-shell -p";
      nsu    = "nix search nixpkgs-unstable";
      ngc    = "sudo nix-collect-garbage -d";
      nlo    = "nix profile list";
      rebuild    = "sudo nixos-rebuild switch --flake /etc/nixos#runabout";
      restartplasma = "kwin_wayland --replace &";	# restart plasma shell

      # --- LAN ---
      # Finds the host, exports $<HOST>_IP, connects. `lanscan` to refresh by hand.
      ssh-ideapad    = "_lan_ensure ideapad && ssh -o HostKeyAlias=ideapad nasrin@$IDEAPAD_IP";
      ssh-enterprise = "_lan_ensure uss-enterprise && ssh -o HostKeyAlias=uss-enterprise operator@$USS_ENTERPRISE_IP";

      # --- Git ---
      #g      = "git";
      ga     = "git add";
      gaa    = "git add --all";
      gc     = "git commit";
      gcm    = "git commit -m";
      gca    = "git commit --amend";
      gco    = "git checkout";
      gcb    = "git checkout -b";
      gd     = "git diff";
      gds    = "git diff --staged";
      gl     = "git log --oneline --graph --decorate";
      gla    = "git log --oneline --graph --decorate --all";
      gp     = "git push";
      gpf    = "git push --force-with-lease";
      gpl    = "git pull";
      gst    = "git status";
      gstash = "git stash";
      gpop   = "git stash pop";
      gr     = "git remote -v";
      grb    = "git rebase";
      gri    = "git rebase -i";
      grs    = "git restore";
      grss   = "git restore --staged";
      gcp    = "git cherry-pick";

      # --- General QoL ---
      ".."   = "cd ..";
      "..."  = "cd ../..";
      "...." = "cd ../../..";
      ll     = "ls -lah";
      la     = "ls -A";
      l      = "ls -CF";
      makemine   = "sudo chown -R $USER:$(id -gn)";
      mkdir  = "mkdir -p";
      cp     = "cp -iv";
      mv     = "mv -iv";
      rm     = "rm -iv";
      df     = "df -h";
      du     = "du -sh";
      free   = "free -h";
      grep   = "grep --color=auto";
      p      = "python3";
      #vi     = "nvim";
      #vim    = "nvim";
      #v      = "nvim";
      y      = "yazi";
      yz     = "yazi";
      zshrc  = "$EDITOR ~/.config/zsh/.zshrc";
      vimrc  = "$EDITOR ~/.config/nvim/init.lua";
    };

    initContent = ''
      # Powerlevel10k instant prompt
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

      # Source p10k config if it exists (run `p10k configure` to generate it)
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

      # lanscan / _lan_ensure — used by the ssh-* aliases
      source ${./lanssh.zsh}
    '';
  };
}
