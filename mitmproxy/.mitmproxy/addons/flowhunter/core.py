from __future__ import annotations

import hashlib
import json
import re
import time
import uuid
from dataclasses import asdict, dataclass
from typing import Any, Iterable
from urllib.parse import parse_qsl


SECRET_KEY = re.compile(
    r"(?:auth|authorization|cookie|token|secret|password|passwd|session|api[-_]?key|csrf|otp)",
    re.IGNORECASE,
)
PERSONAL_KEY = re.compile(
    r"(?:email|phone|address|full[-_]?name|birth|ssn|card|iban|account[-_]?number)",
    re.IGNORECASE,
)
EMAIL_VALUE = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
JWT_VALUE = re.compile(r"\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}\b")
BEARER_VALUE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}")
UUID_SEGMENT = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
INTEGER_SEGMENT = re.compile(r"^\d+$")
LONG_HEX_SEGMENT = re.compile(r"^[0-9a-f]{16,}$", re.IGNORECASE)
ERROR_WORDS = (
    "traceback",
    "stack trace",
    "syntax error",
    "sql error",
    "exception",
    "fatal error",
    "internal server error",
)
SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}


def stable_hash(value: str, length: int = 12) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:length]


def redact_value(value: Any) -> str:
    text = str(value)
    return f"<redacted:{stable_hash(text)}>"


def redact_text(text: str) -> str:
    def replace(label: str):
        return lambda match: f"<redacted-{label}:{stable_hash(match.group(0))}>"

    text = EMAIL_VALUE.sub(replace("email"), text)
    text = JWT_VALUE.sub(replace("jwt"), text)
    text = BEARER_VALUE.sub(replace("bearer"), text)
    return text


def redact_mapping(items: Iterable[tuple[str, Any]]) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, value in items:
        result[str(key)] = redact_value(value) if SECRET_KEY.search(str(key)) else str(value)[:2048]
    return result


def redact_json(value: Any, depth: int = 0) -> Any:
    if depth > 6:
        return "<max-depth>"
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, child in list(value.items())[:100]:
            result[str(key)] = (
                redact_value(child)
                if SECRET_KEY.search(str(key)) or PERSONAL_KEY.search(str(key))
                else redact_json(child, depth + 1)
            )
        return result
    if isinstance(value, list):
        return [redact_json(child, depth + 1) for child in value[:30]]
    if isinstance(value, str):
        return redact_text(value[:2048])
    return value


def json_shape(value: Any, depth: int = 0) -> Any:
    if depth > 6:
        return "..."
    if isinstance(value, dict):
        return {
            str(key): json_shape(child, depth + 1)
            for key, child in sorted(value.items(), key=lambda item: str(item[0]))[:100]
        }
    if isinstance(value, list):
        if not value:
            return []
        shapes = [json_shape(child, depth + 1) for child in value[:5]]
        unique = []
        for shape in shapes:
            if shape not in unique:
                unique.append(shape)
        return unique
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    return "string"


def template_path(path: str) -> str:
    segments = []
    for segment in path.split("/"):
        if INTEGER_SEGMENT.match(segment):
            segments.append("{int}")
        elif UUID_SEGMENT.match(segment):
            segments.append("{uuid}")
        elif LONG_HEX_SEGMENT.match(segment):
            segments.append("{hex}")
        else:
            segments.append(segment)
    return "/".join(segments) or "/"


def body_details(content_type: str, content: bytes) -> tuple[Any, str]:
    if not content:
        return None, ""
    text = content.decode("utf-8", errors="replace")
    if "json" in content_type:
        try:
            parsed = json.loads(text)
            redacted = redact_json(parsed)
            return json_shape(parsed), json.dumps(redacted, sort_keys=True)[:4096]
        except json.JSONDecodeError:
            pass
    if "application/x-www-form-urlencoded" in content_type:
        pairs = parse_qsl(text, keep_blank_values=True)
        shape = sorted({key for key, _ in pairs})
        return shape, json.dumps(redact_mapping(pairs), sort_keys=True)[:4096]
    if content_type.startswith("text/") or any(
        marker in content_type for marker in ("xml", "javascript", "graphql")
    ):
        return "text", redact_text(text[:4096])
    return "binary", f"<binary:{len(content)} bytes>"


