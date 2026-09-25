#!/bin/bash
# ==========================================
# FILE: dhcp_manager.sh (Bản Hoàn thiện)
# ==========================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib_dhcp_core.sh"

conf_file="/etc/dhcp/dhcpd.conf"
leases_file="/var/lib/dhcpd/dhcpd.leases"

if [ "$EUID" -ne 0 ]; then
    echo "-> [LỖI] Vui lòng thực thi bằng quyền root (sudo)!"
    exit 1
fi

# ==========================================
# AUTO-INSTALL: TỰ ĐỘNG CHUẨN BỊ MÔI TRƯỜNG
# ==========================================
check_and_install_dependencies() {
    echo "-> [HỆ THỐNG] Đang kiểm tra môi trường triển khai..."
    
    if systemctl is-active --quiet firewalld; then
        echo "-> [HỆ THỐNG] Vô hiệu hóa Tường lửa (Firewalld) để mở cổng giao tiếp..."
        systemctl stop firewalld > /dev/null 2>&1
        systemctl disable firewalld > /dev/null 2>&1
    fi

    if ! rpm -qa | grep -qw dhcp; then
        echo "-> [HỆ THỐNG] Đang cài đặt dịch vụ DHCP..."
        yum install dhcp -y > /dev/null 2>&1
        if [ $? -ne 0 ]; then echo "-> [LỖI] Tiến trình cài đặt thất bại!"; exit 1; fi
    fi
    
    if ! command -v ipcalc &> /dev/null; then
        echo "-> [HỆ THỐNG] Đang bổ sung gói initscripts (ipcalc)..."
        yum install initscripts -y > /dev/null 2>&1
    fi
    echo "-> [HỆ THỐNG] Môi trường đã sẵn sàng!"
}
check_and_install_dependencies

# ==========================================
# HÀM BỔ TRỢ: CHUYỂN ĐỔI SỐ NGUYÊN THÀNH IP
# ==========================================
int_to_ip() {
    local ui32=$1; local ip n
    for n in 1 2 3 4; do
        ip=$((ui32 & 0xff))${ip:+.}$ip
        ui32=$((ui32 >> 8))
    done
    echo $ip
}

# ==========================================
# LUỒNG 1: TẠO SCOPE
# ==========================================
create_scope() {
    echo ""
    echo "========== [1] KHỞI TẠO SCOPE MỚI =========="
    
    get_valid_network_logic
    if check_scope_exists "$subnet"; then echo "-> [LỖI] Subnet $subnet đã tồn tại trên hệ thống!"; return; fi

    read -p ">> Kích hoạt Cấu hình Mặc định (Auto-Fill)? (y/n): " use_default

    if [[ "$use_default" == "y" || "$use_default" == "Y" ]]; then
        echo "-> [HỆ THỐNG] Đang thiết lập thông số..."
        
        get_valid_domain "Nhập Domain Name (VD: sgu.edu.vn): " domain
        
        broadcast=$(ipcalc -b "$subnet" "$netmask" 2>/dev/null | cut -d= -f2)
        net_int=$(ip_to_int "$subnet")
        bcast_int=$(ip_to_int "$broadcast")
        
        router=$(int_to_ip $((net_int + 1)))
        ip_start=$(int_to_ip $((net_int + 2)))
        
        calc_end=$((net_int + 101))
        if [ "$calc_end" -ge "$bcast_int" ]; then
            calc_end=$((bcast_int - 1))
        fi
        ip_end=$(int_to_ip $calc_end)
        
        dns_ip="8.8.8.8"
        lease_default=600
        lease_max=7200
        
        echo "--- THÔNG SỐ TỰ ĐỘNG TÍNH TOÁN ---"
        echo " [+] Dải IP : $ip_start -> $ip_end"
        echo " [+] Gateway: $router"
        echo " [+] Domain : $domain"
        echo " [+] DNS    : $dns_ip"
        echo "----------------------------------"
    else
        get_ip_in_subnet "Nhập IP bắt đầu: " ip_start "$subnet" "$netmask"
        while true; do
            get_ip_in_subnet "Nhập IP kết thúc: " ip_end "$subnet" "$netmask"
            if [ $(ip_to_int "$ip_end") -gt $(ip_to_int "$ip_start") ]; then break; else echo "-> [LỖI] IP kết thúc phải lớn hơn IP bắt đầu!"; fi
        done
        
        get_valid_domain "Nhập Domain Name: " domain
        
        while true; do
            get_ip_in_subnet "Nhập Default Gateway: " router "$subnet" "$netmask"
            if check_router_conflict "$router" "$ip_start" "$ip_end"; then break; else echo "-> [LỖI] Gateway không được nằm trong dải cấp phát!"; fi
        done
        
        broadcast=$(ipcalc -b "$subnet" "$netmask" 2>/dev/null | cut -d= -f2)
        while true; do read -p "Nhập máy chủ DNS: " dns_ip; if is_valid_ip "$dns_ip"; then break; else echo "-> [LỖI] IP không hợp lệ!"; fi; done
        
        get_valid_lease_times lease_default lease_max
    fi

    cat >> "$conf_file" <<EOF

subnet $subnet netmask $netmask {
    range $ip_start $ip_end;
    option domain-name "$domain";
    option routers $router;
    option broadcast-address $broadcast;
    option domain-name-servers $dns_ip;
    default-lease-time $lease_default;
    max-lease-time $lease_max;
}
EOF
    echo "-> [THÀNH CÔNG] Đã ghi nhận cấu hình mạng $subnet!"
}

