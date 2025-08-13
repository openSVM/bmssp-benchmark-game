#!/usr/bin/env bash
set -euo pipefail

# BMSSP benchmark dependencies installer (Linux/macOS)
# - Detects missing toolchains and installs them via the platform package manager.
# - Installs: Rust (rustup), Python3 + pip packages, C/C++ toolchain, Crystal+shards, Nim,
#   Kotlin (JDK + kotlinc), Elixir, Erlang.
# - Zig was removed from this repository; we no longer install it.
# - Safe to re-run; use --check-only to only report.

YES=0
CHECK_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) YES=1; shift;;
    --check-only) CHECK_ONLY=1; shift;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
confirm() { [[ "$YES" = 1 ]] && return 0; read -r -p "$1 [y/N] " ans; [[ "$ans" =~ ^([yY][eE][sS]|[yY])$ ]]; }
ensure_path_dir() {
  case ":$PATH:" in *":$1:"*) :;; *) export PATH="$1:$PATH";; esac
  # Persist in GitHub Actions across steps
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$1" >> "$GITHUB_PATH" || true
  fi
}

OS=$(uname -s)
DISTRO_ID=""
if [[ "$OS" != "Darwin" ]]; then
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
  fi
fi
PKG=${PKG:-"sudo apt-get install -y"}
case "$DISTRO_ID" in
  ubuntu|debian|linuxmint|pop|pop-os) PKG="sudo apt-get install -y" ;;
  fedora) PKG="sudo dnf install -y" ;;
  centos|rhel) PKG="sudo yum install -y" ;;
  arch|manjaro) PKG="sudo pacman -Sy --noconfirm" ;;
  opensuse*|sles) PKG="sudo zypper install -y" ;;
esac

echo "==> Ensuring prerequisites (curl/xz/ca-certificates)"
if [[ "$CHECK_ONLY" = 0 ]]; then
  if [[ "$OS" == "Darwin" ]]; then
    have brew && brew install curl xz || true
  else
    case "$DISTRO_ID" in
      ubuntu|debian|linuxmint) sudo apt-get update && sudo apt-get install -y curl xz-utils ca-certificates || true ;;
      fedora) sudo dnf install -y curl xz ca-certificates || true ;;
      centos|rhel) sudo yum install -y curl xz ca-certificates || true ;;
      arch|manjaro) sudo pacman -Sy --noconfirm curl xz ca-certificates || true ;;
      opensuse*|sles) sudo zypper install -y curl xz ca-certificates || true ;;
      *) eval "$PKG curl xz" || true ;;
    esac
  fi
fi

echo "==> Checking Rust toolchain"
if ! have cargo || ! have rustc; then
  echo "[miss] Rust not found"
  if [[ "$CHECK_ONLY" = 0 ]]; then
    if [[ "$YES" = 1 ]] || confirm "Install Rust via rustup?"; then
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      # shellcheck source=/dev/null
      source "$HOME/.cargo/env"
    fi
  fi
else
  echo "[ok] Rust: cargo/rustc present"
fi

echo "==> Checking Python3 and pip"
if ! have python3; then
  echo "[miss] python3"; [[ "$CHECK_ONLY" = 0 ]] && eval "$PKG python3 python3-pip || true"
else
  echo "[ok] python3"
fi
if have python3; then
  if ! python3 -m pip --version >/dev/null 2>&1; then
    echo "[miss] pip for python3"; [[ "$CHECK_ONLY" = 0 ]] && eval "$PKG python3-pip || true"
  fi
  if [[ "$CHECK_ONLY" = 0 ]]; then
    if [[ -f "bench/requirements.txt" ]]; then
      python3 -m pip install --user -r bench/requirements.txt || python3 -m pip install --user --break-system-packages -r bench/requirements.txt || true
    else
      python3 -m pip install --user pyyaml matplotlib jsonschema || python3 -m pip install --user --break-system-packages pyyaml matplotlib jsonschema || true
    fi
  fi
fi

echo "==> Checking C/C++ toolchain (gcc/clang, make)"
install_c_toolchain() {
  if [[ "$OS" == "Darwin" ]]; then
    echo "[info] Installing Xcode Command Line Tools (a GUI prompt may appear)"
    xcode-select --install || true
    return
  fi
  case "$DISTRO_ID" in
    ubuntu|debian|linuxmint) sudo apt-get update && sudo apt-get install -y build-essential || true ;;
    fedora) sudo dnf groupinstall -y 'Development Tools' || true; sudo dnf install -y gcc gcc-c++ make || true ;;
    centos|rhel) sudo yum groupinstall -y 'Development Tools' || true; sudo yum install -y gcc gcc-c++ make || true ;;
    arch|manjaro) sudo pacman -Sy --noconfirm base-devel || true ;;
    opensuse*|sles) sudo zypper install -y -t pattern devel_C_C++ || sudo zypper install -y gcc gcc-c++ make || true ;;
    *) eval "$PKG gcc g++ make" || true ;;
  esac
}
if ! have cc && ! have gcc && ! have clang; then echo "[miss] C compiler"; [[ "$CHECK_ONLY" = 0 ]] && install_c_toolchain; else echo "[ok] C compiler"; fi
if ! have make; then echo "[miss] make"; [[ "$CHECK_ONLY" = 0 ]] && install_c_toolchain; else echo "[ok] make"; fi

