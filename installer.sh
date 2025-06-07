#!/usr/bin/env bash
set -euo pipefail

# ====================================================
# Constants & Colors
# ====================================================
RED='\e[31m'; GRN='\e[32m'; BLU='\e[34m'; DEF='\e[0m'
VERSION="1.2.0"

# ====================================================
# Detect User Shell & RC File for exporting paths
# ====================================================
SH=$(basename "$SHELL")
RCFILE="$HOME/.${SH}rc"
if [[ -z "$RCFILE" ]]; then
  RCFILE="$HOME/.bashrc"
fi

# ====================================================
# Logging Helpers
# ====================================================
info()    { echo -e "${BLU}$*${DEF}"; }
success() { echo -e "${GRN}$*${DEF}"; }
error()   { echo -e "${RED}$*${DEF}" >&2; }

# ====================================================
# Detect Package Manager via /etc/os-release
# ====================================================
in_container() {
    [[ -f /.dockerenv ]] || grep -qE 'docker|lxc' /proc/1/cgroup 2>/dev/null
}

source /etc/os-release

if [[ $EUID -eq 0 ]]; then
    SUDO=""
elif command -v sudo &>/dev/null; then
    SUDO="sudo "
elif command -v doas &>/dev/null; then
    SUDO="doas "
else
    SUDO=""
fi

ID_LIKE="${ID_LIKE:-$ID}"

case "${ID_LIKE,,}" in
  ubuntu|debian)
    INSTALL="apt-get install -y"
    REMOVE="apt-get remove -y"
    UPDATE="apt-get update -y -qq"
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
    INSTALL="apk add --no-cache"
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

if in_container && [[ "${ID_LIKE,,}" =~ ubuntu|debian ]]; then
    info "Refreshing APT repositories (container only)…"
    $SUDO $UPDATE
fi


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
            return 1
        fi
    else
        success "$name already present"
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

# checker_generic <cmd1> [<cmd2> ...]
checker_generic() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} )); then
        info "Bootstrapping: ${missing[*]}"
        $CMD_INSTALL "${missing[@]}" \
        && success "Bootstrapped prerequisites" \
        || { error "Failed to install prerequisites"; exit 1; }
    fi
}


# ====================================================
# Section: Languages & Runtimes
# ====================================================
install_python() {
    #
    # On Debian/Ubuntu/Fedora/RHEL/CentOS/Alpine: the package is called "python3"
    # On Arch: Python 3 is provided by "python" (the "python" package is Python 3.11+)
    #
    case "${ID_LIKE,,}" in
      ubuntu|debian|fedora|rhel|centos|alpine|opensuse*|suse*)
        install_generic "Python3" "python3 --version" "$CMD_INSTALL python3"
        ;;
      arch)
        install_generic "Python3 (Arch)" "python --version" "$CMD_INSTALL python"
        ;;
      gentoo)
        install_generic "Python3" "python3 --version" "$CMD_INSTALL dev-lang/python"
        ;;
      *)
        error "Don't know how to install Python3 on $ID_LIKE"; return 1
        ;;
    esac
}

install_go() {
    #
    # On Ubuntu/Debian: "golang-go"
    # On Fedora:     "golang"
    # On RHEL/CentOS: EPEL "golang" (yum install -y golang) or manual fallback
    # On Arch:       "go"
    # On Alpine:     "go"
    # On openSUSE:   "go"
    # On Gentoo:     "dev-lang/go"
    #
    case "${ID_LIKE,,}" in
      ubuntu|debian)
        install_generic "Go" "go version" "$CMD_INSTALL golang-go"
        ;;
      fedora)
        install_generic "Go" "go version" "$CMD_INSTALL golang"
        ;;
      rhel|centos)
        # RHEL7/CentOS7 may not have a recent enough go; fall back to manual if missing or too old.
        if rpm -q --quiet golang; then
          install_generic "Go" "go version" "$CMD_INSTALL golang"
        else
          info "Default 'golang' package not found or too old; installing Go from upstream…"
          checker_generic curl
          curl -fsSL "https://get.golang.org/$(uname)/go_installer" -o go_installer
          chmod +x go_installer && ./go_installer && rm go_installer
          success "Go installed from upstream"
        fi
        ;;
      opensuse*|suse*|arch|alpine)
        install_generic "Go" "go version" "$CMD_INSTALL go"
        ;;
      gentoo)
        install_generic "Go" "go version" "$CMD_INSTALL dev-lang/go"
        ;;
      *)
        error "Don't know how to install Go on $ID_LIKE"; return 1
        ;;
    esac
}

