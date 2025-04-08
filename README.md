# 📦 Database Shuffle Script  
A Bash utility to randomly shuffle specified columns in MySQL tables while preserving row integrity using a shared identifier column.
Useful for anonymizing sensitive data in development or testing environments without breaking foreign key relationships.

---

# 🚀 Features
Shuffles data per-table with flexible column selection
Ensures row relationships stay intact using row numbers
Handles multiple tables in a single run
Supports secure credential handling via .env

---

# 🛠️ Requirements
* Bash (Linux/macOS)
* MySQL client tools with sudo privileges
* .env file

---

# 🔐 Environment Configuration
You can store environment variables in a .env file in the script directory:
```bash
# Example .env
DB_USER="user"
DB_PASSWORD="yourpassword"
DB_HOST="host"
DB_PORT="port_no"
```

---

# 📦 Usage
```bash
./shuffle_data.sh <database> <table1:id_col:col1,col2> <table2:id_col:col3>
```
## Example:
```bash
./shuffle_data.sh my_database users:id:name,email orders:id:amount
```
This will:
- Shuffle name and email in the users table
- Shuffle amount in the orders table
- Keep row alignment using the id column

---

# ⚙️ How It Works
1. Checks MySQL connection and database access
2. Validates table, ID column, and columns to shuffle
3. Creates a temporary shuffled version of the target columns
4. Assigns row numbers to ensure consistent mapping
5. Updates original table with shuffled values

---
# 📂 File Structure
```bash
.
├── shuffle_data.sh     # Main script
└── .env                # Optional: for credentials (not required if using ~/.mylogin.cnf)
```
---
# ✅ Sample Output
```bash
🔄 Shuffling users (ID: id, Columns: name email)
✅ Successfully shuffled users

🔄 Shuffling orders (ID: id, Columns: amount)
✅ Successfully shuffled orders
```
---

# 🚧 Limitations
* Assumes ID column uniquely identifies each row.
* Not suitable for huge datasets without tweaking MySQL memory/session settings.
* Works best on tables with simple foreign key relationships.


