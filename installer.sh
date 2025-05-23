#!/usr/bin/env bash
set -euo pipefail

# ====================================================
# Constants & Colors
# ====================================================
RED='\e[31m'; GRN='\e[32m'; BLU='\e[34m'; DEF='\e[0m'
VERSION="1.0.1"

# ====================================================
# Detect User Shell & RC File for exporting paths
# ====================================================
if [[ -f "$HOME/.zshrc" ]]; then
  SH="zsh";    RCFILE="$HOME/.zshrc"
else
  SH="bash";   RCFILE="$HOME/.bashrc"
fi

# ====================================================
# Detect Package Manager via /etc/os-release
# ====================================================
source /etc/os-release

SUDO="sudo "

ID_LIKE="${ID_LIKE:-$ID}"

case "${ID_LIKE,,}" in
  ubuntu|debian)
    INSTALL="apt-get install -y"
    REMOVE="apt-get remove -y"
    ;;
  fedora)
    INSTALL="dnf install --assumeyes"
    REMOVE="dnf remove --assumeyes"
    ;;
  rhel|centos)
    INSTALL="yum install -y"
    REMOVE="yum remove -y"
    ;;
  arch)
    INSTALL="pacman -Sy --noconfirm"
    REMOVE="pacman -Rs --noconfirm"
    ;;
  alpine)
    INSTALL="apk add"
    REMOVE="apk del"
    ;;
  opensuse*|suse*)
    INSTALL="zypper --non-interactive install"
    REMOVE="zypper --non-interactive remove"
    ;;
  gentoo)
    INSTALL="emerge"
    REMOVE="emerge --depclean"
    ;;
  *)
    echo -e "${RED}Unsupported distro: $ID_LIKE${DEF}" >&2
    exit 1
    ;;
esac

CMD_INSTALL="$SUDO $INSTALL"
CMD_REMOVE="$SUDO $REMOVE"

# ====================================================
# Logging Helpers
# ====================================================
info()    { echo -e "${BLU}$*${DEF}"; }
success() { echo -e "${GRN}$*${DEF}"; }
error()   { echo -e "${RED}$*${DEF}" >&2; }

# ====================================================
# Generic Installer / Remover
# ====================================================
# install_generic <Name> <check-cmd> <install-cmd>
install_generic() {
  local name="$1" check="$2" cmd="$3"
  info "Checking for $name…"
  if ! eval "$check" &>/dev/null; then
    info "Installing $name…"
    if eval "$cmd"; then
      success "$name installed"
    else
      error "Failed to install $name"
    fi
  else
    success "$name already installed"
  fi
}

# remove_generic <Name> <remove-cmd>
remove_generic() {
  local name="$1" cmd="$2"
  info "Removing $name…"
  if eval "$cmd"; then
    success "$name removed"
  else
    error "Failed to remove $name"
  fi
}

# ====================================================
# Section: Languages & Runtimes
# ====================================================
install_python() {
  install_generic "Python3" "python3 --version" "$CMD_INSTALL python3"
}

install_go() {
  info "Checking for Go…"
  if ! command -v go &>/dev/null; then
    info "Installing Go 1.24.3…"
    curl -LO https://get.golang.org/$(uname)/go_installer && chmod +x go_installer && ./go_installer && rm go_installer
    success "Go installed"
    info "Adding Go to $RCFILE…"
    info "Please run: source $RCFILE"
  else
    success "Go already installed"
  fi
}

install_csharp() {
  info "Checking for .NET (C#)…"
  if ! command -v dotnet &>/dev/null; then
    info "Installing .NET…"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh \
      && chmod +x dotnet-install.sh \
      && ./dotnet-install.sh --version latest
    rm -f dotnet-install.sh
    success ".NET installed"
    info "Adding .NET to $RCFILE…"
    {
      echo '# .NET'
      echo 'export DOTNET_ROOT=$HOME/.dotnet'
      echo 'export PATH=$PATH:$HOME/.dotnet/tools'
    } >> "$RCFILE"
    info "Please run: source $RCFILE"
  else
    success ".NET already installed"
  fi
}

