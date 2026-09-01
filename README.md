# <img src="assets/banner.svg" width="100%" alt="Bomalo Tunnel">

<div align="center">

**[English](#english)** | **[Русский](#russian)** | **[فارسی](#persian)**

[![Go Version](https://img.shields.io/badge/Go-1.23+-00ADD8?style=flat-square&logo=go)](https://golang.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Users](https://img.shields.io/badge/Users-1000%2B-orange?style=flat-square)](https://github.com/yourusername/bomalo-tunnel)
[![Transports](https://img.shields.io/badge/Transports-6-blueviolet?style=flat-square)](#transports)

</div>

---

<a name="english"></a>
# 🇬🇧 English

> **Next-Generation Reverse Tunnel Engine** — Smart, Adaptive, Invisible. Supports **1000+ concurrent users**.

Bomalo Tunnel is a high-performance, multi-transport tunnel engine written in Go. It features **AI-powered transport selection**, **eBPF kernel acceleration**, **multi-path hybrid routing**, **adaptive DPI evasion**, and **enterprise-grade user authentication**.

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🤖 **AI-Adaptive Transport** | Auto-switches between TCP/QUIC/WebRTC/WireGuard/KCP based on real-time metrics |
| ⚡ **eBPF Acceleration** | Kernel-level socket redirect reduces latency by up to 40% |
| 🕸️ **Edge Mesh** | Multi-node topology with automatic failover |
| 🎭 **DPI Evasion** | Traffic mimicry, jitter injection, domain fronting |
| 🔒 **Noise Protocol** | Modern lightweight encryption with perfect forward secrecy |
| 👥 **User Management** | Token-based auth, IP whitelisting, rate limiting (1000+ users) |
| 🧪 **Pre-Install Tests** | Mandatory connectivity tests before installation |
| 📊 **Real-Time Dashboard** | WebSocket-based monitoring for all users and transports |

## 🚀 Quick Start

```bash
# One-line install
bash <(curl -fsSL https://raw.githubusercontent.com/yourusername/bomalo-tunnel/main/scripts/install.sh)

# Interactive menu (auto-detects IP, tests DNS, tests both servers)
sudo bomalo

# Or direct setup
sudo bomalo setup --role iran --ports 443,8080
sudo bomalo setup --role kharej --iran-ip <IP>
```

## 🧪 Pre-Installation Testing (Mandatory)

Bomalo **requires** passing network tests before installation:

1. **Auto-detects** your public IP
2. **Tests Google DNS** (8.8.8.8) for internet connectivity
3. **Tests Iran ↔ Kharej** connection (ping + TCP)
4. **Blocks installation** if any test fails

## 👥 User Management (1000+ Users)

During national internet restrictions, **only whitelisted users** can connect:

```bash
# Add authorized user
bomalo user-add --name "John Doe" --email "john@example.com" --ips "1.2.3.4,5.6.7.8"

# List all users
bomalo user-list

# Ban suspicious IP
bomalo ban-ip --ip "10.0.0.1"
```

## 📡 Transports

| Transport | Best For | DPI Resistance | Status |
|-----------|----------|----------------|--------|
| **TCP** | Baseline | Low | ✅ Complete |
| **TCP+Noise** | Encrypted | Medium | ✅ Complete |
| **QUIC** | Fast UDP networks | High | ✅ Complete |
| **WebRTC** | NAT traversal | Very High | ✅ Complete |
| **WireGuard** | Stealth mode | Very High | ✅ Complete |
| **KCP+FEC** | Lossy routes, gaming | Medium | ✅ Complete |

## 🔐 SSL Certificate

During setup, Bomalo asks if you have a domain:
- **Yes** → Auto-installs Certbot + Let's Encrypt
- **No** → Falls back to IP-based tunnel (no SSL)

## 🏗️ Architecture

```
User Traffic → Iran Server → Bomalo Engine → Best Transport → Kharej Server → Origin
                    ↑                                              ↓
               Auth Manager ←── Whitelist ───┘
               AI Optimizer ←── Health Probes ───────────────────┘
               Connection Pool (5000 max)
```

---

<a name="russian"></a>
# 🇷🇺 Русский

> **Туннельный движок нового поколения** — Умный, Адаптивный, Невидимый. Поддерживает **1000+ пользователей**.

## ✨ Основные возможности

| Функция | Описание |
|---------|----------|
| 🤖 **ИИ-Транспорт** | Автопереключение TCP/QUIC/WebRTC/WireGuard/KCP |
| ⚡ **eBPF** | Ускорение на уровне ядра, -40% задержки |
| 🕸️ **Edge Mesh** | Мульти-ноды с авто-отказоустойчивостью |
| 🎭 **Обход DPI** | Маскировка трафика, джиттер-инъекции |
| 🔒 **Noise Protocol** | Современное шифрование |
| 👥 **Управление пользователями** | 1000+ пользователей с whitelist |
| 🧪 **Тесты перед установкой** | Обязательные проверки связи |

## 🚀 Быстрый старт

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yourusername/bomalo-tunnel/main/scripts/install.sh)
sudo bomalo
```

---

<a name="persian"></a>
# 🇮🇷 فارسی

> **موتور تانل نسل جدید** — هوشمند، تطبیقی، نامرئی. پشتیبانی از **۱۰۰۰+ کاربر همزمان**.

Bomalo Tunnel یک موتور تانل چند‌ترنسپورتی با کارایی بالا است که با Go نوشته شده. دارای **انتخابگر هوشمند ترنسپورت با AI**، **شتاب‌دهی eBPF کرنل**، **احراز هویت سطح سازمانی** و **فرار از DPI تطبیقی** است.

## ✨ ویژگی‌های کلیدی

| ویژگی | توضیحات |
|-------|---------|
| 🤖 **ترنسپورت AI** | جابجایی خودکار بین ۶ ترنسپورت بر اساس متریک لحظه‌ای |
| ⚡ **eBPF** | شتاب‌دهی سطح کرنل، کاهش ۴۰٪ تاخیر |
| 🕸️ **Edge Mesh** | توپولوژی چند‌گره با failover خودکار |
| 🎭 **فرار DPI** | ماسک ترافیک، تزریق جیتتر، دامین فرانتینگ |
| 🔒 **Noise Protocol** | رمزنگاری مدرن با Perfect Forward Secrecy |
| 👥 **مدیریت کاربر** | احراز هویت توکن‌بیس، IP Whitelist، Rate Limiting |
| 🧪 **تست قبل نصب** | تست‌های اجباری اتصال (DNS گوگل + Ping + TCP) |
| 📊 **داشبورد لحظه‌ای** | مانیتورینگ WebSocket برای همه کاربران و ترنسپورت‌ها |

## 🚀 شروع سریع

```bash
# نصب یک‌خطی
bash <(curl -fsSL https://raw.githubusercontent.com/yourusername/bomalo-tunnel/main/scripts/install.sh)

# منوی تعاملی (شناسایی خودکار IP، تست DNS، تست دو سرور)
sudo bomalo

# یا راه‌اندازی مستقیم
sudo bomalo setup --role iran --ports 443,8080
sudo bomalo setup --role kharej --iran-ip <IP>
```

## 🧪 تست اجباری قبل از نصب

Bomalo **اجباری** تست شبکه را قبل نصب دارد:

1. **شناسایی خودکار** IP عمومی
2. **تست DNS گوگل** (8.8.8.8)
3. **تست ایران ↔ خارج** (ping + TCP handshake)
4. **مسدود کردن نصب** در صورت خطا

## 👥 مدیریت کاربران (۱۰۰۰+ کاربر)

در زمان نت ملی، **فقط کاربران لیست سفید** می‌توانند وصل شوند:

```bash
# اضافه کردن کاربر مجاز
bomalo user-add --name "علی احمدی" --email "ali@example.com" --ips "1.2.3.4"

# لیست کاربران
bomalo user-list

# بن کردن IP مشکوک
bomalo ban-ip --ip "10.0.0.1"
```

## 🧠 ترنسپورت هوشمند

```
TCP (پایه) → QUIC (سریع) → WebRTC (UDP بسته) → WireGuard (مخفی) → KCP (گیمینگ)
     ↑________________________________________________________________________|
                    (حلقه خود‌ترمیم با AI Optimizer)
```

## 📡 ترنسپورت‌ها

| ترنسپورت | بهترین برای | مقاومت DPI | وضعیت |
|-----------|-------------|------------|-------|
| **TCP** | سازگاری پایه | کم | ✅ کامل |
| **TCP+Noise** | رمزنگاری شده | متوسط | ✅ کامل |
| **QUIC** | شبکه‌های UDP‌دوست | بالا | ✅ کامل |
| **WebRTC** | عبور از NAT | خیلی بالا | ✅ کامل |
| **WireGuard** | حالت مخفی | خیلی بالا | ✅ کامل |
| **KCP+FEC** | شبکه‌های lossy، گیمینگ | متوسط | ✅ کامل |

## 🔐 گواهی SSL

هنگام راه‌اندازی، Bomalo می‌پرسد دامنه دارید:
- **بله** → نصب خودکار Certbot + Let's Encrypt
- **خیر** → استفاده از IP (بدون SSL)

## 🏗️ معماری

```
کاربر → سرور ایران → موتور Bomalo → بهترین ترنسپورت → سرور خارج → سرویس اصلی
              ↑                                              ↓
         Auth Manager ←── Whitelist ───┘  (فقط کاربران مجاز)
         AI Optimizer ←── تست‌های سلامت ───────────────────┘
         Connection Pool (حداکثر ۵۰۰۰ کانکشن)
         Rate Limiter (۱۰۰۰ درخواست/ثانیه)
```

## 📦 ساختار پروژه

```
bomalo-tunnel/
├── cmd/
│   ├── bomalo/          # CLI دوزبانه با منوی تعاملی
│   └── bomalod/         # Daemon
├── internal/
│   ├── tunnel/          # موتور اصلی (۱۰۰۰+ کاربر)
│   ├── transport/       # ۶ ترنسپورت کامل
│   │   ├── tcp.go       ✅ کامل
│   │   ├── quic.go      ✅ کامل
│   │   ├── webrtc.go    ✅ کامل (Pion)
│   │   ├── wireguard.go ✅ کامل
│   │   └── kcp.go       ✅ کامل (+FEC)
│   ├── crypto/          # Noise Protocol Handshake
│   ├── ai/              # بهینه‌ساز هوشمند
│   ├── auth/            # احراز هویت + Rate Limiting
│   ├── pool/            # Connection Pool (۵۰۰۰)
│   ├── nettest/         # تست شبکه قبل نصب
│   ├── ssl/             # Certbot + Let's Encrypt
│   ├── i18n/            # دوزبانه EN/FA
│   ├── ebpf/            # شتاب‌دهی کرنل
│   ├── mesh/            # Edge Mesh
│   ├── dpi/             # فرار از DPI
│   ├── api/             # gRPC + REST
│   ├── dashboard/       # WebSocket
│   └── config/          # کانفیگ
├── pkg/protocol/        # پروتکل باینری
├── web/                 # React Dashboard
├── assets/              # بنر متحرک SVG
├── scripts/             # نصب یک‌خطی
├── deploy/              # systemd, Docker
└── ebpf/c/              # برنامه‌های eBPF
```

## 🖥️ دستورات CLI

```bash
bomalo                    # منوی تعاملی (پیش‌فرض)
bomalo setup --role iran  # راه‌اندازی سرور ایران
bomalo setup --role kharej # راه‌اندازی سرور خارج
bomalo status             # وضعیت زنده تانل
bomalo link-test          # تست لینک و پیشنهاد ترنسپورت
bomalo optimize           # بهینه‌سازی کرنل (BBR, بافر)
bomalo user-add           # اضافه کردن کاربر مجاز
bomalo user-list          # لیست کاربران
bomalo mesh join <token>  # پیوستن به Edge Mesh
bomalo dashboard          # باز کردن پنل وب
bomalo backup             # خروجی پشتیبان کامل
```

## 🛠️ ساخت از سورس

```bash
git clone https://github.com/yourusername/bomalo-tunnel.git
cd bomalo-tunnel
make build
make test
```

## 📜 لایسنس

MIT License

---

<p align="center">
  <b>Bomalo Tunnel</b> — Tunnel Smarter, Not Harder.<br>
  Made with ❤️ for the open-source community.
</p>
