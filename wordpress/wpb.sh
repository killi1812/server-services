#!/bin/bash

# --- Configuration ---
# Directory where your WordPress instances live (e.g., ./data/my-site, ./data/another-site)
DATA_DIR="./data"
# Directory where backups will be stored
BACKUP_DIR="./backup"
# ---------------------

# Ensure the backup directory exists
mkdir -p "$BACKUP_DIR"

# Get the main action (backup, restore) and the instance name
ACTION="$1"
INSTANCE_NAME="$2"

# --- Help/Usage Function ---
usage() {
    echo "Usage: $0 <action> [options]"
    echo ""
    echo "Actions:"
    echo "  backup <instance_name>             Back up a WordPress instance"
    echo "  restore <instance_name> [path_to_backup] Restore a WordPress instance"
    echo ""
    echo "Examples:"
    echo "  ./wpb.sh wpb my-site"
    echo "  sudo ./wpb.sh restore my-site                 (restores the latest wpb)"
    echo "  sudo ./wpb.sh restore my-site wpb/my-site-20251113-125400.tar.gz"
}

# --- Main Logic ---
case "$ACTION" in
    backup)
        if [ -z "$INSTANCE_NAME" ]; then
            echo "Error: Missing <instance_name> for backup."
            usage
            exit 1
        fi

        SOURCE_DIR="$DATA_DIR/$INSTANCE_NAME"
        
        if [ ! -d "$SOURCE_DIR" ]; then
            echo "Error: Source directory not found: $SOURCE_DIR"
            exit 1
        fi

        # Create a timestamped backup file
        DATE_STAMP=$(date +"%Y%m%d-%H%M%S")
        BACKUP_FILE="$BACKUP_DIR/$INSTANCE_NAME-$DATE_STAMP.tar.gz"

        echo "Backing up $SOURCE_DIR to $BACKUP_FILE..."
        
        # -c: create archive
        # -z: compress with gzip (.gz)
        # -f: use archive file
        # -C: Change to directory $SOURCE_DIR before archiving.
        #     This prevents the 'data/my-site' path from being stored in the tarball.
        tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .
        
        echo "Backup complete!"
        ;;

    restore)
	if [ "$EUID" -ne 0 ]; then
            echo "Error: Restore action must be run as root (use sudo)."
            echo "Example: sudo $0 restore $INSTANCE_NAME $3"
            exit 1
        fi

        RESTORE_FILE="$3" # Optional: path to a specific backup
        
        if [ -z "$INSTANCE_NAME" ]; then
            echo "Error: Missing <instance_name> for restore."
            usage
            exit 1
        fi

        DEST_DIR="$DATA_DIR/$INSTANCE_NAME"
        
        # --- Find Backup File ---
        if [ -z "$RESTORE_FILE" ]; then
            # If no file is specified, find the latest one for this instance
            echo "No backup file specified, finding latest for '$INSTANCE_NAME'..."
            
            # Find the newest file matching the pattern (list by time, grab the first one)
            RESTORE_FILE=$(ls -1t "$BACKUP_DIR/$INSTANCE_NAME"-*.tar.gz 2>/dev/null | head -n 1)

            if [ -z "$RESTORE_FILE" ]; then
                echo "Error: No backups found for '$INSTANCE_NAME' in $BACKUP_DIR"
                exit 1
            fi
            
            echo "Found latest backup: $RESTORE_FILE"
        fi
        
        # --- Check if File Exists ---
        if [ ! -f "$RESTORE_FILE" ]; then
            echo "Error: Backup file not found: $RESTORE_FILE"
            exit 1
        fi

        # --- Confirmation and Restore ---
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! WARNING: This will completely WIPE OUT all data in:"
        echo "!! $DEST_DIR"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        read -p "Press [Enter] to continue, or [Ctrl+C] to cancel."

        echo "Restoring $RESTORE_FILE to $DEST_DIR..."
        
        # Clear out the old directory
        rm -rf "$DEST_DIR"
        # Re-create it
        mkdir -p "$DEST_DIR"
        
        # -x: extract
        # -z: decompress gzip
        # -f: from file
        # -C: Extract to directory $DEST_DIR
        tar -xzf "$RESTORE_FILE" -C "$DEST_DIR"
        
        echo "Restore complete!"
	DOCKER_INSTANCE=wordpress-$INSTANCE_NAME
        echo "Restarting docker container $DOCKER_INSTANCE"
	docker compose restart $DOCKER_INSTANCE

        echo "Restart complete!"
        ;;

    *)
        echo "Error: Unknown action '$ACTION'"
        usage
        exit 1
        ;;
esac
