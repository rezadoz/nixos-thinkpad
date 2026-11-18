{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # applications
    btop
    catnip
#     discord
    discordo
    feh
    fish
    ffmpeg
    geeqie
    gimp gimpPlugins.gmic
    imgbrd-grabber
    libreoffice-qt6
    mpv
    obs-studio
    qbittorrent
#     qemu_full
#     quickemu # qemu wrapper
#     retroarch-full
    pcsx2
    #steam # redudant, using `programs.steam.enable = true;`
    protonup-qt
    tor-browser
    tlrc # tldr
    #virtualbox
    wineWow64Packages.waylandFull
    winetricks
    yazi
    zathura
    zapzap # whatapp
    zsh zsh-powerlevel10k

    # utilities
    _7zz-rar unrar
    bat
    fastfetch
    figlet
    file
    fzf
    gnupg
    hunspellDicts.en-us-large
    imagemagick
    lolcat
    lsd
    ripgrep
    rsclock
    nix-output-monitor
    nmap
    pv
    qdirstat
    termdown
    tree
    weather
    unzip
    yt-dlp
    wavemon
    zip

    kdePackages.partitionmanager

    # laptop / Intel GPU
    intel-gpu-tools   # intel_gpu_top
    libva-utils       # vainfo — check that hardware decode is live
    powertop

    # dev pkgs
    android-tools
#     androidsdk
    autoconf
    automake
    binutils
    clang
    cmake
    curl
    gcc
    gdb
    git
    gh
    gnumake
    go
    libtool
    llvm
    meson
    ninja
    openssl
    patch
    pkg-config
    python3
    rustup
    stdenv.cc
    wget

    # my own packages
    (callPackage ./jogger.nix { })
  ];
}
