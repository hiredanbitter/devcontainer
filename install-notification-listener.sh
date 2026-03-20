cat > ~/claude-notify-listener.sh << 'EOF'
#!/bin/bash
PIPE=~/claude-notify.pipe
[ -p "$PIPE" ] || mkfifo "$PIPE"

while true; do
  if read -r line < "$PIPE"; then
    EVENT=$(echo "$line" | jq -r '.event // "Done"')
    MSG=$(echo "$line"   | jq -r '.message // "Task complete"')
    osascript -e "display notification \"$MSG\" with title \"Claude Code\" subtitle \"$EVENT\""
  fi
done
EOF
chmod +x ~/claude-notify-listener.sh

cat > ~/Library/LaunchAgents/com.claudecode.notify.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.claudecode.notify</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOUR_USERNAME/claude-notify-listener.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
EOF

# Replace YOUR_USERNAME, then load it:
launchctl load ~/Library/LaunchAgents/com.claudecode.notify.plist