# ==========================================
# LUỒNG 2: CẬP NHẬT SCOPE
# ==========================================
update_scope() {
    echo ""
    echo "========== [2] CẬP NHẬT SCOPE =========="
    read -p "Nhập Subnet cần cập nhật: " subnet
    if ! check_scope_exists "$subnet"; then echo "-> [LỖI] Scope $subnet không tồn tại!"; return; fi
    current_netmask=$(sed -n "/^subnet $subnet / s/^subnet .* netmask \([0-9.]*\) {/\1/p" "$conf_file")

    while true; do
        echo ""
        echo "1. Dải IP | 2. Gateway | 3. DNS | 4. Domain | 5. Lease Time | 6. Hoàn tất"
        read -p "Chọn tác vụ (Hỗ trợ cấu hình đa mục, VD: 1 2): " choices
        
        if [[ "$choices" == *"6"* ]]; then echo "-> [HỆ THỐNG] Đã thoát tiến trình cập nhật."; break; fi

        for choice in $choices; do
            case $choice in
                1)
                    current_end=$(sed -n "/^subnet $subnet /,/^}/ s/^[[:space:]]*range [0-9.]* \([0-9.]*\);/\1/p" "$conf_file")
                    get_ip_in_subnet "Nhập IP bắt đầu mới: " new_start "$subnet" "$current_netmask"
                    if [ $(ip_to_int "$new_start") -ge $(ip_to_int "$current_end") ]; then
                        echo "-> Yêu cầu thiết lập lại IP kết thúc!"
                        while true; do
                            get_ip_in_subnet "Nhập IP kết thúc mới: " new_end "$subnet" "$current_netmask"
                            if [ $(ip_to_int "$new_end") -gt $(ip_to_int "$new_start") ]; then
                                sed -i "/^subnet $subnet /,/^}/ s/^[[:space:]]*range .*/    range $new_start $new_end;/" "$conf_file"; break
                            else echo "-> [LỖI] Phải lớn hơn IP bắt đầu!"; fi
                        done
                    else
                        sed -i "/^subnet $subnet /,/^}/ s/^[[:space:]]*range .*/    range $new_start $current_end;/" "$conf_file"
                    fi
                    echo "-> Đã cập nhật Dải IP." ;;
                2)
                    current_start=$(sed -n "/^subnet $subnet /,/^}/ s/^[[:space:]]*range \([0-9.]*\) [0-9.]*;/\1/p" "$conf_file")
                    current_end=$(sed -n "/^subnet $subnet /,/^}/ s/^[[:space:]]*range [0-9.]* \([0-9.]*\);/\1/p" "$conf_file")
                    while true; do
                        get_ip_in_subnet "Nhập Gateway mới: " new_router "$subnet" "$current_netmask"
                        if check_router_conflict "$new_router" "$current_start" "$current_end"; then
                            if sed -n "/^subnet $subnet /,/^}/p" "$conf_file" | grep -q "option routers"; then
                                sed -i "/^subnet $subnet /,/^}/ s/^[[:space:]]*option routers .*/    option routers $new_router;/" "$conf_file"
                            else sed -i "/^subnet $subnet /,/^}/ s/^}/    option routers $new_router;\n}/" "$conf_file"; fi
                            echo "-> Đã cập nhật Gateway."; break
                        else echo "-> [LỖI] Gateway nằm trong dải cấp phát!"; fi
                    done ;;
                3)
                    while true; do read -p "Nhập DNS mới: " new_dns; if is_valid_ip "$new_dns"; then break; else echo "-> [LỖI] IP không hợp lệ!"; fi; done
                    if sed -n "/^subnet $subnet /,/^}/p" "$conf_file" | grep -q "option domain-name-servers"; then sed -i "/^subnet $subnet /,/^}/ s/^[[:space:]]*option domain-name-servers .*/    option domain-name-servers $new_dns;/" "$conf_file"
                    else sed -i "/^subnet $subnet /,/^}/ s/^}/    option domain-name-servers $new_dns;\n}/" "$conf_file"; fi
                    echo "-> Đã cập nhật DNS." ;;
                4)
                    get_valid_domain "Nhập Domain Name mới: " new_domain
                    if sed -n "/^subnet $subnet /,/^}/p" "$conf_file" | grep -q "option domain-name "; then sed -i "/^subnet $subnet /,/^}/ s/^[[:space:]]*option domain-name .*/    option domain-name \"$new_domain\";/" "$conf_file"
                    else sed -i "/^subnet $subnet /,/^}/ s/^}/    option domain-name \"$new_domain\";\n}/" "$conf_file"; fi
                    echo "-> Đã cập nhật Domain." ;;
                5)
                    get_valid_lease_times new_default new_max
                    if sed -n "/^subnet $subnet /,/^}/p" "$conf_file" | grep -q "default-lease-time"; then
                        sed -i "/^subnet $subnet /,/^}/ s/^[[:space:]]*default-lease-time .*/    default-lease-time $new_default;/" "$conf_file"
                        sed -i "/^subnet $subnet /,/^}/ s/^[[:space:]]*max-lease-time .*/    max-lease-time $new_max;/" "$conf_file"
                    else sed -i "/^subnet $subnet /,/^}/ s/^}/    default-lease-time $new_default;\n    max-lease-time $new_max;\n}/" "$conf_file"; fi
                    echo "-> Đã cập nhật Lease Time." ;;
                *) echo "-> [CẢNH BÁO] Lựa chọn không hợp lệ." ;;
            esac
        done
    done
}

