# weka-slack-uploader

## WMS / Client Preparation

**Safe Token Generation:** Use the `--path` flag to generate the token file directly.

1. **Create Service User & Directory:**
    
    ```bash
    sudo mkdir -p /opt/WekaSlackBot
    sudo chown $(whoami):$(whoami) /opt/WekaSlackBot
    ```
    
2. **Generate Token (consider modifying token retention/TTL settings prior to creating this):**
    
    ```bash
    weka user add WekaSlackBot readonly 
    # Login and save token to a specific file
    weka user login WekaSlackBot --path /opt/WekaSlackBot/auth-token.json
    ```
    
3. **Secure the Token:**
    
    ```bash
    chmod 400 /opt/WekaSlackBot/auth-token.json
    ```
    
4. **Create Secrets File (Portable Config):**
    - This file now holds ALL environment-specific variables (Token, Channel, Thread).
    - Create file: `vim /opt/WekaSlackBot/.secrets`
    - Add content:
        
        ```bash
        export SLACK_TOKEN="xoxb-YOUR-BOT-TOKEN"
        export SLACK_CHANNEL_ID="slack-channel-id"
        export SLACK_THREAD_TS="slack-thread-ts"
        export SLACK_BROADCAST="false"  # Set to "true" to also post to channel
        ```
        
    - Secure it: `chmod 600 /opt/WekaSlackBot/.secrets`
5. **Install Dependencies:**
    - **OS Packages:** `sudo apt install python3-requests jq` (Ubuntu) or `sudo dnf install python3-pip jq` (RHEL).
    - **Python:** Ensure `requests` is installed (`pip3 install requests` if not using apt).

6. **Clone The Repo:**

7. **Update Secrets:** Ensure `/opt/WekaSlackBot/.secrets` has `SLACK_TOKEN`, `SLACK_CHANNEL_ID`, and `SLACK_THREAD_TS`.
8. **Update Scripts:** Copy new code to `slack_[uploader.py](http://uploader.py)` and `monitor_[quotas.sh](http://quotas.sh)`.
9. **Run:** Execute `./monitor_[quotas.sh](http://quotas.sh)`.
10. **Verify:** Check Slack thread for the new report (and "Also send to channel" if enabled).

## Scheduling (Cron)

`0 9 * * * /opt/WekaSlackBot/monitor_quotas.sh >> /var/log/weka_monitor.log 2>&1`