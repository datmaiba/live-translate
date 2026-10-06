#!/usr/bin/env python3
"""Generate an AltStore/SideStore source (source.json) for the latest build.

Usage: make-source.py VERSION BUILD DOWNLOAD_URL IPA_PATH OUT_PATH
"""
import datetime
import json
import os
import sys

REPO = "https://github.com/datmaiba/live-translate"
RAW = "https://raw.githubusercontent.com/datmaiba/live-translate/main"


def build_source(version, build, url, size, date):
    return {
        "name": "Live Dich",
        "identifier": "com.datmaiba.livetranslate.source",
        "subtitle": "Dịch trực tiếp Việt ⇄ Anh",
        "website": REPO,
        "iconURL": f"{RAW}/LiveTranslate/Resources/Assets.xcassets/AppIcon.appiconset/icon.png",
        "tintColor": "#3399FF",
        "apps": [
            {
                "name": "Live Dich",
                "bundleIdentifier": "com.datmaiba.livetranslate",
                "developerName": "Mai Ba Dat",
                "subtitle": "Dịch hội thoại Việt ⇄ Anh, chạy nền",
                "localizedDescription": (
                    "Bạn nói tiếng Việt → phát tiếng Anh ra loa. Người khác nói tiếng Anh → "
                    "dịch tiếng Việt cho riêng bạn, kèm gợi ý câu trả lời."
                ),
                "iconURL": f"{RAW}/LiveTranslate/Resources/Assets.xcassets/AppIcon.appiconset/icon.png",
                "tintColor": "#3399FF",
                "category": "utilities",
                "versions": [
                    {
                        "version": version,
                        "buildVersion": build,
                        "date": date,
                        "localizedDescription": f"Build {build}",
                        "downloadURL": url,
                        "size": size,
                        "minOSVersion": "17.0",
                    }
                ],
                "appPermissions": {
                    "entitlements": [],
                    "privacy": {
                        "NSMicrophoneUsageDescription": "Live Dịch cần micro để nghe và dịch hội thoại.",
                        "NSSpeechRecognitionUsageDescription": "Live Dịch chuyển giọng nói thành chữ để dịch Việt ⇄ Anh.",
                    },
                },
            }
        ],
        "news": [],
    }


def main(argv):
    if len(argv) != 6:
        sys.exit(__doc__)
    version, build, url, ipa_path, out_path = argv[1:]
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    source = build_source(version, build, url, os.path.getsize(ipa_path), date)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(source, handle, ensure_ascii=False, indent=2)
    print(f"wrote {out_path}: {version} ({build})")


if __name__ == "__main__":
    main(sys.argv)
