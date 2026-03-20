#!/usr/bin/env python3
"""
Debug LLM Proxy Server for AI After Effects
============================================
Mimics the OpenRouter API so you (or an AI assistant in Cursor) can act as the LLM.

How it works:
  1. App sends POST /api/v1/chat/completions → server saves request to .debug_llm/request.json
  2. You read .debug_llm/request.json to see what the app sent
  3. You write your response to .debug_llm/response.json
  4. Server picks it up and returns it to the app in OpenRouter-compatible format

Response format (write to .debug_llm/response.json):
  Simple text response:
    {"text": "Hello! I've created a red rectangle."}

  Text + scene commands:
    {"text": "Here's your rectangle!", "actions": [{"type": "createObject", ...}]}

  Full OpenRouter format (advanced):
    {"id": "debug-1", "choices": [{"message": {"role": "assistant", "content": "..."}, "finish_reason": "stop"}]}

  Tool calls (for agent loop):
    {"tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "query_objects", "arguments": "{\"type\":\"text\"}"}}]}

Usage:
  python3 debug_server.py          # Start on port 8765
  python3 debug_server.py --port 9000  # Custom port
"""

import http.server
import json
import os
import sys
import time
import uuid
import argparse
from pathlib import Path
from urllib.parse import urlparse
from datetime import datetime

EXCHANGE_DIR = Path(__file__).parent / ".debug_llm"
REQUEST_FILE = EXCHANGE_DIR / "request.json"
RESPONSE_FILE = EXCHANGE_DIR / "response.json"
STATUS_FILE = EXCHANGE_DIR / "status.txt"
REQUEST_SUMMARY_FILE = EXCHANGE_DIR / "request_summary.txt"

POLL_INTERVAL = 0.5  # seconds
TIMEOUT = 600  # 10 minutes max wait


def ensure_exchange_dir():
    EXCHANGE_DIR.mkdir(exist_ok=True)
    if RESPONSE_FILE.exists():
        RESPONSE_FILE.unlink()
    STATUS_FILE.write_text("IDLE")


def extract_request_summary(body: dict) -> str:
    """Extract a human-readable summary of the request."""
    lines = []
    lines.append(f"═══ REQUEST at {datetime.now().strftime('%H:%M:%S')} ═══")
    lines.append(f"Model: {body.get('model', 'unknown')}")
    lines.append(f"Temperature: {body.get('temperature', '?')}")
    lines.append(f"Max tokens: {body.get('max_tokens', '?')}")

    messages = body.get("messages", [])
    lines.append(f"Messages: {len(messages)}")

    tools = body.get("tools", [])
    if tools:
        tool_names = [t.get("function", {}).get("name", "?") for t in tools]
        lines.append(f"Tools available: {', '.join(tool_names)}")
    
    tool_choice = body.get("tool_choice")
    if tool_choice:
        lines.append(f"Tool choice: {tool_choice}")

    lines.append("")

    for i, msg in enumerate(messages):
        role = msg.get("role", "?")
        content = msg.get("content", "")

        if isinstance(content, str):
            preview = content[:500] if role == "system" else content[:2000]
            if len(content) > len(preview):
                preview += f"\n... ({len(content)} total chars)"
        elif isinstance(content, list):
            text_parts = [p.get("text", "") for p in content if p.get("type") == "text"]
            image_parts = [p for p in content if p.get("type") == "image_url"]
            preview = "\n".join(text_parts)[:2000]
            if image_parts:
                preview += f"\n[{len(image_parts)} image(s) attached]"
        else:
            preview = str(content)[:500]

        # For tool call messages
        tool_calls = msg.get("tool_calls", [])
        if tool_calls:
            tc_summary = []
            for tc in tool_calls:
                fn = tc.get("function", {})
                tc_summary.append(f"  {fn.get('name', '?')}({fn.get('arguments', '')[:200]})")
            preview = "Tool calls:\n" + "\n".join(tc_summary)

        # For tool result messages
        tool_call_id = msg.get("tool_call_id")
        if tool_call_id:
            preview = f"[tool_call_id: {tool_call_id}]\n{preview}"

        lines.append(f"─── [{i}] {role.upper()} ───")
        lines.append(preview)
        lines.append("")

    return "\n".join(lines)


def wrap_simple_response(data: dict) -> dict:
    """Wrap a simple response dict into OpenRouter API format."""

    # Already in OpenRouter format
    if "choices" in data:
        return data

    response_id = f"debug-{uuid.uuid4().hex[:8]}"

    # Tool calls response
    if "tool_calls" in data and data["tool_calls"]:
        tool_calls_formatted = []
        for i, tc in enumerate(data["tool_calls"]):
            tool_calls_formatted.append({
                "id": tc.get("id", f"call_{uuid.uuid4().hex[:8]}"),
                "type": "function",
                "function": {
                    "name": tc["function"]["name"],
                    "arguments": tc["function"]["arguments"] if isinstance(tc["function"]["arguments"], str) else json.dumps(tc["function"]["arguments"])
                }
            })
        return {
            "id": response_id,
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": data.get("text"),
                    "tool_calls": tool_calls_formatted
                },
                "finish_reason": "tool_calls"
            }]
        }

    # Text + optional scene actions
    text = data.get("text", "")
    actions = data.get("actions")

    if actions:
        content = json.dumps({
            "message": text,
            "actions": actions
        })
    else:
        content = text

    return {
        "id": response_id,
        "choices": [{
            "message": {
                "role": "assistant",
                "content": content,
                "tool_calls": None
            },
            "finish_reason": "stop"
        }]
    }