@dataclass(frozen=True)
class Snapshot:
    signature: str
    timestamp: float
    method: str
    scheme: str
    host: str
    port: int
    path_template: str
    query_keys: list[str]
    request_content_type: str
    request_shape: Any
    request_preview: str
    request_headers: dict[str, str]
    status_code: int
    response_content_type: str
    response_length: int
    response_sha256: str
    response_preview: str
    response_headers: dict[str, str]
    duration_ms: float | None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> "Snapshot":
        return cls(**value)


@dataclass(frozen=True)
class Finding:
    signature: str
    kind: str
    severity: str
    title: str
    evidence: dict[str, Any]

    @property
    def finding_id(self) -> str:
        material = json.dumps(
            [self.signature, self.kind, self.evidence.get("mutation")],
            sort_keys=True,
        )
        return f"fh-{stable_hash(material, 16)}"


def snapshot_from_flow(flow: Any) -> Snapshot:
    request = flow.request
    response = flow.response
    method = request.method.upper()
    host = request.host.lower().rstrip(".")
    path = template_path(request.path.split("?", 1)[0])
    query_keys = sorted({str(key) for key, _ in request.query.items(multi=True)})
    request_type = request.headers.get("content-type", "").split(";", 1)[0].lower()
    request_shape, request_preview = body_details(request_type, request.raw_content or b"")
    response_type = response.headers.get("content-type", "").split(";", 1)[0].lower()
    _, response_preview = body_details(response_type, response.raw_content or b"")
    signature_material = json.dumps(
        [method, request.scheme, host, request.port, path, query_keys, request_type, request_shape],
        sort_keys=True,
        separators=(",", ":"),
    )
    started = getattr(request, "timestamp_start", None)
    ended = getattr(response, "timestamp_end", None)
    duration_ms = round((ended - started) * 1000, 2) if started and ended else None
    response_content = response.raw_content or b""
    return Snapshot(
        signature=f"ep-{stable_hash(signature_material, 20)}",
        timestamp=time.time(),
        method=method,
        scheme=request.scheme,
        host=host,
        port=request.port,
        path_template=path,
        query_keys=query_keys,
        request_content_type=request_type,
        request_shape=request_shape,
        request_preview=request_preview,
        request_headers=redact_mapping(request.headers.items(multi=True)),
        status_code=response.status_code,
        response_content_type=response_type,
        response_length=len(response_content),
        response_sha256=hashlib.sha256(response_content).hexdigest(),
        response_preview=response_preview,
        response_headers=redact_mapping(response.headers.items(multi=True)),
        duration_ms=duration_ms,
    )


def host_in_scope(host: str, scope: Iterable[str]) -> bool:
    normalized = host.lower().rstrip(".")
    for entry in scope:
        candidate = entry.strip().lower().rstrip(".")
        if not candidate:
            continue
        if candidate.startswith("*."):
            suffix = candidate[1:]
            if normalized.endswith(suffix) and normalized != suffix[1:]:
                return True
        elif normalized == candidate:
            return True
    return False


def _query_mutations(flow: Any, limit: int) -> list[tuple[Any, str, str]]:
    mutations: list[tuple[Any, str, str]] = []
    keys = list(dict.fromkeys(str(key) for key, _ in flow.request.query.items(multi=True)))
    for key in keys:
        for label, value in (("empty", ""), ("zero", "0")):
            clone = flow.copy()
            clone.response = None
            clone.request.query[key] = value
            mutations.append((clone, f"query:{key}:{label}", ""))
            if len(mutations) >= limit:
                return mutations
        marker = f"flowhunter-{uuid.uuid4().hex[:10]}"
        clone = flow.copy()
        clone.response = None
        clone.request.query[key] = marker
        mutations.append((clone, f"query:{key}:marker", marker))
        if len(mutations) >= limit:
            return mutations
    return mutations


def _auth_mutation(flow: Any) -> list[tuple[Any, str, str]]:
    clone = flow.copy()
    clone.response = None
    removed = []
    for name in ("authorization", "cookie", "x-api-key"):
        if name in clone.request.headers:
            del clone.request.headers[name]
            removed.append(name)
    return [(clone, f"remove-auth:{','.join(removed)}", "")] if removed else []


