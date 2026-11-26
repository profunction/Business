#!/usr/bin/env python3
"""把 packages/core/test/fixtures/procure_*.json（本机数据库真实返回的样本）变成公司采购网页示范模式用的 Dart 文件。
用法：python3 tool/gen_demo_data.py（tool/export_fixtures.sh 最后会自动跑）"""
import json, pathlib
src = pathlib.Path(__file__).resolve().parents[3] / 'packages/core/test/fixtures'
out = pathlib.Path(__file__).resolve().parents[1] / 'lib/demo/demo_data.dart'
files = sorted(src.glob('procure_*.json'))
lines = ['// 自动生成：python3 tool/gen_demo_data.py。不要手改。', '// 来源：packages/core/test/fixtures/procure_*.json（本机数据库真实返回的 JSON）', '', 'const demoFixtures = <String, String>{']
for f in files:
    text = json.dumps(json.loads(f.read_text()), ensure_ascii=False, separators=(',', ':'))
    assert "'''" not in text
    lines.append(f"  '{f.stem}': r'''{text}''',")
lines += ['};', '']
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text('\n'.join(lines))
print(f'wrote {out} ({len(files)} fixtures)')
