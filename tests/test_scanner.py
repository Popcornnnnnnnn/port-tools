import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from prototype.port_tools import (
    add_alias,
    application_metadata,
    apply_docker_identity,
    build_stop_plan,
    descendant_pids,
    detect_framework,
    endpoint_summary,
    group_services,
    load_route_state,
    parse_endpoint,
    parse_http_response,
    project_candidates_from_command,
    project_from_command,
    redis_candidate,
    redis_response,
    relevance,
    remove_alias,
    validate_alias,
)


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

    def test_nearest_application_manifest_below_project_root(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "apps" / "web"
            app.mkdir(parents=True)
            (app / "package.json").write_text(
                '{"name":"@fixture/web"}\n', encoding="utf-8"
            )
            application = application_metadata(str(app), "node server.js", str(root))
            self.assertEqual(application["root"], str(app.resolve()))
            self.assertEqual(application["relativePath"], "apps/web")
            self.assertEqual(application["name"], "@fixture/web")

    def test_unlabeled_docker_does_not_inherit_host_process_project(self) -> None:
        host_project = {"root": "/workspace/unrelated"}
        listener = {"project": host_project, "projectEvidence": "cwd"}
        apply_docker_identity(
            listener,
            {
                "source": "docker",
                "containerId": "abcdef123456",
                "containerName": "web",
                "labels": {},
            },
        )
        self.assertIsNone(listener["project"])
        self.assertEqual(listener["projectEvidence"], "docker-unattributed")
        self.assertEqual(listener["hostProcessProject"], host_project)


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

    def test_two_apps_in_one_worktree_remain_separate(self) -> None:
        first = self.service("a", 4317, "/workspace/monorepo")
        first["application"] = {"root": "/workspace/monorepo/apps/a", "name": "app-a"}
        second = self.service("b", 4319, "/workspace/monorepo")
        second["application"] = {"root": "/workspace/monorepo/apps/b", "name": "app-b"}
        groups = group_services([first, second])
        self.assertEqual([group["label"] for group in groups], ["app-a", "app-b"])

    def test_unlabeled_docker_name_survives_container_id_change(self) -> None:
        first = self.service("a", 51753, "/unused")
        first["project"] = None
        first["management"] = {
            "source": "docker",
            "containerName": "local-web",
            "containerId": "old-id",
        }
        second = self.service("b", 61753, "/unused")
        second["project"] = None
        second["management"] = {
            "source": "docker",
            "containerName": "local-web",
            "containerId": "new-id",
        }
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
            self.assertEqual(load_route_state(state)["routes"]["todo-app"]["scheme"], "http")
            with self.assertRaises(ValueError):
                add_alias(state, "todo-app", 8000, "rewrite")
            self.assertTrue(remove_alias(state, "todo-app")["removed"])
            self.assertEqual(load_route_state(state)["routes"], {})

    def test_alias_validation(self) -> None:
        self.assertEqual(validate_alias("studio-2"), "studio-2")
        for invalid in ("-studio", "studio-", "two.words", "space name", ""):
            with self.assertRaises(ValueError):
                validate_alias(invalid)


class StopPlanTests(unittest.TestCase):
    def service(self, owner="forge", project_root="/workspace/app", management="unmanaged") -> dict:
        return {
            "id": "service-1",
            "listener": {"address": "127.0.0.1", "port": 5173, "bindScope": "loopback"},
            "process": {
                "pid": 100,
                "parentPid": 50,
                "name": "node",
                "owner": owner,
                "command": "node vite",
                "cwd": project_root,
            },
            "project": {"root": project_root} if project_root else None,
            "management": {"source": management},
        }

    def processes(self) -> dict:
        return {
            100: {
                "pid": 100,
                "parentPid": 50,
                "owner": "forge",
                "name": "node",
                "command": "node vite",
                "projectRoot": "/workspace/app",
            },
            101: {
                "pid": 101,
                "parentPid": 100,
                "owner": "forge",
                "name": "worker",
                "projectRoot": "/workspace/app",
            },
            102: {
                "pid": 102,
                "parentPid": 100,
                "owner": "forge",
                "name": "shared-helper",
                "projectRoot": "/workspace/other",
            },
            103: {
                "pid": 103,
                "parentPid": 101,
                "owner": "other",
                "name": "foreign",
                "projectRoot": "/workspace/app",
            },
        }

    def test_descendant_walk_includes_nested_children(self) -> None:
        self.assertEqual(descendant_pids(100, self.processes()), [101, 102, 103])

    def test_eligible_plan_excludes_unproven_and_other_owner_children(self) -> None:
        plan = build_stop_plan(
            self.service(),
            self.processes(),
            [
                {"pid": 100, "address": "127.0.0.1", "port": 5173},
                {"pid": 101, "address": "127.0.0.1", "port": 5174},
                {"pid": 102, "address": "127.0.0.1", "port": 9999},
            ],
            "forge",
        )
        self.assertEqual(plan["decision"], "eligible")
        self.assertFalse(plan["signalSent"])
        self.assertEqual(plan["gracefulPlan"]["pids"], [101, 100])
        self.assertEqual(
            [listener["port"] for listener in plan["gracefulPlan"]["verifyListenersReleased"]],
            [5173, 5174],
        )
        self.assertEqual({item["pid"] for item in plan["exclusions"]}, {102, 103})
        self.assertFalse(plan["forcePlan"]["allowedInThisAction"])

    def test_sibling_application_child_is_excluded(self) -> None:
        service = self.service()
        service["application"] = {"root": "/workspace/app/apps/a"}
        processes = self.processes()
        processes[101]["applicationRoot"] = "/workspace/app/apps/b"
        plan = build_stop_plan(service, processes, [], "forge")
        exclusion = next(item for item in plan["exclusions"] if item["pid"] == 101)
        self.assertEqual(exclusion["reason"], "same-application ownership not established")

    def test_other_owner_is_refused(self) -> None:
        plan = build_stop_plan(self.service(owner="other"), self.processes(), [], "forge")
        self.assertEqual(plan["decision"], "refused")
        self.assertEqual(plan["gracefulPlan"]["pids"], [])

    def test_reused_pid_identity_is_refused(self) -> None:
        service = self.service()
        service["process"]["started"] = "original start"
        processes = self.processes()
        processes[100]["started"] = "replacement start"
        plan = build_stop_plan(service, processes, [], "forge")
        self.assertEqual(plan["decision"], "refused")
        self.assertIn("PID identity changed since the service was scanned", plan["reasons"])

    def test_docker_and_unattributed_targets_are_refused(self) -> None:
        docker = build_stop_plan(
            self.service(management="docker"), self.processes(), [], "forge"
        )
        unattributed = build_stop_plan(
            self.service(project_root=None), self.processes(), [], "forge"
        )
        self.assertEqual(docker["decision"], "refused")
        self.assertEqual(unattributed["decision"], "refused")

    def test_shared_runtime_is_refused_even_with_project_metadata(self) -> None:
        service = self.service()
        service["process"]["name"] = "com.docker.backend"
        service["process"]["command"] = "com.docker.backend serve"
        processes = self.processes()
        processes[100]["command"] = "com.docker.backend serve"
        plan = build_stop_plan(service, processes, [], "forge")
        self.assertEqual(plan["decision"], "refused")
        self.assertIn("target appears to be a shared or system runtime", plan["reasons"])


if __name__ == "__main__":
    unittest.main()