install_csharp() {
    checker_generic curl
    install_generic ".NET SDK" "dotnet --version" \
        "curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --version latest"
    if ! grep -q 'DOTNET_ROOT' "$RCFILE"; then
        info "Adding .NET to $RCFILE"
        {
            echo '# .NET'
            echo 'export DOTNET_ROOT=$HOME/.dotnet'
            echo 'export PATH=$PATH:$HOME/.dotnet/tools'
        } >>"$RCFILE"
    fi
}

install_swift() {
    #
    # Swift is not packaged in the standard repos on most distros → always do the upstream‐fetch approach.
    #
    # Ensure we have GPG (gnupg) to verify signatures, plus curl/tar/unzip
    #
    install_generic "GnuPG" "gpg --version" "$CMD_INSTALL gnupg"
    checker_generic curl tar unzip

    if ! command -v swift &>/dev/null; then
        info "Installing Swiftly (Swift version manager)…"
        curl -fsSL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" \
            | tar -xz && ./swiftly init
        success "Swift installed via Swiftly"
    else
        success "Swift already installed—skipping"
    fi

    if ! grep -q 'swiftly/bin' "$RCFILE"; then
        info "Adding Swift to $RCFILE"
        {
            echo '# Swift'
            echo 'export PATH=$PATH:$HOME/.local/share/swiftly/bin'
            echo 'export SWIFTLY_HOME_DIR=$HOME/.local/share/swiftly'
        } >>"$RCFILE"
    fi
}

install_rust() {
    #
    # Rustup is not typically in repos (or is very old), so always use the official installer.
    #
    checker_generic curl
    install_generic "Rustup" "rustc --version" \
        "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    if ! grep -q '.cargo/bin' "$RCFILE"; then
        info "Adding Rust to $RCFILE"
        echo 'export PATH=$PATH:$HOME/.cargo/bin' >>"$RCFILE"
    fi
}

install_kotlin() {
    #
    # On Debian/Ubuntu:      "kotlin"
    # On Fedora:            "kotlin"
    # On RHEL/CentOS:       might not exist → manual fallback
    # On Arch:              "kotlin"
    # On Alpine:            "kotlin"
    # On openSUSE:          "kotlin"
    # On Gentoo:            "dev-lang/kotlin"
    #
    case "${ID_LIKE,,}" in
      ubuntu|debian|fedora|arch|alpine|opensuse*|suse*|rhel|centos)
        install_generic "Kotlin" "kotlin -version" "$CMD_INSTALL kotlin"
        ;;
      rhel|centos)
        if rpm -q --quiet kotlin; then
          install_generic "Kotlin" "kotlin -version" "$CMD_INSTALL kotlin"
        else
          info "Kotlin not packaged on RHEL/CentOS; installing manually…"
          # (Example manual install—replace URL with actual “latest Kotlin” if desired)
          local KOTLIN_VER="1.9.0"   # update as needed
          wget -qO kotlin.zip "https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_VER}/kotlin-compiler-${KOTLIN_VER}.zip"
          unzip -q kotlin.zip -d "$HOME/.local/share/kotlin"
          rm kotlin.zip
          ln -sf "$HOME/.local/share/kotlin/bin/kotlinc" "$HOME/.local/bin/kotlinc"
          success "Kotlin ${KOTLIN_VER} installed manually"
        fi
        ;;
      gentoo)
        install_generic "Kotlin" "kotlin -version" "$CMD_INSTALL dev-lang/kotlin"
        ;;
      *)
        error "Don't know how to install Kotlin on $ID_LIKE"; return 1
        ;;
    esac
}

install_ruby() {
    install_generic "Ruby" "ruby --version" "$CMD_INSTALL ruby"
}

install_php() {
    #
    # On Debian/Ubuntu:    "php"
    # On Fedora/RHEL/CentOS: "php"
    # On Arch:             "php"
    # On Alpine:           "php7" or "php81" etc. → fallback
    # On openSUSE:         "php" or "php8"
    # On Gentoo:           "dev-lang/php"
    #
    case "${ID_LIKE,,}" in
      ubuntu|debian|fedora|rhel|centos|arch|opensuse*|suse* )
        install_generic "PHP" "php --version" "$CMD_INSTALL php"
        ;;
      alpine)
        install_generic "PHP" "php --version" "$CMD_INSTALL php7"
        ;;
      gentoo)
        install_generic "PHP" "php --version" "$CMD_INSTALL dev-lang/php"
        ;;
      *)
        error "Don't know how to install PHP on $ID_LIKE"; return 1
        ;;
    esac
}

