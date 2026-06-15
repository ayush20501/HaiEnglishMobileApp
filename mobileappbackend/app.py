from flask import Flask, request, jsonify, Response
from flask_cors import CORS
import sqlite3
import uuid
import json
import os
import requests
from requests.auth import HTTPBasicAuth
from datetime import datetime
from database import get_db_connection, init_db

app = Flask(__name__)
CORS(app)

@app.route('/api/auth/register', methods=['POST'])
def register():
    data = request.get_json() or {}
    email = data.get('email')
    password = data.get('password')
    name = data.get('name')
    
    if not email or not password or not name:
        return jsonify({"error": "All fields are required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "INSERT INTO users (email, password, name) VALUES (?, ?, ?)",
            (email, password, name)
        )
        conn.commit()
        user_id = cursor.lastrowid
        return jsonify({"message": "User registered successfully", "user": {"id": user_id, "name": name, "email": email}}), 201
    except sqlite3.IntegrityError:
        return jsonify({"error": "Email already registered"}), 400
    finally:
        conn.close()

@app.route('/api/auth/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    email = data.get('email')
    password = data.get('password')
    
    if not email or not password:
        return jsonify({"error": "Email and password are required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE email = ?", (email,))
    user = cursor.fetchone()
    conn.close()
    
    if user and user['password'] == password:
        return jsonify({
            "message": "Login successful",
            "user": {
                "id": user['id'],
                "name": user['name'],
                "email": user['email']
            }
        }), 200
    return jsonify({"error": "Invalid email or password"}), 401

@app.route('/api/courses', methods=['GET'])
def get_courses():
    user_id = request.args.get('user_id')
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT * FROM courses")
    courses = cursor.fetchall()
    
    enrolled_set = set()
    if user_id:
        cursor.execute("SELECT course_id FROM enrollments WHERE user_id = ?", (user_id,))
        enrolled_set = {row['course_id'] for row in cursor.fetchall()}
        
    result = []
    for c in courses:
        course_id = c['id']
        is_enrolled = course_id in enrolled_set
        pdf_completed = []
        quiz_score = {}
        essay_submitted = 0
        if user_id and is_enrolled:
            cursor.execute("SELECT pdf_completed, quiz_score, essay_submitted FROM progress WHERE user_id = ? AND course_id = ?", (user_id, course_id))
            prog = cursor.fetchone()
            if prog:
                pdf_completed = json.loads(prog['pdf_completed'] or '[]')
                quiz_score = json.loads(prog['quiz_score'] or '{}')
                essay_submitted = prog['essay_submitted'] or 0
        result.append({
            "id": course_id,
            "title": c['title'],
            "description": c['description'],
            "price": c['price'],
            "course_poster_url": c['course_poster_url'],
            "pdf_data": json.loads(c['pdf_data']),
            "quiz_data": json.loads(c['quiz_data']),
            "essay_prompt": json.loads(c['essay_prompt']),
            "is_enrolled": is_enrolled,
            "pdf_completed": pdf_completed,
            "quiz_score": quiz_score,
            "essay_submitted": essay_submitted
        })
    conn.close()
    return jsonify(result), 200

@app.route('/api/courses/<int:course_id>', methods=['GET'])
def get_course(course_id):
    user_id = request.args.get('user_id')
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT * FROM courses WHERE id = ?", (course_id,))
    c = cursor.fetchone()
    if not c:
        conn.close()
        return jsonify({"error": "Course not found"}), 404
        
    is_enrolled = False
    pdf_completed = []
    quiz_score = {}
    essay_submitted = 0
    if user_id:
        cursor.execute("SELECT 1 FROM enrollments WHERE user_id = ? AND course_id = ?", (user_id, course_id))
        is_enrolled = cursor.fetchone() is not None
        if is_enrolled:
            cursor.execute("SELECT pdf_completed, quiz_score, essay_submitted FROM progress WHERE user_id = ? AND course_id = ?", (user_id, course_id))
            prog = cursor.fetchone()
            if prog:
                pdf_completed = json.loads(prog['pdf_completed'] or '[]')
                quiz_score = json.loads(prog['quiz_score'] or '{}')
                essay_submitted = prog['essay_submitted'] or 0
        
    result = {
        "id": c['id'],
        "title": c['title'],
        "description": c['description'],
        "price": c['price'],
        "course_poster_url": c['course_poster_url'],
        "pdf_data": json.loads(c['pdf_data']),
        "quiz_data": json.loads(c['quiz_data']),
        "essay_prompt": json.loads(c['essay_prompt']),
        "is_enrolled": is_enrolled,
        "pdf_completed": pdf_completed,
        "quiz_score": quiz_score,
        "essay_submitted": essay_submitted
    }
    conn.close()
    return jsonify(result), 200

@app.route('/api/courses/<int:course_id>/enroll', methods=['POST'])
def enroll(course_id):
    data = request.get_json() or {}
    user_id = data.get('user_id')
    if not user_id:
        return jsonify({"error": "User ID is required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT 1 FROM courses WHERE id = ?", (course_id,))
    if not cursor.fetchone():
        conn.close()
        return jsonify({"error": "Course not found"}), 404
        
    try:
        cursor.execute(
            "INSERT INTO enrollments (user_id, course_id) VALUES (?, ?)",
            (user_id, course_id)
        )
        cursor.execute(
            "INSERT OR IGNORE INTO progress (user_id, course_id, pdf_completed, quiz_score, essay_submitted, essay_content) "
            "VALUES (?, ?, '[]', '{}', 0, '')",
            (user_id, course_id)
        )
        conn.commit()
        return jsonify({"message": "Enrolled successfully"}), 201
    except sqlite3.IntegrityError:
        return jsonify({"message": "Already enrolled"}), 200
    finally:
        conn.close()

@app.route('/api/courses/<int:course_id>/progress', methods=['GET'])
def get_progress(course_id):
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({"error": "User ID is required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT * FROM progress WHERE user_id = ? AND course_id = ?",
        (user_id, course_id)
    )
    p = cursor.fetchone()
    conn.close()
    
    if not p:
        return jsonify({
            "pdf_completed": [],
            "quiz_score": {},
            "essay_submitted": 0,
            "essay_content": ""
        }), 200
        
    return jsonify({
        "pdf_completed": json.loads(p['pdf_completed'] or '[]'),
        "quiz_score": json.loads(p['quiz_score'] or '{}'),
        "essay_submitted": p['essay_submitted'],
        "essay_content": p['essay_content'] or ""
    }), 200

@app.route('/api/courses/<int:course_id>/progress/pdf', methods=['POST'])
def update_pdf_progress(course_id):
    data = request.get_json() or {}
    user_id = data.get('user_id')
    chapter_number = data.get('chapter_number')
    if not user_id or chapter_number is None:
        return jsonify({"error": "User ID and chapter number are required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT pdf_completed FROM progress WHERE user_id = ? AND course_id = ?", (user_id, course_id))
    row = cursor.fetchone()
    
    pdf_list = []
    if row and row['pdf_completed']:
        pdf_list = json.loads(row['pdf_completed'])
        
    if chapter_number not in pdf_list:
        pdf_list.append(chapter_number)
        
    cursor.execute(
        "INSERT OR REPLACE INTO progress (user_id, course_id, pdf_completed, quiz_score, essay_submitted, essay_content) "
        "VALUES (?, ?, ?, "
        "COALESCE((SELECT quiz_score FROM progress WHERE user_id = ? AND course_id = ?), '{}'), "
        "COALESCE((SELECT essay_submitted FROM progress WHERE user_id = ? AND course_id = ?), 0), "
        "COALESCE((SELECT essay_content FROM progress WHERE user_id = ? AND course_id = ?), ''))",
        (user_id, course_id, json.dumps(pdf_list), user_id, course_id, user_id, course_id, user_id, course_id)
    )
    conn.commit()
    conn.close()
    return jsonify({"message": "PDF progress updated successfully", "pdf_completed": pdf_list}), 200

@app.route('/api/courses/<int:course_id>/progress/quiz', methods=['POST'])
def update_quiz_progress(course_id):
    data = request.get_json() or {}
    user_id = data.get('user_id')
    chapter_number = data.get('chapter_number')
    score = data.get('score')
    if not user_id or chapter_number is None or score is None:
        return jsonify({"error": "User ID, chapter number, and score are required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT quiz_score FROM progress WHERE user_id = ? AND course_id = ?", (user_id, course_id))
    row = cursor.fetchone()
    
    quiz_dict = {}
    if row and row['quiz_score']:
        quiz_dict = json.loads(row['quiz_score'])
        
    quiz_dict[str(chapter_number)] = score
    
    cursor.execute(
        "INSERT OR REPLACE INTO progress (user_id, course_id, pdf_completed, quiz_score, essay_submitted, essay_content) "
        "VALUES (?, ?, "
        "COALESCE((SELECT pdf_completed FROM progress WHERE user_id = ? AND course_id = ?), '[]'), "
        "?, "
        "COALESCE((SELECT essay_submitted FROM progress WHERE user_id = ? AND course_id = ?), 0), "
        "COALESCE((SELECT essay_content FROM progress WHERE user_id = ? AND course_id = ?), ''))",
        (user_id, course_id, user_id, course_id, json.dumps(quiz_dict), user_id, course_id, user_id, course_id)
    )
    conn.commit()
    conn.close()
    return jsonify({"message": "Quiz progress updated successfully", "quiz_score": quiz_dict}), 200

@app.route('/api/courses/<int:course_id>/progress/essay', methods=['POST'])
def update_essay_progress(course_id):
    data = request.get_json() or {}
    user_id = data.get('user_id')
    essay_content = data.get('essay_content')
    if not user_id or essay_content is None:
        return jsonify({"error": "User ID and essay content are required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT essay_prompt FROM courses WHERE id = ?", (course_id,))
    course_row = cursor.fetchone()
    if not course_row:
        conn.close()
        return jsonify({"error": "Course not found"}), 404
        
    try:
        essay_prompts = json.loads(course_row['essay_prompt'] or '[]')
    except Exception:
        essay_prompts = []
    total_essays = len(essay_prompts)
    
    try:
        parsed_content = json.loads(essay_content)
        submitted_map = parsed_content.get('submitted', {})
        submitted_count = sum(1 for k, v in submitted_map.items() if v is True)
    except Exception:
        submitted_count = 0
        
    essay_submitted = 1 if submitted_count >= total_essays and total_essays > 0 else 0
    
    cursor.execute(
        "INSERT OR REPLACE INTO progress (user_id, course_id, pdf_completed, quiz_score, essay_submitted, essay_content) "
        "VALUES (?, ?, "
        "COALESCE((SELECT pdf_completed FROM progress WHERE user_id = ? AND course_id = ?), '[]'), "
        "COALESCE((SELECT quiz_score FROM progress WHERE user_id = ? AND course_id = ?), '{}'), "
        "?, ?)",
        (user_id, course_id, user_id, course_id, user_id, course_id, essay_submitted, essay_content)
    )
    conn.commit()
    conn.close()
    return jsonify({"message": "Essay progress updated successfully"}), 200

@app.route('/api/courses/<int:course_id>/certificate', methods=['GET'])
def get_certificate(course_id):
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({"error": "User ID is required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT pdf_data FROM courses WHERE id = ?", (course_id,))
    course_row = cursor.fetchone()
    if not course_row:
        conn.close()
        return jsonify({"error": "Course not found"}), 404
    total_chapters = len(json.loads(course_row['pdf_data']))
    
    cursor.execute("SELECT * FROM progress WHERE user_id = ? AND course_id = ?", (user_id, course_id))
    p = cursor.fetchone()
    
    if not p:
        conn.close()
        return jsonify({"error": "No course progress found"}), 400
        
    pdf_completed = json.loads(p['pdf_completed'] or '[]')
    quiz_score = json.loads(p['quiz_score'] or '{}')
    
    is_pdf_finished = len(pdf_completed) >= total_chapters
    is_quiz_finished = len(quiz_score) >= total_chapters
    
    if not is_pdf_finished or not is_quiz_finished or p['essay_submitted'] != 1:
        conn.close()
        return jsonify({"error": "Course is not fully completed. Complete all 25 chapters and submit the essay."}), 400
        
    cursor.execute("SELECT * FROM certificates WHERE user_id = ? AND course_id = ?", (user_id, course_id))
    cert = cursor.fetchone()
    
    if cert:
        cert_uuid = cert['certificate_uuid']
        issued_at = cert['issued_at']
    else:
        cert_uuid = str(uuid.uuid4())
        cursor.execute(
            "INSERT INTO certificates (user_id, course_id, certificate_uuid) VALUES (?, ?, ?)",
            (user_id, course_id, cert_uuid)
        )
        conn.commit()
        cursor.execute("SELECT issued_at FROM certificates WHERE certificate_uuid = ?", (cert_uuid,))
        issued_at = cursor.fetchone()['issued_at']
        
    cursor.execute("SELECT name, email FROM users WHERE id = ?", (user_id,))
    user_row = cursor.fetchone()
    user_name = user_row['name']
    user_email = user_row['email']
    
    cursor.execute("SELECT title FROM courses WHERE id = ?", (course_id,))
    course_title = cursor.fetchone()['title']
    
    conn.close()
    
    api_course_name = "Tesol Prime"
    
    import urllib.parse
    from datetime import datetime
    
    course_map = {
        "Tesol Prime": 24,
        "TESOL Prime": 24
    }
    cert_course_id = course_map.get(course_title, 24)
    
    formatted_name = urllib.parse.quote(user_name)
    try:
        date_part = issued_at.split(" ")[0]
    except Exception:
        date_part = datetime.now().strftime("%Y-%m-%d")
        
    download_url = f"https://www.tesolteflverifier.info/haienglish/certificate/?name={formatted_name}&date={date_part}&course={cert_course_id}"
    
    return jsonify({
        "certificate_uuid": cert_uuid,
        "issued_at": issued_at,
        "user_name": user_name,
        "course_title": api_course_name,
        "download_url": download_url
    }), 200

@app.route('/api/courses/<int:course_id>/certificate/download', methods=['GET'])
def download_certificate(course_id):
    user_id = request.args.get('user_id')
    if not user_id:
        return "User ID is required", 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT pdf_data FROM courses WHERE id = ?", (course_id,))
    course_row = cursor.fetchone()
    if not course_row:
        conn.close()
        return "Course not found", 404
    total_chapters = len(json.loads(course_row['pdf_data']))
    
    cursor.execute("SELECT * FROM progress WHERE user_id = ? AND course_id = ?", (user_id, course_id))
    p = cursor.fetchone()
    if not p:
        conn.close()
        return "No course progress found", 400
        
    pdf_completed = json.loads(p['pdf_completed'] or '[]')
    quiz_score = json.loads(p['quiz_score'] or '{}')
    
    is_pdf_finished = len(pdf_completed) >= total_chapters
    is_quiz_finished = len(quiz_score) >= total_chapters
    
    if not is_pdf_finished or not is_quiz_finished or p['essay_submitted'] != 1:
        conn.close()
        return "Course is not fully completed. Complete all 25 chapters and submit the essay.", 400
        
    cursor.execute("SELECT * FROM certificates WHERE user_id = ? AND course_id = ?", (user_id, course_id))
    cert = cursor.fetchone()
    
    if cert:
        cert_uuid = cert['certificate_uuid']
        issued_at = cert['issued_at']
    else:
        cert_uuid = str(uuid.uuid4())
        cursor.execute(
            "INSERT INTO certificates (user_id, course_id, certificate_uuid) VALUES (?, ?, ?)",
            (user_id, course_id, cert_uuid)
        )
        conn.commit()
        cursor.execute("SELECT issued_at FROM certificates WHERE certificate_uuid = ?", (cert_uuid,))
        issued_at = cursor.fetchone()['issued_at']
        
    cursor.execute("SELECT name FROM users WHERE id = ?", (user_id,))
    user_name = cursor.fetchone()['name']
    
    cursor.execute("SELECT title FROM courses WHERE id = ?", (course_id,))
    course_title = cursor.fetchone()['title']
    
    conn.close()
    
    import urllib.parse
    import urllib.request
    from datetime import datetime
    
    course_map = {
        "Tesol Prime": 24,
        "TESOL Prime": 24
    }
    cert_course_id = course_map.get(course_title, 24)
    
    formatted_name = urllib.parse.quote(user_name)
    try:
        date_part = issued_at.split(" ")[0]
    except Exception:
        date_part = datetime.now().strftime("%Y-%m-%d")
        
    url = f"https://www.tesolteflverifier.info/haienglish/certificate/?name={formatted_name}&date={date_part}&course={cert_course_id}"
    
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=15) as response:
            pdf_bytes = response.read()
    except Exception as e:
        return f"Error downloading certificate from verifier: {str(e)}", 500
        
    safe_filename = "".join([c if c.isalnum() else "_" for c in course_title])
    return Response(
        pdf_bytes,
        mimetype="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={safe_filename}_Certificate.pdf"
        }
    )

@app.route('/api/settings', methods=['GET'])
def get_settings():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM settings")
    rows = cursor.fetchall()
    conn.close()
    settings_dict = {row['key']: row['value'] for row in rows}
    return jsonify(settings_dict), 200

@app.route('/api/auth/forgot-password', methods=['POST'])
def forgot_password():
    data = request.get_json() or {}
    email = data.get('email')
    
    if not email:
        return jsonify({"error": "Email is required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT id FROM users WHERE email = ?", (email,))
    user = cursor.fetchone()
    
    if not user:
        conn.close()
        return jsonify({"error": "No user found with this email address"}), 404
        
    import random
    import smtplib
    from email.message import EmailMessage
    
    otp = str(random.randint(100000, 999999))
    
    cursor.execute("INSERT OR REPLACE INTO otps (email, otp, expires_at) VALUES (?, ?, datetime('now', '+1 minutes'))", (email, otp))
    conn.commit()
    
    cursor.execute("SELECT value FROM settings WHERE key = 'smtp_email'")
    smtp_email = cursor.fetchone()['value']
    cursor.execute("SELECT value FROM settings WHERE key = 'smtp_password'")
    smtp_pwd = cursor.fetchone()['value']
    conn.close()
    
    msg = EmailMessage()
    msg['Subject'] = "HaiEnglish Password Reset OTP"
    msg['From'] = smtp_email
    msg['To'] = email
    msg.set_content(f"Your OTP code for password reset is: {otp}. It is valid for 1 minute.")
    
    try:
        with smtplib.SMTP_SSL('smtp.gmail.com', 465) as smtp_server:
            smtp_server.login(smtp_email, smtp_pwd)
            smtp_server.send_message(msg)
    except Exception as e:
        return jsonify({"error": f"Failed to send email: {str(e)}"}), 500
        
    return jsonify({"message": "OTP sent successfully"}), 200

@app.route('/api/auth/reset-password', methods=['POST'])
def reset_password():
    data = request.get_json() or {}
    email = data.get('email')
    otp = data.get('otp')
    new_password = data.get('new_password')
    
    if not email or not otp or not new_password:
        return jsonify({"error": "Email, OTP, and new password are required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT * FROM otps WHERE email = ? AND otp = ? AND expires_at > datetime('now')", (email, otp))
    row = cursor.fetchone()
    
    if not row:
        conn.close()
        return jsonify({"error": "Invalid or expired OTP"}), 400
        
    cursor.execute("UPDATE users SET password = ? WHERE email = ?", (new_password, email))
    cursor.execute("DELETE FROM otps WHERE email = ?", (email,))
    conn.commit()
    conn.close()
    
    return jsonify({"message": "Password reset successfully"}), 200

@app.route('/api/payment/create-invoice', methods=['POST'])
def create_invoice():
    data = request.get_json() or {}
    user_id = data.get('user_id')
    course_id = data.get('course_id')
    
    if not user_id or not course_id:
        return jsonify({"error": "User ID and Course ID are required"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT email FROM users WHERE id = ?", (user_id,))
    user_row = cursor.fetchone()
    if not user_row:
        conn.close()
        return jsonify({"error": "User not found"}), 404
    user_email = user_row['email']
    
    cursor.execute("SELECT title, price FROM courses WHERE id = ?", (course_id,))
    course_row = cursor.fetchone()
    if not course_row:
        conn.close()
        return jsonify({"error": "Course not found"}), 404
        
    course_title = course_row['title']
    course_price = course_row['price']
    
    cursor.execute("SELECT value FROM settings WHERE key = 'xendit_api_key'")
    key_row = cursor.fetchone()
    xendit_api_key = key_row['value'] if key_row else ""
    conn.close()
    
    if not xendit_api_key:
        return jsonify({"error": "Xendit API Key not configured"}), 500
        
    external_id = f"hai_mobile_inv_{user_id}_{course_id}_{int(datetime.utcnow().timestamp())}"
    
    url = "https://api.xendit.co/v2/invoices"
    auth = HTTPBasicAuth(xendit_api_key, "")
    headers = {
        "Content-Type": "application/json"
    }
    payload = {
        "external_id": external_id,
        "amount": float(course_price),
        "currency": "PHP",
        "payer_email": user_email,
        "description": f"Enrollment in {course_title}",
        "metadata": {
            "app": "HAIENGLISH_MOBILE",
            "user_id": str(user_id),
            "course_id": str(course_id)
        }
    }
    
    try:
        response = requests.post(url, json=payload, auth=auth, headers=headers, timeout=15)
        if response.status_code != 200 and response.status_code != 201:
            return jsonify({"error": f"Xendit API error: {response.text}"}), response.status_code
        invoice_data = response.json()
        return jsonify({
            "invoice_url": invoice_data.get("invoice_url"),
            "external_id": external_id
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to contact Xendit: {str(e)}"}), 500

@app.route('/xendit-webhook/', methods=['POST'])
@app.route('/xendit-webhook', methods=['POST'])
def xendit_webhook():
    data = request.get_json() or {}
    external_id = data.get('external_id', '')
    status = data.get('status', '')
    
    if not external_id or not status:
        return jsonify({"error": "Invalid webhook payload"}), 400
        
    if status in ['PAID', 'SETTLED'] and external_id.startswith('hai_mobile_inv_'):
        parts = external_id.split('_')
        if len(parts) >= 5:
            try:
                user_id = int(parts[3])
                course_id = int(parts[4])
                
                conn = get_db_connection()
                cursor = conn.cursor()
                
                cursor.execute(
                    "INSERT OR IGNORE INTO enrollments (user_id, course_id) VALUES (?, ?)",
                    (user_id, course_id)
                )
                cursor.execute(
                    "INSERT OR IGNORE INTO progress (user_id, course_id, pdf_completed, quiz_score, essay_submitted, essay_content) "
                    "VALUES (?, ?, '[]', '{}', 0, '')",
                    (user_id, course_id)
                )
                conn.commit()
                conn.close()
                return jsonify({"message": "Enrollment completed successfully"}), 200
            except Exception as e:
                return jsonify({"error": f"Database enrollment failed: {str(e)}"}), 500
                
    return jsonify({"message": "Webhook received but no enrollment required"}), 200

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=True)
