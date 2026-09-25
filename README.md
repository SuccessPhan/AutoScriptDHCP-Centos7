# CentOS 7 DHCP Automation Manager

**For NetDevOps, Sysadmin, and Automated Network Management with first-class support for RHEL/CentOS 7**

![Release](https://img.shields.io/badge/release-v1.0.0-blue.svg) ![Shell](https://img.shields.io/badge/shell-Bash%204.2%2B-lightgrey.svg) ![License](https://img.shields.io/badge/license-MIT-green.svg)

```bash
# Auto-generated standard configuration by DHCP Manager
authoritative;

subnet 192.168.10.0 netmask 255.255.255.0 {
    range 192.168.10.2 192.168.10.101;
    option routers 192.168.10.1;
    option domain-name "sgu.edu.vn";
    default-lease-time 600;
    max-lease-time 7200;
}

```

Được xây dựng trên nền tảng Bash Shell, DHCP Automation Manager là cầu nối giữa phương thức quản trị mạng thủ công truyền thống và tư duy tự động hóa hạ tầng (Infrastructure as Code). Hệ thống cung cấp khả năng tự động nội suy mạng (Subnetting), xác thực IPv4 đa tầng, và bảo vệ tính toàn vẹn của kết nối thông qua cơ chế dọn dẹp bộ nhớ đệm (Selective Lease Purging).

Dành cho các hệ thống Lab thực hành và môi trường Enterprise, công cụ này giải quyết triệt để các bài toán cốt lõi: kẹt IP tĩnh trên máy trạm, xung đột Gateway, cấp phát nhầm lớp mạng cấm (Class D/E, Loopback). Tất cả được tích hợp trọn vẹn trong một giao diện CLI tương tác trực quan, dễ dàng mở rộng và triển khai độc lập.

## Try DHCP Manager in 5 Minutes

**Cài đặt Hệ thống (Installation)**

Triển khai cấu trúc thư mục và cấp quyền thực thi trực tiếp trên môi trường CentOS 7 / RHEL 7:

```bash
# 1. Tải mã nguồn dự án về máy chủ
git clone https://github.com/your-username/centos-dhcp-manager.git

# 2. Truy cập vào thư mục dự án
cd centos-dhcp-manager

# 3. Cấp quyền thực thi cho kịch bản chính và thư viện lõi
chmod +x dhcp_manager.sh lib_dhcp_core.sh

# 4. Khởi chạy Bảng điều khiển (Yêu cầu quyền Root)
sudo ./dhcp_manager.sh

```

**Khởi tạo Dải mạng đầu tiên (Create Your First Scope)**

Tại giao diện điều khiển, chọn `[1]`. Kích hoạt tính năng Auto-Fill để hệ thống tự động bóp dải Range và tính toán Gateway an toàn:

```text
Nhập Subnet (VD: 192.168.1.0): 192.168.10.0
Nhập Netmask (VD: 255.255.255.0): 255.255.255.0
>> Kích hoạt Cấu hình Mặc định (Auto-Fill)? (y/n): y
Nhập Domain Name (VD: sgu.edu.vn): sgu.edu.vn

```

**Cấp phát IP Tĩnh (Assign a Static Host)**

Gắn cố định địa chỉ IP cho các thiết bị hạ tầng (Máy in, Database Server) từ Menu `[4]`:

```text
Nhập Hostname (VD: printer_01): server_db
Nhập địa chỉ MAC: 00:0c:29:86:ef:e2
Nhập IP tĩnh cần gán: 192.168.10.201

```

*Lưu ý: Để áp dụng mọi thay đổi vào hệ thống, truy cập Menu `[7] Quản lý dịch vụ` -> chọn `[2] Khởi động lại (Restart)`.*

## Why CentOS 7 DHCP Manager

Từ việc thiết lập Subnet đến thao tác dọn dẹp lịch sử kết nối, công cụ mang quy chuẩn của một hệ thống mạng Layer 3 chuyên nghiệp vào từng dòng lệnh.

**Native IPv4 Validation Support**

Ngăn chặn sai sót cấu hình ngay từ vòng ngoài. Hệ thống tự động từ chối khai báo các dải IP cấm định tuyến nội bộ (Class D/E, Loopback 127.x.x.x, APIPA 169.254.x.x). Ép buộc địa chỉ IP Gateway phải nằm ngoài dải Range cấp phát động, loại trừ hoàn toàn rủi ro xung đột thiết bị định tuyến lõi.

**Selective Lease Purging Integration**

Can thiệp sâu vào sổ lưu trữ `/var/lib/dhcpd/dhcpd.leases` thông qua biểu thức chính quy (Regex). Khi quản trị viên thu hồi một Host hoặc xóa một Scope, hệ thống chỉ dọn sạch chính xác Block lịch sử của IP mục tiêu đó, đảm bảo **không gây gián đoạn mạng (Zero Downtime)** cho hàng loạt thiết bị khác đang hoạt động.

**Authoritative Network Security**

Mặc định kích hoạt chế độ `authoritative` để thiết lập quyền lực tối cao cho Server. Khi phát hiện Client cố chấp sử dụng IP cũ hoặc bị tước đặc quyền IP tĩnh, máy chủ lập tức phát lệnh phủ quyết (`DHCPNAK`), buộc thiết bị trạm phải văng mạng và xin cấp lại dải IP động mới ngay tức thì.

**Auto-Provisioning and Routing Logic**

Loại bỏ rủi ro sập mạng do tính toán thủ công sai lệch. Tích hợp engine `ipcalc` để nội suy Network Address và Broadcast Address. Thuật toán Auto-Fill chủ động giới hạn dải `Range` động trong 100 IP đầu tiên, tạo ra một không gian an toàn (Safe Zone) vĩnh viễn cho toàn bộ hạ tầng IP tĩnh của doanh nghiệp.

## 📜 Giấy phép & Bản quyền (License & Usage)

**Dự án này được phân phối mã nguồn mở dưới giấy phép [MIT License](https://opensource.org/licenses/MIT?utm_source=gemini).**

Giấy phép MIT cấp cho người dùng quyền hạn tối đa trong việc khai thác phần mềm. Cụ thể, bạn được cấp quyền:

* ✅ **Sử dụng thương mại (Commercial Use):** Tự do triển khai và tích hợp công cụ này vào hệ thống máy chủ của công ty hoặc doanh nghiệp.
* ✅ **Sửa đổi (Modification):** Tự do thay đổi mã nguồn, tùy biến các luồng chức năng (`lib_dhcp_core.sh`) để phù hợp với kiến trúc hạ tầng mạng riêng biệt.
* ✅ **Phân phối (Distribution):** Chia sẻ, sao chép, đóng gói lại hoặc sử dụng làm tài liệu tham khảo cốt lõi cho các đồ án/luận văn học thuật.
* ✅ **Sử dụng cá nhân (Private Use):** Triển khai trên các hệ thống Lab cá nhân (VMware, VirtualBox, Proxmox).

```