install_swift() {
  info "Checking for Swift…"
  if ! command -v swift &>/dev/null; then
    info "Installing Swift via Swiftly…"
    curl -fsSL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" \
      -o swiftly.tar.gz \
      && tar -xzf swiftly.tar.gz \
      && rm swiftly.tar.gz \
      && ./swiftly init
    success "Swiftly installed"
    info "Adding Swift to $RCFILE…"
    {
      echo '# Swift'
      echo 'export PATH=$PATH:$HOME/.local/share/swiftly/bin'
      echo 'export SWIFTLY_HOME_DIR=$HOME/.local/share/swiftly'
    } >> "$RCFILE"
    info "Please run: source $RCFILE"
  else
    success "Swift already installed"
  fi
}

install_kotlin() {
  install_generic "Kotlin" "kotlin -version" "$CMD_INSTALL kotlin"
}

install_rust() {
  info "Checking for Rust…"
  if ! command -v rustc &>/dev/null; then
    info "Installing Rust…"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    success "Rust installed"
    info "Adding Rust to $RCFILE…"
    {
      echo '# Rust'
      echo 'export PATH=$PATH:$HOME/.cargo/bin'
    } >> "$RCFILE"
    info "Please run: source $RCFILE"
  else
    success "Rust already installed"
  fi
}

install_ruby() {
  install_generic "Ruby" "ruby --version" "$CMD_INSTALL ruby"
}

install_php() {
  install_generic "PHP" "php --version" "$CMD_INSTALL php"
}

install_perl() {
  install_generic "Perl" "perl --version" "$CMD_INSTALL perl"
}

install_java() {
  install_generic "Java Compiler" "javac --version" "$CMD_INSTALL default-jdk"
}
# ====================================================
# Section: Package Managers & Runtimes (Node, pnpm, bun…)
# ====================================================
install_nvm_node() {
  info "Checking for Node.js…"
  if ! command -v node &>/dev/null; then
    install_generic "NVM" "nvm --version" \
      "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | $SH"
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    info "Installing latest LTS Node.js…"
    nvm install --lts
  else
    success "Node.js already installed"
  fi
}

install_yarn() {
  install_generic "Yarn" "yarn --version" \
    "curl -fsSL https://yarnpkg.com/install.sh | bash"
}

install_pnpm() {
  install_generic "pnpm" "pnpm --version" \
    "curl -fsSL https://get.pnpm.io/install.sh | \
     ENV=\"$RCFILE\" SHELL=\"$(which $SH)\" $SH -"
}

install_bun() {
  install_generic "Bun" "bun --version" \
    "curl -fsSL https://bun.sh/install | bash"
}

# ====================================================
# Section: Container & Virtualization
# ====================================================
install_docker() {
  install_generic "Docker" "docker --version" \
    "curl -fsSL https://get.docker.com | sh"
}
install_podman() {
  install_generic "Podman" "podman --version" "$CMD_INSTALL podman"
}

# ====================================================
# Section: Build Tools & Editors
# ====================================================
install_git()     { install_generic "Git" "git --version" "$CMD_INSTALL git"; }
install_maven()   { install_generic "Maven" "mvn --version" "$CMD_INSTALL maven"; }
install_gradle()  { install_generic "Gradle" "gradle --version" "$CMD_INSTALL gradle"; }
install_vscode() { install_generic "VSCode" "code --version" "$CMD_INSTALL code"; }
install_vim()    { install_generic "Vim" "vim --version" "$CMD_INSTALL vim"; }
install_emacs() { install_generic "Emacs" "emacs --version" "$CMD_INSTALL emacs"; }
install_intellij() {
    echo "Downloading IntelliJ IDEA…"
    local link="https://www.jetbrains.com/idea/download/download-thanks.html?platform=linux&code=IIC"
    local tarball="idea.tar.gz"
    curl -fsSL "$link" -o "$tarball"
    info "Installing IntelliJ IDEA…"
    sudo rm -rf /opt/idea
    sudo mkdir -p /opt/idea
    sudo tar -xzf "$tarball" -C /opt/idea --strip-components=1
    rm -f "$tarball"
    success "IntelliJ IDEA installed"
    info "Adding IntelliJ IDEA to $RCFILE…"
    {
      echo ""
      echo "# IntelliJ IDEA"
      echo 'export PATH=$PATH:/opt/idea/bin'
    } >> "$RCFILE"
    info "Please run: source $RCFILE"   
}
install_cursor() {
  info "Checking for Cursor…"
  if ! command -v cursor &>/dev/null; then
    info "Installing Cursor…"
    local link="https://cursor.so/download/linux"
    local tarball="cursor.tar.gz"
    curl -fsSL "$link" -o "$tarball"
    sudo rm -rf /opt/cursor
    sudo mkdir -p /opt/cursor
    sudo tar -xzf "$tarball" -C /opt/cursor --strip-components=1
    rm -f "$tarball"
    success "Cursor installed"
  else
    success "Cursor already installed"
  fi
}

