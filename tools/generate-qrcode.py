#!/usr/bin/env python3

import argparse
import json
import base64
import sys
import urllib.parse

try:
    import qrcode
    from PIL import Image
except ImportError:
    print("请安装依赖: pip install qrcode[pil]")
    sys.exit(1)


def generate_ss_link(ip, port, password, method="chacha20-ietf-poly1305", name="EasyNet-SS"):
    """生成 Shadowsocks 链接"""
    userinfo = f"{method}:{password}"
    userinfo_b64 = base64.urlsafe_b64encode(userinfo.encode()).decode().rstrip("=")
    link = f"ss://{userinfo_b64}@{ip}:{port}#{urllib.parse.quote(name)}"
    return link


def generate_vmess_link(ip, port, uuid, alter_id=0, network="ws", path="/v2ray", tls="tls", name="EasyNet-V2Ray"):
    """生成 VMess 链接"""
    vmess_config = {
        "v": "2",
        "ps": name,
        "add": ip,
        "port": int(port),
        "id": uuid,
        "aid": alter_id,
        "net": network,
        "type": "none",
        "host": ip,
        "path": path,
        "tls": tls
    }
    vmess_json = json.dumps(vmess_config, ensure_ascii=False)
    vmess_b64 = base64.urlsafe_b64encode(vmess_json.encode()).decode().rstrip("=")
    return f"vmess://{vmess_b64}"


def generate_trojan_link(ip, port, password, path="/trojan", name="EasyNet-Trojan"):
    """生成 Trojan 链接"""
    query = f"security=tls&type=ws&path={urllib.parse.quote(path)}"
    link = f"trojan://{urllib.parse.quote(password)}@{ip}:{port}?{query}#{urllib.parse.quote(name)}"
    return link


def generate_vless_reality_link(ip, port, uuid, public_key, short_id, sni="www.microsoft.com", fp="chrome", flow="xtls-rprx-vision", name="EasyNet-Reality"):
    """生成 VLESS+Reality 链接"""
    query = (
        f"encryption=none&security=reality&sni={urllib.parse.quote(sni)}&"
        f"fp={fp}&pbk={urllib.parse.quote(public_key)}&sid={short_id}&"
        f"type=tcp&flow={flow}"
    )
    link = f"vless://{uuid}@{ip}:{port}?{query}#{urllib.parse.quote(name)}"
    return link


def generate_wireguard_config(private_key, address, dns, public_key, preshared_key, endpoint, allowed_ips="0.0.0.0/0", persistent_keepalive=25):
    """生成 WireGuard 配置文件内容"""
    config = f"""[Interface]
PrivateKey = {private_key}
Address = {address}
DNS = {dns}

[Peer]
PublicKey = {public_key}
PresharedKey = {preshared_key}
Endpoint = {endpoint}
AllowedIPs = {allowed_ips}
PersistentKeepalive = {persistent_keepalive}
"""
    return config


def generate_qrcode(data, output_file="qrcode.png"):
    """生成二维码图片"""
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_H,
        box_size=10,
        border=4,
    )
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save(output_file)
    print(f"二维码已保存到: {output_file}")


def main():
    parser = argparse.ArgumentParser(description="生成代理配置二维码")
    parser.add_argument("--type", required=True, choices=["ss", "vmess", "trojan", "vless", "wireguard"], help="代理类型")
    parser.add_argument("--ip", required=True, help="服务器IP或域名")
    parser.add_argument("--port", required=True, type=int, help="端口号")
    parser.add_argument("--password", help="密码 (SS/Trojan)")
    parser.add_argument("--uuid", help="UUID (VMess/VLESS)")
    parser.add_argument("--method", default="chacha20-ietf-poly1305", help="加密方式 (SS)")
    parser.add_argument("--path", default=None, help="WebSocket路径，VMess 默认 /v2ray，Trojan 默认 /trojan")
    parser.add_argument("--name", default="EasyNet", help="节点名称")
    parser.add_argument("--output", default="qrcode.png", help="输出文件")
    
    parser.add_argument("--public-key", help="公钥 (VLESS/WireGuard)")
    parser.add_argument("--short-id", help="Short ID (VLESS)")
    parser.add_argument("--sni", default="www.microsoft.com", help="SNI (VLESS)")
    parser.add_argument("--fp", default="chrome", help="指纹 (VLESS)")
    parser.add_argument("--flow", default="xtls-rprx-vision", help="流控 (VLESS)")
    
    parser.add_argument("--wg-private-key", help="WireGuard 客户端私钥")
    parser.add_argument("--wg-address", default="10.0.0.2/32", help="WireGuard 客户端地址")
    parser.add_argument("--wg-dns", default="1.1.1.1, 8.8.8.8", help="WireGuard DNS")
    parser.add_argument("--wg-preshared-key", help="WireGuard 预共享密钥")
    parser.add_argument("--wg-allowed-ips", default="0.0.0.0/0", help="WireGuard AllowedIPs")

    args = parser.parse_args()

    link_or_config = ""
    path = args.path
    if args.type == "vmess" and path is None:
        path = "/v2ray"
    if args.type == "trojan" and path is None:
        path = "/trojan"

    if args.type == "ss":
        if not args.password:
            print("错误: SS 需要 --password 参数")
            sys.exit(1)
        link_or_config = generate_ss_link(args.ip, args.port, args.password, args.method, args.name)
    elif args.type == "vmess":
        if not args.uuid:
            print("错误: VMess 需要 --uuid 参数")
            sys.exit(1)
        link_or_config = generate_vmess_link(args.ip, args.port, args.uuid, path=path, name=args.name)
    elif args.type == "trojan":
        if not args.password:
            print("错误: Trojan 需要 --password 参数")
            sys.exit(1)
        link_or_config = generate_trojan_link(args.ip, args.port, args.password, path, args.name)
    elif args.type == "vless":
        if not args.uuid or not args.public_key or not args.short_id:
            print("错误: VLESS 需要 --uuid, --public-key, --short-id 参数")
            sys.exit(1)
        link_or_config = generate_vless_reality_link(
            args.ip, args.port, args.uuid, args.public_key, args.short_id,
            args.sni, args.fp, args.flow, args.name
        )
    elif args.type == "wireguard":
        if not args.wg_private_key or not args.public_key or not args.wg_preshared_key:
            print("错误: WireGuard 需要 --wg-private-key, --public-key, --wg-preshared-key 参数")
            sys.exit(1)
        endpoint = f"{args.ip}:{args.port}"
        link_or_config = generate_wireguard_config(
            args.wg_private_key, args.wg_address, args.wg_dns,
            args.public_key, args.wg_preshared_key, endpoint,
            args.wg_allowed_ips
        )

    if args.type == "wireguard":
        print(f"WireGuard 配置内容:\n{link_or_config}")
        config_file = args.output.replace(".png", ".conf")
        with open(config_file, "w") as f:
            f.write(link_or_config)
        print(f"配置文件已保存到: {config_file}")
        generate_qrcode(link_or_config, args.output)
    else:
        print(f"配置链接: {link_or_config}")
        generate_qrcode(link_or_config, args.output)


if __name__ == "__main__":
    main()
