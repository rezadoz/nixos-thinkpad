{ config, pkgs, ... }:

# Home-manager module for the `bryan` user.
# Wired up in configuration.nix via `home-manager.users.bryan = import ./home.nix;`

{
  imports = [
    ./zsh.nix
  ];

  home.username = "bryan";
  home.homeDirectory = "/home/bryan";
  home.stateVersion = "26.05"; # DO NOT EDIT (first HM generation on runabout)

  home.sessionVariables = {
    EDITOR   = "nvim";
    VISUAL   = "nvim";
    PAGER    = "less";
    MANPAGER = "nvim +Man!";
  };

  home.packages = with pkgs; [
    #
  ];

  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      user.name  = "rezadoz";
      user.email = "rezadoz@gmail.com";
      init.defaultBranch = "master";
      pull.rebase = true;
      core.editor = "nvim";
      diff.tool = "nvimdiff";
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias  = false;
    vimAlias = false;
    withRuby    = false;
    withPython3 = false;
  };

  # Let home-manager manage itself (useful for `home-manager` CLI)
  #programs.home-manager.enable = true;
}
