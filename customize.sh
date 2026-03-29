##########################################################################################
# Installer Script
##########################################################################################
#!/system/bin/sh

# Script Details
AUTOMOUNT=true
SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

ui_print "*******************************"
ui_print "      OneUI 7 Emoji Pack     "
ui_print "*******************************"

# Paths
FONT_DIR="$MODPATH/system/fonts"
FONT_EMOJI="NotoColorEmoji.ttf"
SYSTEM_FONT_FILE="/system/fonts/NotoColorEmoji.ttf"

# Function to check if a package is installed
package_installed() {
    pm path "$1" >/dev/null 2>&1
}

# Function to set user-friendly app name
display_name() {
    case "$1" in
        "com.facebook.orca") echo "Messenger" ;;
        "com.facebook.katana") echo "Facebook" ;;
        "com.facebook.lite") echo "Facebook Lite" ;;
        "com.google.android.inputmethod.latin") echo "Gboard" ;;
        *) echo "$1" ;; 
    esac
}

# Function to mount a font file
mount_font() {
    local source="$1"
    local target="$2"
    local target_dir="${target%/*}"

    if [ ! -f "$source" ]; then
        ui_print "- Source file $source does not exist"
        return 1
    fi

    # Ensure directory exists
    [ ! -d "$target_dir" ] && mkdir -p "$target_dir"

    # Ensure target file exists before binding
    [ ! -f "$target" ] && touch "$target"

    if mount -o bind "$source" "$target"; then
        chmod 644 "$target"
        return 0
    else
        ui_print "- Failed to mount $source to $target"
        return 1
    fi
}

# Function to replace emojis for a specific app
replace_emojis() {
    local app_name="$1"
    local app_dir="$2"
    local emoji_dir="$3"
    local target_filename="$4"
    local app_display_name=$(display_name "$app_name")

    if package_installed "$app_name"; then
        ui_print "- Detected: $app_display_name"
        mount_font "$FONT_DIR/$FONT_EMOJI" "$app_dir/$emoji_dir/$target_filename"
        ui_print "- Emojis mounted: $app_display_name"
    else
        ui_print "- Not installed: $app_display_name"
    fi
}

# Function to clear app cache
clear_cache() {
    local app_name="$1"
    local app_display_name=$(display_name "$app_name")

    # Check if app exists
    if ! package_installed "$app_name"; then
        ui_print "- Skipping: $app_display_name (not installed)"
        return 0
    fi

    ui_print "- Cleaning cache: $app_display_name"

    # Clean standard cache directories
    for dir in cache code_cache app_webview files/GCache; do
        local target_dir="/data/data/${app_name}/${dir}"
        [ -d "$target_dir" ] && rm -rf "$target_dir"
    done

    # Force-stop
    am force-stop "$app_name" >/dev/null 2>&1
    ui_print "- Cache cleared: $app_display_name"
}

# Extract module files
ui_print "- Extracting module files..."
unzip -qo "$ZIPFILE" 'system/*' -d "$MODPATH" || abort "! Failed to extract module files"

# Replace system emoji fonts
ui_print "- Installing OneUI Emoji Pack"
VARIANTS="SamsungColorEmoji.ttf LGNotoColorEmoji.ttf HTC_ColorEmoji.ttf AndroidEmoji-htc.ttf ColorUniEmoji.ttf DcmColorEmoji.ttf CombinedColorEmoji.ttf NotoColorEmojiLegacy.ttf"

for font in $VARIANTS; do
    if [ -f "/system/fonts/$font" ]; then
        if cp "$FONT_DIR/$FONT_EMOJI" "$FONT_DIR/$font"; then
            ui_print "- Replaced $font"
        else
            ui_print "- Failed to replace $font"
        fi
    fi
done

# Mount system emoji font
if [ -f "$FONT_DIR/$FONT_EMOJI" ]; then
    if mount_font "$FONT_DIR/$FONT_EMOJI" "$SYSTEM_FONT_FILE"; then
        ui_print "- System font mounted successfully"
    else
        ui_print "- Failed to mount system font"
    fi
else
    ui_print "- Source emoji font not found. Skipping system font mount."
fi

# Replace app emojis and clear cache
replace_emojis "com.facebook.orca" "/data/data/com.facebook.orca" "app_ras_blobs" "FacebookEmoji.ttf"
clear_cache "com.facebook.orca"

replace_emojis "com.facebook.katana" "/data/data/com.facebook.katana" "app_ras_blobs" "FacebookEmoji.ttf"
clear_cache "com.facebook.katana"

replace_emojis "com.facebook.lite" "/data/data/com.facebook.lite" "files" "emoji_font.ttf"
clear_cache "com.facebook.lite"

clear_cache "com.google.android.inputmethod.latin"

# Remove /data/fonts directory for Android 12+ instead of replacing the files (removing the need to run the troubleshooting step, thanks @reddxae)
if [ -d "/data/fonts" ]; then
    rm -rf "/data/fonts"
    ui_print "- Removed existing /data/fonts directory"
fi

# Handle fonts.xml symlinks
FONTS_XML="/system/etc/fonts.xml"
if [ -f "$FONTS_XML" ]; then
    FONTFILES=$(sed -ne '/<family lang="und-Zsye".*>/,/<\/family>/ {s/.*<font weight="400" style="normal">\(.*\)<\/font>.*/\1/p;}' "$FONTS_XML")
    for font in $FONTFILES; do
        [ ! -f "$MODPATH/system/fonts/$font" ] && ln -s "/system/fonts/$FONT_EMOJI" "$MODPATH/system/fonts/$font"
        ui_print "- Symlinked $font to $FONT_EMOJI"
    else
        ui_print "- No emoji font entries found in fonts.xml"
    done
else
    ui_print "- fonts.xml not found. Skipping symlink creation."
fi

# Set permissions
ui_print "- Setting permissions..."
if set_perm_recursive "$MODPATH" 0 0 0755 0644; then
    ui_print "- Permissions set successfully"
else
    ui_print "- Failed to set permissions"
fi
ui_print "- Done"
ui_print "- OneUI Emojis installed successfully!"
ui_print "- Reboot device to apply changes."

# OverlayFS Support based on https://github.com/HuskyDG/magic_overlayfs 
OVERLAY_IMAGE_EXTRA=0
OVERLAY_IMAGE_SHRINK=true

# Only use OverlayFS if Magisk_OverlayFS is installed
if [ -f "/data/adb/modules/magisk_overlayfs/util_functions.sh" ]; then
    if /data/adb/modules/magisk_overlayfs/overlayfs_system --test; then
        ui_print "- Add support for overlayfs"
        . /data/adb/modules/magisk_overlayfs/util_functions.sh
        support_overlayfs && rm -rf "$MODPATH"/system
    fi
fi
