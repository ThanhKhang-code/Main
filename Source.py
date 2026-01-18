import requests, subprocess
import os
import time
from datetime import datetime

# ================= CONFIG =================

FREEZE_URL = "https://raw.githubusercontent.com/ThanhKhang-code/Main/refs/heads/main/FreezeObfuscated.lua"
SOURCE_URL = "https://raw.githubusercontent.com/ThanhKhang-code/Main/refs/heads/main/SourceObfuscated.lua"
WHITELIST_URL = "https://raw.githubusercontent.com/ThanhKhang-code/Main/main/Whitelist.txt"

print("USING WHITELIST URL =", WHITELIST_URL)

XOR_KEY = b"GG_SECRET_KEY"
LICENSE_KEY = b"MySecretKey123"
# Duong dan thu muc Output (MuMu Shared Folder)
OUT_DIR = os.path.join(
    os.environ["USERPROFILE"],
    "Documents",
    "MuMuSharedFolder",
    "Download"
)
LICENSE_PATH = os.path.join(
    os.environ["USERPROFILE"],
    "Documents",
    "MuMuSharedFolder",
    "Movies",
    "license.bin"
)
# ==========================================

def github_raw(url):
    try:
        r = requests.get(url, timeout=15)
        r.raise_for_status()
        return r.text
    except Exception as e:
        print(f"Loi khi tai tu GitHub: {e}")
        return None

def get_hwid():
    cmd = r'reg query "HKLM\SOFTWARE\Microsoft\Cryptography" /v MachineGuid'
    out = subprocess.check_output(cmd, shell=True, text=True)
    return out.strip().split()[-1]
    
def xor_encrypt(data: bytes, key: bytes) -> bytes:
    return bytes(data[i] ^ key[i % len(key)] for i in range(len(data)))

def create_license(hwid):
    os.makedirs(os.path.dirname(LICENSE_PATH), exist_ok=True)

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    raw = f"{hwid}|{now}".encode("utf-8")

    encrypted = xor_encrypt(raw, LICENSE_KEY)

    with open(LICENSE_PATH, "wb") as f:
        f.write(encrypted)

    print("License created!")
    print(LICENSE_PATH)

def main():
    # 1. Tao thu muc neu chua co
    if not os.path.exists(OUT_DIR):
        os.makedirs(OUT_DIR, exist_ok=True)

    # 2. Check Whitelist
    hwid = get_hwid()
    print(f"Checking HWID: {hwid}...")
    
    whitelist_content = github_raw(WHITELIST_URL)
    if not whitelist_content:
        print("Khong the tai Whitelist. Dung lai.")
        return

    whitelist = whitelist_content.splitlines()

    if hwid not in whitelist:
        print("====== HWID NOT WHITELISTED ======")
        print(f"HWID: {hwid}")
        print("Waiting 30 seconds...")
        time.sleep(30)
        return

    # 3. Tai Code Lua goc
    create_license(hwid)
    print("Dang tai code tu GitHub...")
    freeze_src = github_raw(FREEZE_URL)
    source_src = github_raw(SOURCE_URL)

    if freeze_src and source_src:
        # 4. Ghi truc tiep ra file .lua
        try:
            freeze_path = os.path.join(OUT_DIR, "Freeze.lua")
            source_path = os.path.join(OUT_DIR, "Source.lua")

            with open(freeze_path, "w", encoding="utf-8") as f:
                f.write(freeze_src)
            
            with open(source_path, "w", encoding="utf-8") as f:
                f.write(source_src)

            print("-----------------------------------")
            print(f"Da tai xong: {freeze_path}")
            print(f"Da tai xong: {source_path}")
            print("-----------------------------------")
            print("DONE!!!")
        except Exception as e:
            print(f"Loi khi ghi file: {e}")
    else:
        print("Loi: Noi dung code trong hoac khong tai duoc.")

if __name__ == "__main__":
    main()
