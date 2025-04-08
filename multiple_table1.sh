#!/usr/bin/env bash

# ------------------------------------------
# Database Shuffle Script
# Shuffles specified columns while preserving row relationships
# Usage: ./shuffle_data.sh <db_name> table1:id_col:col1,col2 table2:id_col:col3
# ------------------------------------------

# Load credentials securely from .env file
load_credentials() {
    if [ -f .env ]; then
        set -a
        source .env
        set +a
    else
        echo "ERROR: .env file not found!"
        exit 1
    fi
}

# MySQL command to execute queries using credentials
mysql_command() {
    local db=$1
    local query=$2
    sudo mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$db" -e "$query" >/dev/null 2>&1
}

# Validate MySQL connection
check_mysql_connection() {
    if ! mysql_command "" "SELECT 1"; then
        echo "❌ MySQL connection failed. Check your .env credentials and MySQL status."
        exit 1
    fi
}

# Check if the database exists
check_database() {
    local db=$1
    if ! mysql_command "$db" "SELECT 1"; then
        echo "❌ Database '$db' not found or access denied"
        exit 1
    fi
}

# Validate the table and columns exist
validate_table() {
    local db=$1 table=$2 id_col=$3 columns=$4

    echo "🔍 Validating structure for table '$table'..."

    # Check if the table exists
    if ! sudo mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$db" \
        -e "DESCRIBE $table" >/dev/null 2>&1; then
        echo "❌ Table '$table' does not exist"
        return 1
    fi

    # Check if ID column exists
    if ! sudo mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$db" --silent --skip-column-names \
        -e "DESCRIBE $table" | awk '{print $1}' | grep -qw "$id_col"; then
        echo "❌ ID column '$id_col' not found in table '$table'"
        return 1
    fi

    # Check if all columns to shuffle exist
    IFS=',' read -ra col_array <<< "$columns"
    for col in "${col_array[@]}"; do
        if ! sudo mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$db" --silent --skip-column-names \
            -e "DESCRIBE $table" | awk '{print $1}' | grep -qw "$col"; then
            echo "❌ Column '$col' not found in table '$table'"
            return 1
        fi
    done

    return 0
}

# Shuffle table data
shuffle_table() {
    local db=$1 table=$2 id_col=$3 columns=$4
    echo "🔄 Shuffling '$table' (ID: $id_col, Columns: ${columns//,/ })"

    local rand_table="_shuffle_${table}_$RANDOM"

    # Build SET clause
    local set_clause=""
    IFS=',' read -ra col_array <<< "$columns"
    for col in "${col_array[@]}"; do
        set_clause+="original.${col} = shuffled.${col}, "
    done
    set_clause=${set_clause%, }

    local sql=$(cat <<EOF
SET SESSION bulk_insert_buffer_size = 268435456;
SET SESSION unique_checks = OFF;
SET SESSION foreign_key_checks = OFF;

CREATE TEMPORARY TABLE $rand_table AS
SELECT ${columns}
FROM $table
ORDER BY RAND();

SET @row_num = 0;
UPDATE $table AS original
JOIN (
    SELECT *, @row_num := @row_num + 1 AS rn
    FROM $table
) AS orig_order USING ($id_col)
JOIN (
    SELECT *, @row_shuffle := @row_shuffle + 1 AS rn
    FROM $rand_table
    CROSS JOIN (SELECT @row_shuffle := 0) AS vars
) AS shuffled
ON orig_order.rn = shuffled.rn
SET $set_clause;

DROP TEMPORARY TABLE $rand_table;
EOF
)

    if ! mysql_command "$db" "$sql"; then
        echo "❌ Shuffle failed for '$table'"
        return 1
    fi

    echo "✅ Successfully shuffled '$table'"
}

# Main logic
main() {
    load_credentials
    check_mysql_connection

    if [ "$#" -lt 2 ]; then
        echo "Usage: $0 <database> table1:id_col:col1,col2 table2:id_col:col3"
        exit 1
    fi

    local db=$1
    shift

    check_database "$db"

    for table_def in "$@"; do
        IFS=':' read -r table id_col columns <<< "$table_def"

        if validate_table "$db" "$table" "$id_col" "$columns"; then
            shuffle_table "$db" "$table" "$id_col" "$columns"
        else
            echo "⚠️ Skipping '$table' due to validation errors"
        fi
    done
}

main "$@"

