import requests

# --- STEP 1: Log in automatically to get a fresh token ---
login_url = "http://127.0.0.1:8000/api/auth/login/"
credentials = {
    "employee_id": "EMP-0001",
    "password": "password"  # <--- UPDATE THIS
}

print("Logging in...")
login_response = requests.post(login_url, json=credentials)

if login_response.status_code == 200:
    fresh_token = login_response.json().get("access")
    print("Login successful! Got a fresh token.")
    
    # --- STEP 2: Upload the document ---
    upload_url = "http://127.0.0.1:8000/api/documents/"
    headers = {
        "Authorization": f"Bearer {fresh_token}"
    }
    data = {
        "title": "SRS Document V2",
        "doc_number": "SRS-001",
        "file_type": "DOCX"
    }
    
    file_path = r"C:\Users\HP\Downloads\SRS_Version-02.docx"
    
    print("Uploading file...")
    with open(file_path, "rb") as f:
        files = {"file_url": f}
        upload_response = requests.post(upload_url, headers=headers, data=data, files=files)
        
    print(f"\nStatus Code: {upload_response.status_code}")
    print(upload_response.text)

else:
    print(f"Login Failed: {login_response.status_code}")
    print(login_response.text)