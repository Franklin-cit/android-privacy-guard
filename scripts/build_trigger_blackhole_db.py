#!/usr/bin/env python3
"""
Builds or converts a Xiaomi/HyperOS fraud_detection_data.db into a Zero-Crash
Trigger-Blackhole SQLite database:
- Preserves PRAGMA user_version (default 1) and all 8 original table schemas.
- Wipes all existing rows and resets sqlite_sequence.
- Injects 16 BEFORE INSERT and BEFORE UPDATE triggers with SELECT RAISE(IGNORE);
  so any write attempt returns SQLITE_OK (no exception) while storing 0 rows.

Usage:
  python build_trigger_blackhole_db.py <src_db_path> <dst_db_path>
  python build_trigger_blackhole_db.py --create <dst_db_path>
"""
import os
import shutil
import sqlite3
import sys

SCHEMA_SQL = [
    "CREATE TABLE IF NOT EXISTS android_metadata (locale TEXT)",
    "CREATE TABLE IF NOT EXISTS install_app(_id INTEGER PRIMARY KEY AUTOINCREMENT,pkg_name TEXT NOT NULL,app_name TEXT NOT NULL,source TEXT NOT NULL,version_code INTEGER NOT NULL,md5 TEXT NOT NULL,install_finish_time INTEGER NOT NULL,app_tag_id INTEGER NOT NULL,security_tag_id INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS fraud_url(_id INTEGER PRIMARY KEY AUTOINCREMENT,access_time INTEGER NOT NULL,url_type INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS voip_record(_id INTEGER PRIMARY KEY AUTOINCREMENT,voip_record_package_name TEXT NOT NULL,voip_record_start_time INTEGER NOT NULL,voip_record_end_time INTEGER NOT NULL,is_active INTEGER NOT NULL,is_fraud_call INTEGER NOT NULL,duration INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS fraud_phone(_id INTEGER PRIMARY KEY AUTOINCREMENT,call_start_time INTEGER NOT NULL,call_end_time INTEGER NOT NULL,is_fraud_call INTEGER NOT NULL,tel_location TEXT NOT NULL,tel_number_md5 TEXT NOT NULL,operator TEXT NOT NULL,is_chinese_number INTEGER NOT NULL,is_virtual_operator INTEGER NOT NULL,is_active INTEGER NOT NULL,duration INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS airplane_mode(_id INTEGER PRIMARY KEY AUTOINCREMENT,airplane_mode_on INTEGER NOT NULL,airplane_mode_change_time INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS call_forwarding(_id INTEGER PRIMARY KEY AUTOINCREMENT,reason INTEGER NOT NULL,enabled INTEGER NOT NULL,timestamp INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS screen_share(_id INTEGER PRIMARY KEY AUTOINCREMENT,screen_share_package_name TEXT NOT NULL,screen_share_start_time INTEGER NOT NULL,screen_share_end_time INTEGER NOT NULL,is_active INTEGER NOT NULL,duration INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS screenshot(_id INTEGER PRIMARY KEY AUTOINCREMENT,screenshort_time INTEGER NOT NULL)",
]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    src = sys.argv[1]
    dst = sys.argv[2]

    if src == "--create" or not os.path.exists(src):
        if os.path.exists(dst):
            os.remove(dst)
        conn = sqlite3.connect(dst)
        c = conn.cursor()
        c.execute("PRAGMA user_version = 1")
        for stmt in SCHEMA_SQL:
            c.execute(stmt)
        c.execute("DELETE FROM android_metadata")
        c.execute("INSERT INTO android_metadata VALUES ('zh_CN')")
        conn.commit()
    else:
        shutil.copyfile(src, dst)
        conn = sqlite3.connect(dst)
        c = conn.cursor()

    user_ver = c.execute("PRAGMA user_version").fetchone()[0]
    print(f"[INFO] PRAGMA user_version = {user_ver}")

    tables = [
        r[0]
        for r in c.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'"
        ).fetchall()
    ]

    for t in tables:
        before_cnt = c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"  Table {t}: wiping {before_cnt} existing rows")
        c.execute(f"DELETE FROM {t}")
        c.execute(f"DROP TRIGGER IF EXISTS block_insert_{t}")
        c.execute(f"DROP TRIGGER IF EXISTS block_update_{t}")
        c.execute(
            f"CREATE TRIGGER block_insert_{t} BEFORE INSERT ON {t} BEGIN SELECT RAISE(IGNORE); END;"
        )
        c.execute(
            f"CREATE TRIGGER block_update_{t} BEFORE UPDATE ON {t} BEGIN SELECT RAISE(IGNORE); END;"
        )

    c.execute("DELETE FROM sqlite_sequence")
    conn.commit()
    c.execute("VACUUM")
    conn.commit()

    # Self-test: attempt to insert a dummy row and verify 0 rows remain
    if "screenshot" in tables:
        c.execute("INSERT INTO screenshot (screenshort_time) VALUES (1000000)")
        conn.commit()

    for t in tables:
        after_cnt = c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        assert after_cnt == 0, f"Trigger check failed on {t}"

    triggers = [
        r[0]
        for r in c.execute("SELECT name FROM sqlite_master WHERE type='trigger'").fetchall()
    ]
    print(f"[SUCCESS] Generated {dst} with 0 rows and {len(triggers)} active RAISE(IGNORE) triggers.")
    conn.close()


if __name__ == "__main__":
    main()
