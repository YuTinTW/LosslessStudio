#!/usr/bin/env python3
import argparse
import os
import sys
import re
import zipfile
import subprocess
import hashlib
import tempfile
import getpass

# 違規檔名規則（黑名單）
FORBIDDEN_FILE_PATTERNS = [
    r'^\.env(\..*)?$',
    r'.*\.pem$',
    r'.*\.key$',
    r'.*\.p12$',
    r'.*\.keystore$',
    r'.*\.cer$',
    r'.*\.crt$',
    r'^\.git.*$',
    r'^\.DS_Store$',
    r'.*credentials.*',
    r'.*vault.*',
    r'.*history.*'
]

# 機密與個人隱私字串規則
FORBIDDEN_PATTERNS = [
    (re.compile(r'/Users/[a-zA-Z0-9._-]+/'), "本機個人家目錄絕對路徑 (Local Home Path)"),
    (re.compile(r'/home/[a-zA-Z0-9._-]+/'), "Linux 個人家目錄絕對路徑 (Local Home Path)"),
    (re.compile(r'-----BEGIN[ A-Z0-9_-]*PRIVATE KEY-----'), "私鑰明文 (Private Key)"),
    (re.compile(r'\b(sk-[a-zA-Z0-9]{20,})\b'), "OpenAI / 類似 API 金鑰 (API Key)"),
    (re.compile(r'\b(AIza[0-9A-Za-z-_]{35})\b'), "Google API 金鑰 (API Key)"),
    (re.compile(r'\b(ghp_[0-9a-zA-Z]{36})\b'), "GitHub 個人存取權杖 (Personal Token)"),
    (re.compile(r'\b(AKIA[0-9A-Z]{16})\b'), "AWS 存取金鑰 (Access Key)"),
    (re.compile(r'(?i)(api[_-]?key|secret[_-]?key|auth[_-]?token|access[_-]?token)\s*[:=]\s*["\']?[a-zA-Z0-9+/=_-]{16,}["\']?'), "硬編碼機密金鑰或 Token")
]

current_user = getpass.getuser()
if current_user and current_user.lower() not in ('root', 'runner', 'daemon', 'nobody', 'staff'):
    FORBIDDEN_PATTERNS.insert(0, (re.compile(rf'(?i){re.escape(current_user)}'), "開發者個人帳號/使用者名稱 (User Account)"))

TEXT_EXTENSIONS = {'.txt', '.md', '.plist', '.json', '.xml', '.html', '.sh', '.swift', '.py', '.yaml', '.yml', '.strings'}

ALLOWED_UPSTREAM_DOMAINS = [
    'ffmpeg.org',
    'videolan.org',
    'webmproject.org',
    'opus-codec.org',
    'openssl.org',
    'netflix.com',
    'apple.com',
    'github.com',
    'aomedia.org'
]

def is_text_file(filename):
    ext = os.path.splitext(filename)[1].lower()
    return ext in TEXT_EXTENSIONS

def extract_strings_from_binary(file_path):
    try:
        res = subprocess.run(['strings', file_path], capture_output=True, text=True, errors='ignore')
        return res.stdout
    except Exception:
        return ""

def scan_file(path, relative_display):
    findings = []
    base = os.path.basename(path)
    
    # 1. 檔名檢查
    for pat in FORBIDDEN_FILE_PATTERNS:
        if re.match(pat, base, re.IGNORECASE):
            findings.append(("黑名單機密/暫存檔名", relative_display, base))

    # 2. 內容提取
    if is_text_file(base):
        try:
            with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception:
            content = ""
            
        # 僅在文字檔檢查個人信箱，排除開源官方網域與 Homebrew 套件版本號 (如 openssl@3)
        email_matches = re.finditer(r'\b[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Z|a-z]{2,})\b', content)
        for em in email_matches:
            full_email = em.group(0)
            if re.search(r'@[0-9]', full_email):
                continue
            domain = em.group(1).lower()
            if not any(domain.endswith(allowed) for allowed in ALLOWED_UPSTREAM_DOMAINS):
                masked = full_email[:2] + "****@" + domain
                findings.append(("可疑個人電子郵件地址", relative_display, masked))
    else:
        # 二進位可執行檔/動態庫，使用 strings 提取可讀字串以避免位元碼誤判
        content = extract_strings_from_binary(path)

    # 3. 機密字串比對
    for pat, desc in FORBIDDEN_PATTERNS:
        for m in pat.finditer(content):
            matched = m.group(0)
            masked = matched[:3] + "..." + matched[-3:] if len(matched) > 6 else "***"
            findings.append((desc, relative_display, masked))
            
    return findings

def scan_directory(root_dir, prefix=""):
    findings = []
    file_count = 0
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for f in filenames:
            file_count += 1
            full_path = os.path.join(dirpath, f)
            rel_path = os.path.relpath(full_path, root_dir)
            display_path = os.path.join(prefix, rel_path)
            findings.extend(scan_file(full_path, display_path))
    return findings, file_count

