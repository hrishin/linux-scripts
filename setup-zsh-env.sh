#!/usr/bin/env bash
# Sets up zsh + Oh My Zsh, tmux, and shell profile matching the standard dev environment.
# Supports Debian/Ubuntu, RedHat/Fedora/CentOS, and macOS (Homebrew).
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
section() { echo -e "\n${BOLD}==> $*${NC}"; }

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
  if [[ "$(uname)" == "Darwin" ]]; then
    OS=macos
    PKG_INSTALL="brew install"
  elif command -v apt-get &>/dev/null; then
    OS=debian
    PKG_INSTALL="sudo apt-get install -y"
  elif command -v dnf &>/dev/null; then
    OS=redhat
    PKG_INSTALL="sudo dnf install -y"
  elif command -v yum &>/dev/null; then
    OS=redhat
    PKG_INSTALL="sudo yum install -y"
  else
    error "Unsupported OS. Exiting."
    exit 1
  fi
  info "Detected OS: $OS"
}

# ---------------------------------------------------------------------------
# Package helpers
# ---------------------------------------------------------------------------
pkg_install() {
  info "Installing: $*"
  $PKG_INSTALL "$@"
}

ensure_pkg() {
  local cmd=$1 pkg=${2:-$1}
  if ! command -v "$cmd" &>/dev/null; then
    pkg_install "$pkg"
  else
    info "$cmd already installed — skipping"
  fi
}

# ---------------------------------------------------------------------------
# Backup a file before overwriting
# ---------------------------------------------------------------------------
backup_file() {
  local f=$1
  if [[ -f "$f" ]]; then
    local bak="${f}.bak.$(date +%Y%m%d%H%M%S)"
    warn "Backing up existing $f -> $bak"
    cp "$f" "$bak"
  fi
}

# ---------------------------------------------------------------------------
# Core packages
# ---------------------------------------------------------------------------
install_core_packages() {
  section "Installing core packages"
  if [[ "$OS" == "debian" ]]; then
    sudo apt-get update -qq
    pkg_install zsh tmux git curl wget
  elif [[ "$OS" == "redhat" ]]; then
    pkg_install zsh tmux git curl wget
  elif [[ "$OS" == "macos" ]]; then
    if ! command -v brew &>/dev/null; then
      error "Homebrew not found. Install it first: https://brew.sh"
      exit 1
    fi
    pkg_install zsh tmux git curl wget
  fi
}

# ---------------------------------------------------------------------------
# Oh My Zsh
# ---------------------------------------------------------------------------
install_oh_my_zsh() {
  section "Oh My Zsh"
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    info "Oh My Zsh already installed — skipping"
    return
  fi
  info "Installing Oh My Zsh (non-interactive)..."
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

# ---------------------------------------------------------------------------
# history-search-multi-word plugin (not bundled with OMZ)
# ---------------------------------------------------------------------------
install_hsmw_plugin() {
  section "history-search-multi-word plugin"
  local dest="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/history-search-multi-word"
  if [[ -d "$dest" ]]; then
    info "history-search-multi-word already present — skipping"
    return
  fi
  git clone --depth=1 \
    https://github.com/zdharma-continuum/history-search-multi-word.git \
    "$dest"
  info "Installed history-search-multi-word"
}

# ---------------------------------------------------------------------------
# Optional tools
# ---------------------------------------------------------------------------
install_direnv() {
  section "direnv"
  if command -v direnv &>/dev/null; then
    info "direnv already installed — skipping"
    return
  fi
  if [[ "$OS" == "macos" ]]; then
    pkg_install direnv
  elif [[ "$OS" == "debian" ]]; then
    pkg_install direnv
  elif [[ "$OS" == "redhat" ]]; then
    pkg_install direnv || {
      warn "direnv not in repos, installing via binary"
      local bin_dir="$HOME/.local/bin"
      mkdir -p "$bin_dir"
      curl -sfL https://direnv.net/install.sh | bash
    }
  fi
}

install_tfenv() {
  section "tfenv (Terraform version manager)"
  if [[ -d "$HOME/.tfenv" ]]; then
    info "tfenv already installed — skipping"
    return
  fi
  git clone --depth=1 https://github.com/tfutils/tfenv.git "$HOME/.tfenv"
  info "tfenv installed at ~/.tfenv"
}

install_krew() {
  section "kubectl krew plugin manager"
  if [[ -d "${KREW_ROOT:-$HOME/.krew}" ]]; then
    info "krew already installed — skipping"
    return
  fi
  if ! command -v kubectl &>/dev/null; then
    warn "kubectl not found — skipping krew install. Install kubectl first."
    return
  fi
  (
    set -x
    cd "$(mktemp -d)"
    OS_KREW="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm.*$/arm/' -e 's/aarch64/arm64/')"
    KREW_TMP="krew-${OS_KREW}_${ARCH}"
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW_TMP}.tar.gz"
    tar zxvf "${KREW_TMP}.tar.gz"
    ./"${KREW_TMP}" install krew
  )
}

