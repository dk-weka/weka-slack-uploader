#!/usr/bin/env python3

import requests
import os
import argparse
import sys

def upload_file_to_slack(file_path, initial_comment, channel_id, thread_ts=None, broadcast=False):
    """
    Uploads a file to Slack and ensures visibility by posting a link.
    Supports threading and broadcasting.
    """
    slack_token = os.environ.get("SLACK_TOKEN")
    if not slack_token:
        print("Error: SLACK_TOKEN environment variable not set.")
        sys.exit(1)

    if not os.path.exists(file_path):
        print(f"Error: File not found at {file_path}")
        sys.exit(1)

    file_name = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)

    if file_size == 0:
        print("Error: File is empty (0 bytes). Check generation script.")
        sys.exit(1)

    # --- Step 1: Request upload URL ---
    print("Step 1: Requesting upload URL...")
    headers_auth = {"Authorization": f"Bearer {slack_token}"}

    try:
        data_get_upload = {"filename": file_name, "length": file_size}
        response = requests.post(
            "https://slack.com/api/files.getUploadURLExternal",
            headers=headers_auth,
            data=data_get_upload,
            timeout=30
        )
        response.raise_for_status()
        upload_data = response.json()

        if not upload_data.get("ok"):
            print(f"Error getting upload URL: {upload_data.get('error')}")
            sys.exit(1)

        upload_url = upload_data["upload_url"]
        file_id = upload_data["file_id"]
        print(f"Upload URL obtained. File ID: {file_id}")

    except requests.exceptions.RequestException as e:
        print(f"Network Error in Step 1: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected Error in Step 1: {e}")
        sys.exit(1)

    # --- Step 2: Upload file binary ---
    print("Step 2: Uploading file binary...")
    try:
        with open(file_path, "rb") as file_content:
            requests.post(upload_url, data=file_content, timeout=120).raise_for_status()
        print("File binary uploaded.")

    except OSError as e:
        print(f"File Error in Step 2: {e}")
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"Network Error in Step 2: {e}")
        sys.exit(1)

    # --- Step 3: Complete upload ---
    print("Step 3: Completing file upload...")
    data_complete = {
        "files": [{"id": file_id, "title": file_name}],
        "channel_ids": [channel_id]
    }

    try:
        response_complete = requests.post(
            "https://slack.com/api/files.completeUploadExternal",
            headers=headers_auth,
            json=data_complete,
            timeout=30
        )
        response_complete.raise_for_status()

        if response_complete.json().get("ok"):
            print("File processing started.")

            # --- Step 4: Force Visibility (Post Link) ---
            print("Step 4: Posting file link to channel/thread...")

            # Get Permalink
            info_resp = requests.get(
                "https://slack.com/api/files.info",
                headers=headers_auth,
                params={"file": file_id},
                timeout=30
            )
            permalink = info_resp.json().get("file", {}).get("permalink")

            if permalink:
                post_data = {
                    "channel": channel_id,
                    "text": f"{initial_comment}\n<{permalink}|Download Report>"
                }
                if thread_ts:
                    post_data["thread_ts"] = thread_ts
                    if broadcast:
                        post_data["reply_broadcast"] = True

                requests.post(
                    "https://slack.com/api/chat.postMessage",
                    headers=headers_auth,
                    json=post_data,
                    timeout=30
                )
                print(f"Success! Link posted to {channel_id} (Thread: {thread_ts}, Broadcast: {broadcast})")
            else:
                print("Warning: Could not retrieve file permalink.")

        else:
            print(f"Error completing upload: {response_complete.json().get('error')}")
            sys.exit(1)

    except requests.exceptions.RequestException as e:
        print(f"Network Error in Step 3/4: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected Error in Step 3/4: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Upload quota report to Slack.")
    parser.add_argument("-f", "--file", help="Path to the file to upload.", required=True)
    parser.add_argument("-m", "--comment", help="Initial comment.", default="Quota Report")
    # Token argument removed; uses SLACK_TOKEN env var
    parser.add_argument("-c", "--channel", help="Slack Channel ID.", required=True)
    parser.add_argument("--thread_ts", help="Thread timestamp.", default=None)
    parser.add_argument("--broadcast", action="store_true", help="Broadcast to channel.")

    args = parser.parse_args()

    upload_file_to_slack(args.file, args.comment, args.channel, args.thread_ts, args.broadcast)

if __name__ == "__main__":
    main()
