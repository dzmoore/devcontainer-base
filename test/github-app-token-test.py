#!/usr/bin/env python3
"""End-to-end tests for .devcontainer/bin/gh-app-token."""

import base64
import json
import os
import pathlib
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

REPO = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = REPO / ".devcontainer" / "bin" / "gh-app-token"


def b64decode(segment):
    return base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4))


def verify_jwt(token, public_key):
    header_b64, payload_b64, sig_b64 = token.split(".")
    assert json.loads(b64decode(header_b64)) == {"alg": "RS256", "typ": "JWT"}
    with tempfile.TemporaryDirectory() as tmp:
        data = pathlib.Path(tmp) / "data"
        sig = pathlib.Path(tmp) / "sig"
        data.write_bytes(f"{header_b64}.{payload_b64}".encode())
        sig.write_bytes(b64decode(sig_b64))
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", str(public_key),
             "-signature", str(sig), str(data)],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, result.stderr
    return json.loads(b64decode(payload_b64))


class FakeGitHubHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        fake = self.server.fake
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        fake.requests.append({
            "method": self.command,
            "path": self.path,
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "body": json.loads(body) if body else None,
        })
        data = fake.raw_payload if fake.raw_payload is not None else json.dumps(fake.payload).encode()
        self.send_response(fake.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class FakeGitHubServer:
    def __init__(self):
        self.status = 201
        self.raw_payload = None
        self.payload = {
            "token": "ghs_test_token",
            "expires_at": "2026-11-15T13:00:00Z",
            "permissions": {"contents": "write"},
        }
        self.requests = []
        self.httpd = HTTPServer(("127.0.0.1", 0), FakeGitHubHandler)
        self.httpd.fake = self
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    @property
    def api_url(self):
        return f"http://127.0.0.1:{self.httpd.server_port}"

    def start(self):
        self.thread.start()

    def reset(self):
        self.status = 201
        self.raw_payload = None
        self.payload = {
            "token": "ghs_test_token",
            "expires_at": "2026-11-15T13:00:00Z",
            "permissions": {"contents": "write"},
        }
        self.requests.clear()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)


class GhAppTokenTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(cls.tmp.name)
        cls.key = root / "app.pem"
        cls.pub = root / "app.pub"
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA",
             "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(cls.key)],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", str(cls.key), "-pubout", "-out", str(cls.pub)],
            check=True, capture_output=True,
        )
        cls.server = FakeGitHubServer()
        cls.server.start()
        cls.env_file = root / ".env"

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()
        cls.tmp.cleanup()

    def setUp(self):
        self.server.reset()
        self.write_env()

    def write_env(self, **overrides):
        values = {
            "GITHUB_APP_CLIENT_ID": "Iv1.test",
            "GITHUB_APP_INSTALLATION_ID": "42",
            "GITHUB_APP_PRIVATE_KEY_FILE": str(self.key),
            "GITHUB_API_URL": self.server.api_url,
        }
        values.update(overrides)
        self.env_file.write_text("".join(f"{k}={v}\n" for k, v in values.items()))

    def run_cli(self, *args, env=None, stdin=None, with_env_file=True):
        base = {
            k: v for k, v in os.environ.items()
            if not k.startswith("GITHUB_APP_")
            and k not in ("GITHUB_API_URL", "GITHUB_SERVER_URL", "GITHUB_API_VERSION",
                          "GH_TOKEN", "GH_HOST", "GH_ENTERPRISE_TOKEN",
                          "GITHUB_ENTERPRISE_TOKEN", "GITHUB_TOKEN")
        }
        base.update(env or {})
        cmd = [str(SCRIPT)]
        if with_env_file:
            cmd += ["--env-file", str(self.env_file)]
        cmd += list(args)
        return subprocess.run(
            cmd, input=stdin, text=True, capture_output=True, env=base, timeout=20,
        )

    def test_default_command_prints_token_only(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ghs_test_token\n")
        self.assertEqual(result.stderr, "")
        self.assertEqual(len(self.server.requests), 1)
        request = self.server.requests[0]
        self.assertEqual(request["method"], "POST")
        self.assertEqual(request["path"], "/app/installations/42/access_tokens")
        self.assertEqual(request["body"], {})
        self.assertEqual(request["headers"]["accept"], "application/vnd.github+json")
        self.assertEqual(request["headers"]["x-github-api-version"], "2026-03-10")
        self.assertEqual(request["headers"]["user-agent"], "gh-app-token")

    def test_jwt_is_valid_and_uses_client_id(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        auth = self.server.requests[0]["headers"]["authorization"]
        claims = verify_jwt(auth.removeprefix("Bearer "), self.pub)
        now = int(time.time())
        self.assertEqual(claims["iss"], "Iv1.test")
        self.assertLessEqual(claims["iat"], now)
        self.assertGreater(claims["exp"], now + 480)
        self.assertLessEqual(claims["exp"], now + 600)

    def test_env_file_parsing_and_environment_precedence(self):
        self.env_file.write_bytes(
            b"# comment\r\n"
            b'export GITHUB_APP_CLIENT_ID="Iv1.file"\r\n'
            b"GITHUB_APP_INSTALLATION_ID='42'\r\n"
            + f"GITHUB_APP_PRIVATE_KEY_FILE={self.key}\r\n".encode()
            + f"GITHUB_API_URL={self.server.api_url}\r\n".encode()
        )
        result = self.run_cli(env={"GITHUB_APP_CLIENT_ID": "Iv1.env"})
        self.assertEqual(result.returncode, 0, result.stderr)
        auth = self.server.requests[0]["headers"]["authorization"]
        claims = verify_jwt(auth.removeprefix("Bearer "), self.pub)
        self.assertEqual(claims["iss"], "Iv1.env")

    def test_env_file_from_environment(self):
        result = self.run_cli(
            env={"GITHUB_APP_ENV_FILE": str(self.env_file)},
            with_env_file=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ghs_test_token\n")

    def test_env_file_option_overrides_environment(self):
        bad = pathlib.Path(self.tmp.name) / "bad.env"
        bad.write_text(
            "GITHUB_APP_CLIENT_ID=Iv1.bad\n"
            "GITHUB_APP_INSTALLATION_ID=1\n"
            f"GITHUB_APP_PRIVATE_KEY_FILE={self.key}\n"
            f"GITHUB_API_URL={self.server.api_url}\n"
        )
        result = self.run_cli(env={"GITHUB_APP_ENV_FILE": str(bad)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ghs_test_token\n")
        auth = self.server.requests[0]["headers"]["authorization"]
        self.assertEqual(verify_jwt(auth.removeprefix("Bearer "), self.pub)["iss"], "Iv1.test")

    def test_default_env_file_and_key(self):
        home = pathlib.Path(self.tmp.name) / "home"
        config_dir = home / ".dc" / "github"
        config_dir.mkdir(parents=True)
        (config_dir / "app.pem").write_bytes(self.key.read_bytes())
        (config_dir / ".env").write_text(
            "GITHUB_APP_CLIENT_ID=Iv1.home\n"
            "GITHUB_APP_INSTALLATION_ID=42\n"
            f"GITHUB_API_URL={self.server.api_url}\n"
        )
        result = self.run_cli(env={"HOME": str(home)}, with_env_file=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        auth = self.server.requests[0]["headers"]["authorization"]
        self.assertEqual(verify_jwt(auth.removeprefix("Bearer "), self.pub)["iss"], "Iv1.home")

    def test_app_id_fallback(self):
        self.env_file.write_text(
            "GITHUB_APP_ID=Iv1.appid\n"
            "GITHUB_APP_INSTALLATION_ID=42\n"
            f"GITHUB_APP_PRIVATE_KEY_FILE={self.key}\n"
            f"GITHUB_API_URL={self.server.api_url}\n"
        )
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        auth = self.server.requests[0]["headers"]["authorization"]
        self.assertEqual(verify_jwt(auth.removeprefix("Bearer "), self.pub)["iss"], "Iv1.appid")

    def test_key_path_with_spaces(self):
        spaced = pathlib.Path(self.tmp.name) / "dir with space"
        spaced.mkdir(exist_ok=True)
        key = spaced / "app.pem"
        key.write_bytes(self.key.read_bytes())
        self.write_env(GITHUB_APP_PRIVATE_KEY_FILE=f'"{key}"')
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_env_line_exits_2(self):
        self.env_file.write_text("not a valid line\n")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("invalid line", result.stderr.lower())

    def test_invalid_env_line_does_not_echo_value(self):
        self.env_file.write_text("GITHUB_TOKEN ghp_super_secret\n")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("ghp_super_secret", result.stderr)

    def test_invalid_utf8_env_file_exits_2(self):
        self.env_file.write_bytes(b"\xff\xfe")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertIn(str(self.env_file), result.stderr)

    def test_invalid_api_url_exits_2(self):
        self.write_env(GITHUB_API_URL="http://example.com")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("GITHUB_API_URL", result.stderr)
        self.assertEqual(self.server.requests, [])

    def test_invalid_api_ports_exit_2(self):
        for value in ("https://example.com:bad", "https://example.com:99999"):
            with self.subTest(value=value):
                self.server.reset()
                self.write_env(GITHUB_API_URL=value)
                result = self.run_cli()
                self.assertEqual(result.returncode, 2)
                self.assertIn("GITHUB_API_URL", result.stderr)
                self.assertEqual(self.server.requests, [])

    def test_invalid_server_url_exits_2(self):
        self.write_env(GITHUB_SERVER_URL="http://example.com")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertIn("GITHUB_SERVER_URL", result.stderr)
        self.assertEqual(self.server.requests, [])

    def test_empty_api_version_omits_header(self):
        self.write_env(GITHUB_API_VERSION="")
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("x-github-api-version", self.server.requests[0]["headers"])

    def test_missing_client_id_exits_2(self):
        self.write_env(GITHUB_APP_CLIENT_ID="")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("GITHUB_APP_CLIENT_ID", result.stderr)

    def test_missing_key_exits_2(self):
        self.write_env(GITHUB_APP_PRIVATE_KEY_FILE=str(self.key) + ".missing")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("app.pem.missing", result.stderr)

    def test_network_error_exits_3(self):
        self.write_env(GITHUB_API_URL="http://127.0.0.1:1")
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("GitHub API request failed", result.stderr)

    def test_malformed_api_response_exits_3(self):
        self.server.raw_payload = b"not json"
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("unexpected response", result.stderr)
        self.assertNotIn("not json", result.stderr)

    def test_invalid_utf8_api_response_exits_3(self):
        self.server.raw_payload = b"\xff"
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("unexpected response", result.stderr)

    def test_non_dict_api_response_exits_3(self):
        self.server.payload = []
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("unexpected response", result.stderr)

    def test_missing_expires_at_response_exits_3(self):
        self.server.payload = {"token": "ghs_test_token"}
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("unexpected response", result.stderr)

    def test_missing_token_response_exits_3(self):
        self.server.payload = {"expires_at": "2026-11-15T13:00:00Z"}
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("unexpected response", result.stderr)

    def test_api_error_exits_3_without_token(self):
        self.server.status = 401
        self.server.payload = {"message": "Bad credentials"}
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("HTTP 401", result.stderr)
        self.assertIn("Bad credentials", result.stderr)
        self.assertNotIn("ghs_test_token", result.stderr)


if __name__ == "__main__":
    unittest.main()