# ---------------------------------------------------------------------------
# Write ~/.profile
# ---------------------------------------------------------------------------
write_profile() {
  section "Writing ~/.profile"
  backup_file "$HOME/.profile"

  cat > "$HOME/.profile" <<'PROFILE'
# ---------------------------------------------------------------------------
# macOS: Homebrew
# ---------------------------------------------------------------------------
if [[ "$(uname)" == "Darwin" ]] && [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ---------------------------------------------------------------------------
# PATH additions
# ---------------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.tfenv/bin:$PATH"
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
alias docker=podman
alias python=python3

# kubectl
alias kgnl="kubectl get node -L node-type"

# Pulumi
alias pup="pulumi up -y"
alias pdst="pulumi destroy -y"
alias psop="pulumi stack output"

# ---------------------------------------------------------------------------
# Pulumi
# ---------------------------------------------------------------------------
export PULUMI_CONFIG_PASSPHRASE=""

# ---------------------------------------------------------------------------
# SOPS / age
# ---------------------------------------------------------------------------
export SOPS_AGE_KEY_FILE="$HOME/.age/k8s-key.age"

# ---------------------------------------------------------------------------
# GitHub token — set manually (do NOT commit the actual value)
# export GH_TOKEN="<your-token>"
# ---------------------------------------------------------------------------
PROFILE

  info "~/.profile written"
}

# ---------------------------------------------------------------------------
# Write ~/.zshrc
# ---------------------------------------------------------------------------
write_zshrc() {
  section "Writing ~/.zshrc"
  backup_file "$HOME/.zshrc"

  cat > "$HOME/.zshrc" <<'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="fwalch"

plugins=(git kubectl history-search-multi-word)

source "$ZSH/oh-my-zsh.sh"

[[ -e ~/.profile ]] && source ~/.profile

unset zle_bracketed_paste

# direnv hook — only if installed
if command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi
ZSHRC

  info "~/.zshrc written"
}

# ---------------------------------------------------------------------------
# Write ~/.tmux.conf
# ---------------------------------------------------------------------------
write_tmux_conf() {
  section "Writing ~/.tmux.conf"
  backup_file "$HOME/.tmux.conf"

  cat > "$HOME/.tmux.conf" <<'TMUX'
# Prefix: C-a instead of C-b
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix

set -g allow-passthrough on
set -g set-clipboard on

# Split panes with | (horizontal) and - (vertical)
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

# Reload config
bind r source-file ~/.tmux.conf

# Switch panes with Alt-arrow (no prefix needed)
bind -n M-Left  select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up    select-pane -U
bind -n M-Down  select-pane -D

# Resize panes with 1/2/3/4 (with prefix)
bind -r 1 resize-pane -L 5
bind -r 2 resize-pane -R 5
bind -r 3 resize-pane -U 2
bind -r 4 resize-pane -D 2
TMUX

  info "~/.tmux.conf written"
}

# ---------------------------------------------------------------------------
# Change default shell to zsh
# ---------------------------------------------------------------------------
set_default_shell() {
  section "Default shell"
  local zsh_path
  zsh_path="$(command -v zsh)"
  if [[ "$SHELL" == "$zsh_path" ]]; then
    info "zsh is already the default shell"
    return
  fi
  if ! grep -qF "$zsh_path" /etc/shells; then
    echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
  fi
  chsh -s "$zsh_path"
  info "Default shell changed to zsh ($zsh_path). Re-login to take effect."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo -e "${BOLD}zsh environment setup${NC}"

  detect_os
  install_core_packages
  install_oh_my_zsh
  install_hsmw_plugin

  # Optional tools — comment out anything you don't need
  install_direnv
  install_tfenv
  install_krew

  write_profile
  write_zshrc
  write_tmux_conf
  set_default_shell

  echo
  info "Setup complete."
  warn "Remember to set GH_TOKEN manually in ~/.profile if needed."
  warn "Re-open your terminal (or run: exec zsh) to load the new config."
}

main "$@"
