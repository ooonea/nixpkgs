# Electron rewrites bundled plugin manifests, so they need a writable copy.
{
  flock,
  writeShellApplication,
}:

writeShellApplication {
  name = "chatgpt-launcher";

  runtimeInputs = [ flock ];

  text = ''
    : "''${CHATGPT_EXECUTABLE:?}"
    : "''${CHATGPT_RESOURCES_SOURCE:?}"
    : "''${CHATGPT_RESOURCES_CACHE_LABEL:?}"

    cacheHome="''${XDG_CACHE_HOME:-''${HOME:?XDG_CACHE_HOME and HOME are unset}/.cache}"
    cacheRoot="$cacheHome/chatgpt/bundled-plugins-v2"
    resourcesSourceHash=$(printf '%s' "$CHATGPT_RESOURCES_SOURCE" | sha256sum)
    resourcesSourceHash="''${resourcesSourceHash%% *}"
    cacheKey="$CHATGPT_RESOURCES_CACHE_LABEL-$resourcesSourceHash"
    resourcesPath="$cacheRoot/$cacheKey"

    mkdir -p "$cacheRoot"
    exec {initLockFd}> "$cacheRoot.lock"
    flock --exclusive "$initLockFd"

    # tmpfiles may remove the directory before its lock is acquired.
    while true; do
      mkdir -p "$resourcesPath"
      if exec {resourcesLockFd}< "$resourcesPath"; then
        flock --shared "$resourcesLockFd"
        [[ "$resourcesPath" -ef "/proc/self/fd/$resourcesLockFd" ]] && break
        exec {resourcesLockFd}>&-
      else
        [[ ! -d "$resourcesPath" ]] || exit 1
      fi
    done

    requiredResourcePaths=()
    for requiredResourceName in codex codex-code-mode-host cua_node native rg; do
      requiredResourcePath="$CHATGPT_RESOURCES_SOURCE/$requiredResourceName"
      if [[ ! -e "$requiredResourcePath" ]]; then
        echo "Missing ChatGPT bundled-plugin resource: $requiredResourcePath" >&2
        exit 1
      fi
      requiredResourcePaths+=("$requiredResourcePath")
    done

    if [[ -d "$CHATGPT_RESOURCES_SOURCE/tectonic" ]]; then
      requiredResourcePaths+=("$CHATGPT_RESOURCES_SOURCE/tectonic")
    fi

    if [[ ! -f "$resourcesPath/.complete" ]]; then
      ln -sfn -t "$resourcesPath" "''${requiredResourcePaths[@]}"
      mkdir -p "$resourcesPath/plugins"
      chmod -R u+w "$resourcesPath/plugins"
      cp -RT --preserve=mode "$CHATGPT_RESOURCES_SOURCE/plugins" "$resourcesPath/plugins"
      chmod -R u+w "$resourcesPath/plugins"
      sync --file-system "$resourcesPath"
      touch "$resourcesPath/.complete"
      sync --file-system "$resourcesPath"
    fi
    exec {initLockFd}>&-

    export CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH="$resourcesPath"

    waylandFlags=()
    if [[ -n "''${NIXOS_OZONE_WL:-}" && -n "''${WAYLAND_DISPLAY:-}" ]]; then
      waylandFlags=(
        --ozone-platform=wayland
        --enable-features=WaylandWindowDecorations
        --enable-wayland-ime=true
      )
    fi

    exec "$CHATGPT_EXECUTABLE" "''${waylandFlags[@]}" "$@"
  '';
}