class DebugProxyHandler(http.server.BaseHTTPRequestHandler):

    def do_POST(self):
        path = urlparse(self.path).path

        if path == "/api/v1/chat/completions":
            self.handle_chat_completion()
        else:
            self.send_error(404, f"Not found: {path}")

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/health":
            self.send_json(200, {"status": "ok", "mode": "debug_proxy"})
        elif path == "/api/v1/models":
            self.handle_models()
        else:
            self.send_error(404, f"Not found: {path}")

    def handle_models(self):
        self.send_json(200, {
            "data": [{
                "id": "debug/cursor-proxy",
                "name": "Debug Cursor Proxy",
                "context_length": 200000,
                "pricing": {"prompt": "0", "completion": "0"}
            }]
        })

    def handle_chat_completion(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body_bytes = self.rfile.read(content_length)

        try:
            body = json.loads(body_bytes)
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            return

        request_num = int(time.time() * 1000)

        # Save full request
        REQUEST_FILE.write_text(json.dumps(body, indent=2, ensure_ascii=False))

        # Save human-readable summary
        summary = extract_request_summary(body)
        REQUEST_SUMMARY_FILE.write_text(summary)

        # Remove old response
        if RESPONSE_FILE.exists():
            RESPONSE_FILE.unlink()

        STATUS_FILE.write_text("WAITING")

        # Print to server console
        messages = body.get("messages", [])
        user_msgs = [m for m in messages if m.get("role") == "user"]
        last_user = user_msgs[-1] if user_msgs else None
        user_preview = ""
        if last_user:
            content = last_user.get("content", "")
            if isinstance(content, str):
                user_preview = content[:100]
            elif isinstance(content, list):
                for part in content:
                    if part.get("type") == "text":
                        user_preview = part.get("text", "")[:100]
                        break
        
        tools = body.get("tools", [])
        tool_names = [t.get("function", {}).get("name", "?") for t in tools] if tools else []
        
        print(f"\n{'='*60}")
        print(f"📨 REQUEST #{request_num}")
        print(f"   Model: {body.get('model', '?')}")
        print(f"   Messages: {len(messages)}")
        if tool_names:
            print(f"   Tools: {', '.join(tool_names)}")
        print(f"   User: \"{user_preview}\"")
        print(f"   → Waiting for response at: {RESPONSE_FILE}")
        print(f"{'='*60}")

        # Poll for response
        start_time = time.time()
        while time.time() - start_time < TIMEOUT:
            if RESPONSE_FILE.exists():
                try:
                    response_text = RESPONSE_FILE.read_text()
                    response_data = json.loads(response_text)
                    RESPONSE_FILE.unlink()
                    STATUS_FILE.write_text("IDLE")

                    api_response = wrap_simple_response(response_data)
                    elapsed = time.time() - start_time

                    print(f"\n✅ Response received after {elapsed:.1f}s")
                    content_preview = ""
                    if api_response.get("choices"):
                        msg = api_response["choices"][0].get("message", {})
                        c = msg.get("content", "")
                        if c:
                            content_preview = (c[:100] if isinstance(c, str) else str(c)[:100])
                        tc = msg.get("tool_calls")
                        if tc:
                            content_preview = f"[{len(tc)} tool call(s)]"
                    print(f"   Preview: {content_preview}")

                    self.send_json(200, api_response)
                    return
                except (json.JSONDecodeError, Exception) as e:
                    print(f"⚠️  Error reading response: {e}")
                    time.sleep(POLL_INTERVAL)
                    continue

            time.sleep(POLL_INTERVAL)

        # Timeout
        STATUS_FILE.write_text("TIMEOUT")
        print(f"\n⏰ TIMEOUT after {TIMEOUT}s — no response provided")
        self.send_json(500, {
            "error": {
                "message": "Debug proxy timeout: no response was provided within the time limit.",
                "type": "timeout"
            }
        })

    def send_json(self, status_code: int, data: dict):
        response_bytes = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response_bytes)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(response_bytes)

    def log_message(self, format, *args):
        # Suppress default access logs for cleaner output
        pass


def main():
    parser = argparse.ArgumentParser(description="Debug LLM Proxy for AI After Effects")
    parser.add_argument("--port", type=int, default=8765, help="Port to listen on (default: 8765)")
    args = parser.parse_args()

    ensure_exchange_dir()

    server = http.server.HTTPServer(("127.0.0.1", args.port), DebugProxyHandler)
    print(f"""
╔══════════════════════════════════════════════════════════════╗
║         AI After Effects — Debug LLM Proxy Server           ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  Endpoint: http://localhost:{args.port}/api/v1/chat/completions    ║
║                                                              ║
║  Exchange dir: {str(EXCHANGE_DIR):<44s}║
║                                                              ║
║  How it works:                                               ║
║  1. App sends request → saved to .debug_llm/request.json     ║
║  2. Read request_summary.txt for a quick overview            ║
║  3. Write your response to .debug_llm/response.json          ║
║  4. Server returns it to the app                             ║
║                                                              ║
║  Response format examples:                                   ║
║    Simple:  {{"text": "Hello!"}}                               ║
║    Actions: {{"text": "Done!", "actions": [...]}}              ║
║    Tools:   {{"tool_calls": [{{"id":"c1", "type":"function",   ║
║              "function":{{"name":"...", "arguments":"..."}}}}]}} ║
║                                                              ║
║  Press Ctrl+C to stop                                        ║
╚══════════════════════════════════════════════════════════════╝
""")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped.")
        STATUS_FILE.write_text("STOPPED")
        server.server_close()


if __name__ == "__main__":
    main()
