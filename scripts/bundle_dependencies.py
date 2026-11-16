#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
import re

def get_dependencies(path):
    res = subprocess.run(['otool', '-L', path], capture_output=True, text=True, check=True)
    deps = []
    lines = res.stdout.splitlines()
    if len(lines) > 1:
        for line in lines[1:]:
            m = re.match(r'\s+([^\s]+)\s+\(', line)
            if m:
                dep = m.group(1)
                # Ignore self-id
                if dep != path:
                    deps.append(dep)
    return deps

def bundle(app_path):
    print(f"===> 開始分析並遞迴打包動態庫至: {app_path}")
    contents_dir = os.path.join(app_path, "Contents")
    frameworks_dir = os.path.join(contents_dir, "Frameworks")
    resources_dir = os.path.join(contents_dir, "Resources")
    macos_dir = os.path.join(contents_dir, "MacOS")
    
    os.makedirs(frameworks_dir, exist_ok=True)
    
    binaries = [
        os.path.join(resources_dir, "ffmpeg"),
        os.path.join(resources_dir, "ffprobe"),
        os.path.join(macos_dir, "LosslessStudio")
    ]
    binaries = [b for b in binaries if os.path.exists(b)]
    
    # 遞迴尋找所有非系統 Homebrew 依賴庫
    # mapping: original_path -> destination filename in Frameworks
    copied_map = {} # original_or_symlink_path -> dest_filename
    real_to_name = {} # real_path -> dest_filename
    queue = list(binaries)
    all_targets = set(binaries)
    
    while queue:
        current = queue.pop(0)
        deps = get_dependencies(current)
        for dep in deps:
            if dep.startswith('/opt/homebrew'):
                real_dep = os.path.realpath(dep)
                if real_dep not in real_to_name:
                    base_name = os.path.basename(dep)
                    dest_file = os.path.join(frameworks_dir, base_name)
                    # 避免同名衝突
                    if os.path.exists(dest_file):
                        # 如果已存在且指向同一檔案則重用
                        if os.path.realpath(dest_file) != real_dep:
                            base_name = f"opt_{base_name}"
                            dest_file = os.path.join(frameworks_dir, base_name)
                    
                    shutil.copy2(real_dep, dest_file)
                    os.chmod(dest_file, 0o755)
                    real_to_name[real_dep] = base_name
                    copied_map[dep] = base_name
                    copied_map[real_dep] = base_name
                    
                    all_targets.add(dest_file)
                    queue.append(dest_file)
                else:
                    copied_map[dep] = real_to_name[real_dep]
                    
    print(f"共打包 {len(real_to_name)} 個非系統依賴庫至 Frameworks:")
    for real, name in sorted(real_to_name.items()):
        print(f"  - {name} (來源: {real})")
        
    # 設定 rpath
    for b in binaries:
        subprocess.run(['install_name_tool', '-add_rpath', '@executable_path/../Frameworks', b], capture_output=True)
        subprocess.run(['install_name_tool', '-add_rpath', '@loader_path/../Frameworks', b], capture_output=True)
        
    for target in all_targets:
        if target.endswith('.dylib'):
            target_name = os.path.basename(target)
            # 設定 dylib 自身 id
            subprocess.run(['install_name_tool', '-id', f'@rpath/{target_name}', target], check=True)
            subprocess.run(['install_name_tool', '-add_rpath', '@loader_path', target], capture_output=True)
            
    # 重寫所有引用路徑
    for target in all_targets:
        deps = get_dependencies(target)
        for dep in deps:
            if dep.startswith('/opt/homebrew'):
                real_dep = os.path.realpath(dep)
                dest_name = real_to_name.get(real_dep, os.path.basename(dep))
                new_ref = f'@rpath/{dest_name}'
                res = subprocess.run(['install_name_tool', '-change', dep, new_ref, target], capture_output=True, text=True)
                if res.returncode != 0:
                    print(f"Warning: install_name_tool change failed: {res.stderr}")
                    
    # 驗證檢查：確保沒有任何殘留的 /opt/homebrew 引用
    leak_found = False
    for target in all_targets:
        deps = get_dependencies(target)
        for dep in deps:
            if '/opt/homebrew' in dep:
                print(f"✗ 錯誤：在 {target} 中仍偵測到 Homebrew 外部依賴: {dep}")
                leak_found = True
                
    if leak_found:
        print("打包驗證失敗：存在未重寫的外部動態庫！")
        sys.exit(1)
        
    print("✓ 驗證通過：所有可執行檔與動態庫皆已 100% 轉為內部相對路徑 (@rpath)。")
    
    # 逐一對 Frameworks 進行程式碼簽章
    print("===> 對 Frameworks 動態庫與二進位執行 Ad-Hoc 程式碼簽章...")
    for target in sorted(all_targets):
        res = subprocess.run(['codesign', '--force', '--sign', '-', target], capture_output=True, text=True)
        if res.returncode != 0:
            print(f"Warning: codesign failed on {target}: {res.stderr}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: bundle_dependencies.py <AppBundlePath>")
        sys.exit(1)
    bundle(sys.argv[1])
