import requests

# 1. Log in as the DEPARTMENT_HEAD
login_url = "http://127.0.0.1:8000/api/auth/login/"
credentials = {
    "employee_id": "EMP-0001",
    "password": "password"  # 
}

print("Logging in as Department Head...")
login_response = requests.post(login_url, json=credentials)
head_token = login_response.json().get("access")

headers = {
    "Authorization": f"Bearer {head_token}"
}

# 2. Delete the document
# This is the exact ID from your previous upload test
doc_id = "b38cad3b-5e4b-415d-8276-65195d774790"
delete_url = f"http://127.0.0.1:8000/api/documents/{doc_id}/"

print(f"\n--- Deleting Document {doc_id} ---")
# Sending a DELETE request to the server
delete_response = requests.delete(delete_url, headers=headers)

print(f"DELETE Status Code: {delete_response.status_code} (Should be 204 No Content)")

# 3. Verify it is actually gone from the database
print("\n--- Verifying Deletion ---")
verify_response = requests.get(delete_url, headers=headers)
print(f"GET Status Code: {verify_response.status_code} (Should be 404 Not Found)")

if verify_response.status_code == 404:
    print("Success! The document was completely removed from the database.")
else:
    print("Hmm, the document might still be there.")