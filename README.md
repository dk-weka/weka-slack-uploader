# weka-slack-uploader

## WMS / Client Preparation

**Safe Token Generation:** Use the `--path` flag to generate the token file directly.

1. **Create Service User & Directory:**
    
    ```bash
    sudo mkdir -p /opt/wekaslackbot
    sudo chown $(whoami):$(whoami) /opt/wekaslackbot
    ```
    
2. **Generate Token (consider modifying token retention/TTL settings prior to creating this):**
    
    ```bash
    weka user add wekaslackbot readonly 
    # Login and save token to a specific file
    weka user login wekaslackbot --path /opt/wekaslackbot/auth-token.json
    ```
    
3. **Secure the Token:**
    
    ```bash
    chmod 400 /opt/wekaslackbot/auth-token.json
    ```
    
4. **Create Secrets File (Portable Config):**
    - This file now holds ALL environment-specific variables (Token, Channel, Thread).
    - Create file: `vim /opt/wekaslackbot/.secrets`
    - Add content:
        
        ```bash
        export SLACK_TOKEN="xoxb-YOUR-BOT-TOKEN"
        export SLACK_CHANNEL_ID="slack-channel-id"
        export SLACK_THREAD_TS="slack-thread-ts"
        export SLACK_BROADCAST="false"  # Set to "true" to also post to channel
        ```
        
    - Secure it: `chmod 600 /opt/wekaslackbot/.secrets`
5. **Install Dependencies:**
    - **OS Packages:** `sudo apt install python3-requests jq` (Ubuntu) or `sudo dnf install python3-pip jq` (RHEL).
    - **Python:** Ensure `requests` is installed (`pip3 install requests` if not using apt).

6. **Clone The Repo:**

    ```bash
    cd /opt/wekaslackbot
    git clone --depth=1 https://github.com/dk-weka/weka-slack-uploader
    ```

7. **Update Secrets:** Ensure `/opt/wekaslackbot/.secrets` has `SLACK_TOKEN`, `SLACK_CHANNEL_ID`, and `SLACK_THREAD_TS`.
8. **Run:** Execute `./monitor_quotas.sh`.
9. **Verify:** Check Slack thread for the new report (and "Also send to channel" if enabled).

## Scheduling (Cron)
To ensure long-term stability and traceability, follow these steps to set up automated execution with log rotation and time-stamped output.

1. **Initialize log directory**
Create the log file directory if it doesn't already exist***
- For Ubuntu / Debian:

    ```bash
    sudo mkdir -p /var/log/weka
    sudo chown syslog:adm /var/log/weka
    ```
- For RHEL / Rocky / Alma:
    ```bash
    sudo mkdir -p /var/log/weka
    sudo chown root:root /var/log/weka
    # Set SELinux context for the custom log path
    sudo semanage fcontext -a -t var_log_t "/var/log/weka(/.*)?" 2>/dev/null || true
    sudo restorecon -R -v /var/log/weka 
    ```
2. **Configure log rotation**
Create a `logrotate` policy to prevent log files from exhausting disk space. `sudo vim /etc/logrotate.d/weka-slack-uploader`
- For Ubuntu / Debian:

    ```bash
    /var/log/weka/slack-uploader.log {
        rotate 30
        size 1G
        daily
        missingok
        notifempty
        compress
        delaycompress
        create 0640 syslog syslog
    }
    ```
- For RHEL / Rocky / Alma:

    ```bash
    /var/log/weka/slack-uploader.log {
        rotate 30
        size 1G
        daily
        missingok
        notifempty
        compress
        delaycompress
        create 0600 root root
    }
    ```
3. **Add the Cron Job**
Add the following entry to the root crontab to run the script every day at 8:00 AM. This captures both standard output and errors, prefixes them with a timestamp, and appends them to the log.
    - Open the crontab editor: `sudo crontab -e`
    - Add this line at the bottom:

        ```bash
        0 8 * * * /opt/wekaslackbot/weka-slack-uploader/monitor_quotas.sh 2>&1 | ts '[%Y-%m-%d %H:%M:%S]' >> /var/log/weka/slack-uploader.log
        ```

4. **Verification**
Trigger a manual run to confirm the logging chain and timestamps are functioning as expected:

    ```bash
    sudo /opt/wekaslackbot/weka-slack-uploader/monitor_quotas.sh 2>&1 | ts '[%Y-%m-%d %H:%M:%S]' >> /var/log/weka/slack-uploader.log
    tail -n 20 /var/log/weka/slack-uploader.log
    ```