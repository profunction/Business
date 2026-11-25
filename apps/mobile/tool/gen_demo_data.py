#!/usr/bin/env python3
"""把 packages/core/test/fixtures/*.json（本机数据库真实返回的样本）变成示范模式用的 Dart 文件。
用法：python3 tool/gen_demo_data.py（在 apps/mobile 里跑）"""
import json, pathlib
src = pathlib.Path(__file__).resolve().parents[3] / 'packages/core/test/fixtures'
out = pathlib.Path(__file__).resolve().parents[1] / 'lib/demo/demo_data.dart'
lines = ['// 自动生成：python3 tool/gen_demo_data.py。不要手改。', '// 来源：packages/core/test/fixtures（本机数据库真实返回的 JSON）', '', 'const demoFixtures = <String, String>{']
for f in sorted(src.glob('*.json')):
    text = json.dumps(json.loads(f.read_text()), ensure_ascii=False, separators=(',', ':'))
    assert "'''" not in text
    lines.append(f"  '{f.stem}': r'''{text}''',")
lines += ['};', '']
out.write_text('\n'.join(lines))
print(f'wrote {out} ({len(list(src.glob("*.json")))} fixtures)')
