# Bomalo Tunnel

A reverse tunnel that publishes a foreign VPN server through an Iran server.
The foreign machine dials **out**, so it never needs an open inbound port and its
IP is never contacted directly by users.

```
VPN user ──► Iran VPS  :1194 / :500 / :4500 ...
                 ▲
                 │  one tunnel port (TLS / WSS), dialed out by the foreign VPS
                 │
             Foreign VPS ──► 127.0.0.1:1194  (vpn-ui / Xray / strongSwan / OpenVPN)
```

* Iran server = `mode: server` — owns all public ports and the port map.
* Foreign server = `mode: client` — keeps warm connections open and dials the local services.

## Install (one line, on both servers)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/javadtifusi-eng/BOMALO-TUNNEL/main/install.sh)
```

Then:

1. On the **Iran** server choose `2`, note the token it prints, and add the ports you need.
2. On the **foreign** server choose `3` and paste the Iran IP, port and token.

## Protocol support

| Service | Ports | Works |
|---|---|---|
| OpenVPN | TCP or UDP 1194 | yes |
| L2TP/IPsec | UDP 500, 4500, 1701 | yes, over NAT-T |
| IKEv2 | UDP 500, 4500 | yes, over NAT-T |
| WireGuard | UDP 51820 | yes |
| VLESS / VMess / Trojan / Xray | TCP 443 etc. | yes |
| vpn-ui panel | TCP 8081 | yes |
| SSH, HTTP, any TCP service | any | yes |

Both TCP and UDP are carried. Because the relay rewrites addresses, IPsec peers
detect a NAT between them and switch to NAT-T automatically, so ESP travels
inside UDP 4500. Bare ESP (IP protocol 50) is *not* forwarded — that is a
property of any userspace relay, not a bug.

> Important: the port a service really listens on is not always the port shown
> in an exported config. vpn-ui, for example, serves OpenVPN on **1194**
> internally while its `externalProxy` value (8081) is only the public port
> written into `.ovpn` files. Forward the real listen port.

## Transports

| Value | What it looks like on the wire |
|---|---|
| `tcp` | raw stream, fastest, no disguise |
| `tls` | TLS 1.2+ with a self-signed certificate and a fake SNI |
| `ws` | HTTP `Upgrade: websocket` handshake, then a raw stream |
| `wss` | the same handshake inside TLS — best against DPI |

Note on `ws`/`wss`: the handshake is a byte-accurate WebSocket upgrade, but the
payload afterwards is a raw stream rather than RFC 6455 frames. That defeats
passive DPI; it is not yet enough to sit behind a CDN or an nginx WebSocket
proxy. Full framing is a later pass.

## Configuration

`/etc/bomalo/config.json` on the Iran server:

```json
{
  "mode": "server",
  "listen": "0.0.0.0:8443",
  "transport": "wss",
  "token": "8f3c...",
  "sni": "www.bing.com",
  "path": "/tunnel",
  "forwards": [
    { "name": "OpenVPN", "listen": "0.0.0.0:1194", "net": "udp", "target": "127.0.0.1:1194" },
    { "name": "L2TP",    "listen": "0.0.0.0:4500", "net": "udp", "target": "127.0.0.1:4500" }
  ]
}
```

`target` is resolved **on the foreign server**, so `127.0.0.1` means "the VPN
service running next to the client".

On the foreign server:

```json
{
  "mode": "client",
  "server": "94.249.244.140:8443",
  "transport": "wss",
  "token": "8f3c...",
  "sni": "www.bing.com",
  "path": "/tunnel",
  "pool": 8
}
```

`pool` is how many connections are kept warm. Raising it removes the dial
round-trip for bursty workloads; 8–32 is a sensible range.

## Commands

```bash
bomalo -config /etc/bomalo/config.json   # run in the foreground
bomalo -check                            # validate the config
bomalo -gen-token                        # print a new token
systemctl restart bomalo
journalctl -u bomalo -f
```

## Building manually

```bash
git clone https://github.com/javadtifusi-eng/BOMALO-TUNNEL && cd BOMALO-TUNNEL
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bomalo .
```

Standard library only — no third-party modules.

---

<div dir="rtl">

# بومالو تانل

یک تانل معکوس که سرور VPN خارج را از طریق سرور ایران منتشر می‌کند.
سرور خارج خودش **به بیرون وصل می‌شود**، بنابراین نیازی به پورت باز ورودی ندارد و
کاربران هرگز مستقیم با آی‌پی آن تماس نمی‌گیرند.

* سرور ایران = `mode: server` — همهٔ پورت‌های عمومی و نقشهٔ پورت‌ها اینجاست.
* سرور خارج = `mode: client` — چند کانکشن آماده نگه می‌دارد و به سرویس‌های محلی وصل می‌شود.

## نصب (یک خط، روی هر دو سرور)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/javadtifusi-eng/BOMALO-TUNNEL/main/install.sh)
```

