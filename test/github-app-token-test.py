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

    def test_api_error_message_is_one_line(self):
        self.server.status = 401
        self.server.payload = {"message": "Bad\ncredentials"}
        result = self.run_cli()
        self.assertEqual(result.returncode, 3)
        self.assertEqual(len(result.stderr.strip().splitlines()), 1)
        self.assertIn("Bad credentials", result.stderr)

    def test_json_prints_api_response(self):
        result = self.run_cli("json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), self.server.payload)

    def test_repo_scope_uses_bare_names(self):
        result = self.run_cli(
            "token", "--repo", "dzmoore/devcontainer-base",
            "--repo", "other/example",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.server.requests[0]["body"]["repositories"],
            ["devcontainer-base", "example"],
        )

    def test_repo_scope_strips_git_suffix(self):
        result = self.run_cli("token", "--repo", "owner/repo.git")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.server.requests[0]["body"]["repositories"], ["repo"])

    def test_repo_scope_rejects_more_than_500(self):
        args = ["token"]
        for i in range(501):
            args += ["--repo", f"repo{i}"]
        result = self.run_cli(*args)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_permission_scope(self):
        result = self.run_cli(
            "token", "--permission", "contents=write",
            "--permission", "pull_requests=read",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.server.requests[0]["body"]["permissions"],
            {"contents": "write", "pull_requests": "read"},
        )

    def test_check_hides_token(self):
        result = self.run_cli("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OK", result.stdout)
        self.assertIn("2026-11-15T13:00:00Z", result.stdout)
        self.assertIn("permissions: contents=write", result.stdout)
        self.assertNotIn("ghs_test_token", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_check_sorts_permissions(self):
        self.server.payload["permissions"] = {"pull_requests": "read", "contents": "write"}
        result = self.run_cli("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("permissions: contents=write, pull_requests=read", result.stdout)

    def test_check_omits_empty_permissions(self):
        self.server.payload["permissions"] = {}
        result = self.run_cli("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("permissions:", result.stdout)

    def test_repo_scope_rejects_extra_path(self):
        result = self.run_cli("token", "--repo", "owner/repo/extra")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("repo", result.stderr.lower())
        self.assertEqual(self.server.requests, [])

    def test_admin_permission_is_accepted(self):
        result = self.run_cli("token", "--permission", "repository_projects=admin")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.server.requests[0]["body"]["permissions"],
            {"repository_projects": "admin"},
        )

    def test_invalid_permission_exits_2(self):
        result = self.run_cli("token", "--permission", "contents=execute")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("permission", result.stderr.lower())
        self.assertEqual(self.server.requests, [])

    def test_exec_sets_token_environment(self):
        code = (
            "import json, os; print(json.dumps({k: os.environ.get(k) for k in "
            "['GH_HOST','GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN']}))"
        )
        result = self.run_cli("exec", "--", "python3", "-c", code)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "GH_HOST": "github.com",
            "GH_TOKEN": "ghs_test_token",
            "GITHUB_TOKEN": "ghs_test_token",
            "GH_ENTERPRISE_TOKEN": None,
            "GITHUB_ENTERPRISE_TOKEN": None,
        })

    def test_exec_propagates_child_status(self):
        result = self.run_cli("exec", "--", "python3", "-c", "raise SystemExit(7)")
        self.assertEqual(result.returncode, 7)

    def test_exec_missing_binary_exits_127(self):
        result = self.run_cli("exec", "--", "definitely-not-a-real-command-xyz")
        self.assertEqual(result.returncode, 127)
        self.assertEqual(result.stdout, "")

    def test_git_credential_get_returns_token(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="protocol=https\nhost=github.com\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "username=x-access-token\npassword=ghs_test_token\n\n",
        )

    def test_git_credential_requires_host(self):
        result = self.run_cli("git-credential", "get", stdin="protocol=https\n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_git_credential_accepts_url(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="url=https://github.com/owner/repo\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "username=x-access-token\npassword=ghs_test_token\n\n",
        )

    def test_git_credential_rejects_http_url(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="url=http://github.com/owner/repo\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_git_credential_rejects_wrong_host_url(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="url=https://evil.example/owner/repo\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_git_credential_accepts_port_and_case(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="protocol=https\nhost=GitHub.com:443\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "username=x-access-token\npassword=ghs_test_token\n\n",
        )

    def test_git_credential_rejects_wrong_port(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="protocol=https\nhost=github.com:444\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_git_credential_ignores_other_host(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="protocol=https\nhost=evil.example\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_git_credential_rejects_http(self):
        result = self.run_cli(
            "git-credential", "get",
            stdin="protocol=http\nhost=github.com\n\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_exec_sets_gh_host_for_enterprise(self):
        self.write_env(GITHUB_SERVER_URL="https://ghe.example.com")
        code = (
            "import json, os; print(json.dumps({k: os.environ.get(k) for k in "
            "['GH_HOST','GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN']}))"
        )
        result = self.run_cli("exec", "--", "python3", "-c", code)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "GH_HOST": "ghe.example.com",
            "GH_TOKEN": None,
            "GITHUB_TOKEN": None,
            "GH_ENTERPRISE_TOKEN": "ghs_test_token",
            "GITHUB_ENTERPRISE_TOKEN": "ghs_test_token",
        })

    def test_exec_uses_standard_tokens_for_ghe_cloud(self):
        code = (
            "import json, os; print(json.dumps({k: os.environ.get(k) for k in "
            "['GH_HOST','GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN']}))"
        )
        for host in ("octocorp.ghe.com", "github.localhost"):
            with self.subTest(host=host):
                self.server.reset()
                self.write_env(GITHUB_SERVER_URL=f"https://{host}")
                result = self.run_cli("exec", "--", "python3", "-c", code)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {
                    "GH_HOST": host,
                    "GH_TOKEN": "ghs_test_token",
                    "GITHUB_TOKEN": "ghs_test_token",
                    "GH_ENTERPRISE_TOKEN": None,
                    "GITHUB_ENTERPRISE_TOKEN": None,
                })

    def test_git_credential_store_and_erase_do_nothing(self):
        for action in ("store", "erase"):
            result = self.run_cli(
                "git-credential", action,
                stdin="protocol=https\nhost=github.com\n\n",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
        self.assertEqual(self.server.requests, [])

    def test_gh_app_wrapper_passes_token_to_gh(self):
        fake_bin = pathlib.Path(self.tmp.name) / "fake-bin"
        fake_bin.mkdir(exist_ok=True)
        fake_gh = fake_bin / "gh"
        fake_gh.write_text(
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$GH_TOKEN\"\nprintf '%s\\n' \"$*\"\n"
        )
        fake_gh.chmod(0o755)
        link_bin = pathlib.Path(self.tmp.name) / "link-bin"
        link_bin.mkdir(exist_ok=True)
        (link_bin / "gh-app").symlink_to(REPO / ".devcontainer" / "bin" / "gh-app")
        (link_bin / "gh-app-token").symlink_to(REPO / ".devcontainer" / "bin" / "gh-app-token")
        env = {
            k: v for k, v in os.environ.items()
            if not k.startswith("GITHUB_APP_")
            and k not in ("GITHUB_API_URL", "GITHUB_SERVER_URL", "GITHUB_API_VERSION",
                          "GH_TOKEN", "GH_HOST", "GH_ENTERPRISE_TOKEN",
                          "GITHUB_ENTERPRISE_TOKEN", "GITHUB_TOKEN")
        }
        env.update({
            "GITHUB_APP_ENV_FILE": str(self.env_file),
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
        })
        result = subprocess.run(
            [str(link_bin / "gh-app"), "pr", "list"],
            text=True, capture_output=True, env=env, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ghs_test_token\npr list\n")


if __name__ == "__main__":
    unittest.main()
