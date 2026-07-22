import requests

base_url = "http://127.0.0.1:8000/api"

# --- 1. HEAD BROADCASTS AN ALERT ---
print("1. Logging in as Department Head...")
head_creds = {"employee_id": "EMP-0001", "password": "password"} # <--- UPDATE THIS
head_token = requests.post(f"{base_url}/auth/login/", json=head_creds).json().get("access")

alert_data = {
    "title": "SERVER MAINTENANCE AT MIDNIGHT",
    "description": "Please save all your work. The system will go offline for 30 minutes.",
    "type": "MAINTENANCE"
}

print("   Broadcasting new alert...")
alert_response = requests.post(
    f"{base_url}/alerts/", 
    headers={"Authorization": f"Bearer {head_token}"}, 
    json=alert_data
)
alert_id = alert_response.json().get("id")
print(f"   Status: {alert_response.status_code}")


# --- 2. WORKER CHECKS ALERTS ---
print("\n2. Logging in as Worker...")
worker_creds = {"employee_id": "EMP-001", "password": "password123@"} # <--- UPDATE THIS
worker_token = requests.post(f"{base_url}/auth/login/", json=worker_creds).json().get("access")

print("   Fetching alerts...")
get_alerts_response = requests.get(
    f"{base_url}/alerts/", 
    headers={"Authorization": f"Bearer {worker_token}"}
)

# --- THE FIX: Handle the Pagination Dictionary ---
response_data = get_alerts_response.json()
# If "results" exists, use it. Otherwise, assume it's a standard list.
alerts_list = response_data.get("results", response_data) 

print(f"   Alerts found: {len(alerts_list)}")
if len(alerts_list) > 0:
    print(f"   Top Alert Title: {alerts_list[0]['title']}")


# --- 3. WORKER MARKS ALERT AS READ ---
print("\n3. Worker is marking the alert as read...")
mark_read_url = f"{base_url}/alerts/{alert_id}/mark_read/"
read_response = requests.post(
    mark_read_url, 
    headers={"Authorization": f"Bearer {worker_token}"}
)
print(f"   Status Code: {read_response.status_code}")
print(f"   Response: {read_response.text}")