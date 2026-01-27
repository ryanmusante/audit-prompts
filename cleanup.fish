#!/usr/bin/env fish

# System and Steam cleanup script for CachyOS
# Safe to run — only deletes caches and temporary files

set -l green (set_color green)
set -l red (set_color red)
set -l yellow (set_color yellow)
set -l normal (set_color normal)

function section
    echo ""
    echo "$yellow=== $argv ===$normal"
end

function clean_dir
    set -l dir $argv[1]
    set -l desc $argv[2]
    
    if test -d "$dir"
        set -l size (du -sh "$dir" 2>/dev/null | cut -f1)
        rm -rf "$dir"/*
        echo "$green✓$normal $desc: cleared $size"
    else
        echo "$yellow⚠$normal $desc: not found"
    end
end

function clean_dir_create
    # Clean and recreate directory
    set -l dir $argv[1]
    set -l desc $argv[2]
    
    if test -d "$dir"
        set -l size (du -sh "$dir" 2>/dev/null | cut -f1)
        rm -rf "$dir"
        mkdir -p "$dir"
        echo "$green✓$normal $desc: cleared $size"
    else
        echo "$yellow⚠$normal $desc: not found"
    end
end

# ─────────────────────────────────────────────────────────────
section "Detecting Steam Installation"
# ─────────────────────────────────────────────────────────────

# Find Steam root directory
set -l steam_root ""
set -l possible_paths \
    ~/.local/share/Steam \
    ~/.steam/steam \
    ~/.var/app/com.valvesoftware.Steam/.local/share/Steam

for path in $possible_paths
    if test -d "$path/steamapps"
        set steam_root $path
        echo "$green✓$normal Found Steam at: $steam_root"
        break
    end
end

if test -z "$steam_root"
    echo "$red✗$normal Steam installation not found"
else
    # ─────────────────────────────────────────────────────────────
    section "Steam Cleanup"
    # ─────────────────────────────────────────────────────────────
    
    # Shader cache
    if test -d "$steam_root/steamapps/shadercache"
        clean_dir "$steam_root/steamapps/shadercache" "Shader cache"
    end
    
    # Download temp files
    clean_dir "$steam_root/steamapps/downloading" "Download temp"
    clean_dir "$steam_root/steamapps/temp" "Steamapps temp"
    
    # Web browser caches
    clean_dir "$steam_root/config/htmlcache" "HTML cache"
    clean_dir "$steam_root/config/cef_cache" "CEF cache"
    clean_dir "$steam_root/config/chromedump" "Chrome dump"
    
    # Logs
    clean_dir "$steam_root/logs" "Steam logs"
    
    # Dumps
    clean_dir "$steam_root/dumps" "Crash dumps"
    
    # Depot cache
    clean_dir "$steam_root/depotcache" "Depot cache"
    
    # ─────────────────────────────────────────────────────────────
    section "Proton/Compatdata Info"
    # ─────────────────────────────────────────────────────────────
    
    set -l compatdata "$steam_root/steamapps/compatdata"
    if test -d "$compatdata"
        set -l total_size (du -sh "$compatdata" 2>/dev/null | cut -f1)
        set -l prefix_count (ls -1 "$compatdata" 2>/dev/null | wc -l)
        echo "Total compatdata: $total_size ($prefix_count prefixes)"
        echo ""
        echo "Largest prefixes:"
        du -sh "$compatdata"/* 2>/dev/null | sort -hr | head -5
        echo ""
        echo "$yellow→$normal To remove orphaned prefixes, identify AppIDs at steamdb.info/app/APPID"
        echo "$yellow→$normal Then: rm -rf $compatdata/APPID"
    else
        echo "$yellow⚠$normal No compatdata directory found"
    end
end

# ─────────────────────────────────────────────────────────────
section "Mesa Shader Cache"
# ─────────────────────────────────────────────────────────────

clean_dir_create ~/.cache/mesa_shader_cache "Mesa shader cache"

# ─────────────────────────────────────────────────────────────
section "Pacman Cache"
# ─────────────────────────────────────────────────────────────

if command -q paccache
    set -l cache_size (du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    echo "Current cache size: $cache_size"
    
    # Keep 2 versions
    sudo paccache -rk2
    
    # Remove uninstalled
    sudo paccache -ruk0
    
    set -l new_size (du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    echo "$green✓$normal Pacman cache: $cache_size → $new_size"
else
    echo "$yellow⚠$normal paccache not found (install pacman-contrib)"
end

# ─────────────────────────────────────────────────────────────
section "AUR Cache"
# ─────────────────────────────────────────────────────────────

# Paru
if test -d ~/.cache/paru/clone
    clean_dir ~/.cache/paru/clone "Paru build cache"
end

# Yay
if test -d ~/.cache/yay
    clean_dir ~/.cache/yay "Yay build cache"
end

# ─────────────────────────────────────────────────────────────
section "Journal Logs"
# ─────────────────────────────────────────────────────────────

set -l journal_size (journalctl --disk-usage 2>/dev/null | rg -o '[0-9.]+[GMK]' | head -1)
echo "Current journal size: $journal_size"
sudo journalctl --vacuum-time=7d
echo "$green✓$normal Journal vacuumed to 7 days"

# ─────────────────────────────────────────────────────────────
section "Coredumps"
# ─────────────────────────────────────────────────────────────

if test -d /var/lib/systemd/coredump
    set -l core_size (du -sh /var/lib/systemd/coredump 2>/dev/null | cut -f1)
    if test "$core_size" != "0"
        sudo rm -rf /var/lib/systemd/coredump/*
        echo "$green✓$normal Coredumps cleared: $core_size"
    else
        echo "$yellow⚠$normal No coredumps"
    end
else
    echo "$yellow⚠$normal Coredump directory not found"
end

# ─────────────────────────────────────────────────────────────
section "User Caches"
# ─────────────────────────────────────────────────────────────

clean_dir ~/.cache/thumbnails "Thumbnails"
clean_dir ~/.local/share/Trash "Trash"

# ─────────────────────────────────────────────────────────────
section "Orphaned Packages"
# ─────────────────────────────────────────────────────────────

set -l orphans (pacman -Qtdq 2>/dev/null)
if test -n "$orphans"
    echo "Found orphaned packages:"
    echo $orphans | tr ' ' '\n'
    echo ""
    echo "$yellow→$normal To remove: sudo pacman -Rns (pacman -Qtdq)"
else
    echo "$green✓$normal No orphaned packages"
end

# ─────────────────────────────────────────────────────────────
section "Disk Space Summary"
# ─────────────────────────────────────────────────────────────

echo ""
df -h / | tail -1 | read -l fs size used avail pct mount
echo "Root filesystem: $used used / $size total ($avail available)"
echo ""

# Large directories
if command -q dust
    echo "Largest directories in ~:"
    dust -d 1 ~ 2>/dev/null | tail -10
else
    echo "Largest directories in ~:"
    du -sh ~/* 2>/dev/null | sort -hr | head -10
end

echo ""
echo "$green=== Cleanup Complete ===$normal"