install_perl() {
    install_generic "Perl" "perl --version" "$CMD_INSTALL perl"
}

install_java() {
    #
    # We want to install JDK (javac). Package names differ:
    #   – Debian/Ubuntu:    "default-jdk"
    #   – Fedora:           "java-11-openjdk-devel"
    #   – RHEL/CentOS:      "java-1.8.0-openjdk-devel" (if 7, else 11)
    #   – Arch:             "jdk-openjdk"
    #   – Alpine:           "openjdk11"
    #   – openSUSE/SUSE:    "java-11-openjdk-devel"
    #   – Gentoo:           "dev-java/openjdk"
    #
    local pkg
    case "${ID_LIKE,,}" in
      ubuntu|debian)
        pkg="openjdk-17-jdk";;
      fedora|rhel|centos)
        pkg="java-17-openjdk-devel";;
      arch)
        pkg="jdk17-openjdk";;
      alpine)
        pkg="openjdk17";;
      opensuse*|suse*)
        pkg="java-17-openjdk-devel";;
      gentoo)
        pkg="dev-java/openjdk:17";;
      *)
        error "No Java pkg mapping for $ID_LIKE"; return 1;;
    esac

    install_generic "Java (javac)" "javac --version" "$CMD_INSTALL $pkg"
}

install_flutter() {
    #
    # Flutter is not “same-named” everywhere → always do an upstream install.
    # We delegate all Android/Studio/cmdline-tools work to install_android().
    #
    install_generic "XZ utils" "xz --version" "$CMD_INSTALL xz-utils"
    checker_generic curl jq tar unzip git clang zip

    # Install Chromium for Flutter web support
    install_chromium

    # Ensure Java is present for Android builds
    install_java

	# Install Linux toolchain for building Flutter apps
	checker_generic cmake ninja-build pkg-config libgtk-3-dev libgl1-mesa-dev libglu1-mesa-dev mesa-utils

    # ─────────────────────────────────────────────────────────────────────────────
    # Install Android Studio + cmdline-tools
    # ─────────────────────────────────────────────────────────────────────────────
    install_android

    # ─────────────────────────────────────────────────────────────────────────────
    # Now install or upgrade Flutter itself (from Google’s stable channel JSON)
    # ─────────────────────────────────────────────────────────────────────────────
    info "Checking for Flutter…"
    if ! command -v flutter &>/dev/null; then
        info "Installing Flutter SDK…"
        releases_json="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
        latest=$(curl -fsSL "$releases_json" \
                 | jq -r '.releases[] | select(.channel=="stable") | .version' \
                 | head -n1)
        tarball="flutter_linux_${latest}-stable.tar.xz"
        url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$tarball"
        tmpdir=$(mktemp -d)
        curl -fL "$url" -o "$tmpdir/$tarball"
        tar xf "$tmpdir/$tarball" -C "$HOME"
        rm -rf "$tmpdir"
        success "Flutter SDK $latest installed to \$HOME/flutter"

        if ! grep -q 'flutter/bin' "$RCFILE"; then
            info "Adding Flutter & Android env to $RCFILE…"
            {
                echo ""
                echo "# Flutter SDK"
                echo 'export PATH="$PATH:$HOME/flutter/bin"'
                echo ""
                echo "# Android SDK"
                echo 'export ANDROID_HOME="'"$ANDROID_SDK_ROOT"'"'
                echo 'export ANDROID_SDK_ROOT="'"$ANDROID_SDK_ROOT"'"'
                echo 'export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"'
            } >>"$RCFILE"
            info "Run: source $RCFILE"
        fi
    else
        success "Flutter already installed—upgrading…"
        cd "$HOME/flutter"
        git fetch origin stable
        git reset --hard origin/stable
        flutter upgrade
        success "Now on $(flutter --version | head -n1)"
        cd - &>/dev/null
    fi

    # ─────────────────────────────────────────────────────────────────────────────
    # Final Android SDK components & license acceptance
    # ─────────────────────────────────────────────────────────────────────────────
    info "Installing Android SDK components…"
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" \
        "platform-tools" "platforms;android-35" "build-tools;35.0.1" || true
    info "Accepting all Android SDK licenses…"
    yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses || true

	success "Flutter installation complete!"
	if [[ "$EUID" -eq 0 ]]; then
			info "If you are using the script as a root user; you might need to run: git config --global --add safe.directory $HOME/flutter"
	fi
	info "Run: source $RCFILE  (or reopen your shell) to pick up Flutter & Android SDK"
	info "Run: flutter doctor -v  to check your Flutter installation, if you see that android studio is not found, run: flutter config --android-studio-dir=$HOME/AndroidStudio"
}


