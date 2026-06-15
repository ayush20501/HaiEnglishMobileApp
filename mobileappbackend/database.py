import sqlite3
import json
import os

DB_PATH = os.path.join(os.path.dirname(__file__), 'learning.db')

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            name TEXT NOT NULL
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS courses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            price REAL NOT NULL,
            course_poster_url TEXT NOT NULL,
            pdf_data TEXT NOT NULL,
            quiz_data TEXT NOT NULL,
            essay_prompt TEXT NOT NULL
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS enrollments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            course_id INTEGER NOT NULL,
            enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users (id),
            FOREIGN KEY (course_id) REFERENCES courses (id),
            UNIQUE(user_id, course_id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            course_id INTEGER NOT NULL,
            pdf_completed TEXT,
            quiz_score TEXT,
            essay_submitted INTEGER DEFAULT 0,
            essay_content TEXT,
            FOREIGN KEY (user_id) REFERENCES users (id),
            FOREIGN KEY (course_id) REFERENCES courses (id),
            UNIQUE(user_id, course_id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS certificates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            course_id INTEGER NOT NULL,
            certificate_uuid TEXT UNIQUE NOT NULL,
            issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users (id),
            FOREIGN KEY (course_id) REFERENCES courses (id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
    ''')
    cursor.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('app_logo', 'https://i.ibb.co/KcpRPJD4/HAI-logo.png')")
    cursor.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('smtp_email', 'haicertificates@gmail.com')")
    cursor.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('smtp_password', 'djvq rxnl qthi qrnj')")
    cursor.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('xendit_api_key', 'xnd_production_Up3ESa5GzcvEJBU7e6TTvhhvTqBivvAuGcd6XsQjPKQGhLSAAd86pfyg1YSM4l')")

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS otps (
            email TEXT PRIMARY KEY,
            otp TEXT NOT NULL,
            expires_at TIMESTAMP DEFAULT (datetime('now', '+1 minutes'))
        )
    ''')
    
    conn.commit()
    conn.close()

if __name__ == '__main__':
    init_db()