def check_dmg(dmg_path):
    print(f"===> [機密稽核 1/3] 掛載並稽核 DMG 實體散布內容: {dmg_path}")
    with tempfile.TemporaryDirectory(prefix="losslessstudio-dmg-audit-") as mount_point:
        subprocess.run(
            ['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount_point, dmg_path],
            capture_output=True, text=True, check=True,
        )
        try:
            return scan_directory(mount_point, prefix="[DMG]")
        finally:
            subprocess.run(['hdiutil', 'detach', mount_point], capture_output=True, text=True, check=True)

def check_zip(zip_path):
    print(f"===> [機密稽核 2/3] 解壓並稽核 ZIP 實體散布內容: {zip_path}")
    with tempfile.TemporaryDirectory() as tmpdir:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            zf.extractall(tmpdir)
        findings, count = scan_directory(tmpdir, prefix="[ZIP]")
        return findings, count

def check_app_dir(app_path):
    print(f"===> [機密稽核 3/3] 稽核本機 App Bundle: {app_path}")
    return scan_directory(app_path, prefix="[APP]")

def compute_sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def main():
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    app_dir = os.path.join(project_dir, "build/LosslessStudio.app")
    dmg_path = os.path.join(project_dir, "dist/LosslessStudio.dmg")
    zip_path = os.path.join(project_dir, "dist/LosslessStudio-macOS.zip")
    sources_zip_path = os.path.join(project_dir, "dist/LosslessStudio-sources.zip")
    sources_dir = os.path.join(project_dir, "sources")
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", help="Directory containing a candidate app, DMG, and ZIP")
    args = parser.parse_args()
    if args.candidate:
        app_dir = os.path.join(args.candidate, "LosslessStudio.app")
        dmg_path = os.path.join(args.candidate, "LosslessStudio.dmg")
        zip_path = os.path.join(args.candidate, "LosslessStudio-macOS.zip")
        for artifact in (app_dir, dmg_path, zip_path):
            if not os.path.exists(artifact):
                parser.error(f"Missing candidate artifact: {os.path.basename(artifact)}")
        # The candidate ships only the app, DMG, and ZIP.
    all_findings = []
    total_files_scanned = 0
    
    # 1. 掃描 App
    if os.path.exists(app_dir):
        f, c = check_app_dir(app_dir)
        all_findings.extend(f)
        total_files_scanned += c
        
    # 2. 掃描 DMG
    if os.path.exists(dmg_path):
        f, c = check_dmg(dmg_path)
        all_findings.extend(f)
        total_files_scanned += c
        
    # 3. 掃描 ZIP
    if os.path.exists(zip_path):
        f, c = check_zip(zip_path)
        all_findings.extend(f)
        total_files_scanned += c

    # 4. 掃描配套原始碼封裝 (Sources ZIP 或 sources 目錄)
    if not args.candidate and os.path.exists(sources_zip_path):
        print(f"===> [機密稽核 4/4] 解壓並稽核 Sources 獨立封裝: {sources_zip_path}")
        f, c = check_zip(sources_zip_path)
        all_findings.extend(f)
        total_files_scanned += c
    elif not args.candidate and os.path.exists(sources_dir):
        print(f"===> [機密稽核 4/4] 稽核本機 Sources 目錄: {sources_dir}")
        f, c = scan_directory(sources_dir, prefix="[SOURCES]")
        all_findings.extend(f)
        total_files_scanned += c
        
    print("\n================================================================")
    print("🔒 隱私與機密資料發行前強制檢驗報告 (Pre-Release Privacy Audit)")
    print("================================================================")
    print(f"累計檢驗檔案總數: {total_files_scanned} 個檔案 (涵蓋可執行檔、動態庫、文字說明、plist 與簽章資源)")
    
    if all_findings:
        print("\n✗ 嚴重警告：在發行產物中偵測到敏感或個人隱私資訊，發行流程已強制阻斷！")
        for category, loc, masked in all_findings:
            print(f"  - [{category}] 位於: {loc} (遮罩內容: {masked})")
        print("\n請先清除上述機密資料後再重新編譯與打包！")
        sys.exit(1)
    else:
        print("✓ 稽核通過：未偵測到任何 API Key、Token、密碼、私鑰、本機個人絕對路徑或個人機密檔案。")
        print("\n發行產物 SHA256 完整性雜湊值：")
        if os.path.exists(dmg_path):
            print(f"  - LosslessStudio.dmg       : {compute_sha256(dmg_path)}")
        if os.path.exists(zip_path):
            print(f"  - LosslessStudio-macOS.zip : {compute_sha256(zip_path)}")
        if not args.candidate and os.path.exists(sources_zip_path):
            print(f"  - dist/LosslessStudio-sources.zip: {compute_sha256(sources_zip_path)}")
        print("================================================================\n")

if __name__ == "__main__":
    main()
