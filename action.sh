#!/system/bin/sh
# action.sh — OneUI Emoji Pack (standalone action-button script)
MODPATH="${0%/*}"

set +o standalone 2>/dev/null
unset ASH_STANDALONE 2>/dev/null

# ── Configuration ──────────────────────────────────────────────────────────────
LOGFILE="$MODPATH/action.log"
EMOJI_FONT_SRC="$MODPATH/system/fonts/NotoColorEmoji.ttf"
FACEBOOK_APPS="com.facebook.orca com.facebook.katana com.facebook.lite"
GMS_FONT_PROVIDER="com.google.android.gms/com.google.android.gms.fonts.provider.FontsProvider"
GMS_FONT_UPDATER="com.google.android.gms/com.google.android.gms.fonts.update.UpdateSchedulerService"
DATA_FONTS_DIR="/data/fonts"

# ── Logging — delete existing log and start fresh every run ───────────────────
rm -f "$LOGFILE"

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOGFILE"
    case "$1" in
        INFO:*|ERROR:*|WARN:*) printf '[*] %s\n' "${1#*: }" ;;
        *) printf '[*] %s\n' "$1" ;;
    esac
}

# ── Functions ──────────────────────────────────────────────────────────────────

replace_emoji_fonts() {
    log "INFO: Starting emoji font replacement..."

    if [ ! -f "$EMOJI_FONT_SRC" ]; then
        log "ERROR: Source emoji font not found at $EMOJI_FONT_SRC. Skipping replacement."
        return 1
    fi

    # Dynamically target all active user profiles without redundant symlink parsing
    for userpath in /data/user/*/; do
        [ -d "$userpath" ] || continue
        local uid="${userpath%/}"
        uid="${uid##*/}"

        find "/data/user/$uid" -iname "*emoji*.ttf" 2>/dev/null | while IFS= read -r font; do
            if [ ! -w "$font" ]; then
                log "ERROR: Not writable: $font"
                continue
            fi
            if cp "$EMOJI_FONT_SRC" "$font" && chmod 644 "$font"; then
                log "INFO: Replaced: $font"
            else
                log "ERROR: Failed to replace: $font"
            fi
        done
    done

    log "INFO: Emoji font replacement completed."
}

lock_messenger_emoji() {
    log "INFO: Locking Messenger/Facebook emoji fonts..."

    for userpath in /data/user/*/; do
        [ -d "$userpath" ] || continue
        local uid="${userpath%/}"
        uid="${uid##*/}"

        for pkg in $FACEBOOK_APPS; do
            local base_dir="/data/user/$uid/$pkg"
            [ -d "$base_dir" ] || continue

            local target="$base_dir/app_ras_blobs/FacebookEmoji.ttf"
            
            # CRITICAL FIX: Unlock file if it was previously made immutable
            if [ -f "$target" ]; then
                chattr -i "$target" 2>/dev/null
            fi

            mkdir -p "${target%/*}"

            if cp -f "$EMOJI_FONT_SRC" "$target" && chmod 444 "$target"; then
                log "INFO: Locked emoji font for $pkg (User $uid)"
                chattr +i "$target" 2>/dev/null \
                    && log "INFO: Immutable flag set: $target" \
                    || log "INFO: chattr +i not supported, using read-only fallback: $target"
            else
                log "ERROR: Failed to lock emoji font for $pkg (User $uid)"
            fi
        done
    done

    log "INFO: Messenger/Facebook emoji lock completed."
}

clean_messenger_font_cache() {
    log "INFO: Cleaning Messenger font caches..."

    for userpath in /data/user/*/; do
        [ -d "$userpath" ] || continue
        local uid="${userpath%/}"
        uid="${uid##*/}"
        
        local dir="/data/user/$uid/com.facebook.orca/files/fonts"
        if [ -d "$dir" ]; then
            # FIX: Temporarily restore permissions to ensure clean access
            chmod 700 "$dir" 2>/dev/null
            rm -rf "${dir:?}/"* \
                && log "INFO: Cleaned cache: $dir" \
                || log "ERROR: Failed to clean: $dir"
        fi
        
        mkdir -p "$dir" && chmod 000 "$dir" \
            && log "INFO: Locked download dir: $dir" \
            || log "ERROR: Failed to lock: $dir"
    done

    log "INFO: Messenger font cache cleanup completed."
}

force_stop_facebook_apps() {
    log "INFO: Force-stopping Facebook apps..."
    for app in $FACEBOOK_APPS; do
        am force-stop "$app" 2>/dev/null \
            && log "INFO: Force-stopped: $app" \
            || log "ERROR: Failed to stop: $app"
    done
}

disable_gms_font_services() {
    log "INFO: Disabling GMS font services..."

    for userpath in /data/user/*/; do
        [ -d "$userpath" ] || continue
        local uid="${userpath%/}"
        uid="${uid##*/}"
        
        pm disable --user "$uid" "$GMS_FONT_PROVIDER" >/dev/null 2>&1 \
            && log "INFO: Disabled font provider for user $uid" \
            || log "INFO: Font provider already disabled or not found for user $uid"
            
        pm disable --user "$uid" "$GMS_FONT_UPDATER" >/dev/null 2>&1 \
            && log "INFO: Disabled font updater for user $uid" \
            || log "INFO: Font updater already disabled or not found for user $uid"
    done

    log "INFO: GMS font services disabled."
}

cleanup_gms_fonts() {
    log "INFO: Cleaning up GMS font directories..."

    if [ -d "$DATA_FONTS_DIR" ]; then
        rm -rf "$DATA_FONTS_DIR" \
            && log "INFO: Removed $DATA_FONTS_DIR" \
            || log "ERROR: Failed to remove $DATA_FONTS_DIR"
    fi

    # OPTIMIZATION: Avoid global find scan across all of /data
    for userpath in /data/user/*/; do
        [ -d "$userpath" ] || continue
        local uid="${userpath%/}"
        uid="${uid##*/}"
        
        local gms_dir="/data/user/$uid/com.google.android.gms/files/fonts"
        if [ -d "$gms_dir" ]; then
            rm -rf "$gms_dir" \
                && log "INFO: Removed GMS font dir: $gms_dir" \
                || log "ERROR: Failed to remove: $gms_dir"
        fi
    done

    log "INFO: GMS font cleanup completed."
}

# ── Main ───────────────────────────────────────────────────────────────────────
log "================================================"
log "OneUI Emoji Pack — action.sh"
log "Brand:   $(getprop ro.product.brand)"
log "Device:  $(getprop ro.product.model)"
log "Android: $(getprop ro.build.version.release)"
log "================================================"

replace_emoji_fonts
lock_messenger_emoji
clean_messenger_font_cache
force_stop_facebook_apps
sleep 2
disable_gms_font_services
cleanup_gms_fonts

log "INFO: Action completed successfully."
log "================================================"

printf '\nOperation completed successfully!\n\n'
exit 0
