import requests

# 1. Log in to get the token
login_url = "http://127.0.0.1:8000/api/auth/login/"
credentials = {
    "employee_id": "EMP-0001",
    "password": "password"  # 
}
fresh_token = requests.post(login_url, json=credentials).json().get("access")

# 2. Update the document status
# Using the exact UUID from your successful upload!
doc_id = "b38cad3b-5e4b-415d-8276-65195d774790"
update_url = f"http://127.0.0.1:8000/api/documents/{doc_id}/"

headers = {
    "Authorization": f"Bearer {fresh_token}"
}

# Sending the fields we want to change
update_data = {
    "is_active": True,
    "approval_status": "APPROVED"
}

print("Approving and activating document...")
response = requests.patch(update_url, headers=headers, json=update_data)

print(f"\nStatus Code: {response.status_code}")
print(response.text)