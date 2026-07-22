import requests

# 1. Log in as the WORKER
login_url = "http://127.0.0.1:8000/api/auth/login/"
credentials = {
    "employee_id": "EMP-001",
    "password": "password123@" 
}

print("Logging in as Worker...")
login_response = requests.post(login_url, json=credentials)
worker_token = login_response.json().get("access")

headers = {
    "Authorization": f"Bearer {worker_token}"
}

# 2. Test GET (Worker reading documents)
print("\n--- Testing WORKER Read Access ---")
get_url = "http://127.0.0.1:8000/api/documents/"
get_response = requests.get(get_url, headers=headers)
print(f"GET Status Code: {get_response.status_code} (Should be 200)")
print(f"Total documents visible to worker: {len(get_response.json())}")

# 3. Test POST (Worker trying to upload a document)
print("\n--- Testing WORKER Write Access (Hacking Attempt) ---")
post_url = "http://127.0.0.1:8000/api/documents/"
post_data = {
    "title": "Hacker Document",
    "doc_number": "HACK-001",
    "file_type": "PDF"
}

# The server should block this attempt immediately
post_response = requests.post(post_url, headers=headers, data=post_data)
print(f"POST Status Code: {post_response.status_code} (Should be 403 Forbidden)")
print(post_response.text)