# ====================================================
# Section: IDEs & GUI Tools
# ====================================================

## install_android
# Checks for studio.sh in your PATH; if missing, downloads the latest
# Linux tarball, unpacks into ~/AndroidStudio, and adds it to your shell rc.
install_android() {
  info "Checking for Android Studio…"
  if ! command -v studio.sh &>/dev/null; then
    info "Fetching download page…"
    local page="https://developer.android.com/studio"
    local link
    link=$(curl -fsSL "$page" \
           | grep -Eo 'https://[^"]+linux\.tar\.gz' \
           | head -n1)

    if [[ -z "$link" ]]; then
      error "Could not find Android Studio download link"
      return 1
    fi

    info "Downloading from: $link"
    local tarball="android-studio.tar.gz"
    curl -fsSL "$link" -o "$tarball"

    info "Installing to ~/AndroidStudio…"
    sudo rm -rf "$HOME/AndroidStudio"
    mkdir -p "$HOME/AndroidStudio"
    tar -xzf "$tarball" -C "$HOME/AndroidStudio" --strip-components=1
    rm -f "$tarball"
    success "Android Studio installed"

    info "Adding launcher to PATH in $RCFILE…"
    {
      echo ""
      echo "# Android Studio"
      echo 'export PATH=$PATH:$HOME/AndroidStudio/bin'
    } >> "$RCFILE"
    info "Please run: source $RCFILE"
  else
    success "Android Studio already installed"
  fi
}

## remove_android
# Removes the ~/AndroidStudio folder.
remove_android() {
  info "Removing Android Studio…"
  sudo rm -rf "$HOME/AndroidStudio"
  success "Android Studio removed"
}

# ====================================================
# Section: Language Framework Templates (stubs)
# ====================================================
create_template_django()   { info "Scaffolding Django project…";   }
create_template_flask()    { info "Scaffolding Flask project…";    }
create_template_react()    { info "Scaffolding React project…";    }
create_template_angular()  { info "Scaffolding Angular project…";  }
create_template_vuejs()    { info "Scaffolding Vue.js project…";   }
create_template_expressjs(){ info "Scaffolding Express.js project…";}
create_template_spring()   { info "Scaffolding Spring project…";   }

# ====================================================
# CLI Parsing (now supports multiple names for -i and -r)
# ====================================================
print_help() {
  cat <<EOF
Usage: $0 [OPTIONS] [TOOLS...]
Options:
  -h, --help           Show this message and exit
  -v, --version        Show version
  -i, --install TOOLS  Install one or more tools (e.g. -i git docker node)
  -r, --remove TOOLS   Remove one or more tools (e.g. -r git docker)
  -t, --template NAME  Create a project template (single framework)
EOF
}

case "${1-}" in
  -h|--help)
    print_help; exit 0
    ;;
  -v|--version)
    echo "Version $VERSION"; exit 0
    ;;
  -i|--install)
    shift
    if [[ $# -eq 0 ]]; then
      error "No tools specified for install"; exit 1
    fi
    while [[ $# -gt 0 && $1 != -* ]]; do
      tool="$1"
      if declare -F install_"$tool" &>/dev/null; then
        install_"$tool"
      else
        error "Unknown tool: $tool"
      fi
      shift
    done
    ;;
  -r|--remove)
    shift
    if [[ $# -eq 0 ]]; then
      error "No tools specified for remove"; exit 1
    fi
    while [[ $# -gt 0 && $1 != -* ]]; do
      tool="$1"
      if declare -F remove_"$tool" &>/dev/null; then
        remove_"$tool"
      else
        error "Unknown tool: $tool"
      fi
      shift
    done
    ;;
  -t|--template)
    shift
    if [[ $# -eq 0 ]]; then
      error "No framework specified for template"; exit 1
    fi
    framework="$1"
    if declare -F create_template_"$framework" &>/dev/null; then
      create_template_"$framework"
    else
      error "Unknown framework: $framework"; exit 1
    fi
    ;;
  *)
    print_help
    exit 1
    ;;
esac