echo "==> Checking Crystal + shards"
install_crystal() {
  if [[ "$OS" == "Darwin" ]]; then have brew && brew install crystal shards || true; return; fi
  case "$DISTRO_ID" in
    ubuntu|debian|linuxmint)
      # Add official Crystal apt repo to get recent versions
      sudo apt-get update || true
      if ! apt-cache policy crystal 2>/dev/null | grep -q crystal; then
        curl -fsSL https://dist.crystal-lang.org/apt/setup.sh | sudo bash || true
      fi
      sudo apt-get update || true
      sudo apt-get install -y crystal shards || true
      ;;
    fedora) sudo dnf install -y crystal shards || true ;;
    arch|manjaro) sudo pacman -Sy --noconfirm crystal shards || true ;;
    opensuse*|sles) sudo zypper install -y crystal shards || true ;;
    *) eval "$PKG crystal shards" || true ;;
  esac
}
if ! have crystal; then echo "[miss] crystal"; [[ "$CHECK_ONLY" = 0 ]] && install_crystal; else echo "[ok] crystal"; fi
if have crystal && ! have shards; then echo "[miss] shards"; [[ "$CHECK_ONLY" = 0 ]] && install_crystal; else have shards && echo "[ok] shards"; fi

echo "==> Checking Kotlin (JDK + kotlinc)"
if ! have java; then echo "[miss] java (JDK)"; [[ "$CHECK_ONLY" = 0 ]] && eval "$PKG default-jdk || true"; else echo "[ok] java"; fi
if ! have kotlinc; then
  # If installed via SDKMAN but not on PATH in this shell, add it temporarily
  if [[ -x "$HOME/.sdkman/candidates/kotlin/current/bin/kotlinc" ]]; then
    ensure_path_dir "$HOME/.sdkman/candidates/kotlin/current/bin"
  fi
fi
if ! have kotlinc; then
  echo "[miss] kotlinc"
  if [[ "$CHECK_ONLY" = 0 ]]; then
    # Try SDKMAN fallback for Kotlin
    if [[ "$YES" = 1 ]] || confirm "Install Kotlin via SDKMAN (user-local)?"; then
      curl -s "https://get.sdkman.io" | bash || true
      # shellcheck source=/dev/null
      set +u; source "$HOME/.sdkman/bin/sdkman-init.sh" || true; set -u
      sdk install kotlin || true
      sdk current || true
      if [[ -x "$HOME/.sdkman/candidates/kotlin/current/bin/kotlinc" ]]; then
        ensure_path_dir "$HOME/.sdkman/candidates/kotlin/current/bin"
      fi
    fi
  fi
else
  echo "[ok] kotlinc"
fi

echo "==> Checking Elixir/Erlang"
install_elixir_erlang() {
  if [[ "$OS" == "Darwin" ]]; then have brew && brew install elixir erlang || true; return; fi
  case "$DISTRO_ID" in
    ubuntu|debian|linuxmint) sudo apt-get update && sudo apt-get install -y elixir erlang || true ;;
    fedora) sudo dnf install -y elixir erlang || true ;;
    arch|manjaro) sudo pacman -Sy --noconfirm elixir erlang || true ;;
    opensuse*|sles) sudo zypper install -y elixir erlang || true ;;
    *) eval "$PKG elixir erlang" || true ;;
  esac
}
if ! have elixir; then echo "[miss] Elixir"; [[ "$CHECK_ONLY" = 0 ]] && install_elixir_erlang; else echo "[ok] Elixir"; fi
if ! have erlc; then echo "[miss] Erlang"; [[ "$CHECK_ONLY" = 0 ]] && install_elixir_erlang; else echo "[ok] Erlang"; fi

echo "==> Checking Nim"
install_nim() {
  if [[ "$OS" == "Darwin" ]]; then have brew && brew install nim || true; else eval "$PKG nim || true"; fi
  if have nim; then return; fi
  echo "[info] Installing Nim via choosenim (user-local)"
  curl -fsSL https://nim-lang.org/choosenim/init.sh | bash -s -- -y || true
  if [[ -x "$HOME/.nimble/bin/nim" ]]; then
    ensure_path_dir "$HOME/.nimble/bin"
    echo "[ok] nim installed to ~/.nimble/bin"
  fi
}
if have nim; then echo "[ok] Nim"; else echo "[miss] Nim"; [[ "$CHECK_ONLY" = 0 ]] && install_nim; fi

echo "\n==> Summary"
if have cargo && have rustc; then echo "Rust:   present"; else echo "Rust:   missing"; fi
if have python3; then echo "Python: present"; else echo "Python: missing"; fi
if have cc || have gcc || have clang; then echo "C/C++:  present"; else echo "C/C++:  missing"; fi
if have make; then echo "make:   present"; else echo "make:   missing"; fi
if have crystal; then echo "Crystal:present"; else echo "Crystal:missing"; fi
if have kotlinc && have java; then echo "Kotlin: present"; else echo "Kotlin: missing"; fi
if have elixir; then echo "Elixir: present"; else echo "Elixir: missing"; fi
if have erlc; then echo "Erlang: present"; else echo "Erlang: missing"; fi
if have nim; then echo "Nim:    present"; else echo "Nim:    missing"; fi

echo "\nNext: run the benchmarks"
echo "  python3 bench/runner.py --release --out results"
