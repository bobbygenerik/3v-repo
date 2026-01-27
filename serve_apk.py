#!/usr/bin/env python3
import argparse
import http.server
import os
import socketserver


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve Flutter APK directory over HTTP")
    parser.add_argument(
        "-p",
        "--port",
        type=int,
        default=7575,
        help="Port to listen on (default: 7575)",
    )
    parser.add_argument(
        "-d",
        "--dir",
        default=os.path.join(
            os.path.dirname(__file__),
            "tres_flutter",
            "build",
            "app",
            "outputs",
            "flutter-apk",
        ),
        help="Directory to serve (default: tres_flutter/build/app/outputs/flutter-apk)",
    )
    args = parser.parse_args()

    directory = os.path.abspath(args.dir)
    if not os.path.isdir(directory):
        raise SystemExit(f"Directory does not exist: {directory}")

    handler = http.server.SimpleHTTPRequestHandler

    print(f"Serving {directory} on http://0.0.0.0:{args.port}")
    with socketserver.TCPServer(("0.0.0.0", args.port), handler) as httpd:
        os.chdir(directory)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
