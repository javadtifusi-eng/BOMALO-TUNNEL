<p align="center">
  <img src="assets/logo.jpg" alt="Bomalo" width="190">
</p>

<p align="center">
  <img src="banner.svg" alt="Bomalo Tunnel" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/language-Go-00ADD8?style=flat-square&logo=go&logoColor=white">
  <img src="https://img.shields.io/badge/dependencies-stdlib%20only-2ea44f?style=flat-square">
  <img src="https://img.shields.io/badge/transport-TCP%20%7C%20TLS%20%7C%20WS%20%7C%20WSS-8957e5?style=flat-square">
  <img src="https://img.shields.io/badge/inbound%20ports%20abroad-0-c8102e?style=flat-square">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

<p align="center">
  <a href="#english">🇬🇧 English</a> &nbsp;/&nbsp; <a href="#فارسی"><img src="assets/flag-ir.png" width="16" height="16"> فارسی</a>
</p>

<a name="english"></a>
## English

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
bash <(curl -fsSL https://raw.githubusercontent.com/javadtifusi-eng/Tifusi-Tunnel/main/install.sh)
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
| `ws` | HTTP `Upgrade: websocket` handshake, then real RFC 6455 frames |
| `wss` | the same, inside TLS — best against DPI, and safe to sit behind a WebSocket-aware reverse proxy or CDN |
| `tcpmux` | like `tcp`, but multiplexed — see below |
| `wsmux` | like `ws`, but multiplexed |
| `wssmux` | like `wss`, but multiplexed |

Note on `ws`/`wss`: both the handshake and the traffic after it are real
WebSocket — every tunnel message is sent as one binary frame (masked when
sent by the client, per RFC 6455), fragmented frames from an intermediary
are reassembled transparently, and pings are answered automatically. This
is what makes it possible to place the Iran-side server behind an nginx
WebSocket proxy or a CDN instead of only a plain TCP passthrough.

### Plain vs. mux transports

`tcp`/`tls`/`ws`/`wss` open one physical connection per forwarded TCP
session or UDP flow, drawn from a pool of `pool` connections the foreign
server keeps warm. Simple, and works well.

`tcpmux`/`wsmux`/`wssmux` instead keep a small, fixed number of physical
connections open (`mux_con`, default 8 — Backhaul users will recognize the
model) and multiplex every session as a logical stream over whichever one
is picked, the way [Backhaul](https://github.com/Musixal/Backhaul) does.
This means far fewer open sockets and handshakes on the foreign server
under many simultaneous sessions, at the cost of some head-of-line
blocking on each physical connection when it is very busy — raise
`mux_con` to spread load across more of them.

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
  "server": "IRAN_SERVER_IP:8443",
  "transport": "wss",
  "token": "8f3c...",
  "sni": "www.bing.com",
  "path": "/tunnel",
  "pool": 8
}
```

`pool` is how many connections are kept warm (plain transports). Raising it
removes the dial round-trip for bursty workloads; 8–32 is a sensible range.
For a mux transport (`tcpmux`/`wsmux`/`wssmux`), `mux_con` plays the
equivalent role: it is how many physical connections carry all the
multiplexed sessions.

## Commands

```bash
bm                                       # open the management menu
bomalo -config /etc/bomalo/config.json   # run in the foreground
bomalo -check                            # validate the config
bomalo -gen-token                        # print a new token
systemctl restart bomalo
journalctl -u bomalo -f
```

## Building manually

```bash
git clone https://github.com/javadtifusi-eng/Tifusi-Tunnel && cd Tifusi-Tunnel
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bomalo .
```

Standard library only — no third-party modules.

---

<a name="فارسی"></a>
<div dir="rtl">

# بومالو تانل

[⬆ English](#english)

یک تانل معکوس که سرور VPN خارج را از طریق سرور ایران منتشر می‌کند.
سرور خارج خودش **به بیرون وصل می‌شود**، بنابراین نیازی به پورت باز ورودی ندارد و
کاربران هرگز مستقیم با آی‌پی آن تماس نمی‌گیرند.

* سرور ایران = `mode: server` — همهٔ پورت‌های عمومی و نقشهٔ پورت‌ها اینجاست.
* سرور خارج = `mode: client` — چند کانکشن آماده نگه می‌دارد و به سرویس‌های محلی وصل می‌شود.

## نصب (یک خط، روی هر دو سرور)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/javadtifusi-eng/Tifusi-Tunnel/main/install.sh)
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

علاوه بر این‌ها سه ترنسپورت **multiplex** هم هست: `tcpmux`، `wsmux` و `wssmux`
(دقیقاً همون مدلی که [Backhaul](https://github.com/Musixal/Backhaul) استفاده می‌کنه).
حالت‌های معمولی به ازای هر سشن (هر اتصال TCP یا هر جریان UDP) یک کانکشن فیزیکی
جدا از استخر `pool` برمی‌دارند؛ حالت‌های mux برعکس، فقط تعداد ثابتی کانکشن فیزیکی
(`mux_con`، پیش‌فرض ۸) باز نگه می‌دارند و همهٔ سشن‌ها را روی همون چند کانکشن
multiplex می‌کنند — یعنی زیر بار زیاد، سوکت و هندشیک بسیار کمتری روی سرور خارج
باز می‌مونه. اگر زیر بار سنگین کندی دیدید، `mux_con` را بالا ببرید.

دربارهٔ `ws`/`wss`: هم دست‌دادن، هم دادهٔ بعد از آن، هر دو WebSocket واقعی
هستند — هر پیام تانل به‌صورت یک فریم باینری RFC 6455 فرستاده می‌شود (با
ماسک، وقتی کلاینت می‌فرستد)، فریم‌های تکه‌شده توسط یک واسط دوباره سرهم
می‌شوند، و پینگ‌ها خودکار جواب داده می‌شوند. همین باعث می‌شود بشود سرور
ایران را پشت یک پراکسی WebSocket واقعی (nginx) یا یک CDN گذاشت، نه فقط
یک پاس‌ثرو TCP ساده.

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
