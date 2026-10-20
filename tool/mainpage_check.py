#!/usr/bin/env python3
import socket
import sys
import urllib.request
import urllib.parse
import urllib.error

DOMAIN   = "dev-mainpage0080812569927.vendor.fenrir"
URL      = "http://%s/" % DOMAIN
USERNAME = "72364591234"
PASSWORD = "ZSr2Wf{ifj[:7-5Uxq9LKSBn([v!ME"


def resolve():
    try:
        return socket.gethostbyname(DOMAIN)
    except socket.gaierror:
        return None


def main():
    ip = resolve()
    if ip is None:
        print("[!] Domain '%s' belum bisa di-resolve." % DOMAIN)
        print("[!] Tambahkan ke /etc/hosts, contoh:")
        print("    <IP-server>   %s" % DOMAIN)
        sys.exit(1)

    print("[*] %s -> %s" % (DOMAIN, ip))

    data = urllib.parse.urlencode({"username": USERNAME, "password": PASSWORD}).encode()
    req = urllib.request.Request(URL, data=data, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            r.read()
            print("[+] %s : server alive" % DOMAIN)
    except urllib.error.URLError as e:
        print("[-] Gagal koneksi ke %s : %s" % (DOMAIN, e))
        sys.exit(1)


if __name__ == "__main__":
    main()
