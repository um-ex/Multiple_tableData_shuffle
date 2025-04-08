#!/usr/bin/env bash

# ------------------------------------------
# Database Shuffle Script
# Shuffles specified columns while preserving row relationships
# Usage: ./shuffle_data.sh <db_name> table1:id:col1,col2 table2:id:col3
# ------------------------------------------

# Load credentials securely
load_credentials() {
    if [ -f .env ]; then
        export $(grep -v '^#' .env | xargs)
    else
        echo "ERROR: .env file not found!"
        exit 1
    fi
}

# Validate MySQL connectivity
check_mysql_connection() {
    if ! sudo mysql --login-path=shuffle_script -e "SELECT 1" >/dev/null 2>&1; then
        echo "FATAL: MySQL connection failed. Verify:"
        echo "1. MySQL server is running"
        echo "2. Credentials in ~/.mylogin.cnf are correct"
        echo "3. User has required privileges"
        exit 1
    fi
}

# Validate database existence
check_database() {
    local db=$1
    if ! sudo mysql --login-path=shuffle_script -e "USE $db" >/dev/null 2>&1; then
        echo "FATAL: Database '$db' doesn't exist or access denied"
        exit 1
    fi
}

# Validate table structure
validate_table() {
    local db=$1 table=$2 id_col=$3 columns=$4
    
    # Check table existence
    if ! sudo mysql --login-path=shuffle_script -D "$db" -e "DESCRIBE $table" >/dev/null 2>&1; then
        echo "Table '$table' not found in database '$db'"
        return 1
    fi

    # Verify ID column exists
    if ! sudo mysql --login-path=shuffle_script -D "$db" -e "DESCRIBE $table" | awk '{print $1}' | grep -qw "$id_col"; then
        echo "ID column '$id_col' not found in table '$table'"
        return 1
    fi

    # Verify all shuffle columns exist
    while IFS=',' read -ra COLS; do
        for col in "${COLS[@]}"; do
            if ! sudo mysql --login-path=shuffle_script -D "$db" -e "DESCRIBE $table" | awk '{print $1}' | grep -qw "$col"; then
                echo "Column '$col' not found in table '$table'"
                return 1
            fi
        done
    done <<< "$columns"
}
shuffle_table() {
    local db=$1
    local table=$2
    local id_col=$3
    local columns=$4

    echo "🔄 Shuffling $table (ID: $id_col, Columns: ${columns//,/ })"

    local rand_table="_shuffle_${table}_$RANDOM"

    # Build SET clause dynamically
    local set_clause=""
    IFS=',' read -ra col_array <<< "$columns"
    for col in "${col_array[@]}"; do
        set_clause+="original.${col} = shuffled.${col}, "
    done
    set_clause=${set_clause%, }  # Remove trailing comma and space

    # SQL block
    local sql=$(cat <<EOF
SET SESSION bulk_insert_buffer_size = 268435456;
SET SESSION unique_checks = OFF;
SET SESSION foreign_key_checks = OFF;

-- Create shuffled data WITHOUT ID
CREATE TEMPORARY TABLE $rand_table AS
SELECT ${columns}
FROM $table
ORDER BY RAND();

-- Assign row numbers to original and shuffled data
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
SET
$set_clause;

DROP TEMPORARY TABLE $rand_table;
EOF
)

    # Execute the query
    if ! sudo mysql --login-path=shuffle_script -D "$db" -vv -e "$sql" 2> >(grep -v "Using a password"); then
        echo "❌ Shuffle failed for $table"
        return 1
    fi

    echo "✅ Successfully shuffled $table"
}




# Update the SQL block in shuffle_table() with:
# Main shuffle function
# --------------------------
# Execution Flow
# --------------------------
main() {
    # Initial checks
    load_credentials
    check_mysql_connection

    if [ "$#" -lt 2 ]; then
        echo "Usage: $0 <database> table1:id_col:col1,col2 table2:id_col:col3"
        exit 1
    fi

    local db=$1
    shift
    
    check_database "$db"

    # Process tables
    for table_def in "$@"; do
        IFS=':' read -r table id_col columns <<< "$table_def"
        
        if validate_table "$db" "$table" "$id_col" "$columns"; then
            shuffle_table "$db" "$table" "$id_col" "$columns"
        else
            echo "Skipping $table due to validation errors"
        fi
    done
}

# Run main function
main "$@"
