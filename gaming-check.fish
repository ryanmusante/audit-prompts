#!/usr/bin/env fish

# Gaming environment verification script for CachyOS + RADV + Proton

set -l green (set_color green)
set -l red (set_color red)
set -l yellow (set_color yellow)
set -l normal (set_color normal)

function check_pass
    echo "$green✓$normal $argv"
end

function check_fail
    echo "$red✗$normal $argv"
end

function check_warn
    echo "$yellow⚠$normal $argv"
end

function section
    echo ""
    echo "$yellow=== $argv ===$normal"
end

# ─────────────────────────────────────────────────────────────
section "Environment Variables"
# ─────────────────────────────────────────────────────────────

set -l expected_vars \
    AMD_VULKAN_ICD \
    RADV_PERFTEST \
    RADV_DEBUG \
    MESA_SHADER_CACHE_MAX_SIZE \
    PROTON_USE_NTSYNC \
    PROTON_NO_WM_DECORATION \
    PROTON_ENABLE_MEDIACONV \
    PROTON_ENABLE_WAYLAND

for var in $expected_vars
    set -l val (printenv $var)
    if test -n "$val"
        check_pass "$var=$val"
    else
        check_fail "$var not set"
    end
end

# ─────────────────────────────────────────────────────────────
section "Vulkan Driver"
# ─────────────────────────────────────────────────────────────

set -l driver (vulkaninfo 2>/dev/null | rg 'driverName' | head -1 | string trim)
set -l driver_info (vulkaninfo 2>/dev/null | rg 'driverInfo' | head -1 | string trim)

if string match -q '*radv*' "$driver"
    check_pass "$driver"
    check_pass "$driver_info"
else
    check_fail "Expected RADV, got: $driver"
end

# ─────────────────────────────────────────────────────────────
section "ntsync"
# ─────────────────────────────────────────────────────────────

if lsmod | rg -q '^ntsync'
    check_pass "ntsync module loaded"
else
    check_fail "ntsync module not loaded"
end

if test -c /dev/ntsync
    check_pass "/dev/ntsync device exists"
else
    check_fail "/dev/ntsync device missing"
end

# ─────────────────────────────────────────────────────────────
section "Shader Cache"
# ─────────────────────────────────────────────────────────────

set -l cache_dir ~/.cache/mesa_shader_cache
if test -d $cache_dir
    set -l cache_size (du -sh $cache_dir 2>/dev/null | cut -f1)
    set -l cache_files (find $cache_dir -type f 2>/dev/null | wc -l)
    check_pass "Cache size: $cache_size ($cache_files files)"
else
    check_warn "Shader cache directory doesn't exist yet"
end

set -l max_size (printenv MESA_SHADER_CACHE_MAX_SIZE)
if test -n "$max_size"
    check_pass "Cache limit: $max_size"
else
    check_warn "Cache limit: default (1GB)"
end

# ─────────────────────────────────────────────────────────────
section "GPU Info"
# ─────────────────────────────────────────────────────────────

set -l gpu_name (lspci | rg -i 'vga\|display\|3d' | head -1)
if test -n "$gpu_name"
    check_pass "$gpu_name"
end

# VRAM info (integrated GPU)
set -l vram_total (cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1)
set -l vram_used (cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1)
if test -n "$vram_total"
    set -l vram_total_gb (math "$vram_total / 1024 / 1024 / 1024")
    set -l vram_used_mb (math "$vram_used / 1024 / 1024")
    check_pass "VRAM: $vram_used_mb MB used / $vram_total_gb GB total"
end

# ─────────────────────────────────────────────────────────────
section "ReBAR / Smart Access Memory"
# ─────────────────────────────────────────────────────────────

# Check kernel messages (may need sudo)
set -l rebar_msg (sudo dmesg 2>/dev/null | rg -i 'rebar\|resizable bar' | tail -1)
if test -n "$rebar_msg"
    check_pass "$rebar_msg"
else
    # Strix Halo integrated - ReBAR not applicable
    check_warn "ReBAR not reported (expected for integrated GPU with unified memory)"
end

# ─────────────────────────────────────────────────────────────
section "Kernel"
# ─────────────────────────────────────────────────────────────

check_pass "Kernel: "(uname -r)

# Check for CachyOS-specific features
if test -f /sys/kernel/sched_ext/state
    set -l sched_state (cat /sys/kernel/sched_ext/state 2>/dev/null)
    check_pass "sched_ext: $sched_state"
else
    check_warn "sched_ext not available"
end

# ─────────────────────────────────────────────────────────────
section "Steam/Proton"
# ─────────────────────────────────────────────────────────────

if command -q steam
    check_pass "Steam installed: "(command -v steam)
else
    check_fail "Steam not found"
end

# Check for Proton versions
set -l proton_dir ~/.steam/steam/steamapps/common
if test -d $proton_dir
    set -l protons (ls -1 $proton_dir 2>/dev/null | rg -i '^proton')
    if test -n "$protons"
        for p in $protons
            check_pass "Proton: $p"
        end
    else
        check_warn "No Proton versions found in common folder"
    end
end

# ─────────────────────────────────────────────────────────────
section "Wayland Session"
# ─────────────────────────────────────────────────────────────

if test -n "$WAYLAND_DISPLAY"
    check_pass "Wayland session: $WAYLAND_DISPLAY"
else
    check_fail "Not running Wayland session"
end

if test -n "$XDG_CURRENT_DESKTOP"
    check_pass "Desktop: $XDG_CURRENT_DESKTOP"
end

# ─────────────────────────────────────────────────────────────
section "XWayland"
# ─────────────────────────────────────────────────────────────

if pgrep -x Xwayland >/dev/null
    check_pass "XWayland running (PID: "(pgrep -x Xwayland)")"
else
    check_warn "XWayland not running"
end

set -l xwayland_clients (xlsclients 2>/dev/null | wc -l)
check_pass "XWayland clients: $xwayland_clients"

# ─────────────────────────────────────────────────────────────
section "gstreamer (for PROTON_ENABLE_MEDIACONV)"
# ─────────────────────────────────────────────────────────────

set -l gst_packages \
    gst-plugins-good \
    gst-plugins-bad \
    gst-plugins-ugly \
    gst-libav

for pkg in $gst_packages
    if pacman -Q $pkg >/dev/null 2>&1
        check_pass "$pkg installed"
    else
        check_fail "$pkg missing"
    end
end

# ─────────────────────────────────────────────────────────────
section "RADV Feature Flags"
# ─────────────────────────────────────────────────────────────

echo "Available RADV_PERFTEST options:"
RADV_PERFTEST=help vulkaninfo 2>&1 | rg 'RADV_PERFTEST' -A20 | head -20

echo ""
echo "Available RADV_DEBUG options:"
RADV_DEBUG=help vulkaninfo 2>&1 | rg 'RADV_DEBUG' -A30 | head -30

# ─────────────────────────────────────────────────────────────
section "Summary"
# ─────────────────────────────────────────────────────────────

echo ""
echo "Run a game and verify native Wayland with:"
echo "  xlsclients | rg -i 'wine|proton'"
echo "  (empty output = native Wayland working)"
echo ""
echo "If game has issues, test with:"
echo "  PROTON_ENABLE_WAYLAND=0 %command%"
