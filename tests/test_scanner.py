import unittest

from prototype.port_tools import parse_endpoint, parse_http_response, relevance


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


if __name__ == "__main__":
    unittest.main()