# ==========================================
# LUỒNG 3: XÓA SCOPE
# ==========================================
delete_scope() {
    echo ""
    echo "========== [3] XÓA SCOPE =========="
    read -p "Nhập Subnet cần xóa: " subnet
    if ! check_scope_exists "$subnet"; then echo "-> [LỖI] Scope không tồn tại!"; return; fi
    sed -i "/^subnet $subnet /,/^}/d" "$conf_file"
    echo "-> [THÀNH CÔNG] Đã xóa Scope $subnet!"
}

# ==========================================
# LUỒNG 4: TẠO HOST
# ==========================================
create_host() {
    echo ""
    echo "========== [4] CẤP PHÁT IP TĨNH (HOST) =========="
    while true; do
        get_valid_hostname "Nhập Hostname (VD: printer_01): " host_name
        if grep -q "^[[:space:]]*host $host_name {" "$conf_file"; then echo "-> [LỖI] Hostname đã tồn tại!"; else break; fi
    done

    while true; do
        read -p "Nhập địa chỉ MAC: " mac_addr
        if ! echo "$mac_addr" | grep -Eq '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'; then echo "-> [LỖI] Định dạng MAC sai!"; continue; fi
        mac_addr=$(echo "$mac_addr" | sed 's/-/:/g' | tr '[:upper:]' '[:lower:]')
        if grep -iq "hardware ethernet $mac_addr;" "$conf_file"; then echo "-> [LỖI] Địa chỉ MAC đã được sử dụng!"; else break; fi
    done

    while true; do
        read -p "Nhập IP tĩnh cần gán: " static_ip
        if ! is_valid_ip "$static_ip"; then echo "-> [LỖI] IP sai định dạng!"; continue; fi
        if grep -q "fixed-address $static_ip;" "$conf_file"; then echo "-> [LỖI] IP đã được cấu hình tĩnh!"; continue; fi
        break
    done

    cat >> "$conf_file" <<EOF

host $host_name {
    hardware ethernet $mac_addr;
    fixed-address $static_ip;
}
EOF
    echo "-> [THÀNH CÔNG] Đã gán $static_ip cho thiết bị mang MAC $mac_addr."
}

