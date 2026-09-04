import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from prototype.port_tools import add_alias, detect_framework, endpoint_summary, group_services, load_route_state, parse_endpoint, parse_http_response, project_candidates_from_command, project_from_command, redis_candidate, redis_response, relevance, remove_alias, validate_alias


class EndpointParsingTests(unittest.TestCase):
    def test_ipv4_loopback(self) -> None:
        self.assertEqual(
            parse_endpoint("127.0.0.1:5173"),
            {"address": "127.0.0.1", "port": 5173, "bindScope": "loopback"},
        )

    def test_ipv6_loopback(self) -> None:
        self.assertEqual(
            parse_endpoint("[::1]:8000"),
            {"address": "::1", "port": 8000, "bindScope": "loopback"},
        )

    def test_wildcard(self) -> None:
        self.assertEqual(parse_endpoint("*:4173")["bindScope"], "all-interfaces")


class HTTPParsingTests(unittest.TestCase):
    def test_valid_html_response(self) -> None:
        response = parse_http_response(
            b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<title> Vite App </title>"
        )
        self.assertIsNotNone(response)
        self.assertEqual(response["status"], 200)
        self.assertEqual(response["title"], "Vite App")

    def test_echoed_request_is_not_http_response(self) -> None:
        self.assertIsNone(
            parse_http_response(b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        )

    def test_redis_error_is_detected_as_database_protocol(self) -> None:
        self.assertTrue(redis_response(b"-ERR wrong number of arguments for 'get' command\r\n"))

    def test_redis_probe_requires_process_or_container_evidence(self) -> None:
        self.assertTrue(
            redis_candidate(
                {
                    "processName": "OrbStack Helper",
                    "management": {"image": "redis:7-alpine"},
                }
            )
        )
        self.assertFalse(redis_candidate({"processName": "node", "command": "vite"}))

    def test_next_body_marker(self) -> None:
        self.assertEqual(
            detect_framework(
                {"command": "node server"},
                b"HTTP/1.1 200 OK\r\n\r\n<script src='/_next/static/chunks/app.js'>",
            ),
            "next",
        )


class RelevanceTests(unittest.TestCase):
    def test_git_project_is_developer_relevant(self) -> None:
        result = relevance(
            {
                "project": {"root": "/tmp/project"},
                "command": "/usr/bin/python3 -m http.server",
            }
        )
        self.assertTrue(result["developerRelevant"])
        self.assertEqual(result["category"], "developer-project")

    def test_unattributed_http_server_is_not_default_relevant(self) -> None:
        result = relevance({"project": None, "command": "/System/App/internal-service"})
        self.assertFalse(result["developerRelevant"])
        self.assertEqual(result["category"], "unattributed-web-endpoint")

    def test_docker_published_port_is_developer_relevant(self) -> None:
        result = relevance(
            {
                "project": None,
                "command": "com.docker.backend",
                "management": {"source": "docker", "containerName": "web"},
            }
        )
        self.assertTrue(result["developerRelevant"])
        self.assertEqual(result["category"], "developer-container")


class ProjectIdentityTests(unittest.TestCase):
    def test_absolute_script_path_recovers_project(self) -> None:
        project = project_from_command(
            "python3 {}/evaluation/fixtures/http_fixture.py".format(
                Path(__file__).resolve().parents[1]
            ),
            "/tmp",
        )
        self.assertIsNotNone(project)
        self.assertEqual(project["name"], "port-tools")

    def test_multiple_project_paths_are_ambiguous(self) -> None:
        candidates = project_candidates_from_command(
            "tool {}/README.md {}/AGENTS.md".format(
                Path(__file__).resolve().parents[1],
                Path(__file__).resolve().parents[2] / "Boonray",
            ),
            "/tmp",
        )
        self.assertEqual(len(candidates), 2)


class GroupingTests(unittest.TestCase):
    def service(self, service_id: str, port: int, root: str) -> dict:
        return {
            "id": service_id,
            "listener": {"port": port},
            "process": {"pid": port, "name": "node"},
            "project": {"root": root, "name": "studio", "branch": "main"},
        }

    def test_two_ports_in_one_worktree_share_one_group(self) -> None:
        groups = group_services(
            [
                self.service("a", 4317, "/workspace/studio"),
                self.service("b", 4319, "/workspace/studio"),
            ]
        )
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["serviceIds"], ["a", "b"])

    def test_two_worktrees_remain_separate(self) -> None:
        groups = group_services(
            [
                self.service("a", 4317, "/workspace/studio"),
                self.service("b", 4319, "/workspace/studio-feature"),
            ]
        )
        self.assertEqual(len(groups), 2)

    def test_group_id_survives_pid_and_port_change(self) -> None:
        first = self.service("a", 4317, "/workspace/studio")
        first["process"]["pid"] = 100
        second = self.service("b", 9000, "/workspace/studio")
        second["process"]["pid"] = 200
        self.assertEqual(group_services([first])[0]["id"], group_services([second])[0]["id"])


class EndpointSummaryTests(unittest.TestCase):
    def test_script_explains_untitled_endpoint(self) -> None:
        summary = endpoint_summary(
            {
                "process": {"command": "node scripts/live-bridge.mjs"},
                "observation": {
                    "http": {"status": 404, "contentType": None, "title": None},
                    "evidence": [{"kind": "valid-http-response"}],
                },
            }
        )
        self.assertEqual(summary, "live-bridge.mjs · HTTP 404")


class RouteStateTests(unittest.TestCase):
    def test_alias_state_is_atomic_and_rejects_collision(self) -> None:
        with TemporaryDirectory() as directory:
            state = Path(directory) / "routes.json"
            added = add_alias(state, "Todo-App", 5173, "rewrite")
            self.assertEqual(added["alias"], "todo-app")
            self.assertEqual(load_route_state(state)["routes"]["todo-app"]["port"], 5173)
            with self.assertRaises(ValueError):
                add_alias(state, "todo-app", 8000, "rewrite")
            self.assertTrue(remove_alias(state, "todo-app")["removed"])
            self.assertEqual(load_route_state(state)["routes"], {})

    def test_alias_validation(self) -> None:
        self.assertEqual(validate_alias("studio-2"), "studio-2")
        for invalid in ("-studio", "studio-", "two.words", "space name", ""):
            with self.assertRaises(ValueError):
                validate_alias(invalid)


if __name__ == "__main__":
    unittest.main()
