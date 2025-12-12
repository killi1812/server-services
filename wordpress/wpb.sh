#!/bin/bash

# --- Configuration ---
# Directory where your WordPress instances live (e.g., ./data/my-site, ./data/another-site)
DATA_DIR="./data"
ENV_FILE=".env"
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
    echo "  backup <instance_name>             Back up a WordPress instance (files + database)"
    echo "  restore <instance_name> [path]     Restore a WordPress instance"
    echo ""
    echo "Examples:"
    echo "  ./wp-manage.sh backup my-site"
    echo "  sudo ./wp-manage.sh restore my-site      (restores the latest wpb)"
    echo "  sudo ./wp-manage.sh restore my-site backup/my-site-20251113.tar.gz"
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

        # --- Database Backup ---
        HAS_DB_BACKUP=false
        source "$ENV_FILE"
            
        # Map standard docker variables to our script variables
        # We use the variables we just loaded from the file
        DB_USER="root"
        DB_PASS=$MYSQL_ROOT_PASSWORD
        DB_NAME=$INSTANCE_NAME
            
        # Run command on the WordPress container (which connects to the shared DB)
        DB_CONTAINER="wordpress-db-1"

        if [ -n "$DB_CONTAINER" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASS" ]; then
            echo "Dumping database '$DB_NAME' from container '$DB_CONTAINER'..."
                
            # Run mysqldump inside the container and save to source dir
            # Added flags:
            # --single-transaction: Ensures consistent backup without locking tables
            # --set-gtid-purged=OFF: Prevents GTID warnings on partial dumps
            if docker exec "$DB_CONTAINER" /usr/bin/mysqldump -u "$DB_USER" -p"$DB_PASS" --single-transaction --set-gtid-purged=OFF "$DB_NAME" > "$SOURCE_DIR/backup.sql"; then
                echo "Database dump successful."
                HAS_DB_BACKUP=true
            else
                echo "Error: Database dump failed. Check container name and credentials."
                echo "Proceeding with file-only backup."
            fi
        else
                echo "Warning: Missing MYSQL_USER, MYSQL_PASSWORD, or MYSQL_DATABASE in .env."
        fi


        # --- File Backup ---
        DATE_STAMP=$(date +"%Y%m%d-%H%M%S")
        BACKUP_FILE="$BACKUP_DIR/$INSTANCE_NAME-$DATE_STAMP.tar.gz"

        echo "Backing up $SOURCE_DIR to $BACKUP_FILE"

        # -c: create archive
        # -z: compress with gzip (.gz)
        # -f: use archive file
        # -C: Change to directory $SOURCE_DIR before archiving.
        #
        tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .

        # Cleanup the temporary SQL file so it doesn't clutter the live directory
        if [ "$HAS_DB_BACKUP" = true ]; then
            rm "$SOURCE_DIR/backup.sql"
        fi

        echo "Backup complete!"
        ;;

    restore)
        # Check for sudo/root
        if [ "$EUID" -ne 0 ]; then
            echo "Error: Restore action must be run as root (use sudo)."
            exit 1
        fi

        RESTORE_FILE="$3" 

        if [ -z "$INSTANCE_NAME" ]; then
            echo "Error: Missing <instance_name> for restore."
            usage
            exit 1
        fi

        DEST_DIR="$DATA_DIR/$INSTANCE_NAME"

        # --- Find Backup File ---
        if [ -z "$RESTORE_FILE" ]; then
            echo "No backup file specified, finding latest for '$INSTANCE_NAME'..."
            RESTORE_FILE=$(ls -1t "$BACKUP_DIR/$INSTANCE_NAME"-*.tar.gz 2>/dev/null | head -n 1)

            if [ -z "$RESTORE_FILE" ]; then
                echo "Error: No backups found for '$INSTANCE_NAME' in $BACKUP_DIR"
                exit 1
            fi
            echo "Found latest backup: $RESTORE_FILE"
        fi

        if [ ! -f "$RESTORE_FILE" ]; then
            echo "Error: Backup file not found: $RESTORE_FILE"
            exit 1
        fi

        # --- Confirmation ---
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! WARNING: This will OVERWRITE existing files in:"
        echo "!! $DEST_DIR"
        echo "!! AND overwrite the database content for this instance."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        read -p "Press [Enter] to continue, or [Ctrl+C] to cancel."

        echo "Restoring $RESTORE_FILE to $DEST_DIR..."

        # Clear out the old directory
        rm -rf "$DEST_DIR"
        # Re-create it
        mkdir -p "$DEST_DIR"
        
        # -x: extract
        # -z: decompress gzip
        # -f: use archive file
        # -C: Change to directory $DEST_DIR
        #
        tar -xzf "$RESTORE_FILE" -C "$DEST_DIR"
        
        # --- Database Restore ---
        SQL_BACKUP="$DEST_DIR/backup.sql"

        if [ -f "$SQL_BACKUP" ]; then
            echo "Found backup.sql and .env, attempting database import..."
            
            # Load variables from the newly restored .env file
            source "$ENV_FILE"
            
            DB_USER=$MYSQL_USER
            DB_PASS=$MYSQL_PASSWORD
            DB_NAME=$INSTANCE_NAME
            DB_CONTAINER="wordpress-db-1"

            # Ensure DB container is accessible
            echo "Importing SQL into database '$DB_NAME' via container '$DB_CONTAINER'..."
            
            # This only imports into the specific DB_NAME, safe for shared DB instances
            if docker exec -i "$DB_CONTAINER" /usr/bin/mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_BACKUP"; then
                 echo "Database restore successful."
                 rm "$SQL_BACKUP" # Cleanup the SQL file after import
            else
                 echo "Error: Database restore failed. Is the container running?"
            fi
        fi

        echo "Restore complete!"
        
        DOCKER_INSTANCE="wordpress-$INSTANCE_NAME"
        echo "Restarting docker container $DOCKER_INSTANCE"
        docker compose restart "$DOCKER_INSTANCE" || docker restart "$DOCKER_INSTANCE"
        
        echo "Restart complete!"
        ;;

    *)
        echo "Error: Unknown action '$ACTION'"
        usage
        exit 1
        ;;
esac