# ====================================================
# Section: Package Managers & Runtimes (Node, pnpm, bun…)
# ====================================================
install_nvm_node() {
    checker_generic curl
    info "Checking for Node.js…"
    if ! command -v node &>/dev/null; then
        install_generic "NVM" "nvm --version" \
            "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        info "Installing latest LTS Node.js…"
        nvm install --lts
    else
        success "Node.js already installed"
    fi
}

install_yarn() {
    checker_generic curl
    install_nvm_node
    install_generic "Yarn" "yarn --version" \
        "curl -fsSL https://yarnpkg.com/install.sh | bash"
}

install_pnpm() {
    checker_generic curl
    install_generic "pnpm" "pnpm --version" \
        "curl -fsSL https://get.pnpm.io/install.sh | \
         ENV=\"$RCFILE\" SHELL=\"$(which "$SH")\" $SH -"
}

install_bun() {
    checker_generic curl unzip
    install_generic "Bun" "bun --version" \
        "curl -fsSL https://bun.sh/install | bash"
}


# ====================================================
# Section: Container & Virtualization
# ====================================================
install_docker() {
    checker_generic curl
    install_generic "Docker" "docker --version" \
        "curl -fsSL https://get.docker.com | sh"
}

install_podman() {
    install_generic "Podman" "podman --version" "$CMD_INSTALL podman"
}


# ====================================================
# Section: Build Tools & Editors
# ====================================================

install_chromium() {
    #
    # If Chromium is already on PATH, skip installation.
    #
    if command -v chromium &>/dev/null; then
        success "Chromium already installed: $(chromium --version 2>/dev/null || echo 'unknown version')"
        return 0
    fi

    #
    # Otherwise, grab the latest official Linux_x64 snapshot of Chromium.
    #
    checker_generic curl unzip sudo

    info "Fetching latest Chromium snapshot revision…"
    revision=$(curl -fsSL \
      "https://www.googleapis.com/download/storage/v1/b/chromium-browser-snapshots/o/Linux_x64%2FLAST_CHANGE?alt=media")
    if [[ -z "$revision" ]]; then
        error "Could not obtain latest Chromium revision"
        return 1
    fi

    info "Latest Chromium revision is $revision"
    snapshot_url="https://www.googleapis.com/download/storage/v1/b/chromium-browser-snapshots/o/Linux_x64%2F${revision}%2Fchrome-linux.zip?alt=media"

    info "Downloading Chromium snapshot (rev $revision)…"
    tmpdir=$(mktemp -d)
    curl -fL "$snapshot_url" -o "$tmpdir/chrome-linux.zip"

    info "Unpacking Chromium to /opt/chromium…"
    sudo mkdir -p /opt/chromium
    sudo unzip -q "$tmpdir/chrome-linux.zip" -d /opt/chromium

    rm -rf "$tmpdir"

    info "Creating symlink /usr/local/bin/chromium → /opt/chromium/chrome-linux/chrome"
    sudo ln -sf /opt/chromium/chrome-linux/chrome /usr/local/bin/chromium

	# Export CHROME_EXECUTABLE environment variable
	if ! grep -q 'CHROME_EXECUTABLE' "$RCFILE"; then
		info "Adding CHROME_EXECUTABLE to $RCFILE"
		echo "# Chromium" >> "$RCFILE"
		echo 'export CHROME_EXECUTABLE="/usr/local/bin/chromium"' >> "$RCFILE"
	fi

    success "Chromium rev $revision installed (binary at /usr/local/bin/chromium)"
}


install_git() {
    install_generic "Git" "git --version" "$CMD_INSTALL git"
}

install_maven() {
    install_generic "Maven" "mvn --version" "$CMD_INSTALL maven"
}

install_gradle() {
    case "${ID_LIKE,,}" in
      ubuntu|debian|centos|arch|alpine|opensuse*|suse*|gentoo)
        install_generic "Gradle" "gradle --version" "$CMD_INSTALL gradle"
        ;;
      *)
        info "Gradle package not found in $ID_LIKE repos; installing manually…"
        GRADLE_VER="8.6.1"   # Update to latest if needed
        wget -qO gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VER}-bin.zip"
        unzip -q gradle.zip -d "$HOME/.local/share/gradle"
        rm gradle.zip
        ln -sf "$HOME/.local/share/gradle/gradle-${GRADLE_VER}/bin/gradle" "$HOME/.local/bin/gradle"
        success "Gradle ${GRADLE_VER} installed manually"
        ;;
    esac
}

