import copy
import json
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]


class NativeServiceNamingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = TemporaryDirectory(prefix="port-tools-naming-")
        cls.addClassCleanup(cls.directory.cleanup)
        directory = Path(cls.directory.name)
        source = (REPO_ROOT / "native/PortTools/InventoryUI.swift").read_text()
        # Compile the actual production functions with the actual Codable models.
        functions = []
        for name in (
            "commandApplicationName",
            "containerServiceName",
            "serviceName",
            "isOpenablePage",
            "relatedServiceName",
            "serviceSearchText",
            "secondaryServiceName",
        ):
            match = re.search(rf"^func {name}\(.*?^\}}", source, re.M | re.S)
            if match is None:
                raise AssertionError(f"Missing production function: {name}")
            functions.append(match.group())
        naming_source = directory / "Naming.swift"
        naming_source.write_text(
            'import Foundation\nprivate let webClassifications = Set(["confirmed-web", "suspected-web"])\n'
            + "\n\n".join(functions)
        )
        main_source = directory / "main.swift"
        main_source.write_text("""
import Foundation
let data = FileHandle.standardInput.readDataToEndOfFile()
let services = try JSONDecoder().decode([ServiceRecord].self, from: data)
let names = services.map {
    [
        "page": serviceName($0),
        "related": relatedServiceName($0),
        "secondary": secondaryServiceName($0),
        "search": serviceSearchText($0),
    ]
}
FileHandle.standardOutput.write(try JSONEncoder().encode(names))
""")
        cls.executable = directory / "naming"
        subprocess.run([
            "xcrun", "swiftc", str(REPO_ROOT / "native/PortTools/Models.swift"),
            str(naming_source), str(main_source), "-o", str(cls.executable),
        ], check=True, capture_output=True, text=True)

    def setUp(self):
        self.service = {
            "id": "prometheus", "logicalId": "prometheus",
            "listener": {"address": "127.0.0.1", "port": 9090, "bindScope": "loopback"},
            "process": {
                "pid": 1, "name": "OrbStack Helper",
                "command": "/Applications/OrbStack.app/Contents/Frameworks/OrbStack Helper.app/Contents/MacOS/OrbStack Helper vmgr",
            },
            "management": {
                "source": "docker", "containerName": "network-monitor-prometheus",
                "labels": {"com.docker.compose.service": "prometheus"},
            },
            "observation": {
                "classification": "confirmed-web", "protocol": "http", "role": "page",
                "http": {"status": 302, "contentType": "text/html"}, "evidence": [],
            },
            "relevance": {"developerRelevant": True},
            "history": {"firstSeen": "", "lastSeen": "", "consecutiveProbeFailures": 0},
            "preferences": {"pinned": False, "ignored": False},
            "staleness": {"possiblyForgotten": False, "reasons": []},
        }

    @classmethod
    def names_for(cls, services):
        result = subprocess.run([str(cls.executable)], input=json.dumps(services),
                                check=True, capture_output=True, text=True)
        return json.loads(result.stdout)

    def assert_names(self, expected, related=None, secondary=None):
        actual = [{k: v for k, v in item.items() if k != "search"} for item in self.names_for([self.service])]
        self.assertEqual(actual, [{
            "page": expected,
            "related": related or expected,
            "secondary": secondary or expected,
        }])

    def test_redirect_without_title_uses_compose_service(self):
        self.assert_names("prometheus")
        self.service["observation"]["http"]["title"] = ""
        self.assert_names("prometheus")

    def test_title_and_custom_name_keep_precedence(self):
        self.service["observation"]["http"]["title"] = "Prometheus UI"
        self.assert_names("Prometheus UI")
        self.service["preferences"]["displayName"] = "My metrics"
        self.assert_names("My metrics", related="Prometheus UI", secondary="My metrics")
        del self.service["observation"]["http"]["title"]
        self.assert_names("My metrics", related="prometheus", secondary="My metrics")

    def test_container_name_when_compose_service_is_unavailable(self):
        for labels in ({}, None, {"com.docker.compose.service": " \n"}):
            with self.subTest(labels=labels):
                self.service["management"]["labels"] = labels
                self.assert_names("network-monitor-prometheus")
        del self.service["management"]["labels"]
        self.assert_names("network-monitor-prometheus")

    def test_container_name_without_compose_or_page_title(self):
        self.service["management"] = {"source": "docker", "containerName": "standalone-ui"}
        del self.service["observation"]["http"]
        self.assert_names("standalone-ui")

    def test_non_web_docker_listener_prefers_container_service_name(self):
        self.service["observation"] = {
            "classification": "non-web",
            "protocol": "tcp",
            "role": "listener",
            "evidence": [],
        }
        self.assert_names("prometheus")

    def test_container_service_precedes_application_and_framework(self):
        self.service["application"] = {
            "root": "/fixture", "relativePath": ".", "name": "runtime-app", "manifest": "go.mod",
        }
        self.service["observation"]["framework"] = "runtime-framework"
        self.service["management"]["labels"]["com.docker.compose.service"] = " prometheus \n"
        self.assert_names("prometheus")

    def test_non_docker_and_older_records_keep_original_fallback(self):
        original = copy.deepcopy(self.service)
        del original["management"]
        original_names = self.names_for([original])
        for management in ({"source": "unmanaged", "containerName": "not-a-container"},
                           {"source": "docker"}, None):
            with self.subTest(management=management):
                self.service["management"] = management
                self.assertEqual(self.names_for([self.service]), original_names)
        del self.service["management"]
        self.assertEqual(self.names_for([self.service]), original_names)

    def test_existing_titles_remain_unchanged(self):
        services = []
        for title in ("Grafana", "Blackbox Exporter"):
            service = copy.deepcopy(self.service)
            service["observation"]["protocol"] = "http"
            service["observation"]["http"]["title"] = title
            services.append(service)
        actual = [{k: v for k, v in item.items() if k != "search"} for item in self.names_for(services)]
        self.assertEqual(actual, [
            {"page": "Grafana", "related": "Grafana", "secondary": "Grafana"},
            {"page": "Blackbox Exporter", "related": "Blackbox Exporter", "secondary": "Blackbox Exporter"},
        ])

    def test_search_text_includes_docker_container_and_compose_service(self):
        self.service["observation"]["http"]["title"] = "Custom Page"
        search_text = self.names_for([self.service])[0]["search"]
        self.assertIn("prometheus", search_text)
        self.assertIn("network-monitor-prometheus", search_text)


if __name__ == "__main__":
    unittest.main()
