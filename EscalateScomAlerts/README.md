
# Escalate Alerts
Hugh Scott
2019/07/16

PowerShell and Configuration File used to:
- Manage SCOM Alert workflow
- Features:
 1. Introduce a delay during which alerts may be evaluated/validated
 2. Rule-based alerts get assigned to "Awaiting Evidence" until repeat count or modified date is incremented
 3. Alert Storms get trapped and pushed to a new alert state "Alert Storm"
 4. Monitor-based alerts get pushed to "Verified" state after 10 minute delay
 5. Rule-based alerts automatically closed if no repeat count/modification
 6. Selected alerts may be pushed into a "Create Incident" state (customer needs an service desk/ticketing application)

IMPORTANT:
Copy files to a single directory
Modify the configuration file as necessary