def _mutate_first_json(value: Any, path: str = "$") -> tuple[Any, str, str] | None:
    if isinstance(value, dict):
        for key in sorted(value):
            result = _mutate_first_json(value[key], f"{path}.{key}")
            if result:
                new_child, description, marker = result
                copy = dict(value)
                copy[key] = new_child
                return copy, description, marker
        return None
    if isinstance(value, list) and value:
        result = _mutate_first_json(value[0], f"{path}[0]")
        if result:
            new_child, description, marker = result
            copy = list(value)
            copy[0] = new_child
            return copy, description, marker
        return None
    if isinstance(value, str):
        marker = f"flowhunter-{uuid.uuid4().hex[:10]}"
        return marker, f"json:{path}:marker", marker
    if isinstance(value, bool):
        return (not value), f"json:{path}:toggle", ""
    if isinstance(value, (int, float)):
        return -1, f"json:{path}:negative", ""
    return None


def build_mutations(
    flow: Any,
    profile: str,
    limit: int,
    allow_unsafe_methods: bool,
) -> list[tuple[Any, str, str]]:
    method = flow.request.method.upper()
    if method not in SAFE_METHODS and not allow_unsafe_methods:
        raise ValueError(
            f"{method} replay is disabled; set flowhunter_allow_unsafe_methods=true explicitly"
        )
    if profile == "safe":
        return _query_mutations(flow, limit)
    if profile == "auth":
        return _auth_mutation(flow)
    if profile == "json":
        try:
            body = json.loads(flow.request.get_text(strict=False))
        except (json.JSONDecodeError, TypeError):
            return []
        mutation = _mutate_first_json(body)
        if not mutation:
            return []
        changed, description, marker = mutation
        clone = flow.copy()
        clone.response = None
        clone.request.set_text(json.dumps(changed, separators=(",", ":")))
        return [(clone, description, marker)]
    raise ValueError("unknown profile; use safe, auth, or json")


def compare_replay(
    baseline: Snapshot,
    candidate: Snapshot,
    mutation: str,
    marker: str,
) -> list[Finding]:
    findings: list[Finding] = []
    common = {
        "mutation": mutation,
        "baseline_status": baseline.status_code,
        "replay_status": candidate.status_code,
        "baseline_length": baseline.response_length,
        "replay_length": candidate.response_length,
    }
    if candidate.status_code >= 500 and baseline.status_code < 500:
        findings.append(
            Finding(
                candidate.signature,
                "server-error",
                "medium",
                "Mutation triggered a server error",
                common,
            )
        )
    if baseline.response_content_type != candidate.response_content_type:
        findings.append(
            Finding(
                candidate.signature,
                "content-type-change",
                "low",
                "Response content type changed after mutation",
                {**common, "baseline_type": baseline.response_content_type, "replay_type": candidate.response_content_type},
            )
        )
    baseline_errors = {word for word in ERROR_WORDS if word in baseline.response_preview.lower()}
    candidate_errors = {word for word in ERROR_WORDS if word in candidate.response_preview.lower()}
    new_errors = sorted(candidate_errors - baseline_errors)
    if new_errors:
        findings.append(
            Finding(
                candidate.signature,
                "error-disclosure",
                "medium",
                "Mutation exposed error details",
                {**common, "new_error_terms": new_errors},
            )
        )
    if marker and marker in candidate.response_preview and marker not in baseline.response_preview:
        findings.append(
            Finding(
                candidate.signature,
                "reflection",
                "low",
                "Mutation marker was reflected in the response",
                {**common, "marker": marker},
            )
        )
    if mutation.startswith("remove-auth") and 200 <= candidate.status_code < 300:
        findings.append(
            Finding(
                candidate.signature,
                "auth-removal-success",
                "high",
                "Request still succeeded after authentication material was removed",
                common,
            )
        )
    if baseline.response_length >= 128 and candidate.response_length >= 0:
        ratio = candidate.response_length / baseline.response_length
        if ratio > 4 or ratio < 0.25:
            findings.append(
                Finding(
                    candidate.signature,
                    "body-size-change",
                    "low",
                    "Response size changed substantially after mutation",
                    {**common, "size_ratio": round(ratio, 3)},
                )
            )
    return findings
