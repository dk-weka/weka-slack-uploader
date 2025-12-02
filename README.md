# weka-slack-uploader

## Create a new Slack app to upload files to a Slack thread

## 2. Slack App Configuration (Dedicated App)

1. **Create App:** Log in to [api.slack.com/apps](http://api.slack.com/apps) -> Create New App -> From scratch -> Name: `CustomerName-Uploader` -> Workspace: `weka-support`.
2. **Configure Permissions:** Go to **OAuth & Permissions** -> **Bot Token Scopes** -> Add `files:write` and `chat:write`, and `files:read`.
3. **Install:** Install App to Workspace -> Copy **Bot User OAuth Token** (`xoxb-...`).
4. **Invite:** Run `/invite @CustomerName-Uploader` in the target channel.

## WMS / Client Preparation

**Safe Token Generation:** Use the `--path` flag to generate the token file directly.

1. **Create Service User & Directory:**
    
    ```bash
    sudo mkdir -p /opt/WekaSlackBot
    sudo chown $(whoami):$(whoami) /opt/WekaSlackBot
    ```
    
2. **Generate Token (consider modifying token retention/TTL settings prior to creating this):**
    
    ```bash
    weka user add WekaSlackBot readonly --password <SECURE_PASSWORD>
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
        # 1. Generate a new SSH deploy key specifically for this repo
        ssh-keygen -t ed25519 -C "customer-deploy-key" -f ~/.ssh/id_ed25519_deploy -N ""

        # 2. View the public key (You need to copy this output)
        cat ~/.ssh/id_ed25519_deploy.pub

        # 3. Have this key added to the github repo
        Repo > Settings > Deploy Keys

        # 4. Get the GitHub host key and append it to known_hosts
        ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

        # 5. Clone the Repo
        GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_deploy -o IdentitiesOnly=yes" git clone git@github.com:dk-weka/weka-slack-uploader.git


7. **Make executable:** chmod +x slack_uploader.py
8. **Update Secrets:** Ensure `/opt/WekaSlackBot/.secrets` has `SLACK_TOKEN`, `SLACK_CHANNEL_ID`, and `SLACK_THREAD_TS`.
9. **Update Scripts:** Copy new code to `slack_[uploader.py](http://uploader.py)` and `monitor_[quotas.sh](http://quotas.sh)`.
10. **Run:** Execute `./monitor_[quotas.sh](http://quotas.sh)`.
11. **Verify:** Check Slack thread for the new report (and "Also send to channel" if enabled).

## Scheduling (Cron)

`0 9 * * * /opt/WekaSlackBot/monitor_quotas.sh >> /var/log/weka_monitor.log 2>&1`