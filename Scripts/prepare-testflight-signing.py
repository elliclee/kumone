#!/usr/bin/env python3
"""为 Kumo TestFlight Internal Only 准备 App Store 分发描述文件。

证书是团队级资源，脚本只复用本机已有、且能与 App Store Connect API
返回证书匹配的 Apple Distribution 身份；不会创建或撤销证书，也不会修改
问命书主 App / Widget 的 App ID 与描述文件。
"""

from __future__ import annotations

import argparse
import base64
import json
import plistlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

TEAM_ID = "GLAX98QHX4"
KEY_ID = "3AU3H29X5A"
ISSUER_ID = "f2a5ffef-ebd3-460a-ac5c-4c845a5b4312"
KEY_PATH = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"

BUNDLE_ID = "com.wenmingshu.kumone.internal"
PROFILE_NAME = "Kumo Internal App Store (managed by prepare-testflight-signing.py)"
PROFILE_TYPE = "IOS_APP_STORE"
API_ROOT = "https://api.appstoreconnect.apple.com"

PROFILE_DIRECTORIES = (
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
)


def token() -> str:
    if not KEY_PATH.is_file():
        sys.exit(f"找不到 App Store Connect API 密钥：{KEY_PATH}")

    def encoded(value: bytes) -> bytes:
        return base64.urlsafe_b64encode(value).rstrip(b"=")

    private_key = serialization.load_pem_private_key(KEY_PATH.read_bytes(), password=None)
    now = int(time.time())
    header = encoded(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    payload = encoded(json.dumps({
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 600,
        "aud": "appstoreconnect-v1",
    }).encode())
    signing_input = header + b"." + payload
    r, s = utils.decode_dss_signature(
        private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    )
    signature = encoded(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    return (signing_input + b"." + signature).decode()


def call(method: str, path: str, body: dict | None = None) -> dict:
    request = urllib.request.Request(
        API_ROOT + path,
        data=json.dumps(body).encode() if body else None,
        headers={
            "Authorization": "Bearer " + token(),
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:1200]
        sys.exit(f"App Store Connect API {method} {path} 失败（HTTP {error.code}）：\n{detail}")


def local_distribution_fingerprints() -> set[bytes]:
    result = subprocess.run(
        ["security", "find-certificate", "-a", "-p", "-c", "Apple Distribution"],
        capture_output=True,
        check=True,
    )
    blocks = re.findall(
        rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        result.stdout,
        flags=re.DOTALL,
    )
    fingerprints: set[bytes] = set()
    for block in blocks:
        certificate = x509.load_pem_x509_certificate(block)
        fingerprints.add(certificate.fingerprint(hashes.SHA256()))
    if not fingerprints:
        sys.exit("本机钥匙串没有可用的 Apple Distribution 证书。")
    return fingerprints


def matching_distribution_certificate_id() -> str:
    local_fingerprints = local_distribution_fingerprints()
    response = call("GET", "/v1/certificates?limit=100")
    for item in response.get("data", []):
        attributes = item["attributes"]
        if attributes.get("certificateType") != "DISTRIBUTION":
            continue
        content = attributes.get("certificateContent")
        if not content:
            continue
        certificate = x509.load_der_x509_certificate(base64.b64decode(content))
        if certificate.fingerprint(hashes.SHA256()) in local_fingerprints:
            print(f"  分发证书：复用 {attributes.get('name', 'Apple Distribution')}")
            return item["id"]
    sys.exit("Apple 后台的分发证书与本机私钥不匹配，停止以避免创建无效描述文件。")


def bundle_resource_id() -> str:
    response = call("GET", "/v1/bundleIds?limit=200")
    for item in response.get("data", []):
        if item["attributes"].get("identifier") == BUNDLE_ID:
            print(f"  App ID：已存在（{BUNDLE_ID}）")
            return item["id"]
    sys.exit(f"Apple Developer 后台没有 App ID：{BUNDLE_ID}")


def app_record_exists() -> bool:
    response = call("GET", "/v1/apps?limit=200")
    for item in response.get("data", []):
        attributes = item["attributes"]
        if attributes.get("bundleId") == BUNDLE_ID:
            print(f"  App Store Connect：已存在（{attributes.get('name')}）")
            return True
    print("  App Store Connect：未找到对应应用记录")
    return False


def profile_payload(content_base64: str) -> dict:
    raw = base64.b64decode(content_base64)
    start = raw.find(b"<?xml")
    end = raw.find(b"</plist>")
    if start < 0 or end < 0:
        sys.exit("Apple 返回的描述文件无法解析。")
    return plistlib.loads(raw[start : end + len(b"</plist>")])


def profile_matches_bundle(content_base64: str) -> bool:
    payload = profile_payload(content_base64)
    entitlements = payload.get("Entitlements", {})
    return entitlements.get("application-identifier") == f"{TEAM_ID}.{BUNDLE_ID}"


def install_profile(content_base64: str) -> str:
    raw = base64.b64decode(content_base64)
    uuid = profile_payload(content_base64)["UUID"]
    for directory in PROFILE_DIRECTORIES:
        directory.mkdir(parents=True, exist_ok=True)
        destination = directory / f"{uuid}.mobileprovision"
        if not destination.exists() or destination.read_bytes() != raw:
            destination.write_bytes(raw)
    return uuid


def ensure_profile(bundle_id: str, certificate_id: str, *, dry_run: bool) -> tuple[str, str] | None:
    profiles = call("GET", "/v1/profiles?limit=200").get("data", [])
    for profile in profiles:
        attributes = profile["attributes"]
        if attributes.get("name") != PROFILE_NAME:
            continue
        if (
            attributes.get("profileState") == "ACTIVE"
            and profile_matches_bundle(attributes["profileContent"])
        ):
            uuid = install_profile(attributes["profileContent"])
            print(f"  描述文件：复用已有（{uuid}）")
            return attributes["name"], uuid
        if dry_run:
            print(f"  描述文件：存在但不可用（{attributes.get('profileState')}）")
            return None
        call("DELETE", f"/v1/profiles/{profile['id']}")
        print("  描述文件：已删除不可用的同名旧件")

    if dry_run:
        print("  描述文件：尚未创建")
        return None

    created = call("POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": PROFILE_NAME,
                "profileType": PROFILE_TYPE,
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {
                    "data": [{"type": "certificates", "id": certificate_id}]
                },
            },
        }
    })["data"]
    uuid = install_profile(created["attributes"]["profileContent"])
    print(f"  描述文件：已创建并安装（{uuid}）")
    return created["attributes"]["name"], uuid


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", action="store_true", help="只读检查，不创建描述文件")
    parser.add_argument("--require-app", action="store_true", help="缺少 App 记录时返回失败")
    arguments = parser.parse_args()

    print(f"Kumo TestFlight 签名材料（团队 {TEAM_ID}）")
    bundle_id = bundle_resource_id()
    certificate_id = matching_distribution_certificate_id()
    has_app = app_record_exists()
    profile = ensure_profile(bundle_id, certificate_id, dry_run=arguments.status)

    if arguments.require_app and not has_app:
        sys.exit(3)
    if arguments.status:
        return
    if profile is None:
        sys.exit("未能创建可用的 App Store 描述文件。")

    name, uuid = profile
    print()
    print(f"PROFILE_NAME={name}")
    print(f"PROFILE_UUID={uuid}")


if __name__ == "__main__":
    main()