سپس:

۱. روی سرور **ایران** گزینهٔ `2` را بزنید، توکنی که چاپ می‌شود را یادداشت کنید و پورت‌های لازم را اضافه کنید.
۲. روی سرور **خارج** گزینهٔ `3` را بزنید و آی‌پی ایران، پورت و توکن را وارد کنید.

## پشتیبانی از پروتکل‌ها

OpenVPN (TCP/UDP)، L2TP/IPsec، IKEv2، WireGuard، VLESS/VMess/Trojan، پنل vpn-ui
و هر سرویس TCP دیگر. هم TCP و هم UDP منتقل می‌شوند.

چون رله آدرس‌ها را بازنویسی می‌کند، دو طرف IPsec وجود NAT را تشخیص می‌دهند و
خودکار به NAT-T سوییچ می‌کنند؛ یعنی ESP داخل UDP 4500 عبور می‌کند. ESP خام
(پروتکل ۵۰ در لایهٔ IP) منتقل نمی‌شود — این محدودیت هر رلهٔ فضای‌کاربر است.

> نکتهٔ مهم: پورتی که سرویس واقعاً روی آن گوش می‌دهد همیشه همان پورت داخل کانفیگ
> خروجی نیست. مثلاً vpn-ui سرویس OpenVPN را داخلی روی **1194** بالا می‌آورد و
> مقدار `externalProxy` (یعنی 8081) فقط پورت عمومی داخل فایل `.ovpn` است.
> باید پورت واقعی گوش‌دادن را فوروارد کنید.

## ترنسپورت‌ها

`tcp` سریع‌ترین و بدون استتار، `tls` با گواهی self-signed و SNI جعلی،
`ws` دست‌دادن HTTP/WebSocket و `wss` همان دست‌دادن داخل TLS (بهترین حالت مقابل DPI).

دربارهٔ `ws`/`wss`: دست‌دادن دقیقاً مطابق WebSocket است اما دادهٔ بعد از آن به‌صورت
استریم خام منتقل می‌شود، نه فریم‌های RFC 6455. این کار DPI غیرفعال را دور می‌زند
ولی هنوز برای عبور از CDN یا پراکسی WebSocket نginx کافی نیست. فریم‌بندی کامل در
مرحلهٔ بعد اضافه می‌شود.

## نکات پیکربندی

فیلد `target` روی **سرور خارج** حل می‌شود، پس `127.0.0.1` یعنی سرویس VPN کنار
همان کلاینت. مقدار `pool` تعداد کانکشن‌های آمادهٔ نگه‌داشته‌شده است؛ بازهٔ ۸ تا ۳۲
منطقی است.

## دستورها

```bash
bomalo -check        # بررسی صحت کانفیگ
bomalo -gen-token    # ساخت توکن جدید
systemctl restart bomalo
journalctl -u bomalo -f
```

</div>