install_vscode() {
    success "Skipping VSCode install in automated environment"
}

install_vim() {
    install_generic "Vim" "vim --version" "$CMD_INSTALL vim"
}

install_emacs() {
    install_generic "Emacs" "emacs --version" "$CMD_INSTALL emacs"
}

install_intellij() {
    success "Skipping IntelliJ IDEA install in automated environment"
}

install_cursor() {

    success "Skipping Cursor install in automated environment"
}


# ====================================================
# Section: IDEs & GUI Tools
# ====================================================
install_android() {
    #
    # 1) Ensure we have curl, tar, unzip, sudo
    #
    checker_generic curl tar unzip sudo

    #
    # 2) Download & unpack Android Studio (IDE) if not present
    #
    info "Checking for Android Studio…"
    if ! command -v studio.sh &>/dev/null; then
        info "Fetching Android Studio download page…"
        local page="https://developer.android.com/studio"
        local link
        link=$(curl -fsSL "$page" \
                | grep -Eo 'https://[^"]+linux\.tar\.gz' \
                | head -n1)

        if [[ -z "$link" ]]; then
            error "Could not find Android Studio download link"
            return 1
        fi

        info "Downloading Android Studio from: $link"
        local tarball="android-studio.tar.gz"
        curl -fSL --retry 3 --retry-delay 5 "$link" -o "$tarball"

        info "Installing to ~/AndroidStudio…"
        sudo rm -rf "$HOME/AndroidStudio"
        mkdir -p "$HOME/AndroidStudio"
        tar -xzf "$tarball" -C "$HOME/AndroidStudio" --strip-components=1
        rm -f "$tarball"
        success "Android Studio installed to ~/AndroidStudio"

        info "Adding Android Studio to \$PATH in $RCFILE…"
        {
            echo ""
            echo "# Android Studio IDE"
            echo 'export PATH="$PATH:$HOME/AndroidStudio/bin"'
        } >> "$RCFILE"
        info "Run: source $RCFILE  (or reopen your shell) to pick up Android Studio"
    else
        success "Android Studio already installed"
    fi

    #
    # 4) Prepare Android SDK root directory
    #
    ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"


    #
    # 5) Download & unpack Android “command-line tools” if sdkmanager isn’t present
    #
    if ! command -v sdkmanager &>/dev/null; then
        filename=$(curl -fsSL https://developer.android.com/studio#command-line-tools-only \
                   | grep -oE 'commandlinetools-linux-[0-9]+_latest.zip' \
                   | head -n1)
        if [[ -z "$filename" ]]; then
            error "Failed to find commandlinetools-linux-*_latest.zip on developer.android.com"
            return 1
        fi
        local url="https://dl.google.com/android/repository/$filename"
        info "Downloading $filename…"
        curl -fSL --retry 3 --retry-delay 5 "$url" -o /tmp/cmdline-tools.zip



        info "Unpacking to $ANDROID_SDK_ROOT/cmdline-tools/latest…"
		tmpdir=$(mktemp -d)
        unzip -q /tmp/cmdline-tools.zip -d "$tmpdir"
        rm /tmp/cmdline-tools.zip

		mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        mv "$tmpdir/cmdline-tools/"* "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
        rm -rf "$tmpdir"

        success "Android cmdline-tools unpacked via ZIP fallback"
    else
        success "Android cmdline-tools already installed (sdkmanager present)"
    fi

    #
    # 6) Export environment variables for everyone else to pick up
    #
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    export ANDROID_SDK_ROOT
    export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
}

remove_android() {
    info "Removing Android Studio…"
    rm -rf "$HOME/AndroidStudio"
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
# CLI Parsing (supports -i/--install and -r/--remove)
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
  # -t|--template)
  #   shift
  #   if [[ $# -eq 0 ]]; then
  #     error "No framework specified for template"; exit 1
  #   fi
  #   framework="$1"
  #   if declare -F create_template_"$framework" &>/dev/null; then
  #     create_template_"$framework"
  #   else
  #     error "Unknown framework: $framework"; exit 1
  #   fi
  #   ;;
  *)
    print_help
    exit 1
    ;;
esac