# ==========================================
# LUỒNG 5: XÓA HOST
# ==========================================
delete_host() {
    echo ""
    echo -e "\e[1;36m========== \e[1;33m[5] THU HỒI IP TĨNH\e[1;36m ==========\e[0m"
    read -p "Nhập Hostname cần xóa: " host_name
    
    # 1. Kiểm tra xem Host có tồn tại không
    if ! grep -q "^[[:space:]]*host $host_name {" "$conf_file"; then 
        echo -e "-> \e[1;31m[LỖI] Hostname không tồn tại!\e[0m"
        return
    fi
    
    # 2. Trích xuất địa chỉ IP của Host này trước khi xóa
    ip_to_remove=$(awk "/^[[:space:]]*host $host_name \{/,/\}/" "$conf_file" | grep "fixed-address" | awk '{print $2}' | tr -d ';')
    
    # 3. Xóa cấu hình Host trong file dhcpd.conf
    sed -i "/^[[:space:]]*host $host_name {/,/}/d" "$conf_file"
    echo -e "-> \e[1;32m[THÀNH CÔNG] Đã gạch tên Host [$host_name] khỏi cấu hình.\e[0m"
    
    # 4. Tự động dọn dẹp riêng bộ nhớ đệm (Lease) của IP này
    if [ -n "$ip_to_remove" ] && [ -f "$leases_file" ]; then
        # BẮT BUỘC TẮT dịch vụ trước khi can thiệp sổ nợ để tránh RAM ghi đè ngược lại
        systemctl stop dhcpd 2>/dev/null
        
        # Dùng sed tìm đúng block "lease <IP> { ... }" và xóa sạch
        sed -i "/^lease $ip_to_remove {/,/}/d" "$leases_file"
        
        systemctl start dhcpd 2>/dev/null
        echo -e "-> \e[1;32m[THÀNH CÔNG] Đã xóa vĩnh viễn IP $ip_to_remove khỏi bộ nhớ đệm!\e[0m"
    else
        systemctl restart dhcpd 2>/dev/null
    fi
}

# ==========================================
# LUỒNG 6: XEM TỔNG HỢP CẤU HÌNH
# ==========================================
view_configurations() {
    echo ""
    echo "========== TỔNG QUAN CẤU HÌNH =========="
    
    echo ">> 1. DANH SÁCH SCOPE:"
    subnet_count=$(grep -c "^subnet " "$conf_file")
    if [ "$subnet_count" -gt 0 ]; then
        grep "^subnet " "$conf_file" | awk '{print "   - Subnet: " $2 " / Netmask: " $4}'
    else echo "   (Trống)"; fi
    
    echo ""
    echo ">> 2. DANH SÁCH HOST:"
    host_count=$(grep -c "^[[:space:]]*host " "$conf_file")
    if [ "$host_count" -gt 0 ]; then
        grep "^[[:space:]]*host " "$conf_file" | awk '{print "   - Hostname: " $2}'
    else echo "   (Trống)"; fi
    
    echo "----------------------------------------"
    read -p "Hiển thị toàn bộ mã nguồn file cấu hình? (y/n): " show_all
    if [[ "$show_all" == "y" || "$show_all" == "Y" ]]; then
        echo ""
        cat "$conf_file"
    fi
}

# ==========================================
# LUỒNG 7: QUẢN LÝ DỊCH VỤ
# ==========================================
manage_service() {
    echo ""
    echo "========== [7] ĐIỀU PHỐI DỊCH VỤ =========="
    echo "1. Kiểm tra cú pháp (Syntax Check)"
    echo "2. Khởi động lại (Restart)"
    echo "3. Kiểm tra trạng thái (Status)"
    read -p "Lựa chọn: " svc_choice
    case $svc_choice in
        1) echo "--- BÁO CÁO CÚ PHÁP ---"; dhcpd -t -cf "$conf_file"; echo "-----------------------" ;;
        2) systemctl restart dhcpd; if [ $? -eq 0 ]; then echo "-> [THÀNH CÔNG] Dịch vụ đã được khởi động lại."; else echo "-> [LỖI] Khởi động thất bại. Hãy kiểm tra cấu hình hoặc IP card mạng!"; fi ;;
        3) systemctl status dhcpd -l ;;
        *) echo "-> [LỖI] Lựa chọn không hợp lệ." ;;
    esac
}

# ==========================================
# GIAO DIỆN CHÍNH
# ==========================================
while true; do
    echo ""
    echo " +========================================+"
    echo " |       BẢNG ĐIỀU KHIỂN DHCP SERVER      |"
    echo " +========================================+"
    echo " |                                        |"
    echo " |  [1] Khởi tạo Scope                    |"
    echo " |  [2] Cập nhật Scope                    |"
    echo " |  [3] Xóa Scope                         |"
    echo " |  [4] Khởi tạo Host                     |"
    echo " |  [5] Xóa Host                          |"
    echo " |  [6] Xem cấu hình hiện hành            |"
    echo " |  [7] Quản lý dịch vụ DHCP              |"
    echo " |  [8] Thoát                             |"
    echo " |                                        |"
    echo " +========================================+"
    read -p ">> Chọn chức năng (1-8): " main_choice
    
    case $main_choice in
        1) create_scope ;;
        2) update_scope ;;
        3) delete_scope ;;
        4) create_host ;;
        5) delete_host ;;
        6) view_configurations ;;
        7) manage_service ;;
        8) echo "-> [HỆ THỐNG] Đã thoát chương trình."; exit 0 ;;
        *) echo "-> [LỖI] Vui lòng chọn từ 1 đến 8." ;;
    esac
